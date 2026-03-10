import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

/// Thin wrapper around [http] that injects auth headers and the base URL.
class ApiClient {
  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;
  ApiClient._();

  String? _token;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('jwt_token');
  }

  Future<void> setToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Future<http.Response> get(String path) =>
      http.get(_uri(path), headers: _headers);

  Future<http.Response> post(String path, {Object? body}) =>
      http.post(_uri(path), headers: _headers, body: body != null ? jsonEncode(body) : null);

  Future<http.Response> patch(String path, {Object? body}) =>
      http.patch(_uri(path), headers: _headers, body: body != null ? jsonEncode(body) : null);

  Future<http.Response> delete(String path) =>
      http.delete(_uri(path), headers: _headers);
}
