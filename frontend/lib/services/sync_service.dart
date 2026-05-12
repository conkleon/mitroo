import 'dart:convert';
import '../services/api_client.dart';

class SyncService {
  final _api = ApiClient();

  Future<Map<String, dynamic>?> getSyncConfig(int deptId) async {
    final res = await _api.get('/departments/$deptId/sync/config');
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }

  Future<String?> saveSyncConfig(
    int deptId, {
    required String username,
    required String password,
    required bool syncEnabled,
  }) async {
    final res = await _api.post(
      '/departments/$deptId/sync/config',
      body: {'username': username, 'password': password, 'syncEnabled': syncEnabled},
    );
    if (res.statusCode == 200) return null;
    try {
      return (jsonDecode(res.body) as Map)['error']?.toString() ?? 'Αποτυχία αποθήκευσης';
    } catch (_) {
      return 'Αποτυχία αποθήκευσης (${res.statusCode})';
    }
  }

  Future<Map<String, dynamic>> triggerUserSync(int deptId) async {
    final res = await _api.post('/departments/$deptId/sync/users');
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Sync users failed: ${res.statusCode}');
  }

  Future<Map<String, dynamic>> triggerServiceSync(int deptId) async {
    final res = await _api.post('/departments/$deptId/sync/services');
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Sync services failed: ${res.statusCode}');
  }

  Future<Map<String, dynamic>?> getSyncStatus(int deptId) async {
    final res = await _api.get('/departments/$deptId/sync/status');
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }
}
