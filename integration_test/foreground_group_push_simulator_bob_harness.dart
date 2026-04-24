// Foreground Group Push Simulator Smoke — Bob Harness
//
// Runs on simulator B and approximates the Report 71 real-device checklist by
// keeping the app foregrounded, forcing a temporary group-topic gap, and then
// replaying the exact foreground push router on the real group stack.
//
// This proves app-side same-session drain and dedupe on simulator, but it is
// not a substitute for physical-device APNs / Focus / audio / hardware checks.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';

import '../test/features/push/application/remote_message_fixtures.dart';
import '../test/shared/fakes/fake_notification_service.dart';
import 'group_multi_device_real_harness.dart';

const _sharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '/tmp',
);
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'foreground_group_push_sim_bob.db',
);

String _sig(String name) => '$_sharedDir/fgpush_${_runId}_$name';

void _writeSignal(String name, String content) {
  File(_sig(name)).writeAsStringSync(content);
}

void _writeJson(String name, Map<String, dynamic> data) {
  _writeSignal(name, jsonEncode(data));
}

Future<void> _waitForSignal(
  String name, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(_sig(name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Bob(fgpush): timed out waiting for $name');
}

Future<Map<String, dynamic>> _waitForJson(
  String name, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(_sig(name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Bob(fgpush): timed out waiting for json: $name');
}

Future<bool> _waitForOnline(
  dynamic service, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (healthFromState(service.currentState) == ConnectionHealth.online) {
      print('[BOB-FGPUSH] Online after ${sw.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

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
  throw TimeoutException('Bob(fgpush): timed out waiting for condition');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  testWidgets(
    'Bob(Foreground Group Push Simulator) — S1/S2',
    (tester) async {
      print('\n${'═' * 60}');
      print('  BOB (FOREGROUND GROUP PUSH SIMULATOR)');
      print('${'═' * 60}\n');

      final stack = await setupGroupMultiDeviceStack(
        dbName: _dbName,
        username: 'BobFgPush',
        cliPeerFixture: null,
      );
      await _waitForOnline(stack.p2pService);

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
      );
      foregroundGroupListener.start(stack.groupStreamController.stream);

      _writeJson('bob_identity.json', {
        'peerId': stack.identity.peerId,
        'publicKey': stack.identity.publicKey,
        'mlKemPublicKey': stack.identity.mlKemPublicKey,
      });

      final aliceFixture = await _waitForJson('alice_identity.json');
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

      await _waitForSignal('alice_ready', timeout: const Duration(minutes: 8));
      final groupFixture = await _waitForJson('group_fixture.json');
      final groupId = await importJoinedGroupFixture(
        stack: stack,
        fixture: groupFixture,
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      _writeSignal('bob_group_joined', 'ok');

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

      await _waitForSignal('s1_go');
      final s1BaselineNotifications = notificationService.shown.length;
      await callGroupLeave(stack.bridge, groupId);
      await Future<void>.delayed(const Duration(seconds: 8));
      _writeSignal('s1_bob_gap_ready', 'ok');

      final s1Send = await _waitForJson('s1_alice_sent');
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

      _writeJson('s1_bob_verdict', {
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
      _writeSignal('s1_verified', 'ok');

      await _waitForSignal('s2_go');
      final rejoinResult = await rejoinGroupTopics(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        reason: RejoinReason.inPlaceRecovery,
      );
      expect(rejoinResult.errorCount, 0);
      expect(rejoinResult.joinedGroupCount, greaterThanOrEqualTo(1));
      await Future<void>.delayed(const Duration(seconds: 8));
      _writeSignal('s2_bob_live_ready', 'ok');

      final s2BaselineNotifications = notificationService.shown.length;
      final s2Send = await _waitForJson('s2_alice_sent');
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

      _writeJson('s2_bob_verdict', {
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
      _writeSignal('s2_verified', 'ok');

      await _waitForSignal('all_done');
      foregroundGroupListener.dispose();
      notificationService.dispose();
      currentLifecycle = AppLifecycleState.paused;
      await stack.teardown();
      _writeSignal('bob_done', 'ok');
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
