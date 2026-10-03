import 'package:flutter/material.dart';
import '../state/auth_controller.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_widgets.dart';
import 'avatar_picker_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({required this.authController, super.key});

  final AuthController authController;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _isSubmitting = false;
  AvatarChoice _avatar = avatarChoices.first;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _chooseAvatar() async {
    final selected = await Navigator.of(context).push<AvatarChoice>(
      MaterialPageRoute<AvatarChoice>(
        builder: (_) => AvatarPickerScreen(initialAvatar: _avatar),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _avatar = selected;
      });
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isSubmitting || widget.authController.isSubmitting) return;

    setState(() => _isSubmitting = true);
    late final bool success;
    try {
      success = await widget.authController.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        nickname: _nameController.text,
        avatarAsset: _avatar.assetPath,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.authController.errorMessage ??
                'Account created. Please sign in.',
          ),
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.authController.errorMessage ?? 'Unable to create account.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create Account',
      child: AuthContent(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: AvatarBubble(
                    key: Key('selected-avatar-${_avatar.name.toLowerCase()}'),
                    choice: _avatar,
                    size: 122,
                    borderWidth: 2.5,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      UnderlinedAction(
                        label: 'choose one',
                        onPressed: _chooseAvatar,
                        fontWeight: FontWeight.w500,
                      ),
                      const Text(
                        ' from library',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                AuthField(
                  key: const Key('sign-up-name'),
                  label: 'Nickname',
                  hint: 'Enter your nickname',
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.nickname],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your nickname';
                    }
                    if (value.trim().length > 100) {
                      return 'Please use 100 characters or fewer';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 19),
                AuthField(
                  key: const Key('sign-up-email'),
                  label: 'Email',
                  hint: 'Enter your email',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newUsername],
                  validator: validateEmail,
                ),
                const SizedBox(height: 19),
                AuthField(
                  key: const Key('sign-up-password'),
                  label: 'Password',
                  hint: 'At least 8 characters',
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  onToggleVisibility: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: validatePassword,
                ),
                const SizedBox(height: 19),
                AuthField(
                  key: const Key('sign-up-confirm-password'),
                  label: 'Confirm Password',
                  hint: 'Enter your password again',
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmation,
                  onToggleVisibility: () => setState(
                    () => _obscureConfirmation = !_obscureConfirmation,
                  ),
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return validatePassword(value);
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 30),
                PrimaryAuthButton(
                  key: const Key('sign-up-button'),
                  label: 'Sign up',
                  onPressed: _submit,
                  isLoading: _isSubmitting,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
