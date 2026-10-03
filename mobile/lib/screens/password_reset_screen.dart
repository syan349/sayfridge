import 'package:flutter/material.dart';

import '../widgets/app_dialog.dart';

import '../theme/app_theme.dart';
import '../widgets/profile_widgets.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _hidden = [true, true, true];

  bool get _mismatch =>
      _confirm.text.isNotEmpty && _confirm.text != _password.text;
  String? get _passwordError {
    if (_password.text.isEmpty) return null;
    if (_password.text.length < 8) return 'Use at least 8 characters';
    if (_password.text.length > 128) return 'Use 128 characters or fewer';
    if (_password.text == _current.text) {
      return 'Choose a different password from your current one';
    }
    return null;
  }

  bool get _canSubmit =>
      _current.text.isNotEmpty &&
      _password.text.isNotEmpty &&
      _passwordError == null &&
      _confirm.text == _password.text;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    // There is no change-password endpoint in the current auth contract.
    // Never store passwords locally or simulate a successful account change.
    showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('Password change unavailable'),
        content: const Text(
          'Password changes are not available yet. Your current password has not been changed.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ProfilePageScaffold(
    title: 'Password Reset',
    footer: ProfileActionButton(
      key: const Key('profile-change-password'),
      label: 'Change password',
      onPressed: _canSubmit ? _submit : null,
    ),
    children: [
      AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfileField(
              label: 'Current password',
              controller: _current,
              fieldKey: const Key('profile-current-password'),
              hint: 'Enter your current password',
              isPassword: true,
              obscureText: _hidden[0],
              autofillHints: const [AutofillHints.password],
              onToggleVisibility: () =>
                  setState(() => _hidden[0] = !_hidden[0]),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 23),
            ProfileField(
              label: 'New password',
              controller: _password,
              fieldKey: const Key('profile-new-password'),
              hint: 'At least 8 characters',
              isPassword: true,
              obscureText: _hidden[1],
              error: _passwordError,
              autofillHints: const [AutofillHints.newPassword],
              onToggleVisibility: () =>
                  setState(() => _hidden[1] = !_hidden[1]),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 23),
            ProfileField(
              label: 'Confirm new password',
              controller: _confirm,
              fieldKey: const Key('profile-confirm-password'),
              hint: 'Re-enter your new password',
              isPassword: true,
              obscureText: _hidden[2],
              error: _mismatch ? 'Passwords do not match' : null,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onToggleVisibility: () =>
                  setState(() => _hidden[2] = !_hidden[2]),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            const Text(
              'Re-enter your new password to continue',
              style: TextStyle(fontSize: 15, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}
