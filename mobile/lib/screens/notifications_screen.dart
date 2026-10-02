import 'package:flutter/material.dart';

import '../state/app_notification_controller.dart';
import '../state/expiry_summary_controller.dart';
import '../state/inventory_controller.dart';
import '../state/storage_space_controller.dart';
import '../models/agent_input_draft.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/inventory_visuals.dart';
import '../widgets/page_scroll_fade.dart';
import 'daily_consumption_recall_screen.dart';
import 'expiring_items_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    this.controller,
    this.expiryController,
    this.inventoryController,
    this.storageSpaceController,
    this.onExpiringTap,
    this.onDailyConsumptionSubmit,
    super.key,
  });

  final AppNotificationController? controller;
  final ExpirySummaryController? expiryController;
  final InventoryController? inventoryController;
  final StorageSpaceController? storageSpaceController;
  final VoidCallback? onExpiringTap;
  final ValueChanged<AgentInputDraft>? onDailyConsumptionSubmit;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                const OverviewHeader(title: 'Notifications'),
                Expanded(
                  child: PageScrollFade(
                    child: controller == null
                        ? _emptyState()
                        : ListenableBuilder(
                            listenable: controller!,
                            builder: (context, _) =>
                                controller!.notifications.isEmpty
                                ? _emptyState()
                                : SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      8,
                                      20,
                                      28,
                                    ),
                                    child: _NotificationPanel(
                                      controller: controller!,
                                      onProcessExpired: () =>
                                          _openItems(context, overdue: true),
                                      onViewExpiring: () => _openItems(context),
                                      onDailyCheckIn: () =>
                                          _openDailyCheckIn(context),
                                    ),
                                  ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            HomeAssets.notificationEmpty,
            width: 64,
            height: 64,
            cacheWidth: 192,
            excludeFromSemantics: true,
          ),
          const SizedBox(height: 18),
          const Text(
            'No unread notifications',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'You’re all caught up.',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );

  Future<void> _openItems(BuildContext context, {bool overdue = false}) async {
    final expiry = expiryController;
    final inventory = inventoryController;
    if (expiry == null || inventory == null) return;
    final previousBucket = expiry.bucket;
    await expiry.selectBucket(overdue ? 'overdue' : null);
    if (!context.mounted) return;
    if (onExpiringTap != null) {
      onExpiringTap!();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExpiringItemsScreen(
          controller: expiry,
          inventoryController: inventory,
          storageSpaceController: storageSpaceController,
        ),
      ),
    );
    if (!context.mounted) return;
    await expiry.selectBucket(previousBucket);
    await inventory.reload();
  }

  Future<void> _openDailyCheckIn(BuildContext context) async {
    final summary = await Navigator.of(context).push<AgentInputDraft>(
      MaterialPageRoute<AgentInputDraft>(
        builder: (_) => const DailyConsumptionRecallScreen(),
      ),
    );
    if (!context.mounted || summary == null || summary.isEmpty) return;
    await controller?.markRead(AppNotificationType.daily);
    if (!context.mounted) return;
    onDailyConsumptionSubmit?.call(summary);
  }
}

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({
    required this.controller,
    required this.onProcessExpired,
    required this.onViewExpiring,
    required this.onDailyCheckIn,
  });

  final AppNotificationController controller;
  final Future<void> Function() onProcessExpired;
  final Future<void> Function() onViewExpiring;
  final Future<void> Function() onDailyCheckIn;

  @override
  Widget build(BuildContext context) {
    final notifications = controller.notifications;
    if (notifications.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final notification in notifications)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: notification.type == AppNotificationType.expired
                      ? const Color(0xFFE8BDA9)
                      : const Color(0xFFD7E6C7),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: notification.type == AppNotificationType.expired
                          ? const Color(0xFFFFF1E8)
                          : const Color(0xFFF0F7E9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      notification.type == AppNotificationType.expired
                          ? Icons.warning_amber_rounded
                          : Icons.notifications_none,
                      color: notification.type == AppNotificationType.expired
                          ? const Color(0xFFC8532C)
                          : AppColors.primary,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  notification.title,
                                  textAlign: TextAlign.left,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Mark as read',
                              onPressed: () =>
                                  controller.markRead(notification.type),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(34, 34),
                                maximumSize: const Size(34, 34),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: const Color(0xFF72786C),
                              ),
                              icon: const Icon(Icons.close, size: 21),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          notification.message,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            color: Color(0xFF596050),
                            fontSize: 15.5,
                            height: 1.55,
                          ),
                        ),
                        if (notification.processable ||
                            notification.type == AppNotificationType.expiring ||
                            notification.type == AppNotificationType.daily) ...[
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              style: _actionStyle(
                                background: notification.processable
                                    ? AppColors.userMessage
                                    : const Color(0xFFF0F6E9),
                                foreground: notification.processable
                                    ? Colors.white
                                    : AppColors.userMessage,
                              ),
                              onPressed: notification.processable
                                  ? onProcessExpired
                                  : notification.type ==
                                        AppNotificationType.daily
                                  ? onDailyCheckIn
                                  : onViewExpiring,
                              child: Text(
                                notification.processable
                                    ? 'Process now'
                                    : notification.type ==
                                          AppNotificationType.daily
                                    ? 'Record usage'
                                    : 'View items',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static ButtonStyle _actionStyle({
    required Color background,
    required Color foreground,
  }) => FilledButton.styleFrom(
    backgroundColor: background,
    foregroundColor: foreground,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    minimumSize: const Size(0, 40),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );
}
