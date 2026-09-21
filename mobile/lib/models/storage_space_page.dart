import 'storage_space.dart';

class StorageSpacePage {
  const StorageSpacePage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<StorageSpace> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasNextPage => page * pageSize < total;

  factory StorageSpacePage.fromJson(Map<String, dynamic> json) {
    final itemList = json['items'] as List<dynamic>;

    return StorageSpacePage(
      items: itemList
          .map(
            (item) => StorageSpace.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}