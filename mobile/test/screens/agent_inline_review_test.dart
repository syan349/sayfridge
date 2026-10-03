import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/models/agent_image.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/agent_conversation_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/voice_input_service.dart';
import 'package:sayfridge/state/agent_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';
import 'package:sayfridge/widgets/assistant_widgets.dart';

import '../support/integration_fixtures.dart';

const _captureKey = Key('assistant-capture');

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['ASSISTANT_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(
    () => Future.wait(
      tester
          .widgetList<Image>(find.byType(Image))
          .map(
            (widget) => precacheImage(
              widget.image,
              tester.element(find.byType(AgentConversationScreen)),
            ),
          ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Map<String, dynamic> _proposal({String? missing}) => {
  'item_id': 'apple',
  'proposal_id': 'original',
  'status': missing == null ? 'NEEDS_CONFIRMATION' : 'NEEDS_INPUT',
  'original_text': 'Apples from the receipt',
  'display': {
    'item_name': 'Apples',
    'space_name': 'Fridge',
    'category_name': 'Fruit',
  },
  if (missing != null)
    'error': {
      'code': missing,
      'message': 'Choose the missing information',
      'details': {
        if (missing == 'CATEGORY_REQUIRED')
          'categories': [
            {'id': 'fruit', 'name': 'Fruit'},
            {'id': 'veg', 'name': 'Vegetables & Mushrooms'},
          ],
      },
    },
};

class _Harness {
  _Harness(Map<String, dynamic> proposal, {String? reply}) {
    item = proposal;
    api = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          final options = request.url.path.endsWith('storage-spaces')
              ? [
                  {'id': 'fridge', 'name': 'Fridge'},
                  {'id': 'pantry', 'name': 'Pantry Potter'},
                ]
              : [
                  {'id': 'fruit', 'name': 'Fruit'},
                  {'id': 'veg', 'name': 'Vegetables & Mushrooms'},
                ];
          return jsonResponse({'items': options, 'total': options.length});
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/resume')) {
          posts.add(body);
          final answer = (body['responses'] as List).single as Map;
          item = {
            ...item,
            'proposal_id': answer['decision'] == 'confirm'
                ? item['proposal_id']
                : 'revised',
            'status': answer['decision'] == 'confirm'
                ? 'SUCCEEDED'
                : 'NEEDS_CONFIRMATION',
            'error': null,
          };
        }
        return eventResponse([
          if (reply != null) {'type': 'text_delta', 'delta': reply},
          {
            'type': 'done',
            'data': {
              'status':
                  item.isEmpty ||
                      {
                        'SUCCEEDED',
                        'FAILED',
                        'CANCELLED',
                      }.contains(item['status'])
                  ? 'COMPLETED'
                  : 'WAITING_INPUT',
              'interrupt_id': 'review',
              'items': [if (item.isNotEmpty) item],
            },
          },
        ]);
      }),
    );
    agent = AgentController(
      WorkspaceRepository(api, MemoryTokens()),
      store: MemoryAgentStore(),
    );
  }

  late Map<String, dynamic> item;
  late final ApiClient api;
  late final AgentController agent;
  final posts = <Map<String, dynamic>>[];

  Future<void> open(
    WidgetTester tester, {
    AgentImage? photo,
    VoiceInputService? voiceInput,
    String command = 'Review the receipt',
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(api.close);
    addTearDown(agent.dispose);
    await agent.bindUser('alice');
    await tester.runAsync(
      () => agent.send(
        photo == null ? command : '',
        images: photo == null ? const [] : [photo],
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 47, bottom: 34),
              textScaler: TextScaler.linear(textScale),
              devicePixelRatio:
                  Platform.environment['ASSISTANT_CAPTURE_DIR'] == null
                  ? MediaQuery.devicePixelRatioOf(context)
                  : 2,
            ),
            child: child!,
          ),
          home: AgentConversationScreen(
            controller: agent,
            voiceInput: voiceInput,
            displayName: 'Alice',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(0);
    await tester.pumpAndSettle();
    while (finder.evaluate().isEmpty &&
        position.pixels < position.maxScrollExtent) {
      position.jumpTo(
        (position.pixels + 120).clamp(0, position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: .1);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
}

Finder _inlineControl(Finder matching) => find.descendant(
  of: find.byKey(const Key('proposal-response-input')),
  matching: matching,
);

class _ReviewVoice implements VoiceInputService {
  _ReviewVoice(this.words);
  final String words;
  bool stopped = false, cancelled = false;

  @override
  Future<bool> start({
    required void Function(String) onWords,
    required void Function(String) onError,
    required bool Function() shouldContinue,
  }) async {
    if (!shouldContinue()) return false;
    onWords(words);
    return true;
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> cancel() async => cancelled = true;
}

void main() {
  setUpAll(() async {
    if (Platform.environment['ASSISTANT_CAPTURE_DIR'] == null) return;
    final text = FontLoader('Arial')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('C:/Windows/Fonts/arial.ttf').readAsBytes(),
          ),
        ),
      );
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([text.load(), icons.load()]);
  });

  testWidgets(
    'spoken clarification stays editable and submits only the pending item on Confirm',
    (tester) async {
      final harness = _Harness(_proposal(missing: 'QUANTITY_REQUIRED'));
      final voice = _ReviewVoice('The measured quantity is 3 kg');
      await harness.open(tester, voiceInput: voice);
      expect(find.text('Add supporting photo'), findsNothing);
      expect(find.byKey(const Key('proposal-response-text')), findsNothing);
      final confirm = find.widgetWithText(FilledButton, 'Confirm');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      final hold = _inlineControl(find.text('Press and hold to speak'));
      await tester.ensureVisible(hold);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(hold));
      await tester.pump();
      expect(harness.posts, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(voice.stopped, isTrue);
      final text = find.byKey(const Key('proposal-response-text'));
      expect(tester.widget<TextField>(text).controller!.text, voice.words);
      expect(tester.widget<TextField>(text).maxLength, 1000);
      expect(harness.posts, isEmpty);
      await tester.enterText(text, 'The measured quantity is 4 kg');
      await _tap(tester, confirm);
      final answer = (harness.posts.single['responses'] as List).single;
      expect(answer['item_id'], 'apple');
      expect(answer['proposal_id'], 'original');
      expect(answer['decision'], 'answer');
      expect(answer['message'], 'The measured quantity is 4 kg');
      expect(answer.containsKey('images'), isFalse);
      expect(harness.agent.items.single['proposal_id'], 'revised');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled inline speech preserves the typed clarification and selected choices',
    (tester) async {
      final harness = _Harness(_proposal(missing: 'CATEGORY_REQUIRED'));
      final voice = _ReviewVoice('This must not be submitted');
      await harness.open(tester, voiceInput: voice);
      await _tap(tester, find.byKey(const ValueKey('proposal-category-fruit')));
      await _tap(tester, find.text('Describe another detail'));
      await _tap(tester, _inlineControl(find.byTooltip('Type a message')));
      final text = find.byKey(const Key('proposal-response-text'));
      await tester.enterText(text, 'Keep in the fridge');
      await _tap(
        tester,
        _inlineControl(find.byTooltip('Switch to voice input')),
      );
      final hold = _inlineControl(find.text('Press and hold to speak'));
      await tester.ensureVisible(hold);
      final gesture = await tester.startGesture(tester.getCenter(hold));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -90));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(voice.cancelled, isTrue);
      expect(harness.posts, isEmpty);
      await _tap(tester, _inlineControl(find.byTooltip('Type a message')));
      expect(
        tester.widget<TextField>(text).controller!.text,
        'Keep in the fridge',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Confirm'));
      final answer = (harness.posts.single['responses'] as List).single;
      expect(answer['message'], contains('category_id: fruit'));
      expect(answer['message'], contains('Keep in the fridge'));
      expect(answer['message'], isNot(contains(voice.words)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inline voice and typing fit a small phone with enlarged text', (
    tester,
  ) async {
    final harness = _Harness(_proposal(missing: 'QUANTITY_REQUIRED'));
    await harness.open(tester, size: const Size(320, 568), textScale: 1.4);
    expect(tester.takeException(), isNull);
    await _tap(tester, _inlineControl(find.byTooltip('Type a message')));
    await tester.enterText(
      find.byKey(const Key('proposal-response-text')),
      'Three kilograms of apples, stored in the fridge.',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('assistant-bottom-action')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('proposal-response-text')))
          .controller!
          .text,
      'Three kilograms of apples, stored in the fridge.',
    );
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-bottom-action')), findsOneWidget);
  });

  testWidgets(
    'editing stays in the chat and uses choices before reconfirming the new proposal',
    (tester) async {
      final harness = _Harness(_proposal());
      await harness.open(tester);
      expect(find.byType(AssistantActionBubble), findsOneWidget);
      await _capture(tester, 'inline-confirmation');
      await _tap(tester, find.text('Edit details'));
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Change this proposal'), findsNothing);
      expect(find.byKey(const Key('proposal-response-text')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('proposal-category-veg')));
      await _tap(tester, find.byKey(const ValueKey('proposal-space-pantry')));
      expect(harness.posts, isEmpty);
      await _capture(tester, 'inline-options');
      await _tap(tester, find.text('Update proposal'));
      final answer = (harness.posts.single['responses'] as List).single as Map;
      expect(answer['decision'], 'edit');
      expect(answer['proposal_id'], 'original');
      expect(answer['message'], contains('Vegetables & Mushrooms'));
      expect(answer['message'], contains('Pantry Potter'));
      expect(answer.containsKey('selected_inventory_item_id'), isFalse);
      expect(harness.agent.items.single['status'], 'NEEDS_CONFIRMATION');
      await _tap(tester, find.text('Confirm'));
      expect(
        (harness.posts.last['responses'] as List).single['proposal_id'],
        'revised',
      );
      expect(harness.agent.items.single['status'], 'SUCCEEDED');
      expect(tester.takeException(), isNull);
    },
  );

  for (final missing in ['CATEGORY_REQUIRED', 'SPACE_REQUIRED']) {
    testWidgets('$missing uses real choices without a manual form', (
      tester,
    ) async {
      final harness = _Harness(_proposal(missing: missing));
      await harness.open(tester);
      expect(find.byKey(const Key('proposal-response-text')), findsNothing);
      final button = find.widgetWithText(FilledButton, 'Confirm');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await _tap(
        tester,
        find.byKey(
          ValueKey(
            missing == 'CATEGORY_REQUIRED'
                ? 'proposal-category-fruit'
                : 'proposal-space-fridge',
          ),
        ),
      );
      await _tap(tester, button);
      final answer = (harness.posts.single['responses'] as List).single as Map;
      expect(answer['decision'], 'answer');
      expect(
        answer['message'],
        contains(missing == 'CATEGORY_REQUIRED' ? 'Fruit' : 'Fridge'),
      );
      expect(answer.containsKey('selected_inventory_item_id'), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'details without choices are entered inline and survive keyboard resizing',
    (tester) async {
      final harness = _Harness(_proposal(missing: 'QUANTITY_REQUIRED'));
      await harness.open(tester);
      await _tap(
        tester,
        find.descendant(
          of: find.byKey(const Key('proposal-response-input')),
          matching: find.byTooltip('Type a message'),
        ),
      );
      final response = find.byKey(const Key('proposal-response-text'));
      await tester.ensureVisible(response);
      await tester.enterText(response, 'The measured quantity is 3 kg');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(FilledButton, 'Confirm'));
      expect(
        (harness.posts.single['responses'] as List).single['message'],
        'The measured quantity is 3 kg',
      );
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets('capture response states for layout review without live inventory writes', (
    tester,
  ) async {
    if (Platform.environment['ASSISTANT_CAPTURE_DIR'] == null) return;
    final add = <String, dynamic>{
      ..._proposal(),
      'original_text': 'Add 2 kg of apples to the fridge',
      'preview': {
        'draft': {
          'quantity_value': '2',
          'quantity_unit': 'kg',
          'expiry_date': '2026-10-10',
        },
        'after': {
          'confirmed_current_amount': '2',
          'confirmed_current_unit': 'kg',
        },
        'calculation_method': 'EXACT',
      },
    };
    final modify = <String, dynamic>{
      'item_id': 'milk',
      'proposal_id': 'milk-1',
      'status': 'NEEDS_CONFIRMATION',
      'original_text': 'I consumed 500 ml of milk',
      'display': {
        'item_name': 'Milk',
        'space_name': 'Fridge',
        'category_name': 'Dairy',
      },
      'preview': {
        'draft': {'quantity_value': '500', 'quantity_unit': 'ml'},
        'before': {
          'confirmed_current_amount': '2',
          'confirmed_current_unit': 'L',
        },
        'after': {
          'confirmed_current_amount': '1.5',
          'confirmed_current_unit': 'L',
        },
        'calculation_method': 'EXACT',
      },
    };
    final missing = <String, dynamic>{
      'item_id': 'milk',
      'proposal_id': 'milk-unknown',
      'status': 'NEEDS_INPUT',
      'original_text': 'I consumed 3 cups of milk',
      'display': {
        'item_name': 'Milk',
        'question':
            'How much milk does one cup hold? You can use a measurement or the amount on the packaging.',
      },
      'error': {
        'code': 'REESTIMATE',
        'message':
            'Provide unit_relationship with a ratio and its source; do not calculate final balances',
      },
    };
    for (final scenario
        in <({String name, String command, Map<String, dynamic> item})>[
          (
            name: '01-add-review',
            command: 'Add 2 kg of apples to the fridge',
            item: add,
          ),
          (
            name: '02-add-saved',
            command: 'Add 2 kg of apples to the fridge',
            item: {...add, 'status': 'SUCCEEDED'},
          ),
          (
            name: '03-modify-review',
            command: 'I consumed 500 ml of milk',
            item: modify,
          ),
          (
            name: '04-modify-saved',
            command: 'I consumed 500 ml of milk',
            item: {...modify, 'status': 'SUCCEEDED'},
          ),
          (
            name: '05-missing-voice',
            command: 'I consumed 3 cups of milk',
            item: missing,
          ),
          (
            name: '11-save-failed',
            command: 'Add 2 kg of apples to the fridge',
            item: {
              ...add,
              'status': 'FAILED',
              'error': {
                'code': 'VALIDATION_ERROR',
                'message':
                    'This change could not be saved. Please check the quantity and try again.',
              },
            },
          ),
          (
            name: '12-cancelled',
            command: 'I consumed 500 ml of milk',
            item: {...modify, 'status': 'CANCELLED'},
          ),
          (
            name: '13-choose-batch',
            command: 'I consumed 500 ml of milk',
            item: {
              ...missing,
              'original_text': 'I consumed 500 ml of milk',
              'display': {
                'item_name': 'Milk',
                'question': 'Which batch of milk did you use?',
              },
              'error': {
                'code': 'ITEM_REQUIRED',
                'message': 'Choose a batch',
                'details': {
                  'candidates': [
                    {
                      'id': 'milk-fridge',
                      'item_definition_name': 'Milk',
                      'storage_space_name': 'Fridge',
                      'confirmed_current_amount': '2',
                      'confirmed_current_unit': 'L',
                    },
                    {
                      'id': 'milk-freezer',
                      'item_definition_name': 'Milk',
                      'storage_space_name': 'Freezer',
                      'confirmed_current_amount': '1',
                      'confirmed_current_unit': 'L',
                    },
                  ],
                },
              },
            },
          ),
        ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      final harness = _Harness(scenario.item);
      await harness.open(tester, command: scenario.command);
      await _capture(tester, scenario.name);
      if (scenario.name == '05-missing-voice') {
        await _tap(tester, _inlineControl(find.byTooltip('Type a message')));
        await tester.enterText(
          find.byKey(const Key('proposal-response-text')),
          'One cup holds 250 ml, measured with my measuring cup.',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await _capture(tester, '06-missing-keyboard');
      }
      if (scenario.name == '03-modify-review') {
        await _tap(tester, find.text('Edit details'));
        await _tap(tester, find.text('Describe another detail'));
        await _capture(tester, '07-edit-voice');
        await _tap(tester, _inlineControl(find.byTooltip('Type a message')));
        await tester.enterText(
          find.byKey(const Key('proposal-response-text')),
          'I used 300 ml, not 500 ml.',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await _capture(tester, '14-edit-keyboard');
      }
      expect(tester.takeException(), isNull);
      expect(harness.posts, isEmpty);
    }
    final documents = <({String name, String command, String reply})>[
      (
        name: '08-inventory-query',
        command: 'What is in my fridge?',
        reply:
            'Your fridge has **3 in-stock batches**:\n\n- **Milk** — 1.5 L, expires Oct 6.\n- **Apples** — 2 kg, expires Oct 10.\n- **Eggs** — 6 pieces, expires Oct 12.\n\nMilk expires first, so try to use it soon.',
      ),
      (
        name: '09-inventory-report',
        command: 'Generate an inventory report',
        reply:
            'Here’s your inventory report.\n\n## Inventory report\n\n**6 in-stock batches** across 2 storage spaces.\n\n### Fridge\n- **Milk** — 1.5 L, expires Oct 6.\n- **Apples** — 2 kg, expires Oct 10.\n- **Eggs** — 6 pieces, expires Oct 12.\n\n### Pantry\n- **Rice** — 1 kg.\n- **Pasta** — 500 g.\n- **Olive oil** — estimated 400 ml.\n\n### Use first\n**Milk** expires soon. Consider using it for breakfast or cooking.\n\n### Other records\n- **Yoghurt** — empty.\n- **Bread** — discarded.',
      ),
    ];
    for (final document in documents) {
      await tester.pumpWidget(const SizedBox.shrink());
      final harness = _Harness({}, reply: document.reply);
      await harness.open(tester, command: document.command);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(0);
      await tester.pumpAndSettle();
      await _capture(tester, document.name);
      if (document.name == '09-inventory-report') {
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        await _capture(tester, '10-report-bottom');
      }
      expect(harness.agent.items, isEmpty);
      expect(harness.posts, isEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'portrait and landscape photos preserve their ratio and align with the bubble body',
    (tester) async {
      AgentImage? portrait;
      for (final sourceSize in [const Size(200, 400), const Size(400, 200)]) {
        final photo = await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(
            Offset.zero & sourceSize,
            Paint()..color = Colors.white,
          );
          final receipt = TextPainter(
            text: const TextSpan(
              text:
                  'GROCERY RECEIPT\n\nApples     2 kg\nMilk       1 L\n\nThank you',
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontFamily: 'Arial',
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: sourceSize.width - 24);
          receipt.paint(canvas, const Offset(12, 24));
          receipt.dispose();
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            sourceSize.width.toInt(),
            sourceSize.height.toInt(),
          );
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          picture.dispose();
          return AgentImage.fromPickedBytes(data!.buffer.asUint8List());
        });
        if (sourceSize.height > sourceSize.width) portrait = photo;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 340,
                  child: UserMessageBubble(
                    message: 'Photo attached',
                    images: [photo!],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final imageRect = tester.getRect(
          find.byKey(ValueKey('uploaded-photo-${photo.imageId}')),
        );
        final bubbleRect = tester.getRect(
          find.byKey(const Key('user-message-shape')),
        );
        expect(imageRect.right, closeTo(bubbleRect.right - 13, .1));
        expect(
          imageRect.width / imageRect.height,
          closeTo(sourceSize.aspectRatio, .01),
        );
        if (sourceSize.height > sourceSize.width) {
          expect(imageRect.height, greaterThan(180));
        }
        expect(imageRect.width, lessThanOrEqualTo(327));
        expect(tester.takeException(), isNull);
      }
      final harness = _Harness(_proposal());
      await harness.open(tester, photo: portrait);
      // Existing conversations now open at the end; reveal the earlier photo.
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(UserMessageBubble));
      await tester.pumpAndSettle();
      await _capture(tester, 'photo-chat');
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Edit details'));
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'small-screen-options');
    },
  );
}
