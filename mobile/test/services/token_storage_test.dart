import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/services/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('TokenStorage', () {
    test('returns null when no access token exists', () async {
      const tokenStorage = TokenStorage();

      final token = await tokenStorage.readAccessToken();

      expect(token, isNull);
    });

    test('saves and reads the access token', () async {
      const tokenStorage = TokenStorage();

      await tokenStorage.saveAccessToken('test-jwt-token');

      expect(
        await tokenStorage.readAccessToken(),
        'test-jwt-token',
      );
    });

    test('deletes the stored access token', () async {
      const tokenStorage = TokenStorage();

      await tokenStorage.saveAccessToken('test-jwt-token');
      await tokenStorage.deleteAccessToken();

      expect(await tokenStorage.readAccessToken(), isNull);
    });
  });
}