import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import '../../../shared/fakes/in_memory_group_pending_reaction_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/decline_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package_tombstone.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_pending_membership_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

GroupInviteMembershipFreshnessProof _makeFreshnessProof({
  required String inviteId,
  required String groupId,
  required String? recipientPeerId,
  required Map<String, dynamic> groupConfig,
  int keyEpoch = 1,
  String? recipientDeviceId,
  String? recipientTransportPeerId,
  String? recipientMlKemPublicKey,
  String? recipientKeyPackageId,
  String? recipientKeyPackagePublicMaterial,
  required DateTime issuedAt,
  DateTime? expiresAt,
  String? membershipWatermark,
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
    keyEpoch: keyEpoch,
    groupConfigStateHash: stateHash,
    membershipWatermark: membershipWatermark ?? stateHash,
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
    int keyEpoch = 1,
    Map<String, dynamic>? groupConfig,
    GroupInviteReusePolicy reusePolicy = GroupInviteReusePolicy.singleUse,
    String? recipientDeviceId,
    String? recipientTransportPeerId,
    String? recipientMlKemPublicKey,
    String? recipientKeyPackageId,
    String? recipientKeyPackagePublicMaterial,
    String? membershipWatermark,
    DateTime? membershipProofIssuedAt,
    DateTime? membershipProofExpiresAt,
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
            keyEpoch: keyEpoch,
            issuedAt: inviteTimestamp,
            expiresAt: policyExpiresAt,
          )
        : null;
    final payload = GroupInvitePayload(
      id: inviteId,
      groupId: 'grp-abc123',
      groupKey: overrideGroupKey ?? 'base64-key',
      keyEpoch: keyEpoch,
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
        keyEpoch: keyEpoch,
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
        keyEpoch: keyEpoch,
        issuedAt: membershipProofIssuedAt ?? inviteTimestamp,
        expiresAt: membershipProofExpiresAt,
        membershipWatermark: membershipWatermark,
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
    List<String>? recipientPeerIds,
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
      recipientPeerIds: recipientPeerIds,
      keyInfo: GroupKeyInfo(
        groupId: 'grp-abc123',
        keyGeneration: 1,
        encryptedKey: 'base64-key',
        createdAt: DateTime.utc(2026, 3, 2),
      ),
    );
    return {'from': senderPeerId, 'message': replayEnvelope};
  }

  Future<Map<String, dynamic>> signedMetadataReplayInboxMessage({
    required DateTime updatedAt,
    required String name,
    required String description,
    required String messageId,
    String? avatarBlobId,
    String? avatarMime,
  }) async {
    final groupConfig = <String, dynamic>{
      'name': name,
      'groupType': 'chat',
      'description': description,
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
      'createdAt': DateTime.utc(2026, 3, 2).toIso8601String(),
      'metadataUpdatedAt': updatedAt.toUtc().toIso8601String(),
      groupConfigVersionField: updatedAt.toUtc().toIso8601String(),
    };
    if (avatarBlobId != null) {
      groupConfig['avatarBlobId'] = avatarBlobId;
    }
    if (avatarMime != null) {
      groupConfig['avatarMime'] = avatarMime;
    }
    groupConfig[groupConfigStateHashField] = buildGroupConfigStateHash(
      groupId: 'grp-abc123',
      groupConfig: groupConfig,
    );
    final actorPayload = buildGroupMetadataActorEventPayload(
      groupId: 'grp-abc123',
      updatedAt: updatedAt,
      actorPeerId: '12D3KooWAlice',
      actorUsername: 'Alice',
      actorPublicKey: 'alicePubKey64',
      groupConfig: groupConfig,
    );
    final canonicalPayload = canonicalizeGroupMetadataActorEventPayload(
      actorPayload,
    );
    final signResponse = await callSignPayload(
      bridge: bridge,
      dataToSign: canonicalPayload,
      privateKey: 'alicePrivateKey64',
    );
    final sysText = jsonEncode({
      '__sys': 'group_metadata_updated',
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'groupConfig': groupConfig,
      groupMetadataActorEventEnvelopeField:
          buildSignedGroupMetadataActorEventEnvelope(
            signedPayload: canonicalPayload,
            signature: signResponse['signature'] as String,
          ),
    });
    return signedReplayInboxMessage(
      payloadType: groupOfflineReplayPayloadTypeMessage,
      messageId: messageId,
      plaintextPayload: {
        'groupId': 'grp-abc123',
        'messageId': messageId,
        'senderId': '12D3KooWAlice',
        'senderUsername': 'Alice',
        'keyEpoch': 1,
        'text': sysText,
        'timestamp': updatedAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> signedMetadataDirectMessage({
    required DateTime updatedAt,
    required String name,
    required String description,
    required String messageId,
    String? avatarBlobId,
    String? avatarMime,
  }) async {
    final relayMessage = await signedMetadataReplayInboxMessage(
      updatedAt: updatedAt,
      name: name,
      description: description,
      messageId: messageId,
      avatarBlobId: avatarBlobId,
      avatarMime: avatarMime,
    );
    final replayEnvelope =
        jsonDecode(relayMessage['message'] as String) as Map<String, dynamic>;
    return jsonDecode(replayEnvelope['ciphertext'] as String)
        as Map<String, dynamic>;
  }

  Map<String, dynamic> metadataGroupConfig({
    required String name,
    required String description,
    required DateTime metadataUpdatedAt,
    String? avatarBlobId,
    String? avatarMime,
  }) {
    final config = <String, dynamic>{
      'name': name,
      'groupType': 'chat',
      'description': description,
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
      'createdAt': DateTime.utc(2026, 3, 2).toIso8601String(),
      'metadataUpdatedAt': metadataUpdatedAt.toUtc().toIso8601String(),
      groupConfigVersionField: metadataUpdatedAt.toUtc().toIso8601String(),
    };
    if (avatarBlobId != null) {
      config['avatarBlobId'] = avatarBlobId;
    }
    if (avatarMime != null) {
      config['avatarMime'] = avatarMime;
    }
    config[groupConfigStateHashField] = buildGroupConfigStateHash(
      groupId: 'grp-abc123',
      groupConfig: config,
    );
    return config;
  }

  Future<void> saveCompatibleMaterializedInviteGroup({
    required String name,
    required String description,
    required DateTime metadataUpdatedAt,
    DateTime? membershipEventAt,
    String? avatarBlobId,
    String? avatarMime,
  }) async {
    await groupRepo.saveGroup(
      GroupModel(
        id: 'grp-abc123',
        name: name,
        type: GroupType.chat,
        topicName: '/mknoon/group/grp-abc123',
        description: description,
        avatarBlobId: avatarBlobId,
        avatarMime: avatarMime,
        createdAt: DateTime.utc(2026, 3, 2),
        createdBy: '12D3KooWAlice',
        myRole: GroupRole.member,
        lastMetadataEventAt: metadataUpdatedAt,
        lastMembershipEventAt: membershipEventAt ?? metadataUpdatedAt,
      ),
    );
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'grp-abc123',
        keyGeneration: 1,
        encryptedKey: 'base64-key',
        createdAt: metadataUpdatedAt,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'grp-abc123',
        peerId: '12D3KooWReceiver',
        username: 'Receiver',
        role: MemberRole.writer,
        publicKey: 'receiverPubKey64',
        mlKemPublicKey: 'receiverMlKem64',
        joinedAt: metadataUpdatedAt,
      ),
    );
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
      'D: a successful accept fires onJoinConfigRequest exactly once with the materialized group and invite',
      () async {
        await pendingInviteRepo.savePendingInvite(signedInvite(makeInvite()));

        var fireCount = 0;
        GroupModel? firedGroup;
        PendingGroupInvite? firedInvite;
        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          onJoinConfigRequest: ({required group, required invite}) async {
            fireCount++;
            firedGroup = group;
            firedInvite = invite;
          },
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(fireCount, 1);
        expect(firedGroup!.id, 'grp-abc123');
        // The hook addresses the inviter even though the invite row is consumed.
        expect(firedInvite!.senderPeerId, '12D3KooWAlice');
      },
    );

    test(
      'D: a failed accept (expired) does NOT fire onJoinConfigRequest',
      () async {
        final receivedAt = DateTime.utc(2026, 4, 1, 13);
        await pendingInviteRepo.savePendingInvite(
          makeInvite(receivedAt: receivedAt),
        );

        var fireCount = 0;
        final (result, _) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          now: receivedAt.add(const Duration(days: 11)),
          onJoinConfigRequest: ({required group, required invite}) async {
            fireCount++;
          },
        );

        expect(result, AcceptPendingGroupInviteResult.expired);
        expect(fireCount, 0);
      },
    );

    test(
      'ML-016 valid invited non-contact member is accepted without saving inviter as contact',
      () async {
        contactRepo.seed([]);
        await pendingInviteRepo.savePendingInvite(signedInvite(makeInvite()));

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiverPubKey64',
          senderPrivateKey: 'receiverPrivKey64',
          senderUsername: 'Receiver',
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        expect(
          await groupRepo.getMember('grp-abc123', '12D3KooWAlice'),
          isNotNull,
        );
        expect(await contactRepo.contactExists('12D3KooWAlice'), isFalse);
        expect(contactRepo.addContactCallCount, 0);
        expect(bridge.commandLog, contains('payload.verify'));
        expect(bridge.commandLog, contains('group:join'));
      },
    );

    test(
      'ML-003 accept uses freshness membership watermark for hash convergence',
      () async {
        final membershipAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 10),
        );
        final configVersionAt = membershipAt.add(const Duration(minutes: 5));
        final groupConfig = <String, dynamic>{
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
          'createdAt': membershipAt
              .subtract(const Duration(hours: 6))
              .toIso8601String(),
          'metadataUpdatedAt': configVersionAt.toIso8601String(),
          groupConfigVersionField: configVersionAt.toIso8601String(),
        };
        groupConfig[groupConfigStateHashField] = buildGroupConfigStateHash(
          groupId: 'grp-abc123',
          groupConfig: groupConfig,
        );
        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            groupConfig: groupConfig,
            receivedAt: membershipAt.add(const Duration(minutes: 1)),
            membershipWatermark: membershipAt.toIso8601String(),
          ),
        );
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
          drainAcceptedInboxAllPages: false,
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(group!.lastMembershipEventAt, membershipAt);
        final members = await groupRepo.getMembers('grp-abc123');
        for (final member in members) {
          expect(member.joinedAt, membershipAt);
        }
        expect(
          buildGroupConfigPayload(group, members)[groupConfigStateHashField],
          groupConfig[groupConfigStateHashField],
        );
      },
    );

    test(
      'accept completes after first inbox page when relay reports more backlog',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': const [],
          'cursor': 'stale-or-more-backlog',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          drainAcceptedInboxAllPages: false,
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        expect(
          await msgRepo.getInboxCursor('grp-abc123'),
          'stale-or-more-backlog',
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(1),
        );
      },
    );

    test(
      'GCA-004 inbox bridgeError keeps incomplete materialization pending',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
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
        expect(group, isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(msgRepo.count, 0);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:join'),
          hasLength(1),
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(1),
        );

        final (retryResult, retryGroup) = await acceptPendingGroupInvite(
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

        expect(retryResult, AcceptPendingGroupInviteResult.bridgeError);
        expect(retryGroup, isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(msgRepo.count, 0);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:join'),
          hasLength(2),
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(2),
        );
      },
    );

    test(
      'GCA-103 join bridgeError drains accepted inbox before returning stale metadata',
      () async {
        final inviteReceivedAt = DateTime.now().toUtc();
        final staleMetadataAt = inviteReceivedAt.subtract(
          const Duration(minutes: 1),
        );
        final latestMetadataAt = inviteReceivedAt.add(
          const Duration(minutes: 5),
        );
        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            receivedAt: inviteReceivedAt,
            groupConfig: metadataGroupConfig(
              name: 'test 2',
              description: '222',
              metadataUpdatedAt: staleMetadataAt,
              avatarBlobId: 'stale-avatar',
              avatarMime: 'image/png',
            ),
          ),
        );
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => '12D3KooWReceiver',
          downloadGroupAvatarFn:
              ({required bridge, required groupId, required blobId}) async {
                return '/tmp/$blobId.png';
              },
        );
        addTearDown(listener.dispose);
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'JOIN_FAILED',
        };
        final latestMetadataReplay = await signedMetadataReplayInboxMessage(
          updatedAt: latestMetadataAt,
          name: 'test 3',
          description: '333',
          avatarBlobId: 'latest-avatar',
          avatarMime: 'image/png',
          messageId: 'gca103-join-bridge-error-latest-metadata',
        );
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            {
              ...latestMetadataReplay,
              'timestamp': latestMetadataAt.millisecondsSinceEpoch,
            },
          ],
          'cursor': '',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          groupMessageListener: listener,
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
          downloadGroupAvatarFn:
              ({required bridge, required groupId, required blobId}) async {
                return null;
              },
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(group!.name, 'test 3');
        expect(group.description, '333');
        expect(group.avatarBlobId, 'latest-avatar');
        expect(group.avatarMime, 'image/png');
        expect(group.avatarPath, '/tmp/latest-avatar.png');
        expect(group.lastMetadataEventAt, latestMetadataAt);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getConsumedInvite('invite-1'),
          isNotNull,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:join'),
          hasLength(1),
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(1),
        );

        final (retryResult, retryGroup) = await acceptPendingGroupInvite(
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
        expect(retryResult, AcceptPendingGroupInviteResult.notFound);
        expect(retryGroup, isNull);
      },
    );

    test(
      'GCA-103 transient accepted inbox failure retries before returning stale metadata',
      () async {
        final inviteReceivedAt = DateTime.now().toUtc();
        final staleMetadataAt = inviteReceivedAt.subtract(
          const Duration(minutes: 1),
        );
        final latestMetadataAt = inviteReceivedAt.add(
          const Duration(minutes: 5),
        );
        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            receivedAt: inviteReceivedAt,
            groupConfig: metadataGroupConfig(
              name: 'test 2',
              description: '222',
              metadataUpdatedAt: staleMetadataAt,
              avatarBlobId: 'stale-avatar',
              avatarMime: 'image/png',
            ),
          ),
        );
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => '12D3KooWReceiver',
          downloadGroupAvatarFn:
              ({required bridge, required groupId, required blobId}) async {
                return '/tmp/$blobId.png';
              },
        );
        addTearDown(listener.dispose);
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'JOIN_FAILED',
        };
        bridge.responseSequences['group:inboxRetrieveCursor'] = [
          {
            'ok': false,
            'errorCode': 'RELAY_UNAVAILABLE',
            'errorMessage': 'relay unavailable',
          },
          {
            'ok': true,
            'messages': [
              await signedMetadataReplayInboxMessage(
                updatedAt: latestMetadataAt,
                name: 'test 3',
                description: '333',
                avatarBlobId: 'latest-avatar',
                avatarMime: 'image/png',
                messageId: 'gca103-transient-latest-metadata',
              ),
            ],
            'cursor': '',
          },
        ];

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          groupMessageListener: listener,
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
          downloadGroupAvatarFn:
              ({required bridge, required groupId, required blobId}) async {
                return null;
              },
          acceptedInboxDrainMaxAttempts: 2,
          acceptedInboxDrainRetryDelay: Duration.zero,
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(group!.name, 'test 3');
        expect(group.description, '333');
        expect(group.avatarBlobId, 'latest-avatar');
        expect(group.avatarMime, 'image/png');
        expect(group.avatarPath, '/tmp/latest-avatar.png');
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getConsumedInvite('invite-1'),
          isNotNull,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(2),
        );
      },
    );

    test(
      'GCA-103 post-invite relay metadata with timestamp is applied before accept commits',
      () async {
        final inviteReceivedAt = DateTime.now().toUtc();
        final inviteIssuedAt = inviteReceivedAt
            .subtract(const Duration(hours: 6))
            .add(const Duration(minutes: 5));
        final latestMetadataAt = inviteIssuedAt.add(const Duration(minutes: 5));
        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            receivedAt: inviteReceivedAt,
            groupConfig: metadataGroupConfig(
              name: 'test 2',
              description: '222',
              metadataUpdatedAt: inviteIssuedAt,
              avatarBlobId: 'stale-avatar',
              avatarMime: 'image/png',
            ),
          ),
        );
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => '12D3KooWReceiver',
          downloadGroupAvatarFn:
              ({required bridge, required groupId, required blobId}) async {
                return '/tmp/$blobId.png';
              },
        );
        addTearDown(listener.dispose);
        final latestMetadataReplay = await signedMetadataReplayInboxMessage(
          updatedAt: latestMetadataAt,
          name: 'test 3',
          description: '333',
          avatarBlobId: 'latest-avatar',
          avatarMime: 'image/png',
          messageId: 'gca103-post-invite-relay-metadata',
        );
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            {
              ...latestMetadataReplay,
              'timestamp': latestMetadataAt.millisecondsSinceEpoch,
            },
          ],
          'cursor': '',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          groupMessageListener: listener,
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
          downloadGroupAvatarFn:
              ({required bridge, required groupId, required blobId}) async {
                return null;
              },
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(group!.name, 'test 3');
        expect(group.description, '333');
        expect(group.avatarBlobId, 'latest-avatar');
        expect(group.avatarMime, 'image/png');
        expect(group.avatarPath, '/tmp/latest-avatar.png');
        expect(group.lastMetadataEventAt, latestMetadataAt);
        final acceptedSelf = await groupRepo.getMember(
          'grp-abc123',
          '12D3KooWReceiver',
        );
        expect(acceptedSelf, isNotNull);
        expect(acceptedSelf!.joinedAt, inviteIssuedAt);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(1),
        );
      },
    );

    test(
      'GCA-103 pre-accept direct metadata buffer prevents stale accepted group when relay drain fails',
      () async {
        final inviteReceivedAt = DateTime.now().toUtc();
        final staleMetadataAt = inviteReceivedAt.subtract(
          const Duration(minutes: 1),
        );
        final latestMetadataAt = inviteReceivedAt.add(
          const Duration(minutes: 5),
        );
        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            receivedAt: inviteReceivedAt,
            membershipWatermark: staleMetadataAt.toIso8601String(),
            groupConfig: metadataGroupConfig(
              name: 'test 2',
              description: '222',
              metadataUpdatedAt: staleMetadataAt,
              avatarBlobId: 'stale-avatar',
              avatarMime: 'image/png',
            ),
          ),
        );
        final pendingMembershipRepo =
            InMemoryGroupPendingMembershipMessageRepository();
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          pendingMembershipMessageRepo: pendingMembershipRepo,
          getSelfPeerId: () async => '12D3KooWReceiver',
          downloadGroupAvatarFn:
              ({required bridge, required groupId, required blobId}) async {
                return '/tmp/$blobId.png';
              },
        );
        addTearDown(listener.dispose);

        await listener.handleReplayEnvelope(
          await signedMetadataDirectMessage(
            updatedAt: latestMetadataAt,
            name: 'test 3',
            description: '333',
            avatarBlobId: 'latest-avatar',
            avatarMime: 'image/png',
            messageId: 'gca103-preaccept-direct-latest-metadata',
          ),
          allowMembershipBuffer: true,
        );
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(pendingMembershipRepo.messages, hasLength(1));

        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          groupMessageListener: listener,
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
          downloadGroupAvatarFn:
              ({required bridge, required groupId, required blobId}) async {
                return null;
              },
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(group!.name, 'test 3');
        expect(group.description, '333');
        expect(group.avatarBlobId, 'latest-avatar');
        expect(group.avatarMime, 'image/png');
        expect(group.avatarPath, '/tmp/latest-avatar.png');
        expect(group.lastMetadataEventAt, latestMetadataAt);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(pendingMembershipRepo.messages, isEmpty);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(1),
        );
      },
    );

    test(
      'GCA-103 deferred direct metadata replay refreshes stale invite accept when relay drain fails',
      () async {
        final inviteReceivedAt = DateTime.now().toUtc();
        final staleMetadataAt = inviteReceivedAt.subtract(
          const Duration(minutes: 1),
        );
        final latestMetadataAt = inviteReceivedAt.add(
          const Duration(minutes: 5),
        );
        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            receivedAt: inviteReceivedAt,
            membershipWatermark: staleMetadataAt.toIso8601String(),
            groupConfig: metadataGroupConfig(
              name: 'test 2',
              description: '222',
              metadataUpdatedAt: staleMetadataAt,
              avatarBlobId: 'stale-avatar',
              avatarMime: 'image/png',
            ),
          ),
        );

        final pendingRepairRepo = _InMemoryGroupPendingKeyRepairRepository();
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          pendingKeyRepairRepo: pendingRepairRepo,
          getSelfPeerId: () async => '12D3KooWReceiver',
          downloadGroupAvatarFn:
              ({required bridge, required groupId, required blobId}) async {
                return '/tmp/$blobId.png';
              },
        );
        addTearDown(listener.dispose);
        final directController = StreamController<ChatMessage>.broadcast();
        final membershipListener = GroupMembershipUpdateListener(
          groupMembershipUpdateStream: directController.stream,
          groupRepo: groupRepo,
          bridge: bridge,
          groupMessageListener: listener,
          msgRepo: msgRepo,
          pendingKeyRepairRepo: pendingRepairRepo,
        );
        membershipListener.start();
        addTearDown(() async {
          membershipListener.dispose();
          await directController.close();
        });

        final directMessageId = 'gca103-deferred-direct-latest-metadata';
        final relayMessage = await signedMetadataReplayInboxMessage(
          updatedAt: latestMetadataAt,
          name: 'test 3',
          description: '333',
          avatarBlobId: 'latest-avatar',
          avatarMime: 'image/png',
          messageId: directMessageId,
        );
        directController.add(
          ChatMessage(
            from: '12D3KooWAlice',
            to: '12D3KooWReceiver',
            content: buildGroupMembershipUpdateDirectEnvelope(
              groupId: 'grp-abc123',
              senderPeerId: '12D3KooWAlice',
              replayEnvelope: relayMessage['message'] as String,
              timestamp: latestMetadataAt,
              messageId: directMessageId,
            ),
            timestamp: latestMetadataAt.toIso8601String(),
            isIncoming: true,
          ),
        );
        await pumpEventQueue(times: 10);

        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(pendingRepairRepo.repairs.values, hasLength(1));
        expect(pendingRepairRepo.repairs.values.single.lastError, isNull);
        expect(
          (await msgRepo.getMessage(directMessageId))?.status,
          groupPendingKeyRepairStatusPendingKey,
        );

        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          groupMessageListener: listener,
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
          downloadGroupAvatarFn:
              ({required bridge, required groupId, required blobId}) async {
                return null;
              },
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(group!.name, 'test 3');
        expect(group.description, '333');
        expect(group.avatarBlobId, 'latest-avatar');
        expect(group.avatarMime, 'image/png');
        expect(group.avatarPath, '/tmp/latest-avatar.png');
        expect(group.lastMetadataEventAt, latestMetadataAt);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await msgRepo.getMessage(directMessageId), isNull);
        expect(
          pendingRepairRepo.repairs.values.single.status,
          groupPendingKeyRepairStatusRepaired,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(1),
        );
      },
    );

    test(
      'GCA-103 failed first drain keeps stale materialization out of All until retry catches up',
      () async {
        final inviteReceivedAt = DateTime.now().toUtc();
        final metadataAt = inviteReceivedAt.add(const Duration(minutes: 5));
        await pendingInviteRepo.savePendingInvite(
          makeInvite(receivedAt: inviteReceivedAt),
        );
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => '12D3KooWReceiver',
        );
        addTearDown(listener.dispose);
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
        };

        final (result, acceptedGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          groupMessageListener: listener,
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
        );

        expect(result, AcceptPendingGroupInviteResult.bridgeError);
        expect(acceptedGroup, isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);

        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            await signedMetadataReplayInboxMessage(
              updatedAt: metadataAt,
              name: 'test 3',
              description: '333',
              messageId: 'gca103-metadata-late',
            ),
          ],
          'cursor': '',
        };

        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );

        final (retryResult, retryGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          groupMessageListener: listener,
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
        );
        expect(retryResult, AcceptPendingGroupInviteResult.success);
        expect(retryGroup, isNotNull);
        expect(retryGroup!.name, 'test 3');
        expect(retryGroup.description, '333');
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getConsumedInvite('invite-1'),
          isNotNull,
        );
      },
    );

    test(
      'GCA-103 duplicate retry with inbox failure rolls back stale materialization',
      () async {
        final inviteReceivedAt = DateTime.now().toUtc();
        final staleMetadataAt = inviteReceivedAt.subtract(
          const Duration(minutes: 1),
        );
        final staleConfig = metadataGroupConfig(
          name: 'test 2',
          description: '222',
          metadataUpdatedAt: staleMetadataAt,
          avatarBlobId: 'stale-avatar',
          avatarMime: 'image/png',
        );
        final invite = makeInvite(
          groupConfig: staleConfig,
          receivedAt: inviteReceivedAt,
        );
        await pendingInviteRepo.savePendingInvite(invite);
        await saveCompatibleMaterializedInviteGroup(
          name: 'test 2',
          description: '222',
          metadataUpdatedAt: staleMetadataAt,
          membershipEventAt: invite
              .toPayload()!
              .membershipFreshnessProof!
              .issuedAt,
          avatarBlobId: 'stale-avatar',
          avatarMime: 'image/png',
        );
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
        );

        expect(result, AcceptPendingGroupInviteResult.bridgeError);
        expect(group, isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
      },
    );

    test(
      'duplicate native retry rechecks durable binding and self authority inside its phase',
      () async {
        final retryRepository = _MutatingAcceptedRetryRepository();
        groupRepo = retryRepository;
        final now = DateTime.now().toUtc();
        final removedAt = now.subtract(const Duration(hours: 8));
        await groupRepo.saveGroup(
          GroupModel(
            id: 'grp-abc123',
            name: 'Retained shell',
            type: GroupType.chat,
            topicName: '/mknoon/group/grp-abc123',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: '12D3KooWAlice',
            myRole: GroupRole.member,
            selfRemovedAt: removedAt,
            lastMembershipEventAt: removedAt,
            lastMembershipEventId: 'remove-before-retry',
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'grp-abc123',
            keyGeneration: 1,
            encryptedKey: 'retained-terminal-key',
            createdAt: removedAt,
          ),
        );
        final invite = makeInvite(
          receivedAt: now,
          membershipWatermark: now
              .subtract(const Duration(hours: 4))
              .toIso8601String(),
        );
        final payload = invite.toPayload()!;
        await pendingInviteRepo.savePendingInvite(invite);
        final materialized = await materializeAcceptedGroupInvitePayload(
          payload: payload,
          groupRepo: groupRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWReceiver',
        );
        expect(materialized.$1, HandleGroupInviteResult.success);
        bridge.commandLog.clear();

        retryRepository.rollbackBeforeRetryAuthorization = true;
        final (result, acceptedGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
        );

        expect(result, AcceptPendingGroupInviteResult.repairPending);
        expect(acceptedGroup, isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        final restored = await groupRepo.getGroup('grp-abc123');
        expect(restored?.selfRemovedAt, removedAt);
        expect(
          await groupRepo.getMember('grp-abc123', '12D3KooWReceiver'),
          isNull,
        );
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
      },
    );

    test(
      'duplicate retry revalidates policy and proof expiry after waiting for its phase',
      () async {
        for (final policyExpiry in <bool>[false, true]) {
          pendingInviteRepo = InMemoryPendingGroupInviteRepository();
          final signalingRepository = _ReadSignalingRepository();
          groupRepo = signalingRepository;
          bridge = FakeBridge();
          var clock = DateTime.utc(2026, 7, 20, 12);
          final proofExpiresAt = clock.add(const Duration(minutes: 1));
          final metadataAt = clock.subtract(const Duration(hours: 1));
          final config = metadataGroupConfig(
            name: 'test 2',
            description: '222',
            metadataUpdatedAt: metadataAt,
          );
          final invite = makeInvite(
            groupConfig: config,
            receivedAt: clock,
            membershipProofExpiresAt: proofExpiresAt,
          );
          final payload = invite.toPayload()!;
          await pendingInviteRepo.savePendingInvite(invite);
          await saveCompatibleMaterializedInviteGroup(
            name: 'test 2',
            description: '222',
            metadataUpdatedAt: metadataAt,
            membershipEventAt: payload.membershipFreshnessProof!.issuedAt,
          );

          final blockerEntered = Completer<void>();
          final releaseBlocker = Completer<void>();
          final blocker = runGroupMembershipMutationLocked<void>(
            groupId: invite.groupId,
            action: () async {
              blockerEntered.complete();
              await releaseBlocker.future;
            },
          );
          await blockerEntered.future;
          signalingRepository.signalAfterAdditionalGroupReads(3);
          final acceptance = acceptPendingGroupInvite(
            pendingInviteRepo: pendingInviteRepo,
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            msgRepo: msgRepo,
            bridge: bridge,
            groupId: invite.groupId,
            senderPeerId: '12D3KooWReceiver',
            nowUtc: () => clock,
          );
          await signalingRepository.nextGroupRead!.future;
          await Future<void>.delayed(Duration.zero);
          clock = policyExpiry
              ? invite.expiresAt.add(const Duration(seconds: 1))
              : proofExpiresAt.add(const Duration(seconds: 1));
          releaseBlocker.complete();
          await blocker;

          final (result, acceptedGroup) = await acceptance;
          expect(
            result,
            policyExpiry
                ? AcceptPendingGroupInviteResult.expired
                : AcceptPendingGroupInviteResult.expiredFreshness,
          );
          expect(acceptedGroup, isNull);
          expect(bridge.commandLog, isNot(contains('group:join')));
          expect(
            await pendingInviteRepo.getPendingInvite(invite.groupId),
            isNull,
          );
        }
      },
    );

    test(
      'outer rollback waits for membership phase and preserves newer no-floor authority',
      () async {
        final schedulingBridge = _CommandSchedulingBridge(
          command: 'group:inboxRetrieveCursor',
        );
        bridge = schedulingBridge;
        final inviteReceivedAt = DateTime.now().toUtc();
        final staleMetadataAt = inviteReceivedAt.subtract(
          const Duration(minutes: 1),
        );
        final staleConfig = metadataGroupConfig(
          name: 'test 2',
          description: '222',
          metadataUpdatedAt: staleMetadataAt,
        );
        final invite = makeInvite(
          groupConfig: staleConfig,
          receivedAt: inviteReceivedAt,
        );
        final acceptedAt = invite
            .toPayload()!
            .membershipFreshnessProof!
            .issuedAt;
        await pendingInviteRepo.savePendingInvite(invite);
        await saveCompatibleMaterializedInviteGroup(
          name: 'test 2',
          description: '222',
          metadataUpdatedAt: staleMetadataAt,
          membershipEventAt: acceptedAt,
        );
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
        };

        schedulingBridge.onCommandReturn = () =>
            runGroupMembershipMutationLocked<void>(
              groupId: 'grp-abc123',
              action: () async {
                final current = (await groupRepo.getGroup('grp-abc123'))!;
                await groupRepo.updateGroup(
                  current.copyWith(
                    lastMembershipEventAt: acceptedAt.add(
                      const Duration(minutes: 1),
                    ),
                    lastMembershipEventId: 'newer-membership-won',
                  ),
                );
              },
            );
        final (result, acceptedGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
        );

        expect(result, AcceptPendingGroupInviteResult.bridgeError);
        expect(acceptedGroup, isNull);
        final preserved = await groupRepo.getGroup('grp-abc123');
        expect(preserved, isNotNull);
        expect(preserved?.lastMembershipEventId, 'newer-membership-won');
        expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
      },
    );

    test(
      'removed-shell accept recovery never generically deletes accepted or newer authority',
      () async {
        final now = DateTime.now().toUtc();
        final removedAt = now.subtract(const Duration(hours: 8));
        await groupRepo.saveGroup(
          GroupModel(
            id: 'grp-abc123',
            name: 'Retained shell',
            type: GroupType.chat,
            topicName: '/mknoon/group/grp-abc123',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: '12D3KooWAlice',
            myRole: GroupRole.member,
            selfRemovedAt: removedAt,
            lastMembershipEventAt: removedAt,
            lastMembershipEventId: 'remove-before-accept',
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'grp-abc123',
            peerId: '12D3KooWAlice',
            username: 'Alice',
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'grp-abc123',
            keyGeneration: 1,
            encryptedKey: 'retained-terminal-key',
            createdAt: removedAt,
          ),
        );
        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            inviteId: 'accepted-reentry-auth',
            receivedAt: now,
            membershipWatermark: removedAt
                .add(const Duration(hours: 1))
                .toIso8601String(),
          ),
        );
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
        );

        expect(result, AcceptPendingGroupInviteResult.bridgeError);
        expect(group, isNull);
        final restored = await groupRepo.getGroup('grp-abc123');
        expect(restored, isNotNull);
        expect(restored?.selfRemovedAt, removedAt);
        expect(restored?.lastMembershipEventAt, removedAt);
        expect(
          await groupRepo.getMember('grp-abc123', '12D3KooWReceiver'),
          isNull,
        );
        expect(
          (await groupRepo.getLatestKey('grp-abc123'))?.encryptedKey,
          'retained-terminal-key',
        );
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
      },
    );

    test(
      'GCA-103 duplicate retry join bridgeError keeps stale materialization pending',
      () async {
        final inviteReceivedAt = DateTime.now().toUtc();
        final staleMetadataAt = inviteReceivedAt.subtract(
          const Duration(minutes: 1),
        );
        final staleConfig = metadataGroupConfig(
          name: 'test 2',
          description: '222',
          metadataUpdatedAt: staleMetadataAt,
        );
        final invite = makeInvite(
          groupConfig: staleConfig,
          receivedAt: inviteReceivedAt,
        );
        await pendingInviteRepo.savePendingInvite(invite);
        await saveCompatibleMaterializedInviteGroup(
          name: 'test 2',
          description: '222',
          metadataUpdatedAt: staleMetadataAt,
          membershipEventAt: invite
              .toPayload()!
              .membershipFreshnessProof!
              .issuedAt,
        );
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'JOIN_FAILED',
          'errorMessage': 'join failed',
        };
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
        );

        expect(result, AcceptPendingGroupInviteResult.bridgeError);
        expect(group, isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
      },
    );

    test(
      'GCA-103 equal timestamp metadata replay repairs stale invite snapshot',
      () async {
        final inviteReceivedAt = DateTime.now().toUtc();
        final metadataAt = inviteReceivedAt.add(const Duration(minutes: 5));
        final staleSnapshot = <String, dynamic>{
          'name': 'test 2',
          'groupType': 'chat',
          'description': '222',
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
          'createdAt': inviteReceivedAt
              .subtract(const Duration(hours: 6))
              .toIso8601String(),
          'metadataUpdatedAt': metadataAt.toIso8601String(),
          groupConfigVersionField: metadataAt.toIso8601String(),
        };
        staleSnapshot[groupConfigStateHashField] = buildGroupConfigStateHash(
          groupId: 'grp-abc123',
          groupConfig: staleSnapshot,
        );
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => '12D3KooWReceiver',
        );
        addTearDown(listener.dispose);
        await pendingInviteRepo.savePendingInvite(
          makeInvite(groupConfig: staleSnapshot, receivedAt: inviteReceivedAt),
        );
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': const [],
          'cursor': '',
        };

        final (result, acceptedGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          groupMessageListener: listener,
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(acceptedGroup, isNotNull);
        expect(acceptedGroup!.name, 'test 2');
        expect(acceptedGroup.description, '222');
        expect(acceptedGroup.lastMetadataEventAt, metadataAt);

        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            await signedMetadataReplayInboxMessage(
              updatedAt: metadataAt,
              name: 'test 3',
              description: '333',
              messageId: 'gca103-metadata-equal',
            ),
          ],
          'cursor': '',
        };

        await drainGroupOfflineInboxForGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'grp-abc123',
          groupMessageListener: listener,
          selfPeerId: '12D3KooWReceiver',
        );

        final caughtUpGroup = await groupRepo.getGroup('grp-abc123');
        expect(caughtUpGroup, isNotNull);
        expect(caughtUpGroup!.name, 'test 3');
        expect(caughtUpGroup.description, '333');
        expect(caughtUpGroup.lastMetadataEventAt, metadataAt);
        expect(await msgRepo.getInboxCursor('grp-abc123'), isNotNull);
      },
    );

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
          getSelfPeerId: () async => '12D3KooWReceiver',
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
      'TC-325-01 accept buffers a target-absent reaction and delivers it when '
      'the target lands',
      () async {
        // Plan 325: the accept lane drained WITHOUT a pending-reaction buffer,
        // so a reaction whose target message had not landed was dropped
        // permanently (handle_incoming_group_reaction_use_case.dart:204-214)
        // while the cursor committed regardless, so the relay never re-serves
        // it.
        //
        // Two phases in one test, because retention is NOT the behaviour this
        // fix promises — delivery is. The flush DELETES the buffered row before
        // applying it (group_message_listener_reaction_ingress_processor.dart
        // :141), so asserting "a row still exists" after the target lands would
        // go red against a correct fix.
        final reactionTimestamp = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 4))
            .toIso8601String();
        final reactionRepo = FakeReactionRepository();
        final pendingReactionRepo = InMemoryGroupPendingReactionRepository();
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => '12D3KooWReceiver',
          reactionRepo: reactionRepo,
          pendingReactionRepo: pendingReactionRepo,
        );
        addTearDown(listener.dispose);

        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));

        await pendingInviteRepo.savePendingInvite(makeInvite());

        // The reaction's target is deliberately NOT in this page.
        final signedReactionMessage = await signedReplayInboxMessage(
          payloadType: groupOfflineReplayPayloadTypeReaction,
          messageId: 'reaction-late-1',
          plaintextPayload: {
            'id': 'reaction-late-1',
            'messageId': 'offline-msg-late',
            'emoji': '\u{1F389}',
            'action': 'add',
            'senderPeerId': '12D3KooWAlice',
            'timestamp': reactionTimestamp,
          },
        );
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [signedReactionMessage],
          'cursor': '',
        };

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

        // Phase (a) — retained, not discarded. The discriminator is the ABSENCE
        // of the drop event: both paths otherwise leave the drain looking fine.
        expect(
          flowEvents.map((event) => event['event']),
          isNot(contains('GROUP_REACTION_RECEIVE_UNKNOWN_MESSAGE')),
          reason: 'the reaction was dropped instead of buffered',
        );
        expect(pendingReactionRepo.reactions, hasLength(1));
        expect(pendingReactionRepo.reactions.single.id, 'reaction-late-1');
        expect(
          pendingReactionRepo.reactions.single.messageId,
          'offline-msg-late',
        );
        expect(
          await reactionRepo.getReactionsForMessage('offline-msg-late'),
          isEmpty,
        );

        // Phase (b) — the target lands, and the reaction is DELIVERED.
        await listener.handleReplayEnvelope({
          'groupId': 'grp-abc123',
          'senderId': '12D3KooWAlice',
          'senderUsername': 'Alice',
          'keyEpoch': 1,
          'text': 'the target',
          'timestamp': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
          'messageId': 'offline-msg-late',
        });

        final delivered = await reactionRepo.getReactionsForMessage(
          'offline-msg-late',
        );
        expect(delivered, hasLength(1));
        expect(delivered.single.emoji, '\u{1F389}');
        expect(delivered.single.senderPeerId, '12D3KooWAlice');
        // Drained, not merely retained: processor:141 claims the row before
        // emitting, so a delivered reaction leaves an EMPTY buffer.
        expect(pendingReactionRepo.reactions, isEmpty);
      },
    );

    test(
      'ML-003 accepts offline invite and drains only entitled A/B post-add replay exactly once',
      () async {
        final preAddAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 10),
        );
        final addAt = preAddAt.add(const Duration(minutes: 1));
        final alicePostAddAt = addAt.add(const Duration(minutes: 1));
        final bobPostAddAt = addAt.add(const Duration(minutes: 2));
        final groupConfig = {
          'name': 'ML-003 Private Group',
          'groupType': 'chat',
          'description': 'Offline add proof',
          'members': [
            {
              'peerId': '12D3KooWAlice',
              'username': 'Alice',
              'role': 'admin',
              'publicKey': 'alicePubKey64',
              'mlKemPublicKey': 'aliceMlKem64',
            },
            {
              'peerId': '12D3KooWBob',
              'username': 'Bob',
              'role': 'writer',
              'publicKey': 'bobPubKey64',
              'mlKemPublicKey': 'bobMlKem64',
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
          'createdAt': preAddAt
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
        };
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => '12D3KooWReceiver',
        );
        addTearDown(listener.dispose);

        await pendingInviteRepo.savePendingInvite(
          makeInvite(groupConfig: groupConfig, receivedAt: addAt),
        );

        final preAdd = await signedReplayInboxMessage(
          payloadType: groupOfflineReplayPayloadTypeMessage,
          messageId: 'ml003-a-pre-add',
          recipientPeerIds: const ['12D3KooWBob'],
          plaintextPayload: {
            'groupId': 'grp-abc123',
            'messageId': 'ml003-a-pre-add',
            'senderId': '12D3KooWAlice',
            'senderUsername': 'Alice',
            'keyEpoch': 1,
            'text': 'ML-003 pre-add control',
            'timestamp': preAddAt.toIso8601String(),
          },
        );
        final alicePostAdd = await signedReplayInboxMessage(
          payloadType: groupOfflineReplayPayloadTypeMessage,
          messageId: 'ml003-a-post-add',
          recipientPeerIds: const ['12D3KooWBob', '12D3KooWReceiver'],
          plaintextPayload: {
            'groupId': 'grp-abc123',
            'messageId': 'ml003-a-post-add',
            'senderId': '12D3KooWAlice',
            'senderUsername': 'Alice',
            'keyEpoch': 1,
            'text': 'ML-003 Alice post-add replay',
            'timestamp': alicePostAddAt.toIso8601String(),
          },
        );
        final bobPostAdd = await signedReplayInboxMessage(
          payloadType: groupOfflineReplayPayloadTypeMessage,
          messageId: 'ml003-b-post-add',
          senderPeerId: '12D3KooWBob',
          senderPublicKey: 'bobPubKey64',
          senderPrivateKey: 'bobPrivateKey64',
          recipientPeerIds: const ['12D3KooWAlice', '12D3KooWReceiver'],
          plaintextPayload: {
            'groupId': 'grp-abc123',
            'messageId': 'ml003-b-post-add',
            'senderId': '12D3KooWBob',
            'senderUsername': 'Bob',
            'keyEpoch': 1,
            'text': 'ML-003 Bob post-add replay',
            'timestamp': bobPostAddAt.toIso8601String(),
          },
        );
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            preAdd,
            alicePostAdd,
            bobPostAdd,
            alicePostAdd,
            bobPostAdd,
          ],
          'cursor': '',
        };

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          groupMessageListener: listener,
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiver-public-key',
          senderPrivateKey: 'receiver-private-key',
          senderUsername: 'Receiver',
          drainAcceptedInboxAllPages: true,
          acceptedInboxPageSize: 2,
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
        expect(bridge.commandLog, contains('group:join'));
        expect(bridge.commandLog, contains('group:inboxRetrieveCursor'));

        final joinMessage = bridge.sentMessages.firstWhere((raw) {
          return (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:join';
        });
        final joinPayload =
            (jsonDecode(joinMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(joinPayload['groupId'], 'grp-abc123');
        expect(joinPayload['groupKey'], 'base64-key');
        expect(joinPayload['keyEpoch'], 1);
        final joinConfig = joinPayload['groupConfig'] as Map<String, dynamic>;
        expect((joinConfig['members'] as List<dynamic>), hasLength(3));

        Future<List<String>> idsMatching(String messageId) async {
          return (await msgRepo.getMessagesPage('grp-abc123', limit: 20))
              .where((message) => message.id == messageId)
              .map((message) => message.text)
              .toList(growable: false);
        }

        expect(await idsMatching('ml003-a-pre-add'), isEmpty);
        expect(await idsMatching('ml003-a-post-add'), [
          'ML-003 Alice post-add replay',
        ]);
        expect(await idsMatching('ml003-b-post-add'), [
          'ML-003 Bob post-add replay',
        ]);

        final messages = await msgRepo.getMessagesPage('grp-abc123', limit: 20);
        final replayRows = messages
            .where(
              (message) =>
                  message.id == 'ml003-a-post-add' ||
                  message.id == 'ml003-b-post-add',
            )
            .toList(growable: false);
        expect(replayRows, hasLength(2));
        expect(replayRows.every((message) => message.isIncoming), isTrue);
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
      'GCA-004 join bridgeError with inline invite preserves recovery state',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'JOIN_FAILED',
        };
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
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
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getConsumedInvite('invite-1'),
          isNotNull,
        );
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
      },
    );

    test(
      'GCA-004 join bridgeError with inbox failure keeps welcome package retryable',
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
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'JOIN_FAILED',
        };
        bridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'PUBLISH_FAILED',
        };
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': false,
          'errorCode': 'RELAY_UNAVAILABLE',
          'errorMessage': 'relay unavailable',
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
          ownDeviceId: 'receiver-device-1',
          ownTransportPeerId: 'receiver-device-1',
          ownMlKemPublicKey: 'receiverMlKem64',
          ownKeyPackageId: 'receiver-kp-1',
          ownKeyPackagePublicMaterial: 'receiver-kpm-1',
        );

        expect(result, AcceptPendingGroupInviteResult.bridgeError);
        expect(group, isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        final tombstone = await pendingInviteRepo.getWelcomeKeyPackageTombstone(
          packageId: 'receiver-kp-1',
          recipientDeviceId: 'receiver-device-1',
          groupId: 'grp-abc123',
        );
        expect(tombstone, isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(msgRepo.count, 0);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:join'),
          hasLength(1),
        );

        final (retryResult, retryGroup) = await acceptPendingGroupInvite(
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
          ownDeviceId: 'receiver-device-1',
          ownTransportPeerId: 'receiver-device-1',
          ownMlKemPublicKey: 'receiverMlKem64',
          ownKeyPackageId: 'receiver-kp-1',
          ownKeyPackagePublicMaterial: 'receiver-kpm-1',
        );

        expect(retryResult, AcceptPendingGroupInviteResult.bridgeError);
        expect(retryGroup, isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(msgRepo.count, 0);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:join'),
          hasLength(2),
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxRetrieveCursor'),
          hasLength(2),
        );
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
      'SV-009 rejects invite member key material before join state is active',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));

        Map<String, dynamic> configWithReceiverKeys({
          required String publicKey,
          required String mlKemPublicKey,
        }) {
          return {
            'name': 'SV-009 Book Club',
            'groupType': 'chat',
            'description': 'Invalid key material proof',
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
                'publicKey': publicKey,
                'mlKemPublicKey': mlKemPublicKey,
              },
            ],
            'createdBy': '12D3KooWAlice',
            'createdAt': '2026-05-14T05:55:00.000Z',
          };
        }

        final variants = [
          configWithReceiverKeys(
            publicKey: 'receiver public key with space',
            mlKemPublicKey: 'receiverMlKem64',
          ),
          configWithReceiverKeys(
            publicKey: 'receiverPubKey64',
            mlKemPublicKey: 'receiver\nMlKem64',
          ),
        ];

        for (final groupConfig in variants) {
          pendingInviteRepo = InMemoryPendingGroupInviteRepository();
          groupRepo = InMemoryGroupRepository();
          msgRepo = InMemoryGroupMessageRepository();
          contactRepo = FakeContactRepository()..seed([aliceContact()]);
          bridge = FakeBridge();

          await pendingInviteRepo.savePendingInvite(
            makeInvite(groupConfig: groupConfig),
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
          expect(await groupRepo.getMembers('grp-abc123'), isEmpty);
          expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
          expect(bridge.commandLog, isNot(contains('group:join')));
          expect(msgRepo.count, 0);
        }

        expect(
          flowEvents.where(
            (event) =>
                event['event'] ==
                'GROUP_INVITE_HANDLE_INVALID_MEMBER_KEY_MATERIAL',
          ),
          hasLength(variants.length),
        );
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
      'KE-008 repair-pending re-add is not active until current epoch key material joins',
      () async {
        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            inviteId: 'ke008-readd-invite',
            keyEpoch: 2,
            overrideGroupKey: 'readd-current-epoch-key',
          ),
        );
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'KEY_PACKAGE_DECRYPT_FAILED',
          'errorMessage': 'delayed current epoch re-add key material',
        };

        final (pendingResult, pendingGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiverPubKey64',
          senderPrivateKey: 'receiverPrivKey64',
          senderUsername: 'Receiver',
        );

        expect(pendingResult, AcceptPendingGroupInviteResult.repairPending);
        expect(pendingGroup, isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
          reason: 'the re-add stays explicitly pending while key repair runs',
        );
        expect(
          await groupRepo.getGroup('grp-abc123'),
          isNull,
          reason: 'Charlie must not be shown as joined before current key join',
        );
        expect(await groupRepo.getMembers('grp-abc123'), isEmpty);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(msgRepo.count, 0);
        expect(bridge.commandLog, contains('group:join'));
        expect(bridge.commandLog, isNot(contains('group:publish')));

        bridge.responses['group:join'] = {'ok': true};
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'ke008-charlie-post-readd',
          'topicPeers': 1,
        };
        bridge.responses['group:inboxStore'] = {'ok': true};

        final (acceptedResult, acceptedGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiverPubKey64',
          senderPrivateKey: 'receiverPrivKey64',
          senderUsername: 'Receiver',
        );

        expect(acceptedResult, AcceptPendingGroupInviteResult.success);
        expect(acceptedGroup, isNotNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        expect(
          await groupRepo.getMember('grp-abc123', '12D3KooWReceiver'),
          isNotNull,
        );
        final latestKey = await groupRepo.getLatestKey('grp-abc123');
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 2);
        expect(latestKey.encryptedKey, 'readd-current-epoch-key');

        final (sendResult, sentMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'grp-abc123',
          text: 'KE-008 Charlie post-readd send',
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiverPubKey64',
          senderPrivateKey: 'receiverPrivKey64',
          senderUsername: 'Receiver',
          messageId: 'ke008-charlie-post-readd',
        );

        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 2);
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
      'G3-003 rejects expired payload policy even when pending row is not expired',
      () async {
        final receivedAt = DateTime.utc(2026, 4, 29, 12);
        final invite = makeInvite(receivedAt: receivedAt);
        await pendingInviteRepo.savePendingInvite(
          PendingGroupInvite.fromMap({
            ...invite.toMap(),
            'expires_at': receivedAt
                .add(const Duration(days: 30))
                .toIso8601String(),
          }),
        );

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          now: receivedAt
              .add(pendingGroupInviteTtl)
              .add(const Duration(seconds: 1)),
        );

        expect(result, AcceptPendingGroupInviteResult.expired);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('payload.verify')));
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

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
      'ML-018 decline expiry and cancellation stop accept before join state',
      () async {
        Future<void> expectNoAcceptedState() async {
          expect(await groupRepo.getGroup('grp-abc123'), isNull);
          expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
          expect(bridge.commandLog, isNot(contains('group:join')));
          expect(msgRepo.count, 0);
        }

        final declinedAt = DateTime.utc(2026, 4, 29, 12);
        await pendingInviteRepo.savePendingInvite(
          makeInvite(receivedAt: declinedAt),
        );
        final declineResult = await declinePendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupId: 'grp-abc123',
          now: declinedAt,
        );
        expect(declineResult, DeclinePendingGroupInviteResult.success);
        var (acceptResult, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          now: declinedAt.add(const Duration(minutes: 1)),
        );
        expect(acceptResult, AcceptPendingGroupInviteResult.notFound);
        expect(group, isNull);
        await expectNoAcceptedState();

        pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        groupRepo = InMemoryGroupRepository();
        msgRepo = InMemoryGroupMessageRepository();
        bridge = FakeBridge();
        final expiredReceivedAt = DateTime.utc(2026, 4, 1, 13);
        await pendingInviteRepo.savePendingInvite(
          makeInvite(receivedAt: expiredReceivedAt),
        );
        (acceptResult, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          now: DateTime.utc(2026, 4, 12, 13),
        );
        expect(acceptResult, AcceptPendingGroupInviteResult.expired);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        await expectNoAcceptedState();

        pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        groupRepo = InMemoryGroupRepository();
        msgRepo = InMemoryGroupMessageRepository();
        bridge = FakeBridge();
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
        (acceptResult, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          now: revokedAt.add(const Duration(minutes: 1)),
        );
        expect(acceptResult, AcceptPendingGroupInviteResult.revoked);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        await expectNoAcceptedState();
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
      'ML-019 KE-016 rejects stale invite against newer local removal and key state',
      () async {
        final oldInviteAt = DateTime.utc(2026, 4, 29, 12);
        final removalAt = oldInviteAt.add(const Duration(minutes: 5));
        await groupRepo.saveGroup(
          GroupModel(
            id: 'grp-abc123',
            name: 'Book Club',
            type: GroupType.chat,
            topicName: '/mknoon/group/grp-abc123',
            createdAt: DateTime.utc(2026, 3, 2),
            createdBy: '12D3KooWAlice',
            myRole: GroupRole.member,
            lastMembershipEventAt: removalAt,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'grp-abc123',
            keyGeneration: 2,
            encryptedKey: 'newer-key',
            createdAt: removalAt,
          ),
        );
        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            inviteId: 'invite-old',
            receivedAt: oldInviteAt,
            keyEpoch: 1,
            overrideGroupKey: 'old-key',
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
          now: removalAt.add(const Duration(minutes: 1)),
        );

        expect(result, AcceptPendingGroupInviteResult.invalidPayload);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(
          await groupRepo.getMember('grp-abc123', '12D3KooWReceiver'),
          isNull,
        );
        expect((await groupRepo.getLatestKey('grp-abc123'))!.keyGeneration, 2);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'RA-004 revoked old invite cannot create stale membership before current re-add invite succeeds',
      () async {
        final oldInviteAt = DateTime.utc(2026, 5, 13, 12);
        final removalAt = oldInviteAt.add(const Duration(minutes: 5));
        final currentInviteAt = removalAt.add(const Duration(minutes: 5));

        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            inviteId: 'invite-ra004-old',
            receivedAt: oldInviteAt,
            overrideGroupKey: 'old-key',
            keyEpoch: 1,
          ),
        );
        await pendingInviteRepo.saveRevokedInvite(
          GroupInviteRevocation(
            inviteId: 'invite-ra004-old',
            groupId: 'grp-abc123',
            revokedAt: removalAt,
            expiresAt: removalAt.add(const Duration(days: 7)),
            revokedBy: '12D3KooWAlice',
          ),
        );

        final (oldResult, oldGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          now: removalAt.add(const Duration(minutes: 1)),
        );

        expect(oldResult, AcceptPendingGroupInviteResult.revoked);
        expect(oldGroup, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(
          await groupRepo.getMember('grp-abc123', '12D3KooWReceiver'),
          isNull,
        );
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);

        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            inviteId: 'invite-ra004-current',
            receivedAt: currentInviteAt,
            overrideGroupKey: 'current-key',
            keyEpoch: 2,
          ),
        );

        final (currentResult, currentGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          now: currentInviteAt.add(const Duration(minutes: 1)),
        );

        expect(currentResult, AcceptPendingGroupInviteResult.success);
        expect(currentGroup, isNotNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        final latestKey = await groupRepo.getLatestKey('grp-abc123');
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 2);
        expect(latestKey.encryptedKey, 'current-key');
        expect(
          await groupRepo.getMember('grp-abc123', '12D3KooWReceiver'),
          isNotNull,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:join'),
          hasLength(1),
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
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'grp-abc123',
            peerId: '12D3KooWReceiver',
            username: 'Receiver',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 3, 2),
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
        final issuedAt = receivedAt.subtract(const Duration(hours: 1));
        await pendingInviteRepo.savePendingInvite(
          makeInvite(
            receivedAt: receivedAt,
            membershipProofIssuedAt: issuedAt,
            membershipProofExpiresAt: issuedAt.add(const Duration(hours: 18)),
          ),
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

        // This proof's issue time is incompatible with the payload timestamp
        // (an issue-time/structural failure), so it stays invalidPayload — it
        // is NOT the aged-out-freshness case A2 humanises (see the dedicated
        // expiredFreshness test below).
        expect(result, AcceptPendingGroupInviteResult.invalidPayload);
        expect(group, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await pendingInviteRepo.getConsumedInvite('invite-1'), isNull);
        expect(pendingInviteRepo.consumedCount, 0);
        expect(pendingInviteRepo.welcomeKeyPackageTombstoneCount, 0);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('payload.verify')));
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(bridge.commandLog, isNot(contains('group:inboxRetrieveCursor')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'A2: accept returns expiredFreshness (not invalidPayload) for a correctly-signed invite whose freshness proof has simply aged out, deleting it and emitting EXPIRED_FRESHNESS (not INVALID_SIGNATURE)',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final receivedAt = DateTime.utc(2026, 3, 2, 12);
        await pendingInviteRepo.savePendingInvite(
          // Default proof issuedAt (== payload timestamp) keeps the issue time
          // compatible and the TTL window sane; only the freshness deadline is
          // in the past relative to `now`, so the SOLE failure is staleness.
          makeInvite(
            receivedAt: receivedAt,
            membershipProofExpiresAt: receivedAt.add(const Duration(hours: 12)),
          ),
        );

        final (result, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          groupId: 'grp-abc123',
          // Card TTL (receivedAt + 7d) is still valid; only the freshness proof
          // (expired at receivedAt + 12h) has aged out.
          now: receivedAt.add(const Duration(days: 2)),
        );

        expect(result, AcceptPendingGroupInviteResult.expiredFreshness);
        expect(group, isNull);
        // A >TTL-stale proof can never become fresh again → the dead row is
        // still deleted (no resurrection).
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);

        // Telemetry: stale freshness gets its own distinct event and must NOT
        // be miscounted as a signature forgery.
        expect(
          flowEvents.where(
            (e) =>
                e['event'] == 'PENDING_GROUP_INVITE_ACCEPT_EXPIRED_FRESHNESS',
          ),
          hasLength(1),
        );
        expect(
          flowEvents.where(
            (e) =>
                e['event'] == 'PENDING_GROUP_INVITE_ACCEPT_INVALID_SIGNATURE',
          ),
          isEmpty,
        );
      },
    );

    test(
      'accepts delayed policy-valid invite after old freshness window',
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
          now: receivedAt.add(const Duration(hours: 25)),
        );

        expect(result, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getConsumedInvite('invite-1'),
          isNotNull,
        );
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
        expect(bridge.commandLog, contains('group:join'));
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

    test(
      'RA-013 device-bound re-add accept keeps sibling device pending until its own onboarding',
      () async {
        final multiDeviceConfig = receiverDeviceBoundConfig();
        final receiver =
            (multiDeviceConfig['members'] as List<dynamic>)[1]
                as Map<String, dynamic>;
        receiver['devices'] = [
          {
            'deviceId': 'receiver-phone',
            'transportPeerId': 'receiver-phone',
            'deviceSigningPublicKey': 'receiverPhonePubKey64',
            'mlKemPublicKey': 'receiverPhoneMlKem64',
            'keyPackageId': 'receiver-phone-kp',
            'keyPackagePublicMaterial': 'receiver-phone-kpm',
            'status': 'active',
          },
          {
            'deviceId': 'receiver-tablet',
            'transportPeerId': 'receiver-tablet',
            'deviceSigningPublicKey': 'receiverTabletPubKey64',
            'mlKemPublicKey': 'receiverTabletMlKem64',
            'keyPackageId': 'receiver-tablet-kp',
            'keyPackagePublicMaterial': 'receiver-tablet-kpm',
            'status': 'active',
          },
        ];

        final phonePendingInviteRepo = InMemoryPendingGroupInviteRepository();
        final tabletPendingInviteRepo = InMemoryPendingGroupInviteRepository();
        final wrongDevicePendingInviteRepo =
            InMemoryPendingGroupInviteRepository();
        final phoneGroupRepo = InMemoryGroupRepository();
        final tabletGroupRepo = InMemoryGroupRepository();
        final wrongDeviceGroupRepo = InMemoryGroupRepository();
        final phoneMsgRepo = InMemoryGroupMessageRepository();
        final tabletMsgRepo = InMemoryGroupMessageRepository();
        final wrongDeviceMsgRepo = InMemoryGroupMessageRepository();

        final phoneInvite = makeInvite(
          inviteId: 'ra013-phone-invite',
          groupConfig: multiDeviceConfig,
          recipientDeviceId: 'receiver-phone',
          recipientTransportPeerId: 'receiver-phone',
          recipientMlKemPublicKey: 'receiverPhoneMlKem64',
          recipientKeyPackageId: 'receiver-phone-kp',
          recipientKeyPackagePublicMaterial: 'receiver-phone-kpm',
        );
        final tabletInvite = makeInvite(
          inviteId: 'ra013-tablet-invite',
          groupConfig: multiDeviceConfig,
          recipientDeviceId: 'receiver-tablet',
          recipientTransportPeerId: 'receiver-tablet',
          recipientMlKemPublicKey: 'receiverTabletMlKem64',
          recipientKeyPackageId: 'receiver-tablet-kp',
          recipientKeyPackagePublicMaterial: 'receiver-tablet-kpm',
        );

        await phonePendingInviteRepo.savePendingInvite(phoneInvite);
        await tabletPendingInviteRepo.savePendingInvite(tabletInvite);
        await wrongDevicePendingInviteRepo.savePendingInvite(phoneInvite);

        final (phoneResult, phoneGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: phonePendingInviteRepo,
          groupRepo: phoneGroupRepo,
          contactRepo: contactRepo,
          msgRepo: phoneMsgRepo,
          bridge: FakeBridge(),
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiverPhonePubKey64',
          senderPrivateKey: 'receiverPhonePrivKey64',
          senderUsername: 'Receiver',
          ownDeviceId: 'receiver-phone',
          ownTransportPeerId: 'receiver-phone',
          ownMlKemPublicKey: 'receiverPhoneMlKem64',
          ownKeyPackageId: 'receiver-phone-kp',
          ownKeyPackagePublicMaterial: 'receiver-phone-kpm',
        );

        expect(phoneResult, AcceptPendingGroupInviteResult.success);
        expect(phoneGroup, isNotNull);
        expect(
          await phonePendingInviteRepo.getPendingInvite('grp-abc123'),
          isNull,
        );
        expect(
          await tabletPendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await tabletGroupRepo.getGroup('grp-abc123'), isNull);

        final phoneMember = await phoneGroupRepo.getMember(
          'grp-abc123',
          '12D3KooWReceiver',
        );
        expect(
          phoneMember!.devices.map((device) => device.deviceId),
          unorderedEquals(['receiver-phone', 'receiver-tablet']),
        );

        final (
          wrongDeviceResult,
          wrongDeviceGroup,
        ) = await acceptPendingGroupInvite(
          pendingInviteRepo: wrongDevicePendingInviteRepo,
          groupRepo: wrongDeviceGroupRepo,
          contactRepo: contactRepo,
          msgRepo: wrongDeviceMsgRepo,
          bridge: FakeBridge(),
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiverTabletPubKey64',
          senderPrivateKey: 'receiverTabletPrivKey64',
          senderUsername: 'Receiver',
          ownDeviceId: 'receiver-tablet',
          ownTransportPeerId: 'receiver-tablet',
          ownMlKemPublicKey: 'receiverTabletMlKem64',
          ownKeyPackageId: 'receiver-tablet-kp',
          ownKeyPackagePublicMaterial: 'receiver-tablet-kpm',
        );

        expect(wrongDeviceResult, AcceptPendingGroupInviteResult.wrongIdentity);
        expect(wrongDeviceGroup, isNull);
        expect(await wrongDeviceGroupRepo.getGroup('grp-abc123'), isNull);

        final (tabletResult, tabletGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: tabletPendingInviteRepo,
          groupRepo: tabletGroupRepo,
          contactRepo: contactRepo,
          msgRepo: tabletMsgRepo,
          bridge: FakeBridge(),
          groupId: 'grp-abc123',
          senderPeerId: '12D3KooWReceiver',
          senderPublicKey: 'receiverTabletPubKey64',
          senderPrivateKey: 'receiverTabletPrivKey64',
          senderUsername: 'Receiver',
          ownDeviceId: 'receiver-tablet',
          ownTransportPeerId: 'receiver-tablet',
          ownMlKemPublicKey: 'receiverTabletMlKem64',
          ownKeyPackageId: 'receiver-tablet-kp',
          ownKeyPackagePublicMaterial: 'receiver-tablet-kpm',
        );

        expect(tabletResult, AcceptPendingGroupInviteResult.success);
        expect(tabletGroup, isNotNull);
        expect(
          await tabletPendingInviteRepo.getPendingInvite('grp-abc123'),
          isNull,
        );
      },
    );
  });
}

class _InMemoryGroupPendingKeyRepairRepository
    implements
        GroupPendingKeyRepairRepository,
        GroupPendingKeyRepairExactRepository {
  final Map<String, GroupPendingKeyRepair> repairs = {};

  @override
  Future<GroupPendingKeyRepairUpsertResult> upsertPendingRepair(
    GroupPendingKeyRepair repair,
  ) async {
    final existing = repairs[repair.id];
    if (existing == null) {
      repairs[repair.id] = repair;
      return GroupPendingKeyRepairUpsertResult(repair: repair, created: true);
    }
    final merged = existing.copyWith(
      updatedAt: repair.updatedAt,
      replayEnvelopeJson: repair.replayEnvelopeJson,
      lastError: repair.lastError,
    );
    repairs[repair.id] = merged;
    return GroupPendingKeyRepairUpsertResult(repair: merged, created: false);
  }

  @override
  Future<GroupPendingKeyRepair?> getRepair(String id) async => repairs[id];

  @override
  Future<List<GroupPendingKeyRepair>> getPendingRepairsForGroupEpoch({
    required String groupId,
    required int keyEpoch,
    int limit = 50,
  }) async {
    return repairs.values
        .where(
          (repair) =>
              repair.groupId == groupId &&
              repair.keyEpoch == keyEpoch &&
              repair.status == groupPendingKeyRepairStatusPendingKey,
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<GroupPendingKeyRepair>> getAllPendingRepairs({
    int limit = 200,
  }) async {
    final pending =
        repairs.values
            .where(
              (repair) =>
                  repair.status == groupPendingKeyRepairStatusPendingKey,
            )
            .toList()
          ..sort((a, b) {
            final byCreated = a.createdAt.compareTo(b.createdAt);
            return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
          });
    return pending.take(limit).toList();
  }

  @override
  Future<List<GroupPendingKeyRepair>> getPendingRepairsForGroup({
    required String groupId,
    int limit = 100,
  }) async {
    final pending =
        repairs.values
            .where(
              (repair) =>
                  repair.groupId == groupId &&
                  repair.status == groupPendingKeyRepairStatusPendingKey,
            )
            .toList()
          ..sort((a, b) {
            final byCreated = a.createdAt.compareTo(b.createdAt);
            return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
          });
    return pending.take(limit).toList();
  }

  @override
  Future<void> deleteRepair(String id) async {
    repairs.remove(id);
  }

  @override
  Future<void> recordAttempt(String id, {required String? lastError}) async {
    final existing = repairs[id];
    if (existing == null) return;
    repairs[id] = existing.copyWith(
      attempts: existing.attempts + 1,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<GroupPendingKeyRepair?> recordAttemptIfExact(
    GroupPendingKeyRepair expected, {
    required String? lastError,
  }) async {
    final current = repairs[expected.id];
    if (current == null || !sameExactGroupPendingKeyRepair(current, expected)) {
      return null;
    }
    await recordAttempt(expected.id, lastError: lastError);
    return repairs[expected.id];
  }

  @override
  Future<bool> deleteRepairIfExact(GroupPendingKeyRepair expected) async {
    final current = repairs[expected.id];
    if (current == null || !sameExactGroupPendingKeyRepair(current, expected)) {
      return false;
    }
    repairs.remove(expected.id);
    return true;
  }

  @override
  Future<void> finalizeRepaired(String id) async {
    final existing = repairs[id];
    if (existing == null) return;
    repairs[id] = existing.copyWith(
      status: groupPendingKeyRepairStatusRepaired,
      lastError: null,
      finalizedAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<bool> finalizeRepairedIfExact(GroupPendingKeyRepair expected) async {
    final current = repairs[expected.id];
    if (current == null || !sameExactGroupPendingKeyRepair(current, expected)) {
      return false;
    }
    await finalizeRepaired(expected.id);
    return true;
  }

  @override
  Future<void> finalizeUndecryptable(
    String id, {
    required String lastError,
  }) async {
    final existing = repairs[id];
    if (existing == null) return;
    repairs[id] = existing.copyWith(
      status: groupPendingKeyRepairStatusUndecryptable,
      lastError: lastError,
      finalizedAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<bool> finalizeUndecryptableIfExact(
    GroupPendingKeyRepair expected, {
    required String lastError,
  }) async {
    final current = repairs[expected.id];
    if (current == null || !sameExactGroupPendingKeyRepair(current, expected)) {
      return false;
    }
    await finalizeUndecryptable(expected.id, lastError: lastError);
    return true;
  }
}

class _MutatingAcceptedRetryRepository extends InMemoryGroupRepository {
  bool rollbackBeforeRetryAuthorization = false;

  @override
  Future<SelfRemovedAcceptedRetryAuthorizationOutcome>
  authorizeAcceptedReentryRetry({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required int keyGeneration,
  }) async {
    if (rollbackBeforeRetryAuthorization) {
      rollbackBeforeRetryAuthorization = false;
      await super.rollbackAcceptedReentry(
        groupId: groupId,
        selfPeerId: selfPeerId,
        authorizationId: authorizationId,
      );
    }
    return super.authorizeAcceptedReentryRetry(
      groupId: groupId,
      selfPeerId: selfPeerId,
      authorizationId: authorizationId,
      signedMembershipWatermark: signedMembershipWatermark,
      signedIssuedAt: signedIssuedAt,
      keyGeneration: keyGeneration,
    );
  }
}

class _ReadSignalingRepository extends InMemoryGroupRepository {
  Completer<void>? nextGroupRead;
  var groupReadCount = 0;
  var _signalAtRead = 0;

  void signalAfterAdditionalGroupReads(int count) {
    nextGroupRead = Completer<void>();
    _signalAtRead = groupReadCount + count;
  }

  @override
  Future<GroupModel?> getGroup(String id) async {
    final result = await super.getGroup(id);
    groupReadCount++;
    final signal = nextGroupRead;
    if (signal != null &&
        !signal.isCompleted &&
        groupReadCount >= _signalAtRead) {
      signal.complete();
    }
    return result;
  }
}

class _CommandSchedulingBridge extends FakeBridge {
  _CommandSchedulingBridge({required this.command});

  final String command;
  Future<void> Function()? onCommandReturn;
  var _used = false;

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final response = await super.send(message);
    if (!_used && decoded['cmd'] == command) {
      _used = true;
      unawaited(onCommandReturn?.call());
    }
    return response;
  }
}
