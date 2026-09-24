import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/inventory_page.dart';

void main() {
  test('parses an inventory page and its display quantity', () {
    final page = InventoryPage.fromJson({
      'items': [
        {
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
          'estimated_current_amount': 1.25,
          'estimated_current_unit': 'L',
          'estimated_at': '2026-09-24T10:00:00Z',
          'display_amount': '1.250',
          'display_unit': 'L',
          'is_estimated': true,
          'version': 2,
          'created_at': '2026-09-20T01:00:00Z',
          'updated_at': '2026-09-24T10:00:00Z',
        },
      ],
      'total': 21,
      'page': 1,
      'page_size': 20,
    });

    expect(page.items, hasLength(1));
    expect(page.hasNextPage, isTrue);

    final item = page.items.single;
    expect(item.itemDefinitionName, 'Milk');
    expect(item.storageSpaceName, 'Kitchen fridge');
    expect(item.displayAmount, 1.25);
    expect(item.displayQuantity, '1.25 L');
    expect(item.isEstimated, isTrue);
    expect(item.isInStock, isTrue);
    expect(item.purchaseDate, DateTime(2026, 9, 20));
  });
}
