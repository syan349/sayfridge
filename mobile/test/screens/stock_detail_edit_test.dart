import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/models/inventory_item.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/stock_editor_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/theme/app_theme.dart';
import '../support/integration_fixtures.dart';

Future<void> save(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  final button = find.widgetWithText(FilledButton, 'Save changes');
  await tester.dragUntilVisible(
    button,
    find.byType(ListView).last,
    const Offset(0, -250),
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final estimated in [false, true]) {
    testWidgets(
      'name and measured free-text units save together, original estimate: $estimated',
      (tester) async {
        Map<String, dynamic>? patch;
        final value = stockJson();
        if (estimated) {
          value.addAll({
            'is_estimated': true,
            'estimated_current_amount': '1.250',
            'estimated_current_unit': 'l',
            'estimated_at': '2026-09-24T10:00:00Z',
            'display_amount': '1.250',
          });
        }
        final api = ApiClient(
          client: MockClient((request) async {
            if (request.method == 'PATCH') {
              patch = jsonDecode(request.body) as Map<String, dynamic>;
              return jsonResponse(stockJson(version: 2));
            }
            return jsonResponse({
              'items': [
                {'id': 'space-1', 'name': 'Kitchen fridge'},
              ],
              'total': 1,
            });
          }),
        );
        addTearDown(api.close);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: StockEditorScreen(
              workspace: WorkspaceRepository(api, MemoryTokens()),
              item: InventoryItem.fromJson(value),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final quantity = find.byKey(const Key('item-quantity-input'));
        final unit = find.byKey(const Key('item-unit-input'));
        final name = find.byKey(const Key('item-name-input'));
        expect(tester.widget<TextFormField>(name).enabled, isTrue);
        TextField quantityField() => tester.widget<TextField>(
          find.descendant(of: quantity, matching: find.byType(TextField)),
        );
        expect(quantityField().readOnly, estimated);
        if (estimated) {
          expect(quantityField().decoration?.prefixText, '≈ ');
          await tester.ensureVisible(find.text('Exact'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Exact'));
          await tester.pumpAndSettle();
        }
        expect(quantityField().readOnly, isFalse);
        expect(quantityField().decoration?.prefixText, isNull);
        await tester.enterText(name, 'My milk');
        await tester.enterText(quantity, '4.25');
        await tester.enterText(unit, 'bowls');
        await save(tester);
        expect(patch, {
          'expected_version': 1,
          'item_name': 'My milk',
          'quantity': {'mode': 'EXACT', 'amount': '4.25', 'unit': 'bowls'},
        });
        expect(patch?.containsKey('created_at'), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'choosing estimate locks and resets the quantity without submitting typed estimate data',
    (tester) async {
      Map<String, dynamic>? patch;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'PATCH') {
            patch = jsonDecode(request.body) as Map<String, dynamic>;
            return jsonResponse(stockJson(version: 2));
          }
          return jsonResponse({
            'items': [
              {'id': 'space-1', 'name': 'Kitchen fridge'},
            ],
            'total': 1,
          });
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StockEditorScreen(
            workspace: WorkspaceRepository(api, MemoryTokens()),
            item: InventoryItem.fromJson(stockJson()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final quantity = find.byKey(const Key('item-quantity-input'));
      await tester.enterText(quantity, '9');
      await tester.ensureVisible(find.text('≈ AI estimate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('≈ AI estimate'));
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(
        find.descendant(of: quantity, matching: find.byType(TextField)),
      );
      expect(input.readOnly, isTrue);
      expect(input.controller?.text, '1.5');
      expect(input.decoration?.prefixText, '≈ ');
      final unit = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('item-unit-input')),
          matching: find.byType(TextField),
        ),
      );
      expect(unit.readOnly, isTrue);
      await save(tester);
      expect(patch, {
        'expected_version': 1,
        'quantity': {'mode': 'ESTIMATED'},
      });
      expect(tester.takeException(), isNull);
    },
  );
}
