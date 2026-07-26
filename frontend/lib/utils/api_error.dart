import 'dart:convert';
import 'package:http/http.dart' as http;

/// Extracts the `error` field from a JSON error response body, falling back
/// to [fallback] if the body isn't JSON or has no `error` field. Used to
/// surface backend messages (e.g. the original Mitroo error text) instead of
/// a generic failure string.
String extractApiError(http.Response res, String fallback) {
  try {
    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded['error'] is String) {
      return decoded['error'] as String;
    }
  } catch (_) {}
  return fallback;
}
