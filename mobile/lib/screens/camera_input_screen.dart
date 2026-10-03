import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/app_dialog.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/app_bottom_navigation.dart';

class CameraInputScreen extends StatefulWidget {
  const CameraInputScreen({
    this.pickGalleryImages,
    this.takePicture,
    this.switchCamera,
    this.cameraPreview,
    super.key,
  });

  final Future<List<XFile>> Function()? pickGalleryImages;
  final Future<XFile?> Function()? takePicture;
  final Future<void> Function()? switchCamera;
  final Widget? cameraPreview;

  @override
  State<CameraInputScreen> createState() => _CameraInputScreenState();
}

class _CameraInputScreenState extends State<CameraInputScreen> {
  static const _maxImages = 4;
  static bool _permissionExplanationShown = false;

  final _picker = ImagePicker();
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  List<XFile> _selected = const [];
  List<Uint8List> _selectedBytes = const [];
  int _previewIndex = 0;
  bool _loading = false;
  String? _cameraError;

  bool get _usingTestCamera =>
      widget.cameraPreview != null ||
      widget.takePicture != null ||
      widget.switchCamera != null;

  bool get _cameraReady =>
      _usingTestCamera || (_controller?.value.isInitialized ?? false);

  @override
  void initState() {
    super.initState();
    if (!_usingTestCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _prepareCamera());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepareCamera() async {
    if (!mounted || _loading) return;
    if (!_permissionExplanationShown) {
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AppDialog(
          title: const Text('Camera access'),
          content: const Text(
            'SayFridge uses your camera only when you choose to photograph an item or label. Your browser will ask for device permission next.',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        if (mounted) {
          setState(() => _cameraError = 'Camera access has not been enabled.');
        }
        return;
      }
      _permissionExplanationShown = true;
    }

    setState(() {
      _loading = true;
      _cameraError = null;
    });
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw CameraException('NO_CAMERA', 'No camera was found.');
      }
      final rear = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      _cameraIndex = rear < 0 ? 0 : rear;
      await _openCamera(_cameraIndex);
    } on CameraException catch (error) {
      if (mounted) setState(() => _cameraError = _cameraMessage(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _cameraError =
              'Unable to start the camera. Check browser permission and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCamera(int index) async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller = controller;
    await controller.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _selectGallery() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final files = widget.pickGalleryImages != null
          ? await widget.pickGalleryImages!.call()
          : await _picker.pickMultiImage(
              maxWidth: 2000,
              maxHeight: 2000,
              imageQuality: 85,
              limit: _maxImages,
              requestFullMetadata: false,
            );
      if (files.isEmpty) return;
      final selected = files.take(_maxImages).toList(growable: false);
      final bytes = await Future.wait(
        selected.map((file) => file.readAsBytes()),
      );
      if (!mounted) return;
      setState(() {
        _selected = selected;
        _selectedBytes = bytes;
        _previewIndex = selected.length - 1;
      });
      if (files.length > _maxImages) {
        _message('You can attach at most 4 photos.');
      }
    } catch (_) {
      if (mounted) {
        _message('Unable to open the photo library. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _capture() async {
    if (_loading || !_cameraReady) return;
    setState(() => _loading = true);
    try {
      final file = widget.takePicture != null
          ? await widget.takePicture!.call()
          : await _controller!.takePicture();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selected = [file];
        _selectedBytes = [bytes];
        _previewIndex = 0;
      });
    } on CameraException catch (error) {
      if (mounted) _message(_cameraMessage(error));
    } catch (_) {
      if (mounted) _message('Unable to take a photo. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchCamera() async {
    if (_loading || _selected.isNotEmpty) return;
    if (widget.switchCamera != null) {
      await widget.switchCamera!.call();
      return;
    }
    if (_cameras.length < 2) return;
    setState(() => _loading = true);
    try {
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
      await _openCamera(_cameraIndex);
    } on CameraException catch (error) {
      if (mounted) _message(_cameraMessage(error));
    } catch (_) {
      if (mounted) _message('Unable to switch cameras.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirm() {
    if (_selected.isNotEmpty) Navigator.of(context).pop(_selected);
  }

  void _retake() {
    setState(() {
      _selected = const [];
      _selectedBytes = const [];
      _previewIndex = 0;
    });
  }

  void _removePhoto(int index) {
    final files = _selected.toList();
    final bytes = _selectedBytes.toList();
    files.removeAt(index);
    bytes.removeAt(index);
    setState(() {
      _selected = files;
      _selectedBytes = bytes;
      if (files.isEmpty) {
        _previewIndex = 0;
      } else if (_previewIndex >= files.length) {
        _previewIndex = files.length - 1;
      } else if (index < _previewIndex) {
        _previewIndex--;
      }
    });
  }

  String _cameraMessage(CameraException error) {
    if (error.code.toLowerCase().contains('denied') ||
        error.code.toLowerCase().contains('permission')) {
      return 'Camera permission was denied. Allow camera access in your browser settings and try again.';
    }
    return error.description ?? 'Unable to use the camera.';
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _selectedImage(int index, {required BoxFit fit, Key? key}) {
    Widget memoryFallback() => Image.memory(
      _selectedBytes[index],
      fit: fit,
      gaplessPlayback: false,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white70),
        ),
      ),
    );

    return KeyedSubtree(
      key: key,
      child: kIsWeb && _selected[index].path.isNotEmpty
          ? Image.network(
              _selected[index].path,
              fit: fit,
              gaplessPlayback: false,
              errorBuilder: (_, _, _) => memoryFallback(),
            )
          : memoryFallback(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSwitch = _usingTestCamera || _cameras.length > 1;
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
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.black),
                    if (_selectedBytes.isNotEmpty)
                      _selectedImage(
                        _previewIndex,
                        key: ValueKey(
                          'camera-main-preview-$_previewIndex-${_selectedBytes[_previewIndex].length}',
                        ),
                        fit: BoxFit.cover,
                      )
                    else if (widget.cameraPreview != null)
                      widget.cameraPreview!
                    else if (_cameraReady)
                      CameraPreview(_controller!)
                    else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(30),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.camera_alt_outlined,
                                color: Colors.white70,
                                size: 52,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _cameraError ?? 'Preparing camera…',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              if (_cameraError != null) ...[
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: _prepareCamera,
                                  child: const Text('Try camera again'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    if (_loading)
                      const ColoredBox(
                        color: Color(0x66000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),
            if (_selectedBytes.isNotEmpty)
              SizedBox(
                height: 84,
                child: ListView.separated(
                  key: const Key('camera-selected-thumbnails'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedBytes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      InkWell(
                        onTap: () => setState(() => _previewIndex = index),
                        child: Container(
                          key: ValueKey('camera-thumbnail-$index'),
                          width: 68,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: index == _previewIndex
                                  ? const Color(0xFF8FC957)
                                  : Colors.white54,
                              width: index == _previewIndex ? 3 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _selectedImage(index, fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        right: -7,
                        top: -7,
                        child: Semantics(
                          label: 'Remove selected photo ${index + 1}',
                          button: true,
                          child: InkWell(
                            onTap: () => _removePhoto(index),
                            customBorder: const CircleBorder(),
                            child: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.white,
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 29),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RoundCameraButton(
                      onTap: _loading ? null : _selectGallery,
                      tooltip: 'Choose photos from library',
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
                          : _selected.isEmpty
                          ? _capture
                          : _confirm,
                      onLongPress: _selected.isEmpty ? null : _retake,
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
                            color: _selected.isEmpty
                                ? Colors.white
                                : const Color(0xFF8FC957),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: _selected.isEmpty
                              ? null
                              : const Icon(Icons.check, color: Colors.black),
                        ),
                      ),
                    ),
                    _RoundCameraButton(
                      onTap: _loading || !canSwitch ? null : _switchCamera,
                      tooltip: 'Switch camera',
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
