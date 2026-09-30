import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/agent_conversation_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/voice_input_service.dart';
import 'package:sayfridge/state/agent_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';

import 'support/integration_fixtures.dart';

void main() {
  testWidgets('voice overlay fits text and paints every screen edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    final api = ApiClient(client: MockClient((_) async => jsonResponse({})));
    addTearDown(api.close);
    final agent = AgentController(
      WorkspaceRepository(api, MemoryTokens()),
      store: MemoryAgentStore(),
    );
    addTearDown(agent.dispose);
    await agent.bindUser('alice');

    const previewKey = Key('voice-preview');
    final voice = _PreviewVoiceInput();
    await tester.pumpWidget(
      RepaintBoundary(
        key: previewKey,
        child: MaterialApp(
          theme: AppTheme.light,
          home: AgentConversationScreen(
            controller: agent,
            displayName: 'tim',
            voiceInput: voice,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Hold to speak')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump();

    final overlay = find.byKey(const Key('voice-recording-overlay'));
    final bubble = find.byKey(const Key('voice-input-status'));
    expect(tester.getRect(overlay), const Rect.fromLTWH(0, 0, 390, 844));
    final oneLineHeight = tester.getSize(bubble).height;
    expect(oneLineHeight, lessThan(88));
    expect(find.text('Listening…'), findsOneWidget);

    void expectPlainText() {
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.descendant(of: overlay, matching: find.byType(RichText)),
      )) {
        expect(
          paragraph.text.style?.decoration?.contains(
                TextDecoration.underline,
              ) ??
              false,
          isFalse,
        );
      }
    }

    Future<void> savePreview(String name) async {
      expectPlainText();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(previewKey),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final rgba = await image.toByteData();
        // Both system safe areas must receive the same dim layer as the page.
        for (final point in [const Offset(0, 0), const Offset(389, 843)]) {
          final pixel = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
          expect(rgba!.getUint8(pixel), lessThan(140));
          expect(rgba.getUint8(pixel + 1), lessThan(140));
          expect(rgba.getUint8(pixel + 2), lessThan(140));
        }
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'C:/Users/cqw80/Documents/ChatGPT/734/agent-ui-preview/$name.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    await savePreview('voice-overlay-listening-fixed');
    voice.onWords('I want to add two tomatoes in my fridge');
    await tester.pump();
    final multiLineHeight = tester.getSize(bubble).height;
    expect(multiLineHeight, greaterThan(oneLineHeight));
    await savePreview('voice-overlay-english');
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(find.text('Release to cancel'), findsWidgets);
    expect(tester.getSize(bubble).height, lessThan(multiLineHeight));
    await savePreview('voice-overlay-cancel-fixed');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);
  });
}

class _PreviewVoiceInput implements VoiceInputService {
  late void Function(String words) onWords;
  @override
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function(String message) onError,
    required bool Function() shouldContinue,
  }) async {
    this.onWords = onWords;
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}
