import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';

class VictimProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<Map<String, dynamic>> _victims = [];
  Map<String, dynamic>? _selected;
  bool _loading = false;

  List<Map<String, dynamic>> get victims => _victims;
  Map<String, dynamic>? get selected => _selected;
  bool get loading => _loading;

  Future<void> fetchVictims({int? serviceId}) async {
    _loading = true;
    notifyListeners();
    try {
      final q = serviceId != null ? '?serviceId=$serviceId' : '';
      final res = await _api.get('/victims$q');
      if (res.statusCode == 200) {
        _victims = (jsonDecode(res.body) as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
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
