import 'package:flutter/material.dart';

import '../state/auth_controller.dart';
import 'sign_in_screen.dart';

import '../theme/app_theme.dart';
import '../widgets/profile_widgets.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({this.authController, super.key});

  final AuthController? authController;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _hidden = [true, true, true];
  bool _submitting = false;
  String? _error;

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

  Future<void> _submit() async {
    final auth = widget.authController;
    if (!_canSubmit || _submitting || auth == null) return;
    FocusScope.of(context).unfocus();
    setState(() { _submitting = true; _error = null; });
    final success = await auth.changePassword(currentPassword: _current.text, newPassword: _password.text);
    if (!mounted) return;
    if (success) {
      _current.clear(); _password.clear(); _confirm.clear();
      // The auth controller clears credentials on success, which makes
      // SayFridgeApp._syncSession schedule a post-frame popUntil(route.isFirst).
      // Defer our navigation to the same frame so that callback runs first
      // (callbacks are FIFO): the protected stack is discarded, then SignInScreen
      // is pushed ABOVE the AuthGate root instead of replacing it. That keeps
      // sign-in usable (back returns to the guest home, logging in pops normally).
      final navigator = Navigator.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigator.popUntil((route) => route.isFirst);
        navigator.push(MaterialPageRoute<void>(builder: (_) => SignInScreen(authController: auth,
          initialMessage: 'Password changed. Please sign in with your new password.')));
      });
    } else {
      setState(() { _submitting = false; _error = auth.errorMessage; });
    }
  }

  @override
  Widget build(BuildContext context) => ProfilePageScaffold(
    title: 'Change password',
    footer: ProfileActionButton(
      key: const Key('profile-change-password'),
      label: 'Change password',
      onPressed: _canSubmit && !_submitting ? _submit : null,
    ),
    children: [
      if (_submitting) const LinearProgressIndicator(),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
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
