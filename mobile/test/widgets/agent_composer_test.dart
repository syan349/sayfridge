import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/widgets/agent_composer.dart';

void main() {
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
