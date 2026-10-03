import 'package:flutter/material.dart';

import '../widgets/app_dialog.dart';
import '../state/auth_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_widgets.dart';
import 'sign_up_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({required this.authController, super.key});

  final AuthController authController;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _openSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SignUpScreen(authController: widget.authController),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isSubmitting || widget.authController.isSubmitting) return;

    setState(() => _isSubmitting = true);
    late final bool success;
    try {
      success = await widget.authController.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.authController.errorMessage ?? 'Unable to sign in.',
        ),
      ),
    );
  }

  void _showRecoveryDialog() {
    final initialEmail = _emailController.text;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: const Text('Recover password'),
        // The field owns its controller until the dialog's exit animation ends.
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Email',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 9),
              TextFormField(
                initialValue: initialEmail,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(hintText: 'Enter your email'),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Password reset is not available yet. No email has been sent.',
                  ),
                ),
              );
            },
            child: const Text('Send link'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: AuthContent(
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 42),
                Text(
                  'Sign in',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 22),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    const Text('New user?', style: TextStyle(fontSize: 16)),
                    UnderlinedAction(
                      label: 'Create an account',
                      onPressed: _openSignUp,
                    ),
                  ],
                ),
                const SizedBox(height: 27),
                AuthField(
                  key: const Key('sign-in-email'),
                  label: 'Email',
                  hint: 'Enter your email',
                  controller: _emailController,
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: validateEmail,
                ),
                const SizedBox(height: 22),
                AuthField(
                  key: const Key('sign-in-password'),
                  label: 'Password',
                  hint: 'Enter your password',
                  controller: _passwordController,
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  onToggleVisibility: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: validatePassword,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 18),
                UnderlinedAction(
                  label: 'Forgot password?',
                  onPressed: _showRecoveryDialog,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                ),
                const SizedBox(height: 26),
                PrimaryAuthButton(
                  key: const Key('sign-in-button'),
                  label: 'Log in',
                  onPressed: _submit,
                  isLoading: _isSubmitting,
                ),
                const SizedBox(height: 40),
                const _TermsText(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TermsText extends StatelessWidget {
  const _TermsText();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text.rich(
        TextSpan(
          text: 'By signing in with an account, you agree to SayFridge’s\n',
          children: [
            TextSpan(
              text: 'Terms of Service',
              style: TextStyle(decoration: TextDecoration.underline),
            ),
            TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy Policy',
              style: TextStyle(decoration: TextDecoration.underline),
            ),
            TextSpan(text: '.'),
          ],
        ),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35),
      ),
    );
  }
}
