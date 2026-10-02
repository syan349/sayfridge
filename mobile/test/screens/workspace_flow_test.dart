import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sayfridge/widgets/selection_field.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/models/inventory_item.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/stock_editor_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/api_exception.dart';
import 'package:sayfridge/widgets/business_forms.dart';
import '../support/integration_fixtures.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'metadata form submits only changed fields, not a rounded quantity',
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
          home: StockEditorScreen(
            workspace: WorkspaceRepository(api, MemoryTokens()),
            item: InventoryItem.fromJson(stockJson(amount: '1.567')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Notes (optional)'),
        'Opened',
      );
      final save = find.widgetWithText(FilledButton, 'Save changes');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.dragUntilVisible(
        save,
        find.byType(ListView).last,
        const Offset(0, -200),
      );
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(patch, {'expected_version': 1, 'notes': 'Opened'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new stock form allows creating a first space instead of dead-end empty state',
    (tester) async {
      final api = ApiClient(
        client: MockClient(
          (_) async => jsonResponse({
            'items': [],
            'total': 0,
            'page': 1,
            'page_size': 100,
          }),
        ),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: StockEditorScreen(
            workspace: WorkspaceRepository(api, MemoryTokens()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SelectionField).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage storage spaces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add storage space'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'non-idempotent lost-response write blocks resubmit and safely closes its form',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => businessForm(
                  context,
                  title: 'Create space',
                  fields: const [],
                  submit: (_) async {
                    calls++;
                    throw const ApiException(
                      statusCode: 0,
                      message: 'Response lost',
                    );
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls, 1);
      expect(find.textContaining('result may be unknown'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncertain quantity request freezes literal inputs for same-operation retry',
    (tester) async {
      final attempts = <Map<String, String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => businessForm(
                  context,
                  title: 'Add quantity',
                  idempotentRetry: true,
                  fields: const [
                    BusinessField('amount', 'Amount', initial: '2.00'),
                  ],
                  submit: (values) async {
                    attempts.add(Map.of(values));
                    if (attempts.length == 1) {
                      throw const ApiException(
                        statusCode: 0,
                        message: 'Lost response',
                      );
                    }
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(find.text('Retry same operation'));
      await tester.pumpAndSettle();
      expect(attempts, [
        {'amount': '2.00'},
        {'amount': '2.00'},
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
