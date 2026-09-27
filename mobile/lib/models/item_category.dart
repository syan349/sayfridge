class ItemCategory {
  const ItemCategory({
    required this.id,
    required this.name,
    required this.status,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String status;
  final int sortOrder;

  bool get isActive => status == 'ACTIVE';

  factory ItemCategory.fromJson(Map<String, dynamic> json) {
    return ItemCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      status: json['status'] as String,
      sortOrder: json['sort_order'] as int,
    );
  }
}
