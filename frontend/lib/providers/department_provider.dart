import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';

class DepartmentProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<dynamic> _departments = [];
  Map<String, dynamic>? _selected;
  List<dynamic> _members = [];
  bool _loading = false;

  List<dynamic> get departments => _departments;
  Map<String, dynamic>? get selected => _selected;
  List<dynamic> get members => _members;
  bool get loading => _loading;

  Future<void> fetchDepartments() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/departments');
      if (res.statusCode == 200) _departments = jsonDecode(res.body);
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchDepartment(int id) async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/departments/$id');
      if (res.statusCode == 200) _selected = jsonDecode(res.body);
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchMembers(int departmentId) async {
    try {
      final res = await _api.get('/departments/$departmentId/members');
      if (res.statusCode == 200) {
        _members = jsonDecode(res.body);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<String?> create(Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/departments', body: data);
      if (res.statusCode == 201) { await fetchDepartments(); return null; }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> update(int id, Map<String, dynamic> data) async {
    try {
      final res = await _api.patch('/departments/$id', body: data);
      if (res.statusCode == 200) { await fetchDepartments(); return null; }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> deleteDepartment(int id) async {
    try {
      final res = await _api.delete('/departments/$id');
      if (res.statusCode == 204) { await fetchDepartments(); return null; }
      return 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> addMember(int departmentId, int userId, String role) async {
    try {
      final res = await _api.post('/departments/$departmentId/members', body: {'userId': userId, 'role': role});
      if (res.statusCode == 201) { await fetchMembers(departmentId); return null; }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> removeMember(int departmentId, int userId) async {
    try {
      final res = await _api.delete('/departments/$departmentId/members/$userId');
      if (res.statusCode == 204) { await fetchMembers(departmentId); return null; }
      return 'Failed';
    } catch (e) { return 'Error: $e'; }
  }
}
