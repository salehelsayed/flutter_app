/// Notification Sound Smoke — Bob Harness (Receiver)
///
/// Receives a message from Alice in each of four scenarios (S1: 1:1 direct,
/// S2: group discussion, S3: group announcement, S4: suppression control) and
/// verifies that the REAL FlutterNotificationService path fires with sound
/// config intact. Captures FLOW events and writes per-scenario verdict files
/// that the orchestrator reads to produce the final pass/fail summary.
///
/// Stays on a neutral staging screen so the `isViewingConversation` gate does
/// not suppress S1–S3. For S4 it programmatically activates the conversation
/// tracker to verify the suppression gate works.
///
/// Launch via orchestrator:
///   dart run integration_test/scripts/run_notification_sound_smoke.dart -d <alice>,<bob>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

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
  defaultValue: 'notif_sound_smoke_bob.db',
);
const _nonInteractive = bool.fromEnvironment(
  'NOTIFICATION_SOUND_NON_INTERACTIVE',
);

String _sig(String name) => '$_sharedDir/nsmoke_${_runId}_$name';

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
  throw TimeoutException('Bob(notif): timed out waiting for $name');
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
  throw TimeoutException('Bob(notif): timed out waiting for json: $name');
}

Future<bool> _waitForOnline(
  dynamic service, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (healthFromState(service.currentState) == ConnectionHealth.online) {
      print('[BOB-N] Online after ${sw.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

// ---------------------------------------------------------------------------
// Recording NotificationService
//
// Wraps FlutterNotificationService and records every showMessageNotification
// call directly (no dependence on debugPrint capture, which the
// integration-test binding clobbers). We infer NOTIFICATION_SUPPRESSED by
// observing that a call did NOT happen within a scenario window — the
// `maybeShowNotification` gate is the only other code path, so "no call"
// unambiguously means "suppressed".
// ---------------------------------------------------------------------------

class _RecordingNotificationService implements NotificationService {
  _RecordingNotificationService(this._inner);
  final NotificationService _inner;
  final List<_RecordedShow> shown = <_RecordedShow>[];

  @override
  void Function(String payload)? get onNotificationTap =>
      _inner.onNotificationTap;
  @override
  set onNotificationTap(void Function(String payload)? value) =>
      _inner.onNotificationTap = value;

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
  }) async {
    await _inner.showMessageNotification(
      contactPeerId: contactPeerId,
      senderUsername: senderUsername,
      messageText: messageText,
      payload: payload,
    );
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
      '[BOB-N-REC] showMessageNotification called contactPeerId=$contactPeerId shown.length=${shown.length}',
    );
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) => _inner.showNotification(title: title, body: body, payload: payload);

  @override
  Future<String?> consumeInitialPayload() => _inner.consumeInitialPayload();

  @override
  Future<void> clearDeliveredNotifications() =>
      _inner.clearDeliveredNotifications();

  @override
  void dispose() => _inner.dispose();
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

  Map<String, dynamic> toJson() => {
    'contactPeerId': contactPeerId,
    'senderUsername': senderUsername,
    'messageText': messageText,
    'payload': payload,
    'at': at.toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  testWidgets('Bob(Notif) — S1..S4', (tester) async {
    print('\n${'═' * 60}');
    print('  BOB (NOTIFICATION SOUND) — SMOKE E2E');
    print('${'═' * 60}\n');

    // ── Mount staging screen so the app is in `resumed` + not viewing any
    //    conversation. Tester requires a widget to be pumped for the app to
    //    render.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            key: Key('staging-screen'),
            child: Text('Staging — awaiting messages'),
          ),
        ),
      ),
    );

    // ── Stack setup (uses setupGroupMultiDeviceStack for DB/P2P/bridge/repos).
    //    The stack wires its own GroupMessageListener with FakeNotificationService
    //    — we dispose it below and rewire with the REAL FlutterNotificationService
    //    so we can verify production behaviour.
    final stack = await setupGroupMultiDeviceStack(
      dbName: _dbName,
      username: 'BobNotif',
      cliPeerFixture: null,
    );
    await _waitForOnline(stack.p2pService);

    // Publish identity before initializing the local notification plugin. On a
    // fresh iOS simulator the permission request can block an unattended run;
    // Alice still waits for bob_ready before sending any scenario messages.
    _writeJson('bob_identity.json', {
      'peerId': stack.identity.peerId,
      'publicKey': stack.identity.publicKey,
      'mlKemPublicKey': stack.identity.mlKemPublicKey,
    });

    // Replace the stack's FakeNotificationService-wired group listener with
    // one that targets the REAL FlutterNotificationService.
    stack.groupListener.dispose();

    final recording = _RecordingNotificationService(
      FlutterNotificationService(requestApplePermissions: !_nonInteractive),
    );
    await recording.initialize().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Bob(notif): FlutterNotificationService.initialize() timed out',
      ),
    );
    final NotificationService notificationService = recording;

    final chatConversationTracker = ActiveConversationTracker();
    final groupConversationTracker = ActiveConversationTracker();
    AppLifecycleState currentLifecycle = AppLifecycleState.resumed;

    final realGroupListener = GroupMessageListener(
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      bridge: stack.bridge,
      getSelfPeerId: () async => stack.identity.peerId,
      notificationService: notificationService,
      groupConversationTracker: groupConversationTracker,
      getAppLifecycleState: () => currentLifecycle,
    );
    realGroupListener.start(stack.groupStreamController.stream);

    // ── 1:1 message repo (not created by setupGroupMultiDeviceStack) ──
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
      dbDeleteMessagesForContact: (p) =>
          dbDeleteMessagesForContact(stack.db, p),
      dbDeleteMessage: (id) => dbDeleteMessage(stack.db, id),
      dbLoadMessagesPage: (p, {limit = 50, beforeTimestamp}) =>
          dbLoadMessagesPage(
            stack.db,
            p,
            limit: limit,
            beforeTimestamp: beforeTimestamp,
          ),
      dbLoadFailedOutgoingMessages: () =>
          dbLoadFailedOutgoingMessages(stack.db),
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

    // ── 1:1 chat listener wired to the REAL notification service ──
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

    // ── Identity exchange ──
    print('[BOB-N] Identity written, waiting for Alice...');

    final aliceFixture = await _waitForJson('alice_identity.json');
    final alicePeerId = aliceFixture['peerId'] as String;

    await stack.contactRepo.addContact(
      ContactModel(
        peerId: alicePeerId,
        publicKey: aliceFixture['publicKey'] as String,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'AliceNotif',
        signature: 'sig-alice-notif',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: aliceFixture['mlKemPublicKey'] as String?,
      ),
    );
    print('[BOB-N] Alice added as contact');

    _writeSignal('bob_ready', 'ok');

    // Helpers — verdict is derived from the recording wrapper's call log.
    // "Shown" = showMessageNotification was called; "Suppressed" = the
    // maybeShowNotification gate short-circuited (no call recorded). For
    // an expect-shown scenario we wait up to 30s for the wrapper to grow;
    // for an expect-suppressed scenario we wait a short settling window
    // and then confirm no call was recorded.
    Future<void> waitForShown({
      required int baselineCount,
      Duration timeout = const Duration(seconds: 30),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (recording.shown.length > baselineCount) return;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    Map<String, dynamic> buildVerdict({
      required String scenarioId,
      required String state,
      required int baselineCount,
      required bool expectSuppressed,
      String? expectedContactPeerId,
    }) {
      final calls = recording.shown.sublist(baselineCount);
      final hasExpected = expectedContactPeerId != null
          ? calls.any((s) => s.contactPeerId == expectedContactPeerId)
          : calls.isNotEmpty;
      final programmaticPass = expectSuppressed ? calls.isEmpty : hasExpected;
      return {
        'scenarioId': scenarioId,
        'state': state,
        'expectSuppressed': expectSuppressed,
        'expectedContactPeerId': expectedContactPeerId,
        'notificationShown': calls.isNotEmpty,
        'notificationSuppressed': expectSuppressed && calls.isEmpty,
        'programmaticPass': programmaticPass,
        'shownCount': calls.length,
        'shownCalls': calls.map((s) => s.toJson()).toList(),
      };
    }

    // ════════════════════════════════════════════════════════════════
    //  S1: 1:1 direct chat — foreground, off-conversation → should NOTIFY
    // ════════════════════════════════════════════════════════════════
    print('\n--- S1: 1:1 direct chat ---');
    // Capture baseline BEFORE the signal wait — the notification may fire
    // between Alice writing the signal and Bob observing it, so reading
    // after the wait would double-count.
    final s1Baseline = recording.shown.length;
    await _waitForSignal('s1_alice_sent');
    await waitForShown(baselineCount: s1Baseline);
    final s1Verdict = buildVerdict(
      scenarioId: 'S1',
      state: 'foreground_off_conversation',
      baselineCount: s1Baseline,
      expectSuppressed: false,
      expectedContactPeerId: alicePeerId,
    );
    _writeJson('s1_bob_verdict', s1Verdict);
    print(
      '[BOB-N] S1 verdict: pass=${s1Verdict['programmaticPass']} '
      'shown=${s1Verdict['notificationShown']} '
      'count=${s1Verdict['shownCount']}',
    );

    // ════════════════════════════════════════════════════════════════
    //  S2: Group discussion (GroupType.chat) → should NOTIFY
    // ════════════════════════════════════════════════════════════════
    print('\n--- S2: Group discussion ---');
    await _waitForSignal('alice_group_chat_ready');
    final chatGroupFixture = await _waitForJson('group_chat_fixture.json');
    final chatGroupId = await importJoinedGroupFixture(
      stack: stack,
      fixture: chatGroupFixture,
    );
    print('[BOB-N] Joined chat group: ${chatGroupId.substring(0, 16)}...');
    // Give GossipSub peer discovery + connection a few seconds.
    await Future<void>.delayed(const Duration(seconds: 5));
    _writeSignal('bob_group_chat_joined', 'ok');

    final s2Baseline = recording.shown.length;
    await _waitForSignal('s2_alice_sent');
    await waitForShown(baselineCount: s2Baseline);
    final s2Verdict = buildVerdict(
      scenarioId: 'S2',
      state: 'foreground_off_conversation',
      baselineCount: s2Baseline,
      expectSuppressed: false,
      expectedContactPeerId: 'group:$chatGroupId',
    );
    _writeJson('s2_bob_verdict', s2Verdict);
    print(
      '[BOB-N] S2 verdict: pass=${s2Verdict['programmaticPass']} '
      'count=${s2Verdict['shownCount']}',
    );

    // ════════════════════════════════════════════════════════════════
    //  S3: Group announcement (GroupType.announcement) → should NOTIFY
    // ════════════════════════════════════════════════════════════════
    print('\n--- S3: Group announcement ---');
    await _waitForSignal('alice_group_announcement_ready');
    final annGroupFixture = await _waitForJson(
      'group_announcement_fixture.json',
    );
    final annGroupId = await importJoinedGroupFixture(
      stack: stack,
      fixture: annGroupFixture,
    );
    print(
      '[BOB-N] Joined announcement group: ${annGroupId.substring(0, 16)}...',
    );
    await Future<void>.delayed(const Duration(seconds: 5));
    _writeSignal('bob_group_announcement_joined', 'ok');

    final s3Baseline = recording.shown.length;
    await _waitForSignal('s3_alice_sent');
    await waitForShown(baselineCount: s3Baseline);
    final s3Verdict = buildVerdict(
      scenarioId: 'S3',
      state: 'foreground_off_conversation',
      baselineCount: s3Baseline,
      expectSuppressed: false,
      expectedContactPeerId: 'group:$annGroupId',
    );
    _writeJson('s3_bob_verdict', s3Verdict);
    print(
      '[BOB-N] S3 verdict: pass=${s3Verdict['programmaticPass']} '
      'count=${s3Verdict['shownCount']}',
    );

    // ════════════════════════════════════════════════════════════════
    //  S4: Suppression control — Bob simulates viewing Alice's 1:1
    //       conversation. Expected: NOTIFICATION_SUPPRESSED, no NOTIFICATION_SHOWN.
    // ════════════════════════════════════════════════════════════════
    print('\n--- S4: Suppression control ---');
    chatConversationTracker.setActive(alicePeerId);
    _writeSignal('bob_viewing_conversation', 'ok');

    final s4Baseline = recording.shown.length;
    await _waitForSignal('s4_alice_sent');
    // For the suppression case, wait a short settling window so any rogue
    // showMessageNotification call has time to fire — then assert none did.
    await Future<void>.delayed(const Duration(seconds: 6));
    final s4Verdict = buildVerdict(
      scenarioId: 'S4',
      state: 'foreground_viewing_conversation',
      baselineCount: s4Baseline,
      expectSuppressed: true,
      expectedContactPeerId: alicePeerId,
    );
    _writeJson('s4_bob_verdict', s4Verdict);
    print(
      '[BOB-N] S4 verdict: pass=${s4Verdict['programmaticPass']} '
      'suppressed=${s4Verdict['notificationSuppressed']} '
      'count=${s4Verdict['shownCount']}',
    );

    chatConversationTracker.clear();

    // ── Done ──
    await _waitForSignal('all_done');
    print('\n[BOB-N] All scenarios complete');

    chatListener.dispose();
    realGroupListener.dispose();
    notificationService.dispose();
    await stack.teardown();
    _writeSignal('bob_done', 'ok');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
