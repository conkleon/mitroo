import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/pwa_provider.dart';
import 'api_client.dart';

@JS('window')
external JSObject get _jsWindow;

@JS('navigator.serviceWorker')
external JSObject? get _swContainer;

class PwaService {
  static final StreamController<String> _navigateCtrl =
      StreamController<String>.broadcast();

  static Stream<String> get navigateStream => _navigateCtrl.stream;

  static PwaProvider? _provider;

  /// Called once from main.dart after the first frame on web only.
  static Future<void> init(PwaProvider provider) async {
    if (!kIsWeb) return;
    _provider = provider;
    await _checkInstallState();
    _listenForSwMessages();
    try {
      await _subscribeAndRegister();
    } catch (e) {
      debugPrint('[pwa] push subscription threw: $e');
    }
  }

  /// True when the browser has a deferred install prompt ready.
  static bool canInstall() {
    if (!kIsWeb) return false;
    return _jsWindow.getProperty<JSAny?>('_installPrompt'.toJS) != null;
  }

  /// Force-update the service worker and reload.
  /// Returns false when no update is waiting (already up-to-date).
  static Future<bool> forceUpdate() async {
    if (!kIsWeb) return false;
    try {
      final sw = _swContainer;
      if (sw == null) return false;

      // First check the cached sw registration from index.html
      final cached = _jsWindow.getProperty<JSObject?>('_swReg'.toJS);
      JSObject? reg;
      if (cached != null) {
        reg = cached;
      } else {
        final ready = sw.getProperty<JSPromise>('ready'.toJS);
        reg = await ready.toDart as JSObject?;
      }
      if (reg == null) return false;

      final waiting = reg.getProperty<JSObject?>('waiting'.toJS);
      if (waiting == null) {
        // Try to update — this finds a new version if one exists
        await reg.callMethod<JSPromise>('update'.toJS).toDart;
        // wait a tick for the new worker to reach 'waiting' state
        await Future.delayed(const Duration(milliseconds: 300));
        final waiting2 = reg.getProperty<JSObject?>('waiting'.toJS);
        if (waiting2 == null) return false;
        waiting2.callMethod('postMessage'.toJS, 'skipWaiting'.toJS);
      } else {
        waiting.callMethod('postMessage'.toJS, 'skipWaiting'.toJS);
      }

      // Reload after the new SW activates
      await Future.delayed(const Duration(milliseconds: 200));
      _jsWindow.getProperty<JSObject?>('location'.toJS)
          ?.callMethod('reload'.toJS);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Triggers the native install prompt. Returns true if the user accepted.
  static Future<bool> triggerInstall() async {
    if (!kIsWeb) return false;
    final prompt = _jsWindow.getProperty<JSObject?>('_installPrompt'.toJS);
    if (prompt == null) return false;
    try {
      final result =
          await prompt.callMethod<JSPromise>('prompt'.toJS).toDart as JSObject;
      final outcome =
          result.getProperty<JSString?>('outcome'.toJS)?.toDart;
      return outcome == 'accepted';
    } catch (_) {
      return false;
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  static Future<void> _checkInstallState() async {
    // Check if the install prompt fired before Dart booted
    if (_jsWindow.getProperty<JSAny?>('_installPrompt'.toJS) != null) {
      _provider?.setInstallAvailable(true);
    }
    // Check if already installed (e.g. user installed in a previous session)
    final appInstalled =
        _jsWindow.getProperty<JSBoolean?>('_appInstalled'.toJS);
    if (appInstalled?.toDart == true) {
      _provider?.setInstalled(true);
    }
    // Restore persisted "dialog shown" flag without writing it again
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('pwa_install_shown') ?? false) {
      _provider?.restoreInstallDialogShown();
    }
  }

  static void _listenForSwMessages() {
    final sw = _swContainer;
    if (sw == null) return;
    sw.callMethod(
      'addEventListener'.toJS,
      'message'.toJS,
      ((JSObject event) {
        final data = event.getProperty<JSObject?>('data'.toJS);
        if (data == null) return;
        final type = data.getProperty<JSString?>('type'.toJS)?.toDart;
        if (type == 'navigate') {
          final route = data.getProperty<JSString?>('route'.toJS)?.toDart;
          if (route != null) _navigateCtrl.add(route);
        }
      }).toJS,
    );
  }

  static Future<void> _subscribeAndRegister() async {
    final sw = _swContainer;
    if (sw == null) {
      debugPrint('[pwa] serviceWorker container not available');
      return;
    }

    // 1. Fetch VAPID public key from backend
    final keyRes = await ApiClient().get('/push/vapid-public-key');
    if (keyRes.statusCode != 200) {
      debugPrint('[pwa] VAPID key fetch failed: ${keyRes.statusCode}');
      return;
    }
    final vapidPublicKey =
        (jsonDecode(keyRes.body) as Map<String, dynamic>)['publicKey']
            as String?;
    if (vapidPublicKey == null) {
      debugPrint('[pwa] VAPID public key missing in response');
      return;
    }

    // 2. Get the SW registration (set by index.html on load)
    JSObject reg;
    final cached = _jsWindow.getProperty<JSObject?>('_swReg'.toJS);
    if (cached != null) {
      reg = cached;
    } else {
      final ready = sw.getProperty<JSPromise>('ready'.toJS);
      reg = await ready.toDart as JSObject;
    }

    // 3. Subscribe via PushManager
    final pushManager = reg.getProperty<JSObject?>('pushManager'.toJS);
    if (pushManager == null) {
      debugPrint('[pwa] pushManager not available on SW registration');
      return;
    }

    final options = JSObject();
    options.setProperty('userVisibleOnly'.toJS, true.toJS);
    options.setProperty(
        'applicationServerKey'.toJS, _urlBase64ToUint8Array(vapidPublicKey));

    final sub = await pushManager
        .callMethod<JSPromise>('subscribe'.toJS, options)
        .toDart as JSObject;

    // 4. Extract endpoint + keys via toJSON()
    final subJson =
        sub.callMethod('toJSON'.toJS) as JSObject;
    final endpoint =
        subJson.getProperty<JSString?>('endpoint'.toJS)?.toDart;
    if (endpoint == null) {
      debugPrint('[pwa] push subscription endpoint missing');
      return;
    }
    final keys = subJson.getProperty<JSObject?>('keys'.toJS);
    if (keys == null) {
      debugPrint('[pwa] push subscription keys missing');
      return;
    }
    final p256dh = keys.getProperty<JSString?>('p256dh'.toJS)?.toDart;
    final auth = keys.getProperty<JSString?>('auth'.toJS)?.toDart;
    if (p256dh == null || auth == null) {
      debugPrint('[pwa] push subscription key fields missing');
      return;
    }

    // 5. POST subscription to backend
    final subRes = await ApiClient().post('/push/subscribe', body: {
      'endpoint': endpoint,
      'p256dhKey': p256dh,
      'authKey': auth,
    });
    debugPrint('[pwa] push subscription registered: ${subRes.statusCode}');
  }

  static JSUint8Array _urlBase64ToUint8Array(String base64String) {
    final padding = '=' * ((4 - base64String.length % 4) % 4);
    final padded = (base64String + padding)
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    return base64Decode(padded).toJS;
  }
}
