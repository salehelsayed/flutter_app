import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_shell_theme_binding.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final preference in [
    BackgroundPreference.defaultBackground,
    BackgroundPreference.cosmic,
    BackgroundPreference.aurora,
  ]) {
    testWidgets('${preference.name} background stops frames while paused', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AmbientBackground(
            preference: preference,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ]) {
      testWidgets('${preference.name} stops frames when ${state.name}', (
        tester,
      ) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        addTearDown(() {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        });
        await tester.pumpWidget(_background(preference));
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.binding.transientCallbackCount, greaterThan(0));

        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.binding.transientCallbackCount, greaterThan(0));
      });
    }

    testWidgets(
      '${preference.name} switch stops and restarts background frames',
      (tester) async {
        final controller = AppShellController(
          initialBackgroundMotionEnabled: false,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _background(preference, controller: controller),
        );
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);

        controller.setBackgroundMotionEnabled(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.binding.transientCallbackCount, greaterThan(0));

        controller.setBackgroundMotionEnabled(false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );

    testWidgets('${preference.name} is static outside visible TickerMode', (
      tester,
    ) async {
      await tester.pumpWidget(_background(preference));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pumpWidget(_background(preference, visible: false));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(_background(preference));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets(
      '${preference.name} stops beneath an opaque route and resumes',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: AmbientBackground(
              preference: preference,
              child: const SizedBox.expand(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.binding.transientCallbackCount, greaterThan(0));

        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covering route')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.text('Covering route'), findsOneWidget);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);

        navigator.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(tester.binding.transientCallbackCount, greaterThan(0));
      },
    );

    for (final accessibleNavigation in [false, true]) {
      testWidgets(
        '${preference.name} keeps OS motion restriction $accessibleNavigation',
        (tester) async {
          final controller = AppShellController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _background(
              preference,
              controller: controller,
              disableAnimations: !accessibleNavigation,
              accessibleNavigation: accessibleNavigation,
            ),
          );
          await tester.pump(const Duration(milliseconds: 32));
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.binding.hasScheduledFrame, isFalse);

          controller.setBackgroundMotionEnabled(false);
          await tester.pump();
          controller.setBackgroundMotionEnabled(true);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 32));
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.binding.hasScheduledFrame, isFalse);

          await tester.pumpWidget(
            _background(preference, controller: controller),
          );
          await tester.pump(const Duration(milliseconds: 32));
          expect(tester.binding.transientCallbackCount, greaterThan(0));
        },
      );
    }

    testWidgets('${preference.name} mounted while paused starts static', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await tester.pumpWidget(_background(preference));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });
  }

  testWidgets(
    'switch leaves foreground accessibility and animation policy intact',
    (tester) async {
      final controller = AppShellController(
        initialBackgroundMotionEnabled: false,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _background(
          BackgroundPreference.defaultBackground,
          controller: controller,
          child: Builder(
            builder: (context) => Text(
              '${MediaQuery.disableAnimationsOf(context)}:'
              '${MediaQuery.accessibleNavigationOf(context)}:'
              '${TickerMode.valuesOf(context).enabled}',
            ),
          ),
        ),
      );
      expect(find.text('false:false:true'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('Signal remains static when moving background is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(_background(BackgroundPreference.daylightLagoon));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

Widget _background(
  BackgroundPreference preference, {
  AppShellController? controller,
  bool visible = true,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  Widget child = const SizedBox.expand(),
}) {
  final app = MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
      ),
      child: TickerMode(
        enabled: visible,
        child: AmbientBackground(preference: preference, child: child),
      ),
    ),
  );
  return controller == null
      ? app
      : BackgroundMotionScope(controller: controller, child: app);
}
