import 'dart:js_interop';

import 'package:flutter/widgets.dart';

@JS('window.sayFridgeReadSafeArea')
external JSFunction? get _readSafeArea;

EdgeInsets readCssSafeArea() {
  final reader = _readSafeArea;
  if (reader == null) return EdgeInsets.zero;
  final insets = (reader.callAsFunction()! as JSArray<JSNumber>).toDart;
  return EdgeInsets.fromLTRB(
    insets[3].toDartDouble,
    insets[0].toDartDouble,
    insets[1].toDartDouble,
    insets[2].toDartDouble,
  );
}
