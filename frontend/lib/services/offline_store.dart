import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OfflineStore {
  static const _outboxKey = 'offline_victim_outbox';

  static Future<void> saveVictimReport(
      Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_outboxKey);
    final list = raw != null
        ? (jsonDecode(raw) as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    list.add(payload);
    await prefs.setString(_outboxKey, jsonEncode(list));
  }

  static Future<List<Map<String, dynamic>>>
      getPendingVictimReports() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_outboxKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> setPendingVictimReports(
      List<Map<String, dynamic>> reports) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_outboxKey, jsonEncode(reports));
  }
}
