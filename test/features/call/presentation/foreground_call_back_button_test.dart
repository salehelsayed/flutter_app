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
//
// Beta 2026-09-25 (F4, second round): the first fix told the engine that the
// framework does not handle Back while a call shows. On Android 13+ that
// unregisters Flutter's OnBackInvokedCallback, so the FIRST Back closed the
// task (WindowManager `type = CLOSE` at 19:34:43.850) and teardown ended the
// call. Back must stay with Flutter and send the app to the background.

final _callId = CallId.parse('33333333-3333-4333-8333-333333333333');
final _now = DateTime.utc(2026, 9, 24, 21, 15);

void main() {
  late List<String> platformCalls;
  late List<Object?> frameworkHandlesBack;
  late List<String> taskCalls;
  late List<Object?> nativeBackOwner;
  const callTaskChannel = MethodChannel('mknoon/call_task');

  setUp(() {
    platformCalls = <String>[];
    frameworkHandlesBack = <Object?>[];
    taskCalls = <String>[];
    nativeBackOwner = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call.method);
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            frameworkHandlesBack.add(call.arguments);
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(callTaskChannel, (call) async {
          if (call.method == 'setCallOwnsBack') {
            nativeBackOwner.add((call.arguments as Map)['owns']);
          } else {
            taskCalls.add(call.method);
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(callTaskChannel, null);
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

  Future<Object?> backGesture(String method, [Object? arguments]) async {
    final codec = SystemChannels.backGesture.codec;
    final reply = Completer<ByteData?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SystemChannels.backGesture.name,
          codec.encodeMethodCall(MethodCall(method, arguments)),
          reply.complete,
        );
    final data = await reply.future;
    return data == null ? null : codec.decodeEnvelope(data);
  }

  testWidgets(
    'Back during a connected call sends the app to the background and keeps '
    'the retained route',
    (tester) async {
      final fixture = await pumpApp(tester);
      await pushConversation(tester, fixture);
      fixture.capability.emit(_projection(state: CallState.connected));
      await tester.pump();

      for (var press = 0; press < 3; press++) {
        expect(await pressBack(tester), isTrue);
      }

      expect(taskCalls, <String>[
        'moveToBackground',
        'moveToBackground',
        'moveToBackground',
      ]);
      expect(fixture.navigatorKey.currentState!.canPop(), isTrue);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      expect(fixture.capability.actions, isEmpty);
    },
  );

  testWidgets(
    'a call surface hands Back to Android while it shows, so a predictive '
    'swipe never reaches the hidden routes',
    (tester) async {
      final fixture = await pumpApp(tester);
      await pushConversation(tester, fixture);
      expect(nativeBackOwner, isEmpty);

      // MainActivity then registers an overlay-priority back callback that
      // moves the task to the back. Flutter's page routes never see the
      // swipe, so the conversation route under the call stays.
      fixture.capability.emit(_projection(state: CallState.connected));
      await tester.pumpAndSettle();
      expect(nativeBackOwner, <Object?>[true]);

      fixture.capability.emit(_projection(state: CallState.reconnecting));
      await tester.pumpAndSettle();
      expect(nativeBackOwner, <Object?>[true]);

      // The terminal notice is informational: Back returns to Flutter.
      fixture.capability.emit(
        _projection(
          state: CallState.ended,
          endReason: CallEndReason.remoteHangup,
        ),
      );
      await tester.pumpAndSettle();
      expect(nativeBackOwner, <Object?>[true, false]);
      expect(taskCalls, isEmpty);
    },
  );

  testWidgets(
    'a predictive back swipe that still reaches Flutter during a call sends '
    'the app to the background',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final fixture = await pumpApp(tester);
      fixture.capability.emit(_projection(state: CallState.connected));
      await tester.pumpAndSettle();

      final started = await backGesture('startBackGesture', <String, Object?>{
        'touchOffset': <double>[5, 300],
        'progress': 0.0,
        'swipeEdge': 0,
      });
      expect(started, isTrue);
      await backGesture('commitBackGesture');
      await tester.pumpAndSettle();

      expect(taskCalls, <String>['moveToBackground']);
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

    expect(taskCalls, List<String>.filled(3, 'moveToBackground'));
    expect(platformCalls, isNot(contains('SystemNavigator.pop')));
    expect(fixture.capability.actions, isEmpty);
  });

  testWidgets(
    'a call surface keeps the platform back callback registered, even at the '
    'root route',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final fixture = await pumpApp(tester);
      await tester.pumpAndSettle();
      // At the root route the navigator cannot pop. Android then owns Back.
      expect(frameworkHandlesBack.lastOrNull ?? false, isFalse);

      // FlutterActivity unregisters its OnBackInvokedCallback whenever this
      // is false, and the system Back then closes the task under the call.
      fixture.capability.emit(_projection(state: CallState.connected));
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isTrue);

      // Route changes under the call must not give Back back to the system.
      unawaited(
        fixture.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const Text('third route')),
        ),
      );
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isTrue);
      fixture.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isTrue);

      // The navigator's own answer returns once the call surface hides.
      fixture.capability.emit(null);
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isFalse);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      expect(taskCalls, isEmpty);
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
    // Only the live call surface sends the app to the background.
    expect(taskCalls, <String>['moveToBackground']);
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
