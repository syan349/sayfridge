import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local recent transcripts and any unacknowledged request; never tokens.
class AgentSessionStore {
  const AgentSessionStore([this.storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage storage;

  Future<Map<String, dynamic>?> read(String userId) async {
    final value = await storage.read(key: 'agent_session_$userId');
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  Future<void> write(String userId, Map<String, dynamic> value) =>
      storage.write(key: 'agent_session_$userId', value: jsonEncode(value));
}
