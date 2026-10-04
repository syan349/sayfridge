// These bytes are captured from FastAPI + isolated PostgreSQL, not invented SSE.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/state/agent_controller.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/models/inventory_item.dart';
import 'package:sayfridge/widgets/inventory_actions.dart';
import 'package:sayfridge/screens/agent_conversation_screen.dart';
import 'package:sayfridge/widgets/agent_proposal_options.dart';
import '../../mobile/test/support/integration_fixtures.dart';

void main() {
  final path = Platform.environment['AGENT_CLIENT_CAPTURE_FILE'] ?? '../backend/.venv/chat_client_traces.jsonl';
  final traces = File(path).readAsLinesSync().map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  final streams = traces.where((r) => r['status'] == 200 && (r['content_type'] as String).contains('event-stream')).toList();
  List<Map<String, dynamic>> events(Map<String, dynamic> r) => (r['body'] as String).split('\n')
      .where((s) => s.startsWith('data: ')).map((s) => jsonDecode(s.substring(6)) as Map<String, dynamic>).toList();

  test('unchanged Mobile parser consumes actual backend SSE and heartbeat comments', () async {
    expect(streams.length, greaterThan(10));
    for (final row in streams) {
      final client = ApiClient(client: MockClient((request) async => http.Response(
        ': keep-alive\n\n${row['body']}', 200, headers: {'content-type': row['content_type'] as String})));
      try {
        final actual = await client.events('/agent/chat', body: {}, accessToken: 'test-token').toList();
        expect(actual, events(row));
      } finally {
        client.close();
      }
    }
  });

  test('Mobile controller opens captured requests from history and retries their exact chat/resume payloads', () async {
    var checked = 0;
    final decisions = <String>{};
    for (final row in streams) {
      final original = Map<String, dynamic>.from(row['request'] as Map);
      if (original['conversation_id'] == null) continue;
      final parsed = events(row);
      if (parsed.last['type'] != 'done') continue;
      final terminal = Map<String, dynamic>.from(parsed.last['data'] as Map);
      final cid = original['conversation_id'] as String;
      for (final answer in original['responses'] as List? ?? []) {
        decisions.add(answer['decision'] as String);
      }
      final store = MemoryAgentStore();
      final relativePath = (row['path'] as String).replaceFirst('/api/v1', '');
      await store.write('compat-mobile', {'conversation_id': cid, 'messages': <String, String>{},
        'pending': {'path': relativePath, 'body': original}});
      var posts = 0, stateReads = 0;
      final client = ApiClient(client: MockClient((request) async {
        if (request.method == 'GET') {
          stateReads++;
          expect(request.url.path, '/api/v1/agent/conversations/$cid/state');
          return jsonResponse(terminal);
        }
        posts++;
        expect(request.url.path, row['path']);
        expect(jsonDecode(request.body), original);
        return http.Response(row['body'] as String, 200, headers: {'content-type': row['content_type'] as String});
      }));
      final controller = AgentController(WorkspaceRepository(client, MemoryTokens()), store: store);
      try {
        await controller.bindUser('compat-mobile');
        // Login/restart now shows welcome. Recovery remains an explicit history
        // action, with the original captured write preserved rather than replayed.
        expect(controller.conversationId, isNull);
        expect(controller.messages, isEmpty);
        expect(controller.canSend, isTrue);
        expect(controller.canRetry, isFalse);
        expect(controller.history.single.id, cid);
        expect(controller.history.single.pendingRequest, {'path': relativePath, 'body': original});
        expect(stateReads, 0);
        expect(posts, 0);
        await controller.bindUser('compat-mobile', reload: true);
        expect(controller.history.single.pendingRequest, {'path': relativePath, 'body': original});
        expect(stateReads, 0);
        expect(posts, 0);
        await controller.openConversation(cid);
        expect(stateReads, 1);
        expect(posts, 0);
        expect(controller.canRetry, isTrue);
        await controller.retry();
        expect(posts, 1);
        expect(controller.error, isNull);
        expect(controller.conversationId, cid);
        expect(controller.status, terminal['status']);
        expect(controller.items, terminal['items']);
        expect(controller.unresolved, isFalse);
        final saved = await store.read('compat-mobile');
        expect(saved?['pending'], isNull);
        checked++;
      } finally {
        controller.dispose();
        client.close();
      }
    }
    expect(checked, greaterThan(10));
    expect(decisions, containsAll(['confirm', 'answer', 'edit', 'cancel']));
  });

  for (final reason in ['NO_MATCH', 'AMBIGUOUS']) {
    Map<String, dynamic>? matchingReply(Map<String, dynamic> row, Map item) {
      for (final reply in streams) {
        if (!(reply['path'] as String).endsWith('/resume') ||
            reply['request']['conversation_id'] != row['request']['conversation_id']) continue;
        final answers = reply['request']['responses'] as List;
        if (answers.length != 1) continue;
        final answer = answers.single as Map;
        if (answer['decision'] != 'answer' || answer['item_id'] != item['item_id'] ||
            answer['proposal_id'] != item['proposal_id']) continue;
        if (reason == 'AMBIGUOUS') {
          final candidates = item['error']['details']['candidates'] as List;
          if (!candidates.any((candidate) => candidate['id'] == answer['selected_inventory_item_id']) ||
              answer.containsKey('message') || answer.containsKey('images')) continue;
        } else if (answer['message'] is! String || answer.containsKey('images') ||
            answer.containsKey('selected_inventory_item_id')) {
          continue;
        }
        final last = events(reply).last;
        if (last['type'] == 'done' && (last['data']['items'] as List).any((result) =>
            result['item_id'] == item['item_id'] && result['status'] == 'SUCCEEDED')) return reply;
      }
      return null;
    }
    final cases = streams.where((row) {
      final last = events(row).last;
      if (last['type'] != 'done') return false;
      final items = last['data']['items'] as List;
      if (items.length != 1 || items.single['status'] != 'NEEDS_INPUT' ||
          items.single['error']?['details']?['reason'] != reason) return false;
      return matchingReply(row, items.single as Map) != null;
    }).toList();
    testWidgets('unchanged Mobile displays $reason and submits the existing answer contract', (tester) async {
      final row = cases.first;
      final state = Map<String, dynamic>.from(events(row).last['data'] as Map);
      final item = Map<String, dynamic>.from((state['items'] as List).single as Map);
      final cid = row['request']['conversation_id'] as String;
      final reply = matchingReply(row, item)!;
      final expected = reply['request']['responses'][0] as Map;
      var posts = 0;
      final client = ApiClient(client: MockClient((request) async {
        if (request.method == 'GET') return jsonResponse(state);
        posts++;
        final sent = jsonDecode(request.body) as Map;
        expect(request.url.path, '/api/v1/agent/resume');
        expect(sent['conversation_id'], cid);
        expect(sent['interrupt_id'], state['interrupt_id']);
        expect(sent['responses'], [expected]);
        return http.Response(reply['body'] as String, 200, headers: {'content-type': reply['content_type'] as String});
      }));
      final store = MemoryAgentStore();
      await store.write('target-compat', {'conversation_id': cid, 'messages': <String, String>{}, 'status': 'WAITING_INPUT'});
      final controller = AgentController(WorkspaceRepository(client, MemoryTokens()), store: store);
      await controller.bindUser('target-compat');
      await controller.openConversation(cid);
      expect(controller.canRespond, isTrue);
      await tester.pumpWidget(MaterialApp(home: AgentConversationScreen(controller: controller)));
      await tester.pumpAndSettle();
      expect(find.text(item['display']['question'] as String), findsOneWidget);
      expect(find.text('inventory item id'), findsNothing);
      if (reason == 'AMBIGUOUS') {
        final candidates = item['error']['details']['candidates'] as List;
        final selected = candidates.indexWhere((candidate) => candidate['id'] == expected['selected_inventory_item_id']);
        expect(selected, greaterThanOrEqualTo(0));
        // Captured items need not be Apples; two batches may have identical labels.
        final choice = find.descendant(of: find.byType(AgentProposalOptions),
            matching: find.byType(OutlinedButton)).at(selected);
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(FilledButton, 'Confirm');
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
      } else {
        final bottom = find.byKey(const Key('assistant-bottom-action'));
        await tester.tap(find.descendant(of: bottom, matching: find.byTooltip('Type a message')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('assistant-answer-field')), expected['message'] as String);
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: bottom, matching: find.byTooltip('Send message')));
      }
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(controller.error, isNull);
      expect(controller.items.single['status'], 'SUCCEEDED');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      client.close();
    }, skip: cases.isEmpty);
  }

  testWidgets('existing expired discard cancels without a write, confirms and refreshes with the real backend result', (tester) async {
    final row = traces.firstWhere((r) => (r['path'] as String).endsWith('/discard') && r['status'] == 200
        && (jsonDecode(r['body'] as String) as Map)['expiry_date'] != null);
    final after = Map<String, dynamic>.from(jsonDecode(row['body'] as String) as Map);
    final request = Map<String, dynamic>.from(row['request'] as Map);
    // Discard preserves these exact facts. Its before version comes from the
    // backend-validated request; the response supplies the post-discard facts.
    final before = {...after, 'status': 'IN_STOCK', 'version': request['expected_version']};
    var item = InventoryItem.fromJson(before);
    var writes = 0, reloads = 0;
    final client = ApiClient(client: MockClient((incoming) async {
      if (incoming.method == 'GET') return jsonResponse(writes == 0 ? before : after);
      writes++;
      expect(incoming.url.path, row['path']);
      expect(jsonDecode(incoming.body), request);
      return jsonResponse(after);
    }));
    addTearDown(client.close);
    final workspace = WorkspaceRepository(client, MemoryTokens());
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, setState) => Scaffold(
      body: InventoryActions(item: item, workspace: workspace, reload: () async {
        reloads++;
        final current = await client.getJson('/inventory-items/${after['id']}', accessToken: 'test-token');
        setState(() => item = InventoryItem.fromJson(current));
      }),
    ))));
    expect(find.text('Discard item'), findsOneWidget);
    await tester.tap(find.text('Discard item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(item.status, 'IN_STOCK');
    await tester.tap(find.text('Discard item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(reloads, 2);
    expect(find.text('Discard item'), findsNothing);
    expect(item.status, 'DISCARDED');
    expect(item.displayQuantity, InventoryItem.fromJson(after).displayQuantity);
  });
}
