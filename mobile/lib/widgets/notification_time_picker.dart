import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

Future<TimeOfDay?> showNotificationTimePicker(
  BuildContext context,
  TimeOfDay initialTime,
) => showModalBottomSheet<TimeOfDay>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.background,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => NotificationTimePicker(initialTime: initialTime),
);

class NotificationTimePicker extends StatefulWidget {
  const NotificationTimePicker({required this.initialTime, super.key});
  final TimeOfDay initialTime;
  @override
  State<NotificationTimePicker> createState() => _NotificationTimePickerState();
}

class _NotificationTimePickerState extends State<NotificationTimePicker> {
  late int _hour = (widget.initialTime.hour + 11) % 12;
  late int _minute = widget.initialTime.minute;
  late int _period = widget.initialTime.hour ~/ 12;
  late final _hourController = FixedExtentScrollController(initialItem: _hour);
  late final _minuteController = FixedExtentScrollController(
    initialItem: _minute,
  );
  late final _periodController = FixedExtentScrollController(
    initialItem: _period,
  );
  TimeOfDay get _time =>
      TimeOfDay(hour: (_hour + 1) % 12 + _period * 12, minute: _minute);

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  Widget _wheel(
    String label,
    FixedExtentScrollController controller,
    List<String> values,
    ValueChanged<int> onChanged, {
    bool looping = true,
  }) => Expanded(
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 164,
          child: CupertinoPicker(
            key: ValueKey('notification-${label.toLowerCase()}'),
            scrollController: controller,
            itemExtent: 44,
            looping: looping,
            onSelectedItemChanged: onChanged,
            selectionOverlay: Container(
              decoration: BoxDecoration(
                color: const Color(0x2296C55B),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            children: [
              for (final value in values)
                Center(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontFamily: 'Arial',
                      color: Color(0xFF086B38),
                      fontSize: 27,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Notification time',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose when your daily reminders arrive.',
            style: TextStyle(color: AppColors.muted, fontSize: 14),
          ),
          const SizedBox(height: 18),
          Semantics(
            liveRegion: true,
            child: Center(
              child: Text(
                MaterialLocalizations.of(
                  context,
                ).formatTimeOfDay(_time, alwaysUse24HourFormat: false),
                key: const Key('notification-time-preview'),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF086B38),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFDCF3D1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _wheel('Hour', _hourController, [
                  for (var i = 1; i <= 12; i++) '$i',
                ], (value) => setState(() => _hour = value)),
                const SizedBox(width: 8),
                _wheel(
                  'Minute',
                  _minuteController,
                  [for (var i = 0; i < 60; i++) i.toString().padLeft(2, '0')],
                  (value) => setState(() => _minute = value),
                ),
                const SizedBox(width: 8),
                _wheel(
                  'Period',
                  _periodController,
                  const ['AM', 'PM'],
                  (value) => setState(() => _period = value),
                  looping: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Uses your device time zone.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 22),
          FilledButton(
            key: const Key('save-notification-time'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context, _time),
            child: const Text('Save time'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: AppColors.primary),
              foregroundColor: Colors.black,
              shape: const StadiumBorder(),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
