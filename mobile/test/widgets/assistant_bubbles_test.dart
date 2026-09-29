import 'package:flutter/material.dart';
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
