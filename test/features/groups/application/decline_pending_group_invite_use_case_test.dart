import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/decline_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

void main() {
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;

  PendingGroupInvite makeInvite({
    DateTime? receivedAt,
    String? inviterMlKemPublicKey,
  }) {
    final effectiveReceivedAt = (receivedAt ?? DateTime.now().toUtc()).toUtc();
    final createdAt = effectiveReceivedAt.subtract(const Duration(hours: 6));
    final inviteTimestamp = createdAt.add(const Duration(minutes: 5));
    // When an inviter ML-KEM key is requested, attach a membership-freshness
    // proof carrying it in the inviter snapshot — exactly how a real invite
    // delivers the key (G1 extraction path).
    final freshnessProof = inviterMlKemPublicKey == null
        ? null
        : GroupInviteMembershipFreshnessProof(
            inviteId: 'invite-1',
            groupId: 'grp-abc123',
            recipientPeerId: '12D3KooWReceiver',
            inviterPeerId: '12D3KooWAlice',
            inviterPublicKey: 'alicePubKey64',
            keyEpoch: 1,
            groupConfigStateHash: 'state-hash',
            membershipWatermark: 'state-hash',
            issuedAt: inviteTimestamp,
            expiresAt: inviteTimestamp.add(const Duration(hours: 1)),
            inviterMemberSnapshot: {
              'peerId': '12D3KooWAlice',
              'username': 'Alice',
              'role': 'admin',
              'publicKey': 'alicePubKey64',
              'mlKemPublicKey': inviterMlKemPublicKey,
            },
          );
    final payload = GroupInvitePayload(
      id: 'invite-1',
      groupId: 'grp-abc123',
      groupKey: 'base64-key',
      keyEpoch: 1,
      groupConfig: {
        'name': 'Book Club',
        'groupType': 'chat',
        'members': const [
          {'peerId': '12D3KooWAlice', 'role': 'admin'},
          {'peerId': '12D3KooWReceiver', 'role': 'writer'},
        ],
        'createdBy': '12D3KooWAlice',
        'createdAt': createdAt.toIso8601String(),
      },
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      timestamp: inviteTimestamp.toIso8601String(),
      recipientPeerId: '12D3KooWReceiver',
      invitePolicy: GroupInvitePolicy(
        expiresAt: effectiveReceivedAt.add(pendingGroupInviteTtl),
        allowedDevices: const ['12D3KooWReceiver'],
        assignedRole: 'writer',
        canInviteOthers: false,
        joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
        keyEpoch: 1,
      ),
      membershipFreshnessProof: freshnessProof,
    );
    return PendingGroupInvite.fromPayload(
      payload,
      receivedAt: effectiveReceivedAt,
    );
  }

  setUp(() {
    pendingInviteRepo = InMemoryPendingGroupInviteRepository();
  });

  group('declinePendingGroupInvite', () {
    test('deletes pending invite on decline', () async {
      await pendingInviteRepo.savePendingInvite(makeInvite());

      final result = await declinePendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupId: 'grp-abc123',
      );

      expect(result, DeclinePendingGroupInviteResult.success);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
    });

    test(
      'ML-018 decline records a tombstone so delayed copies stay unusable',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());
        final declinedAt = DateTime.utc(2026, 4, 2, 12);

        final result = await declinePendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupId: 'grp-abc123',
          now: declinedAt,
        );

        expect(result, DeclinePendingGroupInviteResult.success);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        final consumption = await pendingInviteRepo.getConsumedInvite(
          'invite-1',
        );
        expect(consumption, isNotNull);
        expect(consumption!.groupId, 'grp-abc123');
        expect(consumption.consumedAt, declinedAt);
        expect(
          consumption.isActiveAt(declinedAt.add(const Duration(days: 6))),
          isTrue,
        );
      },
    );

    test('returns expired when declining an expired invite', () async {
      await pendingInviteRepo.savePendingInvite(
        makeInvite(receivedAt: DateTime.utc(2026, 4, 1, 13, 0)),
      );

      final result = await declinePendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupId: 'grp-abc123',
        now: DateTime.utc(2026, 4, 12, 13, 0),
      );

      expect(result, DeclinePendingGroupInviteResult.expired);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
    });

    test(
      'declining on one device does not clear the sibling device pending invite',
      () async {
        final phonePendingInviteRepo = InMemoryPendingGroupInviteRepository();
        final tabletPendingInviteRepo = InMemoryPendingGroupInviteRepository();

        await phonePendingInviteRepo.savePendingInvite(makeInvite());
        await tabletPendingInviteRepo.savePendingInvite(makeInvite());

        final result = await declinePendingGroupInvite(
          pendingInviteRepo: phonePendingInviteRepo,
          groupId: 'grp-abc123',
        );

        expect(result, DeclinePendingGroupInviteResult.success);
        expect(
          await phonePendingInviteRepo.getPendingInvite('grp-abc123'),
          isNull,
        );
        expect(
          await tabletPendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
      },
    );

    test(
      'F: decline sends a signed decline-ack to the inviter and still tombstones + deletes',
      () async {
        await pendingInviteRepo.savePendingInvite(makeInvite());
        final contactRepo = FakeContactRepository();
        contactRepo.seed([
          const ContactModel(
            peerId: '12D3KooWAlice',
            publicKey: 'alicePubKey64',
            rendezvous: '/ip4/0.0.0.0',
            username: 'Alice',
            signature: 'sig',
            scannedAt: '2026-01-01T00:00:00Z',
            mlKemPublicKey: 'aliceMlKem64',
          ),
        ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
          sendMessageResult: true,
        );

        final result = await declinePendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupId: 'grp-abc123',
          p2pService: p2pService,
          bridge: FakeBridge(),
          contactRepo: contactRepo,
          declinerPeerId: '12D3KooWReceiver',
          declinerPrivateKey: 'recv-priv',
        );

        expect(result, DeclinePendingGroupInviteResult.success);
        // Local effects are intact and unaffected by the best-effort send.
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getConsumedInvite('invite-1'),
          isNotNull,
        );
        // A decline-ack was sent to the inviter.
        expect(p2pService.sendMessageCallCount, 1);
        expect(p2pService.lastSendMessagePeerId, '12D3KooWAlice');
        final envelope =
            jsonDecode(p2pService.lastSendMessageContent!)
                as Map<String, dynamic>;
        expect(envelope['type'], 'group_invite_decline_ack');
        expect(envelope['id'], 'invite-1');
      },
    );

    test(
      'F: decline still succeeds locally and skips the ack (DECLINE_ACK_ENCRYPTION_SKIPPED) when the inviter ML-KEM key is unavailable',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));

        await pendingInviteRepo.savePendingInvite(makeInvite());
        // No contact for the inviter → no resolvable ML-KEM key.
        final contactRepo = FakeContactRepository();
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
          sendMessageResult: true,
        );

        final result = await declinePendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupId: 'grp-abc123',
          p2pService: p2pService,
          bridge: FakeBridge(),
          contactRepo: contactRepo,
          declinerPeerId: '12D3KooWReceiver',
          declinerPrivateKey: 'recv-priv',
        );

        expect(result, DeclinePendingGroupInviteResult.success);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(p2pService.sendMessageCallCount, 0);
        expect(
          flowEvents.where(
            (e) => e['event'] == 'DECLINE_ACK_ENCRYPTION_SKIPPED',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'G1: decline sends a signed decline-ack to a NON-CONTACT inviter using the invite-carried ML-KEM key',
      () async {
        // Invite carries the inviter ML-KEM key in its freshness proof, but the
        // inviter is NOT a contact — the common group-invite case.
        await pendingInviteRepo.savePendingInvite(
          makeInvite(inviterMlKemPublicKey: 'aliceMlKem64'),
        );
        final contactRepo = FakeContactRepository(); // no inviter contact
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
          sendMessageResult: true,
        );

        final result = await declinePendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupId: 'grp-abc123',
          p2pService: p2pService,
          bridge: FakeBridge(),
          contactRepo: contactRepo,
          declinerPeerId: '12D3KooWReceiver',
          declinerPrivateKey: 'recv-priv',
        );

        expect(result, DeclinePendingGroupInviteResult.success);
        // The ack was sent despite there being no contact for the inviter.
        expect(p2pService.sendMessageCallCount, 1);
        expect(p2pService.lastSendMessagePeerId, '12D3KooWAlice');
        final envelope =
            jsonDecode(p2pService.lastSendMessageContent!)
                as Map<String, dynamic>;
        expect(envelope['type'], 'group_invite_decline_ack');
      },
    );

    test(
      'G1: decline still skips the ack for a non-contact inviter when the invite carries no ML-KEM key',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));

        // No freshness proof → invite.mlKemPublicKey is null; no contact either.
        await pendingInviteRepo.savePendingInvite(makeInvite());
        final contactRepo = FakeContactRepository();
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
          sendMessageResult: true,
        );

        final result = await declinePendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupId: 'grp-abc123',
          p2pService: p2pService,
          bridge: FakeBridge(),
          contactRepo: contactRepo,
          declinerPeerId: '12D3KooWReceiver',
          declinerPrivateKey: 'recv-priv',
        );

        expect(result, DeclinePendingGroupInviteResult.success);
        expect(p2pService.sendMessageCallCount, 0);
        expect(
          flowEvents.where(
            (e) => e['event'] == 'DECLINE_ACK_ENCRYPTION_SKIPPED',
          ),
          hasLength(1),
        );
      },
    );
  });
}
