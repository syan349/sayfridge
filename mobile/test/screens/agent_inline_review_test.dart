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
  _Harness(Map<String, dynamic> proposal) {
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
          {
            'type': 'done',
            'data': {
              'status': item['status'] == 'SUCCEEDED'
                  ? 'COMPLETED'
                  : 'WAITING_INPUT',
              'interrupt_id': 'review',
              'items': [item],
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

  Future<void> open(WidgetTester tester, {AgentImage? photo}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(api.close);
    addTearDown(agent.dispose);
    await agent.bindUser('alice');
    await tester.runAsync(
      () => agent.send(
        photo == null ? 'Review the receipt' : '',
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
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(top: 47, bottom: 34)),
            child: child!,
          ),
          home: AgentConversationScreen(controller: agent),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
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
