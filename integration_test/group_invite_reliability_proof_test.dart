/// Real-bridge device proofs for Review-08 invite/join reliability (slices
/// C revoke, F decline-ack, D on-join metadata resync).
///
/// Every host test for these slices used FakeBridge (fake sign/verify, fake
/// encrypt/decrypt). These proofs exercise the SAME wire payloads + use-case
/// code against the REAL Go ML-KEM + ed25519 bridge on-device, end-to-end:
///   - F: a decline-ack is real-ML-KEM-encrypted to the inviter and decrypts +
///        marks declined (spoof guard holds).
///   - C: a revocation carrying the persisted invite_id deletes the live
///        pending invite after a real decrypt (HOLE-4).
///   - D: an admin-signed config:response verifies with REAL ed25519
///        (the formerly-dead callVerifyPayload gate) and applies strictly-newer
///        metadata; a forged signature is rejected.
@Tags(['device'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/apply_on_join_group_config_resync.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_decline_ack.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_decline_ack_use_case.dart';
import 'package:flutter_app/features/groups/application/revoke_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../test/core/services/fake_p2p_service.dart';
import '../test/features/contacts/domain/repositories/fake_contact_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
import '../test/shared/fakes/in_memory_pending_group_invite_repository.dart';
import '_support/canonical_runtime_device_test_lease.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runtimeLease = CanonicalRuntimeDeviceTestLease(
    binding: 'group-invite-reliability-device-test',
  );
  setUpAll(runtimeLease.acquire);
  tearDownAll(runtimeLease.release);

  group('real-crypto invite/join reliability (Review-08)', () {
    late GoBridgeClient bridge;

    setUp(() async {
      bridge = GoBridgeClient();
      await bridge.initialize();
    });

    tearDown(() {
      bridge.dispose();
    });

    testWidgets(
      'F: a decline-ack real-ML-KEM-encrypts to the inviter, decrypts, and marks declined; a spoofed ack is rejected',
      (tester) async {
        final alice = await _generateIdentity(bridge, 'Alice'); // inviter
        final bob = await _generateIdentity(bridge, 'Bob'); // decliner

        final p2p = FakeP2PService(
          initialState: const NodeState(isStarted: true),
          sendMessageResult: true,
        );

        // Bob declines → sign (Bob ed25519) + encrypt (Alice ML-KEM pub).
        final sendResult = await sendGroupInviteDeclineAck(
          p2pService: p2p,
          bridge: bridge,
          inviteId: 'invite-f1',
          groupId: 'grp-f1',
          inviterPeerId: alice.peerId,
          inviterMlKemPublicKey: alice.mlKemPublicKey,
          declinerPeerId: bob.peerId,
          declinerPrivateKey: bob.privateKey,
        );
        expect(sendResult, SendGroupInviteDeclineAckResult.success);

        final envelope = p2p.lastSendMessageContent!;
        expect(p2p.lastSendMessagePeerId, alice.peerId);

        // Alice receives → decrypt (Alice ML-KEM secret) + spoof guard.
        final deliveryRepo = _SpyDeliveryRepo();
        final honest = await handleIncomingGroupInviteDeclineAck(
          message: _msg(from: bob.peerId, to: alice.peerId, content: envelope),
          deliveryRepo: deliveryRepo,
          bridge: bridge,
          ownMlKemSecretKey: alice.mlKemSecretKey,
        );
        expect(honest, HandleGroupInviteDeclineAckResult.declined);
        expect(deliveryRepo.declined, [(groupId: 'grp-f1', peerId: bob.peerId)]);

        // A relayed copy claiming a different transport sender is rejected.
        final spoofed = await handleIncomingGroupInviteDeclineAck(
          message: _msg(
            from: '12D3KooWMallory',
            to: alice.peerId,
            content: envelope,
          ),
          deliveryRepo: deliveryRepo,
          bridge: bridge,
          ownMlKemSecretKey: alice.mlKemSecretKey,
        );
        expect(spoofed, HandleGroupInviteDeclineAckResult.invalidPayload);
        expect(deliveryRepo.declined, hasLength(1));
      },
    );

    testWidgets(
      'C: a revocation carrying the persisted invite_id real-decrypts and deletes the matching live pending invite (HOLE-4); a mismatched id leaves it',
      (tester) async {
        final alice = await _generateIdentity(bridge, 'Alice'); // admin revoker
        final bob = await _generateIdentity(bridge, 'Bob'); // invitee

        final groupConfig = <String, dynamic>{
          'name': 'Revoke Proof',
          'groupType': 'chat',
          'members': [
            {
              'peerId': alice.peerId,
              'username': 'Alice',
              'role': 'admin',
              'publicKey': alice.publicKey,
              'mlKemPublicKey': alice.mlKemPublicKey,
            },
            {
              'peerId': bob.peerId,
              'username': 'Bob',
              'role': 'writer',
              'publicKey': bob.publicKey,
              'mlKemPublicKey': bob.mlKemPublicKey,
            },
          ],
          'createdBy': alice.peerId,
          'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        };

        final p2p = FakeP2PService(
          initialState: const NodeState(isStarted: true),
          sendMessageResult: true,
        );
        final sendResult = await sendGroupInviteRevocation(
          p2pService: p2p,
          bridge: bridge,
          inviteId: 'invite-c1',
          groupId: 'grp-c1',
          recipientPeerId: bob.peerId,
          recipientMlKemPublicKey: bob.mlKemPublicKey,
          senderPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          groupConfig: groupConfig,
        );
        expect(sendResult, SendGroupInviteRevocationResult.success);
        final envelope = p2p.lastSendMessageContent!;

        // Bob knows Alice's real signing key (the revocation receiver verifies
        // the revoker's ed25519 signature against the contact's publicKey).
        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: alice.peerId,
              publicKey: alice.publicKey,
              rendezvous: '/ip4/0.0.0.0',
              username: 'Alice',
              signature: 'sig',
              scannedAt: '2026-01-01T00:00:00Z',
              mlKemPublicKey: alice.mlKemPublicKey,
            ),
          ]);

        // Bob holds a pending invite under the SAME id → revocation deletes it.
        final pendingRepo = InMemoryPendingGroupInviteRepository();
        await pendingRepo.savePendingInvite(
          _pendingInvite(groupId: 'grp-c1', inviteId: 'invite-c1', from: alice),
        );
        final (matchResult, removed) =
            await handleIncomingGroupInviteRevocation(
              message: _msg(
                from: alice.peerId,
                to: bob.peerId,
                content: envelope,
              ),
              pendingInviteRepo: pendingRepo,
              contactRepo: contactRepo,
              bridge: bridge,
              ownMlKemSecretKey: bob.mlKemSecretKey,
              ownPeerId: bob.peerId,
            );
        expect(matchResult, HandleGroupInviteRevocationResult.revoked);
        expect(removed, isNotNull);
        expect(await pendingRepo.getPendingInvite('grp-c1'), isNull);

        // A pending invite under a DIFFERENT id is NOT deleted by this id.
        final pendingRepo2 = InMemoryPendingGroupInviteRepository();
        await pendingRepo2.savePendingInvite(
          _pendingInvite(
            groupId: 'grp-c1',
            inviteId: 'invite-OTHER',
            from: alice,
          ),
        );
        final (_, removed2) = await handleIncomingGroupInviteRevocation(
          message: _msg(from: alice.peerId, to: bob.peerId, content: envelope),
          pendingInviteRepo: pendingRepo2,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: bob.mlKemSecretKey,
          ownPeerId: bob.peerId,
        );
        expect(removed2, isNull, reason: 'id mismatch must not delete');
        expect(await pendingRepo2.getPendingInvite('grp-c1'), isNotNull);
      },
    );

    testWidgets(
      'D: an admin-signed config:response verifies with REAL ed25519 and applies strictly-newer metadata; a forged signature is rejected',
      (tester) async {
        final alice = await _generateIdentity(bridge, 'Alice'); // admin
        final bob = await _generateIdentity(bridge, 'Bob'); // joiner
        const groupId = 'grp-d1';

        // Bob's local group: stale name, admin Alice known with her real key.
        final groupRepo = InMemoryGroupRepository();
        final t1 = DateTime.utc(2026, 6, 1);
        final t2 = DateTime.utc(2026, 6, 10);
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Stale Name',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: alice.peerId,
            myRole: GroupRole.member,
            lastMetadataEventAt: t1,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: alice.peerId,
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: alice.publicKey,
            mlKemPublicKey: alice.mlKemPublicKey,
            joinedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        // Honest path: Alice signs the actorEvent with her REAL ed25519 key.
        final honestPayload = await _buildConfigResponsePayload(
          bridge: bridge,
          groupId: groupId,
          newName: 'Fresh Name',
          actorPeerId: alice.peerId,
          actorUsername: 'Alice',
          actorPublicKey: alice.publicKey,
          actorPrivateKey: alice.privateKey,
          updatedAt: t2,
        );
        final applied = await applyOnJoinGroupConfigResponse(
          systemPayload: honestPayload,
          groupId: groupId,
          groupRepo: groupRepo,
          bridge: bridge,
          downloadGroupAvatarFn:
              ({required bridge, required groupId, required blobId}) async =>
                  null,
        );
        expect(applied, ApplyGroupConfigResponseResult.applied);
        final updated = await groupRepo.getGroup(groupId);
        expect(updated!.name, 'Fresh Name');
        expect(updated.lastMetadataEventAt, t2);

        // Forged path: sign with BOB's key but claim Alice's public key.
        // Real ed25519 verification (callVerifyPayload) must reject it.
        final t3 = DateTime.utc(2026, 6, 20);
        final forgedPayload = await _buildConfigResponsePayload(
          bridge: bridge,
          groupId: groupId,
          newName: 'Forged Name',
          actorPeerId: alice.peerId,
          actorUsername: 'Alice',
          actorPublicKey: alice.publicKey,
          actorPrivateKey: bob.privateKey, // wrong signer
          updatedAt: t3,
        );
        final rejected = await applyOnJoinGroupConfigResponse(
          systemPayload: forgedPayload,
          groupId: groupId,
          groupRepo: groupRepo,
          bridge: bridge,
        );
        expect(rejected, ApplyGroupConfigResponseResult.unauthenticated);
        // Unchanged from the honest apply.
        expect((await groupRepo.getGroup(groupId))!.name, 'Fresh Name');
      },
    );
  });
}

// --- Helpers ---

Future<IdentityModel> _generateIdentity(
  GoBridgeClient bridge,
  String username,
) async {
  final identityResponse = await bridge.send(
    jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
  );
  final identityResult = jsonDecode(identityResponse) as Map<String, dynamic>;
  expect(identityResult['ok'], isTrue, reason: '$identityResult');
  final identity = identityResult['identity'] as Map<String, dynamic>;

  final mlKemResponse = await bridge.send(
    jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
  );
  final mlKemResult = jsonDecode(mlKemResponse) as Map<String, dynamic>;
  expect(mlKemResult['ok'], isTrue, reason: '$mlKemResult');

  final now = DateTime.now().toUtc().toIso8601String();
  return IdentityModel(
    peerId: identity['peerId'] as String,
    publicKey: identity['publicKey'] as String,
    privateKey: identity['privateKey'] as String,
    mnemonic12: identity['mnemonic12'] as String? ?? 'integration mnemonic',
    mlKemPublicKey: mlKemResult['publicKey'] as String,
    mlKemSecretKey: mlKemResult['secretKey'] as String,
    username: username,
    createdAt: now,
    updatedAt: now,
  );
}

ChatMessage _msg({
  required String from,
  required String to,
  required String content,
}) {
  return ChatMessage(
    from: from,
    to: to,
    content: content,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

PendingGroupInvite _pendingInvite({
  required String groupId,
  required String inviteId,
  required IdentityModel from,
}) {
  final now = DateTime.now().toUtc();
  return PendingGroupInvite(
    groupId: groupId,
    inviteId: inviteId,
    payloadJson: '{}',
    groupName: 'Revoke Proof',
    groupType: GroupType.chat,
    senderPeerId: from.peerId,
    senderUsername: from.username,
    createdBy: from.peerId,
    createdAt: now,
    receivedAt: now,
    expiresAt: now.add(const Duration(days: 7)),
  );
}

Future<Map<String, dynamic>> _buildConfigResponsePayload({
  required GoBridgeClient bridge,
  required String groupId,
  required String newName,
  required String actorPeerId,
  required String actorUsername,
  required String actorPublicKey,
  required String actorPrivateKey,
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
    privateKey: actorPrivateKey,
  );
  expect(sign['ok'], isTrue, reason: '$sign');
  return {
    '__sys': groupMetadataUpdatedEventType,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'groupConfig': groupConfig,
    groupMetadataActorEventEnvelopeField:
        buildSignedGroupMetadataActorEventEnvelope(
          signedPayload: canonical,
          signature: sign['signature'] as String,
        ),
  };
}

class _SpyDeliveryRepo implements GroupInviteDeliveryAttemptRepository {
  final List<({String groupId, String peerId})> declined = [];

  @override
  Future<void> markDeclined({
    required String groupId,
    required String peerId,
    DateTime? declinedAt,
  }) async {
    declined.add((groupId: groupId, peerId: peerId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
