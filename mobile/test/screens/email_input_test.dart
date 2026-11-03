import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/auth_repository.dart';
import 'package:sayfridge/screens/sign_in_screen.dart';
import 'package:sayfridge/screens/sign_up_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/auth_api_service.dart';
import 'package:sayfridge/services/token_storage.dart';
import 'package:sayfridge/state/auth_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';
import 'package:sayfridge/widgets/auth_widgets.dart';

void main() {
  for (final signup in [false, true]) {
    for (final incremental in [false, true]) {
      testWidgets('email punctuation retained: signup=$signup incremental=$incremental', (tester) async {
        final api=ApiClient(client:MockClient((_) async {fail('Typing must not send a request');}));
        final auth=AuthController(AuthRepository(AuthApiService(api),const TokenStorage()));
        addTearDown(api.close);addTearDown(auth.dispose);
        await tester.pumpWidget(MaterialApp(theme:AppTheme.light,home:signup ? SignUpScreen(authController:auth) : SignInScreen(authController:auth)));
        final field=find.descendant(of:find.byKey(Key(signup?'sign-up-email':'sign-in-email')),matching:find.byType(TextFormField));
        await tester.ensureVisible(field);await tester.tap(field);await tester.pump();
        const email='qa_user.name+tag-2@example.com';
        if(incremental){
          for(var i=1;i<=email.length;i++){
            tester.testTextInput.updateEditingValue(TextEditingValue(text:email.substring(0,i),selection:TextSelection.collapsed(offset:i)));
            await tester.pump();
            expect(tester.widget<TextFormField>(field).controller!.text,email.substring(0,i));
          }
        }else{await tester.enterText(field,email);await tester.pump();}
        expect(tester.widget<TextFormField>(field).controller!.text,email);
        expect(validateEmail(email),isNull);
        expect(tester.takeException(),isNull);
      });
    }
  }
}
