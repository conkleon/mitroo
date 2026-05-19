import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/connectivity_service.dart';

class ConnectivityProvider extends ChangeNotifier {
  bool _isOnline;
  StreamSubscription<bool>? _sub;

  ConnectivityProvider()
      : _isOnline = kIsWeb ? ConnectivityService.isOnline : true {
    if (kIsWeb) {
      ConnectivityService.init();
      _sub = ConnectivityService.onConnectivityChanged.listen((online) {
        _isOnline = online;
        notifyListeners();
      });
    }
  }

  bool get isOnline => _isOnline;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
