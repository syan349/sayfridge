import 'package:image_picker/image_picker.dart';
import 'package:sayfridge/models/agent_input_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/screens/daily_consumption_recall_screen.dart';
import 'package:sayfridge/theme/app_theme.dart';
import 'package:sayfridge/services/voice_input_service.dart';
import 'package:sayfridge/widgets/hold_to_speak_button.dart';

class FakeRecallVoice implements VoiceInputService {
  void Function(String)? reportWords;
  int cancelled = 0;

  @override
  Future<bool> start({
    required void Function(String) onWords,
    required void Function(String) onError,
    required bool Function() shouldContinue,
  }) async {
    reportWords = onWords;
    return shouldContinue();
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {
    cancelled++;
  }
}

void main() {
  testWidgets('topic cards provide specific recall questions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DailyConsumptionRecallScreen(voiceInput: FakeRecallVoice()),
      ),
    );
    await tester.tap(find.text('Meals and cooking'));
    await tester.pump();
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('What ingredients did you use for your meals?'),
      150,
      scrollable: page,
    );
    expect(
      find.text('What ingredients did you use for your meals?'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Anything finished?'),
      150,
      scrollable: page,
    );
    await tester.ensureVisible(find.text('Anything finished?'));
    await tester.tap(find.text('Anything finished?'));
    await tester.pump();
    expect(find.text('Which items did you completely finish?'), findsOneWidget);
  });

  testWidgets('voice appends editable text and cancellation preserves it', (
    tester,
  ) async {
    final voice = FakeRecallVoice();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DailyConsumptionRecallScreen(voiceInput: voice),
      ),
    );
    final input = find.byKey(const Key('daily-consumption-input'));
    await tester.tap(find.byTooltip('Type a message'));
    await tester.pumpAndSettle();
    await tester.enterText(input, '3 eggs');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to voice input'));
    await tester.pumpAndSettle();
    final button = find.byType(HoldToSpeakButton);
    await tester.ensureVisible(button);
    final recording = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    voice.reportWords!('250 ml of milk');
    await tester.pump();
    expect(find.byKey(const Key('voice-recording-overlay')), findsOneWidget);
    await recording.up();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).controller!.text,
      '3 eggs 250 ml of milk',
    );
    expect(find.byType(DailyConsumptionRecallScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Switch to voice input'));
    await tester.pumpAndSettle();
    final cancelled = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    voice.reportWords!('last yoghurt');
    await cancelled.moveBy(const Offset(0, -80));
    await tester.pump();
    await cancelled.up();
    await tester.pumpAndSettle();
    expect(voice.cancelled, 1);
    await tester.tap(find.byTooltip('Type a message'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).controller!.text,
      '3 eggs 250 ml of milk',
    );
    await tester.enterText(input, '2 eggs');
    expect(tester.widget<TextField>(input).controller!.text, '2 eggs');
  });

  testWidgets('daily recall requires usage before continuing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const DailyConsumptionRecallScreen(),
      ),
    );

    expect(find.text('What did you use today?'), findsOneWidget);
    expect(find.text('Meals and cooking'), findsOneWidget);
    expect(find.text('Snacks and drinks'), findsOneWidget);
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Anything finished?'),
      180,
      scrollable: page,
    );
    expect(find.text('Anything finished?'), findsOneWidget);
    await tester.tap(find.byTooltip('Type a message'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Send message',
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('daily recall returns the trimmed usage summary', (tester) async {
    AgentInputDraft? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await Navigator.of(context).push<AgentInputDraft>(
                  MaterialPageRoute<AgentInputDraft>(
                    builder: (_) => const DailyConsumptionRecallScreen(),
                  ),
                );
              },
              child: const Text('Open recall'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open recall'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Type a message'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('daily-consumption-input')),
      '  3 eggs and 250 ml of milk  ',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(result?.text, '3 eggs and 250 ml of milk');
    expect(result?.images, isEmpty);
  });

  for (final text in ['', '2 eggs']) {
    testWidgets('daily recall transfers photos with usage: "$text"', (
      tester,
    ) async {
      final png = (await rootBundle.load(
        'assets/icons/inventory/milk.png',
      )).buffer.asUint8List();
      AgentInputDraft? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<AgentInputDraft>(
                    MaterialPageRoute<AgentInputDraft>(
                      builder: (_) => DailyConsumptionRecallScreen(
                        pickImages: () async => [
                          XFile.fromData(png, name: 'blob'),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('Open recall'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open recall'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add photos'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Selected photo'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove photo'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Selected photo'), findsNothing);
      await tester.tap(find.byTooltip('Add photos'));
      await tester.pumpAndSettle();
      if (text.isNotEmpty) {
        await tester.tap(find.byTooltip('Type a message'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('daily-consumption-input')),
          text,
        );
        await tester.pump();
      }
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(result?.text, text);
      expect(result?.images, hasLength(1));
      expect(result?.images.single.bytes, png);
      expect(result?.images.single.mimeType, 'image/png');
    });
  }

  testWidgets('invalid photos leave the daily usage editable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DailyConsumptionRecallScreen(
          pickImages: () async => [
            XFile.fromData(Uint8List.fromList([1, 2, 3])),
          ],
        ),
      ),
    );
    await tester.tap(find.byTooltip('Type a message'));
    await tester.pumpAndSettle();
    final input = find.byKey(const Key('daily-consumption-input'));
    await tester.enterText(input, '3 eggs');
    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    expect(find.text('Use a JPEG, PNG or WebP image.'), findsOneWidget);
    expect(find.bySemanticsLabel('Selected photo'), findsNothing);
    expect(tester.widget<TextField>(input).controller!.text, '3 eggs');
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Send message',
            ),
          )
          .onPressed,
      isNotNull,
    );
  });
}
