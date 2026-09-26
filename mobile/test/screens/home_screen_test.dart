import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/expiry_summary.dart';
import 'package:sayfridge/models/inventory_item.dart';
import 'package:sayfridge/models/inventory_page.dart';
import 'package:sayfridge/models/storage_space.dart';
import 'package:sayfridge/models/storage_space_page.dart';
import 'package:sayfridge/repositories/inventory_repository.dart';
import 'package:sayfridge/repositories/storage_space_repository.dart';
import 'package:sayfridge/screens/home_screen.dart';
import 'package:sayfridge/state/expiry_summary_controller.dart';
import 'package:sayfridge/state/inventory_controller.dart';
import 'package:sayfridge/state/storage_space_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guest home fits the phone and keeps login visible', (
    tester,
  ) async {
    _phoneSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          isGuest: true,
          onAssistantTap: () {},
          onLoginTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No item added yet'), findsOneWidget);
    expect(find.text('Your inventory is empty'), findsOneWidget);
    expect(find.text('Log in / Sign up'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('user home shows real summaries and filters by storage space', (
    tester,
  ) async {
    _phoneSize(tester);
    final repository = _InventoryFixtureRepository();
    final inventory = InventoryController(repository);
    final expiry = ExpirySummaryController(repository);
    final spaces = StorageSpaceController(_StorageFixtureRepository());
    addTearDown(inventory.dispose);
    addTearDown(expiry.dispose);
    addTearDown(spaces.dispose);

    await inventory.loadInventory();
    await expiry.loadSummary(asOf: DateUtils.dateOnly(DateTime.now()));
    await spaces.loadStorageSpaces();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          onAssistantTap: () {},
          inventoryController: inventory,
          expirySummaryController: expiry,
          storageSpaceController: spaces,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 items'), findsOneWidget);
    expect(find.text('Meat'), findsOneWidget);
    expect(find.text('Vegetables'), findsOneWidget);
    expect(find.text('Others'), findsOneWidget);
    expect(find.text('View all expiring items'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('All Spaces').first);
    await tester.pumpAndSettle();
    expect(find.text('Choose storage space'), findsOneWidget);
    await tester.tap(find.text('Fridge').last);
    await tester.pumpAndSettle();

    expect(repository.lastStorageSpaceId, 'fridge');
    expect(find.text('Fridge'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('View all items'));
    await tester.tap(find.text('View all items'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory Overview'), findsOneWidget);

    await tester.tap(find.text('Chicken Thigh'));
    await tester.pumpAndSettle();
    expect(find.text('Item details'), findsOneWidget);
    expect(find.text('Edit item'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // This read-only fixture has no write repository. It must not pretend
    // that offline edits were saved; the actual form is tested separately.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Edit item'))
          .onPressed,
      isNull,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View all expiring items'));
    await tester.tap(find.text('View all expiring items'));
    await tester.pumpAndSettle();
    expect(find.text('Expiry Overview'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fridge').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage storage spaces'));
    await tester.pumpAndSettle();
    expect(find.text('Storage spaces'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search items ...'));
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Milk');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('user home hides the expiry action when nothing is due', (
    tester,
  ) async {
    _phoneSize(tester);
    final repository = _InventoryFixtureRepository(emptyExpiry: true);
    final inventory = InventoryController(repository);
    final expiry = ExpirySummaryController(repository);
    addTearDown(inventory.dispose);
    addTearDown(expiry.dispose);
    await inventory.loadInventory();
    await expiry.loadSummary(asOf: DateUtils.dateOnly(DateTime.now()));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          onAssistantTap: () {},
          inventoryController: inventory,
          expirySummaryController: expiry,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No items expiring soon'), findsOneWidget);
    expect(find.text('View all expiring items'), findsNothing);
    expect(find.text('3 items'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _InventoryFixtureRepository implements InventoryRepository {
  _InventoryFixtureRepository({this.emptyExpiry = false});

  final bool emptyExpiry;
  String? lastStorageSpaceId;

  List<InventoryItem> get allItems => [
    _item('chicken', 'Chicken Thigh', 'Meat', 'fridge', 1),
    _item('tomato', 'Tomatoes', 'Vegetables', 'pantry', 2),
    _item('milk', 'Milk', 'Dairy', 'fridge', 1),
  ];

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
    lastStorageSpaceId = storageSpaceId;
    final items = allItems
        .where(
          (item) =>
              (storageSpaceId == null ||
                  item.storageSpaceId == storageSpaceId) &&
              (query.isEmpty ||
                  item.itemDefinitionName.toLowerCase().contains(
                    query.toLowerCase(),
                  )),
        )
        .toList();
    return InventoryPage(
      items: items,
      total: items.length,
      page: page,
      pageSize: pageSize,
    );
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
  }) async {
    if (emptyExpiry) {
      return ExpirySummary(
        counts: const ExpiryCounts(overdue: 0, today: 0, upcoming: 0),
        items: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
      );
    }
    final items = allItems
        .where(
          (item) =>
              storageSpaceId == null || item.storageSpaceId == storageSpaceId,
        )
        .toList();
    return ExpirySummary(
      counts: ExpiryCounts(overdue: 0, today: 0, upcoming: items.length),
      items: items
          .map((item) => ExpirySummaryItem(item: item, bucket: 'upcoming'))
          .toList(),
      total: items.length,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<InventoryItem> getInventoryItem(String itemId) async =>
      allItems.firstWhere((item) => item.id == itemId);
}

class _StorageFixtureRepository implements StorageSpaceRepository {
  @override
  Future<StorageSpacePage> getStorageSpaces({
    String status = 'ACTIVE',
    int page = 1,
    int pageSize = 20,
  }) async => StorageSpacePage(
    items: [
      _space('fridge', 'Fridge', 'FRIDGE'),
      _space('pantry', 'Pantry', 'PANTRY'),
    ],
    total: 2,
    page: page,
    pageSize: pageSize,
  );
}

InventoryItem _item(
  String id,
  String name,
  String category,
  String space,
  int daysLeft,
) {
  final now = DateTime.now();
  return InventoryItem(
    id: id,
    storageSpaceId: space,
    storageSpaceName: space == 'fridge' ? 'Fridge' : 'Pantry',
    itemDefinitionId: id,
    itemDefinitionName: name,
    categoryId: category.toLowerCase(),
    categoryName: category,
    purchaseDate: now,
    expiryDate: DateUtils.dateOnly(now).add(Duration(days: daysLeft)),
    notes: null,
    status: 'IN_STOCK',
    initialAmount: 500,
    initialUnit: 'g',
    confirmedCurrentAmount: 500,
    confirmedCurrentUnit: 'g',
    confirmedAt: now,
    estimatedCurrentAmount: null,
    estimatedCurrentUnit: null,
    estimatedAt: null,
    displayAmount: 500,
    displayUnit: 'g',
    isEstimated: false,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

StorageSpace _space(String id, String name, String type) {
  final now = DateTime.now();
  return StorageSpace(
    id: id,
    name: name,
    type: type,
    status: 'ACTIVE',
    createdAt: now,
    updatedAt: now,
  );
}
