import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/main.dart';
import 'package:sayfridge/screens/sign_in_screen.dart';
import 'package:sayfridge/screens/password_reset_screen.dart';
import 'package:sayfridge/screens/profile_screen.dart';
import 'package:sayfridge/screens/home_screen.dart';

const user={'id':'u','email':'user@example.com','role':'USER','status':'ACTIVE','created_at':'2026-10-01T00:00:00Z'};
void main(){
 for(final goBack in [true,false]){
 testWidgets('full app same-frame change navigation, back=$goBack',(tester) async {
  tester.view.physicalSize=const Size(480,1100);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  FlutterSecureStorage.setMockInitialValues({'auth_access_token':'old','auth_refresh_token':'r-old'});
  var changed=false;
  final client=MockClient((req)async{
   if(req.url.path.endsWith('/me'))return http.Response(jsonEncode(user),200);
   if(req.url.path.endsWith('/change-password')){changed=true;return http.Response('',204);}
   if(req.url.path.endsWith('/login')){
    expect(changed,isTrue);expect(jsonDecode(req.body)['password'],'NewPassword123');
    return http.Response(jsonEncode({'access_token':'new','refresh_token':'r-new','token_type':'bearer','expires_in':900,'user':user}),200);
   }
   return http.Response('{"total":0,"items":[]}',200);
  });
  await http.runWithClient(()async{
   await tester.pumpWidget(const SayFridgeApp());await tester.pumpAndSettle();
   await tester.tap(find.text('Profile').last);await tester.pumpAndSettle();
   await tester.ensureVisible(find.text('Change password'));await tester.tap(find.text('Change password'));await tester.pumpAndSettle();
   await tester.enterText(find.byKey(const Key('profile-current-password')),'OldPassword123');
   await tester.enterText(find.byKey(const Key('profile-new-password')),'NewPassword123');
   await tester.enterText(find.byKey(const Key('profile-confirm-password')),'NewPassword123');await tester.pump();
   await tester.ensureVisible(find.byKey(const Key('profile-change-password')));await tester.tap(find.byKey(const Key('profile-change-password')));await tester.pumpAndSettle();
   expect(find.byType(SignInScreen),findsOneWidget);
   expect(find.text('Password changed. Please sign in with your new password.'),findsOneWidget);
   expect(find.byType(PasswordResetScreen),findsNothing);expect(find.byType(ProfileScreen),findsNothing);
   if(goBack){
    await tester.pageBack();await tester.pumpAndSettle();
    expect(find.byType(SignInScreen),findsNothing);expect(tester.widget<HomeScreen>(find.byType(HomeScreen)).isGuest,isTrue);
   }else{
    await tester.enterText(find.byKey(const Key('sign-in-email')),'user@example.com');
    await tester.enterText(find.byKey(const Key('sign-in-password')),'NewPassword123');
    await tester.ensureVisible(find.byKey(const Key('sign-in-button')));await tester.tap(find.byKey(const Key('sign-in-button')));await tester.pumpAndSettle();
    expect(find.byType(SignInScreen),findsNothing);expect(tester.widget<HomeScreen>(find.byType(HomeScreen)).isGuest,isFalse);
   }
   expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox.shrink());await tester.pumpAndSettle();
  },()=>client);
 });
 }
}
