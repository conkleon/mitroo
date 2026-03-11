import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';

class VehicleProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<dynamic> _vehicles = [];
  Map<String, dynamic>? _selected;
  List<dynamic> _logs = [];
  bool _loading = false;

  List<dynamic> get vehicles => _vehicles;
  Map<String, dynamic>? get selected => _selected;
  List<dynamic> get logs => _logs;
  bool get loading => _loading;

  Future<void> fetchVehicles({int? departmentId}) async {
    _loading = true;
    notifyListeners();
    try {
      final q = departmentId != null ? '?departmentId=$departmentId' : '';
      final res = await _api.get('/vehicles$q');
      if (res.statusCode == 200) _vehicles = jsonDecode(res.body);
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchVehicle(int id) async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/vehicles/$id');
      if (res.statusCode == 200) _selected = jsonDecode(res.body);
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchLogs(int vehicleId) async {
    try {
      final res = await _api.get('/vehicles/$vehicleId/logs');
      if (res.statusCode == 200) {
        _logs = jsonDecode(res.body);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<String?> create(Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/vehicles', body: data);
      if (res.statusCode == 201) { await fetchVehicles(); return null; }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> update(int id, Map<String, dynamic> data) async {
    try {
      final res = await _api.patch('/vehicles/$id', body: data);
      if (res.statusCode == 200) { await fetchVehicles(); return null; }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> deleteVehicle(int id) async {
    try {
      final res = await _api.delete('/vehicles/$id');
      if (res.statusCode == 204) { await fetchVehicles(); return null; }
      return 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> addLog(int vehicleId, Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/vehicles/$vehicleId/logs', body: data);
      if (res.statusCode == 201) { await fetchLogs(vehicleId); return null; }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  // ── Self-service take / return ──────────────────

  List<dynamic> _availableVehicles = [];
  List<dynamic> _myActiveVehicles = [];

  List<dynamic> get availableVehicles => _availableVehicles;
  List<dynamic> get myActiveVehicles => _myActiveVehicles;

  Future<void> fetchAvailable([String search = '']) async {
    try {
      final q = search.isNotEmpty ? '?search=${Uri.encodeComponent(search)}' : '';
      final res = await _api.get('/vehicles/available/list$q');
      if (res.statusCode == 200) {
        _availableVehicles = jsonDecode(res.body);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> fetchMyActive() async {
    try {
      final res = await _api.get('/vehicles/my/active');
      if (res.statusCode == 200) {
        _myActiveVehicles = jsonDecode(res.body);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> takeVehicle(int vehicleId, num meterStart, {int? serviceId, String? destination, String? comment}) async {
    try {
      final body = <String, dynamic>{'meterStart': meterStart};
      if (serviceId != null) body['serviceId'] = serviceId;
      if (destination != null && destination.isNotEmpty) body['destination'] = destination;
      if (comment != null) body['comment'] = comment;
      final res = await _api.post('/vehicles/$vehicleId/take', body: body);
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {'error': jsonDecode(res.body)['error'] ?? 'Failed'};
    } catch (e) { return {'error': 'Error: $e'}; }
  }

  Future<Map<String, dynamic>?> returnVehicle(int vehicleId, num meterEnd, {String? destination, String? comment}) async {
    try {
      final body = <String, dynamic>{'meterEnd': meterEnd};
      if (destination != null && destination.isNotEmpty) body['destination'] = destination;
      if (comment != null) body['comment'] = comment;
      final res = await _api.post('/vehicles/$vehicleId/return', body: body);
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {'error': jsonDecode(res.body)['error'] ?? 'Failed'};
    } catch (e) { return {'error': 'Error: $e'}; }
  }

  // ── Comments ──────────────────────────────────

  List<dynamic> _comments = [];
  List<dynamic> get comments => _comments;

  Future<void> fetchComments(int vehicleId) async {
    try {
      final res = await _api.get('/vehicles/$vehicleId/comments');
      if (res.statusCode == 200) {
        _comments = jsonDecode(res.body);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<String?> addComment(int vehicleId, String text) async {
    try {
      final res = await _api.post('/vehicles/$vehicleId/comments', body: {'text': text});
      if (res.statusCode == 201) { await fetchComments(vehicleId); return null; }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> deleteComment(int vehicleId, int commentId) async {
    try {
      final res = await _api.delete('/vehicles/$vehicleId/comments/$commentId');
      if (res.statusCode == 204) { await fetchComments(vehicleId); return null; }
      return 'Failed';
    } catch (e) { return 'Error: $e'; }
  }
}
