class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  final int statusCode;
  final String message;
  final String? code;

  bool get isUnauthorized => statusCode == 401;

  bool get isNotFound => statusCode == 404;

  bool get isConflict => statusCode == 409;

  bool get isValidationError => statusCode == 422;

  @override
  String toString() {
    final errorCode = code == null ? '' : ' [$code]';
    return 'ApiException ($statusCode)$errorCode: $message';
  }
}