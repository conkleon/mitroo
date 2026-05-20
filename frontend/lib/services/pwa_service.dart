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
  static bool _pushSubscribed = false;

  /// Called early (before login) to set up message listener and install state.
  /// Does NOT request notification permission — that waits until after login.
  static Future<void> init(PwaProvider provider) async {
    if (!kIsWeb) return;
    _provider = provider;
    await _checkInstallState();
    _listenForSwMessages();
  }

  /// Call after the user has logged in to request notification permission
  /// and register for push. Safe to call multiple times — subsequent calls
  /// are no-ops.
  static Future<void> subscribeForPush() async {
    if (!kIsWeb) return;
    if (_pushSubscribed) return;
    _pushSubscribed = true;
    try {
      await _subscribeAndRegister();
    } catch (e) {
      _pushSubscribed = false; // allow retry next time
      debugPrint('[pwa] push subscription threw: $e');
    }
  }

  /// True when the browser has a deferred install prompt ready.
  static bool canInstall() {
    if (!kIsWeb) return false;
    return _jsWindow.getProperty<JSAny?>('_installPrompt'.toJS) != null;
  }

  /// Force-update the service worker and reload.
  /// Returns false when no update is available (already up-to-date).
  /// When true is returned the page will reload automatically via JS.
  static Future<bool> forceUpdate() async {
    if (!kIsWeb) return false;
    try {
      final result = await _jsWindow
          .callMethod<JSPromise>('_checkAndUpdate'.toJS)
          .toDart;
      if (result == null) return false;
      return (result as JSBoolean).toDart;
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

    // 2. Get the SW registration — must use navigator.serviceWorker.ready so we
    // only proceed once the SW is in activated state. window._swReg is set by
    // index.html after register() resolves, but register() resolves before the
    // SW activates, so using it directly causes "no active Service Worker".
    final ready = sw.getProperty<JSPromise>('ready'.toJS);
    final JSObject reg = await ready.toDart as JSObject;

    // 3. Subscribe via PushManager — unsubscribe any stale subscription first
    final pushManager = reg.getProperty<JSObject?>('pushManager'.toJS);
    if (pushManager == null) {
      debugPrint('[pwa] pushManager not available on SW registration');
      return;
    }

    // Check for and remove any existing subscription (could be stale)
    final existingSub = await pushManager
        .callMethod<JSPromise>('getSubscription'.toJS)
        .toDart as JSObject?;
    if (existingSub != null) {
      String? oldEndpoint;
      try {
        final oldJson = existingSub.callMethod('toJSON'.toJS) as JSObject?;
        oldEndpoint = oldJson
            ?.getProperty<JSString?>('endpoint'.toJS)
            ?.toDart;
      } catch (_) {}
      await existingSub.callMethod<JSPromise>('unsubscribe'.toJS).toDart;
      debugPrint('[pwa] unsubscribed stale push subscription: $oldEndpoint');
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

    // 5. POST subscription to backend (ensure token is loaded first)
    await ApiClient().loadToken();
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
