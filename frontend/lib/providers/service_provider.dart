import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';

class ServiceProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<dynamic> _services = [];
  Map<String, dynamic>? _selected;
  bool _loading = false;

  List<dynamic> get services => _services;
  Map<String, dynamic>? get selected => _selected;
  bool get loading => _loading;

  Future<void> fetchServices({int? departmentId}) async {
    _loading = true;
    notifyListeners();
    try {
      final q = departmentId != null ? '?departmentId=$departmentId' : '';
      final res = await _api.get('/services$q');
      if (res.statusCode == 200) {
        _services = jsonDecode(res.body);
      } else {
        debugPrint('fetchServices failed: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('fetchServices error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  /// Fetch services visible to the current user (dept + specialization filter)
  Future<void> fetchMyServices() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/services/my');
      if (res.statusCode == 200) {
        _services = jsonDecode(res.body);
      } else {
        debugPrint('fetchMyServices failed: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('fetchMyServices error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchService(int id) async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/services/$id');
      if (res.statusCode == 200) _selected = jsonDecode(res.body);
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  /// Creates a service and returns its ID on success, or an error string.
  Future<Object?> create(Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/services', body: data);
      if (res.statusCode == 201) {
        final created = jsonDecode(res.body);
        await fetchServices();
        // Return the new service's ID so callers can do follow-up work.
        return created['id'] as int;
      }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> update(int id, Map<String, dynamic> data) async {
    try {
      final res = await _api.patch('/services/$id', body: data);
      if (res.statusCode == 200) { await fetchServices(); return null; }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> deleteService(int id) async {
    try {
      final res = await _api.delete('/services/$id');
      if (res.statusCode == 204) { await fetchServices(); return null; }
      return 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> enrollUser(int serviceId, int userId, {String status = 'requested'}) async {
    try {
      final res = await _api.post('/services/$serviceId/enroll', body: {'userId': userId, 'status': status});
      if (res.statusCode == 201) return null;
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  /// Convenience: current user requests to join a service
  Future<String?> enrollSelf(int serviceId, int userId) async {
    final err = await enrollUser(serviceId, userId, status: 'requested');
    if (err == null) await fetchMyServices();
    return err;
  }

  /// Current user withdraws a pending enrollment request
  Future<String?> unenrollSelf(int serviceId) async {
    try {
      final res = await _api.delete('/services/$serviceId/unenroll');
      if (res.statusCode == 204) { await fetchMyServices(); return null; }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> updateUserStatus(int serviceId, int userId, String status) async {
    try {
      final res = await _api.patch('/services/$serviceId/users/$userId/status', body: {'status': status});
      if (res.statusCode == 200) return null;
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> removeUser(int serviceId, int userId) async {
    try {
      final res = await _api.delete('/services/$serviceId/users/$userId');
      if (res.statusCode == 204) return null;
      return 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  /// Set or clear the responsible user for a service.
  /// Pass null for userId to clear the assignment.
  Future<String?> setResponsibleUser(int serviceId, int? userId) async {
    try {
      final res = await _api.patch(
        '/services/$serviceId/responsible',
        body: {'responsibleUserId': userId},
      );
      if (res.statusCode == 200) return null;
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }
}
