import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/expiry_summary.dart';
import 'package:sayfridge/models/inventory_item.dart';
import 'package:sayfridge/models/inventory_page.dart';
import 'package:sayfridge/models/inventory_create_request.dart';
import 'package:sayfridge/repositories/inventory_repository.dart';
import 'package:sayfridge/state/inventory_controller.dart';

void main() {
  test('loads an empty filtered inventory page', () async {
    final repository = _FakeInventoryRepository();
    final controller = InventoryController(repository);
    addTearDown(controller.dispose);

    await controller.loadInventory(
      query: 'milk',
      storageSpaceId: 'space-1',
      page: 2,
      pageSize: 10,
    );

    expect(controller.status, InventoryLoadStatus.empty);
    expect(controller.query, 'milk');
    expect(controller.storageSpaceId, 'space-1');
    expect(repository.receivedPage, 2);
    expect(repository.receivedPageSize, 10);
  });

  test(
    'changing storage preserves the active search and all item filters',
    () async {
      final repository = _FakeInventoryRepository();
      final controller = InventoryController(repository);
      addTearDown(controller.dispose);
      await controller.loadInventory(
        query: 'milk',
        categoryId: 'dairy',
        purchaseFrom: DateTime(2026, 9, 1),
        purchaseTo: DateTime(2026, 9, 30),
        expiryFrom: DateTime(2026, 10, 1),
        expiryTo: DateTime(2026, 10, 10),
        page: 2,
      );
      await controller.loadStorageSpace('freezer');
      expect(repository.receivedFilters, {
        'query': 'milk',
        'storageSpaceId': 'freezer',
        'categoryId': 'dairy',
        'purchaseFrom': DateTime(2026, 9, 1),
        'purchaseTo': DateTime(2026, 9, 30),
        'expiryFrom': DateTime(2026, 10, 1),
        'expiryTo': DateTime(2026, 10, 10),
      });
      expect(repository.receivedPage, 1);
    },
  );

  test(
    'account reset invalidates an unfinished complete selection read',
    () async {
      final repository = _FakeInventoryRepository();
      final controller = InventoryController(repository);
      addTearDown(controller.dispose);
      await controller.loadInventory();
      repository.pending = Completer<InventoryPage>();
      final selection = controller.matchingItems();
      final expectation = expectLater(selection, throwsStateError);
      controller.reset();
      repository.pending!.complete(
        const InventoryPage(items: [], total: 0, page: 1, pageSize: 100),
      );
      await expectation;
      expect(controller.items, isEmpty);
      expect(controller.status, InventoryLoadStatus.initial);
    },
  );
}

class _FakeInventoryRepository implements InventoryRepository {
  int? receivedPage;
  int? receivedPageSize;
  Map<String, Object?>? receivedFilters;
  Completer<InventoryPage>? pending;

  @override
  Future<InventoryItem> createInventoryItem(InventoryCreateRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<ExpirySummary> getExpirySummary({
    required DateTime asOf,
    int daysBefore = 3,
    String? storageSpaceId,
    String? categoryId,
    String? bucket,
    int page = 1,
    int pageSize = 20,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<InventoryItem> getInventoryItem(String itemId) {
    throw UnimplementedError();
  }

  @override
  Future<InventoryPage> getInventory({
    String status = 'IN_STOCK',
    String query = '',
    String? storageSpaceId,
    String? categoryId,
    DateTime? purchaseFrom,
    DateTime? purchaseTo,
    DateTime? expiryFrom,
    DateTime? expiryTo,
    int page = 1,
    int pageSize = 20,
  }) async {
    receivedPage = page;
    receivedPageSize = pageSize;
    receivedFilters = {
      'query': query,
      'storageSpaceId': storageSpaceId,
      'categoryId': categoryId,
      'purchaseFrom': purchaseFrom,
      'purchaseTo': purchaseTo,
      'expiryFrom': expiryFrom,
      'expiryTo': expiryTo,
    };
    if (pending != null) return pending!.future;
    return InventoryPage(
      items: const [],
      total: 0,
      page: page,
      pageSize: pageSize,
    );
  }
}
