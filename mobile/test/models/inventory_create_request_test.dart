import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/inventory_create_request.dart';

void main() {
  test('serializes required and optional stock-in fields', () {
    final request = InventoryCreateRequest(
      storageSpaceId: 'space-1',
      itemDefinitionId: 'definition-1',
      amount: '2.500',
      unit: ' kg ',
      purchaseDate: DateTime(2026, 9, 20),
      expiryDate: DateTime(2026, 9, 30),
      notes: ' Fridge door ',
    );

    expect(request.toJson(), {
      'storage_space_id': 'space-1',
      'item_definition_id': 'definition-1',
      'amount': '2.500',
      'unit': 'kg',
      'purchase_date': '2026-09-20',
      'expiry_date': '2026-09-30',
      'notes': 'Fridge door',
    });
  });

  test('omits empty optional stock-in fields', () {
    const request = InventoryCreateRequest(
      storageSpaceId: 'space-1',
      itemDefinitionId: 'definition-1',
      amount: '1',
      unit: 'each',
      notes: '   ',
    );

    expect(request.toJson().containsKey('purchase_date'), isFalse);
    expect(request.toJson().containsKey('expiry_date'), isFalse);
    expect(request.toJson().containsKey('notes'), isFalse);
  });
}
