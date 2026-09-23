import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_bottom_navigation.dart';

class ConversationHistoryScreen extends StatelessWidget {
  const ConversationHistoryScreen({super.key});

  static const _today = <_ConversationRecord>[
    _ConversationRecord('What’s expiring soon?', '03:06 PM'),
    _ConversationRecord('Add chicken to fridge.', '09:25 AM'),
  ];

  static const _earlier = <_ConversationRecord>[
    _ConversationRecord('Record milk used.', '15 Sep 2026'),
    _ConversationRecord('Daily fridge check-in', '15 Sep 2026'),
    _ConversationRecord('What fruit is left?', '14 Sep 2026'),
    _ConversationRecord('Remove one chicken breast.', '13 Sep 2026'),
    _ConversationRecord('Give me a fridge summary.', '11 Sep 2026'),
    _ConversationRecord('What vegetables do I have?', '09 Sep 2026'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 27, 24, 42),
                children: [
                  SizedBox(
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 29,
                            ),
                            tooltip: 'Back',
                          ),
                        ),
                        const Text(
                          'Conversation History',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    height: 53,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.search_rounded, size: 30),
                        SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search conversations ...',
                              hintStyle: TextStyle(
                                color: AppColors.muted,
                                fontSize: 17,
                              ),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 39),
                  const _HistorySection(title: 'Today', records: _today),
                  const SizedBox(height: 57),
                  const _HistorySection(title: 'Earlier', records: _earlier),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationRecord {
  const _ConversationRecord(this.title, this.time);

  final String title;
  final String time;
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.title, required this.records});

  final String title;
  final List<_ConversationRecord> records;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 17),
        for (var index = 0; index < records.length; index++) ...[
          _HistoryCard(record: records[index]),
          if (index != records.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.record});

  final _ConversationRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.fromLTRB(16, 11, 11, 11),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: const Color(0xFFB5CE9F), width: 1.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Image.asset(
            AssistantAssets.chat,
            width: 31,
            height: 31,
            cacheWidth: 90,
          ),
          Container(
            width: 1,
            height: 47,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: const Color(0xFFB5CE9F),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16.5, height: 1.05),
                ),
                const SizedBox(height: 6),
                Text(
                  record.time,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 14.5,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 30),
        ],
      ),
    );
  }
}
