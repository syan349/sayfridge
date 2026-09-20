import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/auth_repository.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/api_exception.dart';
import 'package:sayfridge/services/auth_api_service.dart';
import 'package:sayfridge/services/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tokenStorage = TokenStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  AuthRepository createRepository(MockClient mockClient) {
    return AuthRepository(
      AuthApiService(ApiClient(client: mockClient)),
      tokenStorage,
    );
  }

  Map<String, dynamic> userJson() {
    return {
      'id': 'user-1',
      'email': 'user@example.com',
      'role': 'USER',
      'status': 'ACTIVE',
      'created_at': '2026-09-21T00:00:00Z',
    };
  }

  group('AuthRepository', () {
    test('register returns the user without storing a token', () async {
      final repository = createRepository(
        MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/register');

          return http.Response(
            jsonEncode(userJson()),
            201,
          );
        }),
      );

      final user = await repository.register(
        email: 'user@example.com',
        password: 'Password123!',
      );

      expect(user.email, 'user@example.com');
      expect(await tokenStorage.readAccessToken(), isNull);
    });

    test('login stores the access token and returns the user', () async {
      final repository = createRepository(
        MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/login');

          return http.Response(
            jsonEncode({
              'access_token': 'saved-jwt-token',
              'token_type': 'bearer',
              'expires_in': 900,
              'user': userJson(),
            }),
            200,
          );
        }),
      );

      final user = await repository.login(
        email: 'user@example.com',
        password: 'Password123!',
      );

      expect(user.email, 'user@example.com');
      expect(
        await tokenStorage.readAccessToken(),
        'saved-jwt-token',
      );
    });

    test('restoreSession returns null when no token exists', () async {
      final repository = createRepository(
        MockClient((request) async {
          fail('The API must not be called without a stored token');
        }),
      );

      final user = await repository.restoreSession();

      expect(user, isNull);
    });

    test('restoreSession validates the token and returns the user', () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_access_token': 'stored-jwt-token',
      });

      final repository = createRepository(
        MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/me');
          expect(
            request.headers['Authorization'],
            'Bearer stored-jwt-token',
          );

          return http.Response(
            jsonEncode(userJson()),
            200,
          );
        }),
      );

      final user = await repository.restoreSession();

      expect(user?.email, 'user@example.com');
      expect(
        await tokenStorage.readAccessToken(),
        'stored-jwt-token',
      );
    });

    test('restoreSession deletes an unauthorized token', () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_access_token': 'expired-jwt-token',
      });

      final repository = createRepository(
        MockClient((request) async {
          return http.Response(
            jsonEncode({'detail': 'Invalid or expired access token'}),
            401,
          );
        }),
      );

      final user = await repository.restoreSession();

      expect(user, isNull);
      expect(await tokenStorage.readAccessToken(), isNull);
    });

    test('restoreSession preserves the token for non-auth failures', () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_access_token': 'stored-jwt-token',
      });

      final repository = createRepository(
        MockClient((request) async {
          return http.Response(
            jsonEncode({
              'detail': {
                'code': 'SERVICE_UNAVAILABLE',
                'message': 'Backend is temporarily unavailable',
              },
            }),
            503,
          );
        }),
      );

      await expectLater(
        repository.restoreSession(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            503,
          ),
        ),
      );

      expect(
        await tokenStorage.readAccessToken(),
        'stored-jwt-token',
      );
    });

    test('logout deletes the stored token', () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_access_token': 'stored-jwt-token',
      });

      final repository = createRepository(
        MockClient((request) async {
          fail('Logout must not call the backend');
        }),
      );

      await repository.logout();

      expect(await tokenStorage.readAccessToken(), isNull);
    });
  });
}