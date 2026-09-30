import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class NotificationStateRepository {
  const NotificationStateRepository([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  Future<String?> readDate(String userId, String type) =>
      _storage.read(key: 'notification_read_${userId}_$type');

  Future<void> saveDate(String userId, String type, String date) =>
      _storage.write(key: 'notification_read_${userId}_$type', value: date);
}
