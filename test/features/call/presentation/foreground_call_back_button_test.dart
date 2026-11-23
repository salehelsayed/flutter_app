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
// call. Back must preserve the call and avoid popping a covered route.

final _callId = CallId.parse('33333333-3333-4333-8333-333333333333');
final _now = DateTime.utc(2026, 9, 24, 21, 15);

void main() {
  late List<String> platformCalls;
  late List<Object?> frameworkHandlesBack;
  late List<String> taskCalls;
  late List<Object?> nativeBackOwner;
  late List<String?> nativeMinimizeCallIds;
  const callTaskChannel = MethodChannel('mknoon/call_task');
  const bound = Duration(seconds: 3);

  setUp(() {
    platformCalls = <String>[];
    frameworkHandlesBack = <Object?>[];
    taskCalls = <String>[];
    nativeBackOwner = <Object?>[];
    nativeMinimizeCallIds = <String?>[];
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
            final arguments = call.arguments as Map;
            nativeBackOwner.add(arguments['owns']);
            nativeMinimizeCallIds.add(arguments['minimizeCallId'] as String?);
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

  Future<void> settle(WidgetTester tester) => tester
      .pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 2),
      )
      .timeout(bound);

  Future<_Fixture> pumpApp(WidgetTester tester) async {
    final capability = _Capability();
    addTearDown(() => capability.dispose().timeout(bound));
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester
        .pumpWidget(
          _GuardedApp(capability: capability, navigatorKey: navigatorKey),
        )
        .timeout(bound);
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
    await settle(tester);
  }

  Future<bool> pressBack(WidgetTester tester) async {
    final handled = await tester.binding.handlePopRoute().timeout(bound);
    await settle(tester);
    return handled;
  }

  Future<Object?> platformCall(
    MethodChannel channel,
    String method, [
    Object? arguments,
  ]) async {
    final codec = channel.codec;
    final reply = Completer<ByteData?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(MethodCall(method, arguments)),
          reply.complete,
        )
        .timeout(bound);
    final data = await reply.future.timeout(bound);
    return data == null ? null : codec.decodeEnvelope(data);
  }

  Future<Object?> backGesture(String method, [Object? arguments]) =>
      platformCall(SystemChannels.backGesture, method, arguments);

  testWidgets(
    'BL65 Back during a connected call minimizes and the bar restores it',
    (tester) async {
      final fixture = await pumpApp(tester);
      await pushConversation(tester, fixture);
      fixture.capability.emit(_projection(state: CallState.connected));
      await settle(tester);

      expect(await pressBack(tester), isTrue);
      final returnBar = find.byKey(const ValueKey('call-return-bar'));
      expect(returnBar, findsOneWidget);
      expect(find.text('conversation route').hitTestable(), findsOneWidget);
      expect(taskCalls, isEmpty);
      expect(fixture.navigatorKey.currentState!.canPop(), isTrue);

      await tester.tap(returnBar).timeout(bound);
      await settle(tester);
      expect(returnBar, findsNothing);
      expect(find.byKey(const ValueKey('call-minimize')), findsOneWidget);
      expect(fixture.navigatorKey.currentState!.canPop(), isTrue);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      expect(fixture.capability.actions, isEmpty);
    },
  );

  testWidgets('BL65 native Back minimizes the matching outgoing call', (
    tester,
  ) async {
    final fixture = await pumpApp(tester);
    await pushConversation(tester, fixture);
    fixture.capability.emit(_projection(state: CallState.ringing));
    await settle(tester);
    final returnBar = find.byKey(const ValueKey('call-return-bar'));
    expect(find.text('Ringing'), findsOneWidget);

    await platformCall(callTaskChannel, 'minimizeCall', 'retired-call');
    await settle(tester);
    expect(returnBar, findsNothing);

    await platformCall(callTaskChannel, 'minimizeCall', _callId.value);
    await settle(tester);
    expect(returnBar, findsOneWidget);
    expect(find.textContaining('Ringing'), findsOneWidget);
    expect(find.text('conversation route').hitTestable(), findsOneWidget);

    fixture.capability.emit(_projection(state: CallState.connected));
    await settle(tester);
    expect(returnBar, findsOneWidget);
    await tester.tap(returnBar).timeout(bound);
    await settle(tester);
    expect(find.byKey(const ValueKey('call-minimize')), findsOneWidget);
    expect(fixture.capability.actions, isEmpty);
    expect(taskCalls, isEmpty);
  });

  testWidgets('BL65 expanded call gives Android a call-scoped Back target', (
    tester,
  ) async {
    final fixture = await pumpApp(tester);
    await pushConversation(tester, fixture);
    expect(nativeBackOwner, isEmpty);

    fixture.capability.emit(_projection(state: CallState.connected));
    await settle(tester);
    expect(nativeBackOwner, <Object?>[true]);
    expect(nativeMinimizeCallIds, <String?>[_callId.value]);

    fixture.capability.emit(_projection(state: CallState.reconnecting));
    await settle(tester);
    expect(nativeBackOwner, <Object?>[true]);

    // The terminal notice is informational: Back returns to Flutter.
    fixture.capability.emit(
      _projection(
        state: CallState.ended,
        endReason: CallEndReason.remoteHangup,
      ),
    );
    await settle(tester);
    expect(nativeBackOwner, <Object?>[true, false]);
    expect(nativeMinimizeCallIds, <String?>[_callId.value, null]);
    expect(taskCalls, isEmpty);
  });

  testWidgets(
    'BL65 a predictive commit at the root minimizes the current call',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final fixture = await pumpApp(tester);
      fixture.capability.emit(_projection(state: CallState.connected));
      await settle(tester);

      final started = await backGesture('startBackGesture', <String, Object?>{
        'touchOffset': <double>[5, 300],
        'progress': 0.0,
        'swipeEdge': 0,
      });
      expect(started, isTrue);
      await backGesture('commitBackGesture');
      await settle(tester);

      expect(find.byKey(const ValueKey('call-return-bar')), findsOneWidget);
      expect(taskCalls, isEmpty);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      expect(fixture.capability.actions, isEmpty);
    },
  );

  testWidgets('Back on the incoming ringing screen backgrounds the live call', (
    tester,
  ) async {
    final fixture = await pumpApp(tester);
    fixture.capability.emit(
      _projection(state: CallState.ringing, direction: CallDirection.incoming),
    );
    await settle(tester);
    expect(find.text('Answer'), findsOneWidget);
    expect(await pressBack(tester), isTrue);
    expect(find.byKey(const ValueKey('call-return-bar')), findsNothing);
    expect(nativeBackOwner, <Object?>[true]);
    expect(nativeMinimizeCallIds, <String?>[null]);
    expect(taskCalls, ['moveToBackground']);
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

  testWidgets(
    'minimized Back pops chat and root Back backgrounds without ending the session',
    (tester) async {
      final fixture = await pumpApp(tester);
      await pushConversation(tester, fixture);
      fixture.capability.emit(_projection(state: CallState.connected));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('call-minimize')));
      await tester.pumpAndSettle();
      expect(nativeBackOwner.last, isFalse);
      expect(await pressBack(tester), isTrue);
      expect(fixture.navigatorKey.currentState!.canPop(), isFalse);
      expect(taskCalls, isEmpty);
      expect(find.byKey(const ValueKey('call-return-bar')), findsOneWidget);
      expect(await pressBack(tester), isTrue);
      expect(taskCalls, ['moveToBackground']);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      expect(fixture.capability.actions, isEmpty);
    },
  );

  testWidgets('a minimized predictive swipe belongs to the navigator', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final fixture = await pumpApp(tester);
    await pushConversation(tester, fixture);
    fixture.capability.emit(_projection(state: CallState.connected));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('call-minimize')));
    await tester.pumpAndSettle();
    await backGesture('startBackGesture', <String, Object?>{
      'touchOffset': <double>[5, 300],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await backGesture('commitBackGesture');
    await tester.pumpAndSettle();
    expect(taskCalls, isEmpty);
    expect(fixture.capability.actions, isEmpty);
  });

  testWidgets('a live predictive gesture cannot dismiss the finished call', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final fixture = await pumpApp(tester);
    fixture.capability.emit(_projection(state: CallState.connected));
    await tester.pump();

    await backGesture('startBackGesture', <String, Object?>{
      'touchOffset': <double>[5, 300],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    fixture.capability.emit(
      _projection(state: CallState.ended, endReason: CallEndReason.localHangup),
    );
    await tester.pump();
    await backGesture('commitBackGesture');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('foreground-call-terminal-notice')),
      findsOneWidget,
    );
    expect(taskCalls, isEmpty);
  });

  testWidgets('Back works normally once the call surface is gone', (
    tester,
  ) async {
    final fixture = await pumpApp(tester);
    await pushConversation(tester, fixture);
    fixture.capability.emit(_projection(state: CallState.connected));
    await tester.pump();
    expect(fixture.navigatorKey.currentState!.canPop(), isTrue);

    fixture.capability.emit(
      _projection(state: CallState.ended, endReason: CallEndReason.localHangup),
    );
    await tester.pump();
    expect(await pressBack(tester), isTrue);
    expect(
      find.byKey(const ValueKey('foreground-call-terminal-notice')),
      findsNothing,
    );
    expect(fixture.navigatorKey.currentState!.canPop(), isTrue);
    expect(await pressBack(tester), isTrue);
    expect(fixture.navigatorKey.currentState!.canPop(), isFalse);

    fixture.capability.emit(null);
    await tester.pump();
    await pressBack(tester);
    expect(platformCalls, contains('SystemNavigator.pop'));
    expect(taskCalls, isEmpty);
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
