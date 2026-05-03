import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/revoke_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

void main() {
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;

  const deliverableGroupConfig = {
    'name': 'Book Club',
    'groupType': 'chat',
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
    'createdAt': '2026-04-29T10:00:00.000Z',
  };

  PendingGroupInvite makeInvite() {
    final receivedAt = DateTime.utc(2026, 4, 29, 12);
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
        'createdAt': '2026-04-29T10:00:00.000Z',
      },
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      timestamp: '2026-04-29T10:05:00.000Z',
      recipientPeerId: '12D3KooWReceiver',
      invitePolicy: GroupInvitePolicy(
        expiresAt: receivedAt.add(pendingGroupInviteTtl),
        allowedDevices: const ['12D3KooWReceiver'],
        assignedRole: 'writer',
        canInviteOthers: false,
        joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
        keyEpoch: 1,
      ),
    );
    return PendingGroupInvite.fromPayload(payload, receivedAt: receivedAt);
  }

  setUp(() {
    pendingInviteRepo = InMemoryPendingGroupInviteRepository();
  });

  group('revokePendingGroupInvite', () {
    test('removes pending row and records a revocation tombstone', () async {
      await pendingInviteRepo.savePendingInvite(makeInvite());

      final result = await revokePendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupId: 'grp-abc123',
        now: DateTime.utc(2026, 4, 29, 13),
        revokedBy: '12D3KooWAlice',
      );

      expect(result, RevokePendingGroupInviteResult.revoked);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);

      final revocation = await pendingInviteRepo.getRevokedInvite('invite-1');
      expect(revocation, isNotNull);
      expect(revocation!.groupId, 'grp-abc123');
      expect(revocation.revokedBy, '12D3KooWAlice');
      expect(revocation.isActiveAt(DateTime.utc(2026, 4, 30)), isTrue);
    });

    test('returns notFound without writing a tombstone', () async {
      final result = await revokePendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupId: 'missing-group',
        now: DateTime.utc(2026, 4, 29, 13),
      );

      expect(result, RevokePendingGroupInviteResult.notFound);
      expect(pendingInviteRepo.revokedCount, 0);
    });
  });

  group('sendGroupInviteRevocation', () {
    test(
      'signs before encryption and sends direct revocation envelope',
      () async {
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        addTearDown(p2pService.dispose);
        final bridge = PassthroughCryptoBridge();
        bridge.responses['payload.sign'] = {
          'ok': true,
          'signature': 'signed-revocation-by-alice',
        };

        final result = await sendGroupInviteRevocation(
          p2pService: p2pService,
          bridge: bridge,
          inviteId: 'invite-1',
          groupId: 'grp-abc123',
          recipientPeerId: '12D3KooWReceiver',
          recipientMlKemPublicKey: 'receiverMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
          groupConfig: deliverableGroupConfig,
          now: DateTime.utc(2026, 4, 30, 12),
        );

        expect(result, SendGroupInviteRevocationResult.success);
        expect(bridge.commandLog, contains('payload.sign'));
        expect(
          bridge.commandLog.indexOf('payload.sign'),
          lessThan(bridge.commandLog.indexOf('message.encrypt')),
        );
        expect(p2pService.sendMessageCallCount, 1);
        expect(p2pService.storeInInboxCallCount, 0);

        final envelopeJson = p2pService.lastSendMessageContent!;
        final envelope = GroupInviteRevocationPayload.parseEncryptedEnvelope(
          envelopeJson,
        );
        expect(envelope, isNotNull);
        expect(envelope!['type'], 'group_invite_revocation');
        expect(envelope['version'], '1');
        expect(envelope['id'], 'invite-1');

        final cleartextEnvelope = Map<String, dynamic>.from(
          jsonDecode(envelopeJson) as Map,
        )..remove('encrypted');
        expect(
          cleartextEnvelope.keys,
          unorderedEquals(['type', 'version', 'id', 'senderPeerId']),
        );
        expect(cleartextEnvelope.toString(), isNot(contains('grp-abc123')));
        expect(cleartextEnvelope.toString(), isNot(contains('alicePubKey64')));
        expect(
          cleartextEnvelope.toString(),
          isNot(contains('receiverMlKem64')),
        );
        expect(cleartextEnvelope.toString(), isNot(contains('signature')));

        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final inner =
            jsonDecode(encrypted['ciphertext'] as String)
                as Map<String, dynamic>;
        expect(inner['inviteId'], 'invite-1');
        expect(inner['groupId'], 'grp-abc123');
        expect(inner['recipientPeerId'], '12D3KooWReceiver');
        expect(inner['revokedByPeerId'], '12D3KooWAlice');
        expect(inner['revokerAuthorization'], isA<Map<String, dynamic>>());
        final signature = inner['revocationSignature'] as Map<String, dynamic>;
        expect(signature['signatureAlgorithm'], 'ed25519');
        expect(signature['signature'], 'signed-revocation-by-alice');
      },
    );

    test('stores revocation in inbox when direct send fails', () async {
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
        sendMessageResult: false,
        storeInInboxResult: true,
      );
      addTearDown(p2pService.dispose);

      final result = await sendGroupInviteRevocation(
        p2pService: p2pService,
        bridge: PassthroughCryptoBridge(),
        inviteId: 'invite-1',
        groupId: 'grp-abc123',
        recipientPeerId: '12D3KooWReceiver',
        recipientMlKemPublicKey: 'receiverMlKem64',
        senderPeerId: '12D3KooWAlice',
        senderPublicKey: 'alicePubKey64',
        senderPrivateKey: 'alicePrivateKey64',
        groupConfig: deliverableGroupConfig,
        now: DateTime.utc(2026, 4, 30, 12),
      );

      expect(result, SendGroupInviteRevocationResult.success);
      expect(p2pService.sendMessageCallCount, 1);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(p2pService.lastStoreInInboxPeerId, '12D3KooWReceiver');
      expect(
        GroupInviteRevocationPayload.parseEncryptedEnvelope(
          p2pService.lastStoreInInboxMessage!,
        ),
        isNotNull,
      );
    });

    test(
      'fails before encryption or delivery when revoker is unauthorized',
      () async {
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        addTearDown(p2pService.dispose);
        final bridge = PassthroughCryptoBridge();

        final result = await sendGroupInviteRevocation(
          p2pService: p2pService,
          bridge: bridge,
          inviteId: 'invite-1',
          groupId: 'grp-abc123',
          recipientPeerId: '12D3KooWReceiver',
          recipientMlKemPublicKey: 'receiverMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
          groupConfig: {
            ...deliverableGroupConfig,
            'members': [
              {
                'peerId': '12D3KooWAlice',
                'username': 'Alice',
                'role': 'writer',
                'publicKey': 'alicePubKey64',
              },
              (deliverableGroupConfig['members'] as List<dynamic>)[1],
            ],
          },
          now: DateTime.utc(2026, 4, 30, 12),
        );

        expect(result, SendGroupInviteRevocationResult.invalidPayload);
        expect(bridge.commandLog, isNot(contains('payload.sign')));
        expect(bridge.commandLog, isNot(contains('message.encrypt')));
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test('fails closed without delivery when signing fails', () async {
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );
      addTearDown(p2pService.dispose);
      final bridge = PassthroughCryptoBridge();
      bridge.responses['payload.sign'] = {
        'ok': false,
        'errorCode': 'SIGN_FAILED',
      };

      final result = await sendGroupInviteRevocation(
        p2pService: p2pService,
        bridge: bridge,
        inviteId: 'invite-1',
        groupId: 'grp-abc123',
        recipientPeerId: '12D3KooWReceiver',
        recipientMlKemPublicKey: 'receiverMlKem64',
        senderPeerId: '12D3KooWAlice',
        senderPublicKey: 'alicePubKey64',
        senderPrivateKey: 'alicePrivateKey64',
        groupConfig: deliverableGroupConfig,
        now: DateTime.utc(2026, 4, 30, 12),
      );

      expect(result, SendGroupInviteRevocationResult.invalidPayload);
      expect(bridge.commandLog, contains('payload.sign'));
      expect(bridge.commandLog, isNot(contains('message.encrypt')));
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
    });
  });
}
