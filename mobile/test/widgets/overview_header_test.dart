import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/widgets/inventory_visuals.dart';

void main() {
  testWidgets('overview titles stay centred, clear of Back, and Back navigates', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final width in [320.0, 411.0]) {
      tester.view.physicalSize = Size(width, 914);
      for (final scale in [1.0, 1.5]) {
        for (final title in ['Search', 'Inventory']) {
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          // Same loose horizontal constraints as the affected pages.
                          body: Column(
                            children: [
                              OverviewHeader(
                                title: title,
                                actionWidth: title == 'Inventory'
                                    ? (width < 360 ? 72 : 88)
                                    : 48,
                                actions: title != 'Inventory'
                                    ? null
                                    : Material(
                                        key: const Key('header-actions'),
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(28),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: IconButton(
                                                onPressed: () {},
                                                icon: const Icon(
                                                  Icons.add_circle_outline,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: IconButton(
                                                onPressed: () {},
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open page'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open page'));
          await tester.pumpAndSettle();

          final back = find.byTooltip('Back');
          final backBounds = tester.getRect(back);
          final titleBounds = tester.getRect(find.text(title));
          expect(backBounds.right, lessThanOrEqualTo(titleBounds.left));
          expect(titleBounds.center.dx, closeTo(width / 2, 0.1));
          if (title == 'Inventory') {
            expect(
              titleBounds.right,
              lessThanOrEqualTo(
                tester.getRect(find.byKey(const Key('header-actions'))).left +
                    0.1,
              ),
            );
          }
          expect(backBounds.center.dx, lessThan(width / 4));
          expect(tester.takeException(), isNull);

          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(find.text('Open page'), findsOneWidget);
          expect(find.text(title), findsNothing);
        }
      }
    }
  });
}
