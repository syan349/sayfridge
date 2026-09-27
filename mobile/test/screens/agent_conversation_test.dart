import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/agent_conversation_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/state/agent_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';
import '../support/integration_fixtures.dart';

void main() {
  testWidgets('authenticated Agent previews, removes and sends gallery images', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? sent;
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLJhgAAAABJRU5ErkJggg==',
      ),
    );
    final api = ApiClient(
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return eventResponse([
          {
            'type': 'done',
            'status': 'COMPLETED',
            'data': {'status': 'COMPLETED', 'items': []},
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
          pickImages: () async => [
            XFile.fromData(png, mimeType: 'image/png', name: 'milk.png'),
          ],
        ),
      ),
    );

    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Selected photo'), findsOneWidget);
    expect(find.byTooltip('Remove photo'), findsOneWidget);

    await _tapAndFinish(tester, agent, find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(sent?['message'], '');
    expect(sent?['images'], hasLength(1));
    expect(sent?['images'][0]['mime_type'], 'image/png');
    expect(find.bySemanticsLabel('Selected photo'), findsNothing);
  });

  testWidgets('failed image request keeps its preview available for recovery', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLJhgAAAABJRU5ErkJggg==',
      ),
    );
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return jsonResponse({'status': 'RECOVERABLE', 'items': []});
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return eventResponse([
          {'type': 'start', 'conversation_id': body['conversation_id']},
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
          pickImages: () async => [
            XFile.fromData(png, mimeType: 'image/png', name: 'milk.png'),
          ],
        ),
      ),
    );

    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    await _tapAndFinish(tester, agent, find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(agent.canRetry, isTrue);
    expect(find.bySemanticsLabel('Selected photo'), findsOneWidget);
    expect(find.text('Retry same request'), findsOneWidget);
  });

  testWidgets('supporting photo replaces the visible pending proposal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLJhgAAAABJRU5ErkJggg==',
      ),
    );
    Map<String, dynamic>? resumeBody;
    var calls = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        calls++;
        if (calls == 1) {
          return eventResponse([
            {
              'type': 'done',
              'status': 'WAITING_INPUT',
              'data': {
                'status': 'WAITING_INPUT',
                'interrupt_id': 'interrupt-old',
                'items': [
                  {
                    'item_id': 'item',
                    'proposal_id': 'old',
                    'status': 'NEEDS_INPUT',
                    'original_text': 'Unknown package',
                  },
                ],
              },
            },
          ]);
        }
        resumeBody = jsonDecode(request.body) as Map<String, dynamic>;
        return eventResponse([
          {
            'type': 'done',
            'status': 'WAITING_INPUT',
            'data': {
              'status': 'WAITING_INPUT',
              'interrupt_id': 'interrupt-new',
              'items': [
                {
                  'item_id': 'item',
                  'proposal_id': 'new',
                  'status': 'NEEDS_CONFIRMATION',
                  'original_text': 'Milk 1 bottle',
                  'preview': {
                    'calculation_method': 'EXACT',
                    'draft': {
                      'quantity_value': '1',
                      'quantity_unit': 'bottle',
                      'purchase_date': '2026-09-27',
                    },
                    'after': {
                      'confirmed_current_amount': '1',
                      'confirmed_current_unit': 'bottle',
                    },
                    'display': {
                      'item_name': 'Milk',
                      'category_name': 'Dairy',
                      'space_name': 'Fridge',
                    },
                  },
                  'display': {
                    'recognized_text': 'MILK 1L',
                    'package_description': '1 litre carton',
                    'missing_fields': ['expiry_date'],
                    'review_notes': ['Check the expiry date'],
                  },
                },
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
          pickImages: () async => [
            XFile.fromData(png, mimeType: 'image/png', name: 'label.png'),
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'What is this?');
    await _tapAndFinish(tester, agent, find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Unknown package'), findsOneWidget);
    await tester.ensureVisible(find.text('Add supporting photo'));
    await _tapAndFinish(tester, agent, find.text('Add supporting photo'));
    await tester.pumpAndSettle();

    expect(find.text('Unknown package'), findsNothing);
    expect(find.text('Milk 1 bottle'), findsOneWidget);
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Ready for review'), findsOneWidget);
    expect(find.text('MILK 1L'), findsOneWidget);
    expect(find.text('Dairy'), findsOneWidget);
    expect(find.text('Fridge'), findsOneWidget);
    expect(find.text('1 litre carton'), findsOneWidget);
    expect(find.text('1 bottle'), findsOneWidget);
    expect(find.text('Still needed: expiry_date'), findsOneWidget);
    expect(find.text('Review notes: Check the expiry date'), findsOneWidget);
    expect(resumeBody?['responses'][0]['proposal_id'], 'old');
    expect(resumeBody?['responses'][0]['images'], hasLength(1));
    expect(agent.items.single['proposal_id'], 'new');
  });

  testWidgets(
    'phone AI confirms a real proposal and does not claim a failed item succeeded',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      final item = {
        'item_id': 'item',
        'proposal_id': 'proposal',
        'status': 'NEEDS_CONFIRMATION',
        'original_text': 'Use one cup',
      };
      final api = ApiClient(
        client: MockClient((request) async {
          calls++;
          if (calls == 1) {
            expect(request.url.path, endsWith('/agent/chat'));
            return eventResponse([
              {
                'type': 'done',
                'status': 'WAITING_INPUT',
                'data': {
                  'status': 'WAITING_INPUT',
                  'interrupt_id': 'interrupt',
                  'items': [item],
                },
              },
            ]);
          }
          expect(
            jsonDecode(request.body)['responses'][0]['decision'],
            'confirm',
          );
          return eventResponse([
            {
              'type': 'done',
              'status': 'COMPLETED',
              'data': {
                'status': 'COMPLETED',
                'items': [
                  {
                    ...item,
                    'status': 'FAILED',
                    'error': {
                      'code': 'INSUFFICIENT_STOCK',
                      'message': 'Not enough stock',
                    },
                  },
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
          home: AgentConversationScreen(controller: agent),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hey, Tim!  How can I help you?'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Use one cup');
      await _tapAndFinish(tester, agent, find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(agent.waiting, isTrue);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.ensureVisible(find.text('Confirm proposal'));
      await _tapAndFinish(tester, agent, find.text('Confirm proposal'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Not enough stock'), findsOneWidget);
      expect(find.text('Added successfully'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

// Run the asynchronous HTTP/SSE lifecycle outside the widget fake clock,
// then pump the finished state. No sleeps or real requests are needed.
Future<void> _tapAndFinish(
  WidgetTester tester,
  AgentController agent,
  Finder button,
) async {
  await tester.runAsync(() async {
    final finished = Completer<void>();
    var started = false;
    void listener() {
      if (agent.busy) started = true;
      if (started && !agent.busy && !finished.isCompleted) finished.complete();
    }

    agent.addListener(listener);
    try {
      await tester.tap(button);
      await finished.future.timeout(const Duration(seconds: 5));
    } finally {
      agent.removeListener(listener);
    }
  });
}
