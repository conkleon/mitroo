import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';

class CategoryProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<Map<String, dynamic>> _categories = [];
  bool _loading = false;

  List<Map<String, dynamic>> get categories => _categories;
  bool get loading => _loading;

  Future<void> fetchCategories({int? departmentId}) async {
    _loading = true;
    notifyListeners();
    try {
      final q = departmentId != null ? '?departmentId=$departmentId' : '';
      final res = await _api.get('/item-categories$q');
      if (res.statusCode == 200) {
        _categories = (jsonDecode(res.body) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<String?> create(String name, int departmentId) async {
    try {
      final res = await _api.post('/item-categories', body: {'name': name, 'departmentId': departmentId});
      if (res.statusCode == 201) {
        await fetchCategories();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String?> update(int id, String name) async {
    try {
      final res = await _api.patch('/item-categories/$id', body: {'name': name});
      if (res.statusCode == 200) {
        await fetchCategories();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Failed';
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String?> deleteCategory(int id) async {
    try {
      final res = await _api.delete('/item-categories/$id');
      if (res.statusCode == 204) {
        await fetchCategories();
        return null;
      }
      return 'Failed';
    } catch (e) {
      return 'Error: $e';
    }
  }
}
