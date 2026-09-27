import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sayfridge/screens/camera_input_screen.dart';

void main() {
  testWidgets('keeps the camera design while gallery selection returns a photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLJhgAAAABJRU5ErkJggg==',
      ),
    );
    final selected = XFile.fromData(
      png,
      mimeType: 'image/png',
      name: 'milk.png',
    );
    XFile? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<XFile>(
                  MaterialPageRoute<XFile>(
                    builder: (_) => CameraInputScreen(
                      pickImage: (source) async {
                        expect(source, ImageSource.gallery);
                        return selected;
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
    expect(find.byTooltip('Close camera'), findsOneWidget);
    await tester.tap(find.byTooltip('Choose from photo library'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('camera-selected-preview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('camera-shutter-or-confirm')));
    await tester.pumpAndSettle();
    expect(result?.mimeType, 'image/png');
    expect(await result?.readAsBytes(), png);
  });

  testWidgets('explains that camera switching belongs to the system camera', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: CameraInputScreen()));
    await tester.tap(find.byTooltip('Switch camera information'));
    await tester.pump();
    expect(
      find.text('Camera switching is controlled by your system camera.'),
      findsOneWidget,
    );
  });
}
