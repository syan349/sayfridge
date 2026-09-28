import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../state/profile_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/profile_widgets.dart';
import 'avatar_picker_screen.dart';

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({required this.controller, super.key});
  final ProfileController controller;

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.controller.preferences.fullName,
  );
  late final _email = TextEditingController(
    text: widget.controller.authController.user?.email ?? '',
  );
  late String _avatarAsset = widget.controller.preferences.avatarAsset;
  late Uint8List? _avatarBytes = widget.controller.preferences.avatarBytes;
  bool _pickingImage = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _chooseAvatar() async {
    final selected = await Navigator.of(context).push<AvatarChoice>(
      MaterialPageRoute<AvatarChoice>(
        builder: (_) => AvatarPickerScreen(
          title: 'Avatar library',
          showUploadOption: false,
          initialAvatar: avatarChoices.firstWhere(
            (choice) => choice.assetPath == _avatarAsset,
            orElse: () => avatarChoices.first,
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _avatarAsset = selected.assetPath;
      _avatarBytes = null;
    });
  }

  Future<void> _uploadAvatar() async {
    if (_pickingImage) return;
    _pickingImage = true;
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (image == null) return;
      if (await image.length() > 2 * 1024 * 1024) {
        if (mounted) _message('Please choose an image smaller than 2 MB.');
        return;
      }
      final bytes = await image.readAsBytes();
      if (mounted) setState(() => _avatarBytes = bytes);
    } catch (_) {
      if (mounted) {
        _message('Unable to open that photo. Please try another image.');
      }
    } finally {
      _pickingImage = false;
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final saved = await widget.controller.saveIdentity(
      fullName: _name.text,
      avatarAsset: _avatarAsset,
      avatarBytes: _avatarBytes,
    );
    if (!mounted) return;
    if (saved) {
      _message('Profile saved on this device.');
      Navigator.of(context).pop();
    } else {
      _message(widget.controller.error ?? 'Unable to save your profile.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => ProfilePageScaffold(
      title: 'Personal Information',
      topGap: 4,
      footer: ProfileActionButton(
        key: const Key('profile-save'),
        label: 'Save changes',
        busy: widget.controller.isSaving,
        onPressed: _save,
      ),
      children: [
        Center(
          child: ProfileAvatar(
            asset: _avatarAsset,
            bytes: _avatarBytes,
            onUpload: _uploadAvatar,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('or ', style: TextStyle(fontSize: 16)),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 44),
                  foregroundColor: AppColors.primary,
                ),
                onPressed: _chooseAvatar,
                child: const Text(
                  'choose one',
                  style: TextStyle(
                    fontSize: 16,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.primary,
                    decorationThickness: 2,
                  ),
                ),
              ),
              const Text(' from library', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
        const SizedBox(height: 23),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              children: [
                ProfileField(
                  label: 'Full Name',
                  controller: _name,
                  fieldKey: const Key('profile-name'),
                  hint: 'Enter your full name',
                  autofillHints: const [AutofillHints.name],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your full name';
                    }
                    if (value.trim().length > 100) {
                      return 'Please use 100 characters or fewer';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 23),
                ProfileField(
                  label: 'Email',
                  controller: _email,
                  fieldKey: const Key('profile-email'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    final error = validateEmail(value);
                    if (error != null) return error;
                    if (value!.trim().toLowerCase() !=
                        widget.controller.authController.user?.email
                            .toLowerCase()) {
                      return 'Email changes are not available yet. Keep your current email to save.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
