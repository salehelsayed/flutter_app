import 'dart:convert';

import 'package:flutter_app/features/groups/domain/models/group_invite_revocation_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const authSnapshot = {
    'peerId': '12D3KooWAlice',
    'publicKey': 'alicePubKey64',
    'role': 'admin',
    'permissions': {'inviteMembers': true},
  };

  GroupInviteRevocationPayload makePayload({
    String inviteId = 'invite-uuid-001',
    String groupId = 'grp-abc123',
    String recipientPeerId = '12D3KooWBob',
    String revokedByPeerId = '12D3KooWAlice',
    String revokedAt = '2026-04-30T12:00:00.000Z',
    String expiresAt = '2026-05-07T12:00:00.000Z',
    Map<String, dynamic> revokerAuthorization = authSnapshot,
    bool signed = true,
  }) {
    final payload = GroupInviteRevocationPayload(
      inviteId: inviteId,
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      revokedByPeerId: revokedByPeerId,
      revokedAt: revokedAt,
      expiresAt: expiresAt,
      revokerAuthorization: revokerAuthorization,
    );
    return signed
        ? payload.withRevocationSignature(
            signature: 'signed-revocation-by-alice',
          )
        : payload;
  }

  group('GroupInviteRevocationPayload', () {
    test('round-trips signed canonical encrypted plaintext', () {
      final payload = makePayload();

      final inner = jsonDecode(payload.toInnerJson()) as Map<String, dynamic>;
      expect(inner['inviteId'], 'invite-uuid-001');
      expect(inner['groupId'], 'grp-abc123');
      expect(inner['recipientPeerId'], '12D3KooWBob');
      expect(inner['revokedByPeerId'], '12D3KooWAlice');
      expect(inner['revocationSignature'], isA<Map<String, dynamic>>());

      final parsed = GroupInviteRevocationPayload.fromInnerJson(
        payload.toInnerJson(),
      );
      expect(parsed, isNotNull);
      expect(parsed!.inviteId, payload.inviteId);
      expect(parsed.groupId, payload.groupId);
      expect(parsed.recipientPeerId, payload.recipientPeerId);
      expect(parsed.revokedByPeerId, payload.revokedByPeerId);
      expect(parsed.revokedAtDateTime, DateTime.utc(2026, 4, 30, 12));
      expect(parsed.expiresAtDateTime, DateTime.utc(2026, 5, 7, 12));
      expect(
        parsed.revocationSignature!.signedPayload,
        payload.canonicalRevocationSignedPayload(),
      );
    });

    test('rejects unsigned unsupported and tampered revocation payloads', () {
      final unsigned = makePayload(signed: false);
      expect(
        GroupInviteRevocationPayload.fromInnerJson(unsigned.toInnerJson()),
        isNull,
      );

      final unsupportedAlgorithm =
          jsonDecode(makePayload().toInnerJson()) as Map<String, dynamic>;
      (unsupportedAlgorithm['revocationSignature']
              as Map<String, dynamic>)['signatureAlgorithm'] =
          'rsa-pss';
      expect(
        GroupInviteRevocationPayload.fromInnerJson(
          jsonEncode(unsupportedAlgorithm),
        ),
        isNull,
      );

      void expectTamperRejected(
        String label,
        void Function(Map<String, dynamic> inner) mutate,
      ) {
        final tampered =
            jsonDecode(makePayload().toInnerJson()) as Map<String, dynamic>;
        mutate(tampered);
        expect(
          GroupInviteRevocationPayload.fromInnerJson(jsonEncode(tampered)),
          isNull,
          reason: label,
        );
      }

      expectTamperRejected(
        'invite id mismatch',
        (inner) => inner['inviteId'] = 'invite-other',
      );
      expectTamperRejected(
        'group id mismatch',
        (inner) => inner['groupId'] = 'grp-other',
      );
      expectTamperRejected(
        'recipient mismatch',
        (inner) => inner['recipientPeerId'] = '12D3KooWCarol',
      );
      expectTamperRejected(
        'revoker mismatch',
        (inner) => inner['revokedByPeerId'] = '12D3KooWMallory',
      );
      expectTamperRejected(
        'authorization mismatch',
        (inner) =>
            (inner['revokerAuthorization'] as Map<String, dynamic>)['role'] =
                'writer',
      );
    });

    test('checks recipient binding and expiry', () {
      final payload = makePayload();

      expect(payload.isBoundToRecipient('12D3KooWBob'), isTrue);
      expect(payload.isBoundToRecipient('12D3KooWCarol'), isFalse);
      expect(payload.isExpiredAt(DateTime.utc(2026, 5, 1)), isFalse);
      expect(payload.isExpiredAt(DateTime.utc(2026, 5, 8)), isTrue);

      final backwardsExpiry = makePayload(
        revokedAt: '2026-05-07T12:00:00.000Z',
        expiresAt: '2026-04-30T12:00:00.000Z',
      );
      expect(
        GroupInviteRevocationPayload.fromInnerJson(
          backwardsExpiry.toInnerJson(),
        ),
        isNull,
      );
    });

    test('builds a privacy-safe cleartext encrypted envelope', () {
      final envelopeJson = GroupInviteRevocationPayload.buildEncryptedEnvelope(
        senderPeerId: '12D3KooWAlice',
        inviteId: 'invite-uuid-001',
        kem: 'fake-kem',
        ciphertext: '{"encrypted":"revocation"}',
        nonce: 'fake-nonce',
      );

      final envelope = jsonDecode(envelopeJson) as Map<String, dynamic>;
      expect(envelope['type'], 'group_invite_revocation');
      expect(envelope['version'], '1');
      expect(envelope['id'], 'invite-uuid-001');
      expect(envelope['senderPeerId'], '12D3KooWAlice');
      expect(envelope['encrypted'], isA<Map<String, dynamic>>());

      final cleartextEnvelope = Map<String, dynamic>.from(envelope)
        ..remove('encrypted');
      expect(
        cleartextEnvelope.keys,
        unorderedEquals(['type', 'version', 'id', 'senderPeerId']),
      );
      expect(cleartextEnvelope.toString(), isNot(contains('grp-abc123')));
      expect(cleartextEnvelope.toString(), isNot(contains('groupKey')));
      expect(cleartextEnvelope.toString(), isNot(contains('members')));
      expect(cleartextEnvelope.toString(), isNot(contains('invitePolicy')));
      expect(cleartextEnvelope.toString(), isNot(contains('signature')));

      final parsed = GroupInviteRevocationPayload.parseEncryptedEnvelope(
        envelopeJson,
      );
      expect(parsed, isNotNull);
      expect(parsed!['id'], 'invite-uuid-001');
    });
  });
}
