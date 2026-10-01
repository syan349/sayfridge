import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Future<String?> Function(String)? renewAccessToken;

  Future<http.Response> _authorized(
    String? token,
    Future<http.Response> Function(String?) request,
  ) async {
    try {
      return await _send(() => request(token));
    } on ApiException catch (error) {
      if (!error.isUnauthorized || token == null || renewAccessToken == null) {
        rethrow;
      }
      final replacement = await renewAccessToken!(token);
      if (replacement == null) rethrow;
      return _send(() => request(replacement));
    }
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    String? accessToken,
    Map<String, String>? queryParameters,
  }) async {
    final uri = ApiConfig.buildUri(
      path,
    ).replace(queryParameters: queryParameters);

    final response = await _authorized(
      accessToken,
      (token) => _client.get(uri, headers: _headers(accessToken: token)),
    );

    return _decodeSuccessfulResponse(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
    Map<String, String> headers = const {},
  }) async {
    final response = await _authorized(
      accessToken,
      (token) => _client.post(
        ApiConfig.buildUri(path),
        headers: {
          ..._headers(accessToken: token),
          ...headers,
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );

    return _decodeSuccessfulResponse(response);
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    required Map<String, dynamic> body,
    required String accessToken,
  }) async => _decodeSuccessfulResponse(
    await _authorized(
      accessToken,
      (token) => _client.patch(
        ApiConfig.buildUri(path),
        headers: _headers(accessToken: token),
        body: jsonEncode(body),
      ),
    ),
  );

  Future<List<Map<String, dynamic>>> getList(
    String path, {
    required String accessToken,
  }) async {
    final response = await _authorized(
      accessToken,
      (token) => _client.get(
        ApiConfig.buildUri(path),
        headers: _headers(accessToken: token),
      ),
    );
    final value = jsonDecode(response.body);
    if (value is! List) throw const FormatException('Expected a JSON list');
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  /// Decode complete SSE records, including multi-line data and split UTF-8.
  /// A disconnected stream is NOT an acknowledgement of a successful write.
  Stream<Map<String, dynamic>> events(
    String path, {
    required Map<String, dynamic> body,
    required String accessToken,
  }) async* {
    Future<http.StreamedResponse> open(String token) async {
      final request = http.Request('POST', ApiConfig.buildUri(path))
        ..headers.addAll({
          ..._headers(accessToken: token),
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(body);
      return _client.send(request).timeout(ApiConfig.requestTimeout);
    }

    var response = await open(accessToken);
    if (response.statusCode == 401 && renewAccessToken != null) {
      await response.stream.drain<void>();
      final replacement = await renewAccessToken!(accessToken);
      if (replacement == null) {
        throw const ApiException(
          statusCode: 401,
          message: 'Please sign in again.',
        );
      }
      response = await open(replacement);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _parseApiException(
        await http.Response.fromStream(
          response,
        ).timeout(ApiConfig.requestTimeout),
      );
    }
    if (!(response.headers['content-type'] ?? '').contains(
      'text/event-stream',
    )) {
      throw const FormatException('Expected an Agent event stream');
    }
    final data = <String>[];
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(const Duration(seconds: 120))) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          final event = jsonDecode(data.join('\n'));
          data.clear();
          if (event is! Map<String, dynamic>) {
            throw const FormatException('Invalid Agent event');
          }
          yield event;
        }
      } else if (line.startsWith('data:')) {
        final value = line.substring(5);
        data.add(value.startsWith(' ') ? value.substring(1) : value);
      }
    }
  }

  Map<String, String> _headers({String? accessToken}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      final response = await request().timeout(ApiConfig.requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _parseApiException(response);
      }

      return response;
    } on TimeoutException {
      throw const ApiException(
        statusCode: 0,
        code: 'TIMEOUT',
        message: 'The request timed out.',
      );
    } on http.ClientException catch (error) {
      throw ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: error.message,
      );
    }
  }

  Map<String, dynamic> _decodeSuccessfulResponse(http.Response response) {
    if (response.statusCode == 204) return {};
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // Converted to a consistent ApiException below.
    }

    throw ApiException(
      statusCode: response.statusCode,
      code: 'INVALID_RESPONSE',
      message: 'The server returned an invalid response.',
    );
  }

  ApiException _parseApiException(http.Response response) {
    var message = 'Request failed.';
    String? code;

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];

        if (detail is String) {
          message = detail;
        } else if (detail is List) {
          final messages = <String>[];

          for (final error in detail) {
            if (error is Map<String, dynamic>) {
              final errorMessage = error['msg'];
              if (errorMessage is String) {
                messages.add(errorMessage);
              }
            }
          }

          if (messages.isNotEmpty) {
            message = messages.join('\n');
          }
        } else if (detail is Map<String, dynamic>) {
          final detailCode = detail['code'];
          final detailMessage = detail['message'];

          if (detailCode is String) {
            code = detailCode;
            message = detailCode;
          }

          if (detailMessage is String) {
            message = detailMessage;
          }
        }
      }
    } on FormatException {
      // Keep the fallback message when the backend response is not JSON.
    }

    return ApiException(
      statusCode: response.statusCode,
      code: code,
      message: message,
    );
  }

  void close() {
    _client.close();
  }
}
