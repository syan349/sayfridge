import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/inventory_api_service.dart';

void main() {
  test('gets an expiry summary for the requested date window', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/inventory-items/expiry-summary');
      expect(request.url.queryParameters['as_of'], '2026-09-24');
      expect(request.url.queryParameters['days_before'], '7');
      expect(request.url.queryParameters['storage_space_id'], 'space-1');

      return http.Response(
        jsonEncode({
          'counts': {'overdue': 1, 'today': 2, 'upcoming': 3},
          'items': [],
          'total': 0,
          'page': 1,
          'page_size': 20,
        }),
        200,
      );
    });

    final service = InventoryApiService(ApiClient(client: client));
    final summary = await service.getExpirySummary(
      accessToken: 'test-token',
      asOf: DateTime(2026, 9, 24),
      daysBefore: 7,
      storageSpaceId: 'space-1',
    );

    expect(summary.counts.total, 6);
    expect(summary.items, isEmpty);
  });

  test('gets one inventory item by id', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/inventory-items/item-1');
      expect(request.headers['Authorization'], 'Bearer test-token');

      return http.Response(jsonEncode(_inventoryItemJson), 200);
    });

    final service = InventoryApiService(ApiClient(client: client));
    final item = await service.getInventoryItem(
      accessToken: 'test-token',
      itemId: 'item-1',
    );

    expect(item.id, 'item-1');
    expect(item.itemDefinitionName, 'Milk');
  });

  test('sends inventory filters and parses an empty page', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/inventory-items');
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.url.queryParameters['status'], 'IN_STOCK');
      expect(request.url.queryParameters['q'], 'milk');
      expect(request.url.queryParameters['storage_space_id'], 'space-1');
      expect(request.url.queryParameters['expiry_to'], '2026-09-30');
      expect(request.url.queryParameters['page'], '2');
      expect(request.url.queryParameters['page_size'], '10');

      return http.Response(
        jsonEncode({'items': [], 'total': 0, 'page': 2, 'page_size': 10}),
        200,
      );
    });

    final apiClient = ApiClient(client: client);
    final service = InventoryApiService(apiClient);
    final result = await service.getInventory(
      accessToken: 'test-token',
      query: 'milk',
      storageSpaceId: 'space-1',
      expiryTo: DateTime(2026, 9, 30),
      page: 2,
      pageSize: 10,
    );

    expect(result.items, isEmpty);
    expect(result.page, 2);
  });
}

final _inventoryItemJson = <String, dynamic>{
  'id': 'item-1',
  'storage_space_id': 'space-1',
  'storage_space_name': 'Kitchen fridge',
  'item_definition_id': 'definition-1',
  'item_definition_name': 'Milk',
  'category_id': 'category-1',
  'category_name': 'Dairy',
  'purchase_date': '2026-09-20',
  'expiry_date': '2026-09-28',
  'notes': null,
  'status': 'IN_STOCK',
  'initial_amount': '2.000',
  'initial_unit': 'L',
  'confirmed_current_amount': '1.500',
  'confirmed_current_unit': 'L',
  'confirmed_at': '2026-09-23T10:00:00Z',
  'estimated_current_amount': null,
  'estimated_current_unit': null,
  'estimated_at': null,
  'display_amount': '1.500',
  'display_unit': 'L',
  'is_estimated': false,
  'version': 1,
  'created_at': '2026-09-20T01:00:00Z',
  'updated_at': '2026-09-23T10:00:00Z',
};
