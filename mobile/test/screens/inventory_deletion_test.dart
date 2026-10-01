import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/inventory_repository.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/inventory_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/inventory_api_service.dart';
import 'package:sayfridge/state/inventory_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';
import 'package:sayfridge/widgets/swipe_delete_card.dart';
import 'package:sayfridge/widgets/inventory_visuals.dart';

import '../support/integration_fixtures.dart';

void main() {
  testWidgets(
    'short and reversed swipes cancel; long drags stay bounded and ask once on release',
    (tester) async {
      final fixture = _InventoryFixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester);
      final card = find.byType(SwipeDeleteCard).first;
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
      await drag.moveBy(const Offset(-200, 0));
      await tester.pump();
      final travel = initial.dx - tester.getTopLeft(content).dx;
      expect(travel, greaterThan(30));
      expect(travel, lessThanOrEqualTo(60));
      expect(find.byType(AlertDialog), findsNothing);
      await drag.moveBy(const Offset(-200, 0));
      await tester.pump();
      expect(initial.dx - tester.getTopLeft(content).dx, closeTo(travel, 0.1));
      await drag.up();
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
    'left swipe opens confirmation, cancel restores the card, and pending writes preserve it',
    (tester) async {
      final fixture = _InventoryFixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester);
      final card = find.byType(SwipeDeleteCard).first;
      await tester.drag(card, const Offset(-180, 0));
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
      expect(find.byType(Checkbox), findsNWidgets(3));
      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete items'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(fixture.writes, isEmpty);
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete items'));
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
        await tester.tap(find.byTooltip('Delete items'));
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
      await tester.tap(find.byTooltip('Delete items'));
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
  String? failure;

  Future<http.Response> _request(http.Request request) async {
    if (request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      writes.add(body);
      if (failure == 'conflict') {
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
    return jsonResponse({
      'items': rows.skip((page - 1) * pageSize).take(pageSize).toList(),
      'total': rows.length,
      'page': page,
      'page_size': pageSize,
    });
  }

  Future<void> open(
    WidgetTester tester, {
    double width = 411,
    int pageSize = 20,
    bool filtered = false,
  }) async {
    tester.view.physicalSize = Size(width, 820);
    tester.view.devicePixelRatio = 1;
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
        home: InventoryScreen(controller: controller, onAddItemTap: () {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() {
    controller.dispose();
    api.close();
  }
}
