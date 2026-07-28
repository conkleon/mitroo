import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';
import '../services/download_helper.dart';

class MissionReportProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<dynamic> _missions = [];
  bool _loadingMissions = false;
  bool _generating = false;
  Map<String, dynamic>? _structuredData;
  String? _narrativeText;
  String? _narrativeError;
  String? _reportError;

  /// Mission ids that produced [_structuredData]. Sent to the PDF endpoint so the
  /// server re-aggregates the report itself instead of trusting a client blob.
  List<int> _reportServiceIds = [];

  List<dynamic> get missions => _missions;
  bool get loadingMissions => _loadingMissions;
  bool get generating => _generating;
  Map<String, dynamic>? get structuredData => _structuredData;
  String? get narrativeText => _narrativeText;
  String? get narrativeError => _narrativeError;
  String? get reportError => _reportError;

  void setNarrativeText(String text) {
    _narrativeText = text;
    notifyListeners();
  }

  Future<void> fetchMissions({
    int? departmentId,
    String? from,
    String? to,
    String? search,
    int? limit,
  }) async {
    _loadingMissions = true;
    notifyListeners();
    try {
      final params = <String, String>{};
      if (departmentId != null) params['departmentId'] = departmentId.toString();
      if (from != null) params['from'] = from;
      if (to != null) params['to'] = to;
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (limit != null) params['limit'] = limit.toString();
      final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
      final res = await _api.get('/reports/missions$query');
      if (res.statusCode == 200) {
        _missions = jsonDecode(res.body);
      }
    } catch (_) {}
    _loadingMissions = false;
    notifyListeners();
  }

  Future<bool> generateReport(Map<String, dynamic> body) async {
    _generating = true;
    _reportError = null;
    notifyListeners();
    try {
      final res = await _api.post('/reports/generate', body: body);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        _structuredData = decoded['structuredData'] as Map<String, dynamic>;
        _reportServiceIds = ((_structuredData!['missions'] as List<dynamic>?) ?? [])
            .map((m) => (m as Map<String, dynamic>)['id'] as int)
            .toList();
        _narrativeText = decoded['narrativeDraft'] as String?;
        _narrativeError = decoded['narrativeError'] as String?;
        _generating = false;
        notifyListeners();
        return true;
      }
      _reportError = (jsonDecode(res.body) as Map<String, dynamic>)['error'] as String? ??
          'Η δημιουργία της αναφοράς απέτυχε';
    } catch (e) {
      _reportError = 'Σφάλμα: $e';
    }
    _generating = false;
    notifyListeners();
    return false;
  }

  Future<String?> exportPdf() async {
    if (_structuredData == null || _narrativeText == null || _reportServiceIds.isEmpty) {
      return 'Δεν υπάρχουν δεδομένα αναφοράς';
    }
    try {
      final res = await _api.post('/reports/pdf', body: {
        'serviceIds': _reportServiceIds,
        'narrativeText': _narrativeText,
      });
      if (res.statusCode == 200) {
        await downloadFile(res.bodyBytes, 'mission-report.pdf');
        return null;
      }
      return 'Η εξαγωγή PDF απέτυχε';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }
}
