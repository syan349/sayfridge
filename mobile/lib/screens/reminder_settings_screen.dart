import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../state/profile_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_widgets.dart';

class ReminderSettingsScreen extends StatelessWidget {
  const ReminderSettingsScreen({required this.controller, super.key});
  final ProfileController controller;

  Future<void> _selectTime(BuildContext context) async {
    final preferences = controller.preferences;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: preferences.notificationHour,
        minute: preferences.notificationMinute,
      ),
      helpText: 'Notification time',
    );
    if (time == null || !context.mounted) return;
    await controller.saveReminders(
      notificationHour: time.hour,
      notificationMinute: time.minute,
    );
  }

  Future<void> _enableNotifications(BuildContext context) async {
    if (controller.notificationPermission ==
        NotificationPermissionState.enabled) {
      await _showStatus(context, 'Notifications are enabled.');
      return;
    }
    final continueRequest = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable notifications?'),
        content: Text(
          kIsWeb
              ? 'SayFridge will show reminders when you open this website. Web browsers cannot deliver scheduled reminders while the site is closed.'
              : 'SayFridge will use device notifications for expiry and daily inventory reminders at your selected time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (continueRequest != true || !context.mounted) return;
    final enabled = await controller.requestNotificationPermission();
    if (!context.mounted) return;
    await _showStatus(
      context,
      enabled
          ? kIsWeb
                ? 'Notifications enabled. Unread reminders will appear when you open SayFridge.'
                : 'Notifications enabled. Reminders will use your selected time.'
          : controller.notificationError ?? 'Notifications were not enabled.',
    );
  }

  Future<void> _showStatus(BuildContext context, String message) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Device notifications'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  String _notificationStatus() => switch (controller.notificationPermission) {
    NotificationPermissionState.enabled => 'Enabled',
    NotificationPermissionState.denied => 'Blocked',
    NotificationPermissionState.unsupported => 'Unavailable',
    NotificationPermissionState.unknown => 'Set up',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final preferences = controller.preferences;
      final busy =
          controller.isSaving ||
          controller.isLoading ||
          controller.isUpdatingNotifications;
      final time = TimeOfDay(
        hour: preferences.notificationHour,
        minute: preferences.notificationMinute,
      );
      return ProfilePageScaffold(
        title: 'Reminder settings',
        topGap: 19,
        children: [
          ProfileCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: busy ? null : () => _enableNotifications(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 20,
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.bell, size: 25),
                    const SizedBox(width: 13),
                    const Expanded(
                      flex: 2,
                      child: Text(
                        'Device notifications',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        controller.isUpdatingNotifications
                            ? 'Checking…'
                            : _notificationStatus(),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ProfileCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReminderToggle(
                  label: 'Expiry reminders',
                  description: 'Get notified before item expires.',
                  value: preferences.expiryReminders,
                  onChanged: busy
                      ? null
                      : (value) =>
                            controller.saveReminders(expiryReminders: value),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.primary),
                const SizedBox(height: 9),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Notify me', style: TextStyle(fontSize: 18)),
                    ),
                    Expanded(
                      flex: 2,
                      child: DropdownButton<int>(
                        isExpanded: true,
                        key: const Key('reminder-days'),
                        value: preferences.daysBeforeExpiry,
                        underline: const SizedBox.shrink(),
                        icon: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(CupertinoIcons.chevron_down, size: 19),
                        ),
                        style: const TextStyle(
                          fontFamily: 'Arial',
                          fontSize: 16,
                          color: Colors.black,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        items: [
                          for (var day = 1; day <= 7; day++)
                            DropdownMenuItem(
                              value: day,
                              alignment: AlignmentDirectional.centerEnd,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '$day ${day == 1 ? 'day' : 'days'} before',
                                ),
                              ),
                            ),
                        ],
                        onChanged: busy || !preferences.expiryReminders
                            ? null
                            : (value) => controller.saveReminders(
                                daysBeforeExpiry: value,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ProfileCard(
            child: _ReminderToggle(
              label: 'Daily check-in',
              description: 'Daily storage space reminder.',
              value: preferences.dailyCheckIn,
              onChanged: busy
                  ? null
                  : (value) => controller.saveReminders(dailyCheckIn: value),
            ),
          ),
          const SizedBox(height: 24),
          ProfileCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  key: const Key('reminder-time'),
                  onTap: busy ? null : () => _selectTime(context),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Notification time',
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                        Text(
                          MaterialLocalizations.of(
                            context,
                          ).formatTimeOfDay(time, alwaysUse24HourFormat: false),
                          style: const TextStyle(fontSize: 17),
                        ),
                        const SizedBox(width: 9),
                        const Icon(CupertinoIcons.chevron_forward, size: 21),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                const Divider(height: 1, color: AppColors.primary),
                const SizedBox(height: 16),
                const Text(
                  'Applies to both reminders.\nUses your device time zone.',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF7B7B7B),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Semantics(
            liveRegion: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (controller.error != null)
                  const ProfileIcon(ProfileAssets.warning, size: 25)
                else
                  const Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    color: AppColors.primary,
                    size: 27,
                  ),
                const SizedBox(width: 13),
                Flexible(
                  child: Text(
                    busy
                        ? 'Saving changes…'
                        : controller.error ?? 'Changes saved automatically',
                    style: TextStyle(
                      color: controller.error == null
                          ? const Color(0xFF808080)
                          : Colors.red,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _ReminderToggle extends StatelessWidget {
  const _ReminderToggle({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 5),
            Text(
              description,
              style: const TextStyle(fontSize: 14, color: Color(0xFF7B7B7B)),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Semantics(
        label: label,
        child: CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: const Color(0xFF8FBB5C),
        ),
      ),
    ],
  );
}
