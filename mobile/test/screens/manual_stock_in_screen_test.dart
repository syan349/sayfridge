import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/models/item_icon.dart';
import 'package:sayfridge/models/inventory_item.dart';
import 'package:sayfridge/repositories/catalog_repository.dart';
import 'package:sayfridge/repositories/inventory_repository.dart';
import 'package:sayfridge/repositories/item_artwork_repository.dart';
import 'package:sayfridge/repositories/storage_space_repository.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/stock_editor_screen.dart';
import 'package:sayfridge/widgets/selection_field.dart';
import 'package:sayfridge/screens/manual_stock_in_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/catalog_api_service.dart';
import 'package:sayfridge/services/inventory_api_service.dart';
import 'package:sayfridge/services/storage_space_api_service.dart';
import 'package:sayfridge/state/manual_stock_in_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';
import 'package:sayfridge/widgets/inventory_visuals.dart';

import '../support/integration_fixtures.dart';

const _captureKey = Key('add-item-capture');

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['ADD_ITEM_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _Harness {
  _Harness({this.failStock = false, this.emptyDefinitions = false}) {
    api = ApiClient(
      client: MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'POST' || request.method == 'PATCH') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          writes.add((path, body));
          if (request.method == 'PATCH') {
            return jsonResponse({
              ...stockJson(version: 2),
              'category_id': body['category_id'] ?? 'category-1',
            });
          }
          if (path.endsWith('/item-categories')) {
            return jsonResponse({
              'id': 'custom-category',
              'name': body['name'],
              'status': 'ACTIVE',
              'sort_order': 0,
            });
          }
          if (path.endsWith('/item-definitions')) {
            return jsonResponse({
              'id': 'new-definition',
              'name': body['name'],
              'category_id': body['category_id'],
              'status': 'ACTIVE',
              'scope': 'PRIVATE',
            });
          }
          if (failStock) return jsonResponse({'message': 'Response lost'}, 500);
          return jsonResponse({
            ...stockJson(),
            'item_definition_name': 'Apple',
            'item_definition_id': body['item_definition_id'],
            'display_amount': body['amount'],
            'display_unit': body['unit'],
          });
        }
        if (path.endsWith('/storage-spaces')) {
          return jsonResponse({
            'items': [
              {
                'id': 'space-1',
                'name': 'Kitchen fridge',
                'type': 'FRIDGE',
                'status': 'ACTIVE',
                'is_default': true,
                'created_at': '2026-09-01T00:00:00Z',
                'updated_at': '2026-09-01T00:00:00Z',
              },
            ],
            'total': 1,
            'page': 1,
            'page_size': 100,
          });
        }
        if (path.endsWith('/item-categories')) {
          return jsonResponse({
            'items': [
              {
                'id': 'category-1',
                'name': 'Fruit',
                'status': 'ACTIVE',
                'sort_order': 1,
              },
            ],
            'total': 1,
            'page': 1,
            'page_size': 100,
          });
        }
        return jsonResponse({
          'items': emptyDefinitions
              ? []
              : [
                  {
                    'id': 'apple-definition',
                    'name': 'Apple',
                    'category_id': 'category-1',
                    'status': 'ACTIVE',
                    'scope': 'PUBLIC',
                  },
                ],
          'total': emptyDefinitions ? 0 : 1,
          'page': 1,
          'page_size': 100,
        });
      }),
    );
    final tokens = MemoryTokens();
    controller = ManualStockInController(
      CatalogRepository(CatalogApiService(api), tokens),
      InventoryRepository(InventoryApiService(api), tokens),
      StorageSpaceRepository(StorageSpaceApiService(api), tokens),
    );
  }
  final bool failStock, emptyDefinitions;
  late final ApiClient api;
  late final ManualStockInController controller;
  final writes = <(String, Map<String, dynamic>)>[];

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(api.close);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: ManualStockInScreen(
            controller: controller,
            workspace: WorkspaceRepository(api, MemoryTokens()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (Platform.environment['ADD_ITEM_CAPTURE_DIR'] != null) {
      await tester.runAsync(() async {
        await Future.wait([
          precacheImage(
            const AssetImage(ItemIcon.defaultAsset),
            tester.element(find.byType(ManualStockInScreen)),
          ),
          for (final icon in ItemIcon.library)
            precacheImage(
              AssetImage(icon.asset),
              tester.element(find.byType(ManualStockInScreen)),
            ),
        ]);
      });
      await tester.pumpAndSettle();
    }
  }
}

String _previewAsset(WidgetTester tester) =>
    (tester.widget<Image>(find.byKey(const Key('item-icon-preview'))).image
            as AssetImage)
        .assetName;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Optional visual QA uses the app font instead of Flutter's Ahem test font.
    if (Platform.environment['ADD_ITEM_CAPTURE_DIR'] == null) return;
    final font = File('C:/Windows/Fonts/arial.ttf');
    if (await font.exists()) {
      final loader = FontLoader('Arial')
        ..addFont(
          font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test('keyword matching respects words, plurals and specific phrases', () {
    expect(ItemIcon.forName('fresh APPLES'), endsWith('/apple.png'));
    expect(ItemIcon.forName('Whole milk'), endsWith('/milk.png'));
    expect(ItemIcon.forName('Chicken breast'), endsWith('/chicken_breast.png'));
    expect(ItemIcon.forName('Eggplant'), endsWith('/eggplant.png'));
    expect(ItemIcon.forName('Pineapple'), ItemIcon.defaultAsset);
    expect(ItemIcon.forName('苹果'), endsWith('/apple.png'));
    expect(ItemIcon.forName(''), ItemIcon.defaultAsset);
  });

  testWidgets(
    'typing matches immediately; manual icon survives edits and can return to automatic',
    (tester) async {
      await _Harness().open(tester);
      expect(_previewAsset(tester), ItemIcon.defaultAsset);
      expect(find.text('Type'), findsNothing);
      expect(find.textContaining('Choose Exact'), findsNothing);
      final name = find.byKey(const Key('add-item-name'));
      await tester.enterText(name, 'apple');
      await tester.pumpAndSettle();
      expect(_previewAsset(tester), endsWith('/apple.png'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _capture(tester, 'add-item-apple');
      await tester.enterText(name, 'unrecognised item');
      await tester.pumpAndSettle();
      expect(_previewAsset(tester), ItemIcon.defaultAsset);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('item-icon-preview')));
      await tester.tap(find.byKey(const Key('item-icon-preview')));
      await tester.pumpAndSettle();
      await _capture(tester, 'add-item-library');
      final search = find.widgetWithText(TextField, 'Search icons');
      await tester.enterText(search, 'banana');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Banana'));
      await tester.pumpAndSettle();
      expect(_previewAsset(tester), endsWith('/banana.png'));
      await tester.enterText(name, 'milk');
      await tester.pumpAndSettle();
      expect(_previewAsset(tester), endsWith('/banana.png'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use automatic icon'));
      await tester.tap(find.text('Use automatic icon'));
      await tester.pumpAndSettle();
      expect(_previewAsset(tester), endsWith('/milk.png'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing name reuses catalog ID, submits exact user quantity and persists selected icon',
    (tester) async {
      final harness = _Harness();
      await harness.open(tester);
      await tester.enterText(find.byKey(const Key('add-item-name')), 'Apple');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('item-icon-preview')));
      await tester.tap(find.byKey(const Key('item-icon-preview')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Banana'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('add-item-quantity')), '2.5');
      await tester.enterText(find.byKey(const Key('add-item-unit')), 'bowls');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Add to inventory');
      await tester.dragUntilVisible(
        button,
        find.byType(ListView).last,
        const Offset(0, -200),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await _capture(tester, 'add-item-form-bottom');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(harness.writes.length, 1);
      expect(
        harness.writes.single.$2['item_definition_id'],
        'apple-definition',
      );
      expect(harness.writes.single.$2['amount'], '2.5');
      expect(harness.writes.single.$2['unit'], 'bowls');
      expect(harness.controller.createdItem?.isEstimated, isFalse);
      expect(
        await const ItemArtworkRepository().read('item-1'),
        endsWith('/banana.png'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryArtwork(item: InventoryItem.fromJson(stockJson())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        endsWith('/banana.png'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'new name can be created in an empty category; unknown stock result blocks a second write',
    () async {
      final harness = _Harness(failStock: true, emptyDefinitions: true);
      addTearDown(harness.api.close);
      addTearDown(harness.controller.dispose);
      await harness.controller.loadOptions();
      expect(harness.controller.hasRequiredOptions, isTrue);
      expect(
        await harness.controller.submit(
          itemName: 'Green apple',
          amount: '2',
          unit: 'pcs',
        ),
        isFalse,
      );
      expect(harness.writes.length, 2);
      expect(harness.writes.first.$2, {
        'name': 'Green apple',
        'category_id': 'category-1',
      });
      expect(harness.writes.last.$2['item_definition_id'], 'new-definition');
      expect(harness.controller.submissionUncertain, isTrue);
      await harness.controller.submit(
        itemName: 'Green apple',
        amount: '2',
        unit: 'pcs',
      );
      expect(harness.writes.length, 2);
      harness.controller.reset();
      expect(harness.controller.submissionUncertain, isFalse);
    },
  );

  testWidgets('small screen and library search keyboard remain scrollable', (
    tester,
  ) async {
    await _Harness().open(tester, size: const Size(320, 568));
    await tester.tap(find.byKey(const Key('item-icon-preview')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search icons'),
      'zzzz',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching icons'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual category is saved and selected; forms open the existing space manager',
    (tester) async {
      final harness = _Harness();
      await harness.open(tester);
      await tester.enterText(find.byKey(const Key('add-item-name')), 'Apple');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final categoryField = find.byType(SelectionField).first;
      await tester.tap(categoryField);
      await tester.pumpAndSettle();
      await _capture(tester, 'choose-category');
      await tester.enterText(
        find.byKey(const Key('category-name-input')),
        'Baking',
      );
      await tester.tap(find.byTooltip('Use category'));
      await tester.pumpAndSettle();
      expect(harness.writes.single.$2, {'name': 'Baking'});
      expect(harness.controller.selectedCategoryId, 'custom-category');
      expect(find.text('Baking'), findsOneWidget);
      final storageField = find.byType(SelectionField).last;
      await tester.ensureVisible(storageField);
      await tester.pumpAndSettle();
      await tester.tap(storageField);
      await tester.pumpAndSettle();
      await _capture(tester, 'choose-storage-space');
      await tester.tap(find.text('Manage storage spaces'));
      await tester.pumpAndSettle();
      expect(find.text('Manage where you store items.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(harness.controller.selectedCategoryId, 'custom-category');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('add-item-name')))
            .controller
            ?.text,
        'Apple',
      );
    },
  );

  testWidgets(
    'detail edits save category and icon; restoring automatic removes the saved override',
    (tester) async {
      final harness = _Harness();
      await harness.open(tester);
      final item = InventoryItem.fromJson({
        ...stockJson(),
        'category_id': 'original-category',
        'category_name': 'Dairy',
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: StockEditorScreen(
              workspace: WorkspaceRepository(harness.api, MemoryTokens()),
              item: item,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, 'item-details-edit');
      await tester.tap(find.byKey(const Key('item-icon-preview')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Banana'));
      await tester.pumpAndSettle();
      await _capture(tester, 'item-details-manual-icon');
      final categoryField = find.byType(SelectionField).first;
      await tester.ensureVisible(categoryField);
      await tester.pumpAndSettle();
      await tester.tap(categoryField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fruit'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save changes');
      await tester.dragUntilVisible(
        save,
        find.byType(ListView).last,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(harness.writes.last.$2['category_id'], 'category-1');
      expect(harness.writes.last.$2['expected_version'], 1);
      expect(
        await const ItemArtworkRepository().read(item.id),
        endsWith('/banana.png'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StockEditorScreen(
            key: const Key('second-edit'),
            workspace: WorkspaceRepository(harness.api, MemoryTokens()),
            item: item,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use automatic icon'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Save changes'),
        find.byType(ListView).last,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      expect(await const ItemArtworkRepository().read(item.id), isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
