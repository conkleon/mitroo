import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';

class ItemProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<dynamic> _items = [];
  Map<String, dynamic>? _selected;
  bool _loading = false;

  List<dynamic> get items => _items;
  Map<String, dynamic>? get selected => _selected;
  bool get loading => _loading;

  // ── Fetch all items (with optional filters) ──

  Future<void> fetchItems({int? containerId, String? search, bool? available}) async {
    _loading = true;
    notifyListeners();
    try {
      final params = <String>[];
      if (containerId != null) params.add('containerId=$containerId');
      if (search != null && search.isNotEmpty) params.add('search=$search');
      if (available == true) params.add('available=true');
      final q = params.isNotEmpty ? '?${params.join('&')}' : '';
      final res = await _api.get('/items$q');
      if (res.statusCode == 200) _items = jsonDecode(res.body);
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  // ── Fetch single item by ID ──

  Future<void> fetchItem(int id) async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/items/$id');
      if (res.statusCode == 200) _selected = jsonDecode(res.body);
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  // ── Fetch items matching a barcode (after scanning) ──

  Future<List<dynamic>> fetchByBarcode(String barCode) async {
    try {
      final res = await _api.get('/items/barcode/${Uri.encodeComponent(barCode)}');
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return [];
  }

  // ── CRUD ──

  Future<String?> create(Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/items', body: data);
      if (res.statusCode == 201) { await fetchItems(); return null; }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> update(int id, Map<String, dynamic> data) async {
    try {
      final res = await _api.patch('/items/$id', body: data);
      if (res.statusCode == 200) {
        _selected = jsonDecode(res.body);
        notifyListeners();
        await fetchItems();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> deleteItem(int id) async {
    try {
      final res = await _api.delete('/items/$id');
      if (res.statusCode == 204) { await fetchItems(); return null; }
      return 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  // ── Self-assign / unassign (regular users) ──

  Future<String?> selfAssign(int itemId) async {
    try {
      final res = await _api.post('/items/$itemId/self-assign', body: {});
      if (res.statusCode == 200) {
        _selected = jsonDecode(res.body);
        notifyListeners();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> selfUnassign(int itemId) async {
    try {
      final res = await _api.post('/items/$itemId/self-unassign', body: {});
      if (res.statusCode == 200) {
        _selected = jsonDecode(res.body);
        notifyListeners();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  // ── Assign / unassign item to a user ──

  Future<String?> assignToUser(int itemId, int userId) async {
    try {
      final res = await _api.post('/items/$itemId/assign-user', body: {'userId': userId});
      if (res.statusCode == 200) {
        _selected = jsonDecode(res.body);
        notifyListeners();
        await fetchItems();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String?> unassignUser(int itemId) async {
    try {
      final res = await _api.delete('/items/$itemId/assign-user');
      if (res.statusCode == 200) {
        _selected = jsonDecode(res.body);
        notifyListeners();
        await fetchItems();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  // ── Move item into / out of a container ──

  Future<String?> moveToContainer(int itemId, int? containerId) async {
    try {
      final res = await _api.patch('/items/$itemId/move', body: {'containerId': containerId});
      if (res.statusCode == 200) {
        _selected = jsonDecode(res.body);
        notifyListeners();
        await fetchItems();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }

  // ── Item–Service assignment ──

  Future<String?> assignToService(int serviceId, int userId, int itemId, {String? comment}) async {
    try {
      final body = <String, dynamic>{'serviceId': serviceId, 'userId': userId, 'itemId': itemId};
      if (comment != null) body['comment'] = comment;
      final res = await _api.post('/items/assign', body: body);
      if (res.statusCode == 201) return null;
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) { return 'Error: $e'; }
  }
}
