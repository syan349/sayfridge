import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/storage_space_repository.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/storage_space_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/storage_space_api_service.dart';
import 'package:sayfridge/state/storage_space_controller.dart';
import '../support/integration_fixtures.dart';

Map<String, dynamic> space(String id, bool isDefault) => {
  'id': id,
  'name': id,
  'type': 'FRIDGE',
  'status': 'ACTIVE',
  'is_default': isDefault,
  'created_at': '2026-10-01T00:00:00Z',
  'updated_at': '2026-10-01T00:00:00Z',
};

void main() {
  testWidgets(
    'default changes from A to B using the existing empty-body endpoint',
    (tester) async {
      var defaultId = 'A';
      var writes = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            expect(
              request.url.path.endsWith('/storage-spaces/B/default'),
              isTrue,
            );
            expect(request.bodyBytes, isEmpty);
            expect(request.headers['authorization'], 'Bearer test-token');
            defaultId = 'B';
            writes++;
            return jsonResponse(space('B', true));
          }
          return jsonResponse({
            'items': [
              space('A', defaultId == 'A'),
              space('B', defaultId == 'B'),
            ],
            'total': 2,
            'page': 1,
            'page_size': 20,
          });
        }),
      );
      final controller = await mount(tester, api);
      expect(controller.storageSpaces.where((s) => s.isDefault).single.id, 'A');
      await tester.tap(find.byTooltip('Set B as default'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(
        find.textContaining('only one space can be default'),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(controller.storageSpaces.where((s) => s.isDefault).single.id, 'B');
      expect(find.byTooltip('Set A as default'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in [
    'stock',
    'cancel',
    'confirm',
    'conflict',
    'read failure',
  ]) {
    testWidgets('archive handles $scenario without deleting records', (
      tester,
    ) async {
      var writes = 0;
      var archived = false;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/inventory-items')) {
            expect(request.url.queryParameters['storage_space_id'], 'A');
            expect(request.url.queryParameters['status'], 'IN_STOCK');
            expect(request.url.queryParameters['page_size'], '1');
            if (scenario == 'read failure') {
              return jsonResponse({
                'detail': {
                  'code': 'UNAVAILABLE',
                  'message': 'Cannot check stock',
                },
              }, 503);
            }
            return jsonResponse({
              'items': [],
              'total': scenario == 'stock' ? 1 : 0,
            });
          }
          if (request.method == 'POST') {
            writes++;
            expect(
              request.url.path.endsWith('/storage-spaces/A/archive'),
              isTrue,
            );
            expect(request.bodyBytes, isEmpty);
            if (scenario == 'conflict') {
              return jsonResponse({
                'detail': {
                  'code': 'STATE_CONFLICT',
                  'message': 'Storage space still contains in-stock inventory',
                },
              }, 409);
            }
            archived = true;
            return jsonResponse({...space('A', false), 'status': 'ARCHIVED'});
          }
          return jsonResponse({
            'items': archived ? [] : [space('A', true)],
            'total': archived ? 0 : 1,
            'page': 1,
            'page_size': 20,
          });
        }),
      );
      final controller = await mount(tester, api);
      await tester.tap(find.byTooltip('Archive A'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      if (scenario == 'stock') {
        expect(find.text('Cannot archive this space'), findsOneWidget);
        expect(find.text('Confirm'), findsNothing);
      } else if (scenario == 'read failure') {
        expect(find.text('Cannot check stock'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      } else {
        expect(
          find.textContaining('Inventory history will not be deleted'),
          findsOneWidget,
        );
        expect(find.textContaining('another default space'), findsOneWidget);
        await tester.tap(find.text(scenario == 'cancel' ? 'Close' : 'Confirm'));
        await tester.pumpAndSettle();
        expect(writes, scenario == 'cancel' ? 0 : 1);
        if (scenario == 'conflict') {
          expect(
            find.textContaining('still contains in-stock inventory'),
            findsOneWidget,
          );
          expect(controller.storageSpaces.single.id, 'A');
        }
        if (scenario == 'confirm') expect(controller.storageSpaces, isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

Future<StorageSpaceController> mount(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(api.close);
  final tokens = MemoryTokens();
  final controller = StorageSpaceController(
    StorageSpaceRepository(StorageSpaceApiService(api), tokens),
    workspace: WorkspaceRepository(api, tokens),
  );
  addTearDown(controller.dispose);
  await controller.loadStorageSpaces();
  await tester.pumpWidget(
    MaterialApp(home: StorageSpaceScreen(controller: controller)),
  );
  await tester.pumpAndSettle();
  return controller;
}
