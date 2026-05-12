import 'dart:async';
import 'dart:convert';
// TODO(push): migrate to dart:js_interop once project targets Dart 3.1+
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'api_client.dart';

class PushService {
  static Future<void> init() async {
    // Only supported on web
    try {
      await _subscribeAndRegister();
    } catch (_) {
      // Non-fatal: push is best-effort
    }
  }

  static Future<void> _subscribeAndRegister() async {
    // 1. Fetch VAPID public key from backend
    final keyRes = await ApiClient().get('/push/vapid-public-key');
    if (keyRes.statusCode != 200) return;
    final vapidPublicKey = (jsonDecode(keyRes.body) as Map<String, dynamic>)['publicKey'] as String?;
    if (vapidPublicKey == null) return;

    // 2. Call JS helper (defined in index.html) — uses a Completer to bridge the callback
    final completer = Completer<String?>();
    js.context.callMethod('mitrooSubscribePush', [
      vapidPublicKey,
      js.allowInterop((dynamic result) {
        completer.complete(result as String?);
      }),
    ]);
    final subJson = await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => null,
    );
    if (subJson == null) return;

    // 3. POST subscription to backend
    final sub = jsonDecode(subJson) as Map<String, dynamic>;
    await ApiClient().post('/push/subscribe', body: {
      'endpoint': sub['endpoint'],
      'p256dhKey': sub['p256dhKey'],
      'authKey': sub['authKey'],
    });
  }
}
