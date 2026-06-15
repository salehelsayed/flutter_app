// Foreground Group Push Simulator Smoke — Role-Dispatched Harness
//
// Single harness that dispatches to the Alice or Bob path based on the
// SMOKE_ROLE dart-define (set by the two-simulator orchestrator). Both roles
// run the real bridge / P2P / relay-backed group stack.
//
// Alice (simulator A) creates the shared group for the Report 71 smoke.
//
// Bob (simulator B) approximates the Report 71 real-device checklist by keeping
// the app foregrounded, forcing a temporary group-topic gap, and then replaying
// the exact foreground push router on the real group stack.
//
// This is a simulator approximation of the real-device checklist: it uses the
// real bridge / P2P / relay-backed group stack, but the foreground push itself
// is replayed by Bob through the app's foreground router instead of through APNs
// delivery. It proves app-side same-session drain and dedupe on simulator, but
// it is not a substitute for physical-device APNs / Focus / audio / hardware
// checks.

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';
import 'package:flutter_app/features/push/application/resolve_group_notification_route_target_use_case.dart';

import '../test/features/push/application/remote_message_fixtures.dart';
import '../test/shared/fakes/fake_notification_service.dart';
import '_support/node_readiness.dart';
import '_support/signal_files.dart';
import 'group_multi_device_real_harness.dart';

const _role = String.fromEnvironment('SMOKE_ROLE', defaultValue: 'alice');

const _sharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '/tmp',
);
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: '',
);

String _defaultDbName() => _role == 'bob'
    ? 'foreground_group_push_sim_bob.db'
    : 'foreground_group_push_sim_alice.db';

String _resolvedDbName() => _dbName.isEmpty ? _defaultDbName() : _dbName;

// Byte-identical to the old `'$_sharedDir/fgpush_${_runId}_$name'`:
// SignalDir.path(name) == '$dir/$prefix$runId$name'
//                      == '$_sharedDir/fgpush_${_runId}_$name'.
final SignalDir _signals = SignalDir(
  dir: _sharedDir,
  prefix: 'fgpush_',
  runId: '${_runId}_',
  role: '$_role(fgpush)',
);

Future<void> _waitForCondition(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(milliseconds: 250),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(interval);
  }
  throw TimeoutException('$_role(fgpush): timed out waiting for condition');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  if (_role == 'bob') {
    _runBob();
  } else {
    _runAlice();
  }
}

void _runAlice() {
  testWidgets(
    'Alice(Foreground Group Push Simulator) — S1/S2',
    (tester) async {
      print('\n${'═' * 60}');
      print('  ALICE (FOREGROUND GROUP PUSH SIMULATOR)');
      print('${'═' * 60}\n');

      final stack = await setupGroupMultiDeviceStack(
        dbName: _resolvedDbName(),
        username: 'AliceFgPush',
        cliPeerFixture: null,
      );
      await waitForOnline(
        stack.p2pService,
        timeout: const Duration(seconds: 60),
      );

      _signals.writeJson('alice_identity.json', {
        'peerId': stack.identity.peerId,
        'publicKey': stack.identity.publicKey,
        'mlKemPublicKey': stack.identity.mlKemPublicKey,
      });
      _signals.writeSignal('alice_ready', content: 'ok');

      final bobFixture = await _signals.waitForJson(
        'bob_identity.json',
        timeout: const Duration(minutes: 5),
      );
      final bobPeerId = bobFixture['peerId'] as String;
      await stack.contactRepo.addContact(
        ContactModel(
          peerId: bobPeerId,
          publicKey: bobFixture['publicKey'] as String,
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'BobFgPush',
          signature: 'sig-bob-fgpush',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
          mlKemPublicKey: bobFixture['mlKemPublicKey'] as String?,
        ),
      );

      final bobContact = await stack.contactRepo.getContact(bobPeerId);
      final groupResult = await createGroupWithMembers(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        p2pService: stack.p2pService,
        identity: stack.identity,
        selectedContacts: [bobContact!],
        type: GroupType.chat,
        name: 'Foreground Group Push Smoke',
        inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
      );
      final groupId = groupResult.group.id;
      final group = await stack.groupRepo.getGroup(groupId);
      final keyInfo = await stack.groupRepo.getLatestKey(groupId);
      final members = await stack.groupRepo.getMembers(groupId);
      expect(group, isNotNull);
      expect(keyInfo, isNotNull);

      _signals.writeJson(
        'group_fixture.json',
        buildGroupFixture(group: group!, keyInfo: keyInfo!, members: members),
      );

      await _signals.waitForSignal(
        'bob_group_joined',
        timeout: const Duration(minutes: 8),
      );
      await stack.groupInviteDeliveryAttemptRepo.markJoined(
        groupId: groupId,
        peerId: bobPeerId,
        username: 'BobFgPush',
      );
      await Future<void>.delayed(const Duration(seconds: 5));

      Future<Map<String, dynamic>> sendScenarioMessage(
        String scenarioId,
      ) async {
        final text =
            '$scenarioId from Alice at '
            '${DateTime.now().toUtc().toIso8601String()}';
        final sw = Stopwatch()..start();
        final result = await sendGroupMessage(
          bridge: stack.bridge,
          groupRepo: stack.groupRepo,
          msgRepo: stack.groupMsgRepo,
          groupId: groupId,
          text: text,
          senderPeerId: stack.identity.peerId,
          senderPublicKey: stack.identity.publicKey,
          senderPrivateKey: stack.identity.privateKey,
          senderUsername: stack.identity.username,
          inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
        );
        sw.stop();
        final message = result.$2;
        expect(message, isNotNull);
        return {
          'scenarioId': scenarioId,
          'groupId': groupId,
          'text': text,
          'sendMs': sw.elapsedMilliseconds,
          'outcome': result.$1.name,
          'messageId': message!.id,
        };
      }

      await _signals.waitForSignal('s1_go', timeout: const Duration(minutes: 5));
      await _signals.waitForSignal(
        's1_bob_gap_ready',
        timeout: const Duration(minutes: 3),
      );
      await Future<void>.delayed(const Duration(seconds: 8));
      _signals.writeJson('s1_alice_sent', await sendScenarioMessage('S1'));
      await _signals.waitForSignal(
        's1_verified',
        timeout: const Duration(minutes: 5),
      );

      await _signals.waitForSignal('s2_go', timeout: const Duration(minutes: 5));
      await _signals.waitForSignal(
        's2_bob_live_ready',
        timeout: const Duration(minutes: 3),
      );
      await Future<void>.delayed(const Duration(seconds: 8));
      _signals.writeJson('s2_alice_sent', await sendScenarioMessage('S2'));
      await _signals.waitForSignal(
        's2_verified',
        timeout: const Duration(minutes: 5),
      );

      await _signals.waitForSignal(
        'all_done',
        timeout: const Duration(minutes: 5),
      );
      await stack.teardown();
      _signals.writeSignal('alice_done', content: 'ok');
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

void _runBob() {
  testWidgets(
    'Bob(Foreground Group Push Simulator) — S1/S2/S3',
    (tester) async {
      print('\n${'═' * 60}');
      print('  BOB (FOREGROUND GROUP PUSH SIMULATOR)');
      print('${'═' * 60}\n');

      final stack = await setupGroupMultiDeviceStack(
        dbName: _resolvedDbName(),
        username: 'BobFgPush',
        cliPeerFixture: null,
      );
      await waitForOnline(
        stack.p2pService,
        timeout: const Duration(seconds: 60),
      );

      stack.groupListener.dispose();
      final notificationService = FakeNotificationService();
      await notificationService.initialize();
      AppLifecycleState currentLifecycle = AppLifecycleState.resumed;
      final foregroundGroupListener = GroupMessageListener(
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        bridge: stack.bridge,
        getSelfPeerId: () async => stack.identity.peerId,
        notificationService: notificationService,
        groupConversationTracker: ActiveConversationTracker(),
        getAppLifecycleState: () => currentLifecycle,
        inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
      );
      foregroundGroupListener.start(stack.groupStreamController.stream);

      _signals.writeJson('bob_identity.json', {
        'peerId': stack.identity.peerId,
        'publicKey': stack.identity.publicKey,
        'mlKemPublicKey': stack.identity.mlKemPublicKey,
      });

      final aliceFixture = await _signals.waitForJson(
        'alice_identity.json',
        timeout: const Duration(minutes: 5),
      );
      final alicePeerId = aliceFixture['peerId'] as String;
      await stack.contactRepo.addContact(
        ContactModel(
          peerId: alicePeerId,
          publicKey: aliceFixture['publicKey'] as String,
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'AliceFgPush',
          signature: 'sig-alice-fgpush',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
          mlKemPublicKey: aliceFixture['mlKemPublicKey'] as String?,
        ),
      );

      await _signals.waitForSignal(
        'alice_ready',
        timeout: const Duration(minutes: 8),
      );
      final groupFixture = await _signals.waitForJson(
        'group_fixture.json',
        timeout: const Duration(minutes: 5),
      );
      final groupId = await importJoinedGroupFixture(
        stack: stack,
        fixture: groupFixture,
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      _signals.writeSignal('bob_group_joined', content: 'ok');

      Future<List<GroupMessage>> incomingMessages() async {
        return (await stack.groupMsgRepo.getMessagesPage(
          groupId,
        )).where((message) => message.isIncoming).toList(growable: false);
      }

      Future<bool> hasIncomingMessage(String messageId) async {
        return (await incomingMessages()).any(
          (message) => message.id == messageId,
        );
      }

      Future<int> countIncomingMessage(String messageId) async {
        return (await incomingMessages())
            .where((message) => message.id == messageId)
            .length;
      }

      Future<GroupMessage> loadIncomingMessage(String messageId) async {
        await _waitForCondition(() => hasIncomingMessage(messageId));
        return (await incomingMessages()).firstWhere(
          (message) => message.id == messageId,
        );
      }

      Future<void> runForegroundPush({
        required String pushGroupId,
        required String messageId,
      }) {
        return handleForegroundRemoteMessage(
          data: groupMessageData(groupId: pushGroupId, messageId: messageId),
          messageId: messageId,
          drainOfflineInbox: () async {},
          drainGroupOfflineInboxForGroup: (targetGroupId) =>
              drainGroupOfflineInboxForGroup(
                bridge: stack.bridge,
                groupRepo: stack.groupRepo,
                msgRepo: stack.groupMsgRepo,
                groupId: targetGroupId,
                mediaAttachmentRepo: null,
                reactionRepo: null,
                groupMessageListener: foregroundGroupListener,
              ),
        );
      }

      await _signals.waitForSignal('s1_go', timeout: const Duration(minutes: 5));
      final s1BaselineNotifications = notificationService.shown.length;
      await callGroupLeave(stack.bridge, groupId);
      await Future<void>.delayed(const Duration(seconds: 8));
      _signals.writeSignal('s1_bob_gap_ready', content: 'ok');

      final s1Send = await _signals.waitForJson(
        's1_alice_sent',
        timeout: const Duration(minutes: 5),
      );
      final s1MessageId = s1Send['messageId'] as String;
      final s1Text = s1Send['text'] as String;

      await Future<void>.delayed(const Duration(seconds: 4));
      final s1PresentBeforePush = await hasIncomingMessage(s1MessageId);
      expect(
        s1PresentBeforePush,
        isFalse,
        reason: 'S1 must miss live delivery before the foreground drain runs',
      );

      await runForegroundPush(pushGroupId: groupId, messageId: s1MessageId);
      final s1Message = await loadIncomingMessage(s1MessageId);
      final s1NotificationDelta = notificationService.shown.sublist(
        s1BaselineNotifications,
      );

      expect(s1Message.text, s1Text);
      expect(await countIncomingMessage(s1MessageId), 1);
      expect(s1NotificationDelta, hasLength(1));
      expect(
        s1NotificationDelta.single.payload,
        'group:$groupId|message:$s1MessageId',
      );

      _signals.writeJson('s1_bob_verdict', {
        'scenarioId': 'S1',
        'sendOutcome': s1Send['outcome'],
        'messagePresentBeforePush': s1PresentBeforePush,
        'notificationCount': s1NotificationDelta.length,
        'materializedMessageId': s1Message.id,
        'programmaticPass':
            !s1PresentBeforePush &&
            s1Message.id == s1MessageId &&
            s1NotificationDelta.length == 1 &&
            await countIncomingMessage(s1MessageId) == 1,
      });
      _signals.writeSignal('s1_verified', content: 'ok');

      await _signals.waitForSignal('s2_go', timeout: const Duration(minutes: 5));
      final rejoinResult = await rejoinGroupTopics(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        reason: RejoinReason.inPlaceRecovery,
      );
      expect(rejoinResult.errorCount, 0);
      expect(rejoinResult.joinedGroupCount, greaterThanOrEqualTo(1));
      await Future<void>.delayed(const Duration(seconds: 8));
      _signals.writeSignal('s2_bob_live_ready', content: 'ok');

      final s2BaselineNotifications = notificationService.shown.length;
      final s2Send = await _signals.waitForJson(
        's2_alice_sent',
        timeout: const Duration(minutes: 5),
      );
      final s2MessageId = s2Send['messageId'] as String;
      final s2Text = s2Send['text'] as String;

      final s2LiveMessage = await loadIncomingMessage(s2MessageId);
      await _waitForCondition(
        () async => notificationService.shown.length > s2BaselineNotifications,
      );
      final s2CountBeforePush = await countIncomingMessage(s2MessageId);
      expect(s2LiveMessage.text, s2Text);
      expect(s2CountBeforePush, 1);

      await runForegroundPush(pushGroupId: groupId, messageId: s2MessageId);
      await Future<void>.delayed(const Duration(seconds: 4));
      final s2CountAfterPush = await countIncomingMessage(s2MessageId);
      final s2NotificationDelta = notificationService.shown.sublist(
        s2BaselineNotifications,
      );

      expect(s2CountAfterPush, 1);
      expect(s2NotificationDelta, hasLength(1));
      expect(
        s2NotificationDelta.single.payload,
        'group:$groupId|message:$s2MessageId',
      );

      _signals.writeJson('s2_bob_verdict', {
        'scenarioId': 'S2',
        'sendOutcome': s2Send['outcome'],
        'countBeforePush': s2CountBeforePush,
        'countAfterPush': s2CountAfterPush,
        'notificationCount': s2NotificationDelta.length,
        'programmaticPass':
            s2CountBeforePush == 1 &&
            s2CountAfterPush == 1 &&
            s2NotificationDelta.length == 1,
      });
      _signals.writeSignal('s2_verified', content: 'ok');

      await _signals.waitForSignal('s3_go', timeout: const Duration(minutes: 5));
      final s3MissingGroupId =
          'missing-${DateTime.now().microsecondsSinceEpoch}';
      const s3MessageId = 'msg-s3-non-current';
      final s3Data = groupMessageData(
        groupId: s3MissingGroupId,
        messageId: s3MessageId,
      );
      final s3BaselineGenericNotifications =
          notificationService.shownGeneric.length;
      var s3DrainAttempts = 0;

      final s3Result = await handleForegroundRemoteMessage(
        data: s3Data,
        messageId: s3MessageId,
        drainOfflineInbox: () async {},
        drainGroupOfflineInboxForGroup: (targetGroupId) async {
          s3DrainAttempts += 1;
          throw StateError('simulated missing group drain for $targetGroupId');
        },
      );
      final s3Shown = await showForegroundPushFallbackNotificationIfNeeded(
        result: s3Result,
        notificationService: notificationService,
        message: RemoteMessage(messageId: s3MessageId, data: s3Data),
        groupMessageDisplayEligibilityResolver: (targetGroupId) {
          return resolveGroupMessageNotificationDisplayEligibility(
            groupId: targetGroupId,
            groupRepo: stack.groupRepo,
            localPeerId: stack.identity.peerId,
          );
        },
      );
      final s3GenericNotificationDelta =
          notificationService.shownGeneric.length -
          s3BaselineGenericNotifications;

      expect(s3Result, ForegroundRemoteMessageResult.notificationNeeded);
      expect(s3DrainAttempts, 1);
      expect(s3Shown, isFalse);
      expect(s3GenericNotificationDelta, 0);

      _signals.writeJson('s3_bob_verdict', {
        'scenarioId': 'S3',
        'groupId': s3MissingGroupId,
        'result': s3Result.name,
        'drainAttempts': s3DrainAttempts,
        'fallbackShown': s3Shown,
        'genericNotificationCount': s3GenericNotificationDelta,
        'programmaticPass':
            s3Result == ForegroundRemoteMessageResult.notificationNeeded &&
            s3DrainAttempts == 1 &&
            !s3Shown &&
            s3GenericNotificationDelta == 0,
      });
      _signals.writeSignal('s3_verified', content: 'ok');

      await _signals.waitForSignal(
        'all_done',
        timeout: const Duration(minutes: 5),
      );
      foregroundGroupListener.dispose();
      notificationService.dispose();
      currentLifecycle = AppLifecycleState.paused;
      await stack.teardown();
      _signals.writeSignal('bob_done', content: 'ok');
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
