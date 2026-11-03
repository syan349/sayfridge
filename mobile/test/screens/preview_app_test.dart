import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/preview/preview_app.dart';
import 'package:sayfridge/preview/preview_session.dart';

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'auth_access_token': 'existing-real-session',
      'profile_preferences_real-user': '{"full_name":"Existing user"}',
    }),
  );

  testWidgets(
    'offline preview navigates, edits, logs out and reenters without touching real storage',
    (tester) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PreviewApp());
      await tester.pumpAndSettle();
      expect(find.text('UI PREVIEW · OFFLINE'), findsOneWidget);
      expect(find.text('Demo User'), findsOneWidget);
      expect(find.text('38 left'), findsOneWidget);

      await tester.tap(find.text('Edit Personal Information'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'Preview Alex',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Preview Alex'), findsOneWidget);

      for (final page in {
        'Change password': 'Current password',
        'Reminders Settings': 'Expiry reminders',
        'Voice Usage': '12 / 50',
      }.entries) {
        await tester.tap(find.text(page.key));
        await tester.pumpAndSettle();
        expect(find.text(page.value), findsOneWidget);
        expect(find.text('UI PREVIEW · OFFLINE'), findsOneWidget);
        await tester.tap(find.byKey(const Key('profile-back')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('8 items'), findsOneWidget);
      expect(find.text('Guest Mode'), findsNothing);
      expect(find.text('Log in / Sign up'), findsNothing);
      await tester.tap(find.text('AI Assistant'));
      await tester.pumpAndSettle();
      expect(find.text('Log in / Sign up'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Guest'), findsOneWidget);
      await tester.tap(find.text('Log in / Sign up'));
      await tester.pumpAndSettle();
      expect(find.text('Preview account'), findsOneWidget);
      await tester.tap(find.text('Enter preview'));
      await tester.pumpAndSettle();
      expect(find.text('Preview Alex'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(tester.takeException(), isNull);

      expect(await const FlutterSecureStorage().readAll(), {
        'auth_access_token': 'existing-real-session',
        'profile_preferences_real-user': '{"full_name":"Existing user"}',
      });
    },
  );

  testWidgets(
    'preview inventory supports details, filters and empty-state switching',
    (tester) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PreviewApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('8 items'), findsOneWidget);
      expect(find.text('Expiry overview'), findsOneWidget);
      await tester.tap(find.text('Chicken Thigh'));
      await tester.pumpAndSettle();
      expect(find.text('Item details'), findsOneWidget);
      expect(find.text('Chicken Thigh'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('All Spaces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pantry').last);
      await tester.pumpAndSettle();
      expect(find.text('2 items'), findsOneWidget);
      expect(find.text('No items expiring soon'), findsOneWidget);

      await tester.tap(find.byKey(const Key('preview-inventory-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty inventory'));
      await tester.pumpAndSettle();
      expect(find.text('All Spaces'), findsOneWidget);
      expect(find.text('0 items'), findsOneWidget);
      expect(find.text('Your inventory is empty'), findsOneWidget);
      expect(find.text('Expiry overview'), findsNothing);
      // Keep the empty-state message centered and the action at the section edge.
      expect(
        tester.getCenter(find.text('No items expiring soon')).dx,
        closeTo(205.5, 1),
      );
      final action = find.ancestor(
        of: find.text('View all items'),
        matching: find.byType(FilledButton),
      );
      expect(
        tester.getTopLeft(action).dx,
        closeTo(tester.getTopLeft(find.text('Inventory')).dx, 1),
      );

      await tester.tap(find.byKey(const Key('preview-inventory-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sample inventory (8 items)'));
      await tester.pumpAndSettle();
      expect(find.text('8 items'), findsOneWidget);
      expect(find.text('Your inventory is empty'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'preview data resets on a new session and never persists credentials',
    () async {
      final first = PreviewSession();
      await first.enter();
      await Future<void>.delayed(Duration.zero);
      expect(first.auth.user!.email, 'preview@example.com');
      await first.profile.saveIdentity(
        fullName: 'Local draft',
        avatarAsset: first.profile.preferences.avatarAsset,
      );
      expect(first.profile.displayName, 'Local draft');
      first.dispose();

      final second = PreviewSession();
      addTearDown(second.dispose);
      await second.enter();
      await Future<void>.delayed(Duration.zero);
      expect(second.profile.displayName, 'Demo User');
      expect(
        await const FlutterSecureStorage().read(key: 'auth_access_token'),
        'existing-real-session',
      );
    },
  );
}
