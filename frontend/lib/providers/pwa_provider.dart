import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pwa_service.dart';

class PwaProvider extends ChangeNotifier {
  bool _installAvailable = false;
  bool _installed = false;
  bool _installDialogShown = false;

  bool get installAvailable => _installAvailable;
  bool get installed => _installed;

  /// True when the install dialog should be shown: prompt available, not yet
  /// installed, and not already shown this device lifetime.
  bool get shouldShowInstallDialog =>
      _installAvailable && !_installed && !_installDialogShown;

  void setInstallAvailable(bool value) {
    _installAvailable = value;
    notifyListeners();
  }

  void setInstalled(bool value) {
    _installed = value;
    _installAvailable = false;
    notifyListeners();
  }

  /// Call before showing the install dialog. Prevents re-showing and persists
  /// the flag so it survives app restarts.
  /// Called by the UI before showing the dialog. Persists the flag so it
  /// survives app restarts.
  void markInstallDialogShown() {
    _setInstallDialogShown(persist: true);
  }

  /// Called by PwaService on init to restore the persisted flag without
  /// writing to SharedPreferences again.
  void restoreInstallDialogShown() {
    _setInstallDialogShown(persist: false);
  }

  void _setInstallDialogShown({required bool persist}) {
    _installDialogShown = true;
    notifyListeners();
    if (persist) {
      SharedPreferences.getInstance()
          .then((p) => p.setBool('pwa_install_shown', true));
    }
  }

  Future<bool> triggerInstall() async {
    final accepted = await PwaService.triggerInstall();
    if (accepted) setInstalled(true);
    return accepted;
  }
}
