import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/agent_image.dart';
import '../models/agent_inventory_query.dart';
import '../repositories/workspace_repository.dart';
import '../services/agent_session_store.dart';
import '../services/api_exception.dart';

class SavedConversation {
  const SavedConversation({
    required this.id,
    required this.messages,
    required this.updatedAt,
    this.messageImages = const {},
    this.inventoryQueries = const {},
  });

  final String id;
  final Map<String, String> messages;
  final DateTime updatedAt;
  final Map<String, List<AgentImage>> messageImages;
  final Map<String, AgentInventoryQuery> inventoryQueries;

  String get title {
    for (final entry in messages.entries) {
      if (entry.key.startsWith('user:') && entry.value.trim().isNotEmpty) {
        return entry.value.trim();
      }
    }
    return 'Conversation';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'messages': messages,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    if (messageImages.isNotEmpty) 'message_images': _saveImages(messageImages),
    if (inventoryQueries.isNotEmpty)
      'inventory_queries': _saveQueries(inventoryQueries),
  };

  static SavedConversation? fromJson(Object? value) {
    if (value is! Map || value['id'] is! String) return null;
    return SavedConversation(
      id: value['id'] as String,
      messages: _readMessages(value['messages']),
      messageImages: _readImages(value['message_images']),
      inventoryQueries: _readQueries(value['inventory_queries']),
      updatedAt:
          DateTime.tryParse(value['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

Map<String, dynamic> _saveQueries(Map<String, AgentInventoryQuery> queries) => {
  for (final entry in queries.entries) entry.key: entry.value.toJson(),
};

Map<String, AgentInventoryQuery> _readQueries(Object? value) {
  final result = <String, AgentInventoryQuery>{};
  if (value is! Map) return result;
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! Map) continue;
    try {
      result[entry.key as String] = AgentInventoryQuery.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    } catch (_) {
      // A damaged cached snapshot must not prevent recovering the conversation.
    }
  }
  return result;
}

Map<String, String> _readMessages(Object? value) {
  if (value is! Map) return {};
  return {
    for (final entry in value.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  };
}

Map<String, dynamic> _saveImages(Map<String, List<AgentImage>> images) => {
  for (final entry in images.entries)
    entry.key: entry.value.map((image) => image.toJson()).toList(),
};

Map<String, List<AgentImage>> _readImages(Object? value) {
  if (value is! Map) return {};
  final result = <String, List<AgentImage>>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! List) continue;
    try {
      final photos = (entry.value as List)
          .map(
            (photo) =>
                AgentImage.fromJson(Map<String, dynamic>.from(photo as Map)),
          )
          .toList();
      AgentImage.validateBatch(photos);
      result[entry.key as String] = List.unmodifiable(photos);
    } catch (_) {
      // Older/corrupt photo records must not prevent transcript recovery.
    }
  }
  return result;
}

class AgentController extends ChangeNotifier {
  AgentController(
    this.workspace, {
    this.store = const AgentSessionStore(),
    this.onInventoryChanged,
  });
  final WorkspaceRepository workspace;
  final AgentSessionStore store;
  final Future<void> Function()? onInventoryChanged;
  String? _user, conversationId, interruptId, error;
  String status = 'COMPLETED';
  bool busy = false, _verified = false, _disposed = false;
  bool _sessionLoaded = false;
  int _generation = 0;
  Map<String, dynamic>? _pending;
  final Map<String, Map<String, dynamic>> _items = {};
  final Map<String, String> messages = {};
  final Map<String, List<AgentImage>> messageImages = {};
  final Map<String, AgentInventoryQuery> inventoryQueries = {};
  final List<SavedConversation> _history = [];
  List<SavedConversation> get history => List.unmodifiable(_history);
  List<Map<String, dynamic>> get items => _items.values.toList();
  bool get unresolved => _pending != null || status == 'RECOVERABLE';
  bool get waiting => status == 'WAITING_INPUT';
  bool get canSend =>
      _user != null && _sessionLoaded && !busy && !unresolved && !waiting;
  bool get canRetry => !busy && _pending != null && _verified;
  bool get canRespond =>
      _user != null && !busy && !unresolved && waiting && interruptId != null;
  bool _current(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> bindUser(String? user, {bool reload = false}) async {
    if (user == _user && !reload) return;
    final generation = ++_generation;
    _user = user;
    _sessionLoaded = false;
    _clear();
    busy = user != null;
    _notify();
    if (user == null) return;
    try {
      final saved = await store.read(user);
      if (!_current(generation)) return;
      _sessionLoaded = true;
      conversationId = saved?['conversation_id'] as String?;
      _pending = saved?['pending'] as Map<String, dynamic>?;
      messages.addAll(_readMessages(saved?['messages']));
      messageImages.addAll(_readImages(saved?['message_images']));
      inventoryQueries.addAll(_readQueries(saved?['inventory_queries']));
      final savedHistory = saved?['history'];
      if (savedHistory is List) {
        for (final record in savedHistory) {
          final conversation = SavedConversation.fromJson(record);
          if (conversation != null && conversation.id != conversationId) {
            _history.add(conversation);
          }
        }
      }
      if (conversationId != null) {
        status = 'RECOVERABLE';
        await _readState(generation);
      }
    } catch (e) {
      if (_current(generation)) error = businessError(e);
    } finally {
      if (_current(generation)) {
        busy = false;
        _notify();
      }
    }
  }

  void _clear() {
    conversationId = interruptId = error = null;
    _pending = null;
    _verified = false;
    status = 'COMPLETED';
    _items.clear();
    messages.clear();
    messageImages.clear();
    inventoryQueries.clear();
    _history.clear();
    busy = false;
  }

  Future<void> _persist() async {
    final user = _user;
    final generation = _generation;
    if (user != null) {
      for (final entry in Map.of(messageImages).entries) {
        final previews = <AgentImage>[];
        for (final image in entry.value) {
          previews.add(await image.thumbnail());
        }
        if (!_current(generation)) return;
        messageImages[entry.key] = List.unmodifiable(previews);
      }
      await store.write(user, {
        'conversation_id': conversationId,
        'pending': _pending,
        'messages': messages,
        if (messageImages.isNotEmpty)
          'message_images': _saveImages(messageImages),
        if (inventoryQueries.isNotEmpty)
          'inventory_queries': _saveQueries(inventoryQueries),
        'history': _history.map((entry) => entry.toJson()).toList(),
      });
    }
  }

  Future<void> newConversation() async {
    if (!canSend) return; // Do not lose unresolved receipt/request identities.
    _archiveCurrent();
    _resetCurrent();
    busy = true;
    final generation = _generation;
    try {
      await _persist();
    } catch (e) {
      if (_current(generation)) error = businessError(e);
    }
    if (_current(generation)) {
      busy = false;
      _notify();
    }
  }

  void _archiveCurrent() {
    final id = conversationId;
    if (id == null || messages.isEmpty) return;
    _history.removeWhere((entry) => entry.id == id);
    _history.insert(
      0,
      SavedConversation(
        id: id,
        messages: Map.of(messages),
        messageImages: Map.of(messageImages),
        inventoryQueries: Map.of(inventoryQueries),
        updatedAt: DateTime.now(),
      ),
    );
    // The device keeps a bounded list; the server remains the source of truth
    // for inventory actions and pending requests.
    if (_history.length > 20) _history.removeRange(20, _history.length);
  }

  void _resetCurrent() {
    conversationId = interruptId = error = null;
    _pending = null;
    _verified = false;
    status = 'COMPLETED';
    _items.clear();
    messages.clear();
    messageImages.clear();
    inventoryQueries.clear();
  }

  Future<void> openConversation(String id) async {
    if (!canSend || id == conversationId) return;
    final index = _history.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final selected = _history.removeAt(index);
    _archiveCurrent();
    _resetCurrent();
    conversationId = selected.id;
    messages.addAll(selected.messages);
    messageImages.addAll(selected.messageImages);
    inventoryQueries.addAll(selected.inventoryQueries);
    busy = true;
    _notify();
    final generation = _generation;
    try {
      await _persist();
      await _readState(generation);
    } catch (e) {
      if (_current(generation)) error = businessError(e);
    } finally {
      if (_current(generation)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> send(
    String text, {
    List<AgentImage> images = const [],
    String? displayText,
  }) async {
    final enteredText = text.trim();
    final message = enteredText.isEmpty && images.isNotEmpty
        ? 'Recognise the items in these photos and prepare inventory entries for review. '
              'Show the recognised items directly without asking whether to read or add them. '
              'Wait for my confirmation before saving.'
        : enteredText;
    if (!canSend || (message.isEmpty && images.isEmpty)) return;
    if (message.length > 8000) {
      error = 'Maximum 8000 characters.';
      _notify();
      return;
    }
    try {
      AgentImage.validateBatch(images);
    } on FormatException catch (e) {
      error = e.message;
      _notify();
      return;
    }
    final id = requestId();
    conversationId ??= requestId();
    _items.clear();
    interruptId = null;
    messages['user:$id'] =
        displayText ?? (enteredText.isEmpty ? 'Photo attached' : enteredText);
    if (images.isNotEmpty) {
      messageImages['user:$id'] = List.unmodifiable(images);
    }
    _pending = {
      'path': '/agent/chat',
      'body': {
        'message': message,
        if (images.isNotEmpty)
          'images': images.map((image) => image.toJson()).toList(),
        'conversation_id': conversationId,
        'request_id': id,
        'as_of': dateInput(DateTime.now()),
      },
    };
    await _run();
  }

  Future<void> respond(
    Map<String, dynamic> item,
    String decision, {
    String? message,
    String? selectedId,
    List<AgentImage> images = const [],
  }) async {
    if (!canRespond) return;
    final current = _items[item['item_id']];
    if (current == null || current['proposal_id'] != item['proposal_id']) {
      return;
    }
    final answer = <String, dynamic>{
      'item_id': item['item_id'],
      'proposal_id': item['proposal_id'],
      'decision': decision,
    };
    if (decision == 'answer' || decision == 'edit') {
      try {
        AgentImage.validateBatch(images);
      } on FormatException catch (e) {
        error = e.message;
        _notify();
        return;
      }
      if ((message ?? '').trim().isNotEmpty) {
        answer['message'] = message!.trim();
      }
      if (selectedId != null) answer['selected_inventory_item_id'] = selectedId;
      if (images.isNotEmpty) {
        answer['images'] = images.map((image) => image.toJson()).toList();
      }
      if (answer.length == 3) return;
    }
    final responseId = requestId();
    if (images.isNotEmpty) {
      messages['user:$responseId'] = (message ?? '').trim().isEmpty
          ? 'Photo attached'
          : message!.trim();
      messageImages['user:$responseId'] = List.unmodifiable(images);
    }
    _pending = {
      'path': '/agent/resume',
      'body': {
        'conversation_id': conversationId,
        'interrupt_id': interruptId,
        'request_id': responseId,
        'responses': [answer],
      },
    };
    await _run();
  }

  Future<void> retry() async {
    if (canRetry) await _run();
  }

  List<Map<String, dynamic>> get confirmableItems => items
      .where(
        (item) =>
            item['status'] == 'NEEDS_CONFIRMATION' &&
            (item['error'] as Map?)?['code'] != 'EXECUTION_UNCERTAIN',
      )
      .toList();

  Future<void> confirmItems(List<Map<String, dynamic>> selected) async {
    if (!canRespond || selected.isEmpty || selected.length > 20) return;
    final answers = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final item in selected) {
      final id = item['item_id'] as String?;
      final current = _items[id];
      if (id == null ||
          !ids.add(id) ||
          current == null ||
          current['proposal_id'] != item['proposal_id'] ||
          current['status'] != 'NEEDS_CONFIRMATION' ||
          (current['error'] as Map?)?['code'] == 'EXECUTION_UNCERTAIN') {
        error =
            'These proposals have changed. Review the current items before confirming.';
        _notify();
        return;
      }
      answers.add({
        'item_id': id,
        'proposal_id': current['proposal_id'],
        'decision': 'confirm',
      });
    }
    _pending = {
      'path': '/agent/resume',
      'body': {
        'conversation_id': conversationId,
        'interrupt_id': interruptId,
        'request_id': requestId(),
        'responses': answers,
      },
    };
    await _run();
  }

  Future<void> recover() async {
    if (busy) return;
    if (!_sessionLoaded) {
      await bindUser(_user, reload: true);
      return;
    }
    if (conversationId == null) return;
    final generation = _generation;
    busy = true;
    error = null;
    _notify();
    try {
      await _readState(generation);
    } catch (e) {
      if (_current(generation)) {
        error = businessError(e);
        _verified = false;
      }
    } finally {
      if (_current(generation)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> _readState(int generation) async {
    final id = conversationId;
    final token = await workspace.accessToken();
    if (!_current(generation)) return;
    try {
      final state = await workspace.client.getJson(
        '/agent/conversations/$id/state',
        accessToken: token,
      );
      if (!_current(generation)) return;
      _applyState(state);
      _verified = true;
    } on ApiException catch (e) {
      if (!_current(generation)) return;
      if (e.isNotFound && _pending != null) {
        // The first POST may never have reached the server. Same-ID retry is safe.
        _verified = true;
      } else {
        rethrow;
      }
    }
  }

  void _mergeItems(Object? rows) {
    if (rows is! List) return;
    for (final row in rows) {
      final item = Map<String, dynamic>.from(row as Map);
      _items[item['item_id'] as String] = item;
    }
  }

  void _applyState(Map<String, dynamic> state, {String? replyKey}) {
    status = state['status'] as String? ?? status;
    interruptId = state['interrupt_id'] as String?;
    _items.clear();
    _mergeItems(state['items']);
    final pending = state['pending'];
    if (pending is Map) _mergeItems(pending['items']);
    final query = state['inventory_query'];
    final key = replyKey ?? 'assistant:${state['request_id']}';
    if (query is Map && messages.containsKey(key)) {
      inventoryQueries[key] = AgentInventoryQuery.fromJson(
        Map<String, dynamic>.from(query),
      );
    }
  }

  Future<void> _run() async {
    final pending = _pending;
    if (pending == null || busy || _user == null) return;
    final generation = _generation;
    final body = Map<String, dynamic>.from(pending['body'] as Map);
    final replyKey = 'assistant:${body['request_id']}';
    busy = true;
    _verified = false;
    error = null;
    messages[replyKey] = '';
    inventoryQueries.remove(replyKey);
    _notify();
    var terminal = false;
    try {
      await _persist(); // Persist exact retry payload BEFORE any possible side effect.
      if (!_current(generation)) return;
      final token = await workspace.accessToken();
      if (!_current(generation)) return;
      await for (final event in workspace.client.events(
        pending['path'] as String,
        body: body,
        accessToken: token,
      )) {
        if (!_current(generation)) return;
        final data = event['data'] as Map<String, dynamic>?;
        switch (event['type']) {
          case 'start':
            if (event['conversation_id'] != conversationId) {
              throw const FormatException('Unexpected conversation');
            }
          case 'text_delta':
            messages[replyKey] = '${messages[replyKey]}${event['delta'] ?? ''}';
          case 'operation_preview':
          case 'operation_result':
            if (data != null) _mergeItems([data]);
          case 'action_required':
            if (data != null) {
              interruptId = data['interrupt_id'] as String?;
              _mergeItems(data['items']);
              status = 'WAITING_INPUT';
            }
          case 'done':
            if (data != null) _applyState(data, replyKey: replyKey);
            status = event['status'] as String? ?? status;
            terminal = true;
            // RECOVERABLE is a checkpoint, not a completed acknowledgement.
            // Preserve the exact request even if the server ends its SSE stream.
            if (status != 'RECOVERABLE') _pending = null;
            await _persist();
          case 'error':
            throw ApiException(
              statusCode: 503,
              code: event['code'] as String?,
              message:
                  event['message'] as String? ??
                  'Agent execution was interrupted.',
            );
        }
        _notify();
        if (terminal) break;
      }
      if (!terminal) {
        throw const FormatException(
          'Agent stream ended before acknowledgement',
        );
      }
    } catch (e) {
      if (!_current(generation)) return;
      error =
          '${businessError(e)}\nCheck the conversation state before retrying. No successful completion is assumed.';
      try {
        await _readState(generation);
        // A rejected proposal must not trap the UI in retrying obsolete IDs.
        // Refresh first, then allow answers to the current server proposal.
        // Transport errors, busy requests and auth failures remain unresolved:
        // an earlier attempt with the same identity might already have executed.
        if (_current(generation) &&
            e is ApiException &&
            (e.statusCode == 422 ||
                (e.statusCode == 409 &&
                    const {
                      'STALE_INTERRUPT',
                      'STALE_PROPOSAL',
                      'REQUEST_ID_CONFLICT',
                      'VERIFY_OUTCOME_FIRST',
                      'AGENT_INPUT_REQUIRED',
                      'AGENT_RECOVERY_REQUIRED',
                    }.contains(e.code)))) {
          _pending = null;
          await _persist();
        }
      } catch (_) {
        if (_current(generation)) _verified = false;
      }
    } finally {
      if (_current(generation)) {
        // A completed stream was saved at 'done'. Failed streams retain any
        // partial transcript alongside the exact pending request identity.
        if (!terminal || error != null) {
          try {
            await _persist();
          } catch (_) {
            /* The request path already reports storage errors above. */
          }
        }
        if (_current(generation)) {
          busy = false;
          _notify();
          // Some items can have succeeded even when another item or the stream failed.
          try {
            await onInventoryChanged?.call();
          } catch (_) {
            /* Readers expose their own errors. */
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
