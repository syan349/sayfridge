import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/models/inventory_item.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/widgets/inventory_actions.dart';

import '../support/integration_fixtures.dart';

void main() {
  testWidgets('expired item offers discard and an explicit used-up action', (
    tester,
  ) async {
    var reloads = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/inventory-items/item-1/operations');
        expect(jsonDecode(request.body), {
          'expected_version': 1,
          'operation_type': 'RECONCILE',
          'quantity_kind': 'AMOUNT',
          'quantity_value': '0',
          'quantity_unit': 'l',
        });
        return jsonResponse({
          'inventory': stockJson(version: 2, amount: '0'),
          'replayed': false,
        });
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryActions(
            item: InventoryItem.fromJson(stockJson()),
            workspace: WorkspaceRepository(api, MemoryTokens()),
            reload: () async => reloads++,
          ),
        ),
      ),
    );

    expect(find.text('Discard expired item'), findsOneWidget);
    expect(find.text('Mark as used up'), findsOneWidget);

    await tester.tap(find.text('Mark as used up'));
    await tester.pumpAndSettle();
    expect(find.text('Mark this item as used up?'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(reloads, 1);
  });

  testWidgets('empty item no longer offers discard or used-up actions', (
    tester,
  ) async {
    final json = stockJson(amount: '0')..['status'] = 'EMPTY';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryActions(
            item: InventoryItem.fromJson(json),
            workspace: null,
            reload: () async {},
          ),
        ),
      ),
    );

    expect(find.text('Discard item'), findsNothing);
    expect(find.text('Discard expired item'), findsNothing);
    expect(find.text('Mark as used up'), findsNothing);
  });
}
