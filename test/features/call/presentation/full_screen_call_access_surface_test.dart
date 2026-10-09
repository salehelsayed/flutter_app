import 'package:flutter/material.dart';
import 'package:flutter_app/features/call/application/full_screen_call_access_prompt.dart';
import 'package:flutter_app/features/call/presentation/full_screen_call_access_surface.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/full_screen_call_access_prompt_test.dart'
    show FakeFullScreenCallAccessGateway;

void main() {
  final now = DateTime.utc(2026, 10, 8, 20);
  final denied = FullScreenCallAccessState(
    supported: true,
    allowed: false,
    deniedCallAt: now.subtract(const Duration(minutes: 5)),
  );

  Future<FullScreenCallAccessPromptController> pump(
    WidgetTester tester,
    FakeFullScreenCallAccessGateway gateway,
  ) async {
    final controller = FullScreenCallAccessPromptController(
      gateway: gateway,
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            FullScreenCallAccessSurface(controller: controller, child: child!),
        home: const _CounterPage(),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('card shows after a denied call; Not now hides it', (
    tester,
  ) async {
    final gateway = FakeFullScreenCallAccessGateway(denied);
    await pump(tester, gateway);
    expect(
      find.byKey(const ValueKey('full-screen-call-access-card')),
      findsOne,
    );
    expect(find.text('Show calls on your lock screen'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('full-screen-call-access-dismiss')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('full-screen-call-access-card')),
      findsNothing,
    );
    expect(gateway.dismissed, 1);
  });

  testWidgets('Open settings, then resume with access granted hides the card '
      'and keeps the app routes', (tester) async {
    final gateway = FakeFullScreenCallAccessGateway(denied);
    await pump(tester, gateway);
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('count 1'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('full-screen-call-access-open')),
    );
    await tester.pump();
    expect(gateway.opened, 1);

    gateway.state = FullScreenCallAccessState(
      supported: true,
      allowed: true,
      deniedCallAt: denied.deniedCallAt,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('full-screen-call-access-card')),
      findsNothing,
    );
    // The nested Navigator and its page state survived the card toggling.
    expect(find.text('count 1'), findsOne);
  });

  testWidgets('no card without a denied call', (tester) async {
    await pump(
      tester,
      FakeFullScreenCallAccessGateway(
        const FullScreenCallAccessState(supported: true, allowed: false),
      ),
    );
    expect(
      find.byKey(const ValueKey('full-screen-call-access-card')),
      findsNothing,
    );
  });
}

class _CounterPage extends StatefulWidget {
  const _CounterPage();

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text('count $_count'),
        TextButton(
          onPressed: () => setState(() => _count++),
          child: const Text('+'),
        ),
      ],
    ),
  );
}
