import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sayfridge/models/agent_image.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/agent_conversation_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/voice_input_service.dart';
import 'package:sayfridge/state/agent_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';
import '../support/integration_fixtures.dart';

void main() {
  testWidgets('history opens the current conversation without sample records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var requests = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, endsWith('/agent/chat'));
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
    await tester.runAsync(() => agent.send('Add items to my inventory'));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AgentConversationScreen(controller: agent),
      ),
    );
    await tester.tap(find.byTooltip('Conversation history'));
    await tester.pumpAndSettle();

    expect(find.text('Conversation History'), findsOneWidget);
    expect(find.text('Current conversation'), findsOneWidget);
    expect(find.text('Add items to my inventory'), findsOneWidget);
    expect(find.text('Record milk used.'), findsNothing);
    expect(requests, 1);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('AI Assistant'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history lists and opens an earlier conversation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      client: MockClient(
        (request) async => request.method == 'GET'
            ? jsonResponse({'status': 'COMPLETED', 'items': []})
            : eventResponse([
                {'type': 'text_delta', 'delta': 'A reply'},
                {
                  'type': 'done',
                  'status': 'COMPLETED',
                  'data': {'status': 'COMPLETED', 'items': []},
                },
              ]),
      ),
    );
    addTearDown(api.close);
    final agent = AgentController(
      WorkspaceRepository(api, MemoryTokens()),
      store: MemoryAgentStore(),
    );
    addTearDown(agent.dispose);
    await agent.bindUser('alice');
    await tester.runAsync(() => agent.send('First question'));
    await agent.newConversation();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AgentConversationScreen(controller: agent),
      ),
    );
    await tester.tap(find.byTooltip('Conversation history'));
    await tester.pumpAndSettle();
    expect(find.text('Earlier conversations'), findsOneWidget);
    expect(find.text('No current conversation'), findsNothing);
    expect(find.text('First question'), findsOneWidget);
    await _tapAndFinish(tester, agent, find.text('First question'));
    await tester.pumpAndSettle();
    expect(agent.messages.values, contains('First question'));
    expect(find.text('First question'), findsOneWidget);
  });

  testWidgets('welcome shortcuts send their own text through the real Agent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final suggestion in [
      'I want to update my inventory',
      'Add items to my inventory',
      'Show me an inventory report',
    ]) {
      Map<String, dynamic>? sent;
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, endsWith('/agent/chat'));
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
            key: ValueKey(suggestion),
            controller: agent,
            displayName: 'Alice Chen',
          ),
        ),
      );
      expect(find.text('Hey, Alice! How can I help you?'), findsOneWidget);
      expect(find.text('Press and hold to speak'), findsOneWidget);
      expect(sent, isNull);
      await tester.ensureVisible(find.text(suggestion));
      await _tapAndFinish(tester, agent, find.text(suggestion));
      await tester.pumpAndSettle();
      expect(sent?['message'], suggestion);
      expect(sent?['request_id'], isNotEmpty);
      expect(agent.messages.values, contains(suggestion));
      expect(find.text('Try saying'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('welcome voice bar inserts editable text and only sends on tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? sent;
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
    final voice = _FakeVoiceInput('add two bottles of milk');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AgentConversationScreen(controller: agent, voiceInput: voice),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Press and hold to speak')),
    );
    await tester.pump();
    expect(voice.starts, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(voice.stopped, isTrue);
    expect(sent, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'add two bottles of milk',
    );
    await tester.enterText(find.byType(TextField), 'add three bottles of milk');
    await _tapAndFinish(tester, agent, find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(sent?['message'], 'add three bottles of milk');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'microphone only switches modes; holding the voice bar appends speech',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var requests = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          requests++;
          return eventResponse([]);
        }),
      );
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: MemoryAgentStore(),
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      final voice = _FakeVoiceInput('add two bottles of milk');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AgentConversationScreen(controller: agent, voiceInput: voice),
        ),
      );

      await tester.tap(find.byTooltip('Type a message'));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      await tester.enterText(field, 'Please');
      await tester.longPress(find.byTooltip('Switch to voice input'));
      await tester.pumpAndSettle();
      expect(voice.starts, 0);
      if (find.byTooltip('Switch to voice input').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Switch to voice input'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Press and hold to speak'), findsOneWidget);
      expect(voice.starts, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('Hold to speak')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(find.text('按住识别语音'), findsOneWidget);
      expect(find.text('松手编辑'), findsOneWidget);
      final overlay = find.byKey(const Key('voice-recording-overlay'));
      expect(overlay, findsOneWidget);
      expect(tester.widget<ColoredBox>(overlay).color, const Color(0xE8444444));
      expect(find.text('add two bottles of milk'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(overlay, findsNothing);

      expect(
        tester.widget<TextField>(field).controller!.text,
        'Please add two bottles of milk',
      );
      expect(voice.stopped, isTrue);
      expect(voice.cancelled, isFalse);
      expect(requests, 0);
    },
  );

  testWidgets('sliding up before release cancels voice input', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(client: MockClient((_) async => eventResponse([])));
    addTearDown(api.close);
    final agent = AgentController(
      WorkspaceRepository(api, MemoryTokens()),
      store: MemoryAgentStore(),
    );
    addTearDown(agent.dispose);
    await agent.bindUser('alice');
    final voice = _FakeVoiceInput('discard this text');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AgentConversationScreen(controller: agent, voiceInput: voice),
      ),
    );

    final microphone = find.byTooltip('Hold to speak');
    final gesture = await tester.startGesture(tester.getCenter(microphone));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(find.text('Release to cancel'), findsWidgets);
    await gesture.up();
    await tester.pumpAndSettle();

    final leftGesture = await tester.startGesture(tester.getCenter(microphone));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await leftGesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(find.text('松手取消'), findsOneWidget);
    await leftGesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Type a message'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(voice.cancelled, isTrue);
    expect(voice.stopped, isFalse);
    expect(voice.starts, 2);
  });

  testWidgets(
    'releasing during first permission request prevents late listening',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiClient(client: MockClient((_) async => eventResponse([])));
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: MemoryAgentStore(),
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      final voice = _DelayedVoiceInput();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AgentConversationScreen(controller: agent, voiceInput: voice),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('Hold to speak')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();
      voice.permissionResolved.complete();
      await tester.pumpAndSettle();

      expect(voice.startedListening, isFalse);
      expect(voice.stopped, isTrue);
      await tester.tap(find.byTooltip('Type a message'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
    },
  );

  testWidgets('Agent attaches and sends a camera JPEG without file metadata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? sent;
    final cameraJpeg = base64Decode(
      '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD5yooor8PP5vP/2Q==',
    );
    expect(
      AgentImage.fromPickedBytes(cameraJpeg).validateDimensions,
      returnsNormally,
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
          pickImages: () async => [XFile.fromData(cameraJpeg, name: 'blob')],
        ),
      ),
    );

    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Selected photo'), findsOneWidget);
    expect(find.byTooltip('Remove photo'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove photo'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Selected photo'), findsNothing);
    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    await _tapAndFinish(tester, agent, find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(sent?['message'], '');
    expect(sent?['images'], hasLength(1));
    expect(sent?['images'][0]['mime_type'], 'image/jpeg');
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
    await tester.scrollUntilVisible(
      find.text('Retry same request'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
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

    await tester.tap(find.byTooltip('Type a message'));
    await tester.pumpAndSettle();
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
      await tester.tap(find.byTooltip('Type a message'));
      await tester.pumpAndSettle();
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

class _FakeVoiceInput implements VoiceInputService {
  _FakeVoiceInput(this.words);

  final String words;
  bool stopped = false;
  bool cancelled = false;
  int starts = 0;

  @override
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function(String message) onError,
    required bool Function() shouldContinue,
  }) async {
    if (!shouldContinue()) return false;
    starts++;
    onWords(words);
    return true;
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> cancel() async => cancelled = true;
}

class _DelayedVoiceInput implements VoiceInputService {
  final permissionResolved = Completer<void>();
  bool startedListening = false;
  bool stopped = false;

  @override
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function(String message) onError,
    required bool Function() shouldContinue,
  }) async {
    await permissionResolved.future;
    if (!shouldContinue()) return false;
    startedListening = true;
    onWords('should not be inserted');
    return true;
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> cancel() async {}
}

// Run the asynchronous HTTP/SSE lifecycle outside the widget fake clock,
// then pump the finished state. No sleeps or real requests are needed.
Future<void> _tapAndFinish(
  WidgetTester tester,
  AgentController agent,
  Finder button,
) async {
  // Keep scrollable actions above the fixed composer before tapping them.
  await Scrollable.ensureVisible(button.evaluate().single, alignment: 0.15);
  await tester.pumpAndSettle();
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
