import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/inventory_item.dart';
import 'package:sayfridge/preview/preview_session.dart';
import 'package:sayfridge/theme/app_theme.dart';
import 'package:sayfridge/widgets/expiry_display_scope.dart';
import 'package:sayfridge/widgets/inventory_visuals.dart';

import '../support/integration_fixtures.dart';

void main() {
  testWidgets(
    'changing reminder days recolours both quantity types at the boundary',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = PreviewSession();
      addTearDown(session.dispose);
      await session.enter();
      await tester.pump();
      expect(await session.profile.saveReminders(daysBeforeExpiry: 2), isTrue);
      final expiry = DateUtils.dateOnly(
        DateTime.now(),
      ).add(const Duration(days: 3));
      final items = [
        for (final estimated in [false, true])
          InventoryItem.fromJson({
            ...stockJson(),
            'id': estimated ? 'estimated-batch' : 'exact-batch',
            'is_estimated': estimated,
            'expiry_date': expiry.toIso8601String(),
          }),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ExpiryDisplayScope(
            controller: session.profile,
            child: Scaffold(
              body: Column(
                children: [
                  for (final item in items)
                    InventoryItemTile(item: item, onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final labels = find.text('3 days left');
      expect(labels, findsNWidgets(2));
      expect(
        tester.widgetList<Text>(labels).map((text) => text.style?.color),
        everyElement(const Color(0xFF388D38)),
      );
      final quantities = items.map(quantityLabel).toList();
      final quantityColours = [
        for (final label in quantities)
          tester.widget<Text>(find.text(label)).style?.color,
      ];
      // The exact threshold is inclusive, and existing cards update immediately.
      expect(await session.profile.saveReminders(daysBeforeExpiry: 3), isTrue);
      await tester.pumpAndSettle();
      expect(
        tester.widgetList<Text>(labels).map((text) => text.style?.color),
        everyElement(const Color(0xFFE75030)),
      );
      expect([
        for (final label in quantities)
          tester.widget<Text>(find.text(label)).style?.color,
      ], quantityColours);
      expect(tester.takeException(), isNull);
    },
  );
}
