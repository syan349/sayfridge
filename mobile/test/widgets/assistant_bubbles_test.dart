import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/agent_conversation_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/state/agent_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';
import 'package:sayfridge/widgets/assistant_widgets.dart';

import '../support/integration_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['ASSISTANT_CAPTURE_DIR'] == null) return;
    final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/arial.ttf').readAsBytes(),
    );
    await (FontLoader('Arial')..addFont(Future.value(font))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  final bubbles = <String, Widget Function(String)>{
    'greeting': (message) => AssistantGreeting(message: message),
    'reply': (message) =>
        AssistantReply(message: message, textStyle: exampleMessageStyle),
    'action': (message) =>
        AssistantActionBubble(child: Text(message, style: exampleMessageStyle)),
    'user': (message) => UserMessageBubble(message: message),
  };
  for (final entry in bubbles.entries) {
    testWidgets(
      '${entry.key} keeps its avatar and tail at the top as text grows',
      (tester) async {
        const messageKey = Key('growing-message');
        Future<void> show(String message) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(25),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyedSubtree(
                          key: messageKey,
                          child: entry.value(message),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Finder shapeFinder() => find.descendant(
          of: find.byKey(messageKey),
          matching: find.byType(ClipPath),
        );
        await show('Hello');
        final before = tester.getRect(shapeFinder());
        final avatarBefore = entry.key == 'user'
            ? null
            : tester.getRect(find.byType(AssistantAvatar));
        await show(List.filled(12, 'A longer inventory reply.').join('\n'));
        final after = tester.getRect(shapeFinder());
        expect(after.top, before.top);
        expect(after.bottom, greaterThan(before.bottom));
        if (avatarBefore != null) {
          expect(tester.getRect(find.byType(AssistantAvatar)), avatarBefore);
        }
        final shape = tester.widget<ClipPath>(shapeFinder());
        final path = shape.clipper!.getClip(after.size);
        final tipX = entry.key == 'user' ? after.width - 0.5 : 0.5;
        final tipY = avatarBefore == null
            ? 23.5
            : avatarBefore.center.dy - after.top;
        expect(path.contains(Offset(tipX, tipY)), isTrue);
        expect(path.contains(Offset(tipX, after.height / 2)), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('capture a long inventory reply for optional visual review', (
    tester,
  ) async {
    final directory = Platform.environment['ASSISTANT_CAPTURE_DIR'];
    if (directory == null) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      client: MockClient((_) async => throw StateError('No request expected')),
    );
    addTearDown(api.close);
    final agent = AgentController(
      WorkspaceRepository(api, MemoryTokens()),
      store: MemoryAgentStore(),
    );
    addTearDown(agent.dispose);
    await agent.bindUser('alice');
    agent.messages['user:report'] = 'Show me an inventory report';
    agent.messages['assistant:report'] =
        'There are 12 in-stock batches:\n\n'
        '- Arctic Box: Chicken Breast — 0.8 kg (expired Sep 27); apple — 5 pics.\n'
        '- BoschFridge: Whole Milk — 2 L (expired Oct 1); Apples — estimated 4 each; Chicken Eggs — 3 each and 5 pieces; Tomatoes — 2 each and 2 pieces.\n'
        '- Pantry Potter: Carrots — 1.6 kg; Rice — 1 kg and 1.5 kg; Apples — 2.3 kg.\n\n'
        'Also recorded: Greek Yoghurt is empty, Chocolate is discarded, and Olive Oil is archived.';
    const captureKey = Key('assistant-top-avatar-capture');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: const EdgeInsets.only(top: 47, bottom: 34)),
          child: RepaintBoundary(key: captureKey, child: child),
        ),
        home: AgentConversationScreen(
          controller: agent,
          displayName: 'qche584',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future.wait([
        for (final element in find.byType(Image).evaluate())
          precacheImage((element.widget as Image).image, element),
      ]);
    });
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/assistant-top-avatar.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('all bubble types wrap long unbroken text on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longWord = 'yangshuo_sjtu_account_identifier_12345678901234567890';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                children: const [
                  AssistantGreeting(message: 'Hey, $longWord! How can I help?'),
                  UserMessageBubble(message: longWord),
                  AssistantReply(
                    message: longWord,
                    textStyle: exampleMessageStyle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    for (final text in find.textContaining(longWord).evaluate()) {
      final rect = tester.getRect(
        find.byElementPredicate((element) => element == text),
      );
      expect(rect.height, greaterThan(25));
      expect(rect.right, lessThanOrEqualTo(295));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation bubbles wrap and keep matching vertical gaps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = ApiClient(
      client: MockClient((_) async => throw StateError('No request expected')),
    );
    addTearDown(api.close);
    final agent = AgentController(
      WorkspaceRepository(api, MemoryTokens()),
      store: MemoryAgentStore(),
    );
    addTearDown(agent.dispose);
    await agent.bindUser('alice');
    agent.messages['user:sample'] = 'Show me an inventory report';
    agent.messages['assistant:sample'] =
        '## Inventory report\n\nThere are no inventory batches or storage spaces '
        'listed in the results. Both queries returned page 1, with 0 items total.';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: const EdgeInsets.only(top: 47, bottom: 34)),
          child: child!,
        ),
        home: AgentConversationScreen(
          controller: agent,
          displayName: 'yangshuo_sjtu_with_a_long_account_name',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final greeting = find.text(
      'Hey, yangshuo_sjtu_with_a_long_account_name! How can I help you?',
    );
    final user = find.byType(UserMessageBubble);
    final reply = find.byType(AssistantReply);
    expect(greeting, findsOneWidget);
    expect(tester.widget<Text>(greeting).maxLines, isNull);
    expect(tester.getSize(greeting).height, greaterThan(30));
    expect(tester.getRect(greeting).right, lessThanOrEqualTo(365));
    expect(
      tester.getTopLeft(user).dy -
          tester.getBottomLeft(find.byType(AssistantGreeting)).dy,
      24,
    );
    expect(tester.getTopLeft(reply).dy - tester.getBottomLeft(user).dy, 24);
    expect(
      tester.widget<Text>(greeting).style?.fontSize,
      exampleMessageStyle.fontSize,
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(320, 568);
    await tester.pump();
    expect(tester.getRect(greeting).right, lessThanOrEqualTo(295));
    expect(tester.takeException(), isNull);
  });
}
