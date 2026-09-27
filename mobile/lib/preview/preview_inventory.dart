/// Read-only fixtures used exclusively by the offline debug entry point.
/// Dates are anchored to the session's local calendar day (including DST).
class PreviewInventory {
  PreviewInventory({DateTime? today}) : today = today ?? DateTime.now();

  final DateTime today;
  bool isEmpty = false;

  String _date(int offset) => DateTime(
    today.year,
    today.month,
    today.day + offset,
  ).toIso8601String().substring(0, 10);

  List<Map<String, dynamic>> get spaces => [
    for (final name in ['Fridge', 'Freezer', 'Pantry'])
      {
        'id': name.toLowerCase(),
        'name': name,
        'type': name.toUpperCase(),
        'status': 'ACTIVE',
        'created_at': '${_date(-5)}T00:00:00Z',
        'updated_at': '${_date(-5)}T00:00:00Z',
      },
  ];

  List<Map<String, dynamic>> get items => isEmpty
      ? []
      : [
          _item('chicken', 'Chicken Thigh', 'Meat', 'Fridge', 1, 'kg', 0),
          _item('milk', 'Milk', 'Dairy', 'Fridge', 1, 'L', 1),
          _item('salmon', 'Salmon', 'Seafood', 'Fridge', 500, 'g', 2),
          _item('tomatoes', 'Tomatoes', 'Vegetables', 'Pantry', 1, 'kg', 7),
          _item('broccoli', 'Broccoli', 'Vegetables', 'Fridge', 2, 'pcs', 5),
          _item('beef', 'Beef', 'Meat', 'Freezer', 500, 'g', 30),
          _item('eggs', 'Eggs', 'Dairy', 'Fridge', 6, 'pcs', 14),
          _item('apples', 'Apples', 'Fruit', 'Pantry', 4, 'pcs', 10),
        ];

  Map<String, dynamic> _item(
    String id,
    String name,
    String category,
    String space,
    num amount,
    String unit,
    int expiresIn,
  ) => {
    'id': id,
    'storage_space_id': space.toLowerCase(),
    'storage_space_name': space,
    'item_definition_id': 'definition-$id',
    'item_definition_name': name,
    'category_id': category.toLowerCase(),
    'category_name': category,
    'purchase_date': _date(-2),
    'expiry_date': _date(expiresIn),
    'notes': 'Offline UI preview sample. Not real inventory.',
    'status': 'IN_STOCK',
    'initial_amount': amount,
    'initial_unit': unit,
    'confirmed_current_amount': amount,
    'confirmed_current_unit': unit,
    'confirmed_at': '${_date(-2)}T00:00:00Z',
    'display_amount': amount,
    'display_unit': unit,
    'is_estimated': false,
    'version': 1,
    'created_at': '${_date(-2)}T00:00:00Z',
    'updated_at': '${_date(-2)}T00:00:00Z',
  };

  Iterable<Map<String, dynamic>> _filtered(Map<String, String> query) {
    return items.where((item) {
      for (final field in ['status', 'storage_space_id', 'category_id']) {
        if (query[field] != null && query[field] != item[field]) return false;
      }
      final name = (item['item_definition_name'] as String).toLowerCase();
      if (!name.contains((query['q'] ?? '').trim().toLowerCase())) return false;
      for (final field in ['purchase', 'expiry']) {
        final date = item['${field}_date'] as String;
        final from = query['${field}_from'];
        final to = query['${field}_to'];
        if (from != null && date.compareTo(from) < 0) return false;
        if (to != null && date.compareTo(to) > 0) return false;
      }
      return true;
    });
  }

  Map<String, dynamic> inventoryPage(Map<String, String> query) =>
      _page(_filtered(query), query);

  Map<String, dynamic> storagePage(Map<String, String> query) => _page(
    spaces.where(
      (space) => query['status'] == null || space['status'] == query['status'],
    ),
    query,
  );

  Map<String, dynamic> expirySummary(Map<String, String> query) {
    final asOf = query['as_of'] ?? _date(0);
    final date = DateTime.parse(asOf);
    final end = DateTime(
      date.year,
      date.month,
      date.day + (int.tryParse(query['days_before'] ?? '') ?? 3),
    ).toIso8601String().substring(0, 10);
    final counts = {'overdue': 0, 'today': 0, 'upcoming': 0};
    final entries = <Map<String, dynamic>>[];
    for (final item in _filtered(query)) {
      final expiry = item['expiry_date'] as String;
      if (expiry.compareTo(end) > 0) continue;
      final bucket = expiry.compareTo(asOf) < 0
          ? 'overdue'
          : expiry == asOf
          ? 'today'
          : 'upcoming';
      counts[bucket] = counts[bucket]! + 1;
      if (query['bucket'] == null || query['bucket'] == bucket) {
        entries.add({...item, 'bucket': bucket});
      }
    }
    entries.sort(
      (a, b) =>
          (a['expiry_date'] as String).compareTo(b['expiry_date'] as String),
    );
    return {'counts': counts, ..._page(entries, query)};
  }

  Map<String, dynamic> _page(
    Iterable<Map<String, dynamic>> records,
    Map<String, String> query,
  ) {
    final page = (int.tryParse(query['page'] ?? '') ?? 1).clamp(1, 10000);
    final size = (int.tryParse(query['page_size'] ?? '') ?? 20).clamp(1, 100);
    final list = records.toList();
    return {
      'items': list.skip((page - 1) * size).take(size).toList(),
      'total': list.length,
      'page': page,
      'page_size': size,
    };
  }
}
