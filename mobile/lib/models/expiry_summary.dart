import 'inventory_item.dart';

class ExpiryCounts {
  const ExpiryCounts({
    required this.overdue,
    required this.today,
    required this.upcoming,
  });

  final int overdue;
  final int today;
  final int upcoming;

  int get total => overdue + today + upcoming;

  factory ExpiryCounts.fromJson(Map<String, dynamic> json) {
    return ExpiryCounts(
      overdue: json['overdue'] as int,
      today: json['today'] as int,
      upcoming: json['upcoming'] as int,
    );
  }
}

class ExpirySummaryItem {
  const ExpirySummaryItem({required this.item, required this.bucket});

  final InventoryItem item;
  final String bucket;

  factory ExpirySummaryItem.fromJson(Map<String, dynamic> json) {
    return ExpirySummaryItem(
      item: InventoryItem.fromJson(json),
      bucket: json['bucket'] as String,
    );
  }
}

class ExpirySummary {
  const ExpirySummary({
    required this.counts,
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final ExpiryCounts counts;
  final List<ExpirySummaryItem> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasNextPage => page * pageSize < total;

  factory ExpirySummary.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>;

    return ExpirySummary(
      counts: ExpiryCounts.fromJson(json['counts'] as Map<String, dynamic>),
      items: rawItems
          .map(
            (item) => ExpirySummaryItem.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
