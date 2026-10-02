import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/widgets/selection_field.dart';

void main() {
  testWidgets(
    'typed categories reuse existing IDs and choices are alphabetical',
    (tester) async {
      String? selected;
      var creates = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionField(
              label: 'Category',
              options: {'z': 'Vegetables', 'f': 'Fruit', 'd': 'Dairy'},
              sortAlphabetically: true,
              onCreateOption: (name) async {
                creates++;
                return 'new-category';
              },
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SelectionField));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Dairy')).dy,
        lessThan(tester.getTopLeft(find.text('Fruit')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Fruit')).dy,
        lessThan(tester.getTopLeft(find.text('Vegetables')).dy),
      );
      await tester.enterText(
        find.byKey(const Key('category-name-input')),
        '  FRUIT  ',
      );
      await tester.tap(find.byTooltip('Use category'));
      await tester.pumpAndSettle();
      expect(selected, 'f');
      expect(creates, 0);
      await tester.tap(find.byType(SelectionField));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('category-name-input')),
        'Baking',
      );
      await tester.tap(find.byTooltip('Use category'));
      await tester.pumpAndSettle();
      expect(selected, 'new-category');
      expect(creates, 1);
    },
  );

  testWidgets('space management opens without replacing the chosen space', (
    tester,
  ) async {
    var manages = 0;
    String? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionField(
            label: 'Storage space',
            value: 'fridge',
            options: {'fridge': 'Fridge'},
            onChanged: (value) => changed = value,
            onManage: () async => manages++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(SelectionField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage storage spaces'));
    await tester.pumpAndSettle();
    expect(manages, 1);
    expect(changed, isNull);
    expect(find.text('Choose storage space'), findsNothing);
    expect(find.text('Fridge'), findsOneWidget);
  });

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
    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom item 39'));
    await tester.pumpAndSettle();
    expect(selected, '39');
    expect(tester.takeException(), isNull);
  });
}
