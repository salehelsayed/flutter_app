import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_decline_ack.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_decline_ack_payload.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';

/// Records markDeclined/markRevoked calls; all other interface methods are
/// unused by the handler under test.
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

ChatMessage _makeDeclineAckMessage({
  String inviteId = 'invite-1',
  String groupId = 'grp-abc123',
  String declinedByPeerId = '12D3KooWBob',
  String? envelopeSenderPeerId,
  String? from,
}) {
  final payload = GroupInviteDeclineAckPayload(
    inviteId: inviteId,
    groupId: groupId,
    declinedByPeerId: declinedByPeerId,
    declinedAt: '2026-06-17T12:00:00.000Z',
    expiresAt: '2026-06-24T12:00:00.000Z',
  ).withDeclineSignature(signature: 'signed-decline-by-bob');
  final envelope = GroupInviteDeclineAckPayload.buildEncryptedEnvelope(
    senderPeerId: envelopeSenderPeerId ?? declinedByPeerId,
    inviteId: inviteId,
    kem: 'fake-kem',
    ciphertext: payload.toInnerJson(),
    nonce: 'fake-nonce',
  );
  return ChatMessage(
    from: from ?? declinedByPeerId,
    to: '12D3KooWAlice',
    content: envelope,
    timestamp: '2026-06-17T12:00:00.000Z',
    isIncoming: true,
  );
}

void main() {
  late _SpyDeliveryRepo deliveryRepo;
  late PassthroughCryptoBridge bridge;

  setUp(() {
    deliveryRepo = _SpyDeliveryRepo();
    bridge = PassthroughCryptoBridge();
  });

  test('a valid signed decline-ack marks the declining peer declined', () async {
    final result = await handleIncomingGroupInviteDeclineAck(
      message: _makeDeclineAckMessage(),
      deliveryRepo: deliveryRepo,
      bridge: bridge,
      ownMlKemSecretKey: 'mySecretKey',
    );

    expect(result, HandleGroupInviteDeclineAckResult.declined);
    expect(deliveryRepo.declinedCalls, hasLength(1));
    expect(deliveryRepo.declinedCalls.single.groupId, 'grp-abc123');
    expect(deliveryRepo.declinedCalls.single.peerId, '12D3KooWBob');
  });

  test(
    'a spoofed ack (message.from != signed declining peer) is rejected without marking declined',
    () async {
      final result = await handleIncomingGroupInviteDeclineAck(
        // Mallory relays an ack claiming Bob declined; envelope sender matches
        // the transport sender (Mallory) so the inner spoof guard must catch it.
        message: _makeDeclineAckMessage(
          declinedByPeerId: '12D3KooWBob',
          envelopeSenderPeerId: '12D3KooWMallory',
          from: '12D3KooWMallory',
        ),
        deliveryRepo: deliveryRepo,
        bridge: bridge,
        ownMlKemSecretKey: 'mySecretKey',
      );

      expect(result, HandleGroupInviteDeclineAckResult.invalidPayload);
      expect(deliveryRepo.declinedCalls, isEmpty);
    },
  );

  test('an envelope whose senderPeerId != transport sender is rejected', () async {
    final result = await handleIncomingGroupInviteDeclineAck(
      message: _makeDeclineAckMessage(
        envelopeSenderPeerId: '12D3KooWBob',
        from: '12D3KooWMallory',
      ),
      deliveryRepo: deliveryRepo,
      bridge: bridge,
      ownMlKemSecretKey: 'mySecretKey',
    );

    expect(result, HandleGroupInviteDeclineAckResult.invalidPayload);
    expect(deliveryRepo.declinedCalls, isEmpty);
  });

  ContactModel bobContact() => const ContactModel(
    peerId: '12D3KooWBob',
    publicKey: 'bobPubKey64',
    rendezvous: '/ip4/0.0.0.0',
    username: 'Bob',
    signature: 'sig',
    scannedAt: '2026-01-01T00:00:00Z',
    mlKemPublicKey: 'bobMlKem64',
  );

  test(
    'G6: a structurally-valid decline-ack with a forged signature from a known '
    'contact decliner is rejected without marking declined',
    () async {
      final contactRepo = FakeContactRepository();
      contactRepo.seed([bobContact()]);
      // Ed25519 verification fails (the signature does not match Bob's key).
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};

      final result = await handleIncomingGroupInviteDeclineAck(
        message: _makeDeclineAckMessage(),
        deliveryRepo: deliveryRepo,
        bridge: bridge,
        contactRepo: contactRepo,
        ownMlKemSecretKey: 'mySecretKey',
      );

      expect(result, HandleGroupInviteDeclineAckResult.invalidPayload);
      expect(deliveryRepo.declinedCalls, isEmpty);
    },
  );

  test(
    'G6: a valid signature from a known contact decliner is marked declined',
    () async {
      final contactRepo = FakeContactRepository();
      contactRepo.seed([bobContact()]);
      // Default PassthroughCryptoBridge payload.verify → {ok:true, valid:true}.

      final result = await handleIncomingGroupInviteDeclineAck(
        message: _makeDeclineAckMessage(),
        deliveryRepo: deliveryRepo,
        bridge: bridge,
        contactRepo: contactRepo,
        ownMlKemSecretKey: 'mySecretKey',
      );

      expect(result, HandleGroupInviteDeclineAckResult.declined);
      expect(deliveryRepo.declinedCalls, hasLength(1));
      expect(deliveryRepo.declinedCalls.single.peerId, '12D3KooWBob');
    },
  );

  test(
    'G6: a non-contact decliner is still marked declined (no trusted signing '
    'key; authenticity rests on encryption + the spoof guard)',
    () async {
      // Empty contacts: the decliner is not a known contact, so there is no
      // trusted key to verify against. Even if the bridge would report the
      // signature invalid, the handler must not falsely reject a legitimate
      // ack — it degrades to the existing encryption + from-guard authenticity.
      final contactRepo = FakeContactRepository();
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};

      final result = await handleIncomingGroupInviteDeclineAck(
        message: _makeDeclineAckMessage(),
        deliveryRepo: deliveryRepo,
        bridge: bridge,
        contactRepo: contactRepo,
        ownMlKemSecretKey: 'mySecretKey',
      );

      expect(result, HandleGroupInviteDeclineAckResult.declined);
      expect(deliveryRepo.declinedCalls, hasLength(1));
    },
  );
}
