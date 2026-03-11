import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';

class AuthProvider extends ChangeNotifier {
  final _api = ApiClient();

  Map<String, dynamic>? _user;
  bool _loading = false;

  Map<String, dynamic>? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get loading => _loading;
  bool get isAdmin => _user?['isAdmin'] == true;
  String get displayName => '${_user?['forename'] ?? ''} ${_user?['surname'] ?? ''}'.trim();

  /// True when the user is a global admin OR has missionAdmin / itemAdmin role in any department.
  bool get canAccessAdminPanel {
    if (isAdmin) return true;
    final depts = _user?['departments'] as List<dynamic>?;
    if (depts == null) return false;
    return depts.any((d) => d['role'] == 'missionAdmin' || d['role'] == 'itemAdmin');
  }

  /// True when user is missionAdmin in at least one department (or global admin).
  bool get isMissionAdmin {
    if (isAdmin) return true;
    final depts = _user?['departments'] as List<dynamic>?;
    if (depts == null) return false;
    return depts.any((d) => d['role'] == 'missionAdmin');
  }

  /// True when user is itemAdmin (or missionAdmin) in at least one department (or global admin).
  bool get isItemAdmin {
    if (isAdmin) return true;
    final depts = _user?['departments'] as List<dynamic>?;
    if (depts == null) return false;
    return depts.any((d) => d['role'] == 'itemAdmin' || d['role'] == 'missionAdmin');
  }

  /// Departments where the user is missionAdmin.
  List<Map<String, dynamic>> get missionAdminDepartments {
    final depts = _user?['departments'] as List<dynamic>?;
    if (depts == null) return [];
    return depts
        .where((d) => d['role'] == 'missionAdmin')
        .map((d) => Map<String, dynamic>.from(d['department'] as Map))
        .toList();
  }

  /// Departments where the user is itemAdmin (or missionAdmin, since missionAdmin inherits itemAdmin).
  List<Map<String, dynamic>> get itemAdminDepartments {
    final depts = _user?['departments'] as List<dynamic>?;
    if (depts == null) return [];
    return depts
        .where((d) => d['role'] == 'itemAdmin' || d['role'] == 'missionAdmin')
        .map((d) => Map<String, dynamic>.from(d['department'] as Map))
        .toList();
  }

  /// The user's specializations from /auth/me
  List<dynamic> get specializations {
    final specs = _user?['specializations'] as List<dynamic>?;
    if (specs == null) return [];
    return specs.map((us) => us['specialization']).whereType<Map<String, dynamic>>().toList();
  }

  AuthProvider() {
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    _loading = true;
    notifyListeners();
    try {
      await _api.loadToken();
      final res = await _api.get('/auth/me');
      if (res.statusCode == 200) {
        _user = jsonDecode(res.body);
      }
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<String?> login(String email, String password) async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.post('/auth/login', body: {
        'email': email,
        'password': password,
      });
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        await _api.setToken(data['token']);
        _user = data['user'];
        _loading = false;
        notifyListeners();
        return null;
      }
      _loading = false;
      notifyListeners();
      return data['error'] ?? 'Login failed';
    } catch (e) {
      _loading = false;
      notifyListeners();
      return 'Connection error: $e';
    }
  }

  Future<String?> register(String email, String password, String forename, String surname, String ename) async {
    _loading = true;
    notifyListeners();
    try {
      final body = <String, dynamic>{
        'email': email,
        'password': password,
        'forename': forename,
        'surname': surname,
        'ename': ename,
      };
      final res = await _api.post('/auth/register', body: body);
      final data = jsonDecode(res.body);
      if (res.statusCode == 201) {
        await _api.setToken(data['token']);
        _user = data['user'];
        _loading = false;
        notifyListeners();
        return null;
      }
      _loading = false;
      notifyListeners();
      return data['error'] ?? 'Registration failed';
    } catch (e) {
      _loading = false;
      notifyListeners();
      return 'Connection error: $e';
    }
  }

  Future<void> logout() async {
    await _api.clearToken();
    _user = null;
    notifyListeners();
  }
}
