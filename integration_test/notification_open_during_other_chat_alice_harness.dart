// Notification-open during other chat — Alice (receiver) harness.
//
// Reproduces a navigation bug:
//
//   Alice opens user-C's chat from Orbit, backgrounds the app. Bob sends
//   Alice a message; the OS shows a notification. Alice taps the
//   notification — the app should route Alice to Bob's conversation
//   (or to the Feed). Today the app stays on user-C's chat.
//
// This harness mounts a minimal MaterialApp with its own navigator and
// exercises the same notification-route helpers
// (routeAppRootLocalNotificationTap, prepareNotificationOpen) that
// production goes through. The _handleNotificationRouteTarget switch is
// replicated to mirror lib/main.dart so the routing decisions are
// identical to production for the conversation case.
//
// Real components used:
//   - real bridge / P2P / relay (so Bob's send actually delivers)
//   - real ChatMessageListener
//   - real FlutterNotificationService (its onNotificationTap callback
//     is the entry point we invoke when Alice "taps" the notification)
//
// Stubbed components:
//   - ConversationWired is replaced with a _ConversationStub that just
//     renders "Conversation peerId=... label=..." with a stable key. The
//     bug under test is in routing/navigation, not in ConversationWired.
//   - User-C is a fake contact pre-seeded in Alice's local DB (no live
//     third device — the user explicitly asked for a 2-simulator test).
//
// Verdict signals (orchestrator reads these):
//   - alice_ready, alice_in_user_c_chat, alice_backgrounded,
//     alice_notification_received, alice_verdict (JSON), alice_done

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'group_multi_device_real_harness.dart';

// ---------------------------------------------------------------------------
// Config from dart-defines
// ---------------------------------------------------------------------------

const _sharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '/tmp',
);
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'notif_open_during_other_chat_alice.db',
);

String _sig(String name) => '$_sharedDir/notifopen_${_runId}_$name';

void _writeSignal(String name, String content) {
  File(_sig(name)).writeAsStringSync(content);
}

void _writeJson(String name, Map<String, dynamic> data) {
  _writeSignal(name, jsonEncode(data));
}

Future<void> _waitForSignal(
  String name, {
  Duration timeout = const Duration(seconds: 300),
}) async {
  final path = _sig(name);
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (File(path).existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Alice(notif-open): timed out waiting for $name');
}

Future<Map<String, dynamic>> _waitForJson(
  String name, {
  Duration timeout = const Duration(seconds: 300),
}) async {
  final path = _sig(name);
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final file = File(path);
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Alice(notif-open): timed out waiting for json: $name');
}

Future<bool> _waitForOnline(
  dynamic service, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (healthFromState(service.currentState) == ConnectionHealth.online) {
      print('[ALICE-NO] Online after ${sw.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

// ---------------------------------------------------------------------------
// Recording NotificationService — self-contained.
//
// We deliberately do NOT wrap FlutterNotificationService here. That
// implementation calls into the iOS notification permission API during
// `initialize()`, which on a fresh install pops a system dialog the test
// can't dismiss and hangs the harness. Since the bug under test is a
// navigation routing bug — not actual OS-level notification delivery —
// we just need the chat listener to "show" a notification (so we know
// the trigger fired) and to expose `onNotificationTap` so the harness
// can simulate a tap. No platform channels needed.
// ---------------------------------------------------------------------------

class _RecordingNotificationService implements NotificationService {
  final List<_RecordedShow> shown = <_RecordedShow>[];

  /// Test seam: when set, `consumeInitialPayload()` returns this once,
  /// then null on subsequent calls. Mirrors how
  /// `FlutterLocalNotificationsPlugin.getNotificationAppLaunchDetails()`
  /// returns the launching-notification's payload exactly once on cold
  /// start.
  String? pendingInitialPayload;

  @override
  void Function(String payload)? onNotificationTap;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
  }) async {
    shown.add(
      _RecordedShow(
        contactPeerId: contactPeerId,
        senderUsername: senderUsername,
        messageText: messageText,
        payload: payload,
        at: DateTime.now(),
      ),
    );
    print(
      '[ALICE-NO-REC] showMessageNotification contactPeerId=$contactPeerId payload=$payload shown.length=${shown.length}',
    );
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {}

  @override
  Future<String?> consumeInitialPayload() async {
    final p = pendingInitialPayload;
    pendingInitialPayload = null;
    return p;
  }

  @override
  Future<void> clearDeliveredNotifications() async {}

  @override
  void dispose() {}
}

class _RecordedShow {
  final String contactPeerId;
  final String senderUsername;
  final String messageText;
  final String? payload;
  final DateTime at;
  _RecordedShow({
    required this.contactPeerId,
    required this.senderUsername,
    required this.messageText,
    required this.payload,
    required this.at,
  });
}

// ---------------------------------------------------------------------------
// Navigator-backed test app + dispatch wiring.
//
// Goals (widened scope per the run-#5 finding that the simple-stub
// version did not reproduce the bug):
//   1. Use the production `buildConversationSlideUpRoute` for conversation
//      pushes — same custom slide-up transition main.dart uses.
//   2. Mount the real `ConversationWired` inside each pushed route — same
//      lifecycle, same chatMessageStream subscription, same conversation
//      tracker behaviour as production.
//
// Each ConversationWired is wrapped in a `_LabeledConversationHost` so the
// test can identify the on-stage conversation by `find.byKey` (the wrap
// has a stable ValueKey; ConversationWired itself does not).
// ---------------------------------------------------------------------------

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

/// Captures every navigator transition with a millisecond timestamp so the
/// verdict can describe *exactly* what the navigator did. The buggy
/// `popUntil(()=>true)` counter that was used previously always reported 1
/// regardless of stack depth — this observer replaces it with a real log.
class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
  final DateTime _t0 = DateTime.now();

  void _record(String op, Route<dynamic>? route, Route<dynamic>? prev) {
    final dt = DateTime.now().difference(_t0).inMilliseconds;
    events.add({
      'op': op,
      't+ms': dt,
      'route': route?.settings.name ?? '<unnamed>',
      'previous': prev?.settings.name ?? '<unnamed>',
    });
    print('[ALICE-NO-NAV] +${dt}ms $op route=${route?.settings.name} prev=${prev?.settings.name}');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('push', route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('pop', route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _record('replace', newRoute, oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('remove', route, previousRoute);
  }
}

final _RecordingNavigatorObserver _navObserver = _RecordingNavigatorObserver();

class _HomeFeedStub extends StatelessWidget {
  const _HomeFeedStub();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: ValueKey('alice-home-feed'),
      body: Center(child: Text('Feed (Alice)')),
    );
  }
}

class _LabeledConversationHost extends StatelessWidget {
  const _LabeledConversationHost({
    required this.label,
    required this.contact,
    required this.deps,
  });

  final String label;
  final ContactModel contact;
  final _AliceConversationDeps deps;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('alice-conversation-$label'),
      child: ConversationWired(
        contact: contact,
        identityRepo: deps.identityRepo,
        messageRepo: deps.messageRepo,
        chatMessageListener: deps.chatListener,
        p2pService: deps.p2pService,
        bridge: deps.bridge,
        contactRepo: deps.contactRepo,
        conversationTracker: deps.conversationTracker,
      ),
    );
  }
}

class _AliceConversationDeps {
  _AliceConversationDeps({
    required this.identityRepo,
    required this.messageRepo,
    required this.chatListener,
    required this.p2pService,
    required this.bridge,
    required this.contactRepo,
    required this.conversationTracker,
  });

  final IdentityRepository identityRepo;
  final MessageRepository messageRepo;
  final ChatMessageListener chatListener;
  final P2PService p2pService;
  final Bridge? bridge;
  final ContactRepository? contactRepo;
  final ActiveConversationTracker? conversationTracker;
}

class _AliceHarnessApp extends StatelessWidget {
  const _AliceHarnessApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [_navObserver],
      // ConversationWired uses AppLocalizations for strings; without
      // these delegates it throws on first build.
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const _HomeFeedStub(),
    );
  }
}

// ---------------------------------------------------------------------------
// Replicated route-target dispatch.
//
// Mirrors `_openConversationForContact` in lib/main.dart: looks up the
// contact via the contact repo, then fire-and-forget pushes a
// `buildConversationSlideUpRoute` wrapping `ConversationWired`. We
// preserve every step main.dart performs for the conversation kind.
// ---------------------------------------------------------------------------

class _PeerToLabel {
  _PeerToLabel({required this.userBPeerId, required this.userCPeerId});

  final String userBPeerId;
  final String userCPeerId;

  String labelFor(String peerId) {
    if (peerId == userBPeerId) return 'user-b';
    if (peerId == userCPeerId) return 'user-c';
    return 'unknown';
  }
}

Future<void> _handleNotificationRouteTarget({
  required NotificationRouteTarget routeTarget,
  required _PeerToLabel labels,
  required _AliceConversationDeps deps,
  required List<String> trace,
}) async {
  final navigator = _navigatorKey.currentState;
  if (navigator == null) {
    trace.add('navigator-null');
    return;
  }
  switch (routeTarget.kind) {
    case NotificationRouteTargetKind.conversation:
      final peerId = routeTarget.peerId!;
      final label = labels.labelFor(peerId);
      // Mirrors lib/main.dart's `_openConversationForContact`: looks up
      // the contact, then pushes the slide-up route. If the contact is
      // missing, production silently returns — replicated here.
      final contact = await deps.contactRepo?.getContact(peerId);
      if (contact == null) {
        trace.add('push-conversation:$label:contact-missing');
        return;
      }
      trace.add('push-conversation:$label');
      unawaited(
        navigator.push(
          buildConversationSlideUpRoute<void>(
            settings: RouteSettings(name: 'conversation:$label'),
            builder: (_) => _LabeledConversationHost(
              label: label,
              contact: contact,
              deps: deps,
            ),
          ),
        ),
      );
      return;
    case NotificationRouteTargetKind.contactRequest:
    case NotificationRouteTargetKind.intros:
    case NotificationRouteTargetKind.group:
    case NotificationRouteTargetKind.post:
    case NotificationRouteTargetKind.postComment:
      trace.add('non-conversation-target:${routeTarget.kind}');
      return;
  }
}

Future<void> _prepareNotificationRouteTarget(
  NotificationRouteTarget routeTarget, {
  required Future<void> Function() drainOfflineInbox,
  required List<String> trace,
}) async {
  trace.add('prepare:${routeTarget.toPayload()}');
  final result = await prepareNotificationOpen(
    routeTarget: routeTarget,
    drainOfflineInbox: drainOfflineInbox,
    drainGroupOfflineInboxForGroup: (_) async {},
  );
  if (!result.ok) {
    trace.add('prepare-error:${result.error}');
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  testWidgets('Alice(notif-open during other chat) — repro', (tester) async {
    print('\n${'═' * 60}');
    print('  ALICE (NOTIF-OPEN DURING OTHER CHAT) — REPRO');
    print('${'═' * 60}\n');

    // ── Mount the harness app ─────────────────────────────────────────
    await tester.pumpWidget(const _AliceHarnessApp());
    await tester.pump();

    // ── Stack ─────────────────────────────────────────────────────────
    final stack = await setupGroupMultiDeviceStack(
      dbName: _dbName,
      username: 'AliceNotifOpen',
      cliPeerFixture: null,
    );
    await _waitForOnline(stack.p2pService);

    // 1:1 message repository wired against the stack DB.
    final messageRepo = MessageRepositoryImpl(
      dbInsertMessage: (row) => dbInsertMessage(stack.db, row),
      dbLoadMessagesForContact: (p) => dbLoadMessagesForContact(stack.db, p),
      dbLoadLatestMessageForContact: (p) =>
          dbLoadLatestMessageForContact(stack.db, p),
      dbUpdateMessageStatus: (id, s) => dbUpdateMessageStatus(stack.db, id, s),
      dbLoadMessage: (id) => dbLoadMessage(stack.db, id),
      dbCountMessagesForContact: (p) => dbCountMessagesForContact(stack.db, p),
      dbMarkConversationAsRead: (p) => dbMarkConversationAsRead(stack.db, p),
      dbCountUnreadForContact: (p) => dbCountUnreadForContact(stack.db, p),
      dbCountTotalUnread: () => dbCountTotalUnread(stack.db),
      dbCountTotalUnreadExcludingArchived: () =>
          dbCountTotalUnreadExcludingArchived(stack.db),
      dbDeleteMessagesForContact: (p) => dbDeleteMessagesForContact(stack.db, p),
      dbDeleteMessage: (id) => dbDeleteMessage(stack.db, id),
      dbLoadMessagesPage: (p, {limit = 50, beforeTimestamp}) =>
          dbLoadMessagesPage(
            stack.db,
            p,
            limit: limit,
            beforeTimestamp: beforeTimestamp,
          ),
      dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(stack.db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
          dbLoadUnackedOutgoingMessages(
            stack.db,
            olderThan: olderThan,
            limit: limit,
          ),
      dbLoadConversationThreadSummaries: (ids) =>
          dbLoadConversationThreadSummaries(stack.db, ids),
      dbRecoverStuckSendingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbRecoverStuckSendingMessages(
                stack.db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbUpdateWireEnvelope: (id, we) => dbUpdateWireEnvelope(stack.db, id, we),
      dbLoadStuckSendingOutgoingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbLoadStuckSendingOutgoingMessages(
                stack.db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbLoadSendingOutgoingMessages: () =>
          dbLoadSendingOutgoingMessages(stack.db),
      dbConditionalTransitionStatus:
          (id, {required fromStatus, required toStatus}) =>
              dbConditionalTransitionStatus(
                stack.db,
                id,
                fromStatus: fromStatus,
                toStatus: toStatus,
              ),
    );

    // ── Recording notification service + tap-binding glue ─────────────
    final recording = _RecordingNotificationService();
    await recording.initialize();
    final NotificationService notificationService = recording;

    final chatConversationTracker = ActiveConversationTracker();
    AppLifecycleState currentLifecycle = AppLifecycleState.resumed;

    final trace = <String>[];

    // ── Real ChatMessageListener wired to the recording notification svc ──
    final chatListener = ChatMessageListener(
      chatMessageStream: stack.p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: stack.contactRepo,
      bridge: stack.bridge,
      getOwnMlKemSecretKey: () async => stack.identity.mlKemSecretKey,
      notificationService: notificationService,
      conversationTracker: chatConversationTracker,
      getAppLifecycleState: () => currentLifecycle,
    );
    chatListener.start();

    // Bundle the deps the dispatcher and the user-C push both need.
    final convDeps = _AliceConversationDeps(
      identityRepo: stack.identityRepo,
      messageRepo: messageRepo,
      chatListener: chatListener,
      p2pService: stack.p2pService,
      bridge: stack.bridge,
      contactRepo: stack.contactRepo,
      conversationTracker: chatConversationTracker,
    );

    // Mirrors main.dart's `_setupNotificationTapHandler`. When
    // FlutterLocalNotifications fires a tap, this is invoked with the
    // payload we set on the notification.
    notificationService.onNotificationTap = (payload) {
      print('[ALICE-NO] onNotificationTap payload=$payload');
      trace.add('local-tap:$payload');
      // Defer routing to a microtask so the lifecycle state has time to
      // settle (matches production's resume → tap ordering).
      Future<void>.microtask(() async {
        await routeAppRootLocalNotificationTap(
          payload: payload,
          onBeforeOpen: notificationService.clearDeliveredNotifications,
          onBeforeRouteTarget: (rt) => _prepareNotificationRouteTarget(
            rt,
            drainOfflineInbox: stack.p2pService.drainOfflineInbox,
            trace: trace,
          ),
          onRouteTarget: (rt) => _handleNotificationRouteTarget(
            routeTarget: rt,
            labels: _placeholderLabels,
            deps: convDeps,
            trace: trace,
          ),
        );
      });
    };

    // ── Identity exchange ─────────────────────────────────────────────
    _writeJson('alice_identity.json', {
      'peerId': stack.identity.peerId,
      'publicKey': stack.identity.publicKey,
      'mlKemPublicKey': stack.identity.mlKemPublicKey,
    });
    _writeSignal('alice_ready', 'ok');
    print('[ALICE-NO] Ready — waiting for Bob identity...');

    final bobFixture = await _waitForJson('bob_identity.json');
    final bobPeerId = bobFixture['peerId'] as String;
    final bobMlKemPk = bobFixture['mlKemPublicKey'] as String?;

    await stack.contactRepo.addContact(
      ContactModel(
        peerId: bobPeerId,
        publicKey: bobFixture['publicKey'] as String,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'BobNotifOpen',
        signature: 'sig-bob-notif-open',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: bobMlKemPk,
      ),
    );

    // ── Pre-seed user-C as a fake contact + one stored message ────────
    final userCPeerId = '12D3KooWFakeUserC0000000000000000000000000000000';
    final userCContact = ContactModel(
      peerId: userCPeerId,
      publicKey: 'pk-fake-user-c',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'UserCSeeded',
      signature: 'sig-fake-user-c',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: null,
    );
    await stack.contactRepo.addContact(userCContact);

    final userCMessageId = 'seed-user-c-msg-1';
    await messageRepo.saveMessage(
      ConversationMessage(
        id: userCMessageId,
        contactPeerId: userCPeerId,
        senderPeerId: userCPeerId,
        text: 'Old message from user-c',
        timestamp: DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        status: 'read',
        isIncoming: true,
        createdAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
      ),
    );

    // Publish labels so the dispatch helper can resolve them.
    _placeholderLabels = _PeerToLabel(
      userBPeerId: bobPeerId,
      userCPeerId: userCPeerId,
    );

    // ── Step 1: Alice opens user-C's conversation from "Orbit" ────────
    // Uses the production `buildConversationSlideUpRoute` + real
    // `ConversationWired` so the harness exercises the same widget tree
    // the production app builds for an open conversation.
    print('[ALICE-NO] Alice opens user-C conversation');
    chatConversationTracker.setActive(userCPeerId);
    _navigatorKey.currentState!.push(
      buildConversationSlideUpRoute<void>(
        settings: const RouteSettings(name: 'conversation:user-c'),
        builder: (_) => _LabeledConversationHost(
          label: 'user-c',
          contact: userCContact,
          deps: convDeps,
        ),
      ),
    );
    // Pump enough cycles for the slide-up animation (420ms) plus
    // ConversationWired's initial load to settle.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }

    // Sanity check: user-C's chat is visible.
    expect(
      find.byKey(const ValueKey('alice-conversation-user-c')),
      findsOneWidget,
      reason: 'user-c chat should be visible after explicit push',
    );
    _writeSignal('alice_in_user_c_chat', 'ok');

    // ── Step 2: "Background" the app ───────────────────────────────────
    //
    // We update the *listener-observable* lifecycle state (the
    // `currentLifecycle` capture the chat listener reads) but DO NOT
    // call `WidgetsBinding.handleAppLifecycleStateChanged(paused)` —
    // doing so deadlocks `tester.pump()` because the binding stops
    // producing frames in the paused state. Concretely: an earlier run
    // hung Alice for 5 minutes after the first paused-pump.
    //
    // For the routing bug under test, the observable lifecycle is what
    // the suppress gate reads, so this faithfully covers the
    // notification path. The real binding state stays `resumed`.
    print('[ALICE-NO] Backgrounding the app (logical lifecycle only)');
    Future<void> setLogicalLifecycle(AppLifecycleState state) async {
      currentLifecycle = state;
      trace.add('lifecycle:${state.name}');
      // Let pending streams flush.
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    }

    await setLogicalLifecycle(AppLifecycleState.inactive);
    await setLogicalLifecycle(AppLifecycleState.hidden);
    await setLogicalLifecycle(AppLifecycleState.paused);
    _writeSignal('alice_backgrounded', 'ok');

    // ── Step 3: Wait for Bob's send. The chat listener will fire
    //           `showMessageNotification` on the recording wrapper as it
    //           processes Bob's incoming P2P message. We poll the
    //           recording list with pure Future.delayed (no tester.pump)
    //           — matching the pattern used by
    //           notification_sound_smoke_bob_harness — because
    //           tester.pump in fullyLive mode can starve the platform
    //           event loop that delivers stream events. ────
    final preSendShown = recording.shown.length;
    print('[ALICE-NO] Awaiting Bob send (notification gate paused, off-conv)');
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    bool received = false;
    while (DateTime.now().isBefore(deadline)) {
      if (recording.shown.length > preSendShown) {
        final last = recording.shown.last;
        if (last.contactPeerId == bobPeerId) {
          print(
            '[ALICE-NO] Notification fired for Bob: payload=${last.payload}',
          );
          _writeSignal('alice_notification_received', 'ok');
          received = true;
          break;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!received) {
      throw TimeoutException(
        'Alice never received a notification for Bob\'s message',
      );
    }
    final bobNotification = recording.shown.last;

    // ── Step 4: Simulate Alice tapping the notification ───────────────
    //
    // Mirror the real iOS resume sequence (paused → hidden → inactive →
    // resumed) on the listener-observable lifecycle BEFORE firing the
    // tap. flutter_local_notifications delivers the tap via the platform
    // channel just after the engine resumes, so the resume must run first.
    print('[ALICE-NO] Resuming app before tap');
    await setLogicalLifecycle(AppLifecycleState.hidden);
    await setLogicalLifecycle(AppLifecycleState.inactive);
    await setLogicalLifecycle(AppLifecycleState.resumed);

    print('[ALICE-NO] Simulating tap on Bob notification');

    // FlutterNotificationService resolves null payloads to contactPeerId
    // before handing the notification to the OS, so on tap the OS hands
    // back contactPeerId (= Bob's peer id) to onNotificationTap. Mirror
    // that fallback here so the simulated tap matches production.
    final tapPayload = (bobNotification.payload?.isNotEmpty ?? false)
        ? bobNotification.payload!
        : bobNotification.contactPeerId;
    if (tapPayload.isEmpty) {
      throw StateError(
        'Notification payload was empty; cannot simulate tap',
      );
    }
    notificationService.onNotificationTap?.call(tapPayload);

    // Pump aggressively over ~5s so:
    //  (a) the microtask scheduled by onNotificationTap can run,
    //  (b) drainOfflineInbox's platform-channel calls can land,
    //  (c) the navigator.push and any route transition fully settle
    //      into the widget tree before find.byKey runs.
    //
    // Mixing real-time delays with explicit pumps avoids both failure
    // modes we hit earlier: Future.delayed alone left the widget tree
    // stale; tester.pump alone starved the platform isolate.
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }

    // ── Step 5: Inspect resulting navigation ───────────────────────────
    // Expectation: top route shows Bob's conversation.
    // Bug today: top route still shows user-C's conversation.
    //
    // We compute three orthogonal signals so the verdict captures both
    // “onstage widget tree” and “navigator route stack” independently:
    //   * find.byKey with skipOffstage:true → onstage check
    //   * find.byKey with skipOffstage:false → presence-anywhere check
    //   * navigator-observer event log → ground truth for push/pop ops
    final bobOnstage =
        find.byKey(const ValueKey('alice-conversation-user-b')).evaluate().isNotEmpty;
    final userCOnstage =
        find.byKey(const ValueKey('alice-conversation-user-c')).evaluate().isNotEmpty;
    final bobInTree = find
        .byKey(
          const ValueKey('alice-conversation-user-b'),
          skipOffstage: false,
        )
        .evaluate()
        .isNotEmpty;
    final userCInTree = find
        .byKey(
          const ValueKey('alice-conversation-user-c'),
          skipOffstage: false,
        )
        .evaluate()
        .isNotEmpty;

    // Capture the topmost route non-destructively. `popUntil(()=>true)`
    // visits exactly one route (the top) and never pops, since the
    // predicate stops popping the moment it returns true. We must NOT
    // use a `false`-returning predicate here — that pops every route.
    //
    // The full navigator stack history is reconstructed from the
    // navigator observer's event log instead.
    Route<dynamic>? topRoute;
    _navigatorKey.currentState?.popUntil((route) {
      topRoute ??= route;
      return true;
    });
    final navEvents = _navObserver.events
        .map((e) => '${e['op']}@${e['t+ms']}ms:${e['route']}')
        .toList();

    final verdict = <String, dynamic>{
      'bobOnstage': bobOnstage,
      'userCOnstage': userCOnstage,
      'bobInTree': bobInTree,
      'userCInTree': userCInTree,
      'topRouteName': topRoute?.settings.name,
      'navEvents': navEvents,
      'shownCount': recording.shown.length,
      'notificationPayload': tapPayload,
      'bobPeerId': bobPeerId,
      'userCPeerId': userCPeerId,
      'trace': trace,
      // Legacy aliases so existing analyzers keep working.
      'bobChatVisible': bobOnstage,
      'userCChatVisible': userCOnstage,
      // The "programmatic pass" condition encodes the EXPECTED behaviour.
      // Today this fails because the app stays on user-C's chat. The fix
      // should make this true.
      'programmaticPass': bobOnstage,
      'reproducedBug': userCOnstage && !bobOnstage,
    };
    _writeJson('alice_verdict', verdict);
    print('[ALICE-NO] Verdict: $verdict');

    // We deliberately DO NOT throw here. The whole point of this harness
    // is to produce a verdict the orchestrator can read; an early
    // expect-failure would short-circuit teardown and leak processes.
    // The orchestrator is responsible for enforcing the pass/fail gate.

    // ── Cold-start variant ────────────────────────────────────────────
    //
    // The warm-tap phase above proved push lands correctly when the user
    // was actively in user-c's chat. The user's bug report could *also*
    // describe a cold start: iOS killed the app while suspended, Bob's
    // notification arrived, the user tapped to launch.
    //
    // Cold-start production path:
    //   - main() runs → MyApp builds → StartupRouter pushReplaces Feed
    //   - `_handleInitialLocalNotificationLaunch` runs (after services ready)
    //   - reads `consumeInitialPayload()` → Bob's peerId
    //   - calls `routeAppRootInitialLocalNotificationOpen` →
    //     `_handleNotificationRouteTarget` → push Bob's chat
    //
    // To simulate: pop everything to home, prime
    // `recording.pendingInitialPayload` with Bob's payload, invoke
    // `routeAppRootInitialLocalNotificationOpen`, and capture a separate
    // verdict.
    print('\n[ALICE-NO] ──── Cold-start variant ────');
    final navigator = _navigatorKey.currentState!;
    navigator.popUntil((route) => route.isFirst);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
    final navEventsBeforeColdStart = _navObserver.events.length;

    recording.pendingInitialPayload = bobPeerId;
    print('[ALICE-NO] coldstart: consumeInitialPayload primed with $bobPeerId');

    await routeAppRootInitialLocalNotificationOpen(
      consumeInitialPayload: notificationService.consumeInitialPayload,
      onBeforeOpen: notificationService.clearDeliveredNotifications,
      onBeforeRouteTarget: (rt) => _prepareNotificationRouteTarget(
        rt,
        drainOfflineInbox: stack.p2pService.drainOfflineInbox,
        trace: trace,
      ),
      onRouteTarget: (rt) => _handleNotificationRouteTarget(
        routeTarget: rt,
        labels: _placeholderLabels,
        deps: convDeps,
        trace: trace,
      ),
    );

    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }

    final coldStartBobOnstage = find
        .byKey(const ValueKey('alice-conversation-user-b'))
        .evaluate()
        .isNotEmpty;
    final coldStartUserCOnstage = find
        .byKey(const ValueKey('alice-conversation-user-c'))
        .evaluate()
        .isNotEmpty;

    Route<dynamic>? coldStartTopRoute;
    _navigatorKey.currentState?.popUntil((route) {
      coldStartTopRoute ??= route;
      return true;
    });

    final coldStartNavEvents = _navObserver.events
        .sublist(navEventsBeforeColdStart)
        .map((e) => '${e['op']}@${e['t+ms']}ms:${e['route']}')
        .toList();

    final coldStartVerdict = <String, dynamic>{
      'phase': 'cold-start',
      'bobOnstage': coldStartBobOnstage,
      'userCOnstage': coldStartUserCOnstage,
      'topRouteName': coldStartTopRoute?.settings.name,
      'navEvents': coldStartNavEvents,
      'programmaticPass': coldStartBobOnstage,
      'reproducedBug': !coldStartBobOnstage,
    };
    _writeJson('alice_cold_start_verdict', coldStartVerdict);
    print('[ALICE-NO] Cold-start verdict: $coldStartVerdict');

    // ── Done ──────────────────────────────────────────────────────────
    await _waitForSignal('all_done');
    chatListener.dispose();
    notificationService.dispose();
    await stack.teardown();
    _writeSignal('alice_done', 'ok');
  }, timeout: const Timeout(Duration(minutes: 15)));
}

// Initialised once we know Bob's peerId. Read by `_handleNotificationRouteTarget`.
late _PeerToLabel _placeholderLabels;
