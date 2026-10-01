import 'package:flutter/material.dart';

import '../services/voice_input_service.dart';
import '../services/voice_input_factory.dart'
    if (dart.library.js_interop) '../services/voice_input_factory_web.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/page_back_button.dart';
import '../widgets/hold_to_speak_button.dart';

class DailyConsumptionRecallScreen extends StatefulWidget {
  const DailyConsumptionRecallScreen({this.voiceInput, super.key});

  final VoiceInputService? voiceInput;

  @override
  State<DailyConsumptionRecallScreen> createState() =>
      _DailyConsumptionRecallScreenState();
}

class _DailyConsumptionRecallScreenState
    extends State<DailyConsumptionRecallScreen> {
  final _usage = TextEditingController();
  late final VoiceInputService _voice;
  bool _recording = false, _holding = false, _finishing = false;
  bool _cancelling = false;
  int _session = 0;
  String _words = '';
  int? _topic;

  @override
  void initState() {
    super.initState();
    _voice = widget.voiceInput ?? createVoiceInputService();
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _startVoice() async {
    if (_recording) return;
    FocusScope.of(context).unfocus();
    final session = ++_session;
    setState(() {
      _recording = _holding = true;
      _finishing = _cancelling = false;
      _words = '';
    });
    final available = await _voice.start(
      onWords: (words) {
        if (mounted && session == _session && _recording) {
          setState(() => _words = words.trim());
        }
      },
      onError: (message) {
        if (!mounted || session != _session) return;
        setState(() {
          _recording = _holding = _finishing = _cancelling = false;
          _words = '';
        });
        _message(message);
      },
      shouldContinue: () => mounted && session == _session && _holding,
    );
    if (!mounted || session != _session || available || !_holding) return;
    setState(() => _recording = _holding = false);
    _message(
      'Speech recognition is unavailable. Check microphone permission or use keyboard input.',
    );
  }

  Future<void> _finishVoice({bool cancel = false}) async {
    _holding = false;
    if (!_recording || (_finishing && !cancel)) return;
    final session = cancel ? ++_session : _session;
    final cancelled = cancel || _cancelling;
    setState(() => _finishing = true);
    if (cancelled) {
      await _voice.cancel();
    } else {
      await _voice.stop();
    }
    if (!mounted || session != _session || !_recording) return;
    final words = _words.trim();
    setState(() {
      _recording = _finishing = _cancelling = false;
      _words = '';
      if (!cancelled && words.isNotEmpty) {
        final existing = _usage.text.trimRight();
        final combined = existing.isEmpty ? words : '$existing $words';
        _usage.text = combined.length > 1000
            ? combined.substring(0, 1000)
            : combined;
        _usage.selection = TextSelection.collapsed(offset: _usage.text.length);
        if (combined.length > 1000) {
          _message(
            'The check-in is limited to 1,000 characters. Please review the text.',
          );
        }
      }
    });
    if (!cancelled && words.isEmpty) {
      _message('No speech was recognized. Please try again.');
    }
  }

  @override
  void dispose() {
    ++_session;
    _holding = false;
    if (_recording) _voice.cancel();
    _usage.dispose();
    super.dispose();
  }

  void _continue() {
    final value = _usage.text.trim();
    if (value.isEmpty || _recording) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    body: AppBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(25, 24, 25, 32),
              children: [
                Row(
                  children: [
                    const PageBackButton(),
                    const Expanded(
                      child: Text(
                        'Daily Check-in',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 34),
                const Text(
                  'What did you use today?',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Choose a topic to help you remember, then speak or type what you used. '
                  'Review the text before asking the AI Assistant to prepare your inventory changes.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 15.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                _RecallPrompt(
                  selected: _topic == 0,
                  onTap: () => setState(() => _topic = 0),
                  icon: Icons.restaurant_rounded,
                  title: 'Meals and cooking',
                  description:
                      'Ingredients used for breakfast, lunch or dinner',
                ),
                const SizedBox(height: 12),
                _RecallPrompt(
                  selected: _topic == 1,
                  onTap: () => setState(() => _topic = 1),
                  icon: Icons.local_cafe_outlined,
                  title: 'Snacks and drinks',
                  description: 'Small items and drinks that are easy to forget',
                ),
                const SizedBox(height: 12),
                _RecallPrompt(
                  selected: _topic == 2,
                  onTap: () => setState(() => _topic = 2),
                  icon: Icons.inventory_2_outlined,
                  title: 'Anything finished?',
                  description: 'Packages or batches that are now used up',
                ),
                const SizedBox(height: 28),
                Text(
                  _topic == 0
                      ? 'What ingredients did you use for your meals?'
                      : _topic == 1
                      ? 'What snacks or drinks did you have?'
                      : _topic == 2
                      ? 'Which items did you completely finish?'
                      : 'Hold to speak, or type below. You can add more than one recording.',
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: HoldToSpeakButton(
                    enabled: !_finishing,
                    recording: _recording,
                    cancelling: _cancelling,
                    finishing: _finishing,
                    onStart: _startVoice,
                    onMove: (offset) {
                      if (_recording) {
                        setState(
                          () =>
                              _cancelling = offset.dy < -60 || offset.dx < -60,
                        );
                      }
                    },
                    onEnd: () => _finishVoice(),
                    onCancel: () => _finishVoice(cancel: true),
                  ),
                ),
                if (_recording) ...[
                  const SizedBox(height: 8),
                  Text(
                    _words.isEmpty ? 'Listening… Slide up to cancel.' : _words,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  key: const Key('daily-consumption-input'),
                  controller: _usage,
                  enabled: !_recording,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText:
                        'e.g. 3 eggs, 250 ml of milk, and the last yoghurt',
                    filled: true,
                    fillColor: Colors.white,
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFCFDCC3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFCFDCC3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _continue(),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const Key('review-daily-consumption'),
                  onPressed: _usage.text.trim().isEmpty || _recording
                      ? null
                      : _continue,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.userMessage,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text(
                    'Review with AI',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You will confirm or correct each proposed change in the next step.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _RecallPrompt extends StatelessWidget {
  const _RecallPrompt({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.selected,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE5F2D8) : const Color(0xBFFFFFFF),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFD7E6C7)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_outline
                    : Icons.chevron_right_rounded,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
