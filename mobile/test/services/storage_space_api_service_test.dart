import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/storage_space_api_service.dart';

void main() {
  group('StorageSpaceApiService', () {
    test('gets and parses a page of active storage spaces', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/storage-spaces');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.url.queryParameters['status'], 'ACTIVE');
        expect(request.url.queryParameters['page'], '1');
        expect(request.url.queryParameters['page_size'], '20');

        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'space-1',
                'name': 'Kitchen fridge',
                'type': 'FRIDGE',
                'status': 'ACTIVE',
                'created_at': '2026-09-21T01:00:00Z',
                'updated_at': '2026-09-21T02:00:00Z',
              },
            ],
            'total': 1,
            'page': 1,
            'page_size': 20,
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final service = StorageSpaceApiService(apiClient);

      final result = await service.getStorageSpaces(
        accessToken: 'test-token',
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.name, 'Kitchen fridge');
      expect(result.total, 1);
      expect(result.hasNextPage, isFalse);
    });
  });
}