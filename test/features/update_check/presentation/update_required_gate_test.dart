import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_overlay.dart';
import 'package:flutter_app/features/call/presentation/screens/active_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/incoming_call_screen.dart';
import 'package:flutter_app/features/update_check/application/update_check_controller.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/update_store_urls.dart';
import 'package:flutter_app/features/update_check/presentation/update_copy.dart';
import 'package:flutter_app/features/update_check/presentation/update_required_back_guard.dart';
import 'package:flutter_app/features/update_check/presentation/update_required_gate.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_update_check_service.dart';

const _hard = UpdateDecisionHard(
  minBuild: 120,
  reasonCode: UpdateReasonCode.security,
);
const _overlay = ValueKey('update-required-overlay');
const _homeLabel = 'Home private content';

void main() {
  late FakeUpdateCheckService service;
  late UpdateCheckController controller;
  late _FakeCallCapability calls;
  late UpdateRequiredBackGuard guard;
  late List<Uri> launches;
  late GlobalKey<NavigatorState> navigatorKey;
  late FocusNode homeFocus;

  setUp(() {
    service = FakeUpdateCheckService(decisions: [_hard]);
    controller = UpdateCheckController(service: service);
    calls = _FakeCallCapability();
    // Attached before MaterialApp is built, as MyApp.initState does.
    guard = UpdateRequiredBackGuard()..attach();
    launches = <Uri>[];
    navigatorKey = GlobalKey<NavigatorState>();
    homeFocus = FocusNode(debugLabel: 'home field');
  });

  tearDown(() async {
    guard.detach();
    controller.dispose();
    homeFocus.dispose();
    await calls.dispose();
  });

  Widget app({Locale locale = const Locale('en'), String? initialRoute}) =>
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[
            BackgroundReadableColors.dark,
          ],
        ),
        // Same layering as MyApp: the gate wraps the app content inside the
        // call overlay.
        builder: (context, child) => ForegroundCallOverlay(
          capability: calls,
          loadContactDisplayName: (_) async => 'Local contact',
          child: UpdateRequiredGate(
            controller: controller,
            callCapability: calls,
            backGuard: guard,
            launchStore: (url) async {
              launches.add(url);
              return true;
            },
            child: child!,
          ),
        ),
        initialRoute: initialRoute,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => switch (settings.name) {
            '/' => Scaffold(
              body: Column(
                children: <Widget>[
                  Semantics(label: _homeLabel, child: const Text('home')),
                  TextField(focusNode: homeFocus),
                ],
              ),
            ),
            final name? => Scaffold(body: Text('route $name')),
            null => const SizedBox.shrink(),
          },
        ),
      );

  /// Starts without an overlay; the first due resume returns hard.
  void hardOnResume() {
    controller.dispose();
    service = FakeUpdateCheckService(
      decisions: [const UpdateDecisionNone(), _hard],
      due: true,
    );
    controller = UpdateCheckController(service: service);
  }

  Future<void> resume(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    String? initialRoute,
  }) async {
    await tester.pumpWidget(app(locale: locale, initialRoute: initialRoute));
    // The first check runs after the first frame.
    await tester.pumpAndSettle();
  }

  group('AC10 covers every route; no close; Back blocked; store link', () {
    testWidgets('home', (tester) async {
      await pumpApp(tester);

      expect(service.checks, 1);
      expect(find.byKey(_overlay), findsOneWidget);
      expect(find.text('Please update Mknoon'), findsOneWidget);
      expect(find.text('Your version: 118'), findsOneWidget);
      expect(find.text('Needed: 120 or newer'), findsOneWidget);
      expect(find.byType(CloseButton), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(_overlay),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(_overlay),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_overlay),
          matching: find.byType(TextButton),
        ),
        findsNothing,
      );

      await tester.tap(find.text('Update now'));
      await tester.pump();
      expect(launches, [Uri.parse(updateStoreUrlIos)]);
      expect(find.byKey(_overlay), findsOneWidget);
    });

    testWidgets('Android opens the Play page', (tester) async {
      service = FakeUpdateCheckService(
        decisions: [_hard],
        platform: UpdatePlatform.android,
      );
      controller.dispose();
      controller = UpdateCheckController(service: service);
      await pumpApp(tester);

      await tester.tap(find.text('Update now'));
      await tester.pump();
      expect(launches, [
        Uri.parse(
          'https://play.google.com/store/apps/details?id=com.mknoon.app',
        ),
      ]);
    });

    testWidgets('a pushed route, and Back does not pop it', (tester) async {
      hardOnResume();
      await pumpApp(tester);
      expect(find.byKey(_overlay), findsNothing);

      unawaited(navigatorKey.currentState!.pushNamed('/settings'));
      await tester.pumpAndSettle();
      expect(find.text('route /settings'), findsOneWidget);

      await resume(tester);
      expect(find.byKey(_overlay), findsOneWidget);
      expect(guard.blocking, isTrue);

      // System Back (key and predictive swipe) is consumed.
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(find.text('route /settings'), findsOneWidget);
      expect(find.byKey(_overlay), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isTrue);
    });

    testWidgets('a deep-link route opened at launch', (tester) async {
      await pumpApp(tester, initialRoute: '/conversation/peer-1');
      expect(find.text('route /conversation/peer-1'), findsOneWidget);
      expect(find.byKey(_overlay), findsOneWidget);
    });

    testWidgets('a notification route pushed from outside the tree', (
      tester,
    ) async {
      await pumpApp(tester);
      // Notification taps push through the root navigator key.
      unawaited(navigatorKey.currentState!.pushNamed('/notification/peer-2'));
      await tester.pumpAndSettle();
      expect(find.text('route /notification/peer-2'), findsOneWidget);
      expect(find.byKey(_overlay), findsOneWidget);
      // The overlay is the top layer: its button is hit-testable over the
      // route.
      await tester.tap(find.text('Update now'));
      expect(launches, hasLength(1));
    });
  });

  testWidgets('AC11 nothing behind the overlay is in the semantics tree or '
      'reachable by Tab', (tester) async {
    final semantics = tester.ensureSemantics();
    hardOnResume();
    await pumpApp(tester);

    expect(
      tester.semantics.simulatedAccessibilityTraversal().map((n) => n.label),
      contains(contains(_homeLabel)),
    );
    homeFocus.requestFocus();
    await tester.pump();
    expect(homeFocus.hasFocus, isTrue);

    await resume(tester);
    expect(find.byKey(_overlay), findsOneWidget);

    // What a screen reader can reach, in traversal order.
    final reachable = tester.semantics
        .simulatedAccessibilityTraversal()
        .map((node) => node.label)
        .toList();
    expect(reachable.where((label) => label.contains(_homeLabel)), isEmpty);
    expect(reachable, contains('Please update Mknoon'));
    expect(reachable, contains('Update now'));
    expect(homeFocus.hasFocus, isFalse);

    // Tab never reaches anything behind the overlay; it does reach the
    // overlay's one button.
    final behind = find.byType(Navigator);
    var reachedButton = false;
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(homeFocus.hasFocus, isFalse);
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) continue;
      final focusedWidget = find.byWidget(focused.widget);
      expect(
        find.descendant(of: behind, matching: focusedWidget),
        findsNothing,
        reason: 'Tab focus must not reach the routes behind the overlay',
      );
      if (find
          .descendant(
            of: find.byKey(const ValueKey('update-required-button')),
            matching: focusedWidget,
          )
          .evaluate()
          .isNotEmpty) {
        reachedButton = true;
      }
    }
    expect(reachedButton, isTrue);
    semantics.dispose();
  });

  group('AC12 calls', () {
    testWidgets('not shown during an incoming or active call; back after it '
        'ends; the call surface is never covered', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(_overlay), findsOneWidget);

      calls.emit(_projection(CallDirection.incoming, CallState.ringing));
      await tester.pumpAndSettle();
      expect(find.byType(IncomingCallScreen), findsOneWidget);
      expect(find.byKey(_overlay), findsNothing);
      expect(guard.blocking, isFalse);
      // The call surface takes taps.
      expect(find.byType(IncomingCallScreen).hitTestable(), findsOneWidget);

      calls.emit(_projection(CallDirection.incoming, CallState.connected));
      await tester.pumpAndSettle();
      expect(find.byType(ActiveCallScreen), findsOneWidget);
      expect(find.byKey(_overlay), findsNothing);

      calls.emit(_projection(CallDirection.incoming, CallState.ended));
      await tester.pumpAndSettle();
      expect(find.byKey(_overlay), findsOneWidget);
      expect(guard.blocking, isTrue);

      calls.emit(null);
      await tester.pumpAndSettle();
      expect(find.byKey(_overlay), findsOneWidget);
    });

    testWidgets('a call already running at launch keeps the overlay away', (
      tester,
    ) async {
      calls.emit(_projection(CallDirection.outgoing, CallState.ringing));
      await pumpApp(tester);
      expect(controller.value, _hard);
      expect(find.byKey(_overlay), findsNothing);

      calls.emit(_projection(CallDirection.outgoing, CallState.ended));
      await tester.pumpAndSettle();
      expect(find.byKey(_overlay), findsOneWidget);
    });
  });

  testWidgets('AC13 the overlay clears on resume when the recheck returns '
      'none', (tester) async {
    service.queue(_hard);
    service.queue(const UpdateDecisionNone());
    await pumpApp(tester);
    expect(find.byKey(_overlay), findsOneWidget);

    // Still hard: rechecked although no check is due.
    await resume(tester);
    expect(service.checks, 2);
    expect(find.byKey(_overlay), findsOneWidget);

    await resume(tester);
    expect(service.checks, 3);
    expect(find.byKey(_overlay), findsNothing);
    expect(guard.blocking, isFalse);
    expect(find.text('home'), findsOneWidget);
    // Back reaches the navigator again.
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  group('AC14 EN, DE and AR', () {
    testWidgets('Arabic renders right to left', (tester) async {
      await pumpApp(tester, locale: const Locale('ar'));
      final l10n = lookupAppLocalizations(const Locale('ar'));
      final title = find.text(l10n.update_required_title);
      expect(title, findsOneWidget);
      expect(Directionality.of(tester.element(title)), TextDirection.rtl);
      expect(find.text(l10n.update_required_body_security), findsOneWidget);
      expect(find.text(l10n.update_required_button), findsOneWidget);
      expect(find.text('إصدارك الحالي: 118'), findsOneWidget);
      expect(find.text('الإصدار المطلوب: 120 أو أحدث'), findsOneWidget);
    });

    testWidgets('German renders left to right', (tester) async {
      await pumpApp(tester, locale: const Locale('de'));
      final title = find.text('Bitte aktualisiere Mknoon');
      expect(title, findsOneWidget);
      expect(Directionality.of(tester.element(title)), TextDirection.ltr);
    });

    test('every reason code has its own text in every language', () {
      for (final locale in const [Locale('en'), Locale('de'), Locale('ar')]) {
        final l10n = lookupAppLocalizations(locale);
        final hard = {
          for (final code in UpdateReasonCode.values)
            updateRequiredBody(l10n, code),
        };
        final soft = {
          for (final code in UpdateReasonCode.values)
            updateAvailableMessage(l10n, code),
        };
        expect(hard, hasLength(UpdateReasonCode.values.length));
        expect(soft, hasLength(UpdateReasonCode.values.length));
        for (final text in [
          ...hard,
          ...soft,
          l10n.update_required_title,
          l10n.update_required_button,
          l10n.update_required_installed_build('1'),
          l10n.update_required_minimum_build('2'),
          l10n.update_available_action,
          l10n.update_available_dismiss,
        ]) {
          expect(text.trim(), isNotEmpty, reason: '$locale');
        }
      }
      // An unknown wire code falls back to the general text.
      final en = lookupAppLocalizations(const Locale('en'));
      expect(
        updateRequiredBody(en, UpdateReasonCode.parse('future_code')),
        en.update_required_body_general,
      );
    });

    test('EN, DE and AR carry the owner-approved final copy (AC16)', () {
      for (final lang in ['en', 'de', 'ar']) {
        final arb = File('lib/l10n/app_$lang.arb').readAsStringSync();
        for (final key in _se41Keys) {
          final at = arb.indexOf('"@$key"');
          expect(at, isNonNegative, reason: '$lang $key');
          final end = arb.indexOf('}', at);
          final block = arb.substring(at, end);
          expect(
            block,
            contains('SE-41 final copy, owner-approved 2026-10-12 (Rawi)'),
            reason: '$lang $key',
          );
          expect(block, isNot(contains('TODO')), reason: '$lang $key');
        }
      }
    });
  });

  test('MyApp mounts the gate inside the call overlay (source check)', () {
    final root = File('lib/app/application_root.dart').readAsStringSync();
    final builder = root.substring(
      root.indexOf('builder: (context, child) {'),
      root.indexOf('localizationsDelegates: AppLocalizations'),
    );
    final gate = builder.indexOf('UpdateRequiredGate(');
    final call = builder.indexOf('ForegroundCallOverlay(');
    expect(gate, isNonNegative);
    expect(call, greaterThan(gate));
    expect(builder, contains('child: appChild,'));
    expect(builder, contains('child: updateGate,'));
    final initState = root.substring(
      root.indexOf('_foregroundCallBackGuard.attach();'),
    );
    expect(
      initState.indexOf('_updateRequiredBackGuard.attach();'),
      lessThan(200),
      reason: 'the update Back guard attaches in initState, before MaterialApp',
    );
  });
}

const _se41Keys = <String>[
  'update_required_title',
  'update_required_body_general',
  'update_required_body_security',
  'update_required_body_protocol_change',
  'update_required_body_critical_fix',
  'update_required_installed_build',
  'update_required_minimum_build',
  'update_required_button',
  'update_available_general',
  'update_available_security',
  'update_available_protocol_change',
  'update_available_critical_fix',
  'update_available_action',
  'update_available_dismiss',
];

ForegroundCallProjection _projection(CallDirection direction, CallState state) {
  final now = DateTime.utc(2026, 10, 11, 12);
  const peerId = 'peer-call';
  return ForegroundCallProjection(
    session: CallSessionSnapshot.active(
      callId: CallId.parse('44444444-4444-4444-8444-444444444444'),
      contactPeerId: peerId,
      direction: direction,
      state: state,
      callerAccountPeerId: direction == CallDirection.incoming
          ? peerId
          : 'local-peer',
      callerDeviceId: direction == CallDirection.incoming
          ? 'remote-device'
          : 'local-device',
      startedAt: now.subtract(const Duration(minutes: 1)),
      ringingAt: state.index >= CallState.ringing.index ? now : null,
      acceptedAt: state.index >= CallState.accepted.index ? now : null,
      connectedAt: state == CallState.connected
          ? now.subtract(const Duration(seconds: 30))
          : null,
      endedAt: state == CallState.ended ? now : null,
      endReason: state == CallState.ended ? CallEndReason.localHangup : null,
      incomingValidated: true,
    ),
    audio: CallAudioControlState.idle,
  );
}

class _FakeCallCapability implements ForegroundCallCapability {
  final StreamController<ForegroundCallProjection?> _changes =
      StreamController<ForegroundCallProjection?>.broadcast(sync: true);
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

  @override
  Future<ForegroundCallActionResult> answer(CallId callId) async =>
      ForegroundCallActionResult.applied;

  @override
  Future<ForegroundCallActionResult> cancel(CallId callId) async =>
      ForegroundCallActionResult.applied;

  @override
  Future<ForegroundCallActionResult> decline(CallId callId) async =>
      ForegroundCallActionResult.applied;

  @override
  Future<ForegroundCallActionResult> end(CallId callId) async =>
      ForegroundCallActionResult.applied;

  @override
  Future<ForegroundCallActionResult> setMuted(
    CallId callId,
    bool muted,
  ) async => ForegroundCallActionResult.applied;

  @override
  Future<ForegroundCallActionResult> setSpeakerEnabled(
    CallId callId,
    bool enabled,
  ) async => ForegroundCallActionResult.applied;
}
