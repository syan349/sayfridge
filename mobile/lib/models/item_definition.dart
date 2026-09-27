class ItemDefinition {
  const ItemDefinition({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.status,
    required this.scope,
  });

  final String id;
  final String name;
  final String categoryId;
  final String status;
  final String scope;

  bool get isActive => status == 'ACTIVE';
  bool get isPrivate => scope == 'PRIVATE';

  factory ItemDefinition.fromJson(Map<String, dynamic> json) {
    return ItemDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['category_id'] as String,
      status: json['status'] as String,
      scope: json['scope'] as String,
    );
  }
}
