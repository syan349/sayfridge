import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/main.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final dismissal in ['Cancel', 'Send link', 'outside', 'back']) {
    testWidgets('forgot password can close via $dismissal and reopen safely', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const SayFridgeApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log in / Sign up'));
      await tester.pumpAndSettle();

      final email = find.descendant(
        of: find.byKey(const Key('sign-in-email')),
        matching: find.byType(TextFormField),
      );
      final password = find.descendant(
        of: find.byKey(const Key('sign-in-password')),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(email, 'guest@example.com');
      await tester.enterText(password, 'Unsubmitted123');

      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.ensureVisible(find.text('Forgot password?'));
        await tester.tap(find.text('Forgot password?'));
        await tester.pumpAndSettle();
        expect(find.text('Recover password'), findsOneWidget);
        final resetField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        expect(
          tester.widget<TextField>(resetField).controller!.text,
          'guest@example.com',
        );
        await tester.enterText(resetField, 'reset@example.com');

        switch (dismissal) {
          case 'outside':
            await tester.tapAt(const Offset(12, 160));
          case 'back':
            await tester.binding.handlePopRoute();
          default:
            await tester.tap(find.text(dismissal));
        }
        // Exercise frames during dismissal, not just the settled route tree.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 75));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Sign in'), findsOneWidget);
        expect(
          tester.widget<TextFormField>(email).controller!.text,
          'guest@example.com',
        );
        expect(
          tester.widget<TextFormField>(password).controller!.text,
          'Unsubmitted123',
        );
      }
      await tester.tap(find.byKey(const Key('back-button')));
      await tester.pumpAndSettle();
      expect(find.text('Guest'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
