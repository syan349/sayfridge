import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/inventory_repository.dart';
import 'package:sayfridge/repositories/storage_space_repository.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/inventory_api_service.dart';
import 'package:sayfridge/services/storage_space_api_service.dart';
import 'package:sayfridge/state/expiry_summary_controller.dart';
import 'package:sayfridge/state/inventory_controller.dart';
import 'package:sayfridge/state/storage_space_controller.dart';
import '../support/integration_fixtures.dart';

void main() {
  test(
    'sign-out reset ignores late authenticated business responses and clears filters',
    () async {
      final replies = <String, Completer<http.Response>>{};
      final requestsStarted = Completer<void>();
      final api = ApiClient(
        client: MockClient((request) {
          final reply = Completer<http.Response>();
          replies[request.url.path] = reply;
          if (replies.length == 3) requestsStarted.complete();
          return reply.future;
        }),
      );
      addTearDown(api.close);
      final tokens = MemoryTokens();
      final repository = InventoryRepository(InventoryApiService(api), tokens);
      final inventory = InventoryController(repository);
      final expiry = ExpirySummaryController(repository);
      final spaces = StorageSpaceController(
        StorageSpaceRepository(StorageSpaceApiService(api), tokens),
      );
      addTearDown(inventory.dispose);
      addTearDown(expiry.dispose);
      addTearDown(spaces.dispose);
      final loads = Future.wait([
        inventory.loadInventory(query: 'private', storageSpaceId: 'space-1'),
        expiry.loadSummary(asOf: DateTime(2026, 9, 27)),
        spaces.loadStorageSpaces(),
      ]);
      await requestsStarted.future;
      inventory.reset();
      expiry.reset();
      spaces.reset();
      tokens.token = null;
      for (final response in replies.values) {
        response.complete(jsonResponse({'detail': 'Old account error'}, 401));
      }
      await loads;
      expect(inventory.status, InventoryLoadStatus.initial);
      expect(inventory.items, isEmpty);
      expect(inventory.query, isEmpty);
      expect(inventory.storageSpaceId, isNull);
      expect(inventory.errorMessage, isNull);
      expect(expiry.status, ExpirySummaryLoadStatus.initial);
      expect(expiry.errorMessage, isNull);
      expect(spaces.status, StorageSpaceLoadStatus.initial);
      expect(spaces.errorMessage, isNull);
    },
  );
}
