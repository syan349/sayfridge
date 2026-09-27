import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sayfridge/services/agent_session_store.dart';
import 'package:sayfridge/services/token_storage.dart';

class MemoryTokens extends TokenStorage {
  String? token = 'test-token';
  @override
  Future<String?> readAccessToken() async => token;
}

class MemoryAgentStore extends AgentSessionStore {
  final Map<String, String> values = {};
  @override
  Future<Map<String, dynamic>?> read(String userId) async =>
      values[userId] == null
      ? null
      : jsonDecode(values[userId]!) as Map<String, dynamic>;
  @override
  Future<void> write(String userId, Map<String, dynamic> value) async {
    values[userId] = jsonEncode(value);
  }
}

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response eventResponse(List<Map<String, dynamic>> events) => http.Response(
  events
      .map((event) => 'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n')
      .join(),
  200,
  headers: {'content-type': 'text/event-stream; charset=utf-8'},
);

Map<String, dynamic> stockJson({int version = 1, String amount = '1.500'}) => {
  'id': 'item-1',
  'storage_space_id': 'space-1',
  'storage_space_name': 'Kitchen fridge',
  'item_definition_id': 'definition-1',
  'item_definition_name': 'Milk',
  'category_id': 'category-1',
  'category_name': 'Dairy',
  'purchase_date': '2026-09-20',
  'expiry_date': '2026-09-28',
  'notes': null,
  'status': 'IN_STOCK',
  'initial_amount': '2.000',
  'initial_unit': 'l',
  'confirmed_current_amount': amount,
  'confirmed_current_unit': 'l',
  'confirmed_at': '2026-09-23T10:00:00Z',
  'estimated_current_amount': null,
  'estimated_current_unit': null,
  'estimated_at': null,
  'display_amount': amount,
  'display_unit': 'l',
  'is_estimated': false,
  'version': version,
  'created_at': '2026-09-20T01:00:00Z',
  'updated_at': '2026-09-23T10:00:00Z',
};
