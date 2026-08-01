import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_group_reaction_replay_outbox_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';

/// Bridge that fails on the first N group:inboxStore calls and succeeds after.
class _FailFirstNInboxBridge extends FakeBridge {
  final int _failCount;
  int _callIndex = 0;
  _FailFirstNInboxBridge({int failCount = 1}) : _failCount = failCount;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:inboxStore') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      _callIndex++;
      if (_callIndex <= _failCount) {
        throw Exception('Simulated inbox store failure #$_callIndex');
      }
      return jsonEncode({'ok': true});
    }
    return super.send(message);
  }
}

class _TimeoutInboxStoreBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:inboxStore') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      throw TimeoutException('Simulated group:inboxStore timeout');
    }
    return super.send(message);
  }
}

class _GatedInboxStoreBridge extends FakeBridge {
  final Completer<void> inboxStarted = Completer<void>();
  final Completer<void> inboxGate = Completer<void>();

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:inboxStore') {
      if (!inboxStarted.isCompleted) inboxStarted.complete();
      await inboxGate.future;
    }
    return super.send(message);
  }
}

class _ReplaceReactionRowOnStoreBridge extends FakeBridge {
  _ReplaceReactionRowOnStoreBridge({
    required this.repository,
    required this.replacement,
  });

  final FakeGroupReactionReplayOutboxRepository repository;
  final GroupReactionReplayOutboxEntry replacement;

  @override
  Future<String> send(String message) async {
    final response = await super.send(message);
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'group:inboxStore') {
      await repository.saveEntry(replacement);
    }
    return response;
  }
}

GroupMessage _makeRetryEligible(
  String id, {
  String status = 'sent',
  bool inboxStored = false,
  String? inboxRetryPayload,
  bool isIncoming = false,
  DateTime? timestamp,
}) {
  final now = timestamp ?? DateTime.utc(2026, 1, 15, 12, 0, 0);
  return GroupMessage(
    id: id,
    groupId: 'group-1',
    senderPeerId: 'peer-1',
    senderUsername: 'Alice',
    text: 'Test message $id',
    timestamp: now,
    keyGeneration: 0,
    status: status,
    isIncoming: isIncoming,
    createdAt: now,
    inboxStored: inboxStored,
    inboxRetryPayload:
        inboxRetryPayload ??
        (isIncoming || inboxStored
            ? null
            : jsonEncode({
                'groupId': 'group-1',
                'message': jsonEncode({
                  'groupId': 'group-1',
                  'senderId': 'peer-1',
                  'text': 'Test message $id',
                  'timestamp': now.toIso8601String(),
                  'messageId': id,
                }),
                'recipientPeerIds': ['peer-2'],
                'pushTitle': 'Test Group',
                'pushBody': 'Alice: Test message $id',
              })),
  );
}

GroupReactionReplayOutboxEntry _makeReactionRetryEntry(
  String reactionId, {
  String action = 'add',
  String deliveryStatus = GroupReactionReplayOutboxStatus.failed,
  DateTime? createdAt,
}) {
  final nowIso = (createdAt ?? DateTime.utc(2026, 1, 15, 12, 0, 0))
      .toIso8601String();
  return GroupReactionReplayOutboxEntry(
    reactionId: reactionId,
    groupId: 'group-1',
    messageId: 'message-$reactionId',
    senderPeerId: 'peer-1',
    emoji: action == 'remove' ? ':remove:' : ':fire:',
    action: action,
    inboxRetryPayload: jsonEncode({
      'groupId': 'group-1',
      'message': jsonEncode({
        'kind': 'group_offline_replay',
        'version': 1,
        'payloadType': 'group_reaction',
        'keyEpoch': 1,
        'messageId': reactionId,
        'ciphertext': jsonEncode({
          'id': reactionId,
          'messageId': 'message-$reactionId',
          'emoji': action == 'remove' ? ':remove:' : ':fire:',
          'action': action,
          'senderPeerId': 'peer-1',
          'timestamp': nowIso,
        }),
        'nonce': 'fake-group-nonce',
      }),
      'recipientPeerIds': ['peer-2'],
      'pushTitle': 'Test Group',
      'pushBody': 'reaction $reactionId',
    }),
    deliveryStatus: deliveryStatus,
    lastError: deliveryStatus == GroupReactionReplayOutboxStatus.failed
        ? 'initial failure'
        : null,
    createdAt: nowIso,
    updatedAt: nowIso,
  );
}

String _signedReplayRetryPayload({
  required String messageId,
  String payloadType = 'group_message',
}) {
  return jsonEncode({
    'groupId': 'group-1',
    'message': jsonEncode({
      'kind': 'group_offline_replay',
      'version': 1,
      'groupId': 'group-1',
      'payloadType': payloadType,
      'keyEpoch': 1,
      'messageId': messageId,
      'senderPeerId': 'peer-1',
      'senderDeviceId': 'peer-1',
      'senderTransportPeerId': 'peer-1',
      'senderPublicKey': 'pk-1',
      'recipientSetHash': 'recipient-set-hash',
      'ciphertext': 'ciphertext-$messageId',
      'nonce': 'nonce-$messageId',
      'signatureAlgorithm': 'ed25519',
      'signedPayload': '{"kind":"group_offline_replay"}',
      'signature': 'sig-$messageId',
    }),
    'recipientPeerIds': ['peer-2'],
  });
}

List<String> _inboxStoreMessageIds(FakeBridge bridge) {
  return bridge.sentMessages
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .where((message) => message['cmd'] == 'group:inboxStore')
      .map((message) {
        final payload = (message['payload'] as Map).cast<String, dynamic>();
        final replay = jsonDecode(payload['message'] as String) as Map;
        return replay['messageId'] as String;
      })
      .toList();
}

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeGroupReactionReplayOutboxRepository reactionReplayOutboxRepo;

  setUp(() {
    bridge = FakeBridge();
    msgRepo = InMemoryGroupMessageRepository();
    reactionReplayOutboxRepo = FakeGroupReactionReplayOutboxRepository();
  });

  test(
    'replays the frozen staged recipient set even when the roster is wider',
    () async {
      // Plan 318 TC-318-14: envelope byte-identity feeds relay dedup/merge, so
      // the retriever must replay the persisted inboxRetryPayload set verbatim
      // and never recompute from the (post-318 wider) live roster.
      final msg = _makeRetryEligible('msg-frozen-1');
      await msgRepo.saveMessage(msg);
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: msg.groupId,
          name: 'Frozen Group',
          type: GroupType.chat,
          topicName: 'topic-frozen',
          createdAt: DateTime.utc(2026, 6, 1),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        ),
      );
      for (final peerId in <String>['peer-2', 'peer-extra-incumbent']) {
        await groupRepo.saveMember(
          GroupMember(
            groupId: msg.groupId,
            peerId: peerId,
            role: MemberRole.writer,
            publicKey: 'pk-$peerId',
            joinedAt: DateTime.utc(2026, 6, 1),
          ),
        );
      }

      final retried = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
        groupRepo: groupRepo,
      );

      expect(retried, 1);
      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['recipientPeerIds'], equals(['peer-2']));
      expect(payload['preserveRecipientPeerIds'], isTrue);
    },
  );

  test('needs-build row is rebuilt with original identity and stored', () async {
    // Plan 319 TC-319-05: the retrier rescues an abandoned reaction by
    // rebuilding its envelope — reusing the ORIGINAL transition id (so every
    // notification surface dedupes it) and anchoring the plaintext timestamp
    // to the row's created_at (so a rebuilt ADD cannot out-time a tombstone).
    final outbox = FakeGroupReactionReplayOutboxRepository();
    const transitionId = 'group-reaction-event-rescue-1';
    const createdAt = '2026-08-01T10:00:00.000Z';
    await outbox.saveEntry(
      GroupReactionReplayOutboxEntry(
        reactionId: transitionId,
        groupId: 'group-1',
        messageId: 'msg-1',
        senderPeerId: 'peer-1',
        emoji: '\u{1F44D}',
        action: 'add',
        inboxRetryPayload: '',
        deliveryStatus: GroupReactionReplayOutboxStatus.needsBuild,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );

    final groupRepo = InMemoryGroupRepository();
    await groupRepo.saveGroup(
      GroupModel(
        id: 'group-1',
        name: 'Rescue Group',
        type: GroupType.chat,
        topicName: 'topic-1',
        createdAt: DateTime.utc(2026, 8, 1),
        createdBy: 'peer-1',
        myRole: GroupRole.admin,
      ),
    );
    for (final peerId in <String>['peer-1', 'peer-2']) {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: peerId,
          username: peerId,
          role: MemberRole.writer,
          publicKey: 'pk-$peerId',
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );
    }
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 0,
        encryptedKey: 'group-key-0',
        createdAt: DateTime.utc(2026, 8, 1),
      ),
    );
    final messages = InMemoryGroupMessageRepository();
    await messages.saveMessage(
      GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Bob',
        text: 'target',
        timestamp: DateTime.utc(2026, 8, 1),
        keyGeneration: 0,
        status: 'delivered',
        isIncoming: true,
        createdAt: DateTime.utc(2026, 8, 1),
      ),
    );

    final identityRepo = FakeIdentityRepository();
    await identityRepo.saveIdentity(
      FakeIdentityRepository.makeIdentity(
        peerId: 'peer-1',
        publicKey: 'pk-peer-1',
        privateKey: 'sk-peer-1',
      ),
    );

    await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: messages,
      groupRepo: groupRepo,
      identityRepo: identityRepo,
      reactionReplayOutboxRepo: outbox,
    );

    final rebuilt = await outbox.getEntry(transitionId);
    expect(rebuilt, isNotNull);
    expect(rebuilt!.inboxRetryPayload, isNotEmpty);
    final retry = jsonDecode(rebuilt.inboxRetryPayload) as Map<String, Object?>;
    final envelope =
        jsonDecode(retry['message'] as String) as Map<String, Object?>;
    final extension =
        envelope['notificationExtension'] as Map<String, Object?>?;
    expect(
      extension?['transitionId'],
      transitionId,
      reason: 'the rebuild must reuse the ORIGINAL transition id',
    );
  });

  test('retries eligible sent messages and clears inbox retry state', () async {
    final msg = _makeRetryEligible('msg-1');
    await msgRepo.saveMessage(msg);

    late int retried;
    final events = await captureFlowEvents(() async {
      retried = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
      );
    });

    expect(retried, 1);
    final saved = await msgRepo.getMessage('msg-1');
    expect(saved!.inboxStored, isTrue);
    expect(saved.status, 'sent');
    expect(saved.inboxRetryPayload, isNull);
    expect(bridge.commandLog, contains('group:inboxStore'));
    final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
    final payload = sent['payload'] as Map<String, dynamic>;
    expect(payload.containsKey('pushTitle'), isFalse);
    expect(payload.containsKey('pushBody'), isFalse);
    expect(payload['recipientPeerIds'], equals(['peer-2']));
    expect(payload['preserveRecipientPeerIds'], isTrue);

    final begin = events.firstWhere(
      (event) => event['event'] == 'RETRY_FAILED_GROUP_INBOX_STORES_BEGIN',
    );
    expect(begin['details']['limit'], 20);

    final ok = events.firstWhere(
      (event) => event['event'] == 'RETRY_FAILED_GROUP_INBOX_STORE_OK',
    );
    expect(ok['details']['messageId'], 'msg-1');

    final done = events.firstWhere(
      (event) => event['event'] == 'RETRY_FAILED_GROUP_INBOX_STORES_DONE',
    );
    expect(done['details']['retried'], 1);
    expect(done['details']['total'], 1);

    final timing = events.lastWhere(
      (event) => event['event'] == 'RETRY_FAILED_GROUP_INBOX_STORES_TIMING',
    );
    expect(timing['details']['outcome'], 'complete');
    expect(timing['details']['total'], 1);
    expect(timing['details']['retried'], 1);
    expect(timing['details']['limit'], 20);
  });

  test(
    'PGC-010 action-first inbox repush completes before B3 commits',
    () async {
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-1',
          name: 'Test Group',
          type: GroupType.chat,
          topicName: 'topic-1',
          createdAt: DateTime.utc(2026, 7, 20, 9),
          createdBy: 'peer-1',
          myRole: GroupRole.member,
        ),
      );
      await msgRepo.saveMessage(_makeRetryEligible('pgc010-inbox-action'));
      final gatedBridge = _GatedInboxStoreBridge();

      final retryFuture = retryFailedGroupInboxStores(
        bridge: gatedBridge,
        msgRepo: msgRepo,
        groupRepo: groupRepo,
      );
      await gatedBridge.inboxStarted.future;

      var markerCommitted = false;
      final markerFuture = runGroupMembershipMutationLocked(
        groupId: 'group-1',
        action: () async {
          final current = await groupRepo.getGroup('group-1');
          await groupRepo.updateGroup(
            current!.copyWith(selfRemovedAt: DateTime.utc(2026, 7, 20, 9, 1)),
          );
          markerCommitted = true;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        markerCommitted,
        isFalse,
        reason: 'B3 must wait for inbox action plus exact completion',
      );

      gatedBridge.inboxGate.complete();
      expect(await retryFuture, 1);
      await markerFuture;
      expect(markerCommitted, isTrue);
      final saved = await msgRepo.getMessage('pgc010-inbox-action');
      expect(saved!.inboxStored, isTrue);
      expect(saved.inboxRetryPayload, isNull);
    },
  );

  test(
    'PGC-010 B3-first membership phase stops inbox repush before dispatch',
    () async {
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-1',
          name: 'Test Group',
          type: GroupType.chat,
          topicName: 'topic-1',
          createdAt: DateTime.utc(2026, 7, 20, 9, 2),
          createdBy: 'peer-1',
          myRole: GroupRole.member,
        ),
      );
      await msgRepo.saveMessage(_makeRetryEligible('pgc010-inbox-b3'));

      final markerMayFinish = Completer<void>();
      final markerCommitted = Completer<void>();
      final markerFuture = runGroupMembershipMutationLocked(
        groupId: 'group-1',
        action: () async {
          final current = await groupRepo.getGroup('group-1');
          await groupRepo.updateGroup(
            current!.copyWith(selfRemovedAt: DateTime.utc(2026, 7, 20, 9, 3)),
          );
          markerCommitted.complete();
          await markerMayFinish.future;
        },
      );
      await markerCommitted.future;

      var retryCompleted = false;
      final retryFuture = retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
        groupRepo: groupRepo,
      ).whenComplete(() => retryCompleted = true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(retryCompleted, isFalse, reason: 'repush must queue behind B3');
      expect(bridge.commandLog, isEmpty);

      markerMayFinish.complete();
      await markerFuture;
      expect(await retryFuture, 0);
      expect(bridge.commandLog, isEmpty);
      final saved = await msgRepo.getMessage('pgc010-inbox-b3');
      expect(saved!.inboxStored, isFalse);
      expect(saved.inboxRetryPayload, isNotNull);
    },
  );

  test(
    'EK004 retry preserves signed group offline replay envelope fields',
    () async {
      final msg = _makeRetryEligible(
        'msg-ek004-retry',
        inboxRetryPayload: _signedReplayRetryPayload(
          messageId: 'msg-ek004-retry',
        ),
      );
      await msgRepo.saveMessage(msg);

      final retried = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
      );

      expect(retried, 1);
      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      final replayEnvelope =
          jsonDecode(payload['message'] as String) as Map<String, dynamic>;
      expect(replayEnvelope['signatureAlgorithm'], 'ed25519');
      expect(replayEnvelope['signedPayload'], isA<String>());
      expect(replayEnvelope['signature'], 'sig-msg-ek004-retry');
      expect(replayEnvelope['senderPeerId'], 'peer-1');
      expect(replayEnvelope['senderPublicKey'], 'pk-1');
      expect(payload['recipientPeerIds'], ['peer-2']);
      final saved = await msgRepo.getMessage('msg-ek004-retry');
      expect(saved!.inboxRetryPayload, isNull);
    },
  );

  test('retries eligible pending messages and promotes them to sent', () async {
    final msg = _makeRetryEligible('msg-pending', status: 'pending');
    await msgRepo.saveMessage(msg);

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
    );

    expect(retried, 1);
    final saved = await msgRepo.getMessage('msg-pending');
    expect(saved, isNotNull);
    expect(saved!.status, 'sent');
    expect(saved.inboxStored, isTrue);
    expect(saved.inboxRetryPayload, isNull);
  });

  // 210b: a 'queued_offline' row (real offline send: publish-without-custody,
  // repush payload armed) is picked up by the same repush pass and settles to
  // 'sent' — this is the live-app clock→tick transition on reconnect.
  test('retries queued_offline messages and promotes them to sent', () async {
    final msg = _makeRetryEligible(
      'msg-queued-offline',
      status: 'queued_offline',
    );
    await msgRepo.saveMessage(msg);

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
    );

    expect(retried, 1);
    final saved = await msgRepo.getMessage('msg-queued-offline');
    expect(saved, isNotNull);
    expect(saved!.status, 'sent');
    expect(saved.inboxStored, isTrue);
    expect(saved.inboxRetryPayload, isNull);
  });

  test(
    'IR-007 inbox retry sends same pending message id once without duplicate rows',
    () async {
      final msg = _makeRetryEligible(
        'ir007-pending-retry-id',
        status: 'pending',
      );
      await msgRepo.saveMessage(msg);

      final retried = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
      );

      expect(retried, 1);
      expect(_inboxStoreMessageIds(bridge), ['ir007-pending-retry-id']);
      final saved = await msgRepo.getMessage('ir007-pending-retry-id');
      expect(saved, isNotNull);
      expect(saved!.id, 'ir007-pending-retry-id');
      expect(saved.status, 'sent');
      expect(saved.inboxStored, isTrue);
      expect(saved.inboxRetryPayload, isNull);
      final page = await msgRepo.getMessagesPage('group-1');
      expect(
        page.where(
          (row) => !row.isIncoming && row.id == 'ir007-pending-retry-id',
        ),
        hasLength(1),
      );

      final secondPass = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
      );
      expect(secondPass, 0);
      expect(_inboxStoreMessageIds(bridge), ['ir007-pending-retry-id']);
    },
  );

  test(
    'UP-008 restart retry promotes pending outbound row without duplicate rows',
    () async {
      await msgRepo.saveMessage(
        _makeRetryEligible('up008-pending-restart-id', status: 'pending'),
      );

      final restartedBridge = FakeBridge();
      final retried = await retryFailedGroupInboxStores(
        bridge: restartedBridge,
        msgRepo: msgRepo,
      );

      expect(retried, 1);
      expect(_inboxStoreMessageIds(restartedBridge), [
        'up008-pending-restart-id',
      ]);
      final saved = await msgRepo.getMessage('up008-pending-restart-id');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.inboxStored, isTrue);
      expect(saved.inboxRetryPayload, isNull);
      final page = await msgRepo.getMessagesPage('group-1');
      expect(
        page.where(
          (row) => !row.isIncoming && row.id == 'up008-pending-restart-id',
        ),
        hasLength(1),
      );

      final secondRestartPass = await retryFailedGroupInboxStores(
        bridge: FakeBridge(),
        msgRepo: msgRepo,
      );
      expect(secondRestartPass, 0);
    },
  );

  test('GO-002 retry promotes pending inbox store failure to sent', () async {
    final msg = _makeRetryEligible('go002-pending', status: 'pending');
    await msgRepo.saveMessage(msg);

    late int retried;
    final events = await captureFlowEvents(() async {
      retried = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
      );
    });

    expect(retried, 1);
    final saved = await msgRepo.getMessage('go002-pending');
    expect(saved, isNotNull);
    expect(saved!.status, 'sent');
    expect(saved.inboxStored, isTrue);
    expect(saved.inboxRetryPayload, isNull);
    expect(_inboxStoreMessageIds(bridge), <String>['go002-pending']);

    final ok = events.firstWhere(
      (event) => event['event'] == 'RETRY_FAILED_GROUP_INBOX_STORE_OK',
    );
    expect(ok['details']['messageId'], 'go002-pe');
    final timing = events.lastWhere(
      (event) => event['event'] == 'RETRY_FAILED_GROUP_INBOX_STORES_TIMING',
    );
    expect(timing['details']['outcome'], 'complete');
    expect(timing['details']['total'], 1);
    expect(timing['details']['retried'], 1);
  });

  test('skips messages that are already inbox_stored', () async {
    final msg = _makeRetryEligible('msg-stored', inboxStored: true);
    await msgRepo.saveMessage(msg);

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
    );

    expect(retried, 0);
    expect(bridge.commandLog, isEmpty);
  });

  test('handles callGroupInboxStore failure gracefully', () async {
    final failBridge = _FailFirstNInboxBridge(failCount: 1);
    final msg1 = _makeRetryEligible('msg-fail');
    final msg2 = _makeRetryEligible('msg-ok');
    await msgRepo.saveMessage(msg1);
    await msgRepo.saveMessage(msg2);

    late int retried;
    final events = await captureFlowEvents(() async {
      retried = await retryFailedGroupInboxStores(
        bridge: failBridge,
        msgRepo: msgRepo,
      );
    });

    // First fails, second succeeds
    expect(retried, 1);
    final saved1 = await msgRepo.getMessage('msg-fail');
    expect(saved1!.inboxStored, isFalse);
    expect(saved1.status, 'sent');
    expect(saved1.inboxRetryPayload, isNotNull);
    final saved2 = await msgRepo.getMessage('msg-ok');
    expect(saved2!.inboxStored, isTrue);
    expect(saved2.status, 'sent');
    expect(saved2.inboxRetryPayload, isNull);

    final errorEvent = events.firstWhere(
      (event) => event['event'] == 'RETRY_FAILED_GROUP_INBOX_STORE_ERROR',
    );
    expect(errorEvent['details']['messageId'], 'msg-fail');
    expect(
      errorEvent['details']['error'],
      contains('Simulated inbox store failure #1'),
    );

    final okEvent = events.firstWhere(
      (event) => event['event'] == 'RETRY_FAILED_GROUP_INBOX_STORE_OK',
    );
    expect(okEvent['details']['messageId'], 'msg-ok');
  });

  test(
    'BB-013 group:inboxStore timeout leaves the row retryable and not marked stored',
    () async {
      final timeoutBridge = _TimeoutInboxStoreBridge();
      final msg = _makeRetryEligible('msg-bb013-timeout');
      await msgRepo.saveMessage(msg);

      late int retried;
      final events = await captureFlowEvents(() async {
        retried = await retryFailedGroupInboxStores(
          bridge: timeoutBridge,
          msgRepo: msgRepo,
        );
      });

      expect(retried, 0);
      expect(timeoutBridge.commandLog, ['group:inboxStore']);
      final saved = await msgRepo.getMessage('msg-bb013-timeout');
      expect(saved, isNotNull);
      expect(saved!.inboxStored, isFalse);
      expect(saved.status, 'sent');
      expect(saved.inboxRetryPayload, isNotNull);

      final errorEvent = events.firstWhere(
        (event) => event['event'] == 'RETRY_FAILED_GROUP_INBOX_STORE_ERROR',
      );
      expect(errorEvent['details']['messageId'], 'msg-bb01');
      expect(errorEvent['details']['error'], contains('TimeoutException'));
    },
  );

  test('respects batch limit', () async {
    // Create 25 retry-eligible messages
    for (var i = 0; i < 25; i++) {
      await msgRepo.saveMessage(_makeRetryEligible('msg-$i'));
    }

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
      limit: 20,
    );

    expect(retried, 20);
    // Verify exactly 20 inboxStore calls
    final inboxCalls = bridge.commandLog
        .where((c) => c == 'group:inboxStore')
        .length;
    expect(inboxCalls, 20);
  });

  test(
    'deterministic restart retry drains message inbox rows before reaction rows',
    () async {
      await msgRepo.saveMessage(
        _makeRetryEligible(
          'msg-later',
          timestamp: DateTime.utc(2026, 1, 15, 12, 2),
        ),
      );
      await msgRepo.saveMessage(
        _makeRetryEligible(
          'msg-beta',
          timestamp: DateTime.utc(2026, 1, 15, 12, 1),
        ),
      );
      await msgRepo.saveMessage(
        _makeRetryEligible(
          'msg-alpha',
          timestamp: DateTime.utc(2026, 1, 15, 12, 1),
        ),
      );
      await reactionReplayOutboxRepo.saveEntry(
        _makeReactionRetryEntry(
          'rx-later',
          createdAt: DateTime.utc(2026, 1, 15, 12, 4),
        ),
      );
      await reactionReplayOutboxRepo.saveEntry(
        _makeReactionRetryEntry(
          'rx-earlier',
          createdAt: DateTime.utc(2026, 1, 15, 12, 3),
        ),
      );

      final retried = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        limit: 5,
      );

      expect(retried, 5);
      expect(_inboxStoreMessageIds(bridge), [
        'msg-alpha',
        'msg-beta',
        'msg-later',
        'rx-earlier',
        'rx-later',
      ]);
      expect((await msgRepo.getMessage('msg-alpha'))!.inboxStored, isTrue);
      expect((await msgRepo.getMessage('msg-beta'))!.inboxStored, isTrue);
      expect((await msgRepo.getMessage('msg-later'))!.inboxStored, isTrue);
      expect(
        (await reactionReplayOutboxRepo.getEntry('rx-earlier'))!.deliveryStatus,
        GroupReactionReplayOutboxStatus.stored,
      );
      expect(
        (await reactionReplayOutboxRepo.getEntry('rx-later'))!.deliveryStatus,
        GroupReactionReplayOutboxStatus.stored,
      );
    },
  );

  test('retries reaction replay outbox rows and marks them stored', () async {
    await reactionReplayOutboxRepo.saveEntry(_makeReactionRetryEntry('rx-add'));
    await reactionReplayOutboxRepo.saveEntry(
      _makeReactionRetryEntry(
        'rx-remove',
        action: 'remove',
        deliveryStatus: GroupReactionReplayOutboxStatus.pending,
      ),
    );

    late int retried;
    final events = await captureFlowEvents(() async {
      retried = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      );
    });

    expect(retried, 2);
    expect(
      bridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
      hasLength(2),
    );

    final addEntry = await reactionReplayOutboxRepo.getEntry('rx-add');
    final removeEntry = await reactionReplayOutboxRepo.getEntry('rx-remove');
    expect(addEntry, isNotNull);
    expect(removeEntry, isNotNull);
    expect(addEntry!.deliveryStatus, GroupReactionReplayOutboxStatus.stored);
    expect(removeEntry!.deliveryStatus, GroupReactionReplayOutboxStatus.stored);
    expect(
      await reactionReplayOutboxRepo.loadRetryableEntries(limit: 10),
      isEmpty,
    );

    final okEvents = events
        .where(
          (event) => event['event'] == 'RETRY_FAILED_GROUP_REACTION_REPLAY_OK',
        )
        .toList();
    expect(okEvents, hasLength(2));

    final done = events.firstWhere(
      (event) => event['event'] == 'RETRY_FAILED_GROUP_INBOX_STORES_DONE',
    );
    expect(done['details']['messageTotal'], 0);
    expect(done['details']['reactionTotal'], 2);
    expect(done['details']['retried'], 2);
  });

  test(
    'legacy empty-recipient reaction row is retired without a bridge call',
    () async {
      final legacy = _makeReactionRetryEntry('rx-empty-recipients').copyWith(
        inboxRetryPayload: jsonEncode({
          'groupId': 'group-1',
          'message': jsonEncode({
            'kind': 'group_offline_replay',
            'version': 1,
            'payloadType': 'group_reaction',
            'messageId': 'rx-empty-recipients',
            'ciphertext': 'opaque-ciphertext',
            'nonce': 'opaque-nonce',
          }),
        }),
      );
      await reactionReplayOutboxRepo.saveEntry(legacy);

      late int retried;
      final firstPassEvents = await captureFlowEvents(() async {
        retried = await retryFailedGroupInboxStores(
          bridge: bridge,
          msgRepo: msgRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        );
      });

      expect(retried, 0);
      expect(
        bridge.commandLog.where((command) => command == 'group:inboxStore'),
        isEmpty,
      );
      expect(reactionReplayOutboxRepo.deleteEntryCallCount, 1);
      expect(
        await reactionReplayOutboxRepo.getEntry('rx-empty-recipients'),
        isNull,
      );
      expect(
        await reactionReplayOutboxRepo.loadRetryableEntries(limit: 10),
        isEmpty,
      );
      expect(
        firstPassEvents.where(
          (event) => event['event'] == 'GROUP_REACTION_CUSTODY_UNROUTABLE',
        ),
        hasLength(1),
      );
      expect(
        firstPassEvents.where(
          (event) => event['event'] == 'GROUP_FL_BRIDGE_INBOX_STORE_REQUEST',
        ),
        isEmpty,
      );

      expect(
        await retryFailedGroupInboxStores(
          bridge: bridge,
          msgRepo: msgRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        ),
        0,
      );
      expect(reactionReplayOutboxRepo.deleteEntryCallCount, 1);
    },
  );

  test(
    'reaction replay completion cannot settle a replacement with the same id',
    () async {
      final loaded = _makeReactionRetryEntry('rx-replaced');
      await reactionReplayOutboxRepo.saveEntry(loaded);
      final replacement = loaded.copyWith(
        action: 'remove',
        emoji: ':remove:',
        inboxRetryPayload: '${loaded.inboxRetryPayload} ',
        deliveryStatus: GroupReactionReplayOutboxStatus.pending,
        lastError: null,
        updatedAt: '2026-01-15T12:01:00.000Z',
      );
      final replacingBridge = _ReplaceReactionRowOnStoreBridge(
        repository: reactionReplayOutboxRepo,
        replacement: replacement,
      );

      expect(
        await retryFailedGroupInboxStores(
          bridge: replacingBridge,
          msgRepo: msgRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        ),
        0,
      );
      final current = await reactionReplayOutboxRepo.getEntry('rx-replaced');
      expect(current!.action, 'remove');
      expect(current.deliveryStatus, GroupReactionReplayOutboxStatus.pending);
      expect(current.updatedAt, replacement.updatedAt);
    },
  );

  test(
    'reaction replay retry failure leaves the row failed and continues to later rows',
    () async {
      final failBridge = _FailFirstNInboxBridge(failCount: 1);
      await reactionReplayOutboxRepo.saveEntry(
        _makeReactionRetryEntry('rx-fail'),
      );
      await reactionReplayOutboxRepo.saveEntry(
        _makeReactionRetryEntry('rx-ok'),
      );

      late int retried;
      final events = await captureFlowEvents(() async {
        retried = await retryFailedGroupInboxStores(
          bridge: failBridge,
          msgRepo: msgRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        );
      });

      expect(retried, 1);

      final failedEntry = await reactionReplayOutboxRepo.getEntry('rx-fail');
      final storedEntry = await reactionReplayOutboxRepo.getEntry('rx-ok');
      expect(failedEntry, isNotNull);
      expect(storedEntry, isNotNull);
      expect(
        failedEntry!.deliveryStatus,
        GroupReactionReplayOutboxStatus.failed,
      );
      expect(
        failedEntry.lastError,
        contains('Simulated inbox store failure #1'),
      );
      expect(
        storedEntry!.deliveryStatus,
        GroupReactionReplayOutboxStatus.stored,
      );

      final errorEvent = events.firstWhere(
        (event) => event['event'] == 'RETRY_FAILED_GROUP_REACTION_REPLAY_ERROR',
      );
      expect(errorEvent['details']['reactionId'], 'rx-fail');

      final okEvent = events.firstWhere(
        (event) => event['event'] == 'RETRY_FAILED_GROUP_REACTION_REPLAY_OK',
      );
      expect(okEvent['details']['reactionId'], 'rx-ok');
    },
  );

  test('returns 0 when no eligible messages', () async {
    // incoming message — not eligible
    await msgRepo.saveMessage(
      _makeRetryEligible('msg-incoming', isIncoming: true),
    );
    // already stored — not eligible
    await msgRepo.saveMessage(
      _makeRetryEligible('msg-stored', inboxStored: true),
    );
    // failed status — not eligible
    await msgRepo.saveMessage(
      _makeRetryEligible('msg-failed', status: 'failed'),
    );

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
    );

    expect(retried, 0);
    expect(bridge.commandLog, isEmpty);
  });

  test('skips legacy rows with null inbox_retry_payload', () async {
    final legacyMsg = GroupMessage(
      id: 'msg-legacy',
      groupId: 'group-1',
      senderPeerId: 'peer-1',
      senderUsername: 'Alice',
      text: 'Legacy message',
      timestamp: DateTime.utc(2026, 1, 15),
      status: 'sent',
      isIncoming: false,
      createdAt: DateTime.utc(2026, 1, 15),
      inboxStored: false,
      inboxRetryPayload: null,
    );
    await msgRepo.saveMessage(legacyMsg);

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
    );

    expect(retried, 0);
    expect(bridge.commandLog, isEmpty);
  });
}
