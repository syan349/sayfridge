import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/agent_input_draft.dart';
import '../services/voice_input_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_input_panel.dart';
import '../widgets/app_background.dart';
import '../widgets/assistant_scroll_layout.dart';
import '../widgets/page_back_button.dart';

class DailyConsumptionRecallScreen extends StatefulWidget {
  const DailyConsumptionRecallScreen({
    this.voiceInput,
    this.pickImages,
    super.key,
  });

  final VoiceInputService? voiceInput;
  final Future<List<XFile>> Function()? pickImages;

  @override
  State<DailyConsumptionRecallScreen> createState() =>
      _DailyConsumptionRecallScreenState();
}

class _DailyConsumptionRecallScreenState
    extends State<DailyConsumptionRecallScreen> {
  final _usage = TextEditingController();
  int? _topic;

  @override
  void dispose() {
    _usage.dispose();
    super.dispose();
  }

  Future<bool> _continue(AgentInputDraft draft) async {
    if (draft.isEmpty) return false;
    Navigator.of(context).pop(draft);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom == 0
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AssistantScrollLayout(
                bottomInset: bottomInset,
                contentBuilder: (context, bottomPadding) => ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(25, 24, 25, bottomPadding),
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
                      'Choose a topic to help you remember, then speak, type or add photos of what you used. '
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
                      description:
                          'Small items and drinks that are easy to forget',
                    ),
                    const SizedBox(height: 12),
                    _RecallPrompt(
                      selected: _topic == 2,
                      onTap: () => setState(() => _topic = 2),
                      icon: Icons.inventory_2_outlined,
                      title: 'Anything finished?',
                      description: 'Packages or batches that are now used up',
                    ),

                    const SizedBox(height: 24),
                    if (_topic != null) ...[
                      Text(
                        _topic == 0
                            ? 'What ingredients did you use for your meals?'
                            : _topic == 1
                            ? 'What snacks or drinks did you have?'
                            : 'Which items did you completely finish?',
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const Text(
                      'Send your text or photos to AI Assistant to review the proposed changes.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
                footer: Padding(
                  padding: const EdgeInsets.fromLTRB(25, 8, 25, 28),
                  child: AgentInputPanel(
                    controller: _usage,
                    voiceInput: widget.voiceInput,
                    pickImages: widget.pickImages,
                    maxLength: 1000,
                    inputKey: const Key('daily-consumption-input'),
                    onSend: _continue,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
