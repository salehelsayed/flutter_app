import 'package:flutter/material.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/identity/presentation/screens/onboarding_mic_permission_step.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/fakes/fake_mic_permission_gateway.dart';

const _title = 'Calls and voice notes';

Widget _app(MicPermissionGateway gateway, ValueNotifier<bool> done) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[
          BackgroundReadableColors.dark,
        ],
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                await runOnboardingMicPermissionStep(context, gateway);
                done.value = true;
              },
              child: const Text('start onboarding step'),
            ),
          ),
        ),
      ),
    );

Future<ValueNotifier<bool>> _start(
  WidgetTester tester,
  MicPermissionGateway gateway,
) async {
  final done = ValueNotifier<bool>(false);
  addTearDown(done.dispose);
  await tester.pumpWidget(_app(gateway, done));
  await tester.tap(find.text('start onboarding step'));
  await tester.pumpAndSettle();
  return done;
}

void main() {
  testWidgets('already granted skips the step quietly', (tester) async {
    final gateway = FakeMicPermissionGateway()
      ..currentStatus = MicPermissionStatus.granted;
    final done = await _start(tester, gateway);

    expect(find.text(_title), findsNothing);
    expect(gateway.requestCallCount, 0);
    expect(done.value, isTrue);
  });

  testWidgets('a permanently denied mic is not asked again', (tester) async {
    final gateway = FakeMicPermissionGateway()
      ..currentStatus = MicPermissionStatus.permanentlyDenied;
    final done = await _start(tester, gateway);

    expect(find.text(_title), findsNothing);
    expect(gateway.requestCallCount, 0);
    expect(done.value, isTrue);
  });

  testWidgets('allow asks once and onboarding completes when granted', (
    tester,
  ) async {
    final gateway = FakeMicPermissionGateway()
      ..currentStatus = MicPermissionStatus.denied
      ..statusToReturn = MicPermissionStatus.granted;
    final done = await _start(tester, gateway);

    expect(find.text(_title), findsOneWidget);
    expect(
      find.text('MKnoon uses your microphone for calls and voice notes.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('onboarding-mic-allow')));
    await tester.pumpAndSettle();

    expect(gateway.requestCallCount, 1);
    expect(find.text(_title), findsNothing);
    expect(done.value, isTrue);
  });

  testWidgets('a denial at the prompt never blocks onboarding', (tester) async {
    final gateway = FakeMicPermissionGateway()
      ..currentStatus = MicPermissionStatus.denied
      ..statusToReturn = MicPermissionStatus.denied;
    final done = await _start(tester, gateway);

    await tester.tap(find.byKey(const ValueKey('onboarding-mic-allow')));
    await tester.pumpAndSettle();

    expect(gateway.requestCallCount, 1);
    expect(find.text(_title), findsNothing);
    expect(done.value, isTrue);
  });

  testWidgets('not now skips without asking', (tester) async {
    final gateway = FakeMicPermissionGateway()
      ..currentStatus = MicPermissionStatus.denied;
    final done = await _start(tester, gateway);

    await tester.tap(find.byKey(const ValueKey('onboarding-mic-not-now')));
    await tester.pumpAndSettle();

    expect(gateway.requestCallCount, 0);
    expect(done.value, isTrue);
  });

  testWidgets('system back skips without asking', (tester) async {
    final gateway = FakeMicPermissionGateway()
      ..currentStatus = MicPermissionStatus.denied;
    final done = await _start(tester, gateway);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.maybePop();
    await tester.pumpAndSettle();

    expect(gateway.requestCallCount, 0);
    expect(done.value, isTrue);
  });

  testWidgets('an unreadable status skips the step', (tester) async {
    final gateway = FakeMicPermissionGateway()
      ..statusError = StateError('no plugin');
    final done = await _start(tester, gateway);

    expect(find.text(_title), findsNothing);
    expect(done.value, isTrue);
  });

  testWidgets('a failing prompt still completes onboarding', (tester) async {
    final gateway = _ThrowingRequestGateway();
    final done = await _start(tester, gateway);

    await tester.tap(find.byKey(const ValueKey('onboarding-mic-allow')));
    await tester.pumpAndSettle();

    expect(done.value, isTrue);
  });
}

final class _ThrowingRequestGateway extends FakeMicPermissionGateway {
  _ThrowingRequestGateway() {
    currentStatus = MicPermissionStatus.denied;
  }

  @override
  Future<MicPermissionStatus> request() async =>
      throw StateError('prompt failed');
}
