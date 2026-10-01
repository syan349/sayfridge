import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/widgets/selection_field.dart';

void main() {
  testWidgets(
    'selection sheet preserves cancellation, validates and follows dependent choices',
    (tester) async {
      final form = GlobalKey<FormState>();
      String? selected;
      var dependent = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Form(
                  key: form,
                  child: SelectionField(
                    label: 'Type',
                    value: selected,
                    options: dependent
                        ? {'PANTRY': 'Pantry'}
                        : {'FRIDGE': 'Fridge', 'FREEZER': 'Freezer'},
                    validator: (value) =>
                        value == null ? 'Choose a type' : null,
                    onChanged: (value) => setState(() => selected = value),
                  ),
                );
              },
            ),
          ),
        ),
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Choose a type'), findsOneWidget);
      await tester.tap(find.byType(SelectionField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Freezer'));
      await tester.pumpAndSettle();
      expect(selected, 'FREEZER');
      expect(form.currentState!.validate(), isTrue);
      await tester.tap(find.byType(SelectionField));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(selected, 'FREEZER');
      rebuild(() {
        dependent = true;
        selected = null;
      });
      await tester.pump();
      expect(find.text('Freezer'), findsNothing);
      expect(form.currentState!.validate(), isFalse);
      await tester.tap(find.byType(SelectionField));
      await tester.pumpAndSettle();
      expect(find.text('Freezer'), findsNothing);
      await tester.tap(find.text('Pantry'));
      await tester.pumpAndSettle();
      expect(selected, 'PANTRY');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long option lists remain reachable on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionField(
            label: 'Item',
            options: {for (var i = 0; i < 40; i++) '$i': 'Custom item $i'},
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(SelectionField));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Custom item 39'), 250);
    await tester.tap(find.text('Custom item 39'));
    await tester.pumpAndSettle();
    expect(selected, '39');
    expect(tester.takeException(), isNull);
  });
}
