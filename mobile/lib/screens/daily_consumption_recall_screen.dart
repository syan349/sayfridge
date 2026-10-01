import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/page_back_button.dart';

class DailyConsumptionRecallScreen extends StatefulWidget {
  const DailyConsumptionRecallScreen({super.key});

  @override
  State<DailyConsumptionRecallScreen> createState() =>
      _DailyConsumptionRecallScreenState();
}

class _DailyConsumptionRecallScreenState
    extends State<DailyConsumptionRecallScreen> {
  final _usage = TextEditingController();

  @override
  void dispose() {
    _usage.dispose();
    super.dispose();
  }

  void _continue() {
    final value = _usage.text.trim();
    if (value.isEmpty) return;
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
                  'Think through your day, then describe everything in one message. '
                  'The AI Assistant will prepare deductions for you to review before anything changes.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 15.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                const _RecallPrompt(
                  icon: Icons.restaurant_rounded,
                  title: 'Meals and cooking',
                  description:
                      'Ingredients used for breakfast, lunch or dinner',
                ),
                const SizedBox(height: 12),
                const _RecallPrompt(
                  icon: Icons.local_cafe_outlined,
                  title: 'Snacks and drinks',
                  description: 'Small items and drinks that are easy to forget',
                ),
                const SizedBox(height: 12),
                const _RecallPrompt(
                  icon: Icons.inventory_2_outlined,
                  title: 'Anything finished?',
                  description: 'Packages or batches that are now used up',
                ),
                const SizedBox(height: 28),
                TextField(
                  key: const Key('daily-consumption-input'),
                  controller: _usage,
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
                  onPressed: _usage.text.trim().isEmpty ? null : _continue,
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
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xBFFFFFFF),
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
      ],
    ),
  );
}
