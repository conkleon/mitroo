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
}
