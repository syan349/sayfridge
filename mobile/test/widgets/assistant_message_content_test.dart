import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/theme/app_theme.dart';
import 'package:sayfridge/widgets/assistant_message_content.dart';

void main() {
  testWidgets(
    'a query introduction ending in a colon keeps normal body weight',
    (tester) async {
      const introduction = 'Here’s what’s currently in your fridge:';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AssistantMessageContent(
              message: introduction,
              textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            ),
          ),
        ),
      );
      final text = tester.widget<RichText>(
        find.text(introduction, findRichText: true),
      );
      expect(text.text.style!.fontWeight, FontWeight.w400);
      expect(text.text.toPlainText(), introduction);
    },
  );

  testWidgets(
    'report hierarchy preserves facts and distinguishes paragraphs from list rows',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const message =
          '## Inventory report\n\n### Fridge\n'
          '- **Milk** — **estimated** 2 L\n  expires tomorrow\n'
          '- Eggs — 3 each\n\nUse first.\n\nCheck dates.';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(25),
                child: AssistantMessageContent(
                  message: message,
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Inventory report', findRichText: true), findsOneWidget);
      expect(find.text('Fridge', findRichText: true), findsOneWidget);
      final milk = find.text(
        'Milk — estimated 2 L expires tomorrow',
        findRichText: true,
      );
      final eggs = find.text('Eggs — 3 each', findRichText: true);
      expect(milk, findsOneWidget);
      expect(eggs, findsOneWidget);
      final rich = tester.widget<RichText>(milk);
      final spans = <TextSpan>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) spans.add(span);
        return true;
      });
      expect(
        spans.where((span) => span.text == 'Milk').single.style!.fontWeight,
        FontWeight.w700,
      );
      expect(
        spans
            .where((span) => span.text == 'estimated')
            .single
            .style!
            .fontWeight,
        FontWeight.w700,
      );
      final rowGap = tester.getTopLeft(eggs).dy - tester.getBottomLeft(milk).dy;
      final paragraphGap =
          tester.getTopLeft(find.text('Check dates.', findRichText: true)).dy -
          tester.getBottomLeft(find.text('Use first.', findRichText: true)).dy;
      expect(paragraphGap, greaterThan(rowGap));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy report labels and numbered steps stay readable at large font sizes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(25),
                child: AssistantMessageContent(
                  message:
                      '库存报告：\n\n- Arctic Box: Chicken Breast — 0.8 kg\n\n1. Check dates.\n2. Use the oldest batch.',
                  textStyle: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      final rich = tester.widget<RichText>(
        find.text('Arctic Box: Chicken Breast — 0.8 kg', findRichText: true),
      );
      final spans = <TextSpan>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) spans.add(span);
        return true;
      });
      final label = spans.first;
      expect(label.text, 'Arctic Box:');
      expect(label.style!.fontWeight, FontWeight.w700);
      expect(tester.takeException(), isNull);
    },
  );
}
