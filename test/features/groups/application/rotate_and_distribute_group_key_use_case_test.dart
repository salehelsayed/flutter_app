import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_key_update_signature.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late PassthroughCryptoBridge bridge;
  late InMemoryGroupRepository groupRepo;

  const selfPeerId = 'peer-self';
  const groupId = 'group-1';

  setUp(() async {
    bridge = PassthroughCryptoBridge();
    groupRepo = InMemoryGroupRepository();

    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Test Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: DateTime.now().toUtc(),
        createdBy: selfPeerId,
        myRole: GroupRole.admin,
      ),
    );

    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: selfPeerId,
        username: 'Self',
        role: MemberRole.admin,
        publicKey: 'selfPubKey',
        mlKemPublicKey: 'selfMlKem',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-bob',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'bobPubKey',
        mlKemPublicKey: 'bobMlKem',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-carol',
        username: 'Carol',
        role: MemberRole.writer,
        publicKey: 'carolPubKey',
        mlKemPublicKey: 'carolMlKem',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'oldKey==',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    bridge.responses['group:generateNextKey'] = {
      'ok': true,
      'groupKey': 'newKey==',
      'keyEpoch': 2,
    };

    bridge.responses['group:publish'] = {'ok': true, 'messageId': 'sys-msg-id'};
  });

  test(
    'OB-002 key generation failure emits safe group and epoch metadata',
    () async {
      const obGroupId = 'group-ob002-key-rotation';
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      await groupRepo.saveGroup(
        GroupModel(
          id: obGroupId,
          name: 'OB-002 Key Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$obGroupId',
          createdAt: DateTime.utc(2026, 5, 14, 6, 52),
          createdBy: selfPeerId,
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: obGroupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'selfPubKey',
          mlKemPublicKey: 'selfMlKem',
          joinedAt: DateTime.utc(2026, 5, 14, 6, 52),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: obGroupId,
          keyGeneration: 4,
          encryptedKey: 'epoch4Key==',
          createdAt: DateTime.utc(2026, 5, 14, 6, 52),
        ),
      );
      bridge.responses['group:generateNextKey'] = {
        'ok': false,
        'errorCode': 'KEYGEN_FAILED',
        'errorMessage': 'generator unavailable',
      };

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: obGroupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: _sendOk,
      );

      expect(result, isNull);
      final event = flowEvents.singleWhere(
        (event) => event['event'] == 'GROUP_ROTATE_KEY_BRIDGE_ERROR',
      );
      final details = event['details'] as Map<String, dynamic>;
      expect(details['groupId'], obGroupId.substring(0, 8));
      expect(details['keyEpoch'], 5);
      expect(details['membershipOperationId'], 'rotate:group-ob:peer-sel');
      expect(details['errorCode'], 'KEYGEN_FAILED');

      final encoded = jsonEncode(details);
      expect(encoded, isNot(contains(obGroupId)));
    },
  );

  test(
    'allows writer with rotate permission override to rotate keys',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(rotateKeys: true),
          publicKey: 'selfPubKey',
          mlKemPublicKey: 'selfMlKem',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: _sendOk,
      );

      expect(result, isNotNull);
      expect(result!.keyGeneration, 2);
      expect(bridge.commandLog, contains('group:generateNextKey'));

      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 2);
    },
  );

  test('denies admin whose rotate permission override is false', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: selfPeerId,
        username: 'Self',
        role: MemberRole.admin,
        permissions: const GroupMemberPermissions(rotateKeys: false),
        publicKey: 'selfPubKey',
        mlKemPublicKey: 'selfMlKem',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: _sendOk,
    );

    expect(result, isNull);
    expect(bridge.commandLog, isEmpty);

    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
  });

  test('GKR-001 non-owner admin cannot rotate group key', () async {
    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Test Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-owner',
        myRole: GroupRole.admin,
      ),
    );

    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: selfPeerId,
        username: 'Self',
        role: MemberRole.admin,
        publicKey: 'selfPubKey',
        mlKemPublicKey: 'selfMlKem',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: _sendOk,
    );

    expect(result, isNull);
    expect(bridge.commandLog, isEmpty);

    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
    expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);
    expect(await groupRepo.getPendingKeyRotation(groupId), isNull);
  });

  test('ML-013 bare writer and removed peer cannot rotate keys', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: selfPeerId,
        username: 'Self',
        role: MemberRole.writer,
        publicKey: 'selfPubKey',
        mlKemPublicKey: 'selfMlKem',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    final writerResult = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: _sendOk,
    );

    expect(writerResult, isNull);
    expect(bridge.commandLog, isNot(contains('group:generateNextKey')));
    expect(bridge.commandLog, isNot(contains('group:updateKey')));
    var latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);

    bridge.commandLog.clear();
    bridge.sentMessages.clear();

    final removedResult = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: 'peer-removed',
      senderPublicKey: 'removedPubKey',
      senderPrivateKey: 'removedPrivKey',
      senderUsername: 'Removed',
    );

    expect(removedResult, isNull);
    expect(bridge.commandLog, isNot(contains('group:generateNextKey')));
    expect(bridge.commandLog, isNot(contains('group:updateKey')));
    latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
    expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);
  });

  test(
    'KE-013 restores persisted current epoch before generate after restart memory loss',
    () async {
      bridge = _RestartEmptyGenerateBridge();
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 7,
          encryptedKey: 'epoch7Key==',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final sentP2P = <(String, String)>[];

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: (peerId, message) async {
          sentP2P.add((peerId, message));
          return true;
        },
      );

      expect(result, isNotNull);
      expect(result!.keyGeneration, 8);
      expect(result.encryptedKey, 'epoch8Key==');

      final restoreIdx = _bridgeCommandIndex(
        bridge,
        'group:updateKey',
        keyEpoch: 7,
      );
      final generateIdx = _bridgeCommandIndex(bridge, 'group:generateNextKey');
      final firstEncryptIdx = _bridgeCommandIndex(bridge, 'message.encrypt');
      final promoteIdx = _bridgeCommandIndex(
        bridge,
        'group:updateKey',
        keyEpoch: 8,
      );
      final publishIdx = _bridgeCommandIndex(bridge, 'group:publish');

      expect(restoreIdx, greaterThanOrEqualTo(0));
      expect(generateIdx, greaterThan(restoreIdx));
      expect(firstEncryptIdx, greaterThan(generateIdx));
      expect(promoteIdx, greaterThan(firstEncryptIdx));
      expect(publishIdx, greaterThan(promoteIdx));

      expect(sentP2P, hasLength(2));
      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 8);
      expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);
    },
  );

  test('KE-013 blocks when persisted current key is absent', () async {
    await groupRepo.removeAllKeys(groupId);
    final sentP2P = <(String, String)>[];

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: (peerId, message) async {
        sentP2P.add((peerId, message));
        return true;
      },
    );

    expect(result, isNull);
    expect(bridge.commandLog, isNot(contains('group:updateKey')));
    expect(bridge.commandLog, isNot(contains('group:generateNextKey')));
    expect(bridge.commandLog, isNot(contains('group:publish')));
    expect(sentP2P, isEmpty);
    expect(await groupRepo.getLatestKey(groupId), isNull);
    expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);
  });

  test('KE-013 blocks when persisted current key restore fails', () async {
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 7,
        encryptedKey: 'epoch7Key==',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    bridge.responses['group:updateKey'] = {
      'ok': false,
      'errorCode': 'RESTORE_FAILED',
    };
    final sentP2P = <(String, String)>[];

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: (peerId, message) async {
        sentP2P.add((peerId, message));
        return true;
      },
    );

    expect(result, isNull);
    expect(
      _bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 7),
      greaterThanOrEqualTo(0),
    );
    expect(bridge.commandLog, isNot(contains('group:generateNextKey')));
    expect(bridge.commandLog, isNot(contains('group:publish')));
    expect(sentP2P, isEmpty);
    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 7);
    expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);
  });

  test('KE-013 blocks stale generated epoch after persisted restore', () async {
    bridge = _RestartEmptyGenerateBridge(forceStaleGenerate: true);
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 7,
        encryptedKey: 'epoch7Key==',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final sentP2P = <(String, String)>[];

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: (peerId, message) async {
        sentP2P.add((peerId, message));
        return true;
      },
    );

    expect(result, isNull);
    expect(
      _bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 7),
      greaterThanOrEqualTo(0),
    );
    expect(
      _bridgeCommandIndex(bridge, 'group:generateNextKey'),
      greaterThanOrEqualTo(0),
    );
    expect(_bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2), -1);
    expect(bridge.commandLog, isNot(contains('message.encrypt')));
    expect(bridge.commandLog, isNot(contains('group:publish')));
    expect(sentP2P, isEmpty);

    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 7);
    expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);
  });

  test(
    'rechecks revoked rotate permission before generating a queued key',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(rotateKeys: true),
          publicKey: 'selfPubKey',
          mlKemPublicKey: 'selfMlKem',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.writer,
          publicKey: 'selfPubKey',
          mlKemPublicKey: 'selfMlKem',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: _sendOk,
      );

      expect(result, isNull);
      expect(bridge.commandLog, isEmpty);

      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 1);
    },
  );

  test('promotes generated key only after distribution completes', () async {
    final bobSend = Completer<bool>();
    final carolSend = Completer<bool>();
    addTearDown(() {
      if (!bobSend.isCompleted) bobSend.complete(false);
      if (!carolSend.isCompleted) carolSend.complete(false);
    });

    final pending = rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      perRecipientTimeout: const Duration(milliseconds: 200),
      distributionTimeout: const Duration(milliseconds: 200),
      sendP2PMessage: (peerId, message) {
        if (peerId == 'peer-bob') return bobSend.future;
        if (peerId == 'peer-carol') return carolSend.future;
        return Future.value(true);
      },
    );

    await Future<void>.delayed(Duration.zero);

    final latestBeforePromotion = await groupRepo.getLatestKey(groupId);
    expect(latestBeforePromotion, isNotNull);
    expect(latestBeforePromotion!.keyGeneration, 1);
    expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);

    expect(bridge.commandLog, contains('group:generateNextKey'));
    expect(bridge.commandLog.where((c) => c == 'message.encrypt').length, 1);
    expect(_bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2), -1);
    expect(bridge.commandLog, isNot(contains('group:publish')));

    bobSend.complete(true);
    carolSend.complete(true);

    final result = await pending;

    expect(result, isNotNull);
    expect(result!.keyGeneration, 2);
    expect(result.encryptedKey, 'newKey==');

    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 2);
  });

  test(
    'KE-020 concurrent rotations allocate unique increasing epochs',
    () async {
      bridge = _CommittedEpochGenerateBridge(initialCommittedEpoch: 1);
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'ke020-key-rotated',
      };
      final committedBridge = bridge as _CommittedEpochGenerateBridge;
      final firstSendStarted = Completer<void>();
      final secondRotationDistributedBeforeRelease = Completer<void>();
      final releaseFirstSend = Completer<bool>();
      addTearDown(() {
        if (!releaseFirstSend.isCompleted) releaseFirstSend.complete(false);
      });
      final capturedPayloads = <Map<String, dynamic>>[];
      String? firstBlockedKey;

      Future<bool> captureAndGateSend(String peerId, String message) {
        final payload = _decodeDirectKeyUpdatePayload(message);
        capturedPayloads.add(payload);
        final encryptedKey = payload['encryptedKey'] as String;
        firstBlockedKey ??= encryptedKey;
        if (!firstSendStarted.isCompleted) {
          firstSendStarted.complete();
          return releaseFirstSend.future;
        }
        if (encryptedKey != firstBlockedKey &&
            !releaseFirstSend.isCompleted &&
            !secondRotationDistributedBeforeRelease.isCompleted) {
          secondRotationDistributedBeforeRelease.complete();
        }
        return Future.value(true);
      }

      final firstRotation = rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: captureAndGateSend,
      );

      await firstSendStarted.future.timeout(const Duration(seconds: 1));

      final secondRotation = rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: captureAndGateSend,
      );

      try {
        await secondRotationDistributedBeforeRelease.future.timeout(
          const Duration(milliseconds: 100),
        );
      } on TimeoutException {
        // Green behavior serializes the second rotation until the first one
        // has promoted, saved, and published epoch 2.
      }

      releaseFirstSend.complete(true);
      final results = await Future.wait([
        firstRotation,
        secondRotation,
      ]).timeout(const Duration(seconds: 2));

      expect(results, everyElement(isNotNull));
      expect(results.map((key) => key!.keyGeneration).toList(), [2, 3]);
      expect(results.map((key) => key!.encryptedKey).toSet(), hasLength(2));
      _expectNoSameEpochDifferentKeys(capturedPayloads);

      final payloadEpochs = capturedPayloads
          .map((payload) => payload['keyGeneration'] as int)
          .toSet();
      expect(payloadEpochs, {2, 3});
      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 3);
      expect(latestKey.encryptedKey, results.last!.encryptedKey);

      final firstPublishIndex = committedBridge.eventIndex('publish');
      final secondGenerateIndex = committedBridge.nthEventIndex('generate', 2);
      expect(firstPublishIndex, greaterThanOrEqualTo(0));
      expect(secondGenerateIndex, greaterThan(firstPublishIndex));
    },
  );

  test(
    'NW-013 restart retry reuses pending generated key and eventAt before commit',
    () async {
      bridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': 'nw013-draft-key-a',
        'keyEpoch': 2,
      };
      final capturedPayloads = <Map<String, dynamic>>[];

      final firstResult = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        distributionAttemptCount: 1,
        distributionRetryDelay: Duration.zero,
        sendP2PMessage: (peerId, message) async {
          capturedPayloads.add(_decodeDirectKeyUpdatePayload(message));
          return peerId == 'peer-bob';
        },
      );

      expect(firstResult, isNull);
      final latestAfterFailedDistribution = await groupRepo.getLatestKey(
        groupId,
      );
      expect(latestAfterFailedDistribution, isNotNull);
      expect(latestAfterFailedDistribution!.keyGeneration, 1);
      expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);
      final pendingDraft = await groupRepo.getPendingKeyRotation(groupId);
      expect(pendingDraft, isNotNull);
      expect(pendingDraft!.keyGeneration, 2);
      expect(pendingDraft.encryptedKey, 'nw013-draft-key-a');
      final draftEventAt = pendingDraft.createdAt.toUtc().toIso8601String();

      final retryBridge = PassthroughCryptoBridge();
      retryBridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': 'nw013-draft-key-b',
        'keyEpoch': 2,
      };
      retryBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'nw013-key-rotated',
      };

      final retryResult = await rotateAndDistributeGroupKey(
        bridge: retryBridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: (peerId, message) async {
          capturedPayloads.add(_decodeDirectKeyUpdatePayload(message));
          return true;
        },
      );

      expect(retryResult, isNotNull);
      expect(retryResult!.keyGeneration, 2);
      expect(retryResult.encryptedKey, 'nw013-draft-key-a');
      expect(retryBridge.commandLog, isNot(contains('group:generateNextKey')));
      _expectNoSameEpochDifferentKeys(capturedPayloads);
      expect(
        capturedPayloads.map((payload) => payload['eventAt'] as String).toSet(),
        {draftEventAt},
      );
      expect(
        capturedPayloads
            .map(
              (payload) =>
                  (payload[signedGroupTransitionAuditField]
                          as Map<String, dynamic>)['eventAt']
                      as String,
            )
            .toSet(),
        {draftEventAt},
      );

      final latestAfterRetry = await groupRepo.getLatestKey(groupId);
      expect(latestAfterRetry, isNotNull);
      expect(latestAfterRetry!.keyGeneration, 2);
      expect(latestAfterRetry.encryptedKey, 'nw013-draft-key-a');
      expect(await groupRepo.getPendingKeyRotation(groupId), isNull);
    },
  );

  test(
    'NW-013 future pending draft fails closed instead of skipping epoch',
    () async {
      await groupRepo.savePendingKeyRotation(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 3,
          encryptedKey: 'future-draft-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: _sendOk,
      );

      expect(result, isNull);
      expect(bridge.commandLog, isNot(contains('group:generateNextKey')));
      expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);
      expect(await groupRepo.getPendingKeyRotation(groupId), isNotNull);
    },
  );

  test('distribution completes before admin update and broadcast', () async {
    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: _sendOk,
    );

    expect(result, isNotNull);

    final generateIdx = _bridgeCommandIndex(bridge, 'group:generateNextKey');
    final encryptIdx = _bridgeCommandIndex(bridge, 'message.encrypt');
    final updateIdx = _bridgeCommandIndex(
      bridge,
      'group:updateKey',
      keyEpoch: 2,
    );
    final publishIdx = _bridgeCommandIndex(bridge, 'group:publish');

    expect(generateIdx, greaterThanOrEqualTo(0));
    expect(encryptIdx, greaterThan(generateIdx));
    expect(updateIdx, greaterThan(encryptIdx));
    expect(publishIdx, greaterThan(updateIdx));
  });

  test('calls bridge to encrypt key for each non-self member', () async {
    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: _sendOk,
    );

    // message.encrypt should be called twice (Bob + Carol, not self)
    final encryptCount = bridge.commandLog
        .where((c) => c == 'message.encrypt')
        .length;
    expect(encryptCount, 2);
  });

  test('broadcasts key_rotated system message', () async {
    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: _sendOk,
    );

    // group:publish should be called for the system message
    expect(bridge.commandLog, contains('group:publish'));

    // Parse the published text to verify it's a key_rotated system message
    final publishMsg = bridge.sentMessages.firstWhere((m) {
      final parsed = jsonDecode(m) as Map<String, dynamic>;
      return parsed['cmd'] == 'group:publish';
    });
    final publishPayload =
        (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    final sysText =
        jsonDecode(publishPayload['text'] as String) as Map<String, dynamic>;
    expect(sysText['__sys'], 'key_rotated');
    expect(sysText['newKeyEpoch'], 2);
  });

  test(
    'PREREQ-SIGNED-COMMIT-AUDIT signs key_rotated transition before publish',
    () async {
      await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: _sendOk,
      );

      final publishMsg = bridge.sentMessages.firstWhere((m) {
        final parsed = jsonDecode(m) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:publish';
      });
      final publishPayload =
          (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      final sysText =
          jsonDecode(publishPayload['text'] as String) as Map<String, dynamic>;

      expect(sysText['__sys'], 'key_rotated');
      expect(sysText[signedGroupTransitionAuditField], isNotNull);
      expect(bridge.commandLog.where((c) => c == 'payload.sign').length, 5);
    },
  );

  test('sends key update to each non-self member via p2p', () async {
    final sentMessages = <(String, String)>[];

    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      distributionAttemptCount: 2,
      distributionRetryDelay: Duration.zero,
      sendP2PMessage: (peerId, message) async {
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Should send to Bob and Carol (not self)
    expect(sentMessages.length, 2);
    final peerIds = sentMessages.map((m) => m.$1).toSet();
    expect(peerIds, contains('peer-bob'));
    expect(peerIds, contains('peer-carol'));

    // Each message should be a group_key_update envelope
    for (final (_, msg) in sentMessages) {
      final parsed = jsonDecode(msg) as Map<String, dynamic>;
      expect(parsed['type'], 'group_key_update');
      expect(parsed['version'], '2');
      expect(parsed['encrypted'], isNotNull);
    }
  });

  test(
    'fails closed when direct transport is missing for recipients',
    () async {
      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
      );

      expect(result, isNull);
      expect(bridge.commandLog, isNot(contains('group:generateNextKey')));
      expect(bridge.commandLog, isNot(contains('message.encrypt')));
      expect(_bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2), -1);
      expect(bridge.commandLog, isNot(contains('group:publish')));

      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 1);
      expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);
      expect(await groupRepo.getPendingKeyRotation(groupId), isNull);
    },
  );

  test(
    'PREREQ-SIGNED-COMMIT-AUDIT signs distributed direct key-update payloads before encryption',
    () async {
      final sentMessages = <(String, String)>[];

      await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: (peerId, message) async {
          sentMessages.add((peerId, message));
          return true;
        },
      );

      expect(sentMessages.length, 2);
      expect(bridge.commandLog.where((c) => c == 'payload.sign').length, 5);

      final sourceEventIds = <String>{};
      final eventAtValues = <String>{};
      for (final (_, message) in sentMessages) {
        final envelope = jsonDecode(message) as Map<String, dynamic>;
        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final keyPayload =
            jsonDecode(encrypted['ciphertext'] as String)
                as Map<String, dynamic>;

        expect(keyPayload['sourcePeerId'], selfPeerId);
        expect(keyPayload['sourceEventId'], isA<String>());
        expect(keyPayload['eventAt'], isA<String>());
        sourceEventIds.add(keyPayload['sourceEventId'] as String);
        eventAtValues.add(keyPayload['eventAt'] as String);
        expect(
          keyPayload['signatureAlgorithm'],
          groupKeyUpdateSignatureAlgorithm,
        );
        expect(keyPayload['signature'], 'fake-signature');
        expect(keyPayload[signedGroupTransitionAuditField], isNotNull);

        final expectedSignedPayload = canonicalGroupKeyUpdateSignedPayload(
          groupId: groupId,
          sourcePeerId: selfPeerId,
          keyGeneration: 2,
          encryptedKey: 'newKey==',
          sourceDeviceId: selfPeerId,
          sourceTransportPeerId: selfPeerId,
          recipientPeerId: keyPayload['recipientPeerId'] as String?,
          recipientDeviceId: keyPayload['recipientDeviceId'] as String?,
          recipientTransportPeerId:
              keyPayload['recipientTransportPeerId'] as String?,
        );
        expect(keyPayload['signedPayload'], expectedSignedPayload);
        final signedAudit =
            keyPayload[signedGroupTransitionAuditField] as Map<String, dynamic>;
        expect(signedAudit['transitionType'], 'group_key_update');
        expect(signedAudit['sourceEventId'], keyPayload['sourceEventId']);
        expect(signedAudit['eventAt'], keyPayload['eventAt']);
        expect(signedAudit['signedPayload'], isA<String>());
      }
      expect(sourceEventIds, hasLength(2));
      expect(eventAtValues, hasLength(1));
    },
  );

  test('returns null when generate-next-key fails (ok: false)', () async {
    bridge.responses['group:generateNextKey'] = {
      'ok': false,
      'errorCode': 'GENERATE_FAILED',
    };

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: _sendOk,
    );

    expect(result, isNull);

    // Verify no new key was saved — latest key should still be generation 1
    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
  });

  test(
    'fails closed when an active member has no deliverable key device',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-dave',
          username: 'Dave',
          role: MemberRole.writer,
          publicKey: 'davePubKey',
          mlKemPublicKey: null,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final sentMessages = <(String, String)>[];

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        distributionAttemptCount: 2,
        distributionRetryDelay: Duration.zero,
        sendP2PMessage: (peerId, message) async {
          sentMessages.add((peerId, message));
          return true;
        },
      );

      expect(result, isNull);
      expect(sentMessages, isEmpty);
      expect(bridge.commandLog, isNot(contains('group:generateNextKey')));
      expect(bridge.commandLog, isNot(contains('message.encrypt')));
      expect(_bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2), -1);
      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 1);
      expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);

      final event = flowEvents.singleWhere(
        (event) => event['event'] == 'GROUP_ROTATE_KEY_UNDELIVERABLE_MEMBERS',
      );
      final details = event['details'] as Map<String, dynamic>;
      expect(details['undeliverableCount'], 1);
      expect(details['peerIds'], contains('peer-dav'));
    },
  );

  test(
    'targets active registered recipient devices and skips revoked devices',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'selfPubKey',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'self-device-1',
              transportPeerId: 'self-device-1',
              deviceSigningPublicKey: 'selfPubKey',
              mlKemPublicKey: 'selfDeviceMlKem',
              keyPackageId: 'self-kp-1',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'bobPubKey',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'bob-phone',
              transportPeerId: 'bob-phone-transport',
              deviceSigningPublicKey: 'bobPhonePubKey',
              mlKemPublicKey: 'bobPhoneMlKem',
              keyPackageId: 'bob-phone-kp',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'bob-tablet',
              transportPeerId: 'bob-tablet-transport',
              deviceSigningPublicKey: 'bobTabletPubKey',
              mlKemPublicKey: 'bobTabletMlKem',
              keyPackageId: 'bob-tablet-kp',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'bob-revoked',
              transportPeerId: 'bob-revoked-transport',
              deviceSigningPublicKey: 'bobRevokedPubKey',
              mlKemPublicKey: 'bobRevokedMlKem',
              keyPackageId: 'bob-revoked-kp',
              status: GroupMemberDeviceStatus.revoked,
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );
      final sentMessages = <(String, Map<String, dynamic>)>[];

      await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: (peerId, message) async {
          final envelope = jsonDecode(message) as Map<String, dynamic>;
          final encrypted = envelope['encrypted'] as Map<String, dynamic>;
          final payload =
              jsonDecode(encrypted['ciphertext'] as String)
                  as Map<String, dynamic>;
          sentMessages.add((peerId, payload));
          return true;
        },
      );

      final targetPeerIds = sentMessages.map((entry) => entry.$1).toSet();
      expect(targetPeerIds, contains('bob-phone-transport'));
      expect(targetPeerIds, contains('bob-tablet-transport'));
      expect(targetPeerIds, isNot(contains('bob-revoked-transport')));
      final bobPayloads = sentMessages
          .where(
            (entry) => (entry.$2['recipientPeerId'] as String?) == 'peer-bob',
          )
          .map((entry) => entry.$2)
          .toList();
      expect(
        bobPayloads.map((payload) => payload['recipientDeviceId']).toSet(),
        {'bob-phone', 'bob-tablet'},
      );
      expect(bobPayloads.map((payload) => payload['sourceDeviceId']).toSet(), {
        'self-device-1',
      });
    },
  );

  test(
    'KE-021 removed member is excluded from future direct key update fanout',
    () async {
      const bobPeerId = 'peer-bob';
      const bobDeviceId = 'bob-ke021-device';
      const bobTransportPeerId = 'bob-ke021-transport';
      const removedPeerId = 'peer-carol';
      const removedDeviceId = 'carol-ke021-device';
      const removedTransportPeerId = 'carol-ke021-transport';
      final createdAt = DateTime.utc(2026, 5, 11, 8, 24);
      final staleRemovedRepo = InMemoryGroupRepository();
      final removedMember = GroupMember(
        groupId: groupId,
        peerId: removedPeerId,
        username: 'Carol',
        role: MemberRole.writer,
        publicKey: 'carolPubKey',
        mlKemPublicKey: 'carolMlKem',
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: removedDeviceId,
            transportPeerId: removedTransportPeerId,
            deviceSigningPublicKey: 'carolDevicePubKey',
            mlKemPublicKey: 'carolDeviceMlKem',
            keyPackageId: 'carol-ke021-package',
          ),
        ],
        joinedAt: createdAt,
      );

      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: bobPeerId,
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'bobPubKey',
          mlKemPublicKey: 'bobMlKem',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: bobDeviceId,
              transportPeerId: bobTransportPeerId,
              deviceSigningPublicKey: 'bobDevicePubKey',
              mlKemPublicKey: 'bobDeviceMlKem',
              keyPackageId: 'bob-ke021-package',
            ),
          ],
          joinedAt: createdAt,
        ),
      );
      await groupRepo.saveMember(removedMember);
      await groupRepo.removeMember(groupId, removedPeerId);

      final group = await groupRepo.getGroup(groupId);
      await staleRemovedRepo.saveGroup(group!);
      await staleRemovedRepo.saveMember(removedMember);
      await staleRemovedRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'oldKey==',
          createdAt: createdAt,
        ),
      );

      final sentMessages = <(String, Map<String, dynamic>)>[];
      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: (peerId, message) async {
          sentMessages.add((peerId, _decodeDirectKeyUpdatePayload(message)));
          return true;
        },
      );

      expect(result, isNotNull);
      expect(result!.keyGeneration, 2);
      expect(result.encryptedKey, 'newKey==');

      final targetTransportPeerIds = sentMessages
          .map((entry) => entry.$1)
          .toSet();
      expect(targetTransportPeerIds, contains(bobTransportPeerId));
      expect(targetTransportPeerIds, isNot(contains(removedTransportPeerId)));

      final payloads = sentMessages.map((entry) => entry.$2).toList();
      final recipientPeerIds = payloads
          .map((payload) => payload['recipientPeerId'] as String?)
          .toSet();
      final recipientDeviceIds = payloads
          .map((payload) => payload['recipientDeviceId'] as String?)
          .toSet();
      final recipientTransportPeerIds = payloads
          .map((payload) => payload['recipientTransportPeerId'] as String?)
          .toSet();
      expect(recipientPeerIds, contains(bobPeerId));
      expect(recipientPeerIds, isNot(contains(removedPeerId)));
      expect(recipientDeviceIds, contains(bobDeviceId));
      expect(recipientDeviceIds, isNot(contains(removedDeviceId)));
      expect(recipientTransportPeerIds, contains(bobTransportPeerId));
      expect(
        recipientTransportPeerIds,
        isNot(contains(removedTransportPeerId)),
      );
      expect(payloads.map((payload) => payload['keyGeneration']).toSet(), {2});

      final savedCurrentKey = await groupRepo.getLatestKey(groupId);
      expect(savedCurrentKey, isNotNull);
      expect(savedCurrentKey!.keyGeneration, 2);
      final staleRemovedKey = await staleRemovedRepo.getLatestKey(groupId);
      expect(staleRemovedKey, isNotNull);
      expect(staleRemovedKey!.keyGeneration, 1);
      expect(
        sentMessages.where(
          (entry) =>
              entry.$1 == removedTransportPeerId ||
              entry.$2['recipientPeerId'] == removedPeerId ||
              entry.$2['recipientDeviceId'] == removedDeviceId ||
              entry.$2['recipientTransportPeerId'] == removedTransportPeerId,
        ),
        isEmpty,
      );
    },
  );

  test(
    'RA-012 re-added same peer uses rotated device material for future keys',
    () async {
      const charliePeerId = 'peer-carol';
      const charlieDeviceId = 'carol-ra012-device';
      const charlieTransportPeerId = 'carol-ra012-transport';
      const oldCharlieMlKem = 'carol-ra012-old-mlkem';
      const oldCharlieKeyPackage = 'carol-ra012-old-package';
      const newCharlieMlKem = 'carol-ra012-new-mlkem';
      const newCharlieKeyPackage = 'carol-ra012-new-package';
      final createdAt = DateTime.utc(2026, 5, 12, 10, 15);

      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'selfPubKey',
          mlKemPublicKey: 'selfMlKem',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'self-ra012-device',
              transportPeerId: 'self-ra012-transport',
              deviceSigningPublicKey: 'selfPubKey',
              mlKemPublicKey: 'selfRa012MlKem',
              keyPackageId: 'self-ra012-package',
            ),
          ],
          joinedAt: createdAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: charliePeerId,
          username: 'Carol',
          role: MemberRole.writer,
          publicKey: 'carolOldPubKey',
          mlKemPublicKey: oldCharlieMlKem,
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: charlieDeviceId,
              transportPeerId: charlieTransportPeerId,
              deviceSigningPublicKey: 'carolOldDevicePubKey',
              mlKemPublicKey: oldCharlieMlKem,
              keyPackageId: oldCharlieKeyPackage,
              keyPackagePublicMaterial: 'carol-ra012-old-package-material',
            ),
          ],
          joinedAt: createdAt,
        ),
      );
      await groupRepo.removeMember(groupId, charliePeerId);
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: charliePeerId,
          username: 'Carol restored',
          role: MemberRole.writer,
          publicKey: 'carolNewPubKey',
          mlKemPublicKey: newCharlieMlKem,
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: charlieDeviceId,
              transportPeerId: charlieTransportPeerId,
              deviceSigningPublicKey: 'carolNewDevicePubKey',
              mlKemPublicKey: newCharlieMlKem,
              keyPackageId: newCharlieKeyPackage,
              keyPackagePublicMaterial: 'carol-ra012-new-package-material',
            ),
          ],
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        ),
      );

      final sentMessages = <(String, Map<String, dynamic>)>[];
      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sourceDeviceId: 'self-ra012-device',
        sendP2PMessage: (peerId, message) async {
          sentMessages.add((peerId, _decodeDirectKeyUpdatePayload(message)));
          return true;
        },
      );

      expect(result, isNotNull);
      expect(result!.keyGeneration, 2);

      final charliePayload = sentMessages
          .where((entry) => entry.$2['recipientPeerId'] == charliePeerId)
          .single;
      expect(charliePayload.$1, charlieTransportPeerId);
      expect(charliePayload.$2['recipientDeviceId'], charlieDeviceId);
      expect(
        charliePayload.$2['recipientTransportPeerId'],
        charlieTransportPeerId,
      );
      expect(charliePayload.$2['recipientKeyPackageId'], newCharlieKeyPackage);
      expect(
        charliePayload.$2['recipientKeyPackageId'],
        isNot(oldCharlieKeyPackage),
      );

      final encryptPayloads = bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'message.encrypt')
          .map((message) => message['payload'] as Map<String, dynamic>)
          .toList();
      expect(
        encryptPayloads.map((payload) => payload['recipientPublicKey']),
        contains(newCharlieMlKem),
      );
      expect(
        encryptPayloads.map((payload) => payload['recipientPublicKey']),
        isNot(contains(oldCharlieMlKem)),
      );

      final savedCharlie = await groupRepo.getMember(groupId, charliePeerId);
      expect(savedCharlie, isNotNull);
      expect(savedCharlie!.publicKey, 'carolNewPubKey');
      expect(savedCharlie.mlKemPublicKey, newCharlieMlKem);
      expect(savedCharlie.devices, hasLength(1));
      expect(
        savedCharlie.devices.single.deviceSigningPublicKey,
        'carolNewDevicePubKey',
      );
      expect(savedCharlie.devices.single.mlKemPublicKey, newCharlieMlKem);
      expect(savedCharlie.devices.single.keyPackageId, newCharlieKeyPackage);
    },
  );

  test(
    'rejects registered source member without matching active source device before key generation',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'selfPubKey',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'self-device-1',
              transportPeerId: 'self-device-1',
              deviceSigningPublicKey: 'different-device-pub-key',
              mlKemPublicKey: 'selfDeviceMlKem',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
      );

      expect(result, isNull);
      expect(bridge.commandLog, isNot(contains('group:generateNextKey')));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      final latest = await groupRepo.getLatestKey(groupId);
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 1);
    },
  );

  test(
    'RA-017 repeated Charlie churn keeps key distribution targeting Bob and Dana',
    () async {
      const charliePeerId = 'peer-carol';
      const danaPeerId = 'peer-dana';
      final createdAt = DateTime.utc(2026, 5, 13, 8);
      bridge = _CommittedEpochGenerateBridge(initialCommittedEpoch: 1);
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'ra017-key-rotated',
      };

      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: danaPeerId,
          username: 'Dana',
          role: MemberRole.writer,
          publicKey: 'danaPubKey',
          mlKemPublicKey: 'danaMlKem',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'dana-device',
              transportPeerId: 'dana-transport',
              deviceSigningPublicKey: 'danaDevicePubKey',
              mlKemPublicKey: 'danaDeviceMlKem',
              keyPackageId: 'dana-key-package',
            ),
          ],
          joinedAt: createdAt,
        ),
      );

      final capturedPayloads = <Map<String, dynamic>>[];
      final targetsByEpoch = <int, Set<String>>{};

      Future<GroupKeyInfo> rotateAndCapture() async {
        final result = await rotateAndDistributeGroupKey(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          selfPeerId: selfPeerId,
          senderPublicKey: 'selfPubKey',
          senderPrivateKey: 'selfPrivKey',
          senderUsername: 'Self',
          sendP2PMessage: (peerId, message) async {
            final payload = _decodeDirectKeyUpdatePayload(message);
            capturedPayloads.add(payload);
            final epoch = payload['keyGeneration'] as int;
            targetsByEpoch
                .putIfAbsent(epoch, () => <String>{})
                .add(payload['recipientPeerId'] as String);
            return true;
          },
        );
        expect(result, isNotNull);
        return result!;
      }

      for (var cycle = 1; cycle <= 3; cycle++) {
        await groupRepo.removeMember(groupId, charliePeerId);
        final removedWindowKey = await rotateAndCapture();
        expect(
          targetsByEpoch[removedWindowKey.keyGeneration],
          {'peer-bob', danaPeerId},
          reason:
              'RA-017 cycle $cycle removed-window key fanout must keep Bob '
              'and Dana active while excluding Charlie',
        );

        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: charliePeerId,
            username: 'Carol re-added $cycle',
            role: MemberRole.writer,
            publicKey: 'carolPubKey',
            mlKemPublicKey: 'carolMlKem',
            joinedAt: createdAt.add(Duration(minutes: cycle)),
          ),
        );
        final postReaddKey = await rotateAndCapture();
        expect(
          targetsByEpoch[postReaddKey.keyGeneration],
          {'peer-bob', charliePeerId, danaPeerId},
          reason:
              'RA-017 cycle $cycle post-readd key fanout must include all '
              'active recipients, not only Charlie',
        );
      }

      expect(capturedPayloads, hasLength(15));
      for (final payload in capturedPayloads) {
        expect(payload['recipientPeerId'], isNot(selfPeerId));
        expect(payload['keyGeneration'], greaterThanOrEqualTo(2));
      }
      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 7);
    },
  );

  test(
    'ST-009 max-size re-add restores key fanout to every active recipient',
    () async {
      const readdPeerId = 'peer-carol';
      final joinedAt = DateTime.utc(2026, 5, 16, 9, 9);

      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'selfPubKey',
          mlKemPublicKey: 'selfMlKem',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'self-st009-device',
              transportPeerId: 'self-st009-transport',
              deviceSigningPublicKey: 'selfPubKey',
              mlKemPublicKey: 'selfSt009MlKem',
              keyPackageId: 'self-st009-package',
            ),
          ],
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'bobPubKey',
          mlKemPublicKey: 'bobMlKem',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'bob-st009-device',
              transportPeerId: 'bob-st009-transport',
              deviceSigningPublicKey: 'bobPubKey',
              mlKemPublicKey: 'bobSt009MlKem',
              keyPackageId: 'bob-st009-package',
            ),
          ],
          joinedAt: joinedAt.add(const Duration(minutes: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: readdPeerId,
          username: 'Carol',
          role: MemberRole.writer,
          publicKey: 'carolPubKey',
          mlKemPublicKey: 'carolMlKem',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'carol-st009-device',
              transportPeerId: 'carol-st009-transport',
              deviceSigningPublicKey: 'carolPubKey',
              mlKemPublicKey: 'carolSt009MlKem',
              keyPackageId: 'carol-st009-package',
            ),
          ],
          joinedAt: joinedAt.add(const Duration(minutes: 2)),
        ),
      );

      for (var index = 0; index < groupMembershipLimit - 3; index++) {
        final peerId = 'peer-st009-synth-${index.toString().padLeft(2, '0')}';
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: peerId,
            username: 'Synthetic $index',
            role: MemberRole.writer,
            publicKey: 'pk-$peerId',
            mlKemPublicKey: 'mlkem-$peerId',
            devices: [
              GroupMemberDeviceIdentity(
                deviceId: '$peerId-device',
                transportPeerId: '$peerId-transport',
                deviceSigningPublicKey: 'pk-$peerId',
                mlKemPublicKey: 'mlkem-$peerId-device',
                keyPackageId: 'kp-$peerId-device',
              ),
            ],
            joinedAt: joinedAt.add(Duration(minutes: 3 + index)),
          ),
        );
      }

      expect(
        (await groupRepo.getMembers(groupId)).length,
        groupMembershipLimit,
      );
      await groupRepo.removeMember(groupId, readdPeerId);
      expect((await groupRepo.getMembers(groupId)).length, 49);
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: readdPeerId,
          username: 'Carol Readded',
          role: MemberRole.writer,
          publicKey: 'carolReaddPubKey',
          mlKemPublicKey: 'carolReaddMlKem',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'carol-st009-readd-device',
              transportPeerId: 'carol-st009-readd-transport',
              deviceSigningPublicKey: 'carolReaddPubKey',
              mlKemPublicKey: 'carolSt009ReaddMlKem',
              keyPackageId: 'carol-st009-readd-package',
            ),
          ],
          joinedAt: joinedAt.add(const Duration(hours: 1)),
        ),
      );
      expect(
        (await groupRepo.getMembers(groupId)).length,
        groupMembershipLimit,
      );

      final sentMessages = <(String, Map<String, dynamic>)>[];
      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sourceDeviceId: 'self-st009-device',
        sendP2PMessage: (peerId, message) async {
          sentMessages.add((peerId, _decodeDirectKeyUpdatePayload(message)));
          return true;
        },
      );

      expect(result, isNotNull);
      expect(result!.keyGeneration, 2);
      expect(sentMessages, hasLength(groupMembershipLimit - 1));
      final recipientPeerIds = sentMessages
          .map((entry) => entry.$2['recipientPeerId'] as String)
          .toSet();
      expect(recipientPeerIds, hasLength(groupMembershipLimit - 1));
      expect(recipientPeerIds, contains('peer-bob'));
      expect(recipientPeerIds, contains(readdPeerId));
      expect(recipientPeerIds, isNot(contains(selfPeerId)));
      for (var index = 0; index < groupMembershipLimit - 3; index++) {
        expect(
          recipientPeerIds,
          contains('peer-st009-synth-${index.toString().padLeft(2, '0')}'),
        );
      }
    },
  );

  test(
    'NW-012 long offline epoch churn distributes keys only to active recipients for each interval',
    () async {
      const charliePeerId = 'peer-carol';
      final baseAt = DateTime.utc(2026, 5, 13, 9);
      bridge = _CommittedEpochGenerateBridge(initialCommittedEpoch: 1);
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'nw012-key-rotated',
      };

      final targetsByEpoch = <int, Set<String>>{};

      Future<GroupKeyInfo> rotateAndCapture() async {
        final result = await rotateAndDistributeGroupKey(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          selfPeerId: selfPeerId,
          senderPublicKey: 'selfPubKey',
          senderPrivateKey: 'selfPrivKey',
          senderUsername: 'Self',
          sendP2PMessage: (peerId, message) async {
            final payload = _decodeDirectKeyUpdatePayload(message);
            final epoch = payload['keyGeneration'] as int;
            targetsByEpoch
                .putIfAbsent(epoch, () => <String>{})
                .add(payload['recipientPeerId'] as String);
            return true;
          },
        );
        expect(result, isNotNull);
        return result!;
      }

      final firstActive = await rotateAndCapture();
      expect(targetsByEpoch[firstActive.keyGeneration], {
        'peer-bob',
        charliePeerId,
      });

      await groupRepo.removeMember(groupId, charliePeerId);
      final removedWindow = await rotateAndCapture();
      expect(targetsByEpoch[removedWindow.keyGeneration], {'peer-bob'});
      expect(
        targetsByEpoch[removedWindow.keyGeneration],
        isNot(contains(charliePeerId)),
      );

      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: charliePeerId,
          username: 'Carol re-added',
          role: MemberRole.writer,
          publicKey: 'carolPubKey',
          mlKemPublicKey: 'carolMlKem',
          joinedAt: baseAt.add(const Duration(minutes: 40)),
        ),
      );
      final finalActive = await rotateAndCapture();
      expect(targetsByEpoch[finalActive.keyGeneration], {
        'peer-bob',
        charliePeerId,
      });

      for (final targets in targetsByEpoch.values) {
        expect(targets, isNot(contains(selfPeerId)));
      }
      expect((await groupRepo.getLatestKey(groupId))!.keyGeneration, 4);
    },
  );

  test(
    'RA-018 alternating C/D churn keeps key distribution deterministic for active intervals',
    () async {
      const charliePeerId = 'peer-carol';
      const danaPeerId = 'peer-dana';
      final createdAt = DateTime.utc(2026, 5, 13, 8);
      bridge = _CommittedEpochGenerateBridge(initialCommittedEpoch: 1);
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'ra018-key-rotated',
      };

      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: danaPeerId,
          username: 'Dana',
          role: MemberRole.writer,
          publicKey: 'danaPubKey',
          mlKemPublicKey: 'danaMlKem',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'dana-device',
              transportPeerId: 'dana-transport',
              deviceSigningPublicKey: 'danaDevicePubKey',
              mlKemPublicKey: 'danaDeviceMlKem',
              keyPackageId: 'dana-key-package',
            ),
          ],
          joinedAt: createdAt,
        ),
      );

      final capturedPayloads = <Map<String, dynamic>>[];
      final targetsByEpoch = <int, Set<String>>{};

      Future<GroupKeyInfo> rotateAndCapture() async {
        final result = await rotateAndDistributeGroupKey(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          selfPeerId: selfPeerId,
          senderPublicKey: 'selfPubKey',
          senderPrivateKey: 'selfPrivKey',
          senderUsername: 'Self',
          sendP2PMessage: (peerId, message) async {
            final payload = _decodeDirectKeyUpdatePayload(message);
            capturedPayloads.add(payload);
            final epoch = payload['keyGeneration'] as int;
            targetsByEpoch
                .putIfAbsent(epoch, () => <String>{})
                .add(payload['recipientPeerId'] as String);
            return true;
          },
        );
        expect(result, isNotNull);
        return result!;
      }

      Future<void> readdMember({
        required String peerId,
        required String username,
        required String publicKey,
        required String mlKemPublicKey,
        required int cycle,
        required int operationIndex,
      }) async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: peerId,
            username: username,
            role: MemberRole.writer,
            publicKey: publicKey,
            mlKemPublicKey: mlKemPublicKey,
            joinedAt: createdAt.add(
              Duration(minutes: cycle * 10 + operationIndex),
            ),
          ),
        );
      }

      for (var cycle = 1; cycle <= 3; cycle++) {
        await groupRepo.removeMember(groupId, charliePeerId);
        final charlieRemovedKey = await rotateAndCapture();
        expect(
          targetsByEpoch[charlieRemovedKey.keyGeneration],
          {'peer-bob', danaPeerId},
          reason:
              'RA-018 cycle $cycle Charlie-removed key fanout must target '
              'only Bob and Dana',
        );

        await readdMember(
          peerId: charliePeerId,
          username: 'Carol re-added $cycle',
          publicKey: 'carolPubKey',
          mlKemPublicKey: 'carolMlKem',
          cycle: cycle,
          operationIndex: 2,
        );
        final charlieReaddedKey = await rotateAndCapture();
        expect(
          targetsByEpoch[charlieReaddedKey.keyGeneration],
          {'peer-bob', charliePeerId, danaPeerId},
          reason:
              'RA-018 cycle $cycle Charlie re-add key fanout must include '
              'Bob, Charlie, and Dana',
        );

        await groupRepo.removeMember(groupId, danaPeerId);
        final danaRemovedKey = await rotateAndCapture();
        expect(
          targetsByEpoch[danaRemovedKey.keyGeneration],
          {'peer-bob', charliePeerId},
          reason:
              'RA-018 cycle $cycle Dana-removed key fanout must target only '
              'Bob and Charlie',
        );

        await readdMember(
          peerId: danaPeerId,
          username: 'Dana re-added $cycle',
          publicKey: 'danaPubKey',
          mlKemPublicKey: 'danaMlKem',
          cycle: cycle,
          operationIndex: 4,
        );
        final danaReaddedKey = await rotateAndCapture();
        expect(
          targetsByEpoch[danaReaddedKey.keyGeneration],
          {'peer-bob', charliePeerId, danaPeerId},
          reason:
              'RA-018 cycle $cycle Dana re-add key fanout must restore all '
              'active recipients',
        );
      }

      expect(capturedPayloads, hasLength(30));
      for (final payload in capturedPayloads) {
        expect(payload['recipientPeerId'], isNot(selfPeerId));
        expect(payload['keyGeneration'], greaterThanOrEqualTo(2));
      }
      _expectNoSameEpochDifferentKeys(capturedPayloads);
      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 13);
    },
  );

  test(
    'KE-015 partial key distribution failure blocks sender promotion and keeps previous epoch',
    () async {
      final attempts = <(String, Map<String, dynamic>)>[];

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        distributionAttemptCount: 1,
        sendP2PMessage: (peerId, message) async {
          attempts.add((peerId, _decodeDirectKeyUpdatePayload(message)));
          return peerId != 'peer-carol';
        },
      );

      expect(result, isNull);
      expect(attempts, hasLength(2));
      expect(attempts.map((attempt) => attempt.$1).toSet(), {
        'peer-bob',
        'peer-carol',
      });
      expect(
        attempts.map((attempt) => attempt.$2['keyGeneration'] as int).toSet(),
        {2},
      );
      expect(
        attempts
            .map((attempt) => attempt.$2['recipientPeerId'] as String)
            .toSet(),
        {'peer-bob', 'peer-carol'},
      );
      expect(
        _bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 1),
        greaterThanOrEqualTo(0),
      );
      expect(_bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2), -1);
      expect(bridge.commandLog, isNot(contains('group:publish')));

      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 1);
      expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);
    },
  );

  test(
    'promotes when inbox fallback stores failed direct key updates',
    () async {
      final directAttempts = <(String, Map<String, dynamic>)>[];
      final inboxFallbacks = <(String, Map<String, dynamic>)>[];

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        distributionAttemptCount: 1,
        sendP2PMessage: (peerId, message) async {
          directAttempts.add((peerId, _decodeDirectKeyUpdatePayload(message)));
          return false;
        },
        storeP2PMessageInInbox: (peerId, message) async {
          inboxFallbacks.add((peerId, _decodeDirectKeyUpdatePayload(message)));
          return true;
        },
      );

      expect(result, isNotNull);
      expect(result!.keyGeneration, 2);
      expect(directAttempts.map((attempt) => attempt.$1).toSet(), {
        'peer-bob',
        'peer-carol',
      });
      expect(inboxFallbacks.map((attempt) => attempt.$1).toSet(), {
        'peer-bob',
        'peer-carol',
      });
      expect(
        inboxFallbacks
            .map((attempt) => attempt.$2['recipientPeerId'] as String)
            .toSet(),
        {'peer-bob', 'peer-carol'},
      );
      expect(
        _bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2),
        greaterThanOrEqualTo(0),
      );
      expect(bridge.commandLog, contains('group:publish'));

      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 2);
    },
  );

  test('continues distribution when per-member encrypt fails', () async {
    // Use a custom bridge that fails encrypt for Bob but succeeds for Carol
    final selectiveBridge = _SelectiveEncryptFailBridge();
    selectiveBridge.responses['group:generateNextKey'] = {
      'ok': true,
      'groupKey': 'newKey==',
      'keyEpoch': 2,
    };
    selectiveBridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'sys-msg-id',
    };

    final sentMessages = <(String, String)>[];

    final result = await rotateAndDistributeGroupKey(
      bridge: selectiveBridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      distributionAttemptCount: 2,
      distributionRetryDelay: Duration.zero,
      sendP2PMessage: (peerId, message) async {
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Only Carol should receive a P2P message (Bob's encrypt failed)
    expect(result, isNull);
    expect(sentMessages.length, 1);
    expect(sentMessages.first.$1, 'peer-carol');
    expect(
      _bridgeCommandIndex(selectiveBridge, 'group:updateKey', keyEpoch: 2),
      -1,
    );
    expect(selectiveBridge.commandLog, isNot(contains('group:publish')));
  });

  test('retries transient send failures before promotion', () async {
    final attemptsByPeer = <String, int>{};
    final sentMessages = <(String, String)>[];

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      distributionRetryDelay: Duration.zero,
      sendP2PMessage: (peerId, message) async {
        attemptsByPeer[peerId] = (attemptsByPeer[peerId] ?? 0) + 1;
        if (peerId == 'peer-bob' && attemptsByPeer[peerId] == 1) {
          throw Exception('Network error for first peer');
        }
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Function should still complete and return a result
    expect(result, isNotNull);
    expect(result!.keyGeneration, 2);

    expect(attemptsByPeer['peer-bob'], 2);
    expect(sentMessages.any((message) => message.$1 == 'peer-bob'), isTrue);
    expect(bridge.commandLog, contains('group:updateKey'));
  });

  test(
    'outer distribution timeout does not return with send in flight',
    () async {
      final blockedSend = Completer<bool>();
      var bobStarted = false;
      var carolStarted = false;
      var completed = false;

      final pending = rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        perRecipientTimeout: const Duration(seconds: 1),
        distributionTimeout: const Duration(milliseconds: 40),
        distributionAttemptCount: 1,
        sendP2PMessage: (peerId, message) {
          if (peerId == 'peer-bob') {
            bobStarted = true;
            return blockedSend.future;
          }
          if (peerId == 'peer-carol') {
            carolStarted = true;
          }
          return Future.value(true);
        },
      );
      unawaited(pending.whenComplete(() => completed = true));

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(bobStarted, isTrue);
      expect(carolStarted, isFalse);
      expect(completed, isFalse);
      expect(_bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2), -1);

      blockedSend.complete(false);
      final result = await pending.timeout(const Duration(seconds: 2));

      expect(result, isNull);
      expect(carolStarted, isTrue);
      expect(_bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2), -1);
      expect(bridge.commandLog, isNot(contains('group:publish')));
    },
  );

  test(
    'late successful direct send after recipient timeout still counts delivered',
    () async {
      final delayedSend = Completer<bool>();
      var completed = false;

      final pending = rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        perRecipientTimeout: const Duration(milliseconds: 10),
        distributionAttemptCount: 1,
        sendP2PMessage: (peerId, message) {
          if (peerId == 'peer-bob') {
            return delayedSend.future;
          }
          return Future.value(true);
        },
      );
      unawaited(pending.whenComplete(() => completed = true));

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(completed, isFalse);
      expect(_bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2), -1);

      delayedSend.complete(true);
      final result = await pending.timeout(const Duration(seconds: 2));

      expect(result, isNotNull);
      expect(result!.keyGeneration, 2);
      expect(
        _bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2),
        isNot(-1),
      );
      expect(bridge.commandLog, contains('group:publish'));
    },
  );

  test('does not update admin key after timed out direct sends fail', () async {
    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      perRecipientTimeout: const Duration(milliseconds: 5),
      distributionAttemptCount: 1,
      sendP2PMessage: (_, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return false;
      },
    );

    expect(result, isNull);
    expect(_bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2), -1);
    expect(bridge.commandLog, isNot(contains('group:publish')));

    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
  });
}

int _bridgeCommandIndex(FakeBridge bridge, String command, {int? keyEpoch}) {
  for (var i = 0; i < bridge.sentMessages.length; i++) {
    final parsed = jsonDecode(bridge.sentMessages[i]) as Map<String, dynamic>;
    if (parsed['cmd'] != command) {
      continue;
    }
    if (keyEpoch == null) {
      return i;
    }
    final payload = parsed['payload'];
    if (payload is Map<String, dynamic> && payload['keyEpoch'] == keyEpoch) {
      return i;
    }
  }
  return -1;
}

Map<String, dynamic> _decodeDirectKeyUpdatePayload(String message) {
  final envelope = jsonDecode(message) as Map<String, dynamic>;
  final encrypted = envelope['encrypted'] as Map<String, dynamic>;
  return jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
}

Future<bool> _sendOk(String peerId, String message) async {
  return peerId.isNotEmpty || message.isNotEmpty;
}

void _expectNoSameEpochDifferentKeys(
  List<Map<String, dynamic>> capturedPayloads,
) {
  final encryptedKeysByEpoch = <int, Set<String>>{};
  for (final payload in capturedPayloads) {
    final epoch = payload['keyGeneration'] as int;
    final encryptedKey = payload['encryptedKey'] as String;
    encryptedKeysByEpoch.putIfAbsent(epoch, () => <String>{}).add(encryptedKey);
  }

  for (final entry in encryptedKeysByEpoch.entries) {
    expect(
      entry.value,
      hasLength(1),
      reason:
          'epoch ${entry.key} must not be distributed with multiple key values',
    );
  }
}

class _CommittedEpochGenerateBridge extends PassthroughCryptoBridge {
  _CommittedEpochGenerateBridge({required int initialCommittedEpoch})
    : _committedEpoch = initialCommittedEpoch;

  int _committedEpoch;
  int _generatedKeyCount = 0;
  final List<({String type, int? epoch, String? key})> events = [];

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:generateNextKey') {
      final nextEpoch = _committedEpoch + 1;
      _generatedKeyCount++;
      final generatedKey = 'ke020-key-$nextEpoch-$_generatedKeyCount';
      responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': generatedKey,
        'keyEpoch': nextEpoch,
      };
      final response = await super.send(message);
      events.add((type: 'generate', epoch: nextEpoch, key: generatedKey));
      return response;
    }

    if (cmd == 'group:updateKey') {
      final response = await super.send(message);
      final responseMap = jsonDecode(response) as Map<String, dynamic>;
      if (responseMap['ok'] == true) {
        final payload = parsed['payload'] as Map<String, dynamic>;
        final epoch = payload['keyEpoch'] as int;
        final key = payload['groupKey'] as String;
        if (epoch > _committedEpoch) {
          _committedEpoch = epoch;
        }
        events.add((type: 'update', epoch: epoch, key: key));
      }
      return response;
    }

    final response = await super.send(message);
    if (cmd == 'group:publish') {
      events.add((type: 'publish', epoch: null, key: null));
    }
    return response;
  }

  int eventIndex(String type) {
    return events.indexWhere((event) => event.type == type);
  }

  int nthEventIndex(String type, int count) {
    var seen = 0;
    for (var i = 0; i < events.length; i++) {
      if (events[i].type != type) {
        continue;
      }
      seen++;
      if (seen == count) {
        return i;
      }
    }
    return -1;
  }
}

class _RestartEmptyGenerateBridge extends PassthroughCryptoBridge {
  _RestartEmptyGenerateBridge({this.forceStaleGenerate = false});

  final bool forceStaleGenerate;
  int? _restoredEpoch;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:generateNextKey') {
      final generatedEpoch = forceStaleGenerate || _restoredEpoch == null
          ? 2
          : _restoredEpoch! + 1;
      responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': 'epoch${generatedEpoch}Key==',
        'keyEpoch': generatedEpoch,
      };
      return super.send(message);
    }

    final response = await super.send(message);
    if (cmd == 'group:updateKey') {
      final responseMap = jsonDecode(response) as Map<String, dynamic>;
      final payload = parsed['payload'] as Map<String, dynamic>;
      if (responseMap['ok'] == true) {
        _restoredEpoch = payload['keyEpoch'] as int;
      }
    }
    return response;
  }
}

class _SelectiveEncryptFailBridge extends PassthroughCryptoBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'message.encrypt') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      if (payload['recipientPublicKey'] == 'bobMlKem') {
        sendCallCount++;
        lastSentMessage = message;
        sentMessages.add(message);
        lastCommand = cmd;
        commandLog.add(cmd!);
        return jsonEncode({'ok': false, 'errorCode': 'ENCRYPT_FAILED'});
      }
    }
    return super.send(message);
  }
}
