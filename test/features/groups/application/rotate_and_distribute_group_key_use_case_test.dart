import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_key_update_signature.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

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
    'TC-363-02a protected group authority converges physical devices before content is enabled',
    () async {
      expect(
        hasProtectedGroupPhysicalAuthority(await groupRepo.getMembers(groupId)),
        isFalse,
        reason: 'an all-legacy group keeps incumbent delivery default-off',
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'selfPubKey',
          mlKemPublicKey: 'selfMlKem',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: selfPeerId,
              transportPeerId: selfPeerId,
              deviceSigningPublicKey: 'selfPubKey',
              mlKemPublicKey: 'selfMlKem',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'self-linked-device',
              transportPeerId: 'self-linked-transport',
              deviceSigningPublicKey: 'self-linked-public-key',
              mlKemPublicKey: 'self-linked-mlkem',
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 13),
        ),
      );

      ProtectedGroupAuthorityPrepareRequest? captured;
      var activationCount = 0;
      setProtectedGroupAuthorityAdapter(
        prepare: (request) async {
          captured = request;
          final instant = DateTime.utc(2026, 8, 13);
          return ProtectedGroupAuthorityPreparation(
            groupId: request.groupId,
            rows: <GroupPendingBroadcast>[
              GroupPendingBroadcast(
                id: 'protected-key-row',
                groupId: request.groupId,
                kind: groupPendingBroadcastKindProtectedAuthority,
                sysText: '{}',
                recipientPeerIds: const <String>['peer-bob'],
                eventAt: instant,
                sourceMessageId: 'protected-key-source',
                createdAt: instant,
                updatedAt: instant,
              ),
            ],
          );
        },
        activate: (preparation, {required requireAllCustody}) async {
          activationCount++;
          expect(requireAllCustody, isTrue);
          return true;
        },
        cancel: (_) async => true,
      );
      addTearDown(() => setProtectedGroupAuthorityAdapter());
      var ordinaryLiveSends = 0;
      var ordinaryInboxStores = 0;

      final delivered = await distributeCurrentGroupKeyToDeferredPeer(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        peerId: 'peer-bob',
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: (_, _) async {
          ordinaryLiveSends++;
          return true;
        },
        storeP2PMessageInInbox: (_, _) async {
          ordinaryInboxStores++;
          return true;
        },
      );

      expect(delivered, 1);
      expect(activationCount, 1);
      expect(ordinaryLiveSends, 0);
      expect(ordinaryInboxStores, 0);
      expect(captured?.control, ProtectedGroupAuthorityControl.groupKeyUpdate);
      expect(captured?.deliveryRecipients?.single.transportPeerId, 'peer-bob');
      expect(captured?.replayData['keyGeneration'], 1);
      expect(captured?.replayData['content'], contains('group_key_update'));
    },
  );

  test(
    'TC-363-02c key rotation keeps one sender/A/B authority version across restart and zero targets',
    () async {
      const source = GroupMemberDeviceIdentity(
        deviceId: 'source-device',
        transportPeerId: 'source-transport',
        deviceSigningPublicKey: 'selfPubKey',
        mlKemPublicKey: 'source-mlkem',
      );
      const physicalA = GroupMemberDeviceIdentity(
        deviceId: 'device-a',
        transportPeerId: 'physical-a',
        deviceSigningPublicKey: 'public-a',
        mlKemPublicKey: 'mlkem-a',
      );
      const physicalB = GroupMemberDeviceIdentity(
        deviceId: 'device-b',
        transportPeerId: 'physical-b',
        deviceSigningPublicKey: 'public-b',
        mlKemPublicKey: 'mlkem-b',
      );
      await groupRepo.removeMember(groupId, 'peer-bob');
      await groupRepo.removeMember(groupId, 'peer-carol');
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'selfPubKey',
          mlKemPublicKey: 'source-mlkem',
          devices: const <GroupMemberDeviceIdentity>[source],
          joinedAt: DateTime.utc(2026, 8, 13),
        ),
      );
      for (final entry in const <(String, String, GroupMemberDeviceIdentity)>[
        ('peer-a', 'Peer A', physicalA),
        ('peer-b', 'Peer B', physicalB),
      ]) {
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: entry.$1,
            username: entry.$2,
            role: MemberRole.writer,
            publicKey: 'account-${entry.$1}',
            mlKemPublicKey: entry.$3.mlKemPublicKey,
            devices: <GroupMemberDeviceIdentity>[entry.$3],
            joinedAt: DateTime.utc(2026, 8, 13),
          ),
        );
      }

      final durablePrepared = <String, AuthenticatedGroupAuthorityProof>{};
      final durableComplete = <String, AuthenticatedGroupAuthorityProof>{};
      final rowsByRecipient = <String, GroupPendingBroadcast>{};
      final plaintextByRecipient = <String, String>{};
      final requests = <ProtectedGroupAuthorityPrepareRequest>[];
      setProtectedGroupAuthorityAdapter(
        prepare: (request) async {
          requests.add(request);
          final recipientByKey = <String, String>{
            for (final device in request.frozenRecipients)
              if (device.mlKemPublicKey != null)
                device.mlKemPublicKey!: device.transportPeerId,
          };
          final preparation = await buildProtectedGroupAuthorityRows(
            groupId: request.groupId,
            transitionId: request.transitionId,
            control: request.control,
            replayData: request.replayData,
            keyEpoch: request.replayData['keyGeneration'] as int,
            actorAccountPeerId: request.actorAccountPeerId,
            actorAccountPublicKey: request.actorAccountPublicKey,
            actorAccountPrivateKey: request.actorAccountPrivateKey,
            senderDevice: request.senderDevice,
            frozenRecipients: request.frozenRecipients,
            deliveryRecipients: request.deliveryRecipients,
            sharedAuthorityProof: request.sharedAuthorityProof,
            callSign: (data, _) async => <String, dynamic>{
              'ok': true,
              'signature': 'sig:${data.hashCode}',
            },
            callEncrypt:
                ({required recipientMlKemPublicKey, required plaintext}) async {
                  final recipient = recipientByKey[recipientMlKemPublicKey]!;
                  plaintextByRecipient[recipient] = plaintext;
                  return <String, dynamic>{
                    'ok': true,
                    'kem': 'kem-$recipient',
                    'ciphertext': 'ciphertext-$recipient',
                    'nonce': 'nonce-$recipient',
                  };
                },
            now: () => DateTime.parse(
              request.replayData['timestamp'] as String,
            ).toUtc(),
          );
          final proof = preparation.authorityProof;
          if (proof == null) return preparation;
          final existing = durablePrepared[proof.eventId];
          if (existing != null &&
              !sameAuthenticatedGroupAuthorityProof(existing, proof)) {
            return null;
          }
          durablePrepared[proof.eventId] = proof;
          for (final row in preparation.rows) {
            rowsByRecipient[row.recipientPeerIds.single] = row;
          }
          return preparation;
        },
        activate: (preparation, {required requireAllCustody}) async {
          final proof = preparation.authorityProof!;
          durableComplete[proof.eventId] = proof;
          return requireAllCustody;
        },
        cancel: (_) async => true,
      );
      addTearDown(() => setProtectedGroupAuthorityAdapter());

      final rotated = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sourceDeviceId: source.deviceId,
        sendP2PMessage: _sendOk,
      );
      expect(rotated.rotated, isTrue);
      expect(requests, hasLength(2));
      expect(
        requests.map((request) => request.transitionId).toSet(),
        hasLength(1),
      );
      final proofA = ProtectedGroupAuthorityPayload.tryParse(
        plaintextByRecipient['physical-a']!,
      )!.authorityProof;
      final proofB = ProtectedGroupAuthorityPayload.tryParse(
        plaintextByRecipient['physical-b']!,
      )!.authorityProof;
      expect(sameAuthenticatedGroupAuthorityProof(proofA, proofB), isTrue);
      expect(proofA.authorityData['recipientTransportPeerIds'], <String>[
        'physical-a',
        'physical-b',
      ]);
      expect(
        proofA.eventId,
        requests.first.transitionId,
        reason: 'only the outer delivery tuple may be target-qualified',
      );
      expect(durablePrepared[proofA.eventId], isNotNull);
      expect(durableComplete[proofA.eventId], isNotNull);

      Future<void> receiveAndRestart(
        GroupMemberDeviceIdentity recipient,
      ) async {
        final receiverHistory = <String, AuthenticatedGroupAuthorityProof>{};
        final receiver = InMemoryGroupRepository();
        await receiver.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Restart receiver',
            type: GroupType.chat,
            topicName: 'topic-$groupId',
            createdAt: DateTime.utc(2026, 8, 13),
            createdBy: selfPeerId,
            myRole: GroupRole.member,
          ),
        );
        await receiver.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: selfPeerId,
            username: 'Self',
            role: MemberRole.admin,
            publicKey: 'selfPubKey',
            mlKemPublicKey: source.mlKemPublicKey,
            devices: const <GroupMemberDeviceIdentity>[source],
            joinedAt: DateTime.utc(2026, 8, 13),
          ),
        );
        await receiver.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'oldKey==',
            createdAt: DateTime.utc(2026, 8, 13),
          ),
        );
        final row = rowsByRecipient[recipient.transportPeerId]!;
        final plaintext = plaintextByRecipient[recipient.transportPeerId]!;
        final result = await handleProtectedGroupAuthority(
          message: ChatMessage(
            from: source.transportPeerId,
            to: recipient.transportPeerId,
            content: row.sysText,
            timestamp: proofA.eventAt.toIso8601String(),
            isIncoming: true,
          ),
          ownTransportPeerId: recipient.transportPeerId,
          ownMlKemSecretKey: 'secret-${recipient.deviceId}',
          groupRepository: receiver,
          callDecrypt:
              ({
                required ownMlKemSecretKey,
                required kem,
                required ciphertext,
                required nonce,
              }) async => <String, dynamic>{'ok': true, 'plaintext': plaintext},
          callVerify:
              ({required publicKey, required data, required signature}) async =>
                  true,
          loadAuthorityProof:
              ({required groupId, required phase, required eventId}) async =>
                  receiverHistory['${phase.name}:$eventId'],
          appendAuthorityProof: ({required phase, required proof}) async {
            receiverHistory['${phase.name}:${proof.eventId}'] = proof;
          },
          applyReplay: (control, replayData) async {
            await receiver.saveKey(
              GroupKeyInfo(
                groupId: groupId,
                keyGeneration: replayData['keyGeneration'] as int,
                encryptedKey: replayData['encryptedKey'] as String,
                createdAt: proofA.eventAt,
              ),
            );
            return ProtectedGroupAuthorityApplyResult.applied;
          },
          now: () => proofA.eventAt,
        );
        expect(result, ProtectedGroupAuthorityHandleResult.applied);

        final restarted = InMemoryGroupRepository();
        await restarted.saveGroup((await receiver.getGroup(groupId))!);
        await restarted.saveKey((await receiver.getLatestKey(groupId))!);
        final duplicate = await handleProtectedGroupAuthority(
          message: ChatMessage(
            from: source.transportPeerId,
            to: recipient.transportPeerId,
            content: row.sysText,
            timestamp: proofA.eventAt.toIso8601String(),
            isIncoming: true,
          ),
          ownTransportPeerId: recipient.transportPeerId,
          ownMlKemSecretKey: 'secret-${recipient.deviceId}',
          groupRepository: restarted,
          callDecrypt:
              ({
                required ownMlKemSecretKey,
                required kem,
                required ciphertext,
                required nonce,
              }) async => <String, dynamic>{'ok': true, 'plaintext': plaintext},
          callVerify:
              ({required publicKey, required data, required signature}) async =>
                  true,
          loadAuthorityProof:
              ({required groupId, required phase, required eventId}) async =>
                  receiverHistory['${phase.name}:$eventId'],
          appendAuthorityProof: ({required phase, required proof}) async =>
              fail('completed restart must not append authority'),
          applyReplay: (_, _) async =>
              fail('completed restart must not replay the key'),
          now: () => proofA.eventAt,
        );
        expect(duplicate, ProtectedGroupAuthorityHandleResult.duplicate);
      }

      await receiveAndRestart(physicalA);
      await receiveAndRestart(physicalB);

      const zeroGroupId = 'group-zero-target';
      await groupRepo.saveGroup(
        GroupModel(
          id: zeroGroupId,
          name: 'Zero target',
          type: GroupType.chat,
          topicName: 'topic-$zeroGroupId',
          createdAt: DateTime.utc(2026, 8, 13),
          createdBy: selfPeerId,
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: zeroGroupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'selfPubKey',
          mlKemPublicKey: source.mlKemPublicKey,
          devices: const <GroupMemberDeviceIdentity>[source],
          joinedAt: DateTime.utc(2026, 8, 13),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: zeroGroupId,
          keyGeneration: 1,
          encryptedKey: 'zero-old-key',
          createdAt: DateTime.utc(2026, 8, 13),
        ),
      );
      final zeroResult = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: zeroGroupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sourceDeviceId: source.deviceId,
        sendP2PMessage: _sendOk,
      );
      expect(zeroResult.rotated, isTrue);
      final zeroProof = durableComplete.values.singleWhere(
        (proof) => proof.groupId == zeroGroupId,
      );
      expect(
        zeroProof.control,
        ProtectedGroupAuthorityControl.groupKeyUpdate.wireValue,
      );
      expect(
        zeroProof.authorityData['recipientTransportPeerIds'],
        isEmpty,
        reason: 'the common authority explicitly binds the empty remote ACL',
      );
      expect(
        rowsByRecipient.values.where((row) => row.groupId == zeroGroupId),
        isEmpty,
      );
      expect(durablePrepared[zeroProof.eventId], isNotNull);
    },
  );

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

      expect(result.key, isNull);
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

      expect(result.key, isNotNull);
      expect(result.key!.keyGeneration, 2);
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

    expect(result.key, isNull);
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

    expect(result.key, isNull);
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

    expect(writerResult.key, isNull);
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

    expect(removedResult.key, isNull);
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

      expect(result.key, isNotNull);
      expect(result.key!.keyGeneration, 8);
      expect(result.key!.encryptedKey, 'epoch8Key==');

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

    expect(result.key, isNull);
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

    expect(result.key, isNull);
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

    expect(result.key, isNull);
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

      expect(result.key, isNull);
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

    expect(result.key, isNotNull);
    expect(result.key!.keyGeneration, 2);
    expect(result.key!.encryptedKey, 'newKey==');

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
      expect(results.map((key) => key.key!.keyGeneration).toList(), [2, 3]);
      expect(results.map((key) => key.key!.encryptedKey).toSet(), hasLength(2));
      _expectNoSameEpochDifferentKeys(capturedPayloads);

      final payloadEpochs = capturedPayloads
          .map((payload) => payload['keyGeneration'] as int)
          .toSet();
      expect(payloadEpochs, {2, 3});
      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 3);
      expect(latestKey.encryptedKey, results.last.key!.encryptedKey);

      final firstPublishIndex = committedBridge.eventIndex('publish');
      final secondGenerateIndex = committedBridge.nthEventIndex('generate', 2);
      expect(firstPublishIndex, greaterThanOrEqualTo(0));
      expect(secondGenerateIndex, greaterThan(firstPublishIndex));
    },
  );

  test(
    'NW-013 restart retry reuses pending generated key and eventAt before commit',
    () async {
      // Promote-then-defer makes distribution failure non-fatal, so a pending
      // draft is now left uncommitted only by a PROMOTE failure: the key is
      // generated + drafted but `group:updateKey` for the NEW epoch fails, so
      // nothing commits and a later retry must reuse the same draft (no epoch
      // skip, same eventAt).
      final firstBridge = _PromoteFailBridge(failEpoch: 2);
      firstBridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': 'nw013-draft-key-a',
        'keyEpoch': 2,
      };
      firstBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'nw013-key-rotated',
      };
      final capturedPayloads = <Map<String, dynamic>>[];

      final firstResult = await rotateAndDistributeGroupKey(
        bridge: firstBridge,
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
          return true;
        },
      );

      expect(firstResult.key, isNull);
      final latestAfterFailedPromote = await groupRepo.getLatestKey(groupId);
      expect(latestAfterFailedPromote, isNotNull);
      expect(latestAfterFailedPromote!.keyGeneration, 1);
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

      expect(retryResult.key, isNotNull);
      expect(retryResult.key!.keyGeneration, 2);
      expect(retryResult.key!.encryptedKey, 'nw013-draft-key-a');
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

      expect(result.key, isNull);
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

    expect(result.key, isNotNull);

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
    'promotes then defers all recipients when direct transport is missing',
    () async {
      // No transport: every reachable member is deferred rather than aborting.
      // The epoch is still generated + promoted so the removed member loses the
      // live key; the remaining members converge later.
      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
      );

      expect(result.rotated, isTrue);
      expect(result.key!.keyGeneration, 2);
      expect(result.fullyDistributed, isFalse);
      expect(result.distributedDeviceCount, 0);
      expect(
        result.deferredPeerIds,
        unorderedEquals(<String>['peer-bob', 'peer-carol']),
      );
      expect(bridge.commandLog, contains('group:generateNextKey'));
      expect(
        _bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2),
        greaterThanOrEqualTo(0),
      );
      expect(bridge.commandLog, contains('group:publish'));

      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 2);
      expect(await groupRepo.getKeyByGeneration(groupId, 2), isNotNull);
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

    expect(result.key, isNull);

    // Verify no new key was saved — latest key should still be generation 1
    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
  });

  test('INV-D5 an enqueue throw never aborts rotation (deferred member still '
      'promoted + preserved, error telemetry emitted)', () async {
    // INV-D5: the per-peer deferred-distribution enqueue is best-effort. If
    // the enqueue closure throws, rotation MUST still complete (epoch promoted,
    // keyed members delivered, keyless member preserved in deferredPeerIds);
    // only a GROUP_ROTATE_KEY_DEFERRED_ENQUEUE_ERROR is emitted. A regression
    // moving the await outside its try/catch would resurface the abort bug.
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

    final enqueueAttempts = <(String, String, int)>[];

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
      sendP2PMessage: (peerId, message) async => true,
      enqueueDeferredDistribution:
          ({
            required String groupId,
            required String peerId,
            required int keyEpoch,
          }) async {
            enqueueAttempts.add((groupId, peerId, keyEpoch));
            throw Exception('enqueue boom');
          },
    );

    // Rotation succeeded despite the enqueue throw.
    expect(result.rotated, isTrue);
    expect(result.key!.keyGeneration, 2);
    expect(result.fullyDistributed, isFalse);
    expect(result.deferredPeerIds, <String>['peer-dave']);
    // The enqueue closure was reached once for the deferred peer.
    expect(enqueueAttempts, <(String, String, int)>[(groupId, 'peer-dave', 2)]);
    // The throw was caught and surfaced as telemetry, not propagated.
    final enqueueError = flowEvents.singleWhere(
      (event) => event['event'] == 'GROUP_ROTATE_KEY_DEFERRED_ENQUEUE_ERROR',
    );
    final enqueueErrorDetails = enqueueError['details'] as Map<String, dynamic>;
    expect(enqueueErrorDetails['error'], contains('enqueue boom'));
  });

  test(
    'promotes then defers a member that has no deliverable key device',
    () async {
      // Headline promote-then-defer fix: a keyless remaining member (Dave) no
      // longer aborts the rotation. The epoch is generated + promoted (so the
      // removed member loses the live key), keyed members are delivered, and the
      // keyless member is recorded as deferred for later convergence + enqueued.
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
      final deferredEnqueues = <(String, String, int)>[];

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
        enqueueDeferredDistribution:
            ({
              required String groupId,
              required String peerId,
              required int keyEpoch,
            }) async {
              deferredEnqueues.add((groupId, peerId, keyEpoch));
            },
      );

      // Epoch promoted; the keyless member is excluded-but-deferred.
      expect(result.rotated, isTrue);
      expect(result.key!.keyGeneration, 2);
      expect(result.fullyDistributed, isFalse);
      expect(result.deferredPeerIds, <String>['peer-dave']);
      // Keyed members were delivered; the keyless member was never sent to.
      expect(sentMessages.map((m) => m.$1).toSet(), <String>{
        'peer-bob',
        'peer-carol',
      });
      expect(result.distributedDeviceCount, 2);
      expect(bridge.commandLog, contains('group:generateNextKey'));
      expect(
        _bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2),
        greaterThanOrEqualTo(0),
      );
      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 2);
      expect(await groupRepo.getKeyByGeneration(groupId, 2), isNotNull);

      // The deferred member was enqueued through the injected seam exactly once.
      expect(deferredEnqueues, <(String, String, int)>[
        (groupId, 'peer-dave', 2),
      ]);

      // Telemetry: keyless-deferred + one per-peer queued + one partial summary.
      final keylessEvent = flowEvents.singleWhere(
        (event) =>
            event['event'] == 'GROUP_ROTATE_KEY_KEYLESS_MEMBERS_DEFERRED',
      );
      final keylessDetails = keylessEvent['details'] as Map<String, dynamic>;
      expect(keylessDetails['keylessCount'], 1);
      expect(keylessDetails['peerIds'], contains('peer-dav'));
      expect(
        flowEvents
            .where(
              (event) =>
                  event['event'] == 'GROUP_ROTATE_KEY_DEFERRED_REPAIR_QUEUED',
            )
            .length,
        1,
      );
      expect(
        flowEvents
            .where(
              (event) =>
                  event['event'] == 'GROUP_ROTATE_KEY_PARTIAL_DISTRIBUTION',
            )
            .length,
        1,
      );
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

      expect(result.key, isNotNull);
      expect(result.key!.keyGeneration, 2);
      expect(result.key!.encryptedKey, 'newKey==');

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

      expect(result.key, isNotNull);
      expect(result.key!.keyGeneration, 2);

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

      expect(result.key, isNull);
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
        expect(result.key, isNotNull);
        return result.key!;
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

      expect(result.key, isNotNull);
      expect(result.key!.keyGeneration, 2);
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
        expect(result.key, isNotNull);
        return result.key!;
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
        expect(result.key, isNotNull);
        return result.key!;
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
    'KE-015 partial key distribution promotes the epoch and defers the undelivered member',
    () async {
      // Carol's direct send fails; under promote-then-defer the epoch is still
      // promoted (Bob delivered) and Carol is recorded as deferred — the removed
      // member loses the key regardless of an undelivered remaining member.
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

      expect(result.rotated, isTrue);
      expect(result.key!.keyGeneration, 2);
      expect(result.fullyDistributed, isFalse);
      expect(result.deferredPeerIds, <String>['peer-carol']);
      expect(result.distributedDeviceCount, 1);
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
      expect(
        _bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2),
        greaterThanOrEqualTo(0),
      );
      expect(bridge.commandLog, contains('group:publish'));

      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 2);
      expect(await groupRepo.getKeyByGeneration(groupId, 2), isNotNull);
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

      expect(result.key, isNotNull);
      expect(result.key!.keyGeneration, 2);
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

  test('promotes and defers the member whose per-member encrypt fails', () async {
    // Bob's encrypt fails on every attempt; Carol succeeds. Under promote-then-
    // defer the epoch is promoted (Carol delivered) and Bob is deferred.
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

    // Only Carol receives a P2P message (Bob's encrypt failed); epoch promoted.
    expect(result.rotated, isTrue);
    expect(result.key!.keyGeneration, 2);
    expect(result.fullyDistributed, isFalse);
    expect(result.deferredPeerIds, <String>['peer-bob']);
    expect(result.distributedDeviceCount, 1);
    expect(sentMessages.length, 1);
    expect(sentMessages.first.$1, 'peer-carol');
    expect(
      _bridgeCommandIndex(selectiveBridge, 'group:updateKey', keyEpoch: 2),
      greaterThanOrEqualTo(0),
    );
    expect(selectiveBridge.commandLog, contains('group:publish'));
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
    expect(result.key, isNotNull);
    expect(result.key!.keyGeneration, 2);

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

      // Bob's send failed (deferred), Carol then delivered → epoch promoted.
      expect(result.rotated, isTrue);
      expect(result.key!.keyGeneration, 2);
      expect(result.deferredPeerIds, <String>['peer-bob']);
      expect(carolStarted, isTrue);
      expect(
        _bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2),
        greaterThanOrEqualTo(0),
      );
      expect(bridge.commandLog, contains('group:publish'));
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

      expect(result.key, isNotNull);
      expect(result.key!.keyGeneration, 2);
      expect(
        _bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2),
        isNot(-1),
      );
      expect(bridge.commandLog, contains('group:publish'));
    },
  );

  test(
    'promotes and defers all recipients when direct sends time out',
    () async {
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

      // Every send timed out → all remaining members deferred, epoch still
      // promoted so the removed member loses the live key.
      expect(result.rotated, isTrue);
      expect(result.key!.keyGeneration, 2);
      expect(result.distributedDeviceCount, 0);
      expect(
        result.deferredPeerIds,
        unorderedEquals(<String>['peer-bob', 'peer-carol']),
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

  test(
    'mixed cohort: keyed-direct delivered, keyed-inbox delivered, keyless deferred',
    () async {
      // Bob delivers via direct send, Carol via inbox fallback, Dave (keyless)
      // is deferred. The epoch is promoted; only Dave is deferred and the
      // device-delivery count reflects the two members reached.
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

      final directDelivered = <String>[];
      final inboxDelivered = <String>[];

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
          if (peerId == 'peer-bob') {
            directDelivered.add(peerId);
            return true;
          }
          return false; // Carol's direct send fails → inbox fallback.
        },
        storeP2PMessageInInbox: (peerId, message) async {
          inboxDelivered.add(peerId);
          return true;
        },
      );

      expect(result.rotated, isTrue);
      expect(result.key!.keyGeneration, 2);
      expect(result.fullyDistributed, isFalse);
      expect(result.deferredPeerIds, <String>['peer-dave']);
      expect(result.distributedDeviceCount, 2);
      expect(directDelivered, <String>['peer-bob']);
      expect(inboxDelivered, <String>['peer-carol']);
    },
  );

  test(
    'genuine generate failure returns notRotated and enqueues nothing',
    () async {
      // INV-R4: only a true generate/promote failure yields notRotated, and the
      // deferred-distribution seam is never invoked on that path.
      bridge.responses['group:generateNextKey'] = {
        'ok': false,
        'errorCode': 'GENERATE_FAILED',
      };
      final deferredEnqueues = <String>[];

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: _sendOk,
        enqueueDeferredDistribution:
            ({
              required String groupId,
              required String peerId,
              required int keyEpoch,
            }) async {
              deferredEnqueues.add(peerId);
            },
      );

      expect(result.rotated, isFalse);
      expect(result.deferredPeerIds, isEmpty);
      expect(deferredEnqueues, isEmpty);
      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey!.keyGeneration, 1);
    },
  );

  test(
    'falls back to the process-wide deferred-distribution sink when no explicit '
    'seam is passed',
    () async {
      // Production rotate call sites (admin removal / leave / backstop) pass no
      // explicit seam; the rotation must persist deferred peers through the
      // global sink wired by main.dart instead.
      final globalEnqueues = <(String, String, int)>[];
      setDeferredGroupKeyDistributionSink(({
        required groupId,
        required peerId,
        required keyEpoch,
      }) async {
        globalEnqueues.add((groupId, peerId, keyEpoch));
      });
      addTearDown(() => setDeferredGroupKeyDistributionSink(null));

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

      expect(result.rotated, isTrue);
      expect(result.deferredPeerIds, <String>['peer-dave']);
      expect(globalEnqueues, <(String, String, int)>[
        (groupId, 'peer-dave', 2),
      ]);
    },
  );

  test('explicit seam takes precedence over the process-wide sink', () async {
    final globalEnqueues = <String>[];
    final explicitEnqueues = <String>[];
    setDeferredGroupKeyDistributionSink(({
      required groupId,
      required peerId,
      required keyEpoch,
    }) async {
      globalEnqueues.add(peerId);
    });
    addTearDown(() => setDeferredGroupKeyDistributionSink(null));

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

    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: _sendOk,
      enqueueDeferredDistribution:
          ({required groupId, required peerId, required keyEpoch}) async {
            explicitEnqueues.add(peerId);
          },
    );

    expect(explicitEnqueues, <String>['peer-dave']);
    // The global sink is NOT used when an explicit seam is provided.
    expect(globalEnqueues, isEmpty);
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

/// Fails the PROMOTE `group:updateKey` (the post-generation epoch) while letting
/// the pre-generation resync `group:updateKey` (the current epoch) succeed, so a
/// rotation generates + drafts a key but cannot commit it — exercising the
/// pending-draft reuse path on a later retry (the only path that now leaves an
/// uncommitted draft under promote-then-defer).
class _PromoteFailBridge extends PassthroughCryptoBridge {
  _PromoteFailBridge({required this.failEpoch});

  final int failEpoch;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:updateKey') {
      final payload = parsed['payload'] as Map<String, dynamic>?;
      if (payload != null && payload['keyEpoch'] == failEpoch) {
        sendCallCount++;
        lastSentMessage = message;
        sentMessages.add(message);
        lastCommand = cmd;
        commandLog.add(cmd!);
        return jsonEncode({'ok': false, 'errorCode': 'PROMOTE_FAILED'});
      }
    }
    return super.send(message);
  }
}
