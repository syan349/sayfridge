import 'item_category.dart';

class ItemCategoryPage {
  const ItemCategoryPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<ItemCategory> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasNextPage => page * pageSize < total;

  factory ItemCategoryPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'] as List<dynamic>;
    return ItemCategoryPage(
      items: items
          .map((item) => ItemCategory.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
