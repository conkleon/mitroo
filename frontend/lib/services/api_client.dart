import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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

  /// Upload a file via multipart POST. [fileBytes] is the file content,
  /// [fileName] the original name, and [fieldName] the form field key.
  /// Resolve MIME type from file extension.
  static String _mimeFromName(String name) {
    final ext = name.split('.').last.toLowerCase();
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'avif': 'image/avif',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv': 'text/csv',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  Future<http.Response> uploadFile(
    String path, {
    required List<int> fileBytes,
    required String fileName,
    String fieldName = 'file',
  }) async {
    final request = http.MultipartRequest('POST', _uri(path));
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    final contentType = _mimeFromName(fileName);
    request.files.add(http.MultipartFile.fromBytes(
      fieldName,
      fileBytes,
      filename: fileName,
      contentType: MediaType.parse(contentType),
    ));
    final streamed = await request.send();
    return http.Response.fromStream(streamed);
  }

  /// The uploads base URL (server root without /api).
  static String get uploadsBaseUrl {
    final base = ApiConfig.baseUrl;
    // Strip trailing /api to get the server root
    if (base.endsWith('/api')) return base.substring(0, base.length - 4);
    return base;
  }
}
