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

  test('concurrent expired requests rotate once and retry', () async {
    FlutterSecureStorage.setMockInitialValues({
      'auth_access_token': 'old',
      'auth_refresh_token': 'refresh-old',
    });
    var rotations = 0;
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          rotations++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(
            jsonEncode({
              'access_token': 'new',
              'refresh_token': 'refresh-new',
              'token_type': 'bearer',
              'expires_in': 900,
              'user': userJson(),
            }),
            200,
          );
        }
        if (request.headers['Authorization'] == 'Bearer old') {
          return http.Response('{"detail":"Expired"}', 401);
        }
        expect(request.headers['Authorization'], 'Bearer new');
        return http.Response(jsonEncode(userJson()), 200);
      }),
    );
    AuthRepository(AuthApiService(client), tokenStorage);
    await Future.wait([
      client.getJson('/auth/me', accessToken: 'old'),
      client.getJson('/auth/me', accessToken: 'old'),
    ]);
    expect(rotations, 1);
    expect(await tokenStorage.readRefreshToken(), 'refresh-new');
  });

  test('revoked refresh clears credentials and requests login', () async {
    FlutterSecureStorage.setMockInitialValues({
      'auth_access_token': 'old',
      'auth_refresh_token': 'refresh-old',
    });
    final repository = createRepository(
      MockClient((request) async => http.Response('{"detail":"Revoked"}', 401)),
    );
    var expired = false;
    repository.onSessionExpired = () => expired = true;
    expect(await repository.restoreSession(), isNull);
    expect(expired, isTrue);
    expect(await tokenStorage.readRefreshToken(), isNull);
  });

  test('offline renewal preserves credentials for retry', () async {
    FlutterSecureStorage.setMockInitialValues({
      'auth_access_token': 'old',
      'auth_refresh_token': 'refresh-old',
    });
    final repository = createRepository(
      MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          throw http.ClientException('Offline');
        }
        return http.Response('{"detail":"Expired"}', 401);
      }),
    );
    await expectLater(
      repository.restoreSession(),
      throwsA(isA<ApiException>()),
    );
    expect(await tokenStorage.readRefreshToken(), 'refresh-old');
  });

  test(
    'logout revokes server session before deleting local credentials',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_access_token': 'old',
        'auth_refresh_token': 'refresh-old',
      });
      final repository = createRepository(
        MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/logout');
          expect(jsonDecode(request.body), {'refresh_token': 'refresh-old'});
          expect(await tokenStorage.readAccessToken(), 'old');
          return http.Response('', 204);
        }),
      );
      await repository.logout();
      expect(await tokenStorage.readAccessToken(), isNull);
      expect(await tokenStorage.readRefreshToken(), isNull);
    },
  );

  test('offline logout retains session so revocation can be retried', () async {
    FlutterSecureStorage.setMockInitialValues({
      'auth_access_token': 'old',
      'auth_refresh_token': 'refresh-old',
    });
    final repository = createRepository(
      MockClient((request) async {
        throw http.ClientException('Offline');
      }),
    );
    await expectLater(repository.logout(), throwsA(isA<ApiException>()));
    expect(await tokenStorage.readRefreshToken(), 'refresh-old');
  });

  test('Agent stream renews authentication before streaming starts', () async {
    FlutterSecureStorage.setMockInitialValues({
      'auth_access_token': 'old',
      'auth_refresh_token': 'refresh-old',
    });
    var streams = 0;
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          return http.Response(
            jsonEncode({
              'access_token': 'new',
              'refresh_token': 'refresh-new',
              'token_type': 'bearer',
              'expires_in': 900,
              'user': userJson(),
            }),
            200,
          );
        }
        streams++;
        if (request.headers['Authorization'] == 'Bearer old') {
          return http.Response('{"detail":"Expired"}', 401);
        }
        expect(request.headers['Authorization'], 'Bearer new');
        return http.Response(
          'data: {"type":"done"}\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );
    AuthRepository(AuthApiService(client), tokenStorage);
    expect(
      await client
          .events('/agent/chat', body: {'text': 'hello'}, accessToken: 'old')
          .toList(),
      [
        {'type': 'done'},
      ],
    );
    expect(streams, 2);
  });

  group('AuthRepository', () {
    test('register returns the user without storing a token', () async {
      final repository = createRepository(
        MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/register');

          return http.Response(jsonEncode(userJson()), 201);
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
      expect(await tokenStorage.readAccessToken(), 'saved-jwt-token');
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
          expect(request.headers['Authorization'], 'Bearer stored-jwt-token');

          return http.Response(jsonEncode(userJson()), 200);
        }),
      );

      final user = await repository.restoreSession();

      expect(user?.email, 'user@example.com');
      expect(await tokenStorage.readAccessToken(), 'stored-jwt-token');
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

      expect(await tokenStorage.readAccessToken(), 'stored-jwt-token');
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
