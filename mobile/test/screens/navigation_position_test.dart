import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/preview/preview_session.dart';
import 'package:sayfridge/repositories/workspace_repository.dart';
import 'package:sayfridge/screens/ai_assistant_screen.dart';
import 'package:sayfridge/screens/home_screen.dart';
import 'package:sayfridge/screens/profile_screen.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/state/agent_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';

import '../support/integration_fixtures.dart';

void main() {
  for (final (size, safeArea) in [
    (const Size(320, 568), const EdgeInsets.only(top: 24)),
    (const Size(390, 844), const EdgeInsets.only(top: 47, bottom: 34)),
    (const Size(430, 932), const EdgeInsets.only(top: 59, bottom: 34)),
  ]) {
    testWidgets(
      'all guest and signed-in tabs keep navigation fixed at ${size.width}px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final guest = PreviewSession();
        final signedIn = PreviewSession();
        addTearDown(guest.dispose);
        addTearDown(signedIn.dispose);
        await guest.auth.initialize();
        await signedIn.enter();
        final api = ApiClient(
          client: MockClient(
            (_) async => throw StateError('Unexpected request'),
          ),
        );
        addTearDown(api.close);
        final agent = AgentController(
          WorkspaceRepository(api, MemoryTokens()),
          store: MemoryAgentStore(),
        );
        addTearDown(agent.dispose);
        await agent.bindUser('navigation-test');

        final pages = <String, Widget>{
          'guest-home': HomeScreen(isGuest: true, onAssistantTap: () {}),
          'guest-assistant': const AiAssistantScreen(isGuest: true),
          'guest-profile': ProfileScreen(
            authController: guest.auth,
            profileController: guest.profile,
            onAssistantTap: () {},
            onLoginTap: () {},
          ),
          'signed-in-home': HomeScreen(
            onAssistantTap: () {},
            inventoryController: signedIn.inventory,
            expirySummaryController: signedIn.expiry,
            storageSpaceController: signedIn.spaces,
          ),
          'signed-in-assistant': AiAssistantScreen(agentController: agent),
          'preview-assistant': const AiAssistantScreen(),
          'signed-in-profile': ProfileScreen(
            authController: signedIn.auth,
            profileController: signedIn.profile,
            onAssistantTap: () {},
            onLoginTap: () {},
          ),
        };

        final barWidth = size.width * 0.78;
        final expected = Rect.fromLTWH(
          (size.width - barWidth) / 2,
          size.height - safeArea.bottom - 28 - 66,
          barWidth,
          66,
        );
        for (final entry in pages.entries) {
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(entry.key),
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(padding: safeArea, viewPadding: safeArea),
                child: child!,
              ),
              home: entry.value,
            ),
          );
          await tester.pumpAndSettle();
          final bar = find.byKey(const Key('app-navigation-bar'));
          expect(tester.getRect(bar), expected, reason: entry.key);
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -220),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getRect(bar),
            expected,
            reason: '${entry.key} scrolled',
          );
          expect(tester.takeException(), isNull, reason: entry.key);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
