import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sayfridge/screens/camera_input_screen.dart';

void main() {
  final png = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLJhgAAAABJRU5ErkJggg==',
    ),
  );

  testWidgets('gallery selects and returns multiple photos', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = [
      XFile.fromData(png, mimeType: 'image/png', name: 'milk.png'),
      XFile.fromData(png, mimeType: 'image/png', name: 'label.png'),
    ];
    List<XFile>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<List<XFile>>(
                  MaterialPageRoute<List<XFile>>(
                    builder: (_) => CameraInputScreen(
                      cameraPreview: const ColoredBox(color: Colors.blue),
                      pickGalleryImages: () async => selected,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close camera'), findsOneWidget);
    await tester.tap(find.byTooltip('Choose photos from library'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('camera-selected-preview')), findsOneWidget);
    expect(find.text('2 photos selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('camera-shutter-or-confirm')));
    await tester.pumpAndSettle();
    expect(result, hasLength(2));
    expect(await result?.first.readAsBytes(), png);
  });

  testWidgets('centre button captures directly and returns the photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final captured = XFile.fromData(
      png,
      mimeType: 'image/png',
      name: 'camera.png',
    );
    var captureCalls = 0;
    List<XFile>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<List<XFile>>(
                  MaterialPageRoute<List<XFile>>(
                    builder: (_) => CameraInputScreen(
                      cameraPreview: const ColoredBox(color: Colors.blue),
                      takePicture: () async {
                        captureCalls++;
                        return captured;
                      },
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('camera-shutter-or-confirm')));
    await tester.pumpAndSettle();
    expect(captureCalls, 1);
    expect(find.byKey(const Key('camera-selected-preview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('camera-shutter-or-confirm')));
    await tester.pumpAndSettle();
    expect(result, hasLength(1));
  });

  testWidgets('switch button invokes real camera switching action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var switches = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CameraInputScreen(
          cameraPreview: const ColoredBox(color: Colors.blue),
          switchCamera: () async => switches++,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Switch camera'));
    await tester.pumpAndSettle();
    expect(switches, 1);
    expect(
      find.text('Camera switching is controlled by your system camera.'),
      findsNothing,
    );
  });
}
