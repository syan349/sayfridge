import 'dart:js_interop';

@JS('window.sayFridgeSetVoiceOverlayVisible')
external JSFunction? get _setVoiceOverlayVisible;

void setVoiceOverlayVisible(bool visible) {
  _setVoiceOverlayVisible?.callAsFunction(null, visible.toJS);
}
