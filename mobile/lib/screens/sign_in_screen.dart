import 'package:flutter/material.dart';
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

  void _showResetDialog() {
    final initialEmail = _emailController.text;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset password'),
        // The field owns its controller until the dialog's exit animation ends.
        content: TextFormField(
          initialValue: initialEmail,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'Enter your email',
          ),
        ),
        actions: [
          TextButton(
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
                  onPressed: _showResetDialog,
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
                const SizedBox(height: 24),
                const _OrDivider(),
                const SizedBox(height: 22),
                const Center(
                  child: Text(
                    'Join with your favourite social media account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 25),
                const _SocialButtons(),
                const SizedBox(height: 72),
                const _TermsText(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: AppColors.muted)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'or',
            style: TextStyle(color: AppColors.muted, fontSize: 16),
          ),
        ),
        Expanded(child: Divider(color: AppColors.muted)),
      ],
    );
  }
}

class _SocialButtons extends StatelessWidget {
  const _SocialButtons();

  @override
  Widget build(BuildContext context) {
    const providers = [
      ('Apple', 'assets/icons/social/apple_logo.png', 34.0),
      ('Google', 'assets/icons/social/google_logo.png', 33.0),
      ('Facebook', 'assets/icons/social/facebook_logo.png', 34.0),
      ('X', 'assets/icons/social/twitter_logo.png', 31.0),
    ];

    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.94,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final provider in providers)
              Semantics(
                button: true,
                label: 'Continue with ${provider.$1}',
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${provider.$1} sign in is ready to connect to the API.',
                        ),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: Center(
                        child: Image.asset(
                          provider.$2,
                          width: provider.$3,
                          height: provider.$3,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
