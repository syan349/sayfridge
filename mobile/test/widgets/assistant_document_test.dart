import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/assistant_document.dart';
import 'package:sayfridge/theme/app_theme.dart';
import 'package:sayfridge/widgets/assistant_widgets.dart';

void main() {
  test('generation splits introduction without changing document facts', () {
    const content = '## Inventory report\n\n- **Milk** — estimated 2 L';
    final document = AssistantDocument.fromMessage(
      'Here is your report.\n\n$content',
    )!;
    expect(document.introduction, 'Here is your report.');
    expect(document.content, content);
    expect(AssistantDocument.fromMessage(content)!.content, content);
    expect(
      AssistantDocument.fromMessage('Which storage space should I check?'),
      isNull,
    );
    expect(
      AssistantDocument.fromMessage('Saved 2 L of milk in Fridge.'),
      isNull,
    );
    expect(
      AssistantDocument.fromMessage(
        '### Ready for review\nConfirm before saving.',
      ),
      isNull,
    );
    final legacy = AssistantDocument.fromMessage(
      'There are 2 in-stock batches:\n- Fridge: Milk — 2 L\n- Pantry: Rice — 1 kg',
    );
    expect(legacy, isNotNull);
    expect(legacy!.content, contains('Milk — 2 L'));
    expect(
      AssistantDocument.fromMessage(
        '以下是你的食谱。\n\n## 番茄鸡蛋\n\n1. 煮熟。',
      )!.introduction,
      '以下是你的食谱。',
    );
  });

  testWidgets(
    'generated reports use full-width cards while short replies keep bubbles',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> show(String message) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(25),
                child: AssistantReply(
                  message: message,
                  textStyle: exampleMessageStyle,
                ),
              ),
            ),
          ),
        ),
      );
      await show(
        'Here’s your inventory report.\n\n## Inventory report\n\n'
        '### Fridge\n- **Milk** — estimated 2 L\n- **Eggs** — 3 each',
      );
      final card = find.byKey(const Key('assistant-document-card'));
      expect(card, findsOneWidget);
      expect(tester.getSize(card).width, 270);
      final introduction = find.byType(AssistantMessageBubble);
      expect(
        tester.getTopLeft(card).dy,
        greaterThan(tester.getBottomLeft(introduction).dy),
      );
      expect(
        tester.getSize(card).width,
        greaterThan(tester.getSize(introduction).width),
      );
      expect(
        find.text('Here’s your inventory report.', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Milk — estimated 2 L', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(AssistantAvatar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await show('Which storage space should I check?');
      expect(card, findsNothing);
      expect(find.byType(AssistantMessageBubble), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
