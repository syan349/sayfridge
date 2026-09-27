import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/state/agent_controller.dart';
import '../support/integration_fixtures.dart';

void main() {
  test(
    'rejected stale proposal reloads current state and unlocks the new proposal',
    () async {
      final oldItem = {
        'item_id': 'item',
        'proposal_id': 'old',
        'status': 'NEEDS_CONFIRMATION',
        'original_text': 'Use a cup',
      };
      final store = MemoryAgentStore();
      await store.write('alice', {'conversation_id': 'conversation'});
      var reads = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            reads++;
            return jsonResponse({
              'status': 'WAITING_INPUT',
              'interrupt_id': 'interrupt-$reads',
              'items': [
                {...oldItem, 'proposal_id': reads == 1 ? 'old' : 'new'},
              ],
            });
          }
          return jsonResponse({
            'detail': {'code': 'STALE_PROPOSAL'},
          }, 409);
        }),
      );
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: store,
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      await agent.respond(agent.items.single, 'confirm');
      expect(reads, 2);
      expect(agent.items.single['proposal_id'], 'new');
      expect(agent.canRespond, isTrue);
      expect(agent.canRetry, isFalse);
      expect(agent.error, contains('STALE_PROPOSAL'));
    },
  );

  test(
    'RECOVERABLE done retains the original request for explicit recovery',
    () async {
      final api = ApiClient(
        client: MockClient(
          (request) async => request.method == 'GET'
              ? jsonResponse({'status': 'RECOVERABLE', 'items': []})
              : eventResponse([
                  {
                    'type': 'done',
                    'status': 'RECOVERABLE',
                    'data': {'status': 'RECOVERABLE', 'items': []},
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
      await agent.send('Add stock');
      expect(agent.canSend, isFalse);
      expect(agent.canRetry, isFalse);
      await agent.recover();
      expect(agent.canRetry, isTrue);
    },
  );

  test(
    'SSE handles fragmented UTF-8, CRLF, heartbeat and multiline data',
    () async {
      final data = utf8.encode(
        ': heartbeat\r\nevent: text_delta\r\ndata: {"type":"text_delta",\r\ndata: "delta":"你好"}\r\n\r\ndata: {"type":"done","status":"COMPLETED"}\r\n\r\n',
      );
      final api = ApiClient(
        client: MockClient.streaming((request, body) async {
          expect(request.headers['Accept'], 'text/event-stream');
          expect(request.headers['Authorization'], 'Bearer token');
          await body.drain<void>();
          return http.StreamedResponse(
            Stream.fromIterable(data.map((byte) => [byte])),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      addTearDown(api.close);
      final events = await api
          .events(
            '/agent/chat',
            body: {'message': 'hello'},
            accessToken: 'token',
          )
          .toList();
      expect(events.map((e) => e['type']), ['text_delta', 'done']);
      expect(events.first['delta'], '你好');
    },
  );

  test(
    'waiting input is not success; confirmation sends only current identifiers',
    () async {
      final pending = {
        'item_id': 'item',
        'proposal_id': 'proposal',
        'status': 'NEEDS_CONFIRMATION',
        'original_text': 'Use a cup',
      };
      var calls = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          expect(request.headers['Authorization'], 'Bearer test-token');
          calls++;
          if (calls == 1) {
            expect(request.url.path, '/api/v1/agent/chat');
            expect(body['as_of'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
            return eventResponse([
              {
                'type': 'start',
                'conversation_id': body['conversation_id'],
                'request_id': body['request_id'],
              },
              {
                'type': 'action_required',
                'data': {
                  'interrupt_id': 'interrupt',
                  'items': [pending],
                },
              },
              {
                'type': 'done',
                'status': 'WAITING_INPUT',
                'data': {
                  'status': 'WAITING_INPUT',
                  'interrupt_id': 'interrupt',
                  'items': [pending],
                },
              },
            ]);
          }
          expect(request.url.path, '/api/v1/agent/resume');
          expect(body['interrupt_id'], 'interrupt');
          expect(body['responses'], [
            {
              'item_id': 'item',
              'proposal_id': 'proposal',
              'decision': 'confirm',
            },
          ]);
          return eventResponse([
            {
              'type': 'operation_result',
              'data': {...pending, 'status': 'SUCCEEDED'},
            },
            {
              'type': 'done',
              'status': 'COMPLETED',
              'data': {
                'status': 'COMPLETED',
                'items': [
                  {...pending, 'status': 'SUCCEEDED'},
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
      await agent.send('Use a cup');
      expect(calls, 1);
      expect(agent.waiting, isTrue);
      expect(agent.canSend, isFalse);
      expect(agent.canRespond, isTrue);
      await agent.respond(agent.items.single, 'confirm');
      expect(agent.items.single['status'], 'SUCCEEDED');
      expect(agent.canSend, isTrue);
    },
  );

  test(
    'lost stream queries state and retries the exact persisted body without duplicating items',
    () async {
      final posts = <String>[];
      var stateReads = 0;
      final store = MemoryAgentStore();
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            stateReads++;
            return jsonResponse({'status': 'RECOVERABLE', 'items': []});
          }
          posts.add(request.body);
          final body = jsonDecode(request.body);
          expect(jsonDecode(store.values['alice']!)['pending']['body'], body);
          if (posts.length == 1) {
            return eventResponse([
              {'type': 'start', 'conversation_id': body['conversation_id']},
            ]);
          }
          return eventResponse([
            {'type': 'text_delta', 'delta': 'Done'},
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
        store: store,
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      await agent.send('Add 1 kg');
      expect(agent.unresolved, isTrue);
      expect(stateReads, 1);
      expect(agent.canRetry, isTrue);
      await agent.send('Duplicate');
      expect(posts, hasLength(1));
      await agent.retry();
      expect(posts[0], posts[1]);
      expect(agent.unresolved, isFalse);
      expect(jsonDecode(store.values['alice']!)['pending'], isNull);
    },
  );

  test(
    'a recreated controller restores pending identity and does not automatically replay a write',
    () async {
      final store = MemoryAgentStore();
      await store.write('alice', {
        'conversation_id': 'conversation',
        'pending': {
          'path': '/agent/chat',
          'body': {
            'conversation_id': 'conversation',
            'request_id': 'original',
            'message': 'add',
          },
        },
      });
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          return jsonResponse({'status': 'RECOVERABLE', 'items': []});
        }),
      );
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: store,
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      expect(agent.conversationId, 'conversation');
      expect(agent.canRetry, isTrue);
      expect(agent.canSend, isFalse);
    },
  );

  test(
    'late response from previous account cannot repopulate the new account',
    () async {
      final response = Completer<http.Response>();
      final entered = Completer<void>();
      final api = ApiClient(
        client: MockClient((request) async {
          entered.complete();
          return response.future;
        }),
      );
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: MemoryAgentStore(),
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      final turn = agent.send('Alice private inventory');
      await entered.future;
      await agent.bindUser('bob');
      response.complete(
        eventResponse([
          {'type': 'text_delta', 'delta': 'Alice private reply'},
          {'type': 'done', 'status': 'COMPLETED'},
        ]),
      );
      await turn;
      expect(agent.messages, isEmpty);
      expect(agent.items, isEmpty);
      expect(agent.conversationId, isNull);
    },
  );
}
