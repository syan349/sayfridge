import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/main.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Future<void> openSignInFromGuestHome(WidgetTester tester) async {
  await tester.pumpWidget(const SayFridgeApp());
  await tester.pumpAndSettle();

  final loginButton = find.text('Log in / Sign up');
  await tester.ensureVisible(loginButton);
  await tester.pumpAndSettle();
  await tester.tap(loginButton);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
  testWidgets('opens the account creation flow', (tester) async {
    await openSignInFromGuestHome(tester);

    expect(find.text('Sign in'), findsOneWidget);
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.byKey(const Key('sign-up-button')), findsOneWidget);
  });

  testWidgets('sign in validates empty credentials', (tester) async {
    await openSignInFromGuestHome(tester);

    await tester.tap(find.byKey(const Key('sign-in-button')));
    await tester.pump();

    expect(find.text('Please enter your email'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
  });

  testWidgets('avatar selection returns the chosen avatar', (tester) async {
    await openSignInFromGuestHome(tester);
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('choose one'));
    await tester.pumpAndSettle();

    expect(find.text('Choose your avatar'), findsOneWidget);
    final tomato = find.byKey(const Key('avatar-tomato'));
    await tester.ensureVisible(tomato);
    await tester.tap(tomato);
    final useAvatar = find.byKey(const Key('use-avatar-button'));
    await tester.ensureVisible(useAvatar);
    await tester.tap(useAvatar);
    await tester.pumpAndSettle();

    expect(find.text('Full Name'), findsOneWidget);
    expect(find.byKey(const Key('selected-avatar-tomato')), findsOneWidget);
  });
}
