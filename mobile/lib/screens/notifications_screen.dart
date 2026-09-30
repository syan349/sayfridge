import 'package:flutter/material.dart';

import '../state/app_notification_controller.dart';
import '../state/expiry_summary_controller.dart';
import '../state/inventory_controller.dart';
import '../state/storage_space_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/inventory_visuals.dart';
import 'expiring_items_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    this.controller,
    this.expiryController,
    this.inventoryController,
    this.storageSpaceController,
    this.onExpiringTap,
    super.key,
  });

  final AppNotificationController? controller;
  final ExpirySummaryController? expiryController;
  final InventoryController? inventoryController;
  final StorageSpaceController? storageSpaceController;
  final VoidCallback? onExpiringTap;

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
                  child: controller == null
                      ? _emptyState()
                      : ListenableBuilder(
                          listenable: controller!,
                          builder: (context, _) =>
                              controller!.notifications.isEmpty
                              ? _emptyState()
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    25,
                                    8,
                                    25,
                                    28,
                                  ),
                                  child: _NotificationPanel(
                                    controller: controller!,
                                    onProcessExpired: () =>
                                        _openItems(context, overdue: true),
                                    onViewExpiring: () => _openItems(context),
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
}

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({
    required this.controller,
    required this.onProcessExpired,
    required this.onViewExpiring,
  });

  final AppNotificationController controller;
  final Future<void> Function() onProcessExpired;
  final Future<void> Function() onViewExpiring;

  @override
  Widget build(BuildContext context) {
    final notifications = controller.notifications;
    if (notifications.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final notification in notifications)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: notification.type == AppNotificationType.expired
                      ? const Color(0xFFD36B4A)
                      : const Color(0xFFA8D589),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        notification.type == AppNotificationType.expired
                            ? Icons.warning_amber_rounded
                            : Icons.notifications_none,
                        color: notification.type == AppNotificationType.expired
                            ? const Color(0xFFC8532C)
                            : AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          notification.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(notification.message),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (notification.processable)
                        FilledButton(
                          onPressed: onProcessExpired,
                          child: const Text('Process now'),
                        )
                      else if (notification.type ==
                          AppNotificationType.expiring)
                        TextButton(
                          onPressed: onViewExpiring,
                          child: const Text('View items'),
                        ),
                      TextButton(
                        onPressed: () => controller.markRead(notification.type),
                        child: const Text('Mark as read'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
