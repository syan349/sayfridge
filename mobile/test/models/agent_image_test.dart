import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/agent_image.dart';

void main() {
  Uint8List jpeg([int extraBytes = 0]) =>
      Uint8List.fromList([0xff, 0xd8, 0xff, ...List.filled(extraBytes, 0)]);

  test('serializes supported image bytes without a data URL prefix', () {
    final image = AgentImage.fromBytes(
      jpeg(),
      mimeType: 'image/jpeg',
      imageId: '00000000-0000-4000-8000-000000000006',
    );

    expect(image.toJson(), {
      'image_id': '00000000-0000-4000-8000-000000000006',
      'mime_type': 'image/jpeg',
      'data_base64': '/9j/',
    });
  });

  test('recognizes a camera JPEG from bytes without file metadata', () {
    final cameraJpeg = Uint8List.fromList([
      0xff,
      0xd8,
      0xff,
      0xe1,
      0x00,
      0x04,
      0x00,
      0x00,
      0xff,
      0xc0,
      0x00,
      0x07,
      0x08,
      0x00,
      0x01,
      0x00,
      0x01,
      0xff,
      0xd9,
    ]);

    final image = AgentImage.fromPickedBytes(cameraJpeg);

    expect(image.mimeType, 'image/jpeg');
    expect(image.validateDimensions, returnsNormally);
  });

  test('rejects unsupported and mismatched image types', () {
    expect(
      () => AgentImage.fromBytes(jpeg(), mimeType: 'image/heic'),
      throwsFormatException,
    );
    expect(
      () => AgentImage.fromBytes(jpeg(), mimeType: 'image/png'),
      throwsFormatException,
    );
  });

  test('enforces per-image and batch limits', () {
    expect(
      () => AgentImage.fromBytes(
        jpeg(AgentImage.maxImageBytes),
        mimeType: 'image/jpeg',
      ),
      throwsFormatException,
    );

    final images = List.generate(
      AgentImage.maxImages + 1,
      (index) => AgentImage.fromBytes(
        jpeg(),
        mimeType: 'image/jpeg',
        imageId: '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
      ),
    );
    expect(() => AgentImage.validateBatch(images), throwsFormatException);
  });

  test('enforces the combined 8 MiB request limit', () {
    final images = List.generate(
      3,
      (index) => AgentImage.fromBytes(
        jpeg(AgentImage.maxImageBytes - 4),
        mimeType: 'image/jpeg',
        imageId: '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
      ),
    );

    expect(
      () => AgentImage.validateBatch(images),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Images must total no more than 8 MiB per request.',
        ),
      ),
    );
  });

  test('rejects duplicate image IDs in one request', () {
    final first = AgentImage.fromBytes(
      jpeg(),
      mimeType: 'image/jpeg',
      imageId: '00000000-0000-4000-8000-000000000009',
    );
    final duplicate = AgentImage.fromBytes(
      jpeg(),
      mimeType: 'image/jpeg',
      imageId: first.imageId,
    );

    expect(
      () => AgentImage.validateBatch([first, duplicate]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Each image must have a unique ID.',
        ),
      ),
    );
  });

  test('enforces the backend 20 million pixel limit', () {
    expect(
      () => AgentImage.validatePixelDimensions(5000, 4000),
      returnsNormally,
    );
    expect(
      () => AgentImage.validatePixelDimensions(5001, 4000),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Each image must be no larger than 20 million pixels.',
        ),
      ),
    );
    expect(
      () => AgentImage.validatePixelDimensions(0, 4000),
      throwsFormatException,
    );
  });

  test(
    'reads camera JPEG dimensions without using a browser image decoder',
    () {
      final cameraJpeg = Uint8List.fromList([
        0xff,
        0xd8,
        0xff,
        0xe1,
        0x00,
        0x04,
        0x00,
        0x00,
        0xff,
        0xc0,
        0x00,
        0x07,
        0x08,
        0x0f,
        0xa0,
        0x13,
        0x88,
        0xff,
        0xd9,
      ]);
      final image = AgentImage.fromBytes(cameraJpeg, mimeType: 'image/jpeg');

      expect(image.validateDimensions, returnsNormally);
    },
  );
}
