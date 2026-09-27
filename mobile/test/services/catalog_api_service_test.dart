import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/catalog_api_service.dart';

void main() {
  test('loads active item categories', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/item-categories');
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.url.queryParameters['status'], 'ACTIVE');

      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': 'category-1',
              'name': 'Dairy',
              'status': 'ACTIVE',
              'sort_order': 1,
            },
          ],
          'total': 1,
          'page': 1,
          'page_size': 100,
        }),
        200,
      );
    });

    final service = CatalogApiService(ApiClient(client: client));
    final page = await service.getCategories(accessToken: 'test-token');

    expect(page.items.single.name, 'Dairy');
    expect(page.items.single.isActive, isTrue);
  });

  test('filters active definitions by category', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/item-definitions');
      expect(request.url.queryParameters['category_id'], 'category-1');
      expect(request.url.queryParameters['scope'], 'ALL');

      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': 'definition-1',
              'name': 'Milk',
              'category_id': 'category-1',
              'status': 'ACTIVE',
              'scope': 'PUBLIC',
            },
          ],
          'total': 1,
          'page': 1,
          'page_size': 100,
        }),
        200,
      );
    });

    final service = CatalogApiService(ApiClient(client: client));
    final page = await service.getDefinitions(
      accessToken: 'test-token',
      categoryId: 'category-1',
    );

    expect(page.items.single.name, 'Milk');
    expect(page.items.single.categoryId, 'category-1');
  });
}
