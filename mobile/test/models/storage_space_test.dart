import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/storage_space.dart';

void main() {
  group('StorageSpace.fromJson', () {
    test('parses an active storage space response', () {
      final storageSpace = StorageSpace.fromJson({
        'id': 'space-1',
        'name': 'Kitchen fridge',
        'type': 'FRIDGE',
        'status': 'ACTIVE',
        'created_at': '2026-09-21T01:00:00Z',
        'updated_at': '2026-09-21T02:00:00Z',
      });

      expect(storageSpace.id, 'space-1');
      expect(storageSpace.name, 'Kitchen fridge');
      expect(storageSpace.type, 'FRIDGE');
      expect(storageSpace.status, 'ACTIVE');
      expect(storageSpace.isActive, isTrue);
      expect(
        storageSpace.createdAt,
        DateTime.utc(2026, 9, 21, 1),
      );
      expect(
        storageSpace.updatedAt,
        DateTime.utc(2026, 9, 21, 2),
      );
    });

    test('reports an archived storage space as inactive', () {
      final storageSpace = StorageSpace.fromJson({
        'id': 'space-2',
        'name': 'Old freezer',
        'type': 'FREEZER',
        'status': 'ARCHIVED',
        'created_at': '2026-09-20T01:00:00Z',
        'updated_at': '2026-09-21T02:00:00Z',
      });

      expect(storageSpace.isActive, isFalse);
    });
  });
}