import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/delete_self_removed_group_shell_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

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

const _deviceBoundGroupConfig = {
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
          'keyPackageId': 'alice-kp-1',
          'keyPackagePublicMaterial': 'alice-kpm-1',
          'status': 'active',
        },
      ],
    },
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
          'keyPackageId': 'bob-kp-1',
          'keyPackagePublicMaterial': 'bob-kpm-1',
          'status': 'active',
        },
      ],
    },
  ],
  'createdBy': '12D3KooWAlice',
  'createdAt': '2026-03-02T00:00:00.000Z',
};

GroupInviteMembershipFreshnessProof _makeFreshnessProof({
  required String inviteId,
  required String groupId,
  required String? recipientPeerId,
  required Map<String, dynamic> groupConfig,
  required int keyEpoch,
  String? recipientDeviceId,
  String? recipientTransportPeerId,
  String? recipientMlKemPublicKey,
  String? recipientKeyPackageId,
  String? recipientKeyPackagePublicMaterial,
  String? inviterDeviceId,
  String? inviterTransportPeerId,
  String? inviterDeviceSigningPublicKey,
  String? inviterKeyPackageId,
  Map<String, dynamic>? inviterMemberSnapshot,
  DateTime? issuedAt,
  DateTime? expiresAt,
  String? membershipWatermark,
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
    inviterDeviceId: inviterDeviceId,
    inviterTransportPeerId: inviterTransportPeerId,
    inviterDeviceSigningPublicKey: inviterDeviceSigningPublicKey,
    inviterKeyPackageId: inviterKeyPackageId,
    inviterPublicKey: 'alicePubKey64',
    keyEpoch: keyEpoch,
    groupConfigStateHash: stateHash,
    membershipWatermark: membershipWatermark ?? stateHash,
    issuedAt: issuedAtUtc,
    expiresAt: expiresAt ?? issuedAtUtc.add(groupInviteMembershipFreshnessTtl),
    inviterMemberSnapshot:
        inviterMemberSnapshot ??
        {
          'peerId': '12D3KooWAlice',
          'username': 'Alice',
          'role': 'admin',
          'publicKey': 'alicePubKey64',
          'mlKemPublicKey': 'aliceMlKem64',
        },
  );
}

GroupInvitePayload _makePayload({
  String groupId = 'grp-abc123',
  String? overrideGroupKey,
  String? recipientPeerId = '12D3KooWBob',
  Map<String, dynamic> groupConfig = _testGroupConfig,
  String assignedRole = 'writer',
  int keyEpoch = 1,
  String? recipientDeviceId,
  String? recipientTransportPeerId,
  String? recipientMlKemPublicKey,
  String? recipientKeyPackageId,
  String? recipientKeyPackagePublicMaterial,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderDeviceSigningPublicKey,
  String? senderKeyPackageId,
  Map<String, dynamic>? inviterMemberSnapshot,
  DateTime? membershipProofIssuedAt,
  DateTime? membershipProofExpiresAt,
  DateTime? invitePolicyExpiresAt,
  String? membershipWatermark,
}) {
  final issuedAtUtc = (membershipProofIssuedAt ?? DateTime.now().toUtc())
      .toUtc();
  final policyExpiresAt = invitePolicyExpiresAt ?? DateTime.utc(2099, 3, 9, 12);
  final allowedDevices = <String>[];
  if (recipientDeviceId != null) {
    allowedDevices.add(recipientDeviceId);
  } else if (recipientPeerId != null && recipientPeerId.isNotEmpty) {
    allowedDevices.add(recipientPeerId);
  }
  final welcomeKeyPackage =
      recipientKeyPackageId != null &&
          recipientKeyPackagePublicMaterial != null &&
          recipientDeviceId != null &&
          recipientTransportPeerId != null &&
          recipientMlKemPublicKey != null
      ? GroupWelcomeKeyPackage.create(
          packageId: recipientKeyPackageId,
          publicMaterial: recipientKeyPackagePublicMaterial,
          recipientPeerId: '12D3KooWBob',
          recipientDeviceId: recipientDeviceId,
          recipientTransportPeerId: recipientTransportPeerId,
          recipientMlKemPublicKey: recipientMlKemPublicKey,
          inviteId: 'invite-uuid-001',
          groupId: groupId,
          keyEpoch: keyEpoch,
          issuedAt: issuedAtUtc,
          expiresAt: policyExpiresAt,
        )
      : null;
  final payload = GroupInvitePayload(
    id: 'invite-uuid-001',
    groupId: groupId,
    groupKey: overrideGroupKey ?? 'base64GroupKey==',
    keyEpoch: keyEpoch,
    groupConfig: groupConfig,
    senderPeerId: '12D3KooWAlice',
    senderUsername: 'Alice',
    timestamp: issuedAtUtc.toIso8601String(),
    recipientPeerId: recipientPeerId,
    recipientDeviceId: recipientDeviceId,
    recipientTransportPeerId: recipientTransportPeerId,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    recipientKeyPackageId: recipientKeyPackageId,
    recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
    welcomeKeyPackage: welcomeKeyPackage,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderDeviceSigningPublicKey: senderDeviceSigningPublicKey,
    senderKeyPackageId: senderKeyPackageId,
    invitePolicy: GroupInvitePolicy(
      expiresAt: policyExpiresAt,
      allowedDevices: allowedDevices,
      assignedRole: assignedRole,
      canInviteOthers: false,
      joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
      keyEpoch: keyEpoch,
      welcomeKeyPackageId: welcomeKeyPackage?.packageId,
      welcomeKeyPackagePublicMaterialHash:
          welcomeKeyPackage?.publicMaterialHash,
      welcomeKeyPackageExpiresAt: welcomeKeyPackage?.expiresAt,
    ),
    membershipFreshnessProof: _makeFreshnessProof(
      inviteId: 'invite-uuid-001',
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      recipientDeviceId: recipientDeviceId,
      recipientTransportPeerId: recipientTransportPeerId,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      recipientKeyPackageId: recipientKeyPackageId,
      recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
      inviterDeviceId: senderDeviceId,
      inviterTransportPeerId: senderTransportPeerId,
      inviterDeviceSigningPublicKey: senderDeviceSigningPublicKey,
      inviterKeyPackageId: senderKeyPackageId,
      inviterMemberSnapshot: inviterMemberSnapshot,
      groupConfig: groupConfig,
      keyEpoch: keyEpoch,
      issuedAt: issuedAtUtc,
      expiresAt: membershipProofExpiresAt,
      membershipWatermark: membershipWatermark,
    ),
  );
  return payload.withInviteSignature(signature: 'signed-invite-by-alice');
}

ChatMessage _makeV1Message({GroupInvitePayload? payload}) {
  final p = payload ?? _makePayload();
  return ChatMessage(
    from: p.senderPeerId,
    to:
        p.recipientTransportPeerId ??
        p.recipientDeviceId ??
        p.recipientPeerId ??
        'myPeerId',
    content: p.toJson(),
    timestamp: p.timestamp,
    isIncoming: true,
  );
}

Map<String, dynamic> _signedPayloadMap(GroupInvitePayload payload) {
  final payloadMap =
      (jsonDecode(payload.toJson()) as Map<String, dynamic>)['payload']
          as Map<String, dynamic>;
  return {
    ...payloadMap,
    'inviteSignature': {
      'signatureAlgorithm': 'ed25519',
      'signedPayload': payload.canonicalInviteSignedPayload(),
      'signature': 'signed-invite-by-alice',
    },
  };
}

ChatMessage _makeSignedV1Message({GroupInvitePayload? payload}) {
  final p = payload ?? _makePayload();
  return ChatMessage(
    from: p.senderPeerId,
    to:
        p.recipientTransportPeerId ??
        p.recipientDeviceId ??
        p.recipientPeerId ??
        'myPeerId',
    content: jsonEncode({
      'type': 'group_invite',
      'version': '1',
      'payload': _signedPayloadMap(p),
    }),
    timestamp: p.timestamp,
    isIncoming: true,
  );
}

ChatMessage _makeV2Message({
  GroupInvitePayload? payload,
  PassthroughCryptoBridge? bridge,
}) {
  final p = payload ?? _makePayload();
  // PassthroughCryptoBridge returns plaintext as ciphertext, so we just
  // use the inner JSON directly as the ciphertext.
  final innerJson = p.toInnerJson();
  final envelope = GroupInvitePayload.buildEncryptedEnvelope(
    senderPeerId: p.senderPeerId,
    kem: 'fake-kem',
    ciphertext: innerJson,
    nonce: 'fake-nonce',
  );
  return ChatMessage(
    from: p.senderPeerId,
    to:
        p.recipientTransportPeerId ??
        p.recipientDeviceId ??
        p.recipientPeerId ??
        'myPeerId',
    content: envelope,
    timestamp: p.timestamp,
    isIncoming: true,
  );
}

ContactModel _aliceContact() {
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

/// A bridge that throws TimeoutException on group:join commands.
class _TimeoutJoinBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastSentMessage = message;

    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    lastCommand = cmd;

    if (cmd == 'group:join') {
      throw TimeoutException('Simulated timeout');
    }

    return super.send(message);
  }
}

/// A bridge that throws a plain (non-bridge, non-timeout) Exception on
/// group:join — exercises the generic catch branch of materialize.
class _GenericFailJoinBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastSentMessage = message;

    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    lastCommand = cmd;

    if (cmd == 'group:join') {
      throw Exception('Simulated generic join failure');
    }

    return super.send(message);
  }
}

class _GateableJoinBridge extends FakeBridge {
  final Completer<void> joinStarted = Completer<void>();
  final Completer<void> _releaseJoin = Completer<void>();

  void releaseJoin() {
    if (!_releaseJoin.isCompleted) {
      _releaseJoin.complete();
    }
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:join') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      if (!joinStarted.isCompleted) {
        joinStarted.complete();
      }
      await _releaseJoin.future;
      return jsonEncode({'ok': true});
    }
    return super.send(message);
  }
}

class _GateableShellDeleteRepository extends InMemoryGroupRepository {
  final Completer<void> deleteEntered = Completer<void>();
  final Completer<void> _releaseDelete = Completer<void>();

  void releaseDelete() {
    if (!_releaseDelete.isCompleted) {
      _releaseDelete.complete();
    }
  }

  @override
  Future<SelfRemovedShellMediaBatch> loadSelfRemovedShellMediaParents({
    required SelfRemovedShellAuthoritySnapshot expected,
    required int limit,
  }) async {
    if (!deleteEntered.isCompleted) {
      deleteEntered.complete();
    }
    await _releaseDelete.future;
    return super.loadSelfRemovedShellMediaParents(
      expected: expected,
      limit: limit,
    );
  }
}

class _ExpiryBarrierRepository extends InMemoryGroupRepository {
  final Completer<void> preLockSelfCheckDone = Completer<void>();

  @override
  Future<GroupMember?> getMember(String groupId, String peerId) async {
    final member = await super.getMember(groupId, peerId);
    if (!preLockSelfCheckDone.isCompleted) {
      preLockSelfCheckDone.complete();
    }
    return member;
  }
}

/// A bridge that returns ok=false for message.decrypt
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
  late InMemoryGroupRepository groupRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;

  setUp(() {
    groupRepo = InMemoryGroupRepository();
    contactRepo = FakeContactRepository();
    bridge = FakeBridge();
    contactRepo.seed([_aliceContact()]);
  });

  group('handleIncomingGroupInvite', () {
    test(
      // TC-321-09 (plan 321) — drains fire once per regained-key member and
      // only after the join is fully persisted. The observable is repo state
      // at drain time: on HEAD drains ran inside the roster loop (before
      // saveKey), so getLatestKey was still null.
      'deferred key-distribution drains run once per regained member, after the join is fully persisted',
      () async {
        final drainedPeers = <String>[];
        final keyPersistedAtDrainTime = <bool>[];
        setDeferredDistributionDrainSink((
            {required String groupId, required String peerId}) async {
          drainedPeers.add(peerId);
          keyPersistedAtDrainTime
              .add((await groupRepo.getLatestKey(groupId)) != null);
        });
        addTearDown(() => setDeferredDistributionDrainSink(null));

        final (result, _) = await handleIncomingGroupInvite(
          message: _makeV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, equals(HandleGroupInviteResult.success));
        expect(
          drainedPeers.toSet(),
          {'12D3KooWAlice', '12D3KooWBob'},
          reason: 'every keyed roster member drains exactly once on a fresh '
              'join (existing == null passes the regained-key gate)',
        );
        expect(drainedPeers.length, 2);
        expect(
          keyPersistedAtDrainTime.every((persisted) => persisted),
          isTrue,
          reason: 'TC-321-09: drains must run AFTER the join is fully '
              'persisted (HEAD drains inside the roster loop, before saveKey)',
        );
      },
    );

    // --- Cycle 4.1 ---
    test(
      'persists group, members, and key for a valid invite payload',
      () async {
        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, equals(HandleGroupInviteResult.success));
        expect(groupId, equals('grp-abc123'));

        final group = await groupRepo.getGroup('grp-abc123');
        expect(group, isNotNull);
        expect(group!.name, equals('Book Club'));
        expect(group.type, equals(GroupType.chat));
        expect(group.topicName, equals('/mknoon/group/grp-abc123'));
        expect(group.createdBy, equals('12D3KooWAlice'));
        expect(group.myRole, equals(GroupRole.member));
        expect(group.description, equals('A group for book lovers'));

        final members = await groupRepo.getMembers('grp-abc123');
        expect(members, hasLength(2));
        expect(members.any((m) => m.peerId == '12D3KooWAlice'), isTrue);
        expect(members.any((m) => m.peerId == '12D3KooWBob'), isTrue);

        final key = await groupRepo.getLatestKey('grp-abc123');
        expect(key, isNotNull);
        expect(key!.encryptedKey, equals('base64GroupKey=='));
        expect(key.keyGeneration, equals(1));
      },
    );

    test(
      'uses membership freshness watermark for accepted invite membership state',
      () async {
        final membershipWatermark = DateTime.utc(2026, 3, 2, 12, 30, 45);
        final staleConfigVersion = DateTime.utc(2026, 3, 2, 13, 5);
        final groupConfig = {
          ..._testGroupConfig,
          groupConfigVersionField: staleConfigVersion.toIso8601String(),
        };
        final payload = _makePayload(
          groupId: 'grp-membership-watermark',
          groupConfig: groupConfig,
          membershipWatermark: membershipWatermark.toIso8601String(),
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV1Message(payload: payload),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, HandleGroupInviteResult.success);
        expect(groupId, 'grp-membership-watermark');

        final group = await groupRepo.getGroup('grp-membership-watermark');
        expect(group?.lastMembershipEventAt, membershipWatermark);

        final members = await groupRepo.getMembers('grp-membership-watermark');
        expect(members, hasLength(2));
        for (final member in members) {
          expect(member.joinedAt, membershipWatermark);
        }
      },
    );

    test(
      'rejects device-bound invite with wrong or missing local device identity before side effects',
      () async {
        Future<void> expectRejected({
          required String label,
          String? ownDeviceId,
          String? ownTransportPeerId,
          String? ownKeyPackageId = 'bob-kp-1',
        }) async {
          groupRepo = InMemoryGroupRepository();
          bridge = FakeBridge();
          final payload = _makePayload(
            groupId: 'grp-device-$label',
            groupConfig: _deviceBoundGroupConfig,
            recipientDeviceId: 'bob-device-1',
            recipientTransportPeerId: 'bob-device-1',
            recipientMlKemPublicKey: 'bobMlKem64',
            recipientKeyPackageId: 'bob-kp-1',
            recipientKeyPackagePublicMaterial: 'bob-kpm-1',
          );

          final (result, groupId) = await handleIncomingGroupInvite(
            message: _makeSignedV1Message(payload: payload),
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownPeerId: '12D3KooWBob',
            ownDeviceId: ownDeviceId,
            ownTransportPeerId: ownTransportPeerId,
            ownMlKemPublicKey: 'bobMlKem64',
            ownKeyPackageId: ownKeyPackageId,
            ownKeyPackagePublicMaterial: 'bob-kpm-1',
          );

          expect(result, HandleGroupInviteResult.invalidPayload, reason: label);
          expect(groupId, isNull, reason: label);
          expect(
            await groupRepo.getGroup(payload.groupId),
            isNull,
            reason: label,
          );
          expect(
            await groupRepo.getLatestKey(payload.groupId),
            isNull,
            reason: label,
          );
          expect(
            bridge.commandLog,
            isNot(contains('group:join')),
            reason: label,
          );
        }

        await expectRejected(
          label: 'missing-device',
          ownDeviceId: null,
          ownTransportPeerId: 'bob-device-1',
        );
        await expectRejected(
          label: 'wrong-device',
          ownDeviceId: 'bob-device-2',
          ownTransportPeerId: 'bob-device-1',
        );
        await expectRejected(
          label: 'wrong-transport',
          ownDeviceId: 'bob-device-1',
          ownTransportPeerId: 'bob-device-2',
        );
        await expectRejected(
          label: 'wrong-key-package',
          ownDeviceId: 'bob-device-1',
          ownTransportPeerId: 'bob-device-1',
          ownKeyPackageId: 'bob-kp-2',
        );
      },
    );

    test(
      'persists avatar metadata and downloaded path when invite carries it',
      () async {
        final groupConfigWithAvatar = {
          ..._testGroupConfig,
          'avatarBlobId': 'blob-1',
          'avatarMime': 'image/jpeg',
          'metadataUpdatedAt': '2026-04-05T12:25:00.000Z',
        };
        final payload = _makePayload(
          groupId: 'grp-avatar',
          groupConfig: groupConfigWithAvatar,
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV1Message(payload: payload),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
          downloadGroupAvatarFn:
              ({
                required dynamic bridge,
                required String groupId,
                required String blobId,
              }) async => 'media/group_avatars/$groupId.jpg',
        );

        expect(result, HandleGroupInviteResult.success);
        expect(groupId, 'grp-avatar');

        final group = await groupRepo.getGroup('grp-avatar');
        expect(group, isNotNull);
        expect(group!.avatarBlobId, 'blob-1');
        expect(group.avatarMime, 'image/jpeg');
        expect(group.avatarPath, 'media/group_avatars/grp-avatar.jpg');
        expect(
          group.lastMetadataEventAt,
          DateTime.parse('2026-04-05T12:25:00.000Z').toUtc(),
        );
      },
    );

    // --- Cycle 4.2 ---
    test(
      'calls group:join bridge command with groupId, groupConfig, groupKey, keyEpoch',
      () async {
        await handleIncomingGroupInvite(
          message: _makeV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(bridge.lastCommand, equals('group:join'));

        final sent =
            jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
        final payload = sent['payload'] as Map<String, dynamic>;
        expect(payload['groupId'], equals('grp-abc123'));
        expect(payload['groupConfig'], isA<Map<String, dynamic>>());
        expect(payload['groupKey'], equals('base64GroupKey=='));
        expect(payload['keyEpoch'], equals(1));
      },
    );

    // --- Cycle 4.3 ---
    test('returns duplicateGroup when group already exists', () async {
      // Pre-populate a group
      final existingGroup = GroupModel(
        id: 'grp-abc123',
        name: 'Original Name',
        type: GroupType.chat,
        topicName: '/mknoon/group/grp-abc123',
        createdAt: DateTime.utc(2026, 1, 1),
        createdBy: '12D3KooWOriginal',
        myRole: GroupRole.admin,
      );
      await groupRepo.saveGroup(existingGroup);
      // Genuine already-joined duplicate: self is an active member. (Contrast a
      // B3 retained-removed shell where self is absent and a re-add invite
      // re-joins instead — see the re-join test below.)
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'grp-abc123',
          peerId: '12D3KooWBob',
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final (result, _) = await handleIncomingGroupInvite(
        message: _makeV1Message(),
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownPeerId: '12D3KooWBob',
      );

      expect(result, equals(HandleGroupInviteResult.duplicateGroup));

      // Group is unchanged
      final group = await groupRepo.getGroup('grp-abc123');
      expect(group!.name, equals('Original Name'));
      expect(group.createdBy, equals('12D3KooWOriginal'));

      // Signature verification can run, but group:join must not.
      expect(bridge.commandLog, contains('payload.verify'));
      expect(bridge.commandLog, isNot(contains('group:join')));
    });

    // --- B3 re-join after removal ---
    test(
      're-joins a retained-removed group shell when self is no longer a member',
      () async {
        // B3 retains a removed member's group read-only (self absent, keyless)
        // instead of hard-deleting it. A fresh re-add invite must RE-JOIN
        // (re-materialize), not be rejected as a duplicate.
        final removedAt = DateTime.utc(2026, 7, 19, 10);
        final retainedShell = GroupModel(
          id: 'grp-abc123',
          name: 'Original Name',
          type: GroupType.chat,
          topicName: '/mknoon/group/grp-abc123',
          createdAt: DateTime.utc(2026, 1, 1),
          createdBy: '12D3KooWAlice',
          myRole: GroupRole.member,
          selfRemovedAt: removedAt,
          lastMembershipEventAt: removedAt,
          lastMembershipEventId: 'remove-grp-abc123',
        );
        await groupRepo.saveGroup(retainedShell);
        // Only the admin remains; self ('12D3KooWBob') is absent (removed).
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'grp-abc123',
            peerId: '12D3KooWAlice',
            username: 'Alice',
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        final issuedAt = DateTime.utc(2026, 7, 20, 12);
        final payload = _makePayload(
          membershipWatermark: DateTime.utc(2026, 7, 20, 11).toIso8601String(),
          membershipProofIssuedAt: issuedAt,
        );
        final (result, _) = await handleIncomingGroupInvite(
          message: _makeV1Message(payload: payload),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
          now: issuedAt,
        );

        // Re-joins (success), re-materializes the key, and joins the topic.
        expect(result, equals(HandleGroupInviteResult.success));
        expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
        expect(bridge.commandLog, contains('group:join'));
      },
    );

    test(
      'accepted re-invite atomically restores group self and key under a newer local watermark',
      () async {
        final removedAt = DateTime.utc(2026, 7, 20, 10);
        await groupRepo.saveGroup(
          GroupModel(
            id: 'grp-atomic-reentry',
            name: 'Retained history',
            type: GroupType.chat,
            topicName: '/mknoon/group/grp-atomic-reentry',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: '12D3KooWAlice',
            myRole: GroupRole.member,
            selfRemovedAt: removedAt,
            lastMembershipEventAt: removedAt,
            lastMembershipEventId: 'remove-atomic',
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'grp-atomic-reentry',
            peerId: '12D3KooWAlice',
            username: 'Alice',
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        final issuedAt = DateTime.utc(2026, 7, 20, 12);
        final payload = _makePayload(
          groupId: 'grp-atomic-reentry',
          membershipWatermark: removedAt.toIso8601String(),
          membershipProofIssuedAt: issuedAt,
        );
        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV1Message(payload: payload),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
          now: issuedAt,
        );

        expect(result, HandleGroupInviteResult.success);
        expect(groupId, 'grp-atomic-reentry');
        final accepted = await groupRepo.getGroup('grp-atomic-reentry');
        expect(accepted?.selfRemovedAt, isNull);
        expect(accepted?.lastMembershipEventAt, issuedAt);
        expect(accepted?.lastMembershipEventId, isNull);
        expect(
          await groupRepo.getMember('grp-atomic-reentry', '12D3KooWBob'),
          isNotNull,
        );
        expect(
          (await groupRepo.getMember(
            'grp-atomic-reentry',
            '12D3KooWBob',
          ))?.joinedAt,
          issuedAt,
        );
        expect(await groupRepo.getLatestKey('grp-atomic-reentry'), isNotNull);
        expect(
          bridge.commandLog.where((command) => command == 'group:join'),
          hasLength(1),
        );
      },
    );

    test(
      'accepted re-invite refuses same self joinedAt at retained removal authority',
      () async {
        const groupId = 'grp-stale-self-generation';
        const selfPeerId = '12D3KooWBob';
        final removedAt = DateTime.utc(2026, 7, 20, 10);
        final membershipAuthorityAt = removedAt.add(const Duration(hours: 1));
        final issuedAt = removedAt.add(const Duration(hours: 2));
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Retained history',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: '12D3KooWAlice',
            myRole: GroupRole.member,
            selfRemovedAt: removedAt,
            lastMembershipEventAt: membershipAuthorityAt,
            lastMembershipEventId: 'remove-stale-generation',
          ),
        );
        final staleConfig = <String, dynamic>{
          ..._testGroupConfig,
          'members': [
            for (final raw in _testGroupConfig['members']! as List<Object?>)
              <String, Object?>{
                ...Map<String, Object?>.from(raw! as Map),
                if ((raw as Map)['peerId'] == selfPeerId)
                  'joinedAt': membershipAuthorityAt.toIso8601String(),
              },
          ],
        };
        final payload = _makePayload(
          groupId: groupId,
          groupConfig: staleConfig,
          membershipWatermark: removedAt.toIso8601String(),
          membershipProofIssuedAt: issuedAt,
        );

        final (result, acceptedId) = await handleIncomingGroupInvite(
          message: _makeV1Message(payload: payload),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: selfPeerId,
          now: issuedAt,
        );

        expect(result, HandleGroupInviteResult.invalidPayload);
        expect(acceptedId, isNull);
        final preserved = await groupRepo.getGroup(groupId);
        expect(preserved?.selfRemovedAt, removedAt);
        expect(await groupRepo.getMember(groupId, selfPeerId), isNull);
        expect(await groupRepo.getLatestKey(groupId), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'accepted re-invite revalidates expiry after waiting for the membership phase',
      () async {
        const groupId = 'grp-expiry-after-lock';
        const selfPeerId = '12D3KooWBob';
        final removedAt = DateTime.utc(2026, 7, 20, 10);
        final repository = _ExpiryBarrierRepository();
        await repository.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Retained history',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: '12D3KooWAlice',
            myRole: GroupRole.member,
            selfRemovedAt: removedAt,
            lastMembershipEventAt: removedAt,
            lastMembershipEventId: 'remove-expiry',
          ),
        );
        final issuedAt = DateTime.utc(2026, 7, 20, 12);
        final expiresAt = issuedAt.add(const Duration(minutes: 5));
        final payload = _makePayload(
          groupId: groupId,
          membershipWatermark: removedAt.toIso8601String(),
          membershipProofIssuedAt: issuedAt,
          membershipProofExpiresAt: expiresAt,
          invitePolicyExpiresAt: expiresAt,
        );
        var clock = expiresAt.subtract(const Duration(seconds: 1));
        final entered = Completer<void>();
        final release = Completer<void>();
        final blockingPhase = runGroupMembershipMutationLocked<void>(
          groupId: groupId,
          action: () async {
            entered.complete();
            await release.future;
          },
        );
        await entered.future;

        final materialization = materializeAcceptedGroupInvitePayload(
          payload: payload,
          groupRepo: repository,
          bridge: bridge,
          ownPeerId: selfPeerId,
          validationNowUtc: () => clock,
        );
        await repository.preLockSelfCheckDone.future;
        clock = expiresAt.add(const Duration(microseconds: 1));
        release.complete();

        final (result, acceptedId) = await materialization;
        await blockingPhase;
        expect(result, HandleGroupInviteResult.invalidPayload);
        expect(acceptedId, isNull);
        expect((await repository.getGroup(groupId))?.selfRemovedAt, removedAt);
        expect(await repository.getLatestKey(groupId), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'deleted-shell re-entry enforces retained removal freshness floor',
      () async {
        const groupId = 'grp-deleted-floor';
        const selfPeerId = '12D3KooWBob';
        final removedAt = DateTime.utc(2026, 7, 20, 10);
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Deleted shell',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: '12D3KooWAlice',
            myRole: GroupRole.member,
            selfRemovedAt: removedAt,
            lastMembershipEventAt: removedAt,
            lastMembershipEventId: 'remove-floor',
          ),
        );
        final authority = await groupRepo.loadSelfRemovedShellAuthority(
          groupId: groupId,
          selfPeerId: selfPeerId,
        );
        await groupRepo.appendSelfRemovedShellFreshnessFloor(
          expected: authority,
        );
        await groupRepo.deleteGroup(groupId);

        for (final candidate in <DateTime>[
          removedAt.subtract(const Duration(seconds: 1)),
          removedAt,
        ]) {
          final payload = _makePayload(
            groupId: groupId,
            membershipWatermark: candidate.toIso8601String(),
            membershipProofIssuedAt: candidate,
          );
          final (result, acceptedId) = await handleIncomingGroupInvite(
            message: _makeV1Message(payload: payload),
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownPeerId: selfPeerId,
            now: candidate,
          );
          expect(result, HandleGroupInviteResult.invalidPayload);
          expect(acceptedId, isNull);
          expect(await groupRepo.getGroup(groupId), isNull);
        }
        expect(bridge.commandLog, isNot(contains('group:join')));

        final laterIssuedAt = removedAt.add(const Duration(hours: 1));
        final newer = _makePayload(
          groupId: groupId,
          membershipWatermark: removedAt.toIso8601String(),
          membershipProofIssuedAt: laterIssuedAt,
        );
        final (result, acceptedId) = await handleIncomingGroupInvite(
          message: _makeV1Message(payload: newer),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: selfPeerId,
          now: laterIssuedAt,
        );
        expect(result, HandleGroupInviteResult.success);
        expect(acceptedId, groupId);
        expect(
          (await groupRepo.getGroup(groupId))?.lastMembershipEventAt,
          laterIssuedAt,
        );
      },
    );

    test(
      'accepted re-invite and removed-shell delete serialize so later authority transition wins',
      () async {
        const selfPeerId = '12D3KooWBob';

        Future<void> seedRemovedShell(
          InMemoryGroupRepository repository, {
          required String groupId,
          required DateTime removedAt,
        }) async {
          await repository.saveGroup(
            GroupModel(
              id: groupId,
              name: 'Retained shell',
              type: GroupType.chat,
              topicName: '/mknoon/group/$groupId',
              createdAt: DateTime.utc(2026, 1, 1),
              createdBy: '12D3KooWAlice',
              myRole: GroupRole.member,
              selfRemovedAt: removedAt,
              lastMembershipEventAt: removedAt,
              lastMembershipEventId: 'remove-$groupId',
            ),
          );
          await repository.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: '12D3KooWAlice',
              username: 'Alice',
              role: MemberRole.admin,
              joinedAt: DateTime.utc(2026, 1, 1),
            ),
          );
        }

        DeleteSelfRemovedGroupShellUseCase cleanup(
          SelfRemovedGroupShellRepository repository,
        ) => DeleteSelfRemovedGroupShellUseCase(
          repository: repository,
          prepareMedia:
              ({
                required String groupId,
                required String messageId,
                required String operationId,
              }) async => const GroupMediaDeletePrepareResult(
                GroupMediaDeletePrepareOutcome.parentMissing,
              ),
          runMediaReconciler: () async {},
          snapshotAvatarPath: (_) async => null,
          deleteAvatar: (_) async {},
          operationIdFactory: () => 'tc11-cleanup-operation',
        );

        // Delete owns the phase first. Acceptance sees only the durable
        // absent+floor state after purge, then commits its newer signed tuple.
        const deleteFirstGroupId = 'grp-race-delete-first';
        final deleteFirstRemovedAt = DateTime.utc(2026, 7, 20, 10);
        final deleteFirstAcceptedAt = deleteFirstRemovedAt.add(
          const Duration(minutes: 1),
        );
        final deleteFirstRepository = _GateableShellDeleteRepository();
        groupRepo = deleteFirstRepository;
        await seedRemovedShell(
          deleteFirstRepository,
          groupId: deleteFirstGroupId,
          removedAt: deleteFirstRemovedAt,
        );
        final deleteFirst = cleanup(
          deleteFirstRepository,
        ).call(groupId: deleteFirstGroupId, selfPeerId: selfPeerId);
        await deleteFirstRepository.deleteEntered.future.timeout(
          const Duration(seconds: 2),
        );

        bridge = FakeBridge();
        final acceptAfterDelete = handleIncomingGroupInvite(
          message: _makeV1Message(
            payload: _makePayload(
              groupId: deleteFirstGroupId,
              membershipWatermark: deleteFirstRemovedAt.toIso8601String(),
              membershipProofIssuedAt: deleteFirstAcceptedAt,
            ),
          ),
          groupRepo: deleteFirstRepository,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: selfPeerId,
          now: deleteFirstAcceptedAt,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bridge.commandLog, isNot(contains('group:join')));

        deleteFirstRepository.releaseDelete();
        expect(await deleteFirst, DeleteSelfRemovedGroupShellResult.deleted);
        final deleteFirstAccepted = await acceptAfterDelete;
        expect(deleteFirstAccepted.$1, HandleGroupInviteResult.success);
        expect(deleteFirstAccepted.$2, deleteFirstGroupId);
        expect(
          (await deleteFirstRepository.getGroup(
            deleteFirstGroupId,
          ))?.lastMembershipEventAt,
          deleteFirstAcceptedAt,
        );
        expect(
          await deleteFirstRepository.getMember(deleteFirstGroupId, selfPeerId),
          isNotNull,
        );
        expect(
          await deleteFirstRepository.getLatestKey(deleteFirstGroupId),
          isNotNull,
        );

        // Acceptance owns the phase first and holds it through native join.
        // A queued cleanup re-reads the now-active membership and refuses its
        // stale marked-shell delete authority.
        const acceptFirstGroupId = 'grp-race-accept-first';
        final acceptFirstRemovedAt = DateTime.utc(2026, 7, 20, 11);
        final acceptFirstAcceptedAt = acceptFirstRemovedAt.add(
          const Duration(minutes: 1),
        );
        final acceptFirstRepository = InMemoryGroupRepository();
        groupRepo = acceptFirstRepository;
        await seedRemovedShell(
          acceptFirstRepository,
          groupId: acceptFirstGroupId,
          removedAt: acceptFirstRemovedAt,
        );
        final gateableJoinBridge = _GateableJoinBridge();
        bridge = gateableJoinBridge;
        final acceptFirst = handleIncomingGroupInvite(
          message: _makeV1Message(
            payload: _makePayload(
              groupId: acceptFirstGroupId,
              membershipWatermark: acceptFirstRemovedAt.toIso8601String(),
              membershipProofIssuedAt: acceptFirstAcceptedAt,
            ),
          ),
          groupRepo: acceptFirstRepository,
          contactRepo: contactRepo,
          bridge: gateableJoinBridge,
          ownPeerId: selfPeerId,
          now: acceptFirstAcceptedAt,
        );
        await gateableJoinBridge.joinStarted.future.timeout(
          const Duration(seconds: 2),
        );

        var deleteAfterAcceptCompleted = false;
        final deleteAfterAccept = cleanup(acceptFirstRepository)
            .call(groupId: acceptFirstGroupId, selfPeerId: selfPeerId)
            .whenComplete(() => deleteAfterAcceptCompleted = true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(deleteAfterAcceptCompleted, isFalse);

        gateableJoinBridge.releaseJoin();
        final acceptFirstResult = await acceptFirst;
        expect(acceptFirstResult.$1, HandleGroupInviteResult.success);
        expect(
          await deleteAfterAccept,
          DeleteSelfRemovedGroupShellResult.refusedStateChanged,
        );
        final acceptedGroup = await acceptFirstRepository.getGroup(
          acceptFirstGroupId,
        );
        expect(acceptedGroup?.selfRemovedAt, isNull);
        expect(acceptedGroup?.lastMembershipEventAt, acceptFirstAcceptedAt);
        expect(
          await acceptFirstRepository.getMember(acceptFirstGroupId, selfPeerId),
          isNotNull,
        );
        expect(
          await acceptFirstRepository.getLatestKey(acceptFirstGroupId),
          isNotNull,
        );
      },
    );

    // --- Cycle 4.4 ---
    test('returns invalidPayload for missing groupId', () async {
      final malformed = jsonEncode({
        'type': 'group_invite',
        'version': '1',
        'payload': {
          'id': 'invite-1',
          // 'groupId' missing
          'groupKey': 'key',
          'keyEpoch': 1,
          'groupConfig': _testGroupConfig,
          'senderPeerId': '12D3KooWAlice',
          'senderUsername': 'Alice',
          'timestamp': '2026-01-01T00:00:00Z',
        },
      });

      final msg = ChatMessage(
        from: '12D3KooWAlice',
        to: 'myPeerId',
        content: malformed,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      );

      final (result, _) = await handleIncomingGroupInvite(
        message: msg,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      expect(result, equals(HandleGroupInviteResult.invalidPayload));
      expect(groupRepo.groupCount, equals(0));
    });

    // --- Cycle 4.5 ---
    test('returns invalidPayload for missing groupKey', () async {
      final malformed = jsonEncode({
        'type': 'group_invite',
        'version': '1',
        'payload': {
          'id': 'invite-1',
          'groupId': 'grp-1',
          // 'groupKey' missing
          'keyEpoch': 1,
          'groupConfig': _testGroupConfig,
          'senderPeerId': '12D3KooWAlice',
          'senderUsername': 'Alice',
          'timestamp': '2026-01-01T00:00:00Z',
        },
      });

      final msg = ChatMessage(
        from: '12D3KooWAlice',
        to: 'myPeerId',
        content: malformed,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      );

      final (result, _) = await handleIncomingGroupInvite(
        message: msg,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      expect(result, equals(HandleGroupInviteResult.invalidPayload));
    });

    test(
      'returns invalidPayload for empty groupKey before state or join',
      () async {
        final payload = _makePayload(overrideGroupKey: '');

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV1Message(payload: payload),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, equals(HandleGroupInviteResult.invalidPayload));
        expect(groupId, isNull);
        expect(groupRepo.groupCount, equals(0));
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    // --- Cycle 4.6 ---
    test('returns invalidPayload for missing groupConfig', () async {
      final malformed = jsonEncode({
        'type': 'group_invite',
        'version': '1',
        'payload': {
          'id': 'invite-1',
          'groupId': 'grp-1',
          'groupKey': 'key',
          'keyEpoch': 1,
          // 'groupConfig' missing
          'senderPeerId': '12D3KooWAlice',
          'senderUsername': 'Alice',
          'timestamp': '2026-01-01T00:00:00Z',
        },
      });

      final msg = ChatMessage(
        from: '12D3KooWAlice',
        to: 'myPeerId',
        content: malformed,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      );

      final (result, _) = await handleIncomingGroupInvite(
        message: msg,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      expect(result, equals(HandleGroupInviteResult.invalidPayload));
    });

    // --- Cycle 4.7 ---
    test('returns unknownSender for invite from non-contact', () async {
      // Clear contacts — no contacts at all
      contactRepo.seed([]);

      final (result, _) = await handleIncomingGroupInvite(
        message: _makeV1Message(),
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownPeerId: '12D3KooWBob',
      );

      expect(result, equals(HandleGroupInviteResult.unknownSender));
      expect(groupRepo.groupCount, equals(0));
    });

    // --- Cycle 4.8 ---
    test(
      'joining user gets myRole=member in the persisted GroupModel',
      () async {
        await handleIncomingGroupInvite(
          message: _makeV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        final group = await groupRepo.getGroup('grp-abc123');
        expect(group!.myRole, equals(GroupRole.member));
      },
    );

    test(
      'accepts bound invite when recipient peer matches local identity',
      () async {
        final payload = _makePayload(recipientPeerId: '12D3KooWBob');

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV1Message(payload: payload),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, equals(HandleGroupInviteResult.success));
        expect(groupId, equals('grp-abc123'));
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNotNull);
      },
    );

    test(
      'IJ009 rejects signed invite when local peer identity is unavailable before state or join',
      () async {
        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeSignedV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );

        expect(result, equals(HandleGroupInviteResult.invalidPayload));
        expect(groupId, isNull);
        expect(groupRepo.groupCount, equals(0));
        expect(await groupRepo.getMembers('grp-abc123'), isEmpty);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    // --- Cycle 4.9 ---
    test('returns bridgeError when group:join times out', () async {
      final timeoutBridge = _TimeoutJoinBridge();

      final (result, _) = await handleIncomingGroupInvite(
        message: _makeV1Message(),
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: timeoutBridge,
        ownPeerId: '12D3KooWBob',
      );

      // Group IS still persisted to local DB
      final group = await groupRepo.getGroup('grp-abc123');
      expect(group, isNotNull);
      expect(group!.name, equals('Book Club'));

      expect(result, equals(HandleGroupInviteResult.bridgeError));
    });

    test(
      'IJ014 repairable join-material failure rolls back direct invite state',
      () async {
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'STALE_JOIN_MATERIAL',
          'errorMessage': 'stale welcome key material',
        };

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeSignedV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, equals(HandleGroupInviteResult.invalidPayload));
        expect(groupId, isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getMembers('grp-abc123'), isEmpty);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, contains('group:join'));
      },
    );

    // --- Slice E: bound the half-materialized state ---
    test(
      'E: a non-repairable (transient) bridge join failure keeps the group and '
      'enrolls it in the bounded rejoin retrier',
      () async {
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'TOPIC_SUBSCRIBE_FAILED',
          'errorMessage': 'could not subscribe to topic',
        };

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeSignedV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, equals(HandleGroupInviteResult.bridgeError));
        expect(groupId, equals('grp-abc123'));
        // Group stays materialized (key persisted) — NOT rolled back.
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        // ...and is enrolled in the bounded rejoin retrier.
        final states = await groupRepo.loadGroupRejoinStates();
        expect(states['grp-abc123'], isNotNull);
        expect(states['grp-abc123']!.attemptCount, 1);
      },
    );

    test(
      'E: a group:join timeout keeps the group and enrolls it in the rejoin retrier',
      () async {
        final timeoutBridge = _TimeoutJoinBridge();

        final (result, _) = await handleIncomingGroupInvite(
          message: _makeV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: timeoutBridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, equals(HandleGroupInviteResult.bridgeError));
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        final states = await groupRepo.loadGroupRejoinStates();
        expect(states['grp-abc123'], isNotNull);
      },
    );

    test(
      'E: a generic join exception keeps the group and enrolls it in the rejoin retrier',
      () async {
        final genericBridge = _GenericFailJoinBridge();

        final (result, _) = await handleIncomingGroupInvite(
          message: _makeV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: genericBridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, equals(HandleGroupInviteResult.bridgeError));
        expect(await groupRepo.getGroup('grp-abc123'), isNotNull);
        final states = await groupRepo.loadGroupRejoinStates();
        expect(states['grp-abc123'], isNotNull);
      },
    );

    test(
      'E regression guard: a repairable join-material failure rolls back AND '
      'does NOT enroll a rejoin row',
      () async {
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'STALE_JOIN_MATERIAL',
          'errorMessage': 'stale welcome key material',
        };

        final (result, _) = await handleIncomingGroupInvite(
          message: _makeSignedV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, equals(HandleGroupInviteResult.invalidPayload));
        // Fully rolled back — the enrollment path must not resurrect it.
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        final states = await groupRepo.loadGroupRejoinStates();
        expect(states['grp-abc123'], isNull);
      },
    );

    // --- Cycle 4.10 ---
    test('decrypts v2 invite envelope and processes inner payload', () async {
      final cryptoBridge = PassthroughCryptoBridge();

      final (result, _) = await handleIncomingGroupInvite(
        message: _makeV2Message(),
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: cryptoBridge,
        ownMlKemSecretKey: 'mySecretKey',
        ownPeerId: '12D3KooWBob',
      );

      expect(result, equals(HandleGroupInviteResult.success));

      // Verify bridge was called at least twice (decrypt + join)
      expect(cryptoBridge.sendCallCount, greaterThanOrEqualTo(2));

      // Inner payload was parsed and group persisted
      final group = await groupRepo.getGroup('grp-abc123');
      expect(group, isNotNull);
      expect(group!.name, equals('Book Club'));
    });

    // --- Cycle 4.11 ---
    test(
      'returns decryptionFailed when bridge decrypt returns ok=false',
      () async {
        final failBridge = _FailDecryptBridge();

        final (result, _) = await handleIncomingGroupInvite(
          message: _makeV2Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: failBridge,
          ownMlKemSecretKey: 'mySecretKey',
        );

        expect(result, equals(HandleGroupInviteResult.decryptionFailed));
        expect(groupRepo.groupCount, equals(0));
      },
    );

    // --- P1 additions ---

    test(
      'returns decryptionFailed when mlKemSecretKey is null and envelope is v2',
      () async {
        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV2Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: null, // <-- null secret key
        );

        expect(result, equals(HandleGroupInviteResult.decryptionFailed));
        expect(groupId, isNull);
        // Nothing should be persisted.
        expect(groupRepo.groupCount, equals(0));
      },
    );

    test('persists correct myRole as member (not admin)', () async {
      final (result, groupId) = await handleIncomingGroupInvite(
        message: _makeV1Message(),
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownPeerId: '12D3KooWBob',
      );

      expect(result, equals(HandleGroupInviteResult.success));
      expect(groupId, equals('grp-abc123'));

      final group = await groupRepo.getGroup('grp-abc123');
      expect(group, isNotNull);
      // The joining user should always be stored as a member, not admin.
      expect(group!.myRole, equals(GroupRole.member));
      // Double-check it is not admin.
      expect(group.myRole, isNot(equals(GroupRole.admin)));
    });

    test('persists all members from groupConfig, not just sender', () async {
      // Build a config with 3 members (Alice, Bob, and a new Carol).
      const threePersonConfig = {
        'name': 'Trio Club',
        'groupType': 'chat',
        'description': 'Three person group',
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
          },
          {
            'peerId': '12D3KooWCarol',
            'username': 'Carol',
            'role': 'reader',
            'publicKey': 'carolPubKey64',
          },
        ],
        'createdBy': '12D3KooWAlice',
        'createdAt': '2026-03-02T00:00:00.000Z',
      };

      final payload = _makePayload(
        groupId: 'grp-trio',
        overrideGroupKey: 'trioKey==',
        groupConfig: threePersonConfig,
      );

      final msg = _makeV1Message(payload: payload);

      final (result, groupId) = await handleIncomingGroupInvite(
        message: msg,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownPeerId: '12D3KooWBob',
      );

      expect(result, equals(HandleGroupInviteResult.success));
      expect(groupId, equals('grp-trio'));

      final members = await groupRepo.getMembers('grp-trio');
      expect(members, hasLength(3));

      final peerIds = members.map((m) => m.peerId).toSet();
      expect(peerIds, contains('12D3KooWAlice'));
      expect(peerIds, contains('12D3KooWBob'));
      expect(peerIds, contains('12D3KooWCarol'));
    });

    // --- Security: sender binding ---
    test(
      'rejects v1 invite where transport sender != payload sender',
      () async {
        // Payload says sender is Alice, but transport says attacker
        final payload = _makePayload(); // senderPeerId = '12D3KooWAlice'
        final msg = ChatMessage(
          from: 'peer-attacker-X', // transport sender differs
          to: 'myPeerId',
          content: payload.toJson(),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: msg,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );

        expect(result, equals(HandleGroupInviteResult.invalidPayload));
        expect(groupId, isNull);
        expect(groupRepo.groupCount, equals(0));
      },
    );

    test(
      'P269 accepts signed config-bound sender transport distinct from account identity',
      () async {
        const senderAccountPeerId = '12D3KooWAlice';
        const senderTransportPeerId = 'alice-device-1';
        final payload = _makePayload(
          groupId: 'grp-p269-split-identity',
          groupConfig: _deviceBoundGroupConfig,
          recipientDeviceId: 'bob-device-1',
          recipientTransportPeerId: 'bob-device-1',
          recipientMlKemPublicKey: 'bobMlKem64',
          recipientKeyPackageId: 'bob-kp-1',
          recipientKeyPackagePublicMaterial: 'bob-kpm-1',
          senderDeviceId: senderTransportPeerId,
          senderTransportPeerId: senderTransportPeerId,
          senderDeviceSigningPublicKey: 'alicePubKey64',
          senderKeyPackageId: 'alice-kp-1',
          inviterMemberSnapshot: {
            'peerId': senderAccountPeerId,
            'username': 'Alice',
            'role': 'admin',
            'publicKey': 'alicePubKey64',
            'mlKemPublicKey': 'aliceMlKem64',
            'devices': [
              {
                'deviceId': senderTransportPeerId,
                'transportPeerId': senderTransportPeerId,
                'deviceSigningPublicKey': 'alicePubKey64',
                'mlKemPublicKey': 'aliceMlKem64',
                'keyPackageId': 'alice-kp-1',
                'keyPackagePublicMaterial': 'alice-kpm-1',
                'status': 'active',
              },
            ],
          },
        );
        final message = ChatMessage(
          from: senderTransportPeerId,
          to: 'bob-device-1',
          content: _makeSignedV1Message(payload: payload).content,
          timestamp: payload.timestamp,
          isIncoming: true,
        );

        expect(payload.senderPeerId, senderAccountPeerId);
        expect(payload.senderTransportPeerId, senderTransportPeerId);
        expect(payload.senderPeerId, isNot(payload.senderTransportPeerId));

        final attackerRepo = InMemoryGroupRepository();
        final (
          attackerResult,
          attackerGroupId,
        ) = await handleIncomingGroupInvite(
          message: ChatMessage(
            from: 'peer-attacker-X',
            to: 'bob-device-1',
            content: message.content,
            timestamp: payload.timestamp,
            isIncoming: true,
          ),
          groupRepo: attackerRepo,
          contactRepo: contactRepo,
          bridge: FakeBridge(),
          ownPeerId: '12D3KooWBob',
          ownDeviceId: 'bob-device-1',
          ownTransportPeerId: 'bob-device-1',
          ownMlKemPublicKey: 'bobMlKem64',
          ownKeyPackageId: 'bob-kp-1',
          ownKeyPackagePublicMaterial: 'bob-kpm-1',
        );
        expect(attackerResult, HandleGroupInviteResult.invalidPayload);
        expect(attackerGroupId, isNull);
        expect(attackerRepo.groupCount, 0);

        final accountTransportRepo = InMemoryGroupRepository();
        final accountTransportBridge = FakeBridge();
        final (
          accountTransportResult,
          accountTransportGroupId,
        ) = await handleIncomingGroupInvite(
          message: ChatMessage(
            from: senderAccountPeerId,
            to: 'bob-device-1',
            content: message.content,
            timestamp: payload.timestamp,
            isIncoming: true,
          ),
          groupRepo: accountTransportRepo,
          contactRepo: contactRepo,
          bridge: accountTransportBridge,
          ownPeerId: '12D3KooWBob',
          ownDeviceId: 'bob-device-1',
          ownTransportPeerId: 'bob-device-1',
          ownMlKemPublicKey: 'bobMlKem64',
          ownKeyPackageId: 'bob-kp-1',
          ownKeyPackagePublicMaterial: 'bob-kpm-1',
        );
        expect(accountTransportResult, HandleGroupInviteResult.invalidPayload);
        expect(accountTransportGroupId, isNull);
        expect(accountTransportRepo.groupCount, 0);
        expect(
          await accountTransportRepo.getLatestKey('grp-p269-split-identity'),
          isNull,
        );
        expect(
          accountTransportBridge.commandLog,
          isNot(contains('group:join')),
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: message,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
          ownDeviceId: 'bob-device-1',
          ownTransportPeerId: 'bob-device-1',
          ownMlKemPublicKey: 'bobMlKem64',
          ownKeyPackageId: 'bob-kp-1',
          ownKeyPackagePublicMaterial: 'bob-kpm-1',
        );

        expect(result, HandleGroupInviteResult.success);
        expect(groupId, 'grp-p269-split-identity');
        final senderMember = await groupRepo.getMember(
          'grp-p269-split-identity',
          senderAccountPeerId,
        );
        expect(senderMember, isNotNull);
        expect(
          senderMember!.devices.single.transportPeerId,
          senderTransportPeerId,
        );
      },
    );

    test(
      'P269 rejects partial signed sender device tuple before side effects',
      () async {
        const senderTransportPeerId = 'alice-device-1';
        final payload = _makePayload(
          groupId: 'grp-p269-partial-sender',
          groupConfig: _deviceBoundGroupConfig,
          recipientDeviceId: 'bob-device-1',
          recipientTransportPeerId: 'bob-device-1',
          recipientMlKemPublicKey: 'bobMlKem64',
          recipientKeyPackageId: 'bob-kp-1',
          recipientKeyPackagePublicMaterial: 'bob-kpm-1',
          senderDeviceId: senderTransportPeerId,
          senderTransportPeerId: senderTransportPeerId,
          senderKeyPackageId: 'alice-kp-1',
        );
        final partialTupleMessage = ChatMessage(
          from: senderTransportPeerId,
          to: 'bob-device-1',
          content: _makeSignedV1Message(payload: payload).content,
          timestamp: payload.timestamp,
          isIncoming: true,
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: partialTupleMessage,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
          ownDeviceId: 'bob-device-1',
          ownTransportPeerId: 'bob-device-1',
          ownMlKemPublicKey: 'bobMlKem64',
          ownKeyPackageId: 'bob-kp-1',
          ownKeyPackagePublicMaterial: 'bob-kpm-1',
        );

        expect(result, HandleGroupInviteResult.invalidPayload);
        expect(groupId, isNull);
        expect(groupRepo.groupCount, 0);
        expect(await groupRepo.getLatestKey('grp-p269-partial-sender'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'rejects v2 encrypted invite where transport sender != payload sender',
      () async {
        final cryptoBridge = PassthroughCryptoBridge();
        final payload = _makePayload(); // senderPeerId = '12D3KooWAlice'
        final innerJson = payload.toInnerJson();
        final envelope = GroupInvitePayload.buildEncryptedEnvelope(
          senderPeerId: payload.senderPeerId,
          kem: 'fake-kem',
          ciphertext: innerJson,
          nonce: 'fake-nonce',
        );

        final msg = ChatMessage(
          from: 'peer-attacker-X', // transport sender differs
          to: 'myPeerId',
          content: envelope,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: msg,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: cryptoBridge,
          ownMlKemSecretKey: 'mySecretKey',
        );

        expect(result, equals(HandleGroupInviteResult.invalidPayload));
        expect(groupId, isNull);
        expect(groupRepo.groupCount, equals(0));
      },
    );

    test('rejects v1 invite bound to a different recipient peer', () async {
      final payload = _makePayload(recipientPeerId: 'otherPeerId');

      final (result, groupId) = await handleIncomingGroupInvite(
        message: _makeV1Message(payload: payload),
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownPeerId: 'myPeerId',
      );

      expect(result, equals(HandleGroupInviteResult.invalidPayload));
      expect(groupId, isNull);
      expect(groupRepo.groupCount, equals(0));
      expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
      expect(bridge.lastCommand, isNull);
    });

    test(
      'rejects v2 encrypted invite bound to a different recipient peer',
      () async {
        final cryptoBridge = PassthroughCryptoBridge();
        final payload = _makePayload(recipientPeerId: 'otherPeerId');

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV2Message(payload: payload, bridge: cryptoBridge),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: cryptoBridge,
          ownMlKemSecretKey: 'mySecretKey',
          ownPeerId: 'myPeerId',
        );

        expect(result, equals(HandleGroupInviteResult.invalidPayload));
        expect(groupId, isNull);
        expect(groupRepo.groupCount, equals(0));
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(cryptoBridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'IJ001 rejects invite missing first-class policy before group state or join',
      () async {
        final payload = _makePayload();
        final envelope = jsonDecode(payload.toJson()) as Map<String, dynamic>;
        (envelope['payload'] as Map<String, dynamic>).remove('invitePolicy');
        final msg = ChatMessage(
          from: payload.senderPeerId,
          to: payload.recipientPeerId!,
          content: jsonEncode(envelope),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: msg,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: payload.recipientPeerId,
        );

        expect(result, equals(HandleGroupInviteResult.invalidPayload));
        expect(groupId, isNull);
        expect(groupRepo.groupCount, equals(0));
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'IJ001 rejects contradictory policy before group state or join',
      () async {
        final payload = _makePayload();
        final envelope = jsonDecode(payload.toJson()) as Map<String, dynamic>;
        final payloadMap = envelope['payload'] as Map<String, dynamic>;
        (((payloadMap['invitePolicy']
                    as Map<String, dynamic>)['joinMaterialRef'])
                as Map<String, dynamic>)['keyEpoch'] =
            2;
        final msg = ChatMessage(
          from: payload.senderPeerId,
          to: payload.recipientPeerId!,
          content: jsonEncode(envelope),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: msg,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: payload.recipientPeerId,
        );

        expect(result, equals(HandleGroupInviteResult.invalidPayload));
        expect(groupId, isNull);
        expect(groupRepo.groupCount, equals(0));
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'handles bridge group:join timeout without losing persisted data',
      () async {
        final timeoutBridge = _TimeoutJoinBridge();

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: timeoutBridge,
          ownPeerId: '12D3KooWBob',
        );

        // Result should indicate bridge error.
        expect(result, equals(HandleGroupInviteResult.bridgeError));
        // groupId should still be returned (group was persisted).
        expect(groupId, equals('grp-abc123'));

        // Group should be fully persisted in the repo.
        final group = await groupRepo.getGroup('grp-abc123');
        expect(group, isNotNull);
        expect(group!.name, equals('Book Club'));
        expect(group.myRole, equals(GroupRole.member));

        // Members should be persisted.
        final members = await groupRepo.getMembers('grp-abc123');
        expect(members, hasLength(2));

        // Key should be persisted.
        final key = await groupRepo.getLatestKey('grp-abc123');
        expect(key, isNotNull);
        expect(key!.encryptedKey, equals('base64GroupKey=='));
        expect(key.keyGeneration, equals(1));
      },
    );

    test(
      'IJ002 rejects invalid invite signature before group state or join',
      () async {
        bridge.responses['payload.verify'] = {'ok': true, 'valid': false};

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeSignedV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, HandleGroupInviteResult.invalidPayload);
        expect(groupId, isNull);
        expect(bridge.commandLog, contains('payload.verify'));
        expect(groupRepo.groupCount, 0);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'IJ002 rejects tampered signed invite fields before group state or join',
      () async {
        final payload = _makePayload();
        final signed = _signedPayloadMap(payload);
        signed['groupKey'] = 'tampered-group-key';
        final message = ChatMessage(
          from: payload.senderPeerId,
          to: payload.recipientPeerId!,
          content: jsonEncode({
            'type': 'group_invite',
            'version': '1',
            'payload': signed,
          }),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: message,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, HandleGroupInviteResult.invalidPayload);
        expect(groupId, isNull);
        expect(groupRepo.groupCount, 0);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'IJ002 rejects signed non-admin or removed inviters before state or join',
      () async {
        Future<void> expectRejected(
          String label,
          Map<String, dynamic> groupConfig,
        ) async {
          groupRepo = InMemoryGroupRepository();
          bridge = FakeBridge();
          final payload = _makePayload(groupConfig: groupConfig);

          final (result, groupId) = await handleIncomingGroupInvite(
            message: _makeSignedV1Message(payload: payload),
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownPeerId: '12D3KooWBob',
          );

          expect(result, HandleGroupInviteResult.invalidPayload, reason: label);
          expect(groupId, isNull, reason: label);
          expect(groupRepo.groupCount, 0, reason: label);
          expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
          expect(bridge.commandLog, isNot(contains('group:join')));
        }

        await expectRejected('non-admin without invite override', {
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
        });

        await expectRejected('explicit inviteMembers false', {
          ..._testGroupConfig,
          'members': [
            {
              'peerId': '12D3KooWAlice',
              'username': 'Alice',
              'role': 'admin',
              'permissions': {'inviteMembers': false},
              'publicKey': 'alicePubKey64',
              'mlKemPublicKey': 'aliceMlKem64',
            },
            (_testGroupConfig['members'] as List<dynamic>)[1],
          ],
        });

        await expectRejected('removed inviter missing from snapshot', {
          ..._testGroupConfig,
          'members': [(_testGroupConfig['members'] as List<dynamic>)[1]],
        });
      },
    );

    test(
      'PREREQ-INVITER-FRESHNESS rejects stale self-consistent invite before group state or join',
      () async {
        final issuedAt = DateTime.utc(2026, 3, 2, 12);
        final payload = _makePayload(
          membershipProofIssuedAt: issuedAt,
          membershipProofExpiresAt: issuedAt.add(
            groupInviteMembershipFreshnessTtl,
          ),
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeSignedV1Message(payload: payload),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
          now: issuedAt.add(groupInviteMembershipFreshnessTtl),
        );

        expect(result, HandleGroupInviteResult.invalidPayload);
        expect(groupId, isNull);
        expect(groupRepo.groupCount, 0);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );
  });

  // G-A (Finding 03 Slice 2): when an accepted invite materializes a config that
  // first lands a member's usable ML-KEM key, the deferred-distribution drain
  // trigger must fire for that member — but never for a keyless member (whose
  // drain would only burn a deferred-distribution attempt against no key).
  group('G-A member-key-arrival deferred-distribution drain trigger', () {
    late List<({String groupId, String peerId})> drainCalls;

    setUp(() {
      drainCalls = <({String groupId, String peerId})>[];
      setDeferredDistributionDrainSink(({
        required String groupId,
        required String peerId,
      }) async {
        drainCalls.add((groupId: groupId, peerId: peerId));
      });
    });

    tearDown(() => setDeferredDistributionDrainSink(null));

    test(
      'fires the drain for a key-carrying member, not for a keyless one',
      () async {
        final configWithKeylessCarol = {
          ..._testGroupConfig,
          'members': [
            ...(_testGroupConfig['members'] as List),
            {
              'peerId': '12D3KooWCarol',
              'username': 'Carol',
              'role': 'writer',
              'publicKey': 'carolPubKey64',
            },
          ],
        };
        final payload = _makePayload(
          groupId: 'grp-drain-trigger',
          groupConfig: configWithKeylessCarol,
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV1Message(payload: payload),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: '12D3KooWBob',
        );

        expect(result, HandleGroupInviteResult.success);
        expect(groupId, 'grp-drain-trigger');

        final drainedPeers = drainCalls.map((call) => call.peerId).toSet();
        expect(drainedPeers, contains('12D3KooWAlice'));
        expect(drainedPeers, isNot(contains('12D3KooWCarol')));
        expect(
          drainCalls.every((call) => call.groupId == 'grp-drain-trigger'),
          isTrue,
        );
      },
    );
  });
}
