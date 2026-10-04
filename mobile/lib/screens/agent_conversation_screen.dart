import 'package:flutter/material.dart';
import '../widgets/app_action_icon.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:image_picker/image_picker.dart';

import '../models/agent_input_draft.dart';
import '../models/inventory_item.dart';
import '../models/item_artwork_palette.dart';
import '../repositories/inventory_repository.dart';
import '../services/inventory_api_service.dart';
import '../services/voice_input_service.dart';
import '../state/agent_controller.dart';
import '../state/inventory_detail_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_input_panel.dart';
import '../widgets/app_background.dart';
import '../widgets/assistant_widgets.dart';
import '../widgets/assistant_inventory_reply.dart';
import '../widgets/assistant_welcome.dart';
import '../widgets/assistant_scroll_layout.dart';
import '../widgets/inventory_visuals.dart';
import '../widgets/agent_proposal_options.dart';
import 'conversation_history_screen.dart';
import 'inventory_detail_screen.dart';

class AgentConversationScreen extends StatefulWidget {
  const AgentConversationScreen({
    required this.controller,
    this.pickImages,
    this.voiceInput,
    this.displayName,
    this.initialDraft,
    super.key,
  });
  final AgentController controller;
  final Future<List<XFile>> Function()? pickImages;
  final VoiceInputService? voiceInput;
  final String? displayName;
  final AgentInputDraft? initialDraft;
  @override
  State<AgentConversationScreen> createState() =>
      _AgentConversationScreenState();
}

class _AgentConversationScreenState extends State<AgentConversationScreen> {
  final _message = TextEditingController();
  final _answerMessage = TextEditingController();
  final _answerDrafts = <String, String>{};
  String? _answerItemId, _answerProposalId, _answerScope;
  bool _answerEditing = false;
  ProposalResponse _answerOptions = (inventoryId: null, message: null);
  final _footerKey = GlobalKey();
  final _scroll = ScrollController();
  bool _followLatest = true;
  bool _scrollScheduled = false;
  bool _positioningLatest = false;
  bool _userScrolling = false;
  String? _conversationId;
  String? _lastUserMessage;
  int _inputReset = 0;

  @override
  void initState() {
    super.initState();
    _message.text = widget.initialDraft?.text ?? '';
    _rememberConversation();
    _syncAnswer();
    widget.controller.addListener(_onConversationChanged);
    _scheduleLatest();
  }

  void _rememberConversation() {
    _conversationId = widget.controller.conversationId;
    _lastUserMessage = widget.controller.messages.keys
        .where((key) => key.startsWith('user:'))
        .lastOrNull;
  }

  void _onConversationChanged() {
    final agent = widget.controller;
    final lastUser = agent.messages.keys
        .where((key) => key.startsWith('user:'))
        .lastOrNull;
    // Opening another conversation or sending explicitly returns to its end.
    final changedConversation = agent.conversationId != _conversationId;
    if (changedConversation || lastUser != _lastUserMessage) {
      _followLatest = true;
    }
    _syncAnswer(reset: changedConversation);
    _rememberConversation();
    if (_followLatest) _scheduleLatest();
  }

  Map<String, dynamic>? get _activeAnswer => widget.controller.items
      .where(
        (item) =>
            item['item_id'] == _answerItemId &&
            item['proposal_id'] == _answerProposalId,
      )
      .firstOrNull;

  void _syncAnswer({bool reset = false}) {
    if (reset) {
      _answerDrafts.clear();
      _answerItemId = _answerProposalId = null;
      _answerEditing = false;
    }
    final selected = _activeAnswer;
    final valid =
        selected != null &&
        (selected['status'] == 'NEEDS_INPUT' ||
            _answerEditing && selected['status'] == 'NEEDS_CONFIRMATION') &&
        (selected['error'] as Map?)?['code'] != 'EXECUTION_UNCERTAIN';
    final next = valid
        ? selected
        : widget.controller.items
              .where(
                (item) =>
                    item['status'] == 'NEEDS_INPUT' &&
                    (item['error'] as Map?)?['code'] != 'EXECUTION_UNCERTAIN',
              )
              .firstOrNull;
    final editing = valid && _answerEditing;
    final scope = next == null
        ? null
        : '${widget.controller.conversationId}:${next['item_id']}:${next['proposal_id']}:$editing';
    if (_answerScope != scope || reset) {
      if (!reset && _answerScope != null) {
        _answerDrafts[_answerScope!] = _answerMessage.text;
      }
      _answerMessage.text = scope == null ? '' : _answerDrafts[scope] ?? '';
      _answerOptions = (inventoryId: null, message: null);
    }
    _answerScope = scope;
    _answerItemId = next?['item_id'] as String?;
    _answerProposalId = next?['proposal_id'] as String?;
    _answerEditing = editing;
  }

  void _activateAnswer(Map<String, dynamic> item, bool editing) {
    setState(() {
      _answerItemId = item['item_id'] as String?;
      _answerProposalId = item['proposal_id'] as String?;
      _answerEditing = editing;
      _syncAnswer();
      _followLatest = true;
    });
    _scheduleLatest();
  }

  Future<bool> _sendAnswer(AgentInputDraft draft) async {
    final agent = widget.controller;
    final item = _activeAnswer;
    if (item == null || !agent.canRespond) return false;
    final scope = _answerScope;
    final text = [
      if (_answerOptions.message != null) _answerOptions.message!,
      if (draft.text.trim().isNotEmpty) draft.text.trim(),
    ].join(' ');
    if (text.isEmpty && _answerOptions.inventoryId == null) return false;
    await agent.respond(
      item,
      _answerEditing ? 'edit' : 'answer',
      message: text,
      selectedId: _answerOptions.inventoryId,
    );
    if (!mounted || agent.error != null) return false;
    _answerDrafts.remove(scope);
    // A reply may activate another pending item before this send finishes.
    // Only clear the draft belonging to the item that was submitted.
    if (_answerScope != scope) return false;
    _answerMessage.clear();
    return true;
  }

  void _scheduleLatest() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_followLatest || _userScrolling || !_scroll.hasClients) {
        return;
      }
      final agent = widget.controller;
      final welcome =
          agent.messages.isEmpty &&
          agent.items.isEmpty &&
          !agent.waiting &&
          !agent.unresolved &&
          agent.error == null;
      _positioningLatest = true;
      _scroll.jumpTo(welcome ? 0 : _scroll.position.maxScrollExtent);
      _positioningLatest = false;
    });
  }

  Widget _scrollNotifications(Widget child) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 && _followLatest && !_userScrolling) {
            _scheduleLatest();
          }
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (_positioningLatest || notification.depth != 0) return false;
            // Even a slow, short drag must cancel queued automatic positioning.
            if (notification is ScrollStartNotification &&
                    notification.dragDetails != null ||
                notification is UserScrollNotification &&
                    notification.direction != ScrollDirection.idle) {
              _userScrolling = true;
              _followLatest = false;
            } else if (notification is ScrollEndNotification ||
                notification is UserScrollNotification &&
                    notification.direction == ScrollDirection.idle) {
              _userScrolling = false;
              _followLatest = notification.metrics.extentAfter <= 1;
            } else if (notification is ScrollUpdateNotification &&
                !_userScrolling) {
              _followLatest = notification.metrics.extentAfter <= 1;
            }
            return false;
          },
          child: child,
        ),
      );

  @override
  void didUpdateWidget(covariant AgentConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onConversationChanged);
      widget.controller.addListener(_onConversationChanged);
      _followLatest = true;
      _rememberConversation();
      _syncAnswer(reset: true);
      _scheduleLatest();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onConversationChanged);
    _scroll.dispose();
    _message.dispose();
    _answerMessage.dispose();
    super.dispose();
  }

  Future<bool> _send(AgentInputDraft draft) async {
    if (!widget.controller.canSend) return false;
    await widget.controller.send(
      draft.text,
      images: draft.images,
      displayText: draft.text == widget.initialDraft?.text
          ? widget.initialDraft?.displayText
          : null,
    );
    return widget.controller.error == null;
  }

  void _openInventoryItem(InventoryItem item) {
    final workspace = widget.controller.workspace;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryDetailScreen(
          itemId: item.id,
          controller: InventoryDetailController(
            InventoryRepository(
              InventoryApiService(workspace.client),
              workspace.tokens,
            ),
            workspace: workspace,
          ),
        ),
      ),
    );
  }

  void _messageFor(String text) {
    final footer = _footerKey.currentContext?.findRenderObject() as RenderBox?;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          (footer?.size.height ?? 100) +
              MediaQuery.paddingOf(context).bottom +
              12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomInset = keyboardVisible
        ? 0.0
        : MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          AppBackground(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) {
                      final agent = widget.controller;
                      final answering = _activeAnswer != null;
                      final name = widget.displayName
                          ?.trim()
                          .split(RegExp(r'\s+'))
                          .first;
                      final showWelcome =
                          agent.messages.isEmpty &&
                          agent.items.isEmpty &&
                          !agent.waiting &&
                          !agent.unresolved &&
                          agent.error == null;
                      return AssistantScrollLayout(
                        bottomInset: bottomInset,
                        headerFadeExtent: 16,
                        header: Padding(
                          padding: const EdgeInsets.fromLTRB(25, 8, 25, 8),
                          child: AssistantHeader(
                            onNewConversation: () async {
                              if (agent.canSend) {
                                await agent.newConversation();
                                if (!mounted || agent.error != null) {
                                  return;
                                }
                                _message.clear();
                                setState(() {
                                  _inputReset++;
                                });
                              } else {
                                _messageFor(
                                  'Resolve or cancel pending items, or recover the current request first.',
                                );
                              }
                            },
                            onHistory: () async {
                              final previousId = agent.conversationId;
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ConversationHistoryScreen(
                                    controller: agent,
                                  ),
                                ),
                              );
                              if (!mounted ||
                                  agent.conversationId == previousId) {
                                return;
                              }
                              _message.clear();
                              setState(() {
                                _inputReset++;
                              });
                            },
                          ),
                        ),
                        contentBuilder: (context, bottomPadding) => _scrollNotifications(
                          ListView(
                            controller: _scroll,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              25,
                              0,
                              25,
                              bottomPadding,
                            ),
                            children: [
                              const Center(
                                child: Text(
                                  'Add information using voice, photos, or text.',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              AssistantGreeting(
                                message: name == null || name.isEmpty
                                    ? 'Hey! How can I help you?'
                                    : 'Hey, $name! How can I help you?',
                              ),
                              if (showWelcome)
                                AssistantWelcome(
                                  onSuggestionSelected: agent.canSend
                                      ? (message) => agent.send(message)
                                      : null,
                                )
                              else
                                const SizedBox(height: 24),
                              for (final message in agent.messages.entries)
                                if (message.value.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 24),
                                    child: message.key.startsWith('user:')
                                        ? UserMessageBubble(
                                            message: message.value,
                                            textStyle: exampleMessageStyle,
                                            images:
                                                agent.messageImages[message
                                                    .key] ??
                                                const [],
                                          )
                                        : agent.inventoryQueries.containsKey(
                                            message.key,
                                          )
                                        ? AssistantInventoryReply(
                                            message: message.value,
                                            query: agent
                                                .inventoryQueries[message.key]!,
                                            onItemTap: _openInventoryItem,
                                          )
                                        : AssistantReply(
                                            textStyle: exampleMessageStyle,
                                            message: message.value,
                                          ),
                                  ),
                              if (agent.confirmableItems.length > 1)
                                _BatchConfirmation(controller: agent),
                              for (final item in agent.items)
                                _AgentItemCard(
                                  key: ValueKey(
                                    '${item['item_id']}:${item['proposal_id']}',
                                  ),
                                  controller: agent,
                                  item: item,
                                  answering:
                                      answering &&
                                      item['item_id'] == _answerItemId,
                                  onAnswer: (editing) =>
                                      _activateAnswer(item, editing),
                                  onAnswerOptions: (answer) =>
                                      setState(() => _answerOptions = answer),
                                  onSubmitAnswer: () => _sendAnswer(
                                    AgentInputDraft(text: _answerMessage.text),
                                  ),
                                ),
                              if (agent.waiting && !answering)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'Waiting for your input. Pending actions have not all completed.',
                                    style: TextStyle(
                                      color: Color(0xFF667456),
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              if (agent.busy)
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: LinearProgressIndicator(),
                                ),
                              if (agent.error != null)
                                Text(
                                  agent.error!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              if (agent.unresolved)
                                const Text(
                                  'An earlier request is unresolved. Do not submit it as a new request.',
                                ),
                              if (agent.error != null || agent.unresolved)
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: agent.busy
                                          ? null
                                          : agent.recover,
                                      child: const Text(
                                        'Check conversation state',
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed: agent.canRetry
                                          ? agent.retry
                                          : null,
                                      child: const Text('Retry same request'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        footer: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              key: _footerKey,
                              padding: const EdgeInsets.fromLTRB(25, 8, 25, 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Offstage(
                                    offstage: answering,
                                    child: AgentInputPanel(
                                      controller: _message,
                                      textTopPadding: 14,
                                      enabled: agent.canSend,
                                      waiting: agent.waiting,
                                      reset: _inputReset,
                                      voiceInput: widget.voiceInput,
                                      pickImages: widget.pickImages,
                                      initialImages:
                                          widget.initialDraft?.images ??
                                          const [],
                                      submitOnMount:
                                          widget.initialDraft != null,
                                      onMessage: _messageFor,
                                      onSend: _send,
                                    ),
                                  ),
                                  if (answering)
                                    AgentInputPanel(
                                      key: ValueKey('answer-$_answerScope'),
                                      inputKey: const Key(
                                        'assistant-answer-field',
                                      ),
                                      controller: _answerMessage,
                                      textTopPadding: 14,
                                      enabled: agent.canRespond,
                                      waiting: true,
                                      allowImages: false,
                                      maxLength: 1000,
                                      maxLines: keyboardVisible ? 2 : 6,
                                      voiceInput: widget.voiceInput,
                                      onMessage: _messageFor,
                                      onSend: _sendAnswer,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentItemCard extends StatefulWidget {
  const _AgentItemCard({
    required this.controller,
    required this.item,
    required this.answering,
    required this.onAnswer,
    required this.onAnswerOptions,
    required this.onSubmitAnswer,
    super.key,
  });
  final AgentController controller;
  final Map<String, dynamic> item;
  final bool answering;
  final ValueChanged<bool> onAnswer;
  final ValueChanged<ProposalResponse> onAnswerOptions;
  final Future<bool> Function() onSubmitAnswer;
  @override
  State<_AgentItemCard> createState() => _AgentItemCardState();
}

class _AgentItemCardState extends State<_AgentItemCard> {
  String? _selectedId, _answerText;
  bool _editing = false;
  AgentController get controller => widget.controller;
  Map<String, dynamic> get item => widget.item;

  @override
  void didUpdateWidget(covariant _AgentItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.answering != widget.answering) {
      _selectedId = _answerText = null;
    }
  }

  Future<void> _confirm() async {
    if ((item['error'] as Map?)?['code'] == 'EXECUTION_UNCERTAIN' ||
        item['status'] == 'NEEDS_CONFIRMATION' && !_editing) {
      await controller.respond(item, 'confirm');
    } else {
      await widget.onSubmitAnswer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = item['status'];
    final preview = _asMap(item['preview']);
    final draft = _asMap(preview?['draft']);
    final after = _asMap(preview?['after']);
    final previewDisplay = _asMap(preview?['display']);
    final itemDisplay = _asMap(item['display']);
    final display = previewDisplay == null && itemDisplay == null
        ? null
        : <String, dynamic>{...?previewDisplay, ...?itemDisplay};
    final error = item['error'] as Map<String, dynamic>?;
    final details = error?['details'] as Map<String, dynamic>?;
    final uncertain = error?['code'] == 'EXECUTION_UNCERTAIN';
    final waiting = status == 'NEEDS_INPUT' || status == 'NEEDS_CONFIRMATION';
    final canRespond = controller.canRespond && waiting;
    final needsAnswer = !uncertain && (status == 'NEEDS_INPUT' || _editing);
    final asking = needsAnswer && widget.answering;
    final hasChoices =
        _editing ||
        const {
          'CATEGORY_REQUIRED',
          'SPACE_REQUIRED',
        }.contains(error?['code']) ||
        const [
          'candidates',
          'categories',
          'spaces',
        ].any((key) => (details?[key] as List?)?.isNotEmpty ?? false);
    final original = _readableRequest(_text(item['original_text']));
    final heading = _text(display?['item_name']) ?? 'Inventory action';
    final recognized =
        _readableRequest(_text(display?['recognized_text'])) ?? original;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AssistantActionBubble(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Color(
                          ItemArtworkPalette.backgroundArgb(
                            itemArtworkForName(heading),
                          ),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.asset(
                        itemArtworkForName(heading),
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            heading,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(status),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_statusIcon(status), size: 16),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _statusLabel(status),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFFA8D589), height: 24),
                if (recognized != null) _RecognisedText(text: recognized),
                if (_text(display?['category_name']) case final category?)
                  _DetailRow(label: 'Category', value: category),
                if (_text(display?['space_name']) case final space?)
                  _DetailRow(label: 'Location', value: space),
                if (_text(display?['package_description']) case final package?)
                  _DetailRow(label: 'Package', value: package),
                if (_quantity(after, draft) case final quantity?)
                  _DetailRow(label: 'Quantity', value: quantity),
                if (_text(draft?['purchase_date']) case final purchaseDate?)
                  _DetailRow(label: 'Purchase date', value: purchaseDate),
                if (_text(draft?['expiry_date']) case final expiryDate?)
                  _DetailRow(label: 'Expiry date', value: expiryDate),
                if (_stringList(display?['missing_fields']).isNotEmpty)
                  _NoticeBox(
                    icon: Icons.help_outline,
                    title: 'Still needed',
                    values: _stringList(display?['missing_fields']),
                  ),
                if (_stringList(display?['review_notes']).isNotEmpty)
                  _NoticeBox(
                    icon: Icons.fact_check_outlined,
                    title: 'Review notes',
                    values: _stringList(display?['review_notes']),
                  ),
                if (preview != null) ...[
                  if (_text(preview['calculation_method']) case final method?)
                    _DetailRow(
                      label: 'Calculation',
                      value: switch (method) {
                        'EXACT' => 'Exact amount',
                        'AI_ESTIMATED' ||
                        'ESTIMATED' ||
                        'ESTIMATE' => 'Estimated amount',
                        'CONVERTED' => 'Converted amount',
                        _ => method.replaceAll('_', ' ').toLowerCase(),
                      },
                    ),
                  if (preview['before'] is Map)
                    _DetailRow(
                      label: 'Before',
                      value: _balance(preview['before'] as Map),
                    ),
                  if (preview['after'] is Map &&
                      _quantity(after, draft) !=
                          _balance(preview['after'] as Map))
                    _DetailRow(
                      label: 'After',
                      value: _balance(preview['after'] as Map),
                    ),
                ],
                if (error != null && !needsAnswer)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _reviewMessage(error, display),
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (asking && hasChoices) ...[
                  const SizedBox(height: 12),
                  AgentProposalOptions(
                    workspace: controller.workspace,
                    details: details ?? const {},
                    errorCode: error?['code'] as String?,
                    editing: _editing,
                    enabled: canRespond,
                    onChanged: (answer) => setState(() {
                      _selectedId = answer.inventoryId;
                      _answerText = answer.message;
                      widget.onAnswerOptions(answer);
                    }),
                  ),
                ],
                if (waiting) ...[
                  const SizedBox(height: 16),
                  if (uncertain)
                    FilledButton(
                      onPressed: canRespond ? _confirm : null,
                      child: const Text('Verify original action'),
                    )
                  else if (needsAnswer) ...[
                    if (!widget.answering)
                      TextButton(
                        onPressed: canRespond
                            ? () => widget.onAnswer(_editing)
                            : null,
                        child: const Text('Answer this item'),
                      )
                    else if (hasChoices)
                      FilledButton(
                        onPressed:
                            canRespond &&
                                (_selectedId != null || _answerText != null)
                            ? _confirm
                            : null,
                        child: Text(_editing ? 'Update proposal' : 'Confirm'),
                      ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed:
                                canRespond &&
                                    (status == 'NEEDS_CONFIRMATION' &&
                                            !_editing ||
                                        _selectedId != null ||
                                        _answerText != null)
                                ? _confirm
                                : null,
                            child: Text(
                              _editing ? 'Update proposal' : 'Confirm',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: canRespond
                                ? () => controller.respond(item, 'cancel')
                                : null,
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (status == 'NEEDS_CONFIRMATION' && !uncertain) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (status == 'NEEDS_CONFIRMATION')
                          TextButton.icon(
                            onPressed: canRespond
                                ? () => setState(() {
                                    _editing = !_editing;
                                    _selectedId = null;
                                    _answerText = null;
                                    widget.onAnswer(_editing);
                                  })
                                : null,
                            icon: const AppActionIcon(
                              ActionAssets.edit,
                              size: 18,
                            ),
                            label: Text(
                              _editing ? 'Close editing' : 'Edit details',
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
          if (asking) ...[
            const SizedBox(height: 18),
            AssistantActionBubble(
              key: const Key('clarification-question'),
              child: Text(
                _editing
                    ? 'What would you like to change about $heading?'
                    : _reviewMessage(error ?? const {}, display),
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 16, 0, 10),
              child: Text(
                'Please enter your answer below to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF77816D),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            Center(
              child: OutlinedButton.icon(
                key: const Key('cancel-pending-answer'),
                onPressed: canRespond
                    ? () => controller.respond(item, 'cancel')
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFED5145),
                  backgroundColor: const Color(0xFFFFE0CF),
                  side: const BorderSide(color: Color(0xFFFF8174)),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                ),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Cancel'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _readableRequest(String? text) {
    const prefix = 'Today I used: ';
    const suffix =
        '. Please propose the inventory deductions and wait for my confirmation.';
    return text != null && text.startsWith(prefix) && text.endsWith(suffix)
        ? text.substring(prefix.length, text.length - suffix.length)
        : text;
  }

  String _reviewMessage(
    Map<String, dynamic> error,
    Map<String, dynamic>? display,
  ) {
    final question = _text(display?['question']);
    if (question != null) return question;
    if (error['code'] == 'REESTIMATE') {
      // Unit conversion and qualitative estimates share this error code.
      if (_text(error['message'])?.contains('unit_relationship') ?? false) {
        return 'How much does one of these units hold? Tell me the conversion and where it comes from, for example from the packaging or a measurement.';
      }
      return 'Please tell me how much you used or how much remains, including the unit. An approximate amount is fine.';
    }
    return '${error['message'] ?? error['code'] ?? 'What additional details can you provide for this item?'}';
  }

  String _balance(Map value) {
    final estimate =
        value['is_estimated'] == true ||
        value['estimated_current_amount'] != null;
    final amount =
        value['display_amount'] ??
        value['amount'] ??
        value['estimated_current_amount'] ??
        value['confirmed_current_amount'];
    final unit =
        value['display_unit'] ??
        value['unit'] ??
        value['estimated_current_unit'] ??
        value['confirmed_current_unit'];
    return '${estimate ? '≈ ' : ''}$amount $unit';
  }

  Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'null' ? null : text;
  }

  List<String> _stringList(Object? value) => value is List
      ? value
            .map((entry) => entry.toString())
            .where((entry) => entry.isNotEmpty)
            .toList()
      : const [];

  String? _quantity(Map<String, dynamic>? after, Map<String, dynamic>? draft) {
    final amount =
        after?['estimated_current_amount'] ??
        after?['confirmed_current_amount'] ??
        draft?['quantity_value'];
    final unit =
        after?['estimated_current_unit'] ??
        after?['confirmed_current_unit'] ??
        draft?['quantity_unit'];
    if (amount == null && unit == null) return null;
    final estimated = after?['estimated_current_amount'] != null;
    return '${estimated ? '≈ ' : ''}${amount ?? 'Unknown'} ${unit ?? ''}'
        .trim();
  }

  String _statusLabel(Object? status) => switch (status) {
    'NEEDS_INPUT' => 'Needs information',
    'NEEDS_CONFIRMATION' => 'Ready for review',
    'SUCCEEDED' => 'Saved successfully',
    'FAILED' => 'Failed',
    'CANCELLED' => 'Cancelled',
    _ => status?.toString() ?? 'Pending',
  };

  IconData _statusIcon(Object? status) => switch (status) {
    'NEEDS_INPUT' => Icons.help_outline,
    'NEEDS_CONFIRMATION' => Icons.fact_check_outlined,
    'SUCCEEDED' => Icons.check_circle_outline,
    'FAILED' => Icons.error_outline,
    'CANCELLED' => Icons.cancel_outlined,
    _ => Icons.schedule,
  };

  Color _statusColor(Object? status) => switch (status) {
    'SUCCEEDED' => const Color(0xFFDDF4D0),
    'FAILED' => const Color(0xFFFFDDDD),
    'CANCELLED' => const Color(0xFFE6E6E6),
    'NEEDS_INPUT' => const Color(0xFFFFEBC2),
    _ => const Color(0xFFE9F5D9),
  };
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 94,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF77816D),
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 14, height: 1.4)),
        ),
      ],
    ),
  );
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({
    required this.icon,
    required this.title,
    required this.values,
  });

  final IconData icon;
  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF4DF),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.userMessage,
                ),
              ),
              const SizedBox(height: 4),
              for (final value in values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    value.replaceAll('_', ' '),
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _BatchConfirmation extends StatelessWidget {
  const _BatchConfirmation({required this.controller});
  final AgentController controller;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: AssistantActionBubble(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${controller.confirmableItems.length} items ready for review',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('confirm-all-items'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: controller.canRespond
                ? () => controller.confirmItems(controller.confirmableItems)
                : null,
            icon: const Icon(Icons.done_all, size: 20),
            label: Text('Confirm all (${controller.confirmableItems.length})'),
          ),
        ],
      ),
    ),
  );
}

class _RecognisedText extends StatefulWidget {
  const _RecognisedText({required this.text});
  final String text;
  @override
  State<_RecognisedText> createState() => _RecognisedTextState();
}

class _RecognisedTextState extends State<_RecognisedText> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6E8),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recognised text',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 5),
        Text(
          widget.text,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? null : TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, height: 1.45),
        ),
        if (widget.text.length > 90)
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
            ),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Show less' : 'Show more'),
          ),
      ],
    ),
  );
}
