import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/models/inventory_item.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/api_exception.dart';
import '../support/integration_fixtures.dart';

void main() {
  test(
    'batch archive sends one versioned request and refreshes only after a complete acknowledgement',
    () async {
      var refreshes = 0;
      final items = [
        InventoryItem.fromJson(stockJson()),
        InventoryItem.fromJson({...stockJson(version: 4), 'id': 'item-2'}),
      ];
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/inventory-items/batch-archive');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(jsonDecode(request.body), {
            'items': [
              {'id': 'item-1', 'expected_version': 1},
              {'id': 'item-2', 'expected_version': 4},
            ],
          });
          return jsonResponse({
            'count': 2,
            'items': [
              {...stockJson(version: 2), 'status': 'ARCHIVED'},
              {...stockJson(version: 5), 'id': 'item-2', 'status': 'ARCHIVED'},
            ],
          });
        }),
      );
      addTearDown(api.close);
      final repository = WorkspaceRepository(
        api,
        MemoryTokens(),
        onChanged: () async {
          refreshes++;
        },
      );
      await repository.archiveItems(items);
      expect(refreshes, 1);
    },
  );

  test(
    'batch archive rejects a partial acknowledgement and never automatically retries',
    () async {
      var calls = 0, refreshes = 0;
      final api = ApiClient(
        client: MockClient((_) async {
          calls++;
          return jsonResponse({'count': 0, 'items': []});
        }),
      );
      addTearDown(api.close);
      final repository = WorkspaceRepository(
        api,
        MemoryTokens(),
        onChanged: () async {
          refreshes++;
        },
      );
      await expectLater(
        repository.archiveItems([InventoryItem.fromJson(stockJson())]),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
      expect(calls, 1);
      expect(refreshes, 0);
      await expectLater(repository.archiveItems([]), throwsArgumentError);
      final item = InventoryItem.fromJson(stockJson());
      await expectLater(
        repository.archiveItems([item, item]),
        throwsArgumentError,
      );
      expect(calls, 1);
    },
  );
  test(
    'space archive and restore send zero body bytes with authentication',
    () async {
      final paths = <String>[];
      var refreshes = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.bodyBytes, isEmpty);
          expect(request.headers['Authorization'], 'Bearer test-token');
          paths.add(request.url.path);
          return jsonResponse({'id': 'space-1'});
        }),
      );
      addTearDown(api.close);
      final workspace = WorkspaceRepository(
        api,
        MemoryTokens(),
        onChanged: () async {
          refreshes++;
        },
      );
      await workspace.spaceState('space-1', 'archive');
      await workspace.spaceState('space-1', 'restore');
      expect(paths, [
        '/api/v1/storage-spaces/space-1/archive',
        '/api/v1/storage-spaces/space-1/restore',
      ]);
      expect(refreshes, 2);
    },
  );

  test(
    'metadata PATCH carries version and explicit null but no quantity/name',
    () async {
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(jsonDecode(request.body), {
            'expected_version': 7,
            'notes': 'Opened',
            'expiry_date': null,
          });
          return jsonResponse(stockJson(version: 8));
        }),
      );
      addTearDown(api.close);
      final saved = await WorkspaceRepository(api, MemoryTokens()).updateItem(
        InventoryItem.fromJson(stockJson(version: 7)),
        {'notes': 'Opened', 'expiry_date': null},
      );
      expect(saved.version, 8);
    },
  );

  test(
    'quantity retry preserves key and decimal literal; never auto-retries',
    () async {
      var calls = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          calls++;
          expect(request.headers['Idempotency-Key'], 'stable-key');
          expect(jsonDecode(request.body)['quantity_value'], '2.00');
          if (calls == 1) throw http.ClientException('response lost');
          return jsonResponse({
            'inventory': stockJson(version: 2),
            'replayed': true,
          });
        }),
      );
      addTearDown(api.close);
      final workspace = WorkspaceRepository(api, MemoryTokens());
      final body = {
        'expected_version': 1,
        'operation_type': 'ADD',
        'quantity_kind': 'AMOUNT',
        'quantity_value': '2.00',
        'quantity_unit': 'l',
      };
      await expectLater(
        workspace.quantityOperation('item-1', body, 'stable-key'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
      final saved = await workspace.quantityOperation(
        'item-1',
        body,
        'stable-key',
      );
      expect(saved.version, 2);
      expect(calls, 2);
    },
  );

  test('history accepts the documented top-level array', () async {
    final api = ApiClient(
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/inventory-items/item-1/operations');
        return jsonResponse([
          {'status': 'UNDONE', 'operation_type': 'ADD'},
        ]);
      }),
    );
    addTearDown(api.close);
    expect(
      (await WorkspaceRepository(
        api,
        MemoryTokens(),
      ).history('item-1')).single['status'],
      'UNDONE',
    );
  });

  test(
    'selectors fetch subsequent pages and do not treat a failed page as empty',
    () async {
      var count = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          count++;
          expect(request.url.queryParameters['page'], '$count');
          if (count == 2) return jsonResponse({'detail': 'Expired'}, 401);
          return jsonResponse({
            'items': [
              {'id': 'one'},
            ],
            'total': 2,
          });
        }),
      );
      addTearDown(api.close);
      await expectLater(
        WorkspaceRepository(api, MemoryTokens()).choices('storage-spaces'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      expect(count, 2);
    },
  );

  test('missing token prevents a write request', () async {
    final api = ApiClient(
      client: MockClient((_) async => throw StateError('Must not send')),
    );
    addTearDown(api.close);
    await expectLater(
      WorkspaceRepository(
        api,
        MemoryTokens()..token = null,
      ).saveSpace({'name': 'Fridge', 'type': 'FRIDGE'}),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'date validation rejects normalized impossible dates and amounts preserve precision',
    () {
      expect(validateDate('2026-02-30'), isNotNull);
      expect(validateDate('2028-02-29'), isNull);
      expect(validateAmount('1e3'), isNotNull);
      expect(validateAmount('0.0001'), isNotNull);
      expect(validateAmount('0'), isNotNull);
      expect(validateAmount('0', allowZero: true), isNull);
      expect(validateAmount('2.00'), isNull);
    },
  );
}
