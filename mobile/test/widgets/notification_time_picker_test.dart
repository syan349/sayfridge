import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/theme/app_theme.dart';
import 'package:sayfridge/widgets/notification_time_picker.dart';

void main() {
  for (final hour in [0, 12, 23]) {
    testWidgets('saving preserves $hour:37 across the 12-hour wheel', (
      tester,
    ) async {
      TimeOfDay? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showNotificationTimePicker(
                    context,
                    TimeOfDay(hour: hour, minute: 37),
                  );
                },
                child: const Text('Choose'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-notification-time')));
      await tester.pumpAndSettle();
      expect(result, TimeOfDay(hour: hour, minute: 37));
    });
  }

  testWidgets(
    'changing wheels and cancelling does not save; the sheet fits larger text on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TimeOfDay? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.25)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showNotificationTimePicker(
                    context,
                    const TimeOfDay(hour: 9, minute: 0),
                  );
                },
                child: const Text('Choose'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      tester
          .widget<CupertinoPicker>(
            find.byKey(const ValueKey('notification-hour')),
          )
          .scrollController!
          .jumpToItem(11);
      tester
          .widget<CupertinoPicker>(
            find.byKey(const ValueKey('notification-period')),
          )
          .scrollController!
          .jumpToItem(1);
      await tester.pumpAndSettle();
      expect(find.text('12:00 PM'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
