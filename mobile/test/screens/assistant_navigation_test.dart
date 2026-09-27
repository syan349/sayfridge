import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/screens/ai_assistant_screen.dart';
import 'package:sayfridge/theme/app_theme.dart';

void main() {
  testWidgets('guest assistant Home returns home and login opens sign in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => navigatorKey.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => AiAssistantScreen(
                    isGuest: true,
                    onHomeTap: () => navigatorKey.currentState!.popUntil(
                      (route) => route.isFirst,
                    ),
                    onLoginTap: () => navigatorKey.currentState!.push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: Center(child: Text('Sign in route')),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('Open assistant'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open assistant'));
    await tester.pumpAndSettle();
    expect(find.text('AI Assistant'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Open assistant'), findsOneWidget);
    expect(find.text('Home page is coming next.'), findsNothing);

    await tester.tap(find.text('Open assistant'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Log in / Sign up'),
      find.byType(ListView),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log in / Sign up'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
