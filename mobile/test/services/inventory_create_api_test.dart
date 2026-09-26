import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/models/inventory_create_request.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/inventory_api_service.dart';

void main() {
  test('creates one inventory item with the stock-in contract', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/inventory-items');
      expect(request.headers['Authorization'], 'Bearer test-token');

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['storage_space_id'], 'space-1');
      expect(body['item_definition_id'], 'definition-1');
      expect(body['amount'], '2.5');
      expect(body['unit'], 'kg');

      return http.Response(jsonEncode(_inventoryItemJson), 201);
    });

    final service = InventoryApiService(ApiClient(client: client));
    final result = await service.createInventoryItem(
      accessToken: 'test-token',
      request: const InventoryCreateRequest(
        storageSpaceId: 'space-1',
        itemDefinitionId: 'definition-1',
        amount: '2.5',
        unit: 'kg',
      ),
    );

    expect(result.id, 'item-1');
    expect(result.displayQuantity, '2.5 kg');
  });
}

final _inventoryItemJson = <String, dynamic>{
  'id': 'item-1',
  'storage_space_id': 'space-1',
  'storage_space_name': 'Pantry',
  'item_definition_id': 'definition-1',
  'item_definition_name': 'Rice',
  'category_id': 'category-1',
  'category_name': 'Grains',
  'purchase_date': null,
  'expiry_date': null,
  'notes': null,
  'status': 'IN_STOCK',
  'initial_amount': '2.500',
  'initial_unit': 'kg',
  'confirmed_current_amount': '2.500',
  'confirmed_current_unit': 'kg',
  'confirmed_at': '2026-09-26T01:00:00Z',
  'estimated_current_amount': null,
  'estimated_current_unit': null,
  'estimated_at': null,
  'display_amount': '2.500',
  'display_unit': 'kg',
  'is_estimated': false,
  'version': 1,
  'created_at': '2026-09-26T01:00:00Z',
  'updated_at': '2026-09-26T01:00:00Z',
};
