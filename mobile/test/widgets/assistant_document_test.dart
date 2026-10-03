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
    expect(
      document.content,
      '## Inventory report\n\n1. **Milk** — estimated 2 L',
    );
    expect(AssistantDocument.fromMessage(content)!.content, document.content);
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
    expect(legacy!.content, contains('1. **Milk** — 2 L'));
    expect(
      AssistantDocument.fromMessage(
        '以下是你的食谱。\n\n## 番茄鸡蛋\n\n1. 煮熟。',
      )!.introduction,
      '以下是你的食谱。',
    );
  });

  test(
    'old reports number each item and restart for every space without merging amounts',
    () {
      final report = AssistantDocument.fromMessage(
        'There are 12 in-stock batches:\n\n'
        '- Arctic Box: Chicken Breast — 0.8 kg (expired Sep 27); apple — 5 pics.\n'
        '- BoschFridge: Whole Milk — 2 L (expired Oct 1); Apples — estimated 4 each; Chicken Eggs — 3 each and 5 pieces; Tomatoes — 2 each and 2 pieces.\n'
        '- Pantry Potter: Carrots — 1.6 kg; Rice — 1 kg and 1.5 kg; Apples — 2.3 kg.\n\n'
        'Also recorded: Greek Yoghurt is empty, Chocolate is discarded, and Olive Oil is archived.',
      )!;
      expect(
        report.content,
        contains(
          '### Arctic Box\n\n1. **Chicken Breast** — 0.8 kg (expired Sep 27)\n2. **apple** — 5 pics.',
        ),
      );
      expect(
        report.content,
        contains(
          '### BoschFridge\n\n1. **Whole Milk** — 2 L (expired Oct 1)\n2. **Apples** — estimated 4 each\n3. **Chicken Eggs** — 3 each and 5 pieces\n4. **Tomatoes** — 2 each and 2 pieces.',
        ),
      );
      expect(
        report.content,
        contains(
          '### Pantry Potter\n\n1. **Carrots** — 1.6 kg\n2. **Rice** — 1 kg and 1.5 kg\n3. **Apples** — 2.3 kg.',
        ),
      );
      expect(
        report.content,
        contains(
          '### Other records\n\n1. Greek Yoghurt is empty\n2. Chocolate is discarded\n3. Olive Oil is archived.',
        ),
      );
      final recipe = '## Dinner recipe\n\n### Prepare\n3. Chop\n4. Cook';
      expect(AssistantDocument.fromMessage(recipe)!.content, recipe);
    },
  );

  test(
    'modern report item labels stay items instead of becoming storage headings',
    () {
      final report = AssistantDocument.fromMessage(
        '## Inventory report\n\n### Fridge\n- **Milk**: 2 L\n- Eggs: 3 each\n\n### Pantry\n8. Rice — 1 kg',
      )!;
      expect(
        report.content,
        contains('### Fridge\n1. **Milk**: 2 L\n2. Eggs: 3 each'),
      );
      expect(report.content, contains('### Pantry\n1. **Rice** — 1 kg'));
    },
  );

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
