import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/agent_conversation_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/state/agent_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';
import '../support/integration_fixtures.dart';

void main() {
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
      expect(find.text('Status: FAILED'), findsOneWidget);
      expect(find.text('Not enough stock'), findsOneWidget);
      expect(find.text('Status: SUCCEEDED'), findsNothing);
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
