import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

/// A message in 'sending' status, as it exists before any send attempt completes.
/// The [createdAt] is set to [ageOffset] before [relativeTo].
ConversationMessage makeSendingMessage({
  String id = 'msg-sending-001',
  String contactPeerId = 'peer-bob',
  String text = 'Hello',
  Duration ageOffset = Duration.zero,
  DateTime? relativeTo,
}) {
  final base = relativeTo ?? DateTime(2026, 3, 23, 12, 0, 0).toUtc();
  final createdAt = base.subtract(ageOffset).toIso8601String();
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'peer-alice',
    text: text,
    timestamp: createdAt,
    status: 'sending',
    isIncoming: false,
    createdAt: createdAt,
    wireEnvelope: '{"type":"chat_message","version":"1","payload":{}}',
  );
}

/// A message in 'failed' status with a pre-built wire envelope.
ConversationMessage makeFailedMessageWithEnvelope({
  String id = 'msg-failed-001',
  String contactPeerId = 'peer-bob',
  String text = 'Hello',
}) {
  const ts = '2026-03-23T12:00:00.000Z';
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'peer-alice',
    text: text,
    timestamp: ts,
    status: 'failed',
    isIncoming: false,
    createdAt: ts,
    wireEnvelope: '{"type":"chat_message","version":"2","encrypted":{'
        '"kem":"fake-kem","ciphertext":"fake-ct","nonce":"fake-nonce"}}',
  );
}

/// Identity fixture with full ML-KEM keys.
IdentityModel makeAliceIdentity() {
  return IdentityModel(
    peerId: 'peer-alice',
    publicKey: 'alice-pk-base64',
    privateKey: 'alice-privkey-base64',
    mnemonic12: 'word1 word2 word3 word4 word5 word6 '
        'word7 word8 word9 word10 word11 word12',
    mlKemPublicKey: 'alice-mlkem-pk',
    mlKemSecretKey: 'alice-mlkem-sk',
    username: 'Alice',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

/// Contact fixture for Bob, with ML-KEM public key.
ContactModel makeBobContact() {
  return ContactModel(
    peerId: 'peer-bob',
    publicKey: 'bob-pk-base64',
    rendezvous: '/dns4/relay.example.com/tcp/443/p2p/relay',
    username: 'Bob',
    signature: 'bob-sig-base64',
    scannedAt: '2026-01-01T00:00:00.000Z',
    mlKemPublicKey: 'bob-mlkem-pk',
  );
}
