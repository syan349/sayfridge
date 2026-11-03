import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/auth_repository.dart';
import 'package:sayfridge/screens/profile_screen.dart';
import 'package:sayfridge/screens/sign_in_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/auth_api_service.dart';
import 'package:sayfridge/services/token_storage.dart';
import 'package:sayfridge/state/auth_controller.dart';
import 'package:sayfridge/state/profile_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';

const user = {'id':'user-1','email':'user@example.com','role':'USER','status':'ACTIVE','created_at':'2026-10-01T00:00:00Z'};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final outcome in ['success', 'wrong', 'offline', 'expired']) {
    testWidgets('change password: $outcome through Profile and real auth layers', (tester) async {
      tester.view.physicalSize = const Size(480, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FlutterSecureStorage.setMockInitialValues({'auth_access_token':'old','auth_refresh_token':'refresh-old'});
      final pending = Completer<http.Response>();
      var changes = 0;
      var rotations = 0;
      final api = ApiClient(client: MockClient((req) async {
        if (req.url.path.endsWith('/me')) return http.Response(jsonEncode(user),200);
        if (req.url.path.endsWith('/refresh')) {
          rotations++;
          return http.Response(jsonEncode({'access_token':'renewed','refresh_token':'refresh-new','token_type':'bearer','expires_in':900,'user':user}),200);
        }
        expect(req.url.path, '/api/v1/auth/change-password');
        expect(jsonDecode(req.body), {'current_password':'OldPassword123','new_password':'NewPassword123'});
        changes++;
        if (outcome == 'expired' && changes == 1) return http.Response('{"detail":"expired"}',401);
        expect(req.headers['Authorization'], outcome == 'expired' ? 'Bearer renewed' : 'Bearer old');
        return pending.future;
      }));
      final repo = AuthRepository(AuthApiService(api), const TokenStorage());
      final auth = AuthController(repo);
      repo.onSessionExpired = auth.sessionExpired;
      await auth.initialize();
      final profile = ProfileController(auth);
      addTearDown(profile.dispose); addTearDown(auth.dispose); addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(theme:AppTheme.light, home: Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>ProfileScreen(authController:auth,profileController:profile,onAssistantTap:(){},onLoginTap:(){}))),child:const Text('Open Profile'))))));
      await tester.tap(find.text('Open Profile')); await tester.pumpAndSettle();
      // Match both the current label and the intended replacement during red/green.
      final entry = find.textContaining(RegExp(r'^(Password Reset|Change password|Password)$'));
      await tester.ensureVisible(entry); await tester.tap(entry); await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('profile-current-password')), 'OldPassword123');
      await tester.enterText(find.byKey(const Key('profile-new-password')), 'NewPassword123');
      await tester.enterText(find.byKey(const Key('profile-confirm-password')), 'NewPassword123');
      await tester.pump();
      final submit = find.byKey(const Key('profile-change-password'));
      await tester.ensureVisible(submit); await tester.tap(submit); await tester.pump();
      // Drive async HTTP callbacks without waiting for an outstanding spinner.
      for(var i=0;i<10;i++) { await tester.pump(const Duration(milliseconds:10)); }
      expect(changes, outcome == 'expired' ? 2 : 1);
      expect(tester.widget<FilledButton>(find.descendant(of:submit,matching:find.byType(FilledButton))).onPressed, isNull);
      if (outcome == 'wrong') {
        pending.complete(http.Response('{"detail":{"code":"CURRENT_PASSWORD_INCORRECT","message":"Current password is incorrect."}}',400));
      } else if (outcome == 'offline') {
        pending.completeError(http.ClientException('Offline'));
      } else { pending.complete(http.Response('',204)); }
      await tester.pumpAndSettle();
      if (outcome == 'wrong' || outcome == 'offline') {
        expect(auth.isAuthenticated,isTrue);
        expect(await const TokenStorage().readAccessToken(),'old');
        expect(find.byType(SignInScreen),findsNothing);
        expect(find.textContaining(outcome == 'wrong' ? 'Current password is incorrect' : 'could not confirm'),findsOneWidget);
      } else {
        expect(auth.isAuthenticated,isFalse);
        expect(await const TokenStorage().readAccessToken(),isNull);
        expect(await const TokenStorage().readRefreshToken(),isNull);
        expect(find.byType(SignInScreen),findsOneWidget);
        expect(find.text('Password changed. Please sign in with your new password.'),findsOneWidget);
        await tester.pageBack(); await tester.pumpAndSettle();
        expect(find.byType(ProfileScreen),findsNothing);
      }
      expect(rotations,outcome == 'expired' ? 1 : 0);
      expect(tester.takeException(),isNull);
    });
  }
}
