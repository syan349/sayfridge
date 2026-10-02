import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/agent_conversation_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/state/agent_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';

import '../support/integration_fixtures.dart';

class _ScrollAgent extends AgentController {
  _ScrollAgent(super.workspace) : super(store: MemoryAgentStore());

  void update() => notifyListeners();
}

void main() {
  late _ScrollAgent agent;

  setUp(() {
    final api = ApiClient(client: MockClient((_) async => jsonResponse({})));
    addTearDown(api.close);
    agent = _ScrollAgent(WorkspaceRepository(api, MemoryTokens()));
    addTearDown(agent.dispose);
    agent.conversationId = 'existing';
    for (var i = 0; i < 30; i++) {
      agent.messages['assistant:$i'] = 'Older message $i';
    }
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AgentConversationScreen(controller: agent),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  testWidgets('entry and re-entry show the latest message', (tester) async {
    await open(tester);
    expect(position(tester).maxScrollExtent, greaterThan(0));
    expect(position(tester).extentAfter, closeTo(0, 1));
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(position(tester).extentAfter, greaterThan(80));
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    expect(position(tester).extentAfter, closeTo(0, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reply growth follows bottom but preserves reading history', (
    tester,
  ) async {
    await open(tester);
    agent.messages['assistant:29'] = List.filled(
      15,
      'Growing reply',
    ).join('\n');
    agent.update();
    await tester.pumpAndSettle();
    expect(position(tester).extentAfter, closeTo(0, 1));

    await tester.drag(find.byType(ListView).first, const Offset(0, 450));
    await tester.pumpAndSettle();
    final readingOffset = position(tester).pixels;
    agent.messages['assistant:29'] = List.filled(
      25,
      'Growing reply',
    ).join('\n');
    agent.update();
    await tester.pumpAndSettle();
    expect(position(tester).pixels, closeTo(readingOffset, 1));
    expect(position(tester).extentAfter, greaterThan(80));

    agent.messages['user:new'] = 'My next question';
    agent.update();
    await tester.pumpAndSettle();
    expect(position(tester).extentAfter, closeTo(0, 1));
  });

  testWidgets(
    'conversation switch resets position and empty chat stays at top',
    (tester) async {
      await open(tester);
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      agent.conversationId = 'from-history';
      agent.update();
      await tester.pumpAndSettle();
      expect(position(tester).extentAfter, closeTo(0, 1));

      agent.messages.clear();
      agent.conversationId = null;
      agent.update();
      await tester.pumpAndSettle();
      expect(position(tester).pixels, 0);
      expect(find.text('Hey! How can I help you?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard resizing keeps latest content visible', (tester) async {
    await open(tester);
    addTearDown(tester.view.resetViewInsets);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(position(tester).extentAfter, closeTo(0, 1));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(position(tester).extentAfter, closeTo(0, 1));
    expect(tester.takeException(), isNull);
  });
}
