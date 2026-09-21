import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/app_user.dart';

void main() {
  group('AppUser.fromJson', () {
    test('parses a backend user response', () {
      final user = AppUser.fromJson({
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'email': 'postman-demo@example.com',
        'role': 'USER',
        'status': 'ACTIVE',
        'created_at': '2026-09-11T00:00:00Z',
      });

      expect(user.id, '550e8400-e29b-41d4-a716-446655440000');
      expect(user.email, 'postman-demo@example.com');
      expect(user.role, 'USER');
      expect(user.status, 'ACTIVE');
      expect(user.createdAt, DateTime.utc(2026, 9, 11));
    });
  });
}