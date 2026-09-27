import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/widgets/home_greeting.dart';

void main() {
  testWidgets('uses the local greeting at every day-period boundary', (
    tester,
  ) async {
    for (final (hour, minute, greeting) in [
      (0, 0, 'Good evening!'),
      (4, 59, 'Good evening!'),
      (5, 0, 'Good morning!'),
      (11, 59, 'Good morning!'),
      (12, 0, 'Good afternoon!'),
      (16, 59, 'Good afternoon!'),
      (17, 0, 'Good evening!'),
      (23, 31, 'Good evening!'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeGreeting(now: () => DateTime(2026, 9, 27, hour, minute)),
        ),
      );
      expect(find.text(greeting), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('changes greeting at the next minute without reopening Home', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 27, 16, 59, 58);
    await tester.pumpWidget(MaterialApp(home: HomeGreeting(now: () => now)));
    expect(find.text('Good afternoon!'), findsOneWidget);

    now = DateTime(2026, 9, 27, 17);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Good evening!'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reads the device clock again when the app resumes', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 27, 23, 31);
    await tester.pumpWidget(MaterialApp(home: HomeGreeting(now: () => now)));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    now = DateTime(2026, 9, 28, 8);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Good morning!'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
