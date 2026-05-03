import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package_tombstone.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

GroupInviteMembershipFreshnessProof _makeFreshnessProof({
  required String inviteId,
  required String groupId,
  required String? recipientPeerId,
  required Map<String, dynamic> groupConfig,
  String? recipientDeviceId,
  String? recipientTransportPeerId,
  String? recipientMlKemPublicKey,
  String? recipientKeyPackageId,
  String? recipientKeyPackagePublicMaterial,
  required DateTime issuedAt,
  DateTime? expiresAt,
}) {
  final stateHash = buildGroupConfigStateHash(
    groupId: groupId,
    groupConfig: groupConfig,
  );
  return GroupInviteMembershipFreshnessProof(
    inviteId: inviteId,
    groupId: groupId,
    recipientPeerId: recipientPeerId,
    recipientDeviceId: recipientDeviceId,
    recipientTransportPeerId: recipientTransportPeerId,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    recipientKeyPackageId: recipientKeyPackageId,
    recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
    inviterPeerId: '12D3KooWAlice',
    inviterPublicKey: 'alicePubKey64',
    keyEpoch: 1,
    groupConfigStateHash: stateHash,
    membershipWatermark: stateHash,
    issuedAt: issuedAt.toUtc(),
    expiresAt:
        expiresAt ?? issuedAt.toUtc().add(groupInviteMembershipFreshnessTtl),
    inviterMemberSnapshot: {
      'peerId': '12D3KooWAlice',
      'username': 'Alice',
      'role': 'admin',
      'publicKey': 'alicePubKey64',
      'mlKemPublicKey': 'aliceMlKem64',
    },
  );
}

void main() {
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;

  PendingGroupInvite makeInvite({
    String inviteId = 'invite-1',
    DateTime? receivedAt,
    String? overrideGroupKey,
    Map<String, dynamic>? groupConfig,
    GroupInviteReusePolicy reusePolicy = GroupInviteReusePolicy.singleUse,
    String? recipientDeviceId,
    String? recipientTransportPeerId,
    String? recipientMlKemPublicKey,
    String? recipientKeyPackageId,
    String? recipientKeyPackagePublicMaterial,
  }) {
    final effectiveReceivedAt = (receivedAt ?? DateTime.now().toUtc()).toUtc();
    final createdAt = effectiveReceivedAt.subtract(const Duration(hours: 6));
    final inviteTimestamp = createdAt.add(const Duration(minutes: 5));
    final resolvedGroupConfig =
        groupConfig ??
        {
          'name': 'Book Club',
          'groupType': 'chat',
          'description': 'A group for book lovers',
          'members': [
            {
              'peerId': '12D3KooWAlice',
              'username': 'Alice',
              'role': 'admin',
              'publicKey': 'alicePubKey64',
              'mlKemPublicKey': 'aliceMlKem64',
            },
            {
              'peerId': '12D3KooWReceiver',
              'username': 'Receiver',
              'role': 'writer',
              'publicKey': 'receiverPubKey64',
              'mlKemPublicKey': 'receiverMlKem64',
            },
          ],
          'createdBy': '12D3KooWAlice',
          'createdAt': createdAt.toIso8601String(),
        };
    final policyExpiresAt = effectiveReceivedAt.add(pendingGroupInviteTtl);
    final welcomeKeyPackage =
        recipientKeyPackageId != null &&
            recipientKeyPackagePublicMaterial != null &&
            recipientDeviceId != null &&
            recipientTransportPeerId != null &&
            recipientMlKemPublicKey != null
        ? GroupWelcomeKeyPackage.create(
            packageId: recipientKeyPackageId,
            publicMaterial: recipientKeyPackagePublicMaterial,
            recipientPeerId: '12D3KooWReceiver',
            recipientDeviceId: recipientDeviceId,
            recipientTransportPeerId: recipientTransportPeerId,
            recipientMlKemPublicKey: recipientMlKemPublicKey,
            inviteId: inviteId,
            groupId: 'grp-abc123',
            keyEpoch: 1,
            issuedAt: inviteTimestamp,
            expiresAt: policyExpiresAt,
          )
        : null;
    final payload = GroupInvitePayload(
      id: inviteId,
      groupId: 'grp-abc123',
      groupKey: overrideGroupKey ?? 'base64-key',
      keyEpoch: 1,
      groupConfig: resolvedGroupConfig,
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      timestamp: inviteTimestamp.toIso8601String(),
      recipientPeerId: '12D3KooWReceiver',
      recipientDeviceId: recipientDeviceId,
      recipientTransportPeerId: recipientTransportPeerId,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      recipientKeyPackageId: recipientKeyPackageId,
      recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
      welcomeKeyPackage: welcomeKeyPackage,
      invitePolicy: GroupInvitePolicy(
        expiresAt: policyExpiresAt,
        allowedDevices: [recipientDeviceId ?? '12D3KooWReceiver'],
        assignedRole: 'writer',
        canInviteOthers: false,
        joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
        keyEpoch: 1,
        reusePolicy: reusePolicy,
        welcomeKeyPackageId: welcomeKeyPackage?.packageId,
        welcomeKeyPackagePublicMaterialHash:
            welcomeKeyPackage?.publicMaterialHash,
        welcomeKeyPackageExpiresAt: welcomeKeyPackage?.expiresAt,
      ),
      membershipFreshnessProof: _makeFreshnessProof(
        inviteId: inviteId,
        groupId: 'grp-abc123',
        recipientPeerId: '12D3KooWReceiver',
        recipientDeviceId: recipientDeviceId,
        recipientTransportPeerId: recipientTransportPeerId,
        recipientMlKemPublicKey: recipientMlKemPublicKey,
        recipientKeyPackageId: recipientKeyPackageId,
        recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
        groupConfig: resolvedGroupConfig,
        issuedAt: inviteTimestamp,
      ),
    ).withInviteSignature(signature: 'signed-invite-by-alice');
    return PendingGroupInvite.fromPayload(
      payload,
      receivedAt: effectiveReceivedAt,
    );
  }

  ContactModel aliceContact() {
    return const ContactModel(
      peerId: '12D3KooWAlice',
      publicKey: 'alicePubKey64',
      rendezvous: '/ip4/0.0.0.0',
      username: 'Alice',
      signature: 'sig',
      scannedAt: '2026-01-01T00:00:00Z',
      mlKemPublicKey: 'aliceMlKem64',
    );
  }

  PendingGroupInvite signedInvite(PendingGroupInvite invite) {
    final envelope = jsonDecode(invite.payloadJson) as Map<String, dynamic>;
    final payload = envelope['payload'] as Map<String, dynamic>;
    final parsedPayload = GroupInvitePayload.fromInnerJson(jsonEncode(payload));
    if (parsedPayload == null) {
      throw StateError('test invite payload must be parseable before signing');
    }
    payload['inviteSignature'] = {
      'signatureAlgorithm': 'ed25519',
      'signedPayload': parsedPayload.canonicalInviteSignedPayload(),
      'signature': 'signed-invite-by-alice',
    };
    return PendingGroupInvite.fromMap({
      ...invite.toMap(),
      'payload_json': jsonEncode(envelope),
    });
  }

  Map<String, dynamic> receiverDeviceBoundConfig() {
    return {
      'name': 'Book Club',
      'groupType': 'chat',
      'description': 'A group for book lovers',
      'members': [
        {
          'peerId': '12D3KooWAlice',
          'username': 'Alice',
          'role': 'admin',
          'publicKey': 'alicePubKey64',
          'mlKemPublicKey': 'aliceMlKem64',
          'devices': [
            {
              'deviceId': 'alice-device-1',
              'transportPeerId': 'alice-device-1',
              'deviceSigningPublicKey': 'alicePubKey64',
              'mlKemPublicKey': 'aliceMlKem64',
              'status': 'active',
            },
          ],
        },
        {
          'peerId': '12D3KooWReceiver',
          'username': 'Receiver',
          'role': 'writer',
          'publicKey': 'receiverPubKey64',
          'mlKemPublicKey': 'receiverMlKem64',
          'devices': [
            {
              'deviceId': 'receiver-device-1',
              'transportPeerId': 'receiver-device-1',
              'deviceSigningPublicKey': 'receiverPubKey64',
              'mlKemPublicKey': 'receiverMlKem64',
              'keyPackageId': 'receiver-kp-1',
              'keyPackagePublicMaterial': 'receiver-kpm-1',
              'status': 'active',
            },
          ],
        },
      ],
      'createdBy': '12D3KooWAlice',
      'createdAt': '2026-03-02T00:00:00.000Z',
    };
  }

  Future<Map<String, dynamic>> signedReplayInboxMessage({
    required String payloadType,
    required Map<String, dynamic> plaintextPayload,
    required String messageId,
    String senderPeerId = '12D3KooWAlice',
    String senderPublicKey = 'alicePubKey64',
    String senderPrivateKey = 'alicePrivateKey64',
  }) async {
    final replayEnvelope = await buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'grp-abc123',
      payloadType: payloadType,
      plaintext: jsonEncode(plaintextPayload),
      messageId: messageId,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      keyInfo: GroupKeyInfo(
        groupId: 'grp-abc123',
        keyGeneration: 1,
        encryptedKey: 'base64-key',
        createdAt: DateTime.utc(2026, 3, 2),
      ),
    );
    return {'from': senderPeerId, 'message': replayEnvelope};
  }

  setUp(() {
    pendingInviteRepo = InMemoryPendingGroupInviteRepository();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    contactRepo = FakeContactRepository()..seed([aliceContact()]);
    bridge = FakeBridge();
  });

  group('acceptPendingGroupInvite', () {
    test('accepts pending invite, persists group, and drains inbox', () async {
      final inboxTimestamp = DateTime.now().toUtc().subtract(
        const Duration(hours: 1),
      );
      await pendingInviteRepo.savePendingInvite(makeInvite());
      final signedOfflineMessage = await signedReplayInboxMessage(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        messageId: 'offline-msg-1',
        plaintextPayload: {
          'groupId': 'grp-abc123',
          'messageId': 'offline-msg-1',
          'senderId': '12D3KooWAlice',
          'senderUsername': 'Alice',
          'keyEpoch': 1,
          'text': 'Welcome back',
          'timestamp': inboxTimestamp.toIso8601String(),
        },
      );
      bridge.responses['group:inboxRetrieveCursor'] = {
        'ok': true,
        'messages': [signedOfflineMessage],
        'cursor': '',
      };
      final signedEnvelope =
          jsonDecode(signedOfflineMessage['message'] as String)
              as Map<String, dynamic>;
      expect(signedEnvelope['kind'], groupOfflineReplayEnvelopeKind);
      expect(signedEnvelope['signature'], isA<String>());

      final (result, group) = await acceptPendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupId: 'grp-abc123',
      );

      expect(result, AcceptPendingGroupInviteResult.success);
      expect(group, isNotNull);
      expect(group!.name, 'Book Club');
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
      final consumption = await pendingInviteRepo.getConsumedInvite('invite-1');
      expect(consumption, isNotNull);
      expect(consumption!.groupId, 'grp-abc123');
      expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
      expect(msgRepo.count, 1);
      expect(bridge.commandLog, contains('group:join'));
      expect(bridge.commandLog, contains('group:inboxRetrieveCursor'));
    });

    test(
      'accept replays backlog reactions when reactionRepo is provided',
      () async {
        final backlogTimestamp = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 5))
            .toIso8601String();
        final reactionTimestamp = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 4))
            .toIso8601String();
        final reactionRepo = FakeReactionRepository();
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          reactionRepo: reactionRepo,
        );
        addTearDown(listener.dispose);

        await pendingInviteRepo.savePendingInvite(makeInvite());
        final signedOfflineMessage = await signedReplayInboxMessage(
          payloadType: groupOfflineReplayPayloadTypeMessage,
          messageId: 'offline-msg-1',
          plaintextPayload: {
            'groupId': 'grp-abc123',
            'messageId': 'offline-msg-1',
            'senderId': '12D3KooWAlice',
            'senderUsername': 'Alice',
            'keyEpoch': 1,
            'text': 'Welcome back',
            'timestamp': backlogTimestamp,
          },
        );
        final signedReactionMessage = await signedReplayInboxMessage(
          payloadType: groupOfflineReplayPayloadTypeReaction,
          messageId: 'reaction-1',
          plaintextPayload: {
            'id': 'reaction-1',
            'messageId': 'offline-msg-1',
            'emoji': '👍',
            'action': 'add',
            'senderPeerId': '12D3KooWAlice',
            'timestamp': reactionTimestamp,
          },
        );
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [signedOfflineMessage, signedReactionMessage],
          'cursor': '',
        };
        final signedReactionEnvelope =
            jsonDecode(signedReactionMessage['message'] as String)
                as Map<String, dynamic>;
        expect(
          signedReactionEnvelope['payloadType'],
          groupOfflineReplayPayloadTypeReaction,
        );
        expect(signedReactionEnvelope['signature'], isA<String>());

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          reactionRepo: reactionRepo,
          groupMessageListener: listener,
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(msgRepo.count, 1);

        final reactions = await reactionRepo.getReactionsForMessage(
          'offline-msg-1',
        );
        expect(reactions, hasLength(1));
        expect(reactions.single.senderPeerId, '12D3KooWAlice');
        expect(reactions.single.emoji, '👍');
      },
    );

    test(
      'EK004 successful accept stores signed member_joined replay envelope',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
        expect(msgRepo.count, 1);

        final latestMessage = await msgRepo.getLatestMessage('grp-abc123');
        expect(latestMessage, isNotNull);
        expect(latestMessage!.text, 'Receiver joined the group');

        final publishMessage = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;
        expect(sysText['__sys'], 'member_joined');
        expect(sysText['member']['peerId'], '12D3KooWReceiver');
        expect(sysText['member']['username'], 'Receiver');

        final inboxStoreMessage = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:inboxStore';
        });
        final inboxPayload =
            (jsonDecode(inboxStoreMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final replayEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['payloadType'], 'group_message');
        expect(replayEnvelope['senderPeerId'], '12D3KooWReceiver');
        expect(replayEnvelope['senderPublicKey'], 'receiver-public-key');
        expect(replayEnvelope['signatureAlgorithm'], 'ed25519');
        expect(replayEnvelope['signedPayload'], isA<String>());
        expect(replayEnvelope['signature'], isA<String>());
      },
    );

    test(
      'bridgeError keeps a durable join owner and clears the pending invite row',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'JOIN_FAILED',
        };
        bridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'PUBLISH_FAILED',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
        );

        expect(result, AcceptPendingGroupInviteResult.bridgeError);
        expect(group, isNotNull);
        expect(group!.id, 'grp-abc123');
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getConsumedInvite('invite-1'),
          isNotNull,
        );
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
        expect(msgRepo.count, 1);
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        final latestMessage = await msgRepo.getLatestMessage('grp-abc123');
        expect(latestMessage, isNotNull);
        expect(latestMessage!.text, 'Receiver joined the group');
      },
    );

    test(
      'missing join material stays pending for repair without creating group state',
      () async {
        await pendingInviteRepo.savePendingInvite(
          makeInvite(overrideGroupKey: ''),
        );

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
        );

        expect(result, AcceptPendingGroupInviteResult.repairPending);
        expect(group, isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'IJ014 repairable join-material failure keeps pending invite without state or mailbox drain',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'INVALID_JOIN_MATERIAL',
          'errorMessage': 'stale welcome key material',
        };
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': const [],
          'cursor': '',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
        );

        expect(result, AcceptPendingGroupInviteResult.repairPending);
        expect(group, isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getMembers('grp-abc123'), isEmpty);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, contains('group:join'));
        expect(bridge.commandLog, isNot(contains('group:inboxRetrieveCursor')));
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'IJ014 repaired pending invite can retry successfully after key material refresh',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'KEY_PACKAGE_DECRYPT_FAILED',
          'errorMessage': 'undecryptable key package',
        };

        final (firstResult, firstGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
        );

        expect(firstResult, AcceptPendingGroupInviteResult.repairPending);
        expect(firstGroup, isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await groupRepo.getGroup('grp-abc123'), isNull);

        bridge.responses['group:join'] = {'ok': true};

        final (secondResult, secondGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
        );

        expect(secondResult, AcceptPendingGroupInviteResult.success);
        expect(secondGroup, isNotNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getConsumedInvite('invite-1'),
          isNotNull,
        );
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:join'),
          hasLength(2),
        );
      },
    );

    test(
      'IJ001 invalid pending policy stays pending for repair without state or join',
      () async {
        final validInvite = makeInvite();
        final envelope =
            jsonDecode(validInvite.payloadJson) as Map<String, dynamic>;
        (envelope['payload'] as Map<String, dynamic>).remove('invitePolicy');
        final invalidInvite = PendingGroupInvite.fromMap({
          ...validInvite.toMap(),
          'payload_json': jsonEncode(envelope),
        });
        await pendingInviteRepo.savePendingInvite(invalidInvite);

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
        );

        expect(result, AcceptPendingGroupInviteResult.repairPending);
        expect(group, isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'IJ001 contradictory pending policy stays pending for repair without state or join',
      () async {
        final validInvite = makeInvite();
        final envelope =
            jsonDecode(validInvite.payloadJson) as Map<String, dynamic>;
        final payloadMap = envelope['payload'] as Map<String, dynamic>;
        (((payloadMap['invitePolicy']
                    as Map<String, dynamic>)['invitePermissions'])
                as Map<String, dynamic>)['assignedRole'] =
            'reader';
        final invalidInvite = PendingGroupInvite.fromMap({
          ...validInvite.toMap(),
          'payload_json': jsonEncode(envelope),
        });
        await pendingInviteRepo.savePendingInvite(invalidInvite);

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
        );

        expect(result, AcceptPendingGroupInviteResult.repairPending);
        expect(group, isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'IJ005 missing reuse policy stays pending for repair without state or join',
      () async {
        final validInvite = makeInvite();
        final envelope =
            jsonDecode(validInvite.payloadJson) as Map<String, dynamic>;
        final payloadMap = envelope['payload'] as Map<String, dynamic>;
        (payloadMap['invitePolicy'] as Map<String, dynamic>).remove(
          'reusePolicy',
        );
        final invalidInvite = PendingGroupInvite.fromMap({
          ...validInvite.toMap(),
          'payload_json': jsonEncode(envelope),
        });
        await pendingInviteRepo.savePendingInvite(invalidInvite);

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
        );

        expect(result, AcceptPendingGroupInviteResult.repairPending);
        expect(group, isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

    test('returns expired and removes stale invite', () async {
      await pendingInviteRepo.savePendingInvite(
        makeInvite(receivedAt: DateTime.utc(2026, 4, 1, 13, 0)),
      );

      final (result, group) = await acceptPendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupId: 'grp-abc123',
        now: DateTime.utc(2026, 4, 12, 13, 0),
      );

      expect(result, AcceptPendingGroupInviteResult.expired);
      expect(group, isNull);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
      expect(await groupRepo.getGroup('grp-abc123'), isNull);
      expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
      expect(bridge.commandLog, isNot(contains('group:join')));
      expect(msgRepo.count, 0);
    });

    test(
      'returns revoked and removes stale pending row without joining',
      () async {
        final revokedAt = DateTime.utc(2026, 4, 29, 12);
        await pendingInviteRepo.savePendingInvite(
          makeInvite(receivedAt: revokedAt),
        );
        await pendingInviteRepo.saveRevokedInvite(
          GroupInviteRevocation(
            inviteId: 'invite-1',
            groupId: 'grp-abc123',
            revokedAt: revokedAt,
            expiresAt: revokedAt.add(const Duration(days: 7)),
            revokedBy: '12D3KooWAlice',
          ),
        );

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          now: revokedAt.add(const Duration(minutes: 10)),
        );

        expect(result, AcceptPendingGroupInviteResult.revoked);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'returns alreadyUsed and removes stale pending row without joining',
      () async {
        final consumedAt = DateTime.utc(2026, 4, 29, 12);
        await pendingInviteRepo.savePendingInvite(
          makeInvite(receivedAt: consumedAt),
        );
        await pendingInviteRepo.saveConsumedInvite(
          GroupInviteConsumption(
            inviteId: 'invite-1',
            groupId: 'grp-abc123',
            consumedAt: consumedAt,
            expiresAt: consumedAt.add(const Duration(days: 7)),
          ),
        );

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          now: consumedAt.add(const Duration(minutes: 10)),
        );

        expect(result, AcceptPendingGroupInviteResult.alreadyUsed);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'EC001 invalid invite accepts classify failures without group or key state',
      () async {
        final receivedAt = DateTime.utc(2026, 4, 29, 12);

        Future<void> resetRepos() async {
          pendingInviteRepo = InMemoryPendingGroupInviteRepository();
          groupRepo = InMemoryGroupRepository();
          msgRepo = InMemoryGroupMessageRepository();
          contactRepo = FakeContactRepository()..seed([aliceContact()]);
          bridge = FakeBridge();
        }

        Future<void> expectRejectedAccept({
          required String label,
          required AcceptPendingGroupInviteResult expected,
          required Future<void> Function() arrange,
          String? senderPeerId,
          DateTime? now,
        }) async {
          await resetRepos();
          await arrange();

          final (result, group) = await acceptPendingGroupInvite(
            pendingInviteRepo: pendingInviteRepo,
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            msgRepo: msgRepo,
            bridge: bridge,
            groupId: 'grp-abc123',
            senderPeerId: senderPeerId,
            now: now ?? receivedAt.add(const Duration(minutes: 10)),
          );

          expect(result, expected, reason: label);
          expect(group, isNull, reason: label);
          expect(
            await pendingInviteRepo.getPendingInvite('grp-abc123'),
            isNull,
            reason: label,
          );
          expect(await groupRepo.getGroup('grp-abc123'), isNull, reason: label);
          expect(
            await groupRepo.getLatestKey('grp-abc123'),
            isNull,
            reason: label,
          );
          expect(
            bridge.commandLog,
            isNot(contains('group:join')),
            reason: label,
          );
          expect(msgRepo.count, 0, reason: label);
        }

        await expectRejectedAccept(
          label: 'expired',
          expected: AcceptPendingGroupInviteResult.expired,
          arrange: () async {
            await pendingInviteRepo.savePendingInvite(
              makeInvite(receivedAt: receivedAt),
            );
          },
          now: receivedAt
              .add(pendingGroupInviteTtl)
              .add(const Duration(seconds: 1)),
        );

        await expectRejectedAccept(
          label: 'revoked',
          expected: AcceptPendingGroupInviteResult.revoked,
          arrange: () async {
            await pendingInviteRepo.savePendingInvite(
              makeInvite(receivedAt: receivedAt),
            );
            await pendingInviteRepo.saveRevokedInvite(
              GroupInviteRevocation(
                inviteId: 'invite-1',
                groupId: 'grp-abc123',
                revokedAt: receivedAt,
                expiresAt: receivedAt.add(const Duration(days: 7)),
                revokedBy: '12D3KooWAlice',
              ),
            );
          },
        );

        await expectRejectedAccept(
          label: 'wrong identity',
          expected: AcceptPendingGroupInviteResult.wrongIdentity,
          arrange: () async {
            await pendingInviteRepo.savePendingInvite(
              signedInvite(makeInvite(receivedAt: receivedAt)),
            );
          },
          senderPeerId: '12D3KooWEve',
        );

        await expectRejectedAccept(
          label: 'malformed signed payload',
          expected: AcceptPendingGroupInviteResult.invalidPayload,
          arrange: () async {
            final invite = signedInvite(makeInvite(receivedAt: receivedAt));
            final envelope =
                jsonDecode(invite.payloadJson) as Map<String, dynamic>;
            (envelope['payload'] as Map<String, dynamic>)['groupKey'] =
                'tampered-key';
            await pendingInviteRepo.savePendingInvite(
              PendingGroupInvite.fromMap({
                ...invite.toMap(),
                'payload_json': jsonEncode(envelope),
              }),
            );
          },
        );

        await expectRejectedAccept(
          label: 'already used',
          expected: AcceptPendingGroupInviteResult.alreadyUsed,
          arrange: () async {
            await pendingInviteRepo.savePendingInvite(
              makeInvite(receivedAt: receivedAt),
            );
            await pendingInviteRepo.saveConsumedInvite(
              GroupInviteConsumption(
                inviteId: 'invite-1',
                groupId: 'grp-abc123',
                consumedAt: receivedAt,
                expiresAt: receivedAt.add(const Duration(days: 7)),
              ),
            );
          },
        );
      },
    );

    test(
      'IJ005 multi-use accept ignores local consumption tombstone and does not overwrite it',
      () async {
        final consumedAt = DateTime.utc(2026, 4, 29, 12);
        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            receivedAt: consumedAt,
            reusePolicy: GroupInviteReusePolicy.multiUse,
          ),
        );
        await pendingInviteRepo.saveConsumedInvite(
          GroupInviteConsumption(
            inviteId: 'invite-1',
            groupId: 'grp-abc123',
            consumedAt: consumedAt,
            expiresAt: consumedAt.add(const Duration(days: 7)),
          ),
        );

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          now: consumedAt.add(const Duration(minutes: 10)),
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        final consumption = await pendingInviteRepo.getConsumedInvite(
          'invite-1',
        );
        expect(consumption, isNotNull);
        expect(consumption!.consumedAt, consumedAt);
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
        expect(bridge.commandLog, contains('group:join'));
      },
    );

    test(
      'returns duplicateGroup and removes pending row when group already exists',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());
        await groupRepo.saveGroup(
          GroupModel(
            id: 'grp-abc123',
            name: 'Joined Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/grp-abc123',
            createdAt: DateTime.utc(2026, 3, 2),
            createdBy: '12D3KooWAlice',
            myRole: GroupRole.member,
          ),
        );

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
        );

        expect(result, AcceptPendingGroupInviteResult.duplicateGroup);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
      },
    );

    test(
      'IJ002 tampered persisted signed invite is deleted without state or join',
      () async {
        final invite = signedInvite(makeInvite());
        final envelope = jsonDecode(invite.payloadJson) as Map<String, dynamic>;
        (envelope['payload'] as Map<String, dynamic>)['groupKey'] =
            'tampered-key';
        await pendingInviteRepo.savePendingInvite(
          PendingGroupInvite.fromMap({
            ...invite.toMap(),
            'payload_json': jsonEncode(envelope),
          }),
        );

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
        );

        expect(result, AcceptPendingGroupInviteResult.invalidPayload);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'PREREQ-INVITER-FRESHNESS accept deletes stale self-consistent invite without state',
      () async {
        final receivedAt = DateTime.utc(2026, 3, 2, 12);
        await pendingInviteRepo.savePendingInvite(
          makeInvite(receivedAt: receivedAt),
        );

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          now: receivedAt.add(const Duration(hours: 19)),
        );

        expect(result, AcceptPendingGroupInviteResult.invalidPayload);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(pendingInviteRepo.consumedCount, 0);
        expect(pendingInviteRepo.welcomeKeyPackageTombstoneCount, 0);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(bridge.commandLog, isNot(contains('group:inboxRetrieveCursor')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'IJ013 copied pending invite rejects wrong local identity before state or join',
      () async {
        await pendingInviteRepo.savePendingInvite(signedInvite(makeInvite()));

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWEve',
        );

        expect(result, AcceptPendingGroupInviteResult.wrongIdentity);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'device-bound pending invite rejects wrong transport, key package, or missing local device before state',
      () async {
        final deviceBoundConfig = {
          'name': 'Book Club',
          'groupType': 'chat',
          'description': 'A group for book lovers',
          'members': [
            {
              'peerId': '12D3KooWAlice',
              'username': 'Alice',
              'role': 'admin',
              'publicKey': 'alicePubKey64',
              'mlKemPublicKey': 'aliceMlKem64',
              'devices': [
                {
                  'deviceId': 'alice-device-1',
                  'transportPeerId': 'alice-device-1',
                  'deviceSigningPublicKey': 'alicePubKey64',
                  'mlKemPublicKey': 'aliceMlKem64',
                  'status': 'active',
                },
              ],
            },
            {
              'peerId': '12D3KooWReceiver',
              'username': 'Receiver',
              'role': 'writer',
              'publicKey': 'receiverPubKey64',
              'mlKemPublicKey': 'receiverMlKem64',
              'devices': [
                {
                  'deviceId': 'receiver-device-1',
                  'transportPeerId': 'receiver-device-1',
                  'deviceSigningPublicKey': 'receiverPubKey64',
                  'mlKemPublicKey': 'receiverMlKem64',
                  'keyPackageId': 'receiver-kp-1',
                  'keyPackagePublicMaterial': 'receiver-kpm-1',
                  'status': 'active',
                },
              ],
            },
          ],
          'createdBy': '12D3KooWAlice',
          'createdAt': '2026-03-02T00:00:00.000Z',
        };

        Future<void> expectRejected({
          required String label,
          String? ownDeviceId,
          String? ownTransportPeerId,
          String? ownKeyPackageId = 'receiver-kp-1',
        }) async {
          pendingInviteRepo = InMemoryPendingGroupInviteRepository();
          groupRepo = InMemoryGroupRepository();
          msgRepo = InMemoryGroupMessageRepository();
          bridge = FakeBridge();
          final invite = signedInvite(
            makeInvite(
              groupConfig: deviceBoundConfig,
              recipientDeviceId: 'receiver-device-1',
              recipientTransportPeerId: 'receiver-device-1',
              recipientMlKemPublicKey: 'receiverMlKem64',
              recipientKeyPackageId: 'receiver-kp-1',
              recipientKeyPackagePublicMaterial: 'receiver-kpm-1',
            ),
          );
          await pendingInviteRepo.savePendingInvite(invite);

          final (result, group) = await acceptPendingGroupInvite(
            pendingInviteRepo: pendingInviteRepo,
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            msgRepo: msgRepo,
            bridge: bridge,
            groupId: 'grp-abc123',
            senderPeerId: '12D3KooWReceiver',
            ownDeviceId: ownDeviceId,
            ownTransportPeerId: ownTransportPeerId,
            ownMlKemPublicKey: 'receiverMlKem64',
            ownKeyPackageId: ownKeyPackageId,
            ownKeyPackagePublicMaterial: 'receiver-kpm-1',
          );

          expect(
            result,
            AcceptPendingGroupInviteResult.wrongIdentity,
            reason: label,
          );
          expect(group, isNull, reason: label);
          expect(await groupRepo.getGroup('grp-abc123'), isNull, reason: label);
          expect(
            await groupRepo.getLatestKey('grp-abc123'),
            isNull,
            reason: label,
          );
          expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
          expect(
            bridge.commandLog,
            isNot(contains('group:join')),
            reason: label,
          );
          expect(msgRepo.count, 0, reason: label);
        }

        await expectRejected(
          label: 'missing-device',
          ownDeviceId: null,
          ownTransportPeerId: 'receiver-device-1',
        );
        await expectRejected(
          label: 'wrong-transport',
          ownDeviceId: 'receiver-device-1',
          ownTransportPeerId: 'receiver-device-2',
        );
        await expectRejected(
          label: 'wrong-key-package',
          ownDeviceId: 'receiver-device-1',
          ownTransportPeerId: 'receiver-device-1',
          ownKeyPackageId: 'receiver-kp-2',
        );
      },
    );

    test(
      'EK011 records a welcome key-package tombstone only after accepted materialization',
      () async {
        await pendingInviteRepo.savePendingInvite(
          signedInvite(
            makeInvite(
              groupConfig: receiverDeviceBoundConfig(),
              recipientDeviceId: 'receiver-device-1',
              recipientTransportPeerId: 'receiver-device-1',
              recipientMlKemPublicKey: 'receiverMlKem64',
              recipientKeyPackageId: 'receiver-kp-1',
              recipientKeyPackagePublicMaterial: 'receiver-kpm-1',
            ),
          ),
        );

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          ownDeviceId: 'receiver-device-1',
          ownTransportPeerId: 'receiver-device-1',
          ownMlKemPublicKey: 'receiverMlKem64',
          ownKeyPackageId: 'receiver-kp-1',
          ownKeyPackagePublicMaterial: 'receiver-kpm-1',
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        final tombstone = await pendingInviteRepo.getWelcomeKeyPackageTombstone(
          packageId: 'receiver-kp-1',
          recipientDeviceId: 'receiver-device-1',
          groupId: 'grp-abc123',
        );
        expect(tombstone, isNotNull);
        expect(tombstone!.inviteId, 'invite-1');
        expect(tombstone.isActiveAt(DateTime.now().toUtc()), isTrue);
      },
    );

    test(
      'EK011 rejects replayed package tombstone under a changed invite id before state',
      () async {
        final consumedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        await pendingInviteRepo.saveWelcomeKeyPackageTombstone(
          GroupWelcomeKeyPackageTombstone(
            packageId: 'receiver-kp-1',
            recipientDeviceId: 'receiver-device-1',
            groupId: 'grp-abc123',
            inviteId: 'invite-original',
            publicMaterialHash: GroupWelcomeKeyPackage.hashPublicMaterial(
              'receiver-kpm-1',
            ),
            consumedAt: consumedAt,
            expiresAt: consumedAt.add(pendingGroupInviteTtl),
          ),
        );
        await pendingInviteRepo.savePendingInvite(
          signedInvite(
            makeInvite(
              inviteId: 'invite-replay',
              groupConfig: receiverDeviceBoundConfig(),
              recipientDeviceId: 'receiver-device-1',
              recipientTransportPeerId: 'receiver-device-1',
              recipientMlKemPublicKey: 'receiverMlKem64',
              recipientKeyPackageId: 'receiver-kp-1',
              recipientKeyPackagePublicMaterial: 'receiver-kpm-1',
            ),
          ),
        );

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          ownDeviceId: 'receiver-device-1',
          ownTransportPeerId: 'receiver-device-1',
          ownMlKemPublicKey: 'receiverMlKem64',
          ownKeyPackageId: 'receiver-kp-1',
          ownKeyPackagePublicMaterial: 'receiver-kpm-1',
        );

        expect(result, AcceptPendingGroupInviteResult.alreadyUsed);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'IJ002 persisted signed snapshot must still authorize inviter at accept time',
      () async {
        Future<void> expectRejected(
          String label,
          Map<String, dynamic> groupConfig,
        ) async {
          pendingInviteRepo = InMemoryPendingGroupInviteRepository();
          groupRepo = InMemoryGroupRepository();
          msgRepo = InMemoryGroupMessageRepository();
          bridge = FakeBridge();
          await pendingInviteRepo.savePendingInvite(
            signedInvite(makeInvite(groupConfig: groupConfig)),
          );

          final (result, group) = await acceptPendingGroupInvite(
            pendingInviteRepo: pendingInviteRepo,
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            msgRepo: msgRepo,
            bridge: bridge,
            groupId: 'grp-abc123',
          );

          expect(
            result,
            AcceptPendingGroupInviteResult.invalidPayload,
            reason: label,
          );
          expect(group, isNull, reason: label);
          expect(
            await pendingInviteRepo.getPendingInvite('grp-abc123'),
            isNull,
          );
          expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
          expect(await groupRepo.getGroup('grp-abc123'), isNull);
          expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
          expect(bridge.commandLog, isNot(contains('group:join')));
          expect(msgRepo.count, 0);
        }

        await expectRejected('non-admin inviter', {
          'name': 'Book Club',
          'groupType': 'chat',
          'description': 'A group for book lovers',
          'members': [
            {
              'peerId': '12D3KooWAlice',
              'username': 'Alice',
              'role': 'writer',
              'publicKey': 'alicePubKey64',
              'mlKemPublicKey': 'aliceMlKem64',
            },
            {
              'peerId': '12D3KooWReceiver',
              'username': 'Receiver',
              'role': 'writer',
              'publicKey': 'receiverPubKey64',
              'mlKemPublicKey': 'receiverMlKem64',
            },
          ],
          'createdBy': '12D3KooWAlice',
          'createdAt': '2026-03-02T00:00:00.000Z',
        });

        await expectRejected('removed inviter', {
          'name': 'Book Club',
          'groupType': 'chat',
          'description': 'A group for book lovers',
          'members': [
            {
              'peerId': '12D3KooWReceiver',
              'username': 'Receiver',
              'role': 'writer',
              'publicKey': 'receiverPubKey64',
              'mlKemPublicKey': 'receiverMlKem64',
            },
          ],
          'createdBy': '12D3KooWAlice',
          'createdAt': '2026-03-02T00:00:00.000Z',
        });
      },
    );

    test(
      'accepting on one device does not clear the sibling device pending invite',
      () async {
        final phonePendingInviteRepo = InMemoryPendingGroupInviteRepository();
        final tabletPendingInviteRepo = InMemoryPendingGroupInviteRepository();
        final phoneGroupRepo = InMemoryGroupRepository();
        final tabletGroupRepo = InMemoryGroupRepository();
        final phoneMsgRepo = InMemoryGroupMessageRepository();
        final phoneBridge = FakeBridge();

        await phonePendingInviteRepo.savePendingInvite(makeInvite());
        await tabletPendingInviteRepo.savePendingInvite(makeInvite());

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: phonePendingInviteRepo,
          groupRepo: phoneGroupRepo,
          contactRepo: contactRepo,
          msgRepo: phoneMsgRepo,
          bridge: phoneBridge,
          groupId: 'grp-abc123',
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(
          await phonePendingInviteRepo.getPendingInvite('grp-abc123'),
          isNull,
        );
        expect(
          await tabletPendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await tabletGroupRepo.getGroup('grp-abc123'), isNull);
      },
    );
  });
}
