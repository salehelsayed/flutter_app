import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/groups/domain/models/group_config_resync_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_decline_ack_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation_payload.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

const _testGroupConfig = {
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
      'peerId': '12D3KooWBob',
      'username': 'Bob',
      'role': 'writer',
      'publicKey': 'bobPubKey64',
      'mlKemPublicKey': 'bobMlKem64',
    },
  ],
  'createdBy': '12D3KooWAlice',
  'createdAt': '2026-03-02T00:00:00.000Z',
};

ContactModel _aliceContact({bool isBlocked = false}) {
  return ContactModel(
    peerId: '12D3KooWAlice',
    publicKey: 'alicePubKey64',
    rendezvous: '/ip4/0.0.0.0',
    username: 'Alice',
    signature: 'sig',
    scannedAt: '2026-01-01T00:00:00Z',
    mlKemPublicKey: 'aliceMlKem64',
    isBlocked: isBlocked,
    blockedAt: isBlocked ? '2026-01-01T00:00:00Z' : null,
  );
}

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
  DateTime? issuedAt,
  DateTime? expiresAt,
}) {
  final issuedAtUtc = issuedAt ?? DateTime.utc(2026, 3, 2, 12);
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
    issuedAt: issuedAtUtc,
    expiresAt: expiresAt ?? issuedAtUtc.add(groupInviteMembershipFreshnessTtl),
    inviterMemberSnapshot: {
      'peerId': '12D3KooWAlice',
      'username': 'Alice',
      'role': 'admin',
      'publicKey': 'alicePubKey64',
      'mlKemPublicKey': 'aliceMlKem64',
    },
  );
}

ChatMessage _makeV1InviteMessage({
  String groupId = 'grp-abc123',
  String senderPeerId = '12D3KooWAlice',
  Map<String, dynamic>? groupConfig,
}) {
  final effectiveGroupConfig = groupConfig ?? _testGroupConfig;
  final payload = GroupInvitePayload(
    id: 'invite-uuid-001',
    groupId: groupId,
    groupKey: 'base64GroupKey==',
    keyEpoch: 1,
    groupConfig: effectiveGroupConfig,
    senderPeerId: senderPeerId,
    senderUsername: 'Alice',
    timestamp: '2026-03-02T12:00:00.000Z',
    recipientPeerId: '12D3KooWBob',
    invitePolicy: GroupInvitePolicy(
      expiresAt: DateTime.utc(2099, 3, 9, 12),
      allowedDevices: const ['12D3KooWBob'],
      assignedRole: 'writer',
      canInviteOthers: false,
      joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
      keyEpoch: 1,
    ),
    membershipFreshnessProof: _makeFreshnessProof(
      inviteId: 'invite-uuid-001',
      groupId: groupId,
      recipientPeerId: '12D3KooWBob',
      groupConfig: effectiveGroupConfig,
    ),
  ).withInviteSignature(signature: 'signed-invite-by-alice');
  return ChatMessage(
    from: senderPeerId,
    to: 'myPeerId',
    content: payload.toJson(),
    timestamp: payload.timestamp,
    isIncoming: true,
  );
}

ChatMessage _makeV2InviteMessage({
  String groupId = 'grp-abc123',
  String senderPeerId = '12D3KooWAlice',
  Map<String, dynamic>? groupConfig,
}) {
  final effectiveGroupConfig = groupConfig ?? _testGroupConfig;
  final payload = GroupInvitePayload(
    id: 'invite-uuid-001',
    groupId: groupId,
    groupKey: 'base64GroupKey==',
    keyEpoch: 1,
    groupConfig: effectiveGroupConfig,
    senderPeerId: senderPeerId,
    senderUsername: 'Alice',
    timestamp: '2026-03-02T12:00:00.000Z',
    recipientPeerId: '12D3KooWBob',
    invitePolicy: GroupInvitePolicy(
      expiresAt: DateTime.utc(2099, 3, 9, 12),
      allowedDevices: const ['12D3KooWBob'],
      assignedRole: 'writer',
      canInviteOthers: false,
      joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
      keyEpoch: 1,
    ),
    membershipFreshnessProof: _makeFreshnessProof(
      inviteId: 'invite-uuid-001',
      groupId: groupId,
      recipientPeerId: '12D3KooWBob',
      groupConfig: effectiveGroupConfig,
    ),
  ).withInviteSignature(signature: 'signed-invite-by-alice');
  final innerJson = payload.toInnerJson();
  final envelope = GroupInvitePayload.buildEncryptedEnvelope(
    senderPeerId: senderPeerId,
    kem: 'fake-kem',
    ciphertext: innerJson,
    nonce: 'fake-nonce',
  );
  return ChatMessage(
    from: senderPeerId,
    to: 'myPeerId',
    content: envelope,
    timestamp: payload.timestamp,
    isIncoming: true,
  );
}

Map<String, dynamic> _signedInnerMap(GroupInvitePayload payload) {
  final inner = jsonDecode(payload.toInnerJson()) as Map<String, dynamic>;
  return {
    ...inner,
    'inviteSignature': {
      'signatureAlgorithm': 'ed25519',
      'signedPayload': payload.canonicalInviteSignedPayload(),
      'signature': 'signed-invite-by-alice',
    },
  };
}

ChatMessage _makeSignedV2InviteMessage({
  String groupId = 'grp-abc123',
  Map<String, dynamic>? groupConfig,
  DateTime? membershipProofIssuedAt,
  DateTime? membershipProofExpiresAt,
  DateTime? messageTimestamp,
  DateTime? policyExpiresAt,
}) {
  final effectiveGroupConfig = groupConfig ?? _testGroupConfig;
  final payload = GroupInvitePayload(
    id: 'invite-uuid-001',
    groupId: groupId,
    groupKey: 'base64GroupKey==',
    keyEpoch: 1,
    groupConfig: effectiveGroupConfig,
    senderPeerId: '12D3KooWAlice',
    senderUsername: 'Alice',
    timestamp: '2026-03-02T12:00:00.000Z',
    recipientPeerId: '12D3KooWBob',
    invitePolicy: GroupInvitePolicy(
      expiresAt: policyExpiresAt ?? DateTime.utc(2099, 3, 9, 12),
      allowedDevices: const ['12D3KooWBob'],
      assignedRole: 'writer',
      canInviteOthers: false,
      joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
      keyEpoch: 1,
    ),
    membershipFreshnessProof: _makeFreshnessProof(
      inviteId: 'invite-uuid-001',
      groupId: groupId,
      recipientPeerId: '12D3KooWBob',
      groupConfig: effectiveGroupConfig,
      issuedAt: membershipProofIssuedAt,
      expiresAt: membershipProofExpiresAt,
    ),
  ).withInviteSignature(signature: 'signed-invite-by-alice');
  final envelope = GroupInvitePayload.buildEncryptedEnvelope(
    senderPeerId: payload.senderPeerId,
    kem: 'fake-kem',
    ciphertext: jsonEncode(_signedInnerMap(payload)),
    nonce: 'fake-nonce',
  );
  return ChatMessage(
    from: payload.senderPeerId,
    to: 'myPeerId',
    content: envelope,
    timestamp: messageTimestamp?.toUtc().toIso8601String() ?? payload.timestamp,
    isIncoming: true,
  );
}

ChatMessage _makeSignedV2WelcomePackageInviteMessage({
  String packageId = 'key-package-bob-device-1',
  String packagePublicMaterial = 'bob-kpm-1',
}) {
  final policyExpiresAt = DateTime.utc(2099, 3, 9, 12);
  final groupConfig = {
    ..._testGroupConfig,
    'members': [
      (_testGroupConfig['members'] as List)[0],
      {
        'peerId': '12D3KooWBob',
        'username': 'Bob',
        'role': 'writer',
        'publicKey': 'bobPubKey64',
        'mlKemPublicKey': 'bobMlKem64',
        'devices': [
          {
            'deviceId': 'bob-device-1',
            'transportPeerId': 'bob-device-1',
            'deviceSigningPublicKey': 'bobPubKey64',
            'mlKemPublicKey': 'bobMlKem64',
            'keyPackageId': packageId,
            'keyPackagePublicMaterial': packagePublicMaterial,
            'status': 'active',
          },
        ],
      },
    ],
  };
  final welcomeKeyPackage = GroupWelcomeKeyPackage.create(
    packageId: packageId,
    publicMaterial: packagePublicMaterial,
    recipientPeerId: '12D3KooWBob',
    recipientDeviceId: 'bob-device-1',
    recipientTransportPeerId: 'bob-device-1',
    recipientMlKemPublicKey: 'bobMlKem64',
    inviteId: 'invite-uuid-001',
    groupId: 'grp-abc123',
    keyEpoch: 1,
    issuedAt: DateTime.utc(2026, 3, 2, 12),
    expiresAt: policyExpiresAt,
  );
  final payload = GroupInvitePayload(
    id: 'invite-uuid-001',
    groupId: 'grp-abc123',
    groupKey: 'base64GroupKey==',
    keyEpoch: 1,
    groupConfig: groupConfig,
    senderPeerId: '12D3KooWAlice',
    senderUsername: 'Alice',
    timestamp: '2026-03-02T12:00:00.000Z',
    recipientPeerId: '12D3KooWBob',
    recipientDeviceId: 'bob-device-1',
    recipientTransportPeerId: 'bob-device-1',
    recipientMlKemPublicKey: 'bobMlKem64',
    recipientKeyPackageId: packageId,
    recipientKeyPackagePublicMaterial: packagePublicMaterial,
    welcomeKeyPackage: welcomeKeyPackage,
    invitePolicy: GroupInvitePolicy(
      expiresAt: policyExpiresAt,
      allowedDevices: const ['bob-device-1'],
      assignedRole: 'writer',
      canInviteOthers: false,
      joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
      keyEpoch: 1,
      welcomeKeyPackageId: packageId,
      welcomeKeyPackagePublicMaterialHash: welcomeKeyPackage.publicMaterialHash,
      welcomeKeyPackageExpiresAt: policyExpiresAt,
    ),
    membershipFreshnessProof: _makeFreshnessProof(
      inviteId: 'invite-uuid-001',
      groupId: 'grp-abc123',
      recipientPeerId: '12D3KooWBob',
      recipientDeviceId: 'bob-device-1',
      recipientTransportPeerId: 'bob-device-1',
      recipientMlKemPublicKey: 'bobMlKem64',
      recipientKeyPackageId: packageId,
      recipientKeyPackagePublicMaterial: packagePublicMaterial,
      groupConfig: groupConfig,
    ),
  ).withInviteSignature(signature: 'signed-invite-by-alice');
  final envelope = GroupInvitePayload.buildEncryptedEnvelope(
    senderPeerId: payload.senderPeerId,
    kem: 'fake-kem',
    ciphertext: jsonEncode(_signedInnerMap(payload)),
    nonce: 'fake-nonce',
  );
  return ChatMessage(
    from: payload.senderPeerId,
    to: 'bob-device-1',
    content: envelope,
    timestamp: payload.timestamp,
    isIncoming: true,
  );
}

ChatMessage _makeSignedV2RevocationMessage({
  String inviteId = 'invite-uuid-001',
  String groupId = 'grp-abc123',
  String recipientPeerId = '12D3KooWBob',
  String revokedByPeerId = '12D3KooWAlice',
  DateTime? expiresAt,
  DateTime? messageTimestamp,
  Map<String, dynamic> revokerAuthorization = const {
    'peerId': '12D3KooWAlice',
    'publicKey': 'alicePubKey64',
    'role': 'admin',
    'permissions': {'inviteMembers': true},
  },
}) {
  final payload = GroupInviteRevocationPayload(
    inviteId: inviteId,
    groupId: groupId,
    recipientPeerId: recipientPeerId,
    revokedByPeerId: revokedByPeerId,
    revokedAt: '2026-03-02T12:10:00.000Z',
    expiresAt:
        expiresAt?.toUtc().toIso8601String() ?? '2099-03-09T12:00:00.000Z',
    revokerAuthorization: revokerAuthorization,
  ).withRevocationSignature(signature: 'signed-revocation-by-alice');
  final envelope = GroupInviteRevocationPayload.buildEncryptedEnvelope(
    senderPeerId: revokedByPeerId,
    inviteId: inviteId,
    kem: 'fake-kem',
    ciphertext: payload.toInnerJson(),
    nonce: 'fake-nonce',
  );
  return ChatMessage(
    from: revokedByPeerId,
    to: recipientPeerId,
    content: envelope,
    timestamp:
        messageTimestamp?.toUtc().toIso8601String() ??
        '2026-03-02T12:10:00.000Z',
    isIncoming: true,
  );
}

ChatMessage _makeSignedV2DeclineAckMessage({
  String inviteId = 'invite-uuid-001',
  String groupId = 'grp-abc123',
  String declinedByPeerId = '12D3KooWCharlie',
  String? envelopeSenderPeerId,
  String? from,
}) {
  final payload = GroupInviteDeclineAckPayload(
    inviteId: inviteId,
    groupId: groupId,
    declinedByPeerId: declinedByPeerId,
    declinedAt: '2026-03-02T12:00:00.000Z',
    expiresAt: '2099-03-09T12:00:00.000Z',
  ).withDeclineSignature(signature: 'signed-decline-by-charlie');
  final envelope = GroupInviteDeclineAckPayload.buildEncryptedEnvelope(
    senderPeerId: envelopeSenderPeerId ?? declinedByPeerId,
    inviteId: inviteId,
    kem: 'fake-kem',
    ciphertext: payload.toInnerJson(),
    nonce: 'fake-nonce',
  );
  return ChatMessage(
    from: from ?? declinedByPeerId,
    to: '12D3KooWBob',
    content: envelope,
    timestamp: '2026-03-02T12:00:00.000Z',
    isIncoming: true,
  );
}

Future<ChatMessage> _makeConfigResponseMessage({
  required Bridge bridge,
  String groupId = 'grp-abc123',
  String actorPeerId = '12D3KooWAlice',
  String actorUsername = 'Alice',
  String actorPublicKey = 'alicePubKey64',
  required String newName,
  required DateTime updatedAt,
}) async {
  final responderGroup = GroupModel(
    id: groupId,
    name: newName,
    type: GroupType.chat,
    topicName: '/mknoon/group/$groupId',
    createdAt: DateTime.utc(2026, 1, 1),
    createdBy: actorPeerId,
    myRole: GroupRole.admin,
    lastMetadataEventAt: updatedAt,
  );
  final members = [
    GroupMember(
      groupId: groupId,
      peerId: actorPeerId,
      username: actorUsername,
      role: MemberRole.admin,
      publicKey: actorPublicKey,
      joinedAt: DateTime.utc(2026, 1, 1),
    ),
  ];
  final groupConfig = buildGroupConfigPayload(responderGroup, members);
  final actorPayload = buildGroupMetadataActorEventPayload(
    groupId: groupId,
    updatedAt: updatedAt,
    actorPeerId: actorPeerId,
    actorUsername: actorUsername,
    actorPublicKey: actorPublicKey,
    groupConfig: groupConfig,
  );
  final canonical = canonicalizeGroupMetadataActorEventPayload(actorPayload);
  final sign = await callSignPayload(
    bridge: bridge,
    dataToSign: canonical,
    privateKey: 'priv',
  );
  final systemPayload = {
    '__sys': groupMetadataUpdatedEventType,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'groupConfig': groupConfig,
    groupMetadataActorEventEnvelopeField:
        buildSignedGroupMetadataActorEventEnvelope(
          signedPayload: canonical,
          signature: sign['signature'] as String,
        ),
  };
  final envelope = GroupConfigResyncEnvelope.build(
    type: groupConfigResponseType,
    senderPeerId: actorPeerId,
    groupId: groupId,
    kem: 'fake-kem',
    ciphertext: jsonEncode(systemPayload),
    nonce: 'fake-nonce',
  );
  return ChatMessage(
    from: actorPeerId,
    to: '12D3KooWBob',
    content: envelope,
    timestamp: '2026-06-10T12:00:00.000Z',
    isIncoming: true,
  );
}

class _SpyDeliveryRepo implements GroupInviteDeliveryAttemptRepository {
  final List<({String groupId, String peerId})> declinedCalls = [];

  @override
  Future<void> markDeclined({
    required String groupId,
    required String peerId,
    DateTime? declinedAt,
  }) async {
    declinedCalls.add((groupId: groupId, peerId: peerId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayRevocationDecryptBridge extends PassthroughCryptoBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'message.decrypt') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final ciphertext = payload['ciphertext'] as String? ?? '';
      if (ciphertext.contains('"revokedByPeerId"')) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
    return super.send(message);
  }
}

class _FailDecryptBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastSentMessage = message;

    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    lastCommand = cmd;

    if (cmd == 'message.decrypt') {
      return jsonEncode({
        'ok': false,
        'errorCode': 'DECRYPT_FAILED',
        'errorMessage': 'Cannot decrypt',
      });
    }

    return super.send(message);
  }
}

void main() {
  late StreamController<ChatMessage> incomingController;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late InMemoryMediaAttachmentRepository mediaRepo;
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;
  late GroupInviteListener listener;
  late DateTime listenerNow;

  setUp(() {
    incomingController = StreamController<ChatMessage>.broadcast();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    mediaRepo = InMemoryMediaAttachmentRepository();
    pendingInviteRepo = InMemoryPendingGroupInviteRepository();
    contactRepo = FakeContactRepository();
    bridge = PassthroughCryptoBridge();
    listenerNow = DateTime.utc(2026, 3, 2, 12);
    contactRepo.seed([_aliceContact()]);

    listener = GroupInviteListener(
      groupInviteStream: incomingController.stream,
      groupRepo: groupRepo,
      pendingInviteRepo: pendingInviteRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      msgRepo: msgRepo,
      mediaAttachmentRepo: mediaRepo,
      getOwnMlKemSecretKey: () async => 'mySecretKey',
      getOwnPeerId: () async => '12D3KooWBob',
      now: () => listenerNow,
    );
  });

  tearDown(() async {
    listener.dispose();
    await incomingController.close();
  });

  group('GroupInviteListener', () {
    test(
      'routes a decline-ack to markDeclined and does not store it as a pending invite',
      () async {
        final deliveryRepo = _SpyDeliveryRepo();
        final declineListener = GroupInviteListener(
          groupInviteStream: incomingController.stream,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          deliveryRepo: deliveryRepo,
          getOwnMlKemSecretKey: () async => 'mySecretKey',
          getOwnPeerId: () async => '12D3KooWBob',
          now: () => listenerNow,
        );
        addTearDown(declineListener.dispose);
        declineListener.start();

        incomingController.add(_makeSignedV2DeclineAckMessage());
        await Future.delayed(const Duration(milliseconds: 100));
        await declineListener.waitForIdle();

        expect(deliveryRepo.declinedCalls, hasLength(1));
        expect(deliveryRepo.declinedCalls.single.groupId, 'grp-abc123');
        expect(deliveryRepo.declinedCalls.single.peerId, '12D3KooWCharlie');
        // A decline-ack must NOT be mistaken for an incoming invite.
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
      },
    );

    test(
      'D: with the resync flag ON, a config:response routes through the listener and applies strictly-newer admin metadata',
      () async {
        final t1 = DateTime.utc(2026, 6, 1);
        final t2 = DateTime.utc(2026, 6, 10);
        await groupRepo.saveGroup(
          GroupModel(
            id: 'grp-abc123',
            name: 'Old Name',
            type: GroupType.chat,
            topicName: '/mknoon/group/grp-abc123',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: '12D3KooWAlice',
            myRole: GroupRole.member,
            lastMetadataEventAt: t1,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'grp-abc123',
            peerId: '12D3KooWAlice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'alicePubKey64',
            joinedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        final resyncListener = GroupInviteListener(
          groupInviteStream: incomingController.stream,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          getOwnMlKemSecretKey: () async => 'mySecretKey',
          getOwnPeerId: () async => '12D3KooWBob',
          onJoinMetadataResyncEnabled: true,
          now: () => listenerNow,
        );
        addTearDown(resyncListener.dispose);
        resyncListener.start();

        incomingController.add(
          await _makeConfigResponseMessage(
            bridge: bridge,
            newName: 'New Name',
            updatedAt: t2,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));
        await resyncListener.waitForIdle();

        final updated = await groupRepo.getGroup('grp-abc123');
        expect(updated!.name, 'New Name');
        expect(updated.lastMetadataEventAt, t2);
      },
    );

    test(
      'D: with the resync flag explicitly OFF, a config:response is ignored',
      () async {
        final t1 = DateTime.utc(2026, 6, 1);
        await groupRepo.saveGroup(
          GroupModel(
            id: 'grp-abc123',
            name: 'Old Name',
            type: GroupType.chat,
            topicName: '/mknoon/group/grp-abc123',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: '12D3KooWAlice',
            myRole: GroupRole.member,
            lastMetadataEventAt: t1,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'grp-abc123',
            peerId: '12D3KooWAlice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'alicePubKey64',
            joinedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        // Build the default is now ON, so prove the gate by explicitly
        // disabling it (the path a build takes via
        // `--dart-define=MKNOON_ENABLE_ONJOIN_METADATA_RESYNC=false`).
        final disabledListener = GroupInviteListener(
          groupInviteStream: incomingController.stream,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          getOwnMlKemSecretKey: () async => 'mySecretKey',
          getOwnPeerId: () async => '12D3KooWBob',
          onJoinMetadataResyncEnabled: false,
          now: () => listenerNow,
        );
        addTearDown(disabledListener.dispose);
        disabledListener.start();

        incomingController.add(
          await _makeConfigResponseMessage(
            bridge: bridge,
            newName: 'New Name',
            updatedAt: DateTime.utc(2026, 6, 10),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));
        await disabledListener.waitForIdle();

        // Unchanged: the resync path is gated off.
        expect((await groupRepo.getGroup('grp-abc123'))!.name, 'Old Name');
      },
    );

    test(
      'stores a valid v2 invite as pending and does not join immediately',
      () async {
        listener.start();

        final invites = <PendingGroupInvite>[];
        listener.pendingInviteStream.listen(invites.add);

        incomingController.add(_makeV2InviteMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, hasLength(1));
        expect(invites.first.groupId, 'grp-abc123');
        expect(invites.first.groupName, 'Book Club');
        expect(invites.first.groupDescription, 'A group for book lovers');
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'stores delayed policy-valid invite after old freshness window without joining',
      () async {
        final issuedAt = DateTime.utc(2026, 3, 2, 12);
        listenerNow = issuedAt.add(const Duration(hours: 25));
        listener.start();

        final invites = <PendingGroupInvite>[];
        listener.pendingInviteStream.listen(invites.add);

        incomingController.add(
          _makeSignedV2InviteMessage(
            membershipProofIssuedAt: issuedAt,
            messageTimestamp: listenerNow,
            policyExpiresAt: issuedAt.add(pendingGroupInviteTtl),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, hasLength(1));
        expect(invites.first.expiresAt, issuedAt.add(pendingGroupInviteTtl));
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'EK011 stores a valid first-class welcome package invite with local package id wiring',
      () async {
        final packageListener = GroupInviteListener(
          groupInviteStream: incomingController.stream,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          msgRepo: msgRepo,
          mediaAttachmentRepo: mediaRepo,
          getOwnMlKemSecretKey: () async => 'mySecretKey',
          getOwnPeerId: () async => '12D3KooWBob',
          getOwnDeviceId: () async => 'bob-device-1',
          getOwnTransportPeerId: () async => 'bob-device-1',
          getOwnMlKemPublicKey: () async => 'bobMlKem64',
          getOwnKeyPackageId: () async =>
              defaultGroupWelcomeKeyPackageIdForDevice('bob-device-1'),
          getOwnKeyPackagePublicMaterial: () async => 'bob-kpm-1',
          now: () => listenerNow,
        );
        addTearDown(packageListener.dispose);
        packageListener.start();

        final invites = <PendingGroupInvite>[];
        packageListener.pendingInviteStream.listen(invites.add);

        incomingController.add(_makeSignedV2WelcomePackageInviteMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, hasLength(1));
        expect(invites.first.groupId, 'grp-abc123');
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'EK011 rejects welcome package invites when the local package id does not match',
      () async {
        final packageListener = GroupInviteListener(
          groupInviteStream: incomingController.stream,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          msgRepo: msgRepo,
          mediaAttachmentRepo: mediaRepo,
          getOwnMlKemSecretKey: () async => 'mySecretKey',
          getOwnPeerId: () async => '12D3KooWBob',
          getOwnDeviceId: () async => 'bob-device-1',
          getOwnTransportPeerId: () async => 'bob-device-1',
          getOwnMlKemPublicKey: () async => 'bobMlKem64',
          getOwnKeyPackageId: () async => 'key-package-bob-device-2',
          getOwnKeyPackagePublicMaterial: () async => 'bob-kpm-1',
          now: () => listenerNow,
        );
        addTearDown(packageListener.dispose);
        packageListener.start();

        final invites = <PendingGroupInvite>[];
        packageListener.pendingInviteStream.listen(invites.add);

        incomingController.add(_makeSignedV2WelcomePackageInviteMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, isEmpty);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(groupRepo.groupCount, 0);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'IJ009 rejects copied signed invite before pending state when local identity differs',
      () async {
        final copiedListener = GroupInviteListener(
          groupInviteStream: incomingController.stream,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          msgRepo: msgRepo,
          mediaAttachmentRepo: mediaRepo,
          getOwnMlKemSecretKey: () async => 'mySecretKey',
          getOwnPeerId: () async => '12D3KooWEve',
          now: () => listenerNow,
        );
        addTearDown(copiedListener.dispose);
        copiedListener.start();

        final invites = <PendingGroupInvite>[];
        copiedListener.pendingInviteStream.listen(invites.add);

        incomingController.add(_makeSignedV2InviteMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, isEmpty);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(pendingInviteRepo.count, 0);
        expect(groupRepo.groupCount, 0);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'IJ009 rejects signed invite before pending state when local identity is unavailable',
      () async {
        final unavailableIdentityListener = GroupInviteListener(
          groupInviteStream: incomingController.stream,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          msgRepo: msgRepo,
          mediaAttachmentRepo: mediaRepo,
          getOwnMlKemSecretKey: () async => 'mySecretKey',
          getOwnPeerId: () async => null,
          now: () => listenerNow,
        );
        addTearDown(unavailableIdentityListener.dispose);
        unavailableIdentityListener.start();

        final invites = <PendingGroupInvite>[];
        unavailableIdentityListener.pendingInviteStream.listen(invites.add);

        incomingController.add(_makeSignedV2InviteMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, isEmpty);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(pendingInviteRepo.count, 0);
        expect(groupRepo.groupCount, 0);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test('does not store pending invite from unknown sender', () async {
      contactRepo.seed([]);
      listener.start();

      final invites = <PendingGroupInvite>[];
      listener.pendingInviteStream.listen(invites.add);

      incomingController.add(_makeV1InviteMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(invites, isEmpty);
      expect(pendingInviteRepo.count, 0);
      expect(groupRepo.groupCount, 0);
    });

    test(
      'GL-005 rejects public-preview-shaped invites from unknown or blocked senders before pending or join state',
      () async {
        final publicPreviewConfig = {
          ..._testGroupConfig,
          'visibility': 'public',
          'isPublic': true,
          'discoverable': true,
          'openJoin': true,
          'inviteLink': 'https://example.invalid/join/grp-public',
          'publicPreview': {'name': 'Public Preview'},
          'publicListing': true,
        };

        listener.start();
        final invites = <PendingGroupInvite>[];
        listener.pendingInviteStream.listen(invites.add);

        contactRepo.seed([]);
        incomingController.add(
          _makeV1InviteMessage(
            groupId: 'grp-public-unknown',
            senderPeerId: 'peer-public-catalog',
            groupConfig: publicPreviewConfig,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        contactRepo.seed([_aliceContact(isBlocked: true)]);
        incomingController.add(
          _makeV1InviteMessage(
            groupId: 'grp-public-blocked',
            groupConfig: publicPreviewConfig,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, isEmpty);
        expect(pendingInviteRepo.count, 0);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-public-unknown'),
          isNull,
        );
        expect(
          await pendingInviteRepo.getPendingInvite('grp-public-blocked'),
          isNull,
        );
        expect(groupRepo.groupCount, 0);
        expect(await groupRepo.getGroup('grp-public-unknown'), isNull);
        expect(await groupRepo.getGroup('grp-public-blocked'), isNull);
        expect(await groupRepo.getLatestKey('grp-public-unknown'), isNull);
        expect(await groupRepo.getLatestKey('grp-public-blocked'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test('does not store pending invite for an already joined group', () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: 'grp-abc123',
          name: 'Already Joined',
          type: GroupType.chat,
          topicName: '/mknoon/group/grp-abc123',
          createdAt: DateTime.utc(2026, 1, 1),
          createdBy: '12D3KooWAlice',
          myRole: GroupRole.admin,
        ),
      );
      // B3: "already joined" means self is an ACTIVE member — only then is a
      // fresh invite a true duplicate. (A retained-removed shell, where self is
      // absent, intentionally stores the re-add invite to allow re-joining.)
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'grp-abc123',
          peerId: '12D3KooWBob',
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      listener.start();
      final invites = <PendingGroupInvite>[];
      listener.pendingInviteStream.listen(invites.add);

      incomingController.add(_makeV1InviteMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(invites, isEmpty);
      expect(pendingInviteRepo.count, 0);
      expect((await groupRepo.getGroup('grp-abc123'))!.name, 'Already Joined');
    });

    test('does not crash on decryption failure', () async {
      final failListener = GroupInviteListener(
        groupInviteStream: incomingController.stream,
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        contactRepo: contactRepo,
        bridge: _FailDecryptBridge(),
        getOwnMlKemSecretKey: () async => 'mySecretKey',
        getOwnPeerId: () async => '12D3KooWBob',
        now: () => listenerNow,
      );
      addTearDown(failListener.dispose);
      failListener.start();

      final invites = <PendingGroupInvite>[];
      failListener.pendingInviteStream.listen(invites.add);

      incomingController.add(_makeV2InviteMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(invites, isEmpty);
      expect(pendingInviteRepo.count, 0);
    });

    test(
      'calling start twice does not create duplicate subscriptions',
      () async {
        listener.start();
        listener.start();

        final invites = <PendingGroupInvite>[];
        listener.pendingInviteStream.listen(invites.add);

        incomingController.add(_makeV1InviteMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, hasLength(1));
        expect(pendingInviteRepo.count, 1);
      },
    );

    test('stop prevents further processing', () async {
      listener.start();
      listener.stop();

      incomingController.add(_makeV1InviteMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(pendingInviteRepo.count, 0);
    });

    test('dispose is safe after start', () {
      listener.start();
      listener.dispose();
    });

    test('does not process invite from blocked contact', () async {
      contactRepo.seed([_aliceContact(isBlocked: true)]);
      listener.start();

      incomingController.add(_makeV1InviteMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(pendingInviteRepo.count, 0);
      expect(groupRepo.groupCount, 0);
    });

    test(
      'IJ002 does not store pending invite when signature verification fails',
      () async {
        bridge.responses['payload.verify'] = {'ok': true, 'valid': false};
        listener.start();

        final invites = <PendingGroupInvite>[];
        listener.pendingInviteStream.listen(invites.add);

        incomingController.add(_makeSignedV2InviteMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, isEmpty);
        expect(pendingInviteRepo.count, 0);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(groupRepo.groupCount, 0);
        expect(bridge.commandLog, contains('payload.verify'));
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'IJ002 does not store pending invite from unauthorized or removed inviter',
      () async {
        listener.start();

        final invites = <PendingGroupInvite>[];
        listener.pendingInviteStream.listen(invites.add);

        incomingController.add(
          _makeSignedV2InviteMessage(
            groupId: 'grp-non-admin',
            groupConfig: {
              ..._testGroupConfig,
              'members': [
                {
                  'peerId': '12D3KooWAlice',
                  'username': 'Alice',
                  'role': 'writer',
                  'publicKey': 'alicePubKey64',
                  'mlKemPublicKey': 'aliceMlKem64',
                },
                (_testGroupConfig['members'] as List<dynamic>)[1],
              ],
            },
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        incomingController.add(
          _makeSignedV2InviteMessage(
            groupId: 'grp-removed',
            groupConfig: {
              ..._testGroupConfig,
              'members': [(_testGroupConfig['members'] as List<dynamic>)[1]],
            },
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, isEmpty);
        expect(pendingInviteRepo.count, 0);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-non-admin'),
          isNull,
        );
        expect(await pendingInviteRepo.getPendingInvite('grp-removed'), isNull);
        expect(groupRepo.groupCount, 0);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'PREREQ-INVITER-FRESHNESS does not store stale self-consistent invite from removed inviter',
      () async {
        final issuedAt = DateTime.utc(2026, 3, 2, 12);
        final invites = <PendingGroupInvite>[];
        listener.pendingInviteStream.listen(invites.add);
        listener.start();

        listenerNow = issuedAt
            .add(groupInviteMembershipFreshnessTtl)
            .add(const Duration(seconds: 1));
        incomingController.add(
          _makeSignedV2InviteMessage(
            membershipProofIssuedAt: issuedAt,
            membershipProofExpiresAt: issuedAt.add(
              groupInviteMembershipFreshnessTtl,
            ),
            messageTimestamp: issuedAt,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, isEmpty);
        expect(pendingInviteRepo.count, 0);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'duplicate pending invite replaces the existing preview row',
      () async {
        listener.start();

        incomingController.add(_makeV1InviteMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        final refreshedConfig = {
          ..._testGroupConfig,
          'name': 'Renamed Book Club',
          'description': 'Updated invite preview',
        };
        incomingController.add(
          _makeV1InviteMessage(groupConfig: refreshedConfig),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        expect(pendingInviteRepo.count, 1);
        final stored = await pendingInviteRepo.getPendingInvite('grp-abc123');
        expect(stored, isNotNull);
        expect(stored!.groupName, 'Renamed Book Club');
        expect(stored.groupDescription, 'Updated invite preview');
      },
    );

    test(
      'IJ003 valid revocation removes matching pending invite and stores tombstone',
      () async {
        final pendingPayload = GroupInvitePayload.fromJson(
          _makeV1InviteMessage().content,
        )!;
        final existingInvite = PendingGroupInvite.fromPayload(
          pendingPayload,
          receivedAt: DateTime.utc(2026, 3, 2, 12),
        );
        await pendingInviteRepo.savePendingInvite(existingInvite);

        listener.start();
        final refreshFuture = listener.pendingInviteStream.first;

        incomingController.add(_makeSignedV2RevocationMessage());

        final refreshSignal = await refreshFuture.timeout(
          const Duration(seconds: 1),
        );
        expect(refreshSignal.inviteId, 'invite-uuid-001');
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);

        final tombstone = await pendingInviteRepo.getRevokedInvite(
          'invite-uuid-001',
        );
        expect(tombstone, isNotNull);
        expect(tombstone!.groupId, 'grp-abc123');
        expect(tombstone.revokedBy, '12D3KooWAlice');
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, contains('payload.verify'));
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'IJ003 revocation freshness uses local receive time over forged old message timestamp',
      () async {
        final pendingPayload = GroupInvitePayload.fromJson(
          _makeV1InviteMessage().content,
        )!;
        await pendingInviteRepo.savePendingInvite(
          PendingGroupInvite.fromPayload(
            pendingPayload,
            receivedAt: DateTime.utc(2026, 3, 2, 12),
          ),
        );

        listenerNow = DateTime.utc(2026, 3, 3, 12);
        listener.start();
        final refreshSignals = <PendingGroupInvite>[];
        listener.pendingInviteStream.listen(refreshSignals.add);

        incomingController.add(
          _makeSignedV2RevocationMessage(
            expiresAt: DateTime.utc(2026, 3, 2, 12, 15),
            messageTimestamp: DateTime.utc(2026, 3, 2, 12, 10),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        expect(refreshSignals, isEmpty);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(
          await pendingInviteRepo.getRevokedInvite('invite-uuid-001'),
          isNull,
        );
      },
    );

    test(
      'IJ003 serializes revocation before later invite for the same invite id',
      () async {
        final delayedBridge = _DelayRevocationDecryptBridge();
        final serializedListener = GroupInviteListener(
          groupInviteStream: incomingController.stream,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: delayedBridge,
          msgRepo: msgRepo,
          mediaAttachmentRepo: mediaRepo,
          getOwnMlKemSecretKey: () async => 'mySecretKey',
          getOwnPeerId: () async => '12D3KooWBob',
          now: () => listenerNow,
        );
        addTearDown(serializedListener.dispose);

        final refreshSignals = <PendingGroupInvite>[];
        serializedListener.pendingInviteStream.listen(refreshSignals.add);
        serializedListener.start();

        incomingController
          ..add(_makeSignedV2RevocationMessage())
          ..add(_makeSignedV2InviteMessage());
        await Future.delayed(const Duration(milliseconds: 250));

        expect(refreshSignals, isEmpty);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getRevokedInvite('invite-uuid-001'),
          isNotNull,
        );
        expect(delayedBridge.commandLog, isNot(contains('group:join')));
      },
    );

    test('IJ003 invalid revocation leaves pending invite unchanged', () async {
      final pendingPayload = GroupInvitePayload.fromJson(
        _makeV1InviteMessage().content,
      )!;
      await pendingInviteRepo.savePendingInvite(
        PendingGroupInvite.fromPayload(
          pendingPayload,
          receivedAt: DateTime.utc(2026, 3, 2, 12),
        ),
      );
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};

      listener.start();
      final refreshSignals = <PendingGroupInvite>[];
      listener.pendingInviteStream.listen(refreshSignals.add);

      incomingController.add(_makeSignedV2RevocationMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(refreshSignals, isEmpty);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNotNull);
      expect(
        await pendingInviteRepo.getRevokedInvite('invite-uuid-001'),
        isNull,
      );
      expect(groupRepo.groupCount, 0);
      expect(bridge.commandLog, isNot(contains('group:join')));
    });
  });
}
