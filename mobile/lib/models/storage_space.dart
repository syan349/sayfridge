class StorageSpace {
  const StorageSpace({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String type;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == 'ACTIVE';

  factory StorageSpace.fromJson(Map<String, dynamic> json) {
    return StorageSpace(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}