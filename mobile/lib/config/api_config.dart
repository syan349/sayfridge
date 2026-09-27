import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // Web can use a same-origin API; native development uses the Android emulator.
    // Render hosts only static files, so set the HTTPS backend URL there to enable APIs.
    defaultValue: kIsWeb ? '/api/v1' : 'http://10.0.2.2:8000/api/v1',
  );

  static const Duration requestTimeout = Duration(seconds: 15);

  static Uri buildUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final normalizedBase = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$normalizedBase$normalizedPath');
    return kIsWeb ? Uri.base.resolveUri(uri) : uri;
  }
}
