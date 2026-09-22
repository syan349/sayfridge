import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/api_exception.dart';

void main() {
  group('ApiClient', () {
    test('GET sends the bearer token and decodes a JSON object', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/auth/me');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.headers['Accept'], 'application/json');

        return http.Response(
          jsonEncode({
            'id': 'user-1',
            'email': 'user@example.com',
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);

      final result = await apiClient.getJson(
        '/auth/me',
        accessToken: 'test-token',
      );

      expect(result['id'], 'user-1');
      expect(result['email'], 'user@example.com');
    });

    test('POST sends a JSON request body', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/login');
        expect(request.headers['Content-Type'], contains('application/json'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['email'], 'user@example.com');
        expect(body['password'], 'Password123!');

        return http.Response(
          jsonEncode({
            'access_token': 'test-token',
            'token_type': 'bearer',
            'expires_in': 900,
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);

      final result = await apiClient.postJson(
        '/auth/login',
        body: {
          'email': 'user@example.com',
          'password': 'Password123!',
        },
      );

      expect(result['access_token'], 'test-token');
    });

    test('parses an authentication error message', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Invalid email or password'}),
          401,
        );
      });

      final apiClient = ApiClient(client: mockClient);

      expect(
        apiClient.postJson('/auth/login'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having(
                (error) => error.message,
                'message',
                'Invalid email or password',
              ),
        ),
      );
    });

    test('parses FastAPI validation errors', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': [
              {
                'type': 'value_error',
                'loc': ['body', 'email'],
                'msg': 'value is not a valid email address',
              },
              {
                'type': 'value_error',
                'loc': ['body', 'password'],
                'msg': 'password is too short',
              },
            ],
          }),
          422,
        );
      });

      final apiClient = ApiClient(client: mockClient);

      expect(
        apiClient.postJson('/auth/register'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 422)
              .having(
                (error) => error.message,
                'message',
                'value is not a valid email address\npassword is too short',
              ),
        ),
      );
    });

    test('parses a structured business error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': {
              'code': 'STATE_CONFLICT',
              'message': 'Resource state does not allow this operation',
            },
          }),
          409,
        );
      });

      final apiClient = ApiClient(client: mockClient);

      expect(
        apiClient.getJson('/inventory-items/item-1'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 409)
              .having((error) => error.code, 'code', 'STATE_CONFLICT')
              .having(
                (error) => error.message,
                'message',
                'Resource state does not allow this operation',
              ),
        ),
      );
    });

    test('rejects a successful response that is not valid JSON', () async {
      final mockClient = MockClient((request) async {
        return http.Response('not-json', 200);
      });

      final apiClient = ApiClient(client: mockClient);

      expect(
        apiClient.getJson('/auth/me'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 200)
              .having((error) => error.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });
  });
}