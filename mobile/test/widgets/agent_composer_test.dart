import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/widgets/agent_composer.dart';

void main() {
  testWidgets(
    'typing grows the composer upward while action buttons stay put',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 346,
                child: AgentComposer(
                  controller: controller,
                  enabled: true,
                  hasImages: false,
                  onPhotoPressed: () {},
                  onSendPressed: () {},
                  voiceButton: const Text('Press and hold to speak'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Type a message'));
      await tester.pump();
      final topBefore = tester.getTopLeft(find.byType(AgentComposer)).dy;
      final photoBottomBefore = tester
          .getBottomLeft(find.byTooltip('Add photos'))
          .dy;
      final sendBottomBefore = tester
          .getBottomLeft(find.byTooltip('Send message'))
          .dy;

      await tester.enterText(
        find.byKey(const Key('assistant-message-field')),
        'One\nTwo\nThree\nFour\nFive',
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('assistant-message-field'))).width,
        greaterThan(280),
      );
      for (final image in tester.widgetList<Image>(
        find.descendant(
          of: find.byType(AgentComposer),
          matching: find.byType(Image),
        ),
      )) {
        expect(image.height, 20);
      }
      expect(
        tester.getTopLeft(find.byType(AgentComposer)).dy,
        lessThan(topBefore),
      );
      expect(
        tester.getBottomLeft(find.byTooltip('Add photos')).dy,
        photoBottomBefore,
      );
      expect(
        tester.getBottomLeft(find.byTooltip('Send message')).dy,
        sendBottomBefore,
      );
    },
  );

  testWidgets(
    'voice prompt is centered and photo icon keeps its camera action',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var photoTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 346,
                child: AgentComposer(
                  controller: controller,
                  enabled: true,
                  hasImages: false,
                  onPhotoPressed: () => photoTaps++,
                  onSendPressed: () {},
                  voiceButton: const Center(
                    child: Text('Press and hold to speak'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final composerCenter = tester.getCenter(find.byType(AgentComposer)).dx;
      final promptCenter = tester
          .getCenter(find.text('Press and hold to speak'))
          .dx;
      expect((composerCenter - promptCenter).abs(), lessThan(1));
      await tester.tap(find.byTooltip('Add photos'));
      expect(photoTaps, 1);
    },
  );

  testWidgets('successful send reset returns the composer to voice mode', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    late StateSetter updateHost;
    var voiceModeReset = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return AgentComposer(
                controller: controller,
                enabled: true,
                hasImages: false,
                onPhotoPressed: () {},
                onSendPressed: () {},
                voiceButton: const Text(
                  'Press and hold to speak',
                  key: Key('test-voice-button'),
                ),
                voiceModeReset: voiceModeReset,
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Type a message'));
    await tester.pump();
    expect(find.byKey(const Key('assistant-message-field')), findsOneWidget);

    controller.text = 'hello';
    controller.clear();
    updateHost(() => voiceModeReset++);
    await tester.pump();

    expect(find.byKey(const Key('assistant-message-field')), findsNothing);
    expect(find.byKey(const Key('test-voice-button')), findsOneWidget);
  });
}
