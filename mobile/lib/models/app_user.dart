class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String role;
  final String status;
  final DateTime createdAt;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}