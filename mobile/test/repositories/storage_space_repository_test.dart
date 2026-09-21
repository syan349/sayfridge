import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/storage_space_repository.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/api_exception.dart';
import 'package:sayfridge/services/storage_space_api_service.dart';
import 'package:sayfridge/services/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tokenStorage = TokenStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  StorageSpaceRepository createRepository(MockClient mockClient) {
    return StorageSpaceRepository(
      StorageSpaceApiService(
        ApiClient(client: mockClient),
      ),
      tokenStorage,
    );
  }

  group('StorageSpaceRepository', () {
    test('rejects the request when no access token exists', () async {
      final repository = createRepository(
        MockClient((request) async {
          fail('The API must not be called without an access token');
        }),
      );

      await expectLater(
        repository.getStorageSpaces(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having((error) => error.code, 'code', 'AUTH_REQUIRED'),
        ),
      );
    });

    test('uses the stored token to load storage spaces', () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_access_token': 'stored-token',
      });

      final repository = createRepository(
        MockClient((request) async {
          expect(
            request.headers['Authorization'],
            'Bearer stored-token',
          );
          expect(request.url.queryParameters['status'], 'ALL');
          expect(request.url.queryParameters['page'], '2');
          expect(request.url.queryParameters['page_size'], '10');

          return http.Response(
            jsonEncode({
              'items': [],
              'total': 12,
              'page': 2,
              'page_size': 10,
            }),
            200,
          );
        }),
      );

      final result = await repository.getStorageSpaces(
        status: 'ALL',
        page: 2,
        pageSize: 10,
      );

      expect(result.items, isEmpty);
      expect(result.total, 12);
      expect(result.page, 2);
      expect(result.pageSize, 10);
    });
  });
}