import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_pending_key_repair_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

/// Seeds a group + member + (optionally) key, builds a real signed offline
/// replay envelope, and persists a pending repair + placeholder for it, then
/// returns a runner wired to those repos. Used by the UDM-C classification
/// matrix to drive `_retryOne` through real decrypt/verify error paths.
Future<GroupPendingKeyRepairRunner> _seedKeyedGroupRepair({
  required FakeBridge bridge,
  required InMemoryGroupRepository groupRepo,
  required InMemoryGroupMessageRepository msgRepo,
  required InMemoryGroupPendingKeyRepairRepository pendingRepo,
  required String repairId,
  required String messageId,
  int keyEpoch = 1,
  int attempts = 0,
  bool saveKey = true,
  ReplayGroupEnvelope? replayGroupEnvelope,
}) async {
  final createdAt = DateTime.utc(2026, 5, 2);
  await groupRepo.saveGroup(
    GroupModel(
      id: 'group-1',
      name: 'Test Group',
      type: GroupType.chat,
      topicName: '/mknoon/group/group-1',
      createdAt: createdAt,
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    ),
  );
  await groupRepo.saveMember(
    GroupMember(
      groupId: 'group-1',
      peerId: 'peer-sender',
      username: 'Sender',
      role: MemberRole.writer,
      publicKey: 'pk-sender',
      joinedAt: createdAt,
    ),
  );
  final keyInfo = GroupKeyInfo(
    groupId: 'group-1',
    keyGeneration: keyEpoch,
    encryptedKey: 'replay-key-$keyEpoch',
    createdAt: createdAt,
  );
  if (saveKey) {
    await groupRepo.saveKey(keyInfo);
  }
  final envelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: 'group-1',
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: jsonEncode({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'keyEpoch': keyEpoch,
      'text': 'recovered message',
      'timestamp': '2026-05-02T08:00:00.000Z',
      'messageId': messageId,
    }),
    messageId: messageId,
    senderPeerId: 'peer-sender',
    senderPublicKey: 'pk-sender',
    senderPrivateKey: 'sk-sender',
    keyInfo: keyInfo,
  );
  await pendingRepo.upsertPendingRepair(
    GroupPendingKeyRepair(
      id: repairId,
      groupId: 'group-1',
      messageId: messageId,
      senderPeerId: 'peer-sender',
      transportPeerId: 'peer-sender',
      payloadType: groupOfflineReplayPayloadTypeMessage,
      keyEpoch: keyEpoch,
      replayEnvelopeJson: envelope,
      status: groupPendingKeyRepairStatusPendingKey,
      attempts: attempts,
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
  );
  await msgRepo.saveMessage(
    GroupMessage(
      id: messageId,
      groupId: 'group-1',
      senderPeerId: 'peer-sender',
      transportPeerId: 'peer-sender',
      senderUsername: null,
      text: groupPendingKeyRepairPlaceholderText,
      timestamp: createdAt,
      keyGeneration: keyEpoch,
      status: groupPendingKeyRepairStatusPendingKey,
      isIncoming: true,
      createdAt: createdAt,
    ),
  );
  return GroupPendingKeyRepairRunner(
    bridge: bridge,
    groupRepo: groupRepo,
    msgRepo: msgRepo,
    pendingKeyRepairRepo: pendingRepo,
    replayGroupEnvelope: replayGroupEnvelope,
  );
}

void main() {
  test(
    'live decrypt repair without replay envelope records waiting attempt and stays pending',
    () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final pendingRepo = InMemoryGroupPendingKeyRepairRepository();
      final now = DateTime.utc(2026, 5, 24, 12);
      final repairId = liveGroupPendingKeyRepairId(
        groupId: 'group-1',
        senderPeerId: 'peer-sender',
        keyEpoch: 2,
        localKeyEpoch: 1,
      );

      await pendingRepo.upsertPendingRepair(
        GroupPendingKeyRepair(
          id: repairId,
          groupId: 'group-1',
          messageId: repairId,
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          keyEpoch: 2,
          replayEnvelopeJson: null,
          status: groupPendingKeyRepairStatusPendingKey,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await msgRepo.saveMessage(
        GroupMessage(
          id: repairId,
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          senderUsername: null,
          text: groupPendingKeyRepairPlaceholderText,
          timestamp: now,
          keyGeneration: 2,
          status: groupPendingKeyRepairStatusPendingKey,
          isIncoming: true,
          createdAt: now,
        ),
      );

      final runner = GroupPendingKeyRepairRunner(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingKeyRepairRepo: pendingRepo,
        nowUtc: () => now, // within TTL: assert the waiting (not self-clear) path
      );

      final repairedCount = await runner.retryPendingRepairsForKey(
        groupId: 'group-1',
        keyEpoch: 2,
      );

      expect(repairedCount, 0);
      final repair = await pendingRepo.getRepair(repairId);
      expect(repair, isNotNull);
      expect(repair!.status, groupPendingKeyRepairStatusPendingKey);
      expect(repair.finalizedAt, isNull);
      expect(repair.attempts, 1);
      expect(repair.lastError, 'waiting for replay envelope');

      final placeholder = await msgRepo.getMessage(repairId);
      expect(placeholder, isNotNull);
      expect(placeholder!.status, groupPendingKeyRepairStatusPendingKey);
      expect(placeholder.text, groupPendingKeyRepairPlaceholderText);
      expect(bridge.commandLog, isNot(contains('group.decrypt')));
    },
  );

  test(
    'retryAllPending sweeps pending repairs across all groups and epochs and '
    'reuses _retryOne semantics (waiting repairs stay pending)',
    () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final pendingRepo = InMemoryGroupPendingKeyRepairRepository();
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final now = DateTime.utc(2026, 5, 24, 12);

      // Two null-envelope pending repairs in DIFFERENT groups/epochs — a
      // per-(group,epoch) retry could never reach both in a single pass.
      const ids = ['live:group-1:peer-a:2:1', 'live:group-2:peer-b:7:1'];
      await pendingRepo.upsertPendingRepair(
        GroupPendingKeyRepair(
          id: ids[0],
          groupId: 'group-1',
          messageId: ids[0],
          senderPeerId: 'peer-a',
          transportPeerId: 'peer-a',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          keyEpoch: 2,
          replayEnvelopeJson: null,
          status: groupPendingKeyRepairStatusPendingKey,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await pendingRepo.upsertPendingRepair(
        GroupPendingKeyRepair(
          id: ids[1],
          groupId: 'group-2',
          messageId: ids[1],
          senderPeerId: 'peer-b',
          transportPeerId: 'peer-b',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          keyEpoch: 7,
          replayEnvelopeJson: null,
          status: groupPendingKeyRepairStatusPendingKey,
          createdAt: now.add(const Duration(seconds: 1)),
          updatedAt: now.add(const Duration(seconds: 1)),
        ),
      );

      final runner = GroupPendingKeyRepairRunner(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingKeyRepairRepo: pendingRepo,
        // within TTL of both seeded createdAts: assert the waiting (not
        // self-clear) path so the sweep's _retryOne reuse is what's measured.
        nowUtc: () => now.add(const Duration(seconds: 5)),
      );

      final repaired = await runner.retryAllPending();

      // Null-envelope repairs stay pending (waiting), proving _retryOne reuse.
      expect(repaired, 0);
      for (final id in ids) {
        final repair = await pendingRepo.getRepair(id);
        expect(repair, isNotNull);
        expect(repair!.status, groupPendingKeyRepairStatusPendingKey);
        expect(repair.finalizedAt, isNull);
        expect(repair.attempts, 1);
        expect(repair.lastError, 'waiting for replay envelope');
      }
      // The sweep scanned BOTH cross-group/epoch repairs (not just one
      // group+epoch) and emitted its event with accurate counts.
      final sweepEvents = flowEvents
          .where((e) => e['event'] == 'GROUP_PENDING_KEY_REPAIR_SWEEP')
          .toList();
      expect(sweepEvents, hasLength(1));
      expect(sweepEvents.single['details']['scanned'], 2);
      expect(sweepEvents.single['details']['repaired'], 0);
      expect(bridge.commandLog, isNot(contains('group.decrypt')));
    },
  );

  // ---- UDM-C: bounded, classified "undecryptable" finalization (§H) ----

  test(
    'UDM-C confirmed crypto failure with key present below the cap stays '
    'pending (not finalized)',
    () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final pendingRepo = InMemoryGroupPendingKeyRepairRepository();
      final runner = await _seedKeyedGroupRepair(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingRepo: pendingRepo,
        repairId: 'offline:group-1:udmc-soft',
        messageId: 'udmc-soft',
        attempts: 3,
      );
      // Force an authenticity failure (signature_invalid) on replay.
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};

      final repaired = await runner.retryPendingRepairsForKey(
        groupId: 'group-1',
        keyEpoch: 1,
      );

      expect(repaired, 0);
      final repair = await pendingRepo.getRepair('offline:group-1:udmc-soft');
      expect(repair!.status, groupPendingKeyRepairStatusPendingKey);
      expect(repair.finalizedAt, isNull);
      expect(repair.attempts, 4); // one increment this cycle, not finalized
      final message = await msgRepo.getMessage('udmc-soft');
      expect(message!.text, groupPendingKeyRepairPlaceholderText);
    },
  );

  test(
    'UDM-C confirmed crypto failure with key present at the cap finalizes '
    'undecryptable (the only terminal path)',
    () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final pendingRepo = InMemoryGroupPendingKeyRepairRepository();
      final runner = await _seedKeyedGroupRepair(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingRepo: pendingRepo,
        repairId: 'offline:group-1:udmc-hard',
        messageId: 'udmc-hard',
        attempts: kGroupKeyRepairMaxAttempts,
      );
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};

      await runner.retryPendingRepairsForKey(groupId: 'group-1', keyEpoch: 1);

      final repair = await pendingRepo.getRepair('offline:group-1:udmc-hard');
      expect(repair!.status, groupPendingKeyRepairStatusUndecryptable);
      expect(repair.finalizedAt, isNotNull);
      final message = await msgRepo.getMessage('udmc-hard');
      expect(message!.text, 'Message could not be decrypted.');
    },
  );

  test(
    'UDM-C transient bridge decrypt failure (BRIDGE_TIMEOUT) stays pending',
    () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final pendingRepo = InMemoryGroupPendingKeyRepairRepository();
      final runner = await _seedKeyedGroupRepair(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingRepo: pendingRepo,
        repairId: 'offline:group-1:udmc-transient',
        messageId: 'udmc-transient',
      );
      // Signature verifies, but decrypt fails transiently.
      bridge.responses['group.decrypt'] = {
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
      };

      await runner.retryPendingRepairsForKey(groupId: 'group-1', keyEpoch: 1);

      final repair = await pendingRepo.getRepair(
        'offline:group-1:udmc-transient',
      );
      expect(repair!.status, groupPendingKeyRepairStatusPendingKey);
      expect(repair.finalizedAt, isNull);
      expect(repair.attempts, 1);
      final message = await msgRepo.getMessage('udmc-transient');
      expect(message!.text, groupPendingKeyRepairPlaceholderText);
    },
  );

  test(
    'UDM-C missing key is never terminal even at a high attempt count',
    () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final pendingRepo = InMemoryGroupPendingKeyRepairRepository();
      // Envelope built with an explicit key, but the key is NOT in the repo.
      final runner = await _seedKeyedGroupRepair(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingRepo: pendingRepo,
        repairId: 'offline:group-1:udmc-nokey',
        messageId: 'udmc-nokey',
        attempts: 10,
        saveKey: false,
      );

      await runner.retryPendingRepairsForKey(groupId: 'group-1', keyEpoch: 1);

      final repair = await pendingRepo.getRepair('offline:group-1:udmc-nokey');
      expect(repair!.status, groupPendingKeyRepairStatusPendingKey);
      expect(repair.finalizedAt, isNull);
    },
  );

  test(
    'UDM-C a post-decrypt non-crypto error (StateError) stays pending',
    () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final pendingRepo = InMemoryGroupPendingKeyRepairRepository();
      final runner = await _seedKeyedGroupRepair(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingRepo: pendingRepo,
        repairId: 'offline:group-1:udmc-statelerr',
        messageId: 'udmc-statelerr',
        // Decrypt succeeds, then the injected replay step throws a non-crypto
        // ordering error — must NOT finalize (the §H bug finalized on this).
        replayGroupEnvelope: (_) async =>
            throw StateError('replay validation rejected'),
      );

      await runner.retryPendingRepairsForKey(groupId: 'group-1', keyEpoch: 1);

      final repair = await pendingRepo.getRepair(
        'offline:group-1:udmc-statelerr',
      );
      expect(repair!.status, groupPendingKeyRepairStatusPendingKey);
      expect(repair.finalizedAt, isNull);
      expect(repair.attempts, 1);
    },
  );

  test('UDM-C does not double-count attempts across transient cycles', () async {
    final bridge = FakeBridge();
    final groupRepo = InMemoryGroupRepository();
    final msgRepo = InMemoryGroupMessageRepository();
    final pendingRepo = InMemoryGroupPendingKeyRepairRepository();
    final runner = await _seedKeyedGroupRepair(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      pendingRepo: pendingRepo,
      repairId: 'offline:group-1:udmc-count',
      messageId: 'udmc-count',
    );
    bridge.responses['group.decrypt'] = {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
    };

    await runner.retryPendingRepairsForKey(groupId: 'group-1', keyEpoch: 1);
    await runner.retryPendingRepairsForKey(groupId: 'group-1', keyEpoch: 1);

    final repair = await pendingRepo.getRepair('offline:group-1:udmc-count');
    expect(repair!.attempts, 2); // exactly one increment per cycle
  });

  // ---- UDM-D: TTL self-clear for no-envelope live placeholders (§G tail) ----

  test(
    'UDM-D stale no-envelope live placeholder self-clears (DELETED, not '
    'undecryptable)',
    () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final pendingRepo = InMemoryGroupPendingKeyRepairRepository();
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final now = DateTime.utc(2026, 6, 1, 12);
      final createdAt = now.subtract(const Duration(hours: 25));
      const repairId = 'live:group-1:peer-sender:3:2';
      await pendingRepo.upsertPendingRepair(
        GroupPendingKeyRepair(
          id: repairId,
          groupId: 'group-1',
          messageId: repairId,
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          keyEpoch: 3,
          replayEnvelopeJson: null,
          status: groupPendingKeyRepairStatusPendingKey,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      await msgRepo.saveMessage(
        GroupMessage(
          id: repairId,
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          senderUsername: null,
          text: groupPendingKeyRepairPlaceholderText,
          timestamp: createdAt,
          keyGeneration: 3,
          status: groupPendingKeyRepairStatusPendingKey,
          isIncoming: true,
          createdAt: createdAt,
        ),
      );
      final runner = GroupPendingKeyRepairRunner(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingKeyRepairRepo: pendingRepo,
        nowUtc: () => now,
      );

      await runner.retryPendingRepairsForKey(groupId: 'group-1', keyEpoch: 3);

      expect(await pendingRepo.getRepair(repairId), isNull); // row DELETED
      expect(await msgRepo.getMessage(repairId), isNull); // placeholder gone
      final encoded = jsonEncode(flowEvents);
      expect(encoded, contains('GROUP_PENDING_KEY_REPAIR_SELF_CLEARED'));
      expect(encoded, isNot(contains('WAITING_FOR_REPLAY_ENVELOPE')));
    },
  );

  test(
    'UDM-D a within-TTL no-envelope live placeholder stays pending',
    () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final pendingRepo = InMemoryGroupPendingKeyRepairRepository();

      final now = DateTime.utc(2026, 6, 1, 12);
      final createdAt = now.subtract(const Duration(hours: 1));
      const repairId = 'live:group-1:peer-sender:3:2';
      await pendingRepo.upsertPendingRepair(
        GroupPendingKeyRepair(
          id: repairId,
          groupId: 'group-1',
          messageId: repairId,
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          keyEpoch: 3,
          replayEnvelopeJson: null,
          status: groupPendingKeyRepairStatusPendingKey,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      await msgRepo.saveMessage(
        GroupMessage(
          id: repairId,
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          senderUsername: null,
          text: groupPendingKeyRepairPlaceholderText,
          timestamp: createdAt,
          keyGeneration: 3,
          status: groupPendingKeyRepairStatusPendingKey,
          isIncoming: true,
          createdAt: createdAt,
        ),
      );
      final runner = GroupPendingKeyRepairRunner(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingKeyRepairRepo: pendingRepo,
        nowUtc: () => now,
      );

      await runner.retryPendingRepairsForKey(groupId: 'group-1', keyEpoch: 3);

      final repair = await pendingRepo.getRepair(repairId);
      expect(repair, isNotNull);
      expect(repair!.status, groupPendingKeyRepairStatusPendingKey);
      expect(repair.attempts, 1);
      expect(repair.lastError, 'waiting for replay envelope');
      expect(await msgRepo.getMessage(repairId), isNotNull); // placeholder kept
    },
  );

  test(
    'UDM-D a stale durable (offline, enveloped) repair is never self-cleared',
    () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final pendingRepo = InMemoryGroupPendingKeyRepairRepository();

      final now = DateTime.utc(2026, 6, 1, 12);
      final createdAt = now.subtract(const Duration(hours: 48));
      const repairId = 'offline:group-1:durable-1';
      await pendingRepo.upsertPendingRepair(
        GroupPendingKeyRepair(
          id: repairId,
          groupId: 'group-1',
          messageId: 'durable-1',
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          keyEpoch: 3,
          // Non-null envelope ⇒ durable; TTL self-clear must NOT touch it.
          replayEnvelopeJson: '{"kind":"group_offline_replay"}',
          status: groupPendingKeyRepairStatusPendingKey,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      final runner = GroupPendingKeyRepairRunner(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingKeyRepairRepo: pendingRepo,
        nowUtc: () => now,
      );

      await runner.retryPendingRepairsForKey(groupId: 'group-1', keyEpoch: 3);

      // No key present ⇒ stays pending (requeued), but crucially NOT deleted.
      final repair = await pendingRepo.getRepair(repairId);
      expect(repair, isNotNull);
      expect(repair!.status, groupPendingKeyRepairStatusPendingKey);
    },
  );
}
