import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/storage_space_page.dart';

void main() {
  group('StorageSpacePage.fromJson', () {
    test('parses a page containing storage spaces', () {
      final storageSpacePage = StorageSpacePage.fromJson({
        'items': [
          {
            'id': 'space-1',
            'name': 'Kitchen fridge',
            'type': 'FRIDGE',
            'status': 'ACTIVE',
            'created_at': '2026-09-21T01:00:00Z',
            'updated_at': '2026-09-21T02:00:00Z',
          },
        ],
        'total': 25,
        'page': 1,
        'page_size': 20,
      });

      expect(storageSpacePage.items, hasLength(1));
      expect(storageSpacePage.items.first.name, 'Kitchen fridge');
      expect(storageSpacePage.total, 25);
      expect(storageSpacePage.page, 1);
      expect(storageSpacePage.pageSize, 20);
      expect(storageSpacePage.hasNextPage, isTrue);
    });

    test('parses an empty final page', () {
      final storageSpacePage = StorageSpacePage.fromJson({
        'items': [],
        'total': 20,
        'page': 2,
        'page_size': 20,
      });

      expect(storageSpacePage.items, isEmpty);
      expect(storageSpacePage.hasNextPage, isFalse);
    });
  });
}