import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'preview/preview_app.dart';

/// Separate, opt-in entry point. The production entry point never imports it.
void main() {
  if (!kDebugMode) {
    throw UnsupportedError('UI preview is available only in debug builds.');
  }
  runApp(const PreviewApp());
}
