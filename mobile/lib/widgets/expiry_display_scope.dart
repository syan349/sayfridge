import 'package:flutter/material.dart';

import '../state/profile_controller.dart';

/// Keeps expiry colours on every route in sync with the user's reminder window.
class ExpiryDisplayScope extends InheritedNotifier<ProfileController> {
  const ExpiryDisplayScope({
    required ProfileController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static int daysBeforeExpiryOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ExpiryDisplayScope>()
          ?.notifier
          ?.preferences
          .daysBeforeExpiry ??
      3;
}
