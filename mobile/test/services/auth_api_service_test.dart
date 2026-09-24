import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/api_exception.dart';
import 'package:sayfridge/services/auth_api_service.dart';

void main() {
  group('AuthApiService', () {
    test('register sends only email and password and parses the user', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/register');

        final body = jsonDecode(request.body) as Map<String, dynamic>;

        expect(body, {
          'email': 'new-user@example.com',
          'password': 'Password123!',
        });
        expect(body.containsKey('full_name'), isFalse);
        expect(body.containsKey('avatar'), isFalse);

        return http.Response(
          jsonEncode({
            'id': 'user-1',
            'email': 'new-user@example.com',
            'role': 'USER',
            'status': 'ACTIVE',
            'created_at': '2026-09-20T00:00:00Z',
          }),
          201,
        );
      });

      final service = AuthApiService(
        ApiClient(client: mockClient),
      );

      final user = await service.register(
        email: 'new-user@example.com',
        password: 'Password123!',
      );

      expect(user.id, 'user-1');
      expect(user.email, 'new-user@example.com');
      expect(user.role, 'USER');
      expect(user.status, 'ACTIVE');
    });

    test('login parses the authentication session', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/login');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['email'], 'user@example.com');
        expect(body['password'], 'Password123!');

        return http.Response(
          jsonEncode({
            'access_token': 'test-jwt-token',
            'token_type': 'bearer',
            'expires_in': 900,
            'user': {
              'id': 'user-1',
              'email': 'user@example.com',
              'role': 'USER',
              'status': 'ACTIVE',
              'created_at': '2026-09-20T00:00:00Z',
            },
          }),
          200,
        );
      });

      final service = AuthApiService(
        ApiClient(client: mockClient),
      );

      final session = await service.login(
        email: 'user@example.com',
        password: 'Password123!',
      );

      expect(session.accessToken, 'test-jwt-token');
      expect(session.tokenType, 'bearer');
      expect(session.expiresIn, 900);
      expect(session.user.email, 'user@example.com');
    });

    test('getCurrentUser sends the bearer token and parses the user', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/auth/me');
        expect(request.headers['Authorization'], 'Bearer test-jwt-token');

        return http.Response(
          jsonEncode({
            'id': 'user-1',
            'email': 'user@example.com',
            'role': 'USER',
            'status': 'ACTIVE',
            'created_at': '2026-09-20T00:00:00Z',
          }),
          200,
        );
      });

      final service = AuthApiService(
        ApiClient(client: mockClient),
      );

      final user = await service.getCurrentUser(
        accessToken: 'test-jwt-token',
      );

      expect(user.id, 'user-1');
      expect(user.email, 'user@example.com');
    });

    test('register passes backend conflicts through as ApiException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Email is already registered'}),
          409,
        );
      });

      final service = AuthApiService(
        ApiClient(client: mockClient),
      );

      expect(
        service.register(
          email: 'existing@example.com',
          password: 'Password123!',
        ),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 409)
              .having(
                (error) => error.message,
                'message',
                'Email is already registered',
              ),
        ),
      );
    });
  });
}