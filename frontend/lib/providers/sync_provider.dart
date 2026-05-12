import 'package:flutter/foundation.dart';
import '../services/sync_service.dart';

class SyncProvider extends ChangeNotifier {
  final _svc = SyncService();

  Map<String, dynamic>? _config;
  Map<String, dynamic>? _status;
  bool _isSavingConfig = false;
  bool _isSyncingUsers = false;
  bool _isSyncingServices = false;
  String? _error;

  Map<String, dynamic>? get config => _config;
  Map<String, dynamic>? get status => _status;
  bool get isSavingConfig => _isSavingConfig;
  bool get isSyncingUsers => _isSyncingUsers;
  bool get isSyncingServices => _isSyncingServices;
  String? get error => _error;

  Future<void> loadConfig(int deptId) async {
    _config = await _svc.getSyncConfig(deptId);
    notifyListeners();
  }

  Future<void> loadStatus(int deptId) async {
    _status = await _svc.getSyncStatus(deptId);
    notifyListeners();
  }

  Future<String?> saveConfig(
    int deptId, {
    required String username,
    required String password,
    required bool syncEnabled,
  }) async {
    _isSavingConfig = true;
    _error = null;
    notifyListeners();
    final err = await _svc.saveSyncConfig(
      deptId,
      username: username,
      password: password,
      syncEnabled: syncEnabled,
    );
    _isSavingConfig = false;
    if (err == null) await loadConfig(deptId);
    _error = err;
    notifyListeners();
    return err;
  }

  Future<Map<String, dynamic>?> syncUsers(int deptId) async {
    _isSyncingUsers = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _svc.triggerUserSync(deptId);
      await loadStatus(deptId);
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isSyncingUsers = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> syncServices(int deptId) async {
    _isSyncingServices = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _svc.triggerServiceSync(deptId);
      await loadStatus(deptId);
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isSyncingServices = false;
      notifyListeners();
    }
  }
}
