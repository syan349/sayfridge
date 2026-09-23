import 'package:flutter/widgets.dart';

import '../state/auth_controller.dart';

typedef AuthViewBuilder = Widget Function(
  BuildContext context,
  AuthController authController,
);

class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.authController,
    required this.checkingBuilder,
    required this.unauthenticatedBuilder,
    required this.authenticatedBuilder,
    required this.errorBuilder,
    super.key,
  });

  final AuthController authController;
  final AuthViewBuilder checkingBuilder;
  final AuthViewBuilder unauthenticatedBuilder;
  final AuthViewBuilder authenticatedBuilder;
  final AuthViewBuilder errorBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.authController.initialize();
  }

  @override
  void didUpdateWidget(AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.authController != widget.authController) {
      widget.authController.initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.authController,
      builder: (context, _) {
        return switch (widget.authController.status) {
          AuthStatus.initial ||
          AuthStatus.checking => widget.checkingBuilder(
            context,
            widget.authController,
          ),
          AuthStatus.unauthenticated => widget.unauthenticatedBuilder(
            context,
            widget.authController,
          ),
          AuthStatus.authenticated => widget.authenticatedBuilder(
            context,
            widget.authController,
          ),
          AuthStatus.error => widget.errorBuilder(
            context,
            widget.authController,
          ),
        };
      },
    );
  }
}