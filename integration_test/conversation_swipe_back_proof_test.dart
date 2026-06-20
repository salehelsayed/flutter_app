/// Real-device proof: the 1:1 conversation screen supports the iOS
/// edge-swipe-back gesture, at parity with the group conversation screen.
///
/// The host suite
/// (test/features/conversation/presentation/navigation/conversation_route_transition_test.dart)
/// already locks the route TYPE (MaterialPageRoute) and drives the back gesture
/// through flutter_test's gesture arena under a *platform override*. The one
/// genuine host↔device gap here is the gesture itself: the simulator exercises
/// the REAL iOS binding, the real viewport/DPR, and real gesture timing — the
/// exact gap the proof-test convention exists for (see the header of
/// integration_test/group_conversation_polish_proof_test.dart, the template
/// this mirrors).
///
/// This renders the REAL ConversationScreen pushed via the production
/// `buildConversationRoute` onto a real navigation stack on a booted simulator,
/// then performs a real left-edge drag and asserts the route pops.
///
/// Proves:
///   * INV-1 — a real iOS left-edge swipe on the 1:1 conversation route pops
///     back to the previous screen.
///   * INV-2 — parity: a route pushed via stock `MaterialPageRoute` (what the
///     group conversation screen uses) pops the same way. Locks the 1:1 helper
///     against silently diverging from the group route class again.
///   * INV-5 — RTL (ar): the back gesture lives on the RIGHT edge and still
///     pops (Flutter mirrors it via `Directionality`).
@Tags(['device'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  List<ConversationMessage> seedMessages() => const [
    ConversationMessage(
      id: 'm1',
      contactPeerId: 'peer-2',
      senderPeerId: 'peer-2',
      text: 'Hello from the chat',
      timestamp: '2026-02-09T14:05:00.000Z',
      status: 'sent',
      isIncoming: true,
      createdAt: '2026-02-09T14:05:00.000Z',
    ),
  ];

  // The pure presentation screen (no wired DI), mirroring how the group polish
  // proof builds GroupConversationScreen with in-memory fixtures. Production
  // pushes PopScope > Scaffold > ConversationScreen (conversation_wired.dart
  // :3949-3956); the Scaffold supplies the Material ancestor the compose-area
  // TextField requires. We deliberately omit the PopScope so the swipe pops —
  // the upload-guard suppression (INV-3) is covered by the host suite.
  Widget chatScreen(GlobalKey<NavigatorState> nav) => Scaffold(
    body: ConversationScreen(
      contactPeerId: 'peer-2',
      contactUsername: 'Alice',
      connectionDate: 'Feb 2026',
      ownPeerId: 'peer-1',
      messages: seedMessages(),
      onSend: (_) {},
      onBack: () => nav.currentState!.pop(),
      initialLoadDone: true,
    ),
  );

  Widget appWith(
    GlobalKey<NavigatorState> nav, {
    Locale locale = const Locale('en'),
  }) => MaterialApp(
    navigatorKey: nav,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: Center(child: Text('ORBIT'))),
  );

  // Logical viewport size on the booted device (DPR-resolved).
  Size logicalSize(WidgetTester tester) =>
      tester.view.physicalSize / tester.view.devicePixelRatio;

  // Bounded frame pumping. ConversationScreen's AmbientBackground runs an
  // infinite repeat() animation, so `pumpAndSettle()` NEVER settles on the live
  // integration binding (it waits for an idle frame schedule that never comes)
  // — it hangs. ~600ms of frames comfortably covers the 300ms push/pop
  // transitions. (Same reason group_conversation_polish_proof_test uses
  // pumpFrames rather than pumpAndSettle.)
  Future<void> settleFrames(WidgetTester tester, {int count = 20}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  // A real edge drag, sampled across frames so the gesture recogniser builds
  // up displacement/velocity the way a real finger swipe does.
  Future<void> edgeDrag(
    WidgetTester tester, {
    required Offset from,
    required double dx,
  }) async {
    final gesture = await tester.startGesture(from);
    const steps = 14;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(dx / steps, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settleFrames(tester); // let the pop animation run to completion
  }

  testWidgets(
    '1:1 conversation: real iOS left-edge swipe pops to the previous screen',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(appWith(nav));
      expect(find.text('ORBIT'), findsOneWidget);

      nav.currentState!.push(buildConversationRoute<void>(
        builder: (_) => chatScreen(nav),
      ));
      await settleFrames(tester);
      expect(find.text('ORBIT'), findsNothing);
      // Unique to the chat screen ('Alice' appears in both header and bubble).
      expect(find.text('Hello from the chat'), findsOneWidget);

      final size = logicalSize(tester);
      await edgeDrag(
        tester,
        from: const Offset(6, 320),
        dx: size.width * 0.9, // well past mid-width, left → right
      );

      expect(find.text('ORBIT'), findsOneWidget); // back on the previous screen
      expect(find.text('Hello from the chat'), findsNothing);
    },
  );

  testWidgets(
    'parity: a stock MaterialPageRoute (what groups use) pops the same way',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(appWith(nav));

      // Exactly what GroupConversationWired pushes — the control for INV-2.
      nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => chatScreen(nav),
      ));
      await settleFrames(tester);
      expect(find.text('ORBIT'), findsNothing);

      final size = logicalSize(tester);
      await edgeDrag(
        tester,
        from: const Offset(6, 320),
        dx: size.width * 0.9,
      );

      expect(find.text('ORBIT'), findsOneWidget);
    },
  );

  testWidgets(
    'RTL (ar): the back gesture lives on the right edge and still pops',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(appWith(nav, locale: const Locale('ar')));

      nav.currentState!.push(buildConversationRoute<void>(
        builder: (_) => chatScreen(nav),
      ));
      await settleFrames(tester);
      expect(find.text('ORBIT'), findsNothing);

      // Under RTL Flutter mirrors the gesture to the right edge; the drag runs
      // right → left.
      final size = logicalSize(tester);
      await edgeDrag(
        tester,
        from: Offset(size.width - 6, 320),
        dx: -size.width * 0.9,
      );

      expect(find.text('ORBIT'), findsOneWidget);
    },
  );
}
