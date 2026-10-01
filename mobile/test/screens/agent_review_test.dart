import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/models/agent_image.dart';
import 'package:sayfridge/models/agent_input_draft.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/agent_conversation_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/state/agent_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';
import '../support/integration_fixtures.dart';

Map<String, dynamic> proposal(
  String id, {
  String status = 'NEEDS_CONFIRMATION',
  bool uncertain = false,
}) => {
  'item_id': id,
  'proposal_id': 'proposal-$id',
  'status': status,
  'original_text': '2 pieces of $id',
  'display': {
    'item_name': id,
    'recognized_text': '2 pieces of $id',
    'space_name': 'Fridge',
  },
  if (uncertain)
    'error': {
      'code': 'EXECUTION_UNCERTAIN',
      'message': 'Verify this action first',
    },
};

Map<String, dynamic> waiting(List<Map<String, dynamic>> items) => {
  'status': 'WAITING_INPUT',
  'interrupt_id': 'review',
  'items': items,
};

void main() {
  testWidgets(
    'photo history stores a thumbnail while scanning sends the original image',
    (tester) async {
      final source = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)
          ..drawRect(
            const Rect.fromLTWH(0, 0, 1000, 500),
            Paint()..color = Colors.green,
          );
        canvas.drawCircle(
          const Offset(500, 250),
          180,
          Paint()..color = Colors.white,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(1000, 500);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return AgentImage.fromPickedBytes(data!.buffer.asUint8List());
      });
      final store = MemoryAgentStore();
      Map<String, dynamic>? sent;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return jsonResponse({'status': 'COMPLETED', 'items': []});
          }
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return eventResponse([
            {
              'type': 'done',
              'data': {'status': 'COMPLETED', 'items': []},
            },
          ]);
        }),
      );
      addTearDown(api.close);
      final workspace = WorkspaceRepository(api, MemoryTokens());
      final first = AgentController(workspace, store: store);
      addTearDown(first.dispose);
      await first.bindUser('alice');
      await tester.runAsync(() => first.send('', images: [source!]));
      expect((sent?['images'] as List).single, source!.toJson());
      final firstId = first.conversationId!;
      final preview = first.messageImages.values.single.single;
      expect(preview.imageId, source.imageId);
      expect(preview.dataBase64, isNot(source.dataBase64));
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(preview.bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 640);
        expect(frame.image.height, 320);
        frame.image.dispose();
        codec.dispose();
      });
      await first.newConversation();
      final restored = AgentController(workspace, store: store);
      addTearDown(restored.dispose);
      await restored.bindUser('alice');
      await restored.openConversation(firstId);
      expect(
        restored.messageImages.values.single.single.dataBase64,
        preview.dataBase64,
      );
      await restored.bindUser('bob');
      expect(restored.messageImages, isEmpty);
    },
  );
  test(
    'bulk confirmation submits only current ready proposals and retries exactly',
    () async {
      final items = [
        proposal('Milk'),
        proposal('Apples'),
        proposal('Unknown', status: 'NEEDS_INPUT'),
        proposal('Uncertain', uncertain: true),
      ];
      final posts = <Map<String, dynamic>>[];
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET') return jsonResponse(waiting(items));
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path.endsWith('/chat')) {
            return eventResponse([
              {'type': 'done', 'data': waiting(items)},
            ]);
          }
          posts.add(body);
          if (posts.length == 1) {
            return eventResponse([
              {'type': 'start'},
            ]);
          }
          return eventResponse([
            {
              'type': 'done',
              'data': waiting([
                {...items[0], 'status': 'SUCCEEDED'},
                {
                  ...items[1],
                  'status': 'FAILED',
                  'error': {'code': 'VERSION_CONFLICT'},
                },
                items[2],
                items[3],
              ]),
            },
          ]);
        }),
      );
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: MemoryAgentStore(),
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      await agent.send('Review my items');
      expect(agent.confirmableItems.map((i) => i['item_id']), [
        'Milk',
        'Apples',
      ]);
      await agent.confirmItems(agent.confirmableItems);
      expect(posts.single['responses'], [
        {
          'item_id': 'Milk',
          'proposal_id': 'proposal-Milk',
          'decision': 'confirm',
        },
        {
          'item_id': 'Apples',
          'proposal_id': 'proposal-Apples',
          'decision': 'confirm',
        },
      ]);
      expect(agent.canRetry, isTrue);
      await agent.retry();
      expect(posts.last, posts.first);
      expect(agent.items.map((i) => i['status']), [
        'SUCCEEDED',
        'FAILED',
        'NEEDS_INPUT',
        'NEEDS_CONFIRMATION',
      ]);
    },
  );

  test(
    'bulk confirmation rejects a stale or duplicate selection without sending',
    () async {
      var calls = 0;
      final item = proposal('Milk');
      final api = ApiClient(
        client: MockClient((_) async {
          calls++;
          return eventResponse([
            {
              'type': 'done',
              'data': waiting([item]),
            },
          ]);
        }),
      );
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: MemoryAgentStore(),
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      await agent.send('Review milk');
      await agent.confirmItems([
        {...item, 'proposal_id': 'old'},
      ]);
      await agent.confirmItems([item, item]);
      expect(calls, 1);
      expect(agent.error, contains('changed'));
    },
  );

  testWidgets(
    'a scan shows photos and bulk review, with a header that stays fixed',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final image = AgentImage.fromPickedBytes(
        (await rootBundle.load(
          'assets/icons/inventory/milk.png',
        )).buffer.asUint8List(),
      );
      final posts = <Map<String, dynamic>>[];
      final api = ApiClient(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          posts.add(body);
          if (request.url.path.endsWith('/chat')) {
            return eventResponse([
              {
                'type': 'done',
                'data': waiting([proposal('Milk'), proposal('Apples')]),
              },
            ]);
          }
          return eventResponse([
            {
              'type': 'done',
              'data': {
                'status': 'COMPLETED',
                'items': [
                  {...proposal('Milk'), 'status': 'SUCCEEDED'},
                  {...proposal('Apples'), 'status': 'SUCCEEDED'},
                ],
              },
            },
          ]);
        }),
      );
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: MemoryAgentStore(),
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AgentConversationScreen(
            controller: agent,
            initialDraft: AgentInputDraft(text: '', images: [image]),
          ),
        ),
      );
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect(posts, hasLength(1));
      expect(posts.single['message'], contains('Wait for my confirmation'));
      expect(find.text('Photo attached'), findsOneWidget);
      expect(
        find.byKey(ValueKey('uploaded-photo-${image.imageId}')),
        findsOneWidget,
      );
      final header = tester.getRect(find.text('AI Assistant'));
      await tester.ensureVisible(find.byKey(const Key('confirm-all-items')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('AI Assistant')), header);
      expect(find.byTooltip('New conversation').hitTestable(), findsOneWidget);
      expect(
        find.byTooltip('Conversation history').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirm-all-items')));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect(posts, hasLength(2));
      expect(posts.last['responses'], hasLength(2));
      expect(agent.items.every((i) => i['status'] == 'SUCCEEDED'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing batch information is selected before Confirm answers it',
    (tester) async {
      final item = {
        ...proposal('Eggs', status: 'NEEDS_INPUT'),
        'error': {
          'code': 'AMBIGUOUS_ITEM',
          'message': 'Which batch should I use?',
          'details': {
            'candidates': [
              {
                'id': 'batch-3',
                'item_definition_name': 'Eggs',
                'storage_space_name': 'Fridge',
                'confirmed_current_amount': '3',
                'confirmed_current_unit': 'each',
              },
              {
                'id': 'batch-5',
                'item_definition_name': 'Eggs',
                'storage_space_name': 'Fridge',
                'confirmed_current_amount': '5',
                'confirmed_current_unit': 'pieces',
              },
            ],
          },
        },
      };
      final posts = <Map<String, dynamic>>[];
      final api = ApiClient(
        client: MockClient((request) async {
          posts.add(jsonDecode(request.body) as Map<String, dynamic>);
          return eventResponse([
            {
              'type': 'done',
              'data': waiting([item]),
            },
          ]);
        }),
      );
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: MemoryAgentStore(),
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      await tester.runAsync(() => agent.send('Use four eggs'));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AgentConversationScreen(controller: agent),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Eggs · Fridge · 5 pieces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eggs · Fridge · 5 pieces'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect((posts.last['responses'] as List).single['decision'], 'answer');
      expect(
        (posts.last['responses'] as List).single['selected_inventory_item_id'],
        'batch-5',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
