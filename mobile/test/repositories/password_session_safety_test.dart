import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/auth_repository.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/auth_api_service.dart';
import 'package:sayfridge/services/token_storage.dart';
import 'package:sayfridge/state/auth_controller.dart';

const _user = {'id':'u','email':'user@example.com','role':'USER','status':'ACTIVE','created_at':'2026-10-01T00:00:00Z'};
void main() {
  test('concurrent renewal without refresh ends session once and never sends HTTP', () async {
    final tokens=_Tokens()..refresh=null..clearGate=Completer<void>();
    final api=ApiClient(client:MockClient((req) async {fail('No refresh credential: no HTTP request allowed');}));
    final repo=AuthRepository(AuthApiService(api),tokens);
    var expired=0;repo.onSessionExpired=()=>expired++;
    addTearDown(api.close);
    final first=repo.renewAccess('old');await tokens.clearStarted.future;
    final second=repo.renewAccess('old');
    tokens.clearGate!.complete();
    expect(await first,isNull);expect(await second,isNull);
    expect(expired,1);expect(tokens.access,isNull);expect(tokens.refresh,isNull);
  });
  test('missing refresh ends memory auth even if secure clear fails persistently', () async {
    final tokens=_Tokens()..refresh=null..failures=99;
    final api=ApiClient(client:MockClient((req) async=>http.Response(jsonEncode(_user),200)));
    final repo=AuthRepository(AuthApiService(api),tokens);
    final auth=AuthController(repo);repo.onSessionExpired=auth.sessionExpired;
    addTearDown(api.close);addTearDown(auth.dispose);
    await auth.initialize();expect(auth.isAuthenticated,isTrue);
    expect(await repo.renewAccess('old'),isNull);expect(auth.isAuthenticated,isFalse);
  });
  test('failed in-flight renewal does not block confirmed server logout', () async {
    final tokens=_Tokens();final started=Completer<void>();final reply=Completer<http.Response>();
    var revoked=0;
    final api=ApiClient(client:MockClient((req) async {
      if(req.url.path.endsWith('/refresh')){started.complete();return reply.future;}
      expect(req.url.path.endsWith('/logout'),isTrue);revoked++;
      return http.Response('',204);
    }));
    final repo=AuthRepository(AuthApiService(api),tokens);addTearDown(api.close);
    final renewal=repo.renewAccess('old');
    final observed=expectLater(renewal,throwsA(isA<Exception>()));
    await started.future;
    final logout=repo.logout();
    reply.completeError(http.ClientException('Transient refresh failure'));
    await logout;await observed;
    expect(revoked,1);expect(tokens.access,isNull);expect(tokens.refresh,isNull);
  });
  for(final failures in [1, 99]) {
    test('confirmed change exits auth even if secure clear fails $failures times', () async {
      final tokens = _Tokens()..failures=failures;
      var revoked = false;
      final api = ApiClient(client: MockClient((request) async {
        if(request.url.path.endsWith('/change-password')) { revoked=true; return http.Response('',204); }
        return revoked ? http.Response('{"detail":"Revoked"}',401) : http.Response(jsonEncode(_user),200);
      }));
      final repo=AuthRepository(AuthApiService(api),tokens);
      final auth=AuthController(repo);
      repo.onSessionExpired=auth.sessionExpired;
      addTearDown(api.close);addTearDown(auth.dispose);
      await auth.initialize();expect(auth.isAuthenticated,isTrue);
      expect(await auth.changePassword(currentPassword:'OldPassword',newPassword:'NewPassword'),isTrue);
      expect(auth.isAuthenticated,isFalse);
      if(failures==1) {
        await repo.renewAccess('old');
        expect(tokens.access,isNull);expect(tokens.refresh,isNull);
      }
    });
  }
  test('revoked refresh ends in-memory auth when secure storage stays unavailable', () async {
    final tokens=_Tokens();var revoked=false;
    final api=ApiClient(client:MockClient((req) async => revoked ? http.Response('{"detail":"Revoked"}',401) : http.Response(jsonEncode(_user),200)));
    final repo=AuthRepository(AuthApiService(api),tokens);
    final auth=AuthController(repo);repo.onSessionExpired=auth.sessionExpired;
    addTearDown(api.close);addTearDown(auth.dispose);
    await auth.initialize();expect(auth.isAuthenticated,isTrue);
    revoked=true;tokens.failures=99;
    // A platform storage failure cannot keep a revoked session authenticated.
    try { await repo.renewAccess('old'); } catch (_) {}
    expect(auth.isAuthenticated,isFalse);
  });
  test('confirmed logout succeeds despite local secure clear failure', () async {
    final tokens=_Tokens()..failures=1;
    var revoked=false;
    final api=ApiClient(client:MockClient((req) async {
      if(req.url.path.endsWith('/logout')){revoked=true;return http.Response('',204);}
      return http.Response(jsonEncode(_user),200);
    }));
    final repo=AuthRepository(AuthApiService(api),tokens);
    final auth=AuthController(repo);addTearDown(api.close);addTearDown(auth.dispose);
    await auth.initialize();
    expect(await auth.logout(),isTrue);
    expect(revoked,isTrue);expect(auth.isAuthenticated,isFalse);
  });
  for(final blockSave in [false,true]) {
    test('refresh across change cannot restore credentials (save in flight: $blockSave)', () async {
      final tokens=_Tokens();
      final refreshStarted=Completer<void>(), changeStarted=Completer<void>();
      final refreshReply=Completer<http.Response>(), changeReply=Completer<http.Response>();
      final api=ApiClient(client:MockClient((req) async {
        if(req.url.path.endsWith('/refresh')){refreshStarted.complete();return refreshReply.future;}
        changeStarted.complete();return changeReply.future;
      }));
      addTearDown(api.close);
      final repo=AuthRepository(AuthApiService(api),tokens);
      final renewal=repo.renewAccess('old');await refreshStarted.future;
      if(blockSave){
        tokens.saveGate=Completer<void>();
        refreshReply.complete(http.Response(jsonEncode({'access_token':'rotated','refresh_token':'r-new','token_type':'bearer','expires_in':900,'user':_user}),200));
        await tokens.saveStarted.future;
      }
      final change=repo.changePassword(currentPassword:'OldPassword',newPassword:'NewPassword');await changeStarted.future;
      changeReply.complete(http.Response('',204));
      if(blockSave){tokens.saveGate!.complete();}
      else {refreshReply.complete(http.Response(jsonEncode({'access_token':'rotated','refresh_token':'r-new','token_type':'bearer','expires_in':900,'user':_user}),200));}
      await change;await renewal;
      expect(tokens.access,isNull);expect(tokens.refresh,isNull);
      expect(await repo.renewAccess('old'),isNull);
      expect(tokens.access,isNull);
    });
  }
}
class _Tokens extends TokenStorage {
  String? access='old',refresh='r-old';int failures=0;
  Completer<void>? saveGate,clearGate;final saveStarted=Completer<void>();final clearStarted=Completer<void>();
  @override Future<String?> readAccessToken() async=>access;
  @override Future<String?> readRefreshToken() async=>refresh;
  @override Future<void> saveSession(String a,String? r) async {
    if(!saveStarted.isCompleted)saveStarted.complete();
    if(saveGate!=null)await saveGate!.future;
    access=a;refresh=r;
  }
  @override Future<void> clearSession() async {
    if(!clearStarted.isCompleted)clearStarted.complete();
    if(clearGate!=null)await clearGate!.future;
    if(failures>0){failures--;throw StateError('Secure storage unavailable');}
    access=null;refresh=null;
  }
}
