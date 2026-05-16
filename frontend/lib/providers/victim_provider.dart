import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';

class VictimProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<Map<String, dynamic>> _victims = [];
  Map<String, dynamic>? _selected;
  bool _loading = false;
  int _total = 0;
  int _currentPage = 1;
  int _limit = 20;

  List<Map<String, dynamic>> get victims => _victims;
  Map<String, dynamic>? get selected => _selected;
  bool get loading => _loading;
  int get total => _total;
  int get currentPage => _currentPage;
  int get limit => _limit;
  int get totalPages => _total == 0 ? 0 : (_total / _limit).ceil();

  Future<void> fetchVictims({
    int? serviceId,
    String? search,
    String? dateFrom,
    String? dateTo,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    _loading = true;
    notifyListeners();
    try {
      final params = <String, String>{};
      if (serviceId != null) params['serviceId'] = serviceId.toString();
      if (search != null && search.trim().isNotEmpty) params['search'] = search.trim();
      if (dateFrom != null && dateFrom.isNotEmpty) params['dateFrom'] = dateFrom;
      if (dateTo != null && dateTo.isNotEmpty) params['dateTo'] = dateTo;
      if (status != null && status != 'all') params['status'] = status;
      params['page'] = page.toString();
      params['limit'] = limit.toString();

      final qs = params.entries.map((e) =>
        '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
      final res = await _api.get('/victims?$qs');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        _victims = (body['data'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
        _total = body['total'] as int;
        _currentPage = body['page'] as int;
        _limit = body['limit'] as int;
      } else {
        debugPrint('fetchVictims failed: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('fetchVictims error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchVictim(int id) async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/victims/$id');
      if (res.statusCode == 200) {
        _selected = jsonDecode(res.body);
      }
    } catch (e) {
      debugPrint('fetchVictim error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<String?> createVictim(Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/victims', body: data);
      if (res.statusCode == 201) {
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> updateVictim(int id, Map<String, dynamic> data) async {
    try {
      final res = await _api.patch('/victims/$id', body: data);
      if (res.statusCode == 200) {
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> deleteVictim(int id) async {
    try {
      final res = await _api.delete('/victims/$id');
      if (res.statusCode == 204) {
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> finalizeVictim(int id) async {
    try {
      final res = await _api.post('/victims/$id/finalize');
      if (res.statusCode == 200) {
        await fetchVictim(id);
        await fetchVictims();
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> addVitalSign(int victimId, Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/victims/$victimId/vital-signs', body: data);
      if (res.statusCode == 201) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> deleteVitalSign(int victimId, int vsId) async {
    try {
      final res = await _api.delete('/victims/$victimId/vital-signs/$vsId');
      if (res.statusCode == 204) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> addTreatment(int victimId, Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/victims/$victimId/treatments', body: data);
      if (res.statusCode == 201) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }

  Future<String?> deleteTreatment(int victimId, int tId) async {
    try {
      final res = await _api.delete('/victims/$victimId/treatments/$tId');
      if (res.statusCode == 204) {
        await fetchVictim(victimId);
        return null;
      }
      return jsonDecode(res.body)['error'] ?? 'Αποτυχία';
    } catch (e) {
      return 'Σφάλμα: $e';
    }
  }
}
