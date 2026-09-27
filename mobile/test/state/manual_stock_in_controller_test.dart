import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/inventory_create_request.dart';
import 'package:sayfridge/models/inventory_item.dart';
import 'package:sayfridge/models/item_category.dart';
import 'package:sayfridge/models/item_category_page.dart';
import 'package:sayfridge/models/item_definition.dart';
import 'package:sayfridge/models/item_definition_page.dart';
import 'package:sayfridge/models/storage_space.dart';
import 'package:sayfridge/models/storage_space_page.dart';
import 'package:sayfridge/repositories/catalog_repository.dart';
import 'package:sayfridge/repositories/inventory_repository.dart';
import 'package:sayfridge/repositories/storage_space_repository.dart';
import 'package:sayfridge/state/manual_stock_in_controller.dart';

void main() {
  test('loads stock-in options and selects the first values', () async {
    final controller = ManualStockInController(
      _FakeCatalogRepository(),
      _FakeInventoryRepository(),
      _FakeStorageSpaceRepository(),
    );
    addTearDown(controller.dispose);

    await controller.loadOptions();

    expect(controller.status, ManualStockInStatus.ready);
    expect(controller.selectedStorageSpaceId, 'space-1');
    expect(controller.selectedCategoryId, 'category-1');
    expect(controller.selectedDefinitionId, 'definition-1');
    expect(controller.hasRequiredOptions, isTrue);
  });

  test('submits the selected item and stores the created result', () async {
    final inventoryRepository = _FakeInventoryRepository();
    final controller = ManualStockInController(
      _FakeCatalogRepository(),
      inventoryRepository,
      _FakeStorageSpaceRepository(),
    );
    addTearDown(controller.dispose);
    await controller.loadOptions();

    final success = await controller.submit(
      amount: '2.5',
      unit: 'kg',
      expiryDate: DateTime(2026, 10, 1),
    );

    expect(success, isTrue);
    expect(controller.status, ManualStockInStatus.success);
    expect(controller.createdItem?.id, 'item-1');
    expect(inventoryRepository.receivedRequest?.amount, '2.5');
    expect(
      inventoryRepository.receivedRequest?.itemDefinitionId,
      'definition-1',
    );
  });
}

class _FakeCatalogRepository extends Fake implements CatalogRepository {
  @override
  Future<ItemCategoryPage> getCategories({
    int page = 1,
    int pageSize = 100,
  }) async {
    return const ItemCategoryPage(
      items: [
        ItemCategory(
          id: 'category-1',
          name: 'Dairy',
          status: 'ACTIVE',
          sortOrder: 1,
        ),
      ],
      total: 1,
      page: 1,
      pageSize: 100,
    );
  }

  @override
  Future<ItemDefinitionPage> getDefinitions({
    String? categoryId,
    String query = '',
    int page = 1,
    int pageSize = 100,
  }) async {
    return const ItemDefinitionPage(
      items: [
        ItemDefinition(
          id: 'definition-1',
          name: 'Milk',
          categoryId: 'category-1',
          status: 'ACTIVE',
          scope: 'PUBLIC',
        ),
      ],
      total: 1,
      page: 1,
      pageSize: 100,
    );
  }
}

class _FakeStorageSpaceRepository extends Fake
    implements StorageSpaceRepository {
  @override
  Future<StorageSpacePage> getStorageSpaces({
    String status = 'ACTIVE',
    int page = 1,
    int pageSize = 20,
  }) async {
    return StorageSpacePage(
      items: [
        StorageSpace(
          id: 'space-1',
          name: 'Kitchen fridge',
          type: 'FRIDGE',
          status: 'ACTIVE',
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      ],
      total: 1,
      page: 1,
      pageSize: 100,
    );
  }
}

class _FakeInventoryRepository extends Fake implements InventoryRepository {
  InventoryCreateRequest? receivedRequest;

  @override
  Future<InventoryItem> createInventoryItem(
    InventoryCreateRequest request,
  ) async {
    receivedRequest = request;
    return InventoryItem(
      id: 'item-1',
      storageSpaceId: request.storageSpaceId,
      storageSpaceName: 'Kitchen fridge',
      itemDefinitionId: request.itemDefinitionId,
      itemDefinitionName: 'Milk',
      categoryId: 'category-1',
      categoryName: 'Dairy',
      purchaseDate: request.purchaseDate,
      expiryDate: request.expiryDate,
      notes: request.notes,
      status: 'IN_STOCK',
      initialAmount: 2.5,
      initialUnit: request.unit,
      confirmedCurrentAmount: 2.5,
      confirmedCurrentUnit: request.unit,
      confirmedAt: DateTime(2026, 9, 26),
      estimatedCurrentAmount: null,
      estimatedCurrentUnit: null,
      estimatedAt: null,
      displayAmount: 2.5,
      displayUnit: request.unit,
      isEstimated: false,
      version: 1,
      createdAt: DateTime(2026, 9, 26),
      updatedAt: DateTime(2026, 9, 26),
    );
  }
}
