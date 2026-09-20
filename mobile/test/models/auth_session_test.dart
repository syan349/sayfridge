import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/auth_session.dart';

void main() {
  group('AuthSession.fromJson', () {
    test('parses a backend login response', () {
      final session = AuthSession.fromJson({
        'access_token': 'example-jwt-token',
        'token_type': 'bearer',
        'expires_in': 900,
        'user': {
          'id': '550e8400-e29b-41d4-a716-446655440000',
          'email': 'postman-demo@example.com',
          'role': 'USER',
          'status': 'ACTIVE',
          'created_at': '2026-09-11T00:00:00Z',
        },
      });

      expect(session.accessToken, 'example-jwt-token');
      expect(session.tokenType, 'bearer');
      expect(session.expiresIn, 900);
      expect(session.user.email, 'postman-demo@example.com');
      expect(session.user.role, 'USER');
    });
  });
}