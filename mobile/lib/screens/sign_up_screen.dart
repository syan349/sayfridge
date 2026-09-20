import 'package:flutter/material.dart';

import '../widgets/auth_scaffold.dart';
import '../widgets/auth_widgets.dart';
import 'avatar_picker_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

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
    if (selected != null && mounted) setState(() => _avatar = selected);
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AvatarPickerScreen(initialAvatar: _avatar, isFinalStep: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: AuthContent(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    'Create Account',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: AvatarBubble(
                    key: Key('selected-avatar-${_avatar.name.toLowerCase()}'),
                    choice: _avatar,
                    size: 122,
                    onTap: _chooseAvatar,
                    showUploadBadge: true,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('or ', style: TextStyle(fontSize: 16)),
                    UnderlinedAction(
                      label: 'choose one',
                      onPressed: _chooseAvatar,
                      fontWeight: FontWeight.w500,
                    ),
                    const Text(' from library', style: TextStyle(fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 26),
                AuthField(
                  key: const Key('sign-up-name'),
                  label: 'Full Name',
                  hint: 'Enter your full name',
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  validator: (value) {
                    if (value == null || value.trim().length < 2) {
                      return 'Please enter your full name';
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
