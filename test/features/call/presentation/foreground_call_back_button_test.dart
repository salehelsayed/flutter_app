import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_back_guard.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_overlay.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Beta 2026-09-24 (F4): Back pressed three times on the Pixel during a
// connected call. The call surface is a Stack layer, not a route, so Back
// popped the hidden conversation route and then SystemNavigator.pop finished
// MainActivity. The engine detached and the call ended with appShutdown.

final _callId = CallId.parse('33333333-3333-4333-8333-333333333333');
final _now = DateTime.utc(2026, 9, 24, 21, 15);

void main() {
  late List<String> platformCalls;
  late List<Object?> frameworkHandlesBack;

  setUp(() {
    platformCalls = <String>[];
    frameworkHandlesBack = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call.method);
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            frameworkHandlesBack.add(call.arguments);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<_Fixture> pumpApp(WidgetTester tester) async {
    final capability = _Capability();
    addTearDown(capability.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _GuardedApp(capability: capability, navigatorKey: navigatorKey),
    );
    return _Fixture(capability, navigatorKey);
  }

  Future<void> pushConversation(WidgetTester tester, _Fixture fixture) async {
    unawaited(
      fixture.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('conversation route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<bool> pressBack(WidgetTester tester) async {
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    return handled;
  }

  testWidgets(
    'Back during a connected call keeps the retained route and the activity',
    (tester) async {
      final fixture = await pumpApp(tester);
      await pushConversation(tester, fixture);
      fixture.capability.emit(_projection(state: CallState.connected));
      await tester.pump();

      for (var press = 0; press < 3; press++) {
        expect(await pressBack(tester), isTrue);
      }

      expect(fixture.navigatorKey.currentState!.canPop(), isTrue);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      expect(fixture.capability.actions, isEmpty);
    },
  );

  testWidgets('Back at the root route during a call never exits the app', (
    tester,
  ) async {
    final fixture = await pumpApp(tester);
    for (final state in <CallState>[
      CallState.ringing,
      CallState.connected,
      CallState.reconnecting,
    ]) {
      fixture.capability.emit(
        _projection(
          state: state,
          direction: state == CallState.ringing
              ? CallDirection.incoming
              : CallDirection.outgoing,
        ),
      );
      await tester.pump();
      expect(await pressBack(tester), isTrue, reason: '$state');
    }

    expect(platformCalls, isNot(contains('SystemNavigator.pop')));
    expect(fixture.capability.actions, isEmpty);
  });

  testWidgets(
    'a call surface stops the engine routing predictive back to the navigator',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final fixture = await pumpApp(tester);
      await pushConversation(tester, fixture);
      expect(frameworkHandlesBack.last, isTrue);

      fixture.capability.emit(_projection(state: CallState.connected));
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isFalse);

      // A route change under the call must not re-enable framework back.
      unawaited(
        fixture.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const Text('third route')),
        ),
      );
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isFalse);

      fixture.capability.emit(null);
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isTrue);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
    },
  );

  testWidgets('Back works normally once the call surface is gone', (
    tester,
  ) async {
    final fixture = await pumpApp(tester);
    await pushConversation(tester, fixture);
    fixture.capability.emit(_projection(state: CallState.connected));
    await tester.pump();
    expect(await pressBack(tester), isTrue);
    expect(fixture.navigatorKey.currentState!.canPop(), isTrue);

    // Ended call: the terminal notice is informational and must not trap Back.
    fixture.capability.emit(
      _projection(state: CallState.ended, endReason: CallEndReason.localHangup),
    );
    await tester.pump();
    expect(await pressBack(tester), isTrue);
    expect(fixture.navigatorKey.currentState!.canPop(), isFalse);

    fixture.capability.emit(null);
    await tester.pump();
    await pressBack(tester);
    expect(platformCalls, contains('SystemNavigator.pop'));
  });
}

final class _Fixture {
  _Fixture(this.capability, this.navigatorKey);

  final _Capability capability;
  final GlobalKey<NavigatorState> navigatorKey;
}

/// Mirrors production: the guard attaches in the initState of the widget that
/// builds MaterialApp, and the overlay sits in MaterialApp.builder.
class _GuardedApp extends StatefulWidget {
  const _GuardedApp({required this.capability, required this.navigatorKey});

  final _Capability capability;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<_GuardedApp> createState() => _GuardedAppState();
}

class _GuardedAppState extends State<_GuardedApp> {
  final _guard = ForegroundCallBackGuard();

  @override
  void initState() {
    super.initState();
    _guard.attach();
  }

  @override
  void dispose() {
    _guard.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: widget.navigatorKey,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      extensions: const <ThemeExtension<dynamic>>[
        BackgroundReadableColors.dark,
      ],
    ),
    builder: (context, child) => ForegroundCallOverlay(
      capability: widget.capability,
      backGuard: _guard,
      loadContactDisplayName: (_) async => 'Local contact',
      now: () => _now,
      child: child ?? const SizedBox.shrink(),
    ),
    home: const Scaffold(body: Text('home route')),
  );
}

ForegroundCallProjection _projection({
  required CallState state,
  CallDirection direction = CallDirection.outgoing,
  CallEndReason? endReason,
}) => ForegroundCallProjection(
  session: CallSessionSnapshot.active(
    callId: _callId,
    contactPeerId: 'remote-peer',
    direction: direction,
    state: state,
    callerAccountPeerId: direction == CallDirection.incoming
        ? 'remote-peer'
        : 'local-peer',
    callerDeviceId: direction == CallDirection.incoming
        ? 'remote-device'
        : 'local-device',
    startedAt: _now.subtract(const Duration(minutes: 1)),
    ringingAt: state.index >= CallState.ringing.index ? _now : null,
    acceptedAt: state.index >= CallState.accepted.index ? _now : null,
    connectedAt: state == CallState.connected || state == CallState.reconnecting
        ? _now.subtract(const Duration(seconds: 30))
        : null,
    endedAt: state == CallState.ended ? _now : null,
    endReason: state == CallState.ended ? endReason : null,
    incomingValidated: direction == CallDirection.incoming,
  ),
  audio: CallAudioControlState.idle,
);

final class _Capability implements ForegroundCallCapability {
  final StreamController<ForegroundCallProjection?> _changes =
      StreamController<ForegroundCallProjection?>.broadcast(sync: true);
  final List<String> actions = <String>[];
  ForegroundCallProjection? _current;

  @override
  ForegroundCallProjection? get current => _current;

  @override
  Stream<ForegroundCallProjection?> get changes => _changes.stream;

  void emit(ForegroundCallProjection? projection) {
    _current = projection;
    _changes.add(projection);
  }

  Future<void> dispose() => _changes.close();

  Future<ForegroundCallActionResult> _record(String name) async {
    actions.add(name);
    return ForegroundCallActionResult.applied;
  }

  @override
  Future<ForegroundCallActionResult> answer(CallId callId) => _record('answer');

  @override
  Future<ForegroundCallActionResult> cancel(CallId callId) => _record('cancel');

  @override
  Future<ForegroundCallActionResult> decline(CallId callId) =>
      _record('decline');

  @override
  Future<ForegroundCallActionResult> end(CallId callId) => _record('end');

  @override
  Future<ForegroundCallActionResult> setMuted(CallId callId, bool muted) =>
      _record('setMuted');

  @override
  Future<ForegroundCallActionResult> setSpeakerEnabled(
    CallId callId,
    bool enabled,
  ) => _record('setSpeakerEnabled');
}
