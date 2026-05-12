import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'api_client.dart';

class PushService {
  static final _api = ApiClient();

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
    final keyRes = await _api.get('/push/vapid-public-key');
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
    final subJson = await completer.future;
    if (subJson == null) return;

    // 3. POST subscription to backend
    final sub = jsonDecode(subJson) as Map<String, dynamic>;
    await _api.post('/push/subscribe', body: {
      'endpoint': sub['endpoint'],
      'p256dhKey': sub['p256dhKey'],
      'authKey': sub['authKey'],
    });
  }
}
