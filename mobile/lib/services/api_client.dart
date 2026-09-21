import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> getJson(
    String path, {
    String? accessToken,
    Map<String, String>? queryParameters,
  }) async {
    final uri = ApiConfig.buildUri(path).replace(
      queryParameters: queryParameters,
    );

    final response = await _send(
      () => _client.get(
        uri,
        headers: _headers(accessToken: accessToken),
      ),
    );

    return _decodeSuccessfulResponse(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final response = await _send(
      () => _client.post(
        ApiConfig.buildUri(path),
        headers: _headers(accessToken: accessToken),
        body: jsonEncode(body ?? <String, dynamic>{}),
      ),
    );

    return _decodeSuccessfulResponse(response);
  }

  Map<String, String> _headers({String? accessToken}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (accessToken != null)
        'Authorization': 'Bearer $accessToken',
    };
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request,
  ) async {
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

  Map<String, dynamic> _decodeSuccessfulResponse(
    http.Response response,
  ) {
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