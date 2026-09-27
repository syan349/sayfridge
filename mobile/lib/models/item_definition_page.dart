import 'item_definition.dart';

class ItemDefinitionPage {
  const ItemDefinitionPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<ItemDefinition> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasNextPage => page * pageSize < total;

  factory ItemDefinitionPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'] as List<dynamic>;
    return ItemDefinitionPage(
      items: items
          .map((item) => ItemDefinition.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
