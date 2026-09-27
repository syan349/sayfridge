import 'dart:convert';
import 'dart:typed_data';

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

  void validateDimensions() {
    final dimensions = _dimensions(bytes, mimeType);
    validatePixelDimensions(dimensions.$1, dimensions.$2);
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

  static (int, int) _dimensions(Uint8List bytes, String mimeType) {
    try {
      switch (mimeType) {
        case 'image/png':
          if (bytes.length < 24) break;
          return (_uint32BigEndian(bytes, 16), _uint32BigEndian(bytes, 20));
        case 'image/jpeg':
          var offset = 2;
          const startOfFrame = {
            0xc0,
            0xc1,
            0xc2,
            0xc3,
            0xc5,
            0xc6,
            0xc7,
            0xc9,
            0xca,
            0xcb,
            0xcd,
            0xce,
            0xcf,
          };
          while (offset + 8 < bytes.length) {
            while (offset < bytes.length && bytes[offset] != 0xff) {
              offset++;
            }
            while (offset < bytes.length && bytes[offset] == 0xff) {
              offset++;
            }
            if (offset >= bytes.length) break;
            final marker = bytes[offset++];
            if (marker == 0xd8 || marker == 0xd9 || marker == 0x01) continue;
            if (offset + 1 >= bytes.length) break;
            final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
            if (segmentLength < 2 || offset + segmentLength > bytes.length) {
              break;
            }
            if (startOfFrame.contains(marker) && segmentLength >= 7) {
              final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
              final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
              return (width, height);
            }
            offset += segmentLength;
          }
        case 'image/webp':
          if (bytes.length < 30) break;
          final chunk = ascii.decode(bytes.sublist(12, 16), allowInvalid: true);
          if (chunk == 'VP8X') {
            return (
              1 + _uint24LittleEndian(bytes, 24),
              1 + _uint24LittleEndian(bytes, 27),
            );
          }
          if (chunk == 'VP8L' && bytes[20] == 0x2f) {
            final width = 1 + bytes[21] + ((bytes[22] & 0x3f) << 8);
            final height =
                1 +
                (bytes[22] >> 6) +
                (bytes[23] << 2) +
                ((bytes[24] & 0x0f) << 10);
            return (width, height);
          }
          if (chunk == 'VP8 ' &&
              bytes[23] == 0x9d &&
              bytes[24] == 0x01 &&
              bytes[25] == 0x2a) {
            final width = (bytes[26] | (bytes[27] << 8)) & 0x3fff;
            final height = (bytes[28] | (bytes[29] << 8)) & 0x3fff;
            return (width, height);
          }
      }
    } catch (_) {
      // Report one stable business-facing error below.
    }
    throw const FormatException(
      'Unable to read this image. Use a valid JPEG, PNG or WebP image.',
    );
  }

  static int _uint32BigEndian(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static int _uint24LittleEndian(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}
