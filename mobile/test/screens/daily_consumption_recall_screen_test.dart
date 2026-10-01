import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/screens/daily_consumption_recall_screen.dart';
import 'package:sayfridge/theme/app_theme.dart';

void main() {
  testWidgets('daily recall requires usage before continuing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const DailyConsumptionRecallScreen(),
      ),
    );

    expect(find.text('What did you use today?'), findsOneWidget);
    expect(find.text('Meals and cooking'), findsOneWidget);
    expect(find.text('Snacks and drinks'), findsOneWidget);
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Anything finished?'),
      180,
      scrollable: page,
    );
    expect(find.text('Anything finished?'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('review-daily-consumption')),
      180,
      scrollable: page,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('review-daily-consumption')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('daily recall returns the trimmed usage summary', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) => const DailyConsumptionRecallScreen(),
                  ),
                );
              },
              child: const Text('Open recall'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open recall'));
    await tester.pumpAndSettle();
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('daily-consumption-input')),
      180,
      scrollable: page,
    );
    await tester.enterText(
      find.byKey(const Key('daily-consumption-input')),
      '  3 eggs and 250 ml of milk  ',
    );
    await tester.pump();
    await tester.tap(find.text('Review with AI'));
    await tester.pumpAndSettle();

    expect(result, '3 eggs and 250 ml of milk');
  });
}
