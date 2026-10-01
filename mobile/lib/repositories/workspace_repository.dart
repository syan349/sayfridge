import 'dart:math';

import '../models/inventory_item.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/token_storage.dart';

/// Manual business operations. Ownership, balances and versions remain server-owned.
class WorkspaceRepository {
  WorkspaceRepository(this.client, this.tokens, {this.onChanged});
  final ApiClient client;
  final TokenStorage tokens;
  final Future<void> Function()? onChanged;

  Future<T> _saved<T>(Future<T> request) async {
    final result = await request;
    // Refresh failures must not misreport a committed write as failed.
    try {
      await onChanged?.call();
    } catch (_) {
      /* Readers expose their own errors. */
    }
    return result;
  }

  Future<String> accessToken() async {
    final token = await tokens.readAccessToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        statusCode: 401,
        message: 'Please sign in again.',
      );
    }
    return token;
  }

  Future<List<Map<String, dynamic>>> choices(
    String resource, {
    String status = 'ACTIVE',
  }) async {
    // Fetch every page: a selector must not silently hide choices after item 20.
    final token = await accessToken();
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; ; page++) {
      final result = await client.getJson(
        '/$resource',
        accessToken: token,
        queryParameters: {
          'status': status,
          'page': '$page',
          'page_size': '100',
        },
      );
      final items = (result['items'] as List).cast<Map<String, dynamic>>();
      rows.addAll(items);
      if (rows.length >= (result['total'] as int) || items.isEmpty) return rows;
    }
  }

  Future<Map<String, dynamic>> saveSpace(
    Map<String, dynamic> body, {
    String? id,
  }) async {
    final token = await accessToken();
    return _saved(
      id == null
          ? client.postJson('/storage-spaces', body: body, accessToken: token)
          : client.patchJson(
              '/storage-spaces/$id',
              body: body,
              accessToken: token,
            ),
    );
  }

  Future<void> spaceState(String id, String action) async {
    // These endpoints reject {}, null JSON, and all other request bodies.
    await _saved(
      client.postJson(
        '/storage-spaces/$id/$action',
        accessToken: await accessToken(),
      ),
    );
  }

  Future<bool> spaceHasStock(String id) async {
    final result = await client.getJson(
      '/inventory-items',
      accessToken: await accessToken(),
      queryParameters: {
        'storage_space_id': id,
        'status': 'IN_STOCK',
        'page': '1',
        'page_size': '1',
      },
    );
    return (result['total'] as int) > 0;
  }

  Future<Map<String, dynamic>> createDefinition(
    String name,
    String categoryId,
  ) async => client.postJson(
    '/item-definitions',
    accessToken: await accessToken(),
    body: {'name': name.trim(), 'category_id': categoryId},
  );

  Future<InventoryItem> createStock(Map<String, dynamic> body) async =>
      InventoryItem.fromJson(
        await _saved(
          client.postJson(
            '/inventory-items',
            accessToken: await accessToken(),
            body: body,
          ),
        ),
      );

  Future<InventoryItem> updateItem(
    InventoryItem item,
    Map<String, dynamic> changes,
  ) async => InventoryItem.fromJson(
    await _saved(
      client.patchJson(
        '/inventory-items/${item.id}',
        accessToken: await accessToken(),
        body: {'expected_version': item.version, ...changes},
      ),
    ),
  );

  Future<InventoryItem> changeState(InventoryItem item, String action) async =>
      InventoryItem.fromJson(
        await _saved(
          client.postJson(
            '/inventory-items/${item.id}/$action',
            accessToken: await accessToken(),
            body: {'expected_version': item.version},
          ),
        ),
      );

  Future<InventoryItem> quantityOperation(
    String itemId,
    Map<String, dynamic> body,
    String key,
  ) async {
    final result = await _saved(
      client.postJson(
        '/inventory-items/$itemId/operations',
        accessToken: await accessToken(),
        body: body,
        headers: {'Idempotency-Key': key},
      ),
    );
    return InventoryItem.fromJson(result['inventory'] as Map<String, dynamic>);
  }

  /// Remove a selection from inventory using the server's atomic archive write.
  Future<void> archiveItems(List<InventoryItem> items) async {
    if (items.isEmpty ||
        items.length > 100 ||
        items.map((item) => item.id).toSet().length != items.length) {
      throw ArgumentError('Choose between 1 and 100 distinct inventory items.');
    }
    await _saved(_archiveItems(items));
  }

  Future<void> _archiveItems(List<InventoryItem> items) async {
    final response = await client.postJson(
      '/inventory-items/batch-archive',
      accessToken: await accessToken(),
      body: {
        'items': [
          for (final item in items)
            {'id': item.id, 'expected_version': item.version},
        ],
      },
    );
    final rows = (response['items'] as List)
        .map((row) => InventoryItem.fromJson(row as Map<String, dynamic>))
        .toList();
    final versions = {for (final item in items) item.id: item.version};
    if (response['count'] != items.length ||
        rows.length != items.length ||
        rows.map((row) => row.id).toSet().length != items.length ||
        rows.any(
          (row) =>
              !versions.containsKey(row.id) ||
              row.status != 'ARCHIVED' ||
              row.version != versions[row.id]! + 1,
        )) {
      throw const ApiException(
        statusCode: 0,
        code: 'INVALID_RESPONSE',
        message: 'Unable to verify the deletion response.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> history(String id) async => client.getList(
    '/inventory-items/$id/operations',
    accessToken: await accessToken(),
  );
}

String requestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String businessError(Object error) => error is ApiException
    ? (error.isUnauthorized
          ? 'Your session has expired. Please sign in again.'
          : error.message)
    : 'Unable to complete the request. Check the connection and try again.';

String dateInput(DateTime? date) => date == null
    ? ''
    : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String? validateDate(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  final value = input.trim();
  final date = DateTime.tryParse(value);
  return !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
          date == null ||
          date.year < 1 ||
          dateInput(date) != value
      ? 'Use a valid YYYY-MM-DD date.'
      : null;
}

String? validateAmount(String? input, {bool allowZero = false}) {
  final value = input?.trim() ?? '';
  if (!RegExp(r'^\d{1,9}(\.\d{1,3})?$').hasMatch(value) ||
      (!allowZero && double.parse(value) == 0)) {
    return allowZero
        ? 'Enter 0 or a positive amount (up to 3 decimals).'
        : 'Enter a positive amount (up to 3 decimals).';
  }
  return null;
}
