import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/agent_image.dart';
import '../models/agent_input_draft.dart';
import '../platform/voice_overlay_chrome.dart'
    if (dart.library.js_interop) '../platform/voice_overlay_chrome_web.dart';
import '../services/voice_input_service.dart';
import '../services/voice_input_factory.dart'
    if (dart.library.js_interop) '../services/voice_input_factory_web.dart';
import '../screens/camera_input_screen.dart';
import 'agent_composer.dart';
import 'hold_to_speak_button.dart';
import 'voice_recording_overlay.dart';

/// Shared input behavior for AI Assistant and Daily Check-in.
/// A rejected/failed submission keeps the entire draft available for retry.
class AgentInputPanel extends StatefulWidget {
  const AgentInputPanel({
    required this.controller,
    this.onSend,
    this.enabled = true,
    this.waiting = false,
    this.pickImages,
    this.voiceInput,
    this.initialImages = const [],
    this.submitOnMount = false,
    this.reset = 0,
    this.maxLength = 8000,
    this.inputKey = const Key('assistant-message-field'),
    this.onMessage,
    this.textTopPadding = 6,
    this.inline = false,
    this.hintText,
    super.key,
  }) : assert(inline || onSend != null);

  final TextEditingController controller;
  final Future<bool> Function(AgentInputDraft draft)? onSend;
  final bool enabled, waiting, submitOnMount;
  final Future<List<XFile>> Function()? pickImages;
  final VoiceInputService? voiceInput;
  final List<AgentImage> initialImages;
  final int reset, maxLength;
  final Key inputKey;
  final ValueChanged<String>? onMessage;
  final double textTopPadding;

  /// Item clarification only edits a draft; the enclosing Confirm submits it.
  final bool inline;
  final String? hintText;

  @override
  State<AgentInputPanel> createState() => _AgentInputPanelState();
}

class _AgentInputPanelState extends State<AgentInputPanel> {
  TextEditingController get _message => widget.controller;
  OverlayEntry? _voiceOverlayEntry;
  final List<AgentImage> _images = [];
  late final VoiceInputService _voiceInput;
  bool _recordingVoice = false, _holdingVoice = false;
  bool _finishingVoice = false, _cancelVoice = false;
  bool _sending = false, _pickingImages = false;
  int _voiceModeReset = 0, _voiceSession = 0;
  String _recognizedWords = '';

  bool get _enabled => widget.enabled && !_sending && !_pickingImages;

  @override
  void initState() {
    super.initState();
    _voiceInput = widget.voiceInput ?? createVoiceInputService();
    _images.addAll(widget.initialImages);
    _message.addListener(_refreshDraft);
    if (widget.submitOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_enabled) {
          _send();
        } else {
          _messageFor('Resolve the pending items first, then send this draft.');
        }
      });
    }
  }

  void _refreshDraft() => setState(() {});

  @override
  void didUpdateWidget(covariant AgentInputPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refreshDraft);
      _message.addListener(_refreshDraft);
    }
    if (oldWidget.reset != widget.reset) {
      _images.clear();
      _voiceModeReset++;
    }
  }

  @override
  void dispose() {
    ++_voiceSession;
    _holdingVoice = false;
    if (_recordingVoice) _voiceInput.cancel();
    _hideVoiceOverlay();
    _message.removeListener(_refreshDraft);
    super.dispose();
  }

  void _showVoiceOverlay() {
    final entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: VoiceRecordingOverlay(
            words: _recognizedWords,
            cancelling: _cancelVoice,
            finishing: _finishingVoice,
            onClose: () => _finishVoiceInput(forceCancel: true),
          ),
        ),
      ),
    );
    _voiceOverlayEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    setVoiceOverlayVisible(true);
  }

  void _hideVoiceOverlay() {
    final entry = _voiceOverlayEntry;
    _voiceOverlayEntry = null;
    entry?.remove();
    entry?.dispose();
    if (entry != null) setVoiceOverlayVisible(false);
  }

  Future<void> _startVoiceInput() async {
    if (!_enabled || _recordingVoice) return;
    final session = ++_voiceSession;
    setState(() {
      _recordingVoice = true;
      _holdingVoice = true;
      _finishingVoice = false;
      _cancelVoice = false;
      _recognizedWords = '';
    });
    _showVoiceOverlay();
    final available = await _voiceInput.start(
      onWords: (words) {
        if (!mounted || session != _voiceSession || !_recordingVoice) return;
        setState(() => _recognizedWords = words.trim());
        _voiceOverlayEntry?.markNeedsBuild();
      },
      onError: (message) {
        if (!mounted || session != _voiceSession) return;
        setState(() {
          _recordingVoice = false;
          _holdingVoice = false;
          _finishingVoice = false;
          _cancelVoice = false;
          _recognizedWords = '';
        });
        _hideVoiceOverlay();
        _messageFor(message);
      },
      shouldContinue: () =>
          mounted && session == _voiceSession && _holdingVoice,
    );
    if (!mounted || session != _voiceSession || available || !_recordingVoice) {
      return;
    }
    if (!_holdingVoice) return;
    setState(() {
      _recordingVoice = false;
      _holdingVoice = false;
    });
    _hideVoiceOverlay();
    _messageFor(
      'Voice recognition is not available. Check microphone permission or use a supported browser.',
    );
  }

  void _updateVoiceCancel(Offset offset) {
    if (!_recordingVoice) return;
    final shouldCancel = offset.dy < -60 || offset.dx < -60;
    if (shouldCancel != _cancelVoice) {
      setState(() => _cancelVoice = shouldCancel);
      _voiceOverlayEntry?.markNeedsBuild();
    }
  }

  Future<void> _finishVoiceInput({bool forceCancel = false}) async {
    _holdingVoice = false;
    if (!_recordingVoice || (_finishingVoice && !forceCancel)) return;
    // Closing while the final transcript is pending must cancel that pending
    // stop too. Invalidate its callbacks before waiting for browser cleanup.
    final session = forceCancel ? ++_voiceSession : _voiceSession;
    final cancelled = forceCancel || _cancelVoice;
    setState(() => _finishingVoice = true);
    _voiceOverlayEntry?.markNeedsBuild();
    if (cancelled) {
      await _voiceInput.cancel();
    } else {
      await _voiceInput.stop();
    }
    if (!mounted || session != _voiceSession || !_recordingVoice) return;
    final words = _recognizedWords.trim();
    setState(() {
      _recordingVoice = false;
      _finishingVoice = false;
      _cancelVoice = false;
      _recognizedWords = '';
      if (!cancelled && words.isNotEmpty) {
        final existing = _message.text.trimRight();
        final combined = existing.isEmpty ? words : '$existing $words';
        _message.text = combined.length > widget.maxLength
            ? combined.substring(0, widget.maxLength)
            : combined;
        _message.selection = TextSelection.collapsed(
          offset: _message.text.length,
        );
      }
    });
    _hideVoiceOverlay();
    if (!cancelled && words.isEmpty) {
      _messageFor('No speech was recognized. Please try again.');
    }
  }

  Future<void> _send() async {
    final submit = widget.onSend;
    if (widget.inline || submit == null || !_enabled || _recordingVoice) return;
    final draft = AgentInputDraft(text: _message.text, images: _images);
    if (draft.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      final accepted = await submit(draft);
      if (!mounted || !accepted) return;
      _message.clear();
      setState(() {
        _images.clear();
        _voiceModeReset++;
      });
    } catch (_) {
      if (mounted) {
        _messageFor('Unable to send. Your text and photos are saved here.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImages() async {
    if (!_enabled || _images.length >= AgentImage.maxImages) {
      return;
    }
    setState(() => _pickingImages = true);
    try {
      final selected = widget.pickImages != null
          ? await widget.pickImages!.call()
          : await _openCameraInput();
      if (!mounted || selected.isEmpty) return;
      final additions = <AgentImage>[];
      for (final file in selected.take(AgentImage.maxImages - _images.length)) {
        final bytes = await file.readAsBytes();
        final image = AgentImage.fromPickedBytes(bytes);
        image.validateDimensions();
        additions.add(image);
      }
      AgentImage.validateBatch([..._images, ...additions]);
      if (!mounted) return;
      setState(() => _images.addAll(additions));
      if (selected.length > additions.length) {
        _messageFor('Send at most 4 images at a time.');
      }
    } on FormatException catch (e) {
      if (mounted) _messageFor(e.message);
    } catch (_) {
      if (mounted) {
        _messageFor('Unable to open those photos. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  Future<List<XFile>> _openCameraInput() async {
    final selected = await Navigator.of(context).push<List<XFile>>(
      MaterialPageRoute<List<XFile>>(builder: (_) => const CameraInputScreen()),
    );
    return selected ?? [];
  }

  void _messageFor(String text) {
    if (widget.onMessage != null) {
      widget.onMessage!(text);
      return;
    }
    final panel = context.findRenderObject() as RenderBox?;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          (panel?.size.height ?? 100) +
              MediaQuery.paddingOf(context).bottom +
              40,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_images.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final image in _images)
                _ImagePreview(
                  key: ValueKey('agent-image-${image.imageId}'),
                  image: image,
                  onRemove: _enabled && !_recordingVoice
                      ? () => setState(() => _images.remove(image))
                      : null,
                ),
            ],
          ),
        ),
      AgentComposer(
        key: Key(
          widget.inline ? 'assistant-inline-action' : 'assistant-bottom-action',
        ),
        controller: _message,
        voiceModeReset: _voiceModeReset,
        enabled: _enabled,
        waiting: widget.waiting,
        hasImages: _images.isNotEmpty,
        voiceActive: _recordingVoice,
        maxLength: widget.maxLength,
        inputKey: widget.inputKey,
        textTopPadding: widget.textTopPadding,
        inline: widget.inline,
        hintText: widget.hintText,
        onPhotoPressed: _enabled && _images.length < AgentImage.maxImages
            ? _pickImages
            : null,
        onSendPressed:
            _enabled && (_message.text.trim().isNotEmpty || _images.isNotEmpty)
            ? _send
            : null,
        voiceButton: HoldToSpeakButton(
          fontSize: widget.inline ? 14 : 16,
          enabled: _enabled && !_finishingVoice,
          recording: _recordingVoice,
          cancelling: _cancelVoice,
          finishing: _finishingVoice,
          onStart: _startVoiceInput,
          onMove: _updateVoiceCancel,
          onEnd: () => _finishVoiceInput(),
          onCancel: () => _finishVoiceInput(forceCancel: true),
        ),
      ),
    ],
  );
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image, required this.onRemove, super.key});

  final AgentImage image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          image.bytes,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          semanticLabel: 'Selected photo',
        ),
      ),
      Positioned(
        right: -10,
        top: -10,
        child: IconButton.filled(
          onPressed: onRemove,
          tooltip: 'Remove photo',
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          padding: EdgeInsets.zero,
          iconSize: 17,
          icon: const Icon(Icons.close),
        ),
      ),
    ],
  );
}
