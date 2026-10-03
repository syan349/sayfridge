import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sayfridge/models/agent_image.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/state/agent_controller.dart';
import '../support/integration_fixtures.dart';

void main() {
  test(
    'query cards stay with their reply through history, recovery and user changes',
    () async {
      final store = MemoryAgentStore();
      var count = 0;
      String? lastRequest;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return jsonResponse({
              'request_id': lastRequest,
              'status': 'COMPLETED',
              'items': [],
            });
          }
          final body = jsonDecode(request.body) as Map;
          expect(request.headers['x-sayfridge-inventory-cards'], '1');
          lastRequest = body['request_id'] as String;
          return eventResponse([
            {'type': 'text_delta', 'delta': 'Here is what I found.'},
            {
              'type': 'done',
              'data': {
                'request_id': lastRequest,
                'status': 'COMPLETED',
                'items': [],
                if (++count == 1)
                  'inventory_query': {
                    'items': [stockJson()],
                    'total': 1,
                    'has_more': false,
                  },
              },
            },
          ]);
        }),
      );
      addTearDown(api.close);
      final workspace = WorkspaceRepository(api, MemoryTokens());
      final first = AgentController(workspace, store: store);
      await first.bindUser('alice');
      await first.send('What is in my fridge?');
      final queryReply = first.inventoryQueries.keys.single;
      final conversation = first.conversationId!;
      expect(first.inventoryQueries[queryReply]!.items.single.id, 'item-1');
      await first.send('Generate a report');
      expect(first.inventoryQueries.keys, [queryReply]);
      await first.newConversation();
      expect(first.inventoryQueries, isEmpty);
      expect(first.history.single.inventoryQueries.keys, [queryReply]);
      first.dispose();
      final restored = AgentController(workspace, store: store);
      addTearDown(restored.dispose);
      await restored.bindUser('alice');
      await restored.openConversation(conversation);
      expect(
        restored.inventoryQueries[queryReply]!.items.single.displayAmount,
        1.5,
      );
      await restored.bindUser('bob');
      expect(restored.messages, isEmpty);
      expect(restored.inventoryQueries, isEmpty);
      expect(restored.history, isEmpty);
    },
  );

  test(
    'earlier conversations survive restart and reopen with their messages',
    () async {
      final store = MemoryAgentStore();
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return jsonResponse({'status': 'COMPLETED', 'items': []});
          }
          return eventResponse([
            {'type': 'text_delta', 'delta': 'Saved reply'},
            {
              'type': 'done',
              'status': 'COMPLETED',
              'data': {'status': 'COMPLETED', 'items': []},
            },
          ]);
        }),
      );
      addTearDown(api.close);
      final workspace = WorkspaceRepository(api, MemoryTokens());
      final first = AgentController(workspace, store: store);
      await first.bindUser('alice');
      await first.send('First question');
      final firstId = first.conversationId!;
      await first.newConversation();
      expect(first.history.single.title, 'First question');
      await first.send('Second question');
      first.dispose();

      final restored = AgentController(workspace, store: store);
      addTearDown(restored.dispose);
      await restored.bindUser('alice');
      expect(restored.conversationId, isNull);
      expect(restored.messages, isEmpty);
      expect(restored.canSend, isTrue);
      expect(restored.history.map((entry) => entry.title), [
        'Second question',
        'First question',
      ]);
      await restored.openConversation(firstId);
      expect(restored.conversationId, firstId);
      expect(
        restored.messages.values,
        containsAll(['First question', 'Saved reply']),
      );
      expect(restored.history.single.title, 'Second question');
    },
  );

  test('image-only supplement replaces the pending proposal version', () async {
    const oldItem = {
      'item_id': 'item',
      'proposal_id': 'old-proposal',
      'status': 'NEEDS_INPUT',
      'original_text': 'Unknown package',
    };
    const newItem = {
      'item_id': 'item',
      'proposal_id': 'new-proposal',
      'status': 'NEEDS_CONFIRMATION',
      'original_text': 'Milk 1 bottle',
    };
    final image = AgentImage.fromBytes(
      Uint8List.fromList([0xff, 0xd8, 0xff]),
      mimeType: 'image/jpeg',
      imageId: '00000000-0000-4000-8000-000000000007',
    );
    var calls = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (calls == 1) {
          return eventResponse([
            {
              'type': 'done',
              'status': 'WAITING_INPUT',
              'data': {
                'status': 'WAITING_INPUT',
                'interrupt_id': 'interrupt-old',
                'items': [oldItem],
              },
            },
          ]);
        }
        expect(request.url.path, '/api/v1/agent/resume');
        expect(body['interrupt_id'], 'interrupt-old');
        expect(body['responses'], [
          {
            'item_id': 'item',
            'proposal_id': 'old-proposal',
            'decision': 'answer',
            'images': [image.toJson()],
          },
        ]);
        return eventResponse([
          {
            'type': 'action_required',
            'data': {
              'interrupt_id': 'interrupt-new',
              'items': [newItem],
            },
          },
          {
            'type': 'done',
            'status': 'WAITING_INPUT',
            'data': {
              'status': 'WAITING_INPUT',
              'interrupt_id': 'interrupt-new',
              'items': [newItem],
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
    await agent.send('What is this?');
    expect(agent.items.single['proposal_id'], 'old-proposal');
    await agent.respond(agent.items.single, 'answer', images: [image]);
    expect(agent.items.single['proposal_id'], 'new-proposal');
    expect(agent.interruptId, 'interrupt-new');
    expect(agent.canRespond, isTrue);
  });

  test(
    'image-only chat sends the backend contract and preserves retry IDs',
    () async {
      final posts = <Map<String, dynamic>>[];
      final image = AgentImage.fromBytes(
        Uint8List.fromList([0xff, 0xd8, 0xff]),
        mimeType: 'image/jpeg',
        imageId: '00000000-0000-4000-8000-000000000006',
      );
      var stateReads = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            stateReads++;
            return jsonResponse({'status': 'RECOVERABLE', 'items': []});
          }
          posts.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (posts.length == 1) {
            return eventResponse([
              {
                'type': 'start',
                'conversation_id': posts.single['conversation_id'],
              },
            ]);
          }
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
      await agent.send('', images: [image]);

      expect(stateReads, 1);
      expect(agent.canRetry, isTrue);
      expect(
        posts.single['message'],
        contains('prepare inventory entries for review'),
      );
      expect(posts.single['message'], contains('Wait for my confirmation'));
      expect(agent.messages.values, contains('Photo attached'));
      expect(posts.single['images'], [image.toJson()]);
      await agent.retry();
      expect(posts, hasLength(2));
      expect(posts[1], posts[0]);
    },
  );

  test(
    'failed supporting-photo response retries the exact proposal and image IDs',
    () async {
      const item = {
        'item_id': 'item',
        'proposal_id': 'proposal',
        'status': 'NEEDS_INPUT',
        'original_text': 'Unknown package',
      };
      final image = AgentImage.fromBytes(
        Uint8List.fromList([0xff, 0xd8, 0xff]),
        mimeType: 'image/jpeg',
        imageId: '00000000-0000-4000-8000-000000000008',
      );
      final resumePosts = <Map<String, dynamic>>[];
      var chatComplete = false;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return jsonResponse({
              'status': 'RECOVERABLE',
              'interrupt_id': 'interrupt',
              'items': [item],
            });
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (!chatComplete) {
            chatComplete = true;
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
          resumePosts.add(body);
          if (resumePosts.length == 1) {
            return eventResponse([
              {'type': 'start', 'conversation_id': body['conversation_id']},
            ]);
          }
          return eventResponse([
            {
              'type': 'done',
              'status': 'WAITING_INPUT',
              'data': {
                'status': 'WAITING_INPUT',
                'interrupt_id': 'interrupt-new',
                'items': [
                  {...item, 'proposal_id': 'proposal-new'},
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
      await agent.send('What is this?');
      await agent.respond(agent.items.single, 'answer', images: [image]);

      expect(agent.canRetry, isTrue);
      expect(resumePosts.single['responses'], [
        {
          'item_id': 'item',
          'proposal_id': 'proposal',
          'decision': 'answer',
          'images': [image.toJson()],
        },
      ]);
      await agent.retry();
      expect(resumePosts, hasLength(2));
      expect(resumePosts[1], resumePosts[0]);
      expect(agent.items.single['proposal_id'], 'proposal-new');
    },
  );

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
      await agent.openConversation('conversation');
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
    'restart opens a fresh session and keeps the exact pending request for explicit history recovery',
    () async {
      final store = MemoryAgentStore();
      const pending = {
        'path': '/agent/resume',
        'body': {
          'conversation_id': 'conversation',
          'interrupt_id': 'interrupt-original',
          'request_id': 'original',
          'responses': [
            {
              'item_id': 'milk',
              'proposal_id': 'proposal-original',
              'decision': 'cancel',
            },
          ],
        },
      };
      await store.write('alice', {
        'conversation_id': 'conversation',
        'pending': pending,
      });
      var reads = 0;
      final posts = <String>[];
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            reads++;
            expect(
              request.url.path,
              endsWith('/conversations/conversation/state'),
            );
            return jsonResponse({'status': 'RECOVERABLE', 'items': []});
          }
          expect(request.url.path, endsWith('/agent/resume'));
          posts.add(request.body);
          expect(jsonDecode(request.body), pending['body']);
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
        store: store,
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      expect(agent.conversationId, isNull);
      expect(agent.canSend, isTrue);
      expect(agent.history.single.pendingRequest, pending);
      expect(reads, 0);
      expect(posts, isEmpty);
      expect((await store.read('alice'))!['history'][0]['pending'], pending);
      // A second restart still keeps the archived request without replaying it.
      await agent.bindUser('alice', reload: true);
      expect(agent.history.single.pendingRequest, pending);
      expect(reads, 0);
      await agent.openConversation('conversation');
      expect(agent.conversationId, 'conversation');
      expect(reads, 1);
      expect(posts, isEmpty);
      expect(agent.canRetry, isTrue);
      expect(agent.canSend, isFalse);
      await agent.retry();
      expect(posts, hasLength(1));
      expect(agent.canSend, isTrue);
      expect((await store.read('alice'))!['pending'], isNull);
    },
  );

  test(
    'signing in again shows welcome and restores waiting proposals only from history',
    () async {
      final store = MemoryAgentStore();
      await store.write('alice', {
        'conversation_id': 'waiting-conversation',
        'status': 'WAITING_INPUT',
        'messages': {'user:original': 'I consumed 3 cups of milk'},
      });
      var reads = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          reads++;
          return jsonResponse({
            'status': 'WAITING_INPUT',
            'interrupt_id': 'milk-interrupt',
            'items': [
              {
                'item_id': 'milk',
                'proposal_id': 'milk-proposal',
                'status': 'NEEDS_INPUT',
                'original_text': 'I consumed 3 cups of milk',
              },
            ],
          });
        }),
      );
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: store,
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      expect(agent.messages, isEmpty);
      expect(agent.canSend, isTrue);
      expect(reads, 0);
      await agent.openConversation('waiting-conversation');
      expect(agent.canRespond, isTrue);
      expect(agent.items.single['proposal_id'], 'milk-proposal');
      await agent.bindUser('alice');
      expect(agent.conversationId, 'waiting-conversation');
      await agent.bindUser(null);
      await agent.bindUser('bob');
      expect(agent.history, isEmpty);
      await agent.bindUser('alice');
      expect(agent.conversationId, isNull);
      expect(agent.messages, isEmpty);
      expect(agent.canSend, isTrue);
      expect(agent.history.single.status, 'WAITING_INPUT');
      expect(reads, 1);
    },
  );

  test(
    'history retention never evicts an unfinished request identity',
    () async {
      final store = MemoryAgentStore();
      const pending = {
        'path': '/agent/chat',
        'body': {
          'conversation_id': 'unfinished',
          'request_id': 'original',
          'message': 'Add milk',
        },
      };
      await store.write('alice', {
        'conversation_id': 'latest',
        'status': 'COMPLETED',
        'messages': {'user:latest': 'Latest question'},
        'history': [
          for (var i = 0; i < 19; i++)
            {
              'id': 'completed-$i',
              'messages': {'user:$i': 'Question $i'},
              'status': 'COMPLETED',
            },
          {
            'id': 'unfinished',
            'messages': {},
            'pending': pending,
            'status': 'RECOVERABLE',
          },
        ],
      });
      final api = ApiClient(
        client: MockClient((request) async {
          fail('Startup must not call the Agent API');
        }),
      );
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: store,
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      expect(agent.history, hasLength(20));
      expect(agent.history.first.id, 'latest');
      expect(agent.history.last.id, 'unfinished');
      expect(agent.history.last.pendingRequest, pending);
      expect(agent.canSend, isTrue);
      await agent.bindUser('alice', reload: true);
      expect(agent.history.last.pendingRequest, pending);
    },
  );

  test(
    'opening history waits for server state before permitting a new write',
    () async {
      final store = MemoryAgentStore();
      await store.write('alice', {
        'history': [
          {
            'id': 'saved',
            'messages': {'user:old': 'Add milk'},
            'status': 'COMPLETED',
          },
        ],
      });
      var reads = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          return ++reads == 1
              ? jsonResponse({'detail': 'Unavailable'}, 503)
              : jsonResponse({'status': 'COMPLETED', 'items': []});
        }),
      );
      addTearDown(api.close);
      final agent = AgentController(
        WorkspaceRepository(api, MemoryTokens()),
        store: store,
      );
      addTearDown(agent.dispose);
      await agent.bindUser('alice');
      expect(reads, 0);
      await agent.openConversation('saved');
      expect(agent.messages.values, contains('Add milk'));
      expect(agent.canSend, isFalse);
      expect(agent.canRetry, isFalse);
      await agent.send('Duplicate milk');
      expect(reads, 1);
      await agent.recover();
      expect(reads, 2);
      expect(agent.canSend, isTrue);
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
