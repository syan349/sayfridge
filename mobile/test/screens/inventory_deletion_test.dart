import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/models/item_icon.dart';
import 'package:sayfridge/repositories/inventory_repository.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/inventory_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/inventory_api_service.dart';
import 'package:sayfridge/state/inventory_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';
import 'package:sayfridge/widgets/swipe_delete_card.dart';
import 'package:sayfridge/widgets/inventory_visuals.dart';
import 'package:sayfridge/widgets/page_scroll_fade.dart';

import '../support/integration_fixtures.dart';

const _captureKey = Key('inventory-review-capture');

Future<void> _capture(
  WidgetTester tester,
  String name, {
  double pixelRatio = 2,
}) async {
  final directory = Platform.environment['INVENTORY_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _captureSwipeAnimation(WidgetTester tester, Finder card) async {
  if (Platform.environment['INVENTORY_ANIMATION'] != '1') return;
  final context = tester.element(card);
  await tester.runAsync(() async {
    for (final name in ['Milk', 'Eggs']) {
      await precacheImage(AssetImage(ItemIcon.forName(name)), context);
    }
  });
  await tester.pumpAndSettle();
  var frame = 0;
  Future<void> capture() => _capture(
    tester,
    'swipe-frame-${(frame++).toString().padLeft(3, '0')}',
    pixelRatio: 1,
  );
  await capture();
  final gesture = await tester.startGesture(tester.getCenter(card));
  await gesture.moveBy(const Offset(-24, 0));
  for (var index = 0; index < 20; index++) {
    await gesture.moveBy(const Offset(-3.6, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await capture();
  }
  await gesture.up();
  await tester.pumpAndSettle();
  await capture();
  await tester.tap(card);
  await tester.pump();
  for (var index = 0; index < 7; index++) {
    await tester.pump(const Duration(milliseconds: 30));
    await capture();
  }
  await tester.pumpAndSettle();
  await capture();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    final fontPath = Platform.environment['INVENTORY_FONT_PATH'];
    if (fontPath == null) return;
    final data = ByteData.sublistView(await File(fontPath).readAsBytes());
    for (final family in ['Arial', 'Roboto']) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'inventory fade reaches the screen bottom and end cards clear the system inset',
    (tester) async {
      for (final viewport in [
        (width: 320.0, height: 568.0, inset: 0.0),
        (width: 390.0, height: 844.0, inset: 34.0),
        (width: 430.0, height: 932.0, inset: 34.0),
        (width: 360.0, height: 640.0, inset: 24.0),
      ]) {
        final fixture = _InventoryFixture();
        addTearDown(fixture.dispose);
        fixture.rows = [
          for (var index = 1; index <= 24; index++)
            {
              ...stockJson(),
              'id': 'item-$index',
              'item_definition_name': 'Item $index',
            },
        ];
        await fixture.open(
          tester,
          width: viewport.width,
          height: viewport.height,
          bottomInset: viewport.inset,
          pageSize: 100,
        );
        expect(
          tester.getRect(find.byType(PageScrollFade)).bottom,
          closeTo(viewport.height, 0.1),
        );
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final lastCard = find.widgetWithText(InventoryItemTile, 'Item 24');
        expect(lastCard, findsOneWidget);
        final bounds = tester.getRect(lastCard);
        expect(
          bounds.top,
          greaterThan(tester.getRect(find.byType(PageScrollFade)).top),
        );
        expect(
          bounds.bottom,
          lessThanOrEqualTo(viewport.height - viewport.inset),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'short and reversed swipes cancel; long drags stay bounded and reveal a delete action without writing',
    (tester) async {
      final fixture = _InventoryFixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester);
      final card = find.byType(SwipeDeleteCard).first;
      await _captureSwipeAnimation(tester, card);
      final content = find
          .descendant(of: card, matching: find.byType(InventoryItemTile))
          .first;
      final initial = tester.getTopLeft(content);
      await tester.drag(card, const Offset(-24, 0));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.getTopLeft(content), initial);
      final reverse = await tester.startGesture(tester.getCenter(card));
      await reverse.moveBy(const Offset(-140, 0));
      await tester.pump();
      await reverse.moveBy(const Offset(160, 0));
      await reverse.up();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final drag = await tester.startGesture(tester.getCenter(card));
      await drag.moveBy(const Offset(-24, 0));
      await drag.moveBy(const Offset(-24, 0));
      await tester.pump();
      await _capture(tester, 'swipe-during-drag');
      await drag.moveBy(const Offset(-200, 0));
      await tester.pump();
      final travel = initial.dx - tester.getTopLeft(content).dx;
      expect(travel, greaterThan(30));
      expect(travel, lessThanOrEqualTo(72));
      expect(find.byType(AlertDialog), findsNothing);
      await drag.moveBy(const Offset(-200, 0));
      await tester.pump();
      expect(initial.dx - tester.getTopLeft(content).dx, closeTo(travel, 0.1));
      await drag.up();
      await tester.pumpAndSettle();
      await _capture(tester, 'swipe-revealed');
      expect(find.byType(AlertDialog), findsNothing);
      expect(fixture.writes, isEmpty);
      await tester.tap(find.byKey(const Key('swipe-delete-action')).first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(fixture.writes, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(content), initial);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'left swipe reveals delete, tapping confirms, and pending writes preserve the card',
    (tester) async {
      final fixture = _InventoryFixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester);
      final card = find.byType(SwipeDeleteCard).first;
      await tester.drag(card, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(fixture.writes, isEmpty);
      await tester.tap(find.byKey(const Key('swipe-delete-action')).first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(fixture.writes, isEmpty);
      expect(find.text('Milk'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixture.writes, isEmpty);
      fixture.pending = Completer<void>();
      await tester.drag(card, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(fixture.writes, isEmpty);
      await tester.tap(find.byKey(const Key('swipe-delete-action')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm delete'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(fixture.writes, hasLength(1));
      expect(find.text('Milk'), findsOneWidget);
      fixture.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsNothing);
      expect(find.text('Eggs'), findsOneWidget);
      expect(fixture.writes.single['items'], [
        {'id': 'item-1', 'expected_version': 1},
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'header delete selects cards and sends a single atomic request on a narrow screen',
    (tester) async {
      final fixture = _InventoryFixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester, width: 320);
      await tester.tap(find.byTooltip('Delete items'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(4));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('batch-delete-confirm')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('batch-delete-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(fixture.writes, isEmpty);
      await tester.tap(find.byTooltip('Delete items'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await _capture(tester, 'batch-selection-320');
      await tester.tap(find.byKey(const Key('batch-delete-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.writes, isEmpty);
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('batch-delete-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm delete'));
      await tester.pumpAndSettle();
      expect(fixture.writes, hasLength(1));
      expect((fixture.writes.single['items'] as List).length, 2);
      expect(find.text('Your inventory is empty'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final failure in ['conflict', 'lost response']) {
    testWidgets(
      '$failure preserves cards and blocks deletion until an explicit reload',
      (tester) async {
        final fixture = _InventoryFixture()..failure = failure;
        addTearDown(fixture.dispose);
        await fixture.open(tester);
        await tester.tap(find.byTooltip('Delete items'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('batch-delete-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm delete'));
        await tester.pumpAndSettle();
        expect(fixture.writes, hasLength(1));
        expect(find.text('Milk'), findsOneWidget);
        expect(find.text('Eggs'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.ancestor(
                  of: find.byTooltip('Delete items'),
                  matching: find.byType(IconButton),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(find.text('Reload inventory'), findsOneWidget);
        fixture.failure = null;
        await tester.tap(find.text('Reload inventory'));
        await tester.pumpAndSettle();
        expect(fixture.writes, hasLength(1));
        expect(find.text('Reload inventory'), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.ancestor(
                  of: find.byTooltip('Delete items'),
                  matching: find.byType(IconButton),
                ),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'batch selection survives pagination while storage and category filters are preserved',
    (tester) async {
      final fixture = _InventoryFixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester, pageSize: 1, filtered: true);
      await tester.tap(find.byTooltip('Delete items'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsNothing);
      expect(find.text('Eggs'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('batch-delete-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm delete'));
      await tester.pumpAndSettle();
      expect(fixture.writes.single['items'], [
        {'id': 'item-1', 'expected_version': 1},
        {'id': 'item-2', 'expected_version': 3},
      ]);
      expect(
        fixture.reads.every(
          (query) =>
              query['storage_space_id'] == 'space-1' &&
              query['category_id'] == 'category-1',
        ),
        isTrue,
      );
      expect(fixture.controller.page, 1);
      expect(find.text('Your inventory is empty'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Select all deletes every page in All Spaces above 100 items', (
    tester,
  ) async {
    final fixture = _InventoryFixture();
    addTearDown(fixture.dispose);
    fixture.rows = [
      for (var index = 1; index <= 125; index++)
        {
          ...stockJson(),
          'id': 'item-$index',
          'storage_space_id': index.isEven ? 'space-1' : 'space-2',
        },
    ];
    await fixture.open(tester);
    await tester.tap(find.byTooltip('Delete items'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select-all')));
    await tester.pumpAndSettle();
    expect(find.text('125 selected'), findsOneWidget);
    await _capture(tester, 'batch-selection-411');
    expect(fixture.controller.page, 1);
    expect(fixture.controller.items, hasLength(20));
    expect(fixture.writes, isEmpty);
    await tester.tap(find.byKey(const Key('batch-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Delete 125 items?'), findsOneWidget);
    await tester.tap(find.text('Confirm delete'));
    await tester.pumpAndSettle();
    expect(fixture.writes.map((body) => (body['items'] as List).length), [
      100,
      25,
    ]);
    expect(fixture.rows, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Select all respects storage, search, category and date filters',
    (tester) async {
      final fixture = _InventoryFixture();
      addTearDown(fixture.dispose);
      final matching = {...stockJson(), 'expiry_date': '2026-10-08'};
      fixture.rows = [
        for (var index = 1; index <= 105; index++)
          {...matching, 'id': 'match-$index'},
        {...matching, 'id': 'other-space', 'storage_space_id': 'space-2'},
        {...matching, 'id': 'other-category', 'category_id': 'category-2'},
        {...matching, 'id': 'other-name', 'item_definition_name': 'Eggs'},
        {...matching, 'id': 'old-purchase', 'purchase_date': '2026-09-01'},
        {...matching, 'id': 'late-purchase', 'purchase_date': '2026-09-30'},
        {...matching, 'id': 'early-expiry', 'expiry_date': '2026-10-01'},
        {...matching, 'id': 'late-expiry', 'expiry_date': '2026-10-20'},
      ];
      await fixture.open(tester);
      await fixture.controller.loadInventory(
        storageSpaceId: 'space-1',
        query: 'milk',
        categoryId: 'category-1',
        purchaseFrom: DateTime(2026, 9, 15),
        purchaseTo: DateTime(2026, 9, 25),
        expiryFrom: DateTime(2026, 10, 5),
        expiryTo: DateTime(2026, 10, 10),
      );
      await tester.pumpAndSettle();
      fixture.reads.clear();
      await tester.tap(find.byTooltip('Delete items'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pumpAndSettle();
      expect(find.text('105 selected'), findsOneWidget);
      expect(fixture.reads, hasLength(2));
      for (final query in fixture.reads) {
        expect(query['storage_space_id'], 'space-1');
        expect(query['q'], 'milk');
        expect(query['category_id'], 'category-1');
        expect(query['purchase_from'], '2026-09-15');
        expect(query['purchase_to'], '2026-09-25');
        expect(query['expiry_from'], '2026-10-05');
        expect(query['expiry_to'], '2026-10-10');
      }
      await tester.tap(find.byKey(const Key('batch-delete-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm delete'));
      await tester.pumpAndSettle();
      expect(fixture.rows, hasLength(7));
      expect(
        fixture.rows.any((row) => (row['id'] as String).startsWith('match-')),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expired selection spans pages and excludes today and no expiry',
    (tester) async {
      final fixture = _InventoryFixture();
      addTearDown(fixture.dispose);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      fixture.rows = [
        for (final entry in [
          ('today', today),
          ('expired-1', today.subtract(const Duration(days: 1))),
          ('future', today.add(const Duration(days: 1))),
          ('expired-2', today.subtract(const Duration(days: 5))),
          ('no-expiry', null),
        ])
          {...stockJson(), 'id': entry.$1, 'expiry_date': dateInput(entry.$2)},
      ];
      fixture.rows.last['expiry_date'] = null;
      await fixture.open(tester, pageSize: 1, width: 320);
      await tester.tap(find.byTooltip('Delete items'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select-all-expired')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(
        tester.widget<Checkbox>(find.byKey(const Key('select-all'))).value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pumpAndSettle();
      expect(find.text('5 selected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('select-all-expired')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pumpAndSettle();
      expect(find.text('5 selected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('select-all-expired')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('batch-delete-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm delete'));
      await tester.pumpAndSettle();
      expect(
        (fixture.writes.single['items'] as List).map((item) => item['id']),
        ['expired-1', 'expired-2'],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed selection reads never produce a partial selection', (
    tester,
  ) async {
    final fixture = _InventoryFixture();
    addTearDown(fixture.dispose);
    fixture.rows = [
      for (var index = 1; index <= 101; index++)
        {...stockJson(), 'id': 'item-$index'},
    ];
    await fixture.open(tester);
    fixture.failedReadPage = 2;
    await tester.tap(find.byTooltip('Delete items'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select-all')));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('batch-delete-confirm')))
          .onPressed,
      isNull,
    );
    expect(fixture.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancel while selecting prevents a late response from selecting',
    (tester) async {
      final fixture = _InventoryFixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester);
      fixture.pendingRead = Completer<void>();
      await tester.tap(find.byTooltip('Delete items'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pump();
      expect(find.text('Selecting…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('batch-delete-cancel')));
      await tester.pump();
      fixture.pendingRead!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a later batch failure reports progress and blocks blind retries',
    (tester) async {
      final fixture = _InventoryFixture();
      addTearDown(fixture.dispose);
      fixture.rows = [
        for (var index = 1; index <= 125; index++)
          {...stockJson(), 'id': 'item-$index'},
      ];
      await fixture.open(tester);
      fixture.failure = 'conflict';
      fixture.failedWrite = 2;
      await tester.tap(find.byTooltip('Delete items'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('batch-delete-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm delete'));
      await tester.pumpAndSettle();
      expect(fixture.rows, hasLength(25));
      expect(find.text('25 selected'), findsOneWidget);
      expect(find.textContaining('100 items deleted.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('batch-delete-confirm')))
            .onPressed,
        isNull,
      );
      fixture.failure = null;
      await tester.tap(find.text('Reload inventory'));
      await tester.pumpAndSettle();
      expect(find.text('Reload inventory'), findsNothing);
      expect(fixture.writes, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}

class _InventoryFixture {
  _InventoryFixture() {
    api = ApiClient(client: MockClient(_request));
    final tokens = MemoryTokens();
    controller = InventoryController(
      InventoryRepository(InventoryApiService(api), tokens),
      workspace: WorkspaceRepository(api, tokens),
    );
  }

  late final ApiClient api;
  late final InventoryController controller;
  final writes = <Map<String, dynamic>>[];
  final reads = <Map<String, String>>[];
  List<Map<String, dynamic>> rows = [
    stockJson(),
    {...stockJson(version: 3), 'id': 'item-2', 'item_definition_name': 'Eggs'},
  ];
  Completer<void>? pending;
  Completer<void>? pendingRead;
  int? failedReadPage;
  int? failedWrite;
  String? failure;

  Future<http.Response> _request(http.Request request) async {
    if (request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      writes.add(body);
      if (failure == 'conflict' &&
          (failedWrite == null || failedWrite == writes.length)) {
        return jsonResponse({
          'detail': {
            'code': 'VERSION_CONFLICT',
            'message': 'Inventory has changed; refresh and retry',
          },
        }, 409);
      }
      if (failure == 'lost response') {
        rows.clear(); // The server committed, but its acknowledgement was lost.
        throw http.ClientException('Response lost');
      }
      if (pending != null) await pending!.future;
      final ids = (body['items'] as List).map((item) => item['id']).toSet();
      final archived = [
        for (final row in rows.where((row) => ids.contains(row['id'])))
          {
            ...row,
            'status': 'ARCHIVED',
            'version': (row['version'] as int) + 1,
          },
      ];
      rows.removeWhere((row) => ids.contains(row['id']));
      return jsonResponse({'items': archived, 'count': archived.length});
    }
    reads.add(request.url.queryParameters);
    final page = int.parse(request.url.queryParameters['page'] ?? '1');
    final pageSize = int.parse(
      request.url.queryParameters['page_size'] ?? '20',
    );
    if (pendingRead != null) await pendingRead!.future;
    if (failedReadPage == page) {
      return jsonResponse({'detail': 'Unable to load inventory'}, 500);
    }
    final query = request.url.queryParameters;
    final filtered = rows.where((row) {
      for (final field in ['storage_space_id', 'category_id', 'status']) {
        if (query[field] != null && row[field] != query[field]) return false;
      }
      if (query['q'] != null &&
          !(row['item_definition_name'] as String).toLowerCase().contains(
            query['q']!.toLowerCase(),
          )) {
        return false;
      }
      for (final field in ['purchase', 'expiry']) {
        final date = row['${field}_date'] as String?;
        final from = query['${field}_from'];
        final to = query['${field}_to'];
        if (from != null && (date == null || date.compareTo(from) < 0)) {
          return false;
        }
        if (to != null && (date == null || date.compareTo(to) > 0)) {
          return false;
        }
      }
      return true;
    }).toList();
    return jsonResponse({
      'items': filtered.skip((page - 1) * pageSize).take(pageSize).toList(),
      'total': filtered.length,
      'page': page,
      'page_size': pageSize,
    });
  }

  Future<void> open(
    WidgetTester tester, {
    double width = 411,
    double height = 820,
    double bottomInset = 0,
    int pageSize = 20,
    bool filtered = false,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.loadInventory(
      pageSize: pageSize,
      storageSpaceId: filtered ? 'space-1' : null,
      categoryId: filtered ? 'category-1' : null,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: _captureKey,
          child: InventoryScreen(controller: controller, onAddItemTap: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() {
    controller.dispose();
    api.close();
  }
}
