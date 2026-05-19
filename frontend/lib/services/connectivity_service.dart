import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _jsWindow;

class ConnectivityService {
  static final StreamController<bool> _ctrl =
      StreamController<bool>.broadcast();

  static bool _initialized = false;

  static Stream<bool> get onConnectivityChanged => _ctrl.stream;

  static bool get isOnline {
    final nav = _jsWindow.getProperty<JSObject?>('navigator'.toJS);
    if (nav == null) return true;
    return nav.getProperty<JSBoolean?>('onLine'.toJS)?.toDart ?? true;
  }

  static void init() {
    if (_initialized) return;
    _initialized = true;
    _jsWindow.callMethod(
      'addEventListener'.toJS,
      'online'.toJS,
      ((JSObject _) { _ctrl.add(true); }).toJS,
    );
    _jsWindow.callMethod(
      'addEventListener'.toJS,
      'offline'.toJS,
      ((JSObject _) { _ctrl.add(false); }).toJS,
    );
  }
}
