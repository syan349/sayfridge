import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../repositories/workspace_repository.dart';

class AgentImage {
  AgentImage._({
    required this.imageId,
    required this.mimeType,
    required this.dataBase64,
    required this.sizeBytes,
    required this.bytes,
  });

  static const int maxImages = 4;
  static const int maxImageBytes = 3 * 1024 * 1024;
  static const int maxTotalBytes = 8 * 1024 * 1024;
  static const int maxImagePixels = 20000000;
  static const Set<String> supportedMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  final String imageId;
  final String mimeType;
  final String dataBase64;
  final int sizeBytes;
  final Uint8List bytes;

  factory AgentImage.fromBytes(
    Uint8List bytes, {
    required String mimeType,
    String? imageId,
  }) {
    if (!supportedMimeTypes.contains(mimeType)) {
      throw const FormatException('Use a JPEG, PNG or WebP image.');
    }
    if (bytes.isEmpty || bytes.length > maxImageBytes) {
      throw const FormatException(
        'Each image must be nonempty and no larger than 3 MiB.',
      );
    }
    if (!_matchesSignature(bytes, mimeType)) {
      throw const FormatException(
        'The selected file does not match its declared image type.',
      );
    }
    return AgentImage._(
      imageId: imageId ?? requestId(),
      mimeType: mimeType,
      dataBase64: base64Encode(bytes),
      sizeBytes: bytes.length,
      bytes: Uint8List.fromList(bytes),
    );
  }

  static void validateBatch(List<AgentImage> images) {
    if (images.length > maxImages) {
      throw const FormatException('Send at most 4 images at a time.');
    }
    if (images.fold<int>(0, (total, image) => total + image.sizeBytes) >
        maxTotalBytes) {
      throw const FormatException(
        'Images must total no more than 8 MiB per request.',
      );
    }
    if (images.map((image) => image.imageId).toSet().length != images.length) {
      throw const FormatException('Each image must have a unique ID.');
    }
  }

  Future<void> validateDimensions() async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      validatePixelDimensions(descriptor.width, descriptor.height);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Unable to read this image. Use a valid JPEG, PNG or WebP image.',
      );
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static void validatePixelDimensions(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw const FormatException('The selected image has invalid dimensions.');
    }
    if (width * height > maxImagePixels) {
      throw const FormatException(
        'Each image must be no larger than 20 million pixels.',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'image_id': imageId,
    'mime_type': mimeType,
    'data_base64': dataBase64,
  };

  static bool _matchesSignature(Uint8List bytes, String mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
        return bytes.length >= 3 &&
            bytes[0] == 0xff &&
            bytes[1] == 0xd8 &&
            bytes[2] == 0xff;
      case 'image/png':
        const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
        return bytes.length >= signature.length &&
            List.generate(
              signature.length,
              (index) => bytes[index] == signature[index],
            ).every((matches) => matches);
      case 'image/webp':
        return bytes.length >= 12 &&
            ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
    }
    return false;
  }
}
