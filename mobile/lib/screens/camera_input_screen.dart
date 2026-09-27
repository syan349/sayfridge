import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/app_bottom_navigation.dart';

class CameraInputScreen extends StatefulWidget {
  const CameraInputScreen({this.pickImage, super.key});

  final Future<XFile?> Function(ImageSource source)? pickImage;

  @override
  State<CameraInputScreen> createState() => _CameraInputScreenState();
}

class _CameraInputScreenState extends State<CameraInputScreen> {
  static const _cameraReference =
      'assets/images/assistant/camera_reference.png';

  final _picker = ImagePicker();
  XFile? _selected;
  Uint8List? _previewBytes;
  bool _loading = false;

  Future<void> _select(ImageSource source) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final file =
          await (widget.pickImage?.call(source) ??
              _picker.pickImage(
                source: source,
                preferredCameraDevice: CameraDevice.rear,
                maxWidth: 2000,
                maxHeight: 2000,
                imageQuality: 85,
                requestFullMetadata: false,
              ));
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selected = file;
        _previewBytes = bytes;
      });
    } catch (_) {
      if (mounted) {
        _message(
          'Unable to open the camera or photo library. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _usePhoto() {
    final selected = _selected;
    if (selected != null) Navigator.of(context).pop(selected);
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 86,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 31,
                      ),
                      tooltip: 'Close camera',
                    ),
                    const Icon(
                      Icons.flash_auto_rounded,
                      color: Colors.white,
                      size: 29,
                    ),
                  ],
                ),
              ),
            ),
            AspectRatio(
              aspectRatio: 864 / 1154,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = constraints.maxWidth / 864;
                  return ClipRect(
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        if (_previewBytes == null)
                          Positioned(
                            left: -57 * scale,
                            top: -337 * scale,
                            width: 1066 * scale,
                            height: 2088 * scale,
                            child: Image.asset(
                              _cameraReference,
                              fit: BoxFit.fill,
                            ),
                          )
                        else
                          Positioned.fill(
                            child: Image.memory(
                              _previewBytes!,
                              key: const Key('camera-selected-preview'),
                              fit: BoxFit.cover,
                            ),
                          ),
                        if (_loading)
                          const Positioned.fill(
                            child: ColoredBox(
                              color: Color(0x66000000),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 29),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RoundCameraButton(
                      onTap: _loading
                          ? null
                          : () => _select(ImageSource.gallery),
                      tooltip: 'Choose from photo library',
                      child: Image.asset(
                        AssistantAssets.photo,
                        width: 28,
                        height: 28,
                        color: Colors.white,
                        cacheWidth: 96,
                      ),
                    ),
                    GestureDetector(
                      onTap: _loading
                          ? null
                          : _selected == null
                          ? () => _select(ImageSource.camera)
                          : _usePhoto,
                      child: Container(
                        key: const Key('camera-shutter-or-confirm'),
                        width: 74,
                        height: 74,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _selected == null
                                ? Colors.white
                                : const Color(0xFF8FC957),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: _selected == null
                              ? null
                              : const Icon(Icons.check, color: Colors.black),
                        ),
                      ),
                    ),
                    _RoundCameraButton(
                      onTap: _loading
                          ? null
                          : () => _message(
                              'Camera switching is controlled by your system camera.',
                            ),
                      tooltip: 'Switch camera information',
                      child: const Icon(
                        Icons.cameraswitch_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundCameraButton extends StatelessWidget {
  const _RoundCameraButton({
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF28282A),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(width: 50, height: 50, child: Center(child: child)),
        ),
      ),
    );
  }
}
