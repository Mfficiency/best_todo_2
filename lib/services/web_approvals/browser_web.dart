// @dart=3.3
// (Newer than the package's 3.0 default: extension types for JS interop.)
import 'dart:js_interop';

@JS('window')
external _Window get _window;

extension type _Window._(JSObject _) implements JSObject {
  external _Location get location;
  external JSObject get top;
  external JSObject get self;
  external void addEventListener(String type, JSFunction listener);
}

extension type _Location._(JSObject _) implements JSObject {
  external void reload();
}

extension type _Event._(JSObject _) implements JSObject {
  external void preventDefault();
}

void reloadPage() => _window.location.reload();

bool isFramed() {
  try {
    return !_window.top.strictEquals(_window.self).toDart;
  } catch (_) {
    // A cross-origin parent can't even be compared: framed.
    return true;
  }
}

bool _warn = false;
bool _listening = false;

void setLeaveWarning(bool on) {
  _warn = on;
  if (_listening) return;
  _listening = true;
  _window.addEventListener(
    'beforeunload',
    ((_Event event) {
      if (_warn) event.preventDefault();
    }).toJS,
  );
}
