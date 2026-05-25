import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();

    await groupRepo.saveGroup(
      GroupModel(
        id: 'group-1',
        name: 'Replay Group',
        type: GroupType.chat,
        topicName: 'topic-group-1',
        createdAt: DateTime.utc(2026, 5, 2),
        createdBy: 'peer-sender',
        myRole: GroupRole.member,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-sender',
        username: 'Sender',
        role: MemberRole.writer,
        publicKey: 'pk-sender',
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: 'device-sender',
            transportPeerId: 'transport-sender',
            deviceSigningPublicKey: 'pk-sender',
          ),
        ],
        joinedAt: DateTime.utc(2026, 5, 2),
      ),
    );
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 7,
        encryptedKey: 'group-key-7',
        createdAt: DateTime.utc(2026, 5, 2),
      ),
    );
  });

  test(
    'EK004 builds signed replay envelopes bound to sender and payload',
    () async {
      final plaintext = jsonEncode({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderDeviceId': 'device-sender',
        'transportPeerId': 'transport-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 7,
        'text': 'signed replay',
        'timestamp': '2026-05-02T07:15:00.000Z',
        'messageId': 'msg-ek004-signed',
      });

      final rawEnvelope = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: plaintext,
        messageId: 'msg-ek004-signed',
        senderPeerId: 'peer-sender',
        senderPublicKey: 'pk-sender',
        senderPrivateKey: 'sk-sender',
        senderDeviceId: 'device-sender',
        senderTransportPeerId: 'transport-sender',
        recipientPeerIds: const ['peer-recipient-b', 'peer-recipient-a'],
      );

      final envelope = jsonDecode(rawEnvelope) as Map<String, dynamic>;
      expect(envelope['kind'], groupOfflineReplayEnvelopeKind);
      expect(envelope['version'], 1);
      expect(envelope['groupId'], 'group-1');
      expect(envelope['payloadType'], groupOfflineReplayPayloadTypeMessage);
      expect(envelope['messageId'], 'msg-ek004-signed');
      expect(envelope['senderPeerId'], 'peer-sender');
      expect(envelope['senderDeviceId'], 'device-sender');
      expect(envelope['senderTransportPeerId'], 'transport-sender');
      expect(envelope['senderPublicKey'], 'pk-sender');
      expect(
        envelope['signatureAlgorithm'],
        groupOfflineReplaySignatureAlgorithm,
      );
      expect(envelope['signedPayload'], isA<String>());
      expect(envelope['signature'], 'fake-signature');

      final signedPayload =
          jsonDecode(envelope['signedPayload'] as String)
              as Map<String, dynamic>;
      expect(
        signedPayload['schemaVersion'],
        groupOfflineReplaySignatureVersion,
      );
      expect(signedPayload['kind'], groupOfflineReplayEnvelopeKind);
      expect(signedPayload['groupId'], 'group-1');
      expect(
        signedPayload['payloadType'],
        groupOfflineReplayPayloadTypeMessage,
      );
      expect(signedPayload['messageId'], 'msg-ek004-signed');
      expect(signedPayload['senderPeerId'], 'peer-sender');
      expect(signedPayload['senderDeviceId'], 'device-sender');
      expect(signedPayload['senderTransportPeerId'], 'transport-sender');
      expect(signedPayload['senderSigningPublicKey'], 'pk-sender');
      expect(
        signedPayload['ciphertextHash'],
        sha256
            .convert(utf8.encode(envelope['ciphertext'] as String))
            .toString(),
      );
      expect(
        signedPayload['nonceHash'],
        sha256.convert(utf8.encode(envelope['nonce'] as String)).toString(),
      );
      expect(
        signedPayload['plaintextHash'],
        sha256.convert(utf8.encode(plaintext)).toString(),
      );
      expect(signedPayload['recipientSetHash'], isA<String>());
    },
  );

  test(
    'EK004 decode rejects missing malformed mismatched and invalid signatures before decrypt',
    () async {
      final rawEnvelope = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderDeviceId': 'device-sender',
          'transportPeerId': 'transport-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 7,
          'text': 'signed replay',
          'timestamp': '2026-05-02T07:15:00.000Z',
          'messageId': 'msg-ek004-signed',
        }),
        messageId: 'msg-ek004-signed',
        senderPeerId: 'peer-sender',
        senderPublicKey: 'pk-sender',
        senderPrivateKey: 'sk-sender',
        senderDeviceId: 'device-sender',
        senderTransportPeerId: 'transport-sender',
      );
      final baseEnvelope = jsonDecode(rawEnvelope) as Map<String, dynamic>;

      Future<void> expectRejectedBeforeDecrypt(
        Map<String, dynamic> envelope, {
        bool invalidBridgeSignature = false,
      }) async {
        bridge.commandLog.clear();
        if (invalidBridgeSignature) {
          bridge.responses['payload.verify'] = {'ok': true, 'valid': false};
        } else {
          bridge.responses.remove('payload.verify');
        }

        await expectLater(
          decodeInboxMessage(bridge, groupRepo, {
            'from': 'transport-sender',
            'message': jsonEncode(envelope),
          }, 'group-1'),
          throwsA(isA<GroupOfflineReplaySignatureException>()),
        );
        expect(bridge.commandLog, isNot(contains('group.decrypt')));
      }

      final missing = Map<String, dynamic>.from(baseEnvelope)
        ..remove('signature');
      await expectRejectedBeforeDecrypt(missing);

      final malformed = Map<String, dynamic>.from(baseEnvelope)
        ..['signedPayload'] = '{"groupId":"different"';
      await expectRejectedBeforeDecrypt(malformed);

      final mismatched = Map<String, dynamic>.from(baseEnvelope)
        ..['senderPeerId'] = 'peer-attacker';
      await expectRejectedBeforeDecrypt(mismatched);

      await expectRejectedBeforeDecrypt(
        Map<String, dynamic>.from(baseEnvelope),
        invalidBridgeSignature: true,
      );
    },
  );

  test(
    'SV-014 hides membership replay event details from relay-visible payload',
    () async {
      bridge.responses['group.encrypt'] = {
        'ok': true,
        'ciphertext': 'sv014-membership-ciphertext',
        'nonce': 'sv014-membership-nonce',
      };

      const systemMessageId = 'sys-member_added:group-1:peer-dana:42';
      final plaintext = jsonEncode({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderDeviceId': 'device-sender',
        'transportPeerId': 'transport-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 7,
        'text': jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-dana',
            'username': 'Dana Secret',
            'role': 'writer',
            'publicKey': 'pk-dana-secret',
            'mlKemPublicKey': 'mlkem-dana-secret',
          },
          'groupConfig': {
            'name': 'SV014 Secret Group',
            'members': [
              {'peerId': 'peer-sender', 'role': 'admin'},
              {'peerId': 'peer-dana', 'role': 'writer'},
            ],
          },
        }),
        'timestamp': '2026-05-16T05:28:00.000Z',
        'messageId': systemMessageId,
      });

      final retryPayload = await buildGroupOfflineReplayInboxRetryPayload(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: plaintext,
        messageId: systemMessageId,
        senderPeerId: 'peer-sender',
        senderPublicKey: 'pk-sender',
        senderPrivateKey: 'sk-sender',
        senderDeviceId: 'device-sender',
        senderTransportPeerId: 'transport-sender',
        recipientPeerIds: const ['peer-bob', 'peer-charlie'],
      );

      final retry = jsonDecode(retryPayload) as Map<String, dynamic>;
      expect(retry['groupId'], 'group-1');
      expect(retry['recipientPeerIds'], ['peer-bob', 'peer-charlie']);

      final envelope =
          jsonDecode(retry['message'] as String) as Map<String, dynamic>;
      expect(envelope.containsKey('messageId'), isFalse);
      expect(envelope['recipientPeerIds'], ['peer-bob', 'peer-charlie']);
      expect(envelope['recipientSetHash'], isA<String>());

      final signedPayload =
          jsonDecode(envelope['signedPayload'] as String)
              as Map<String, dynamic>;
      expect(signedPayload.containsKey('messageId'), isFalse);
      expect(signedPayload['plaintextHash'], isA<String>());

      for (final forbidden in const [
        'sys-member_added',
        'member_added',
        '__sys',
        'Dana Secret',
        'pk-dana-secret',
        'mlkem-dana-secret',
        'SV014 Secret Group',
      ]) {
        expect(
          retryPayload,
          isNot(contains(forbidden)),
          reason: 'relay-visible retry payload leaked $forbidden',
        );
      }
      expect(
        sha256.convert(utf8.encode(plaintext)).toString(),
        signedPayload['plaintextHash'],
      );
    },
  );

  test(
    'storeGroupOfflineReplayEnvelope can preserve explicit recipients',
    () async {
      await storeGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'text': 'member removed',
          'timestamp': '2026-05-02T07:20:00.000Z',
          'messageId': 'msg-explicit-recipients',
        }),
        senderPeerId: 'peer-sender',
        senderPublicKey: 'pk-sender',
        senderPrivateKey: 'sk-sender',
        messageId: 'msg-explicit-recipients',
        recipientPeerIds: const ['peer-removed'],
        preserveRecipientPeerIds: true,
      );

      final inboxStore = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .singleWhere((message) => message['cmd'] == 'group:inboxStore');
      final payload = inboxStore['payload'] as Map<String, dynamic>;
      expect(payload['recipientPeerIds'], ['peer-removed']);
      expect(payload['preserveRecipientPeerIds'], isTrue);
    },
  );

  test('GK-028 decode rejects senderPublicKey tamper before decrypt', () async {
    final rawEnvelope = await buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: jsonEncode({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderDeviceId': 'device-sender',
        'transportPeerId': 'transport-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 7,
        'text': 'signed replay',
        'timestamp': '2026-05-02T07:15:00.000Z',
        'messageId': 'msg-gk028-signed',
      }),
      messageId: 'msg-gk028-signed',
      senderPeerId: 'peer-sender',
      senderPublicKey: 'pk-sender',
      senderPrivateKey: 'sk-sender',
      senderDeviceId: 'device-sender',
      senderTransportPeerId: 'transport-sender',
    );
    final tamperedEnvelope = jsonDecode(rawEnvelope) as Map<String, dynamic>;
    tamperedEnvelope['senderPublicKey'] = 'pk-attacker';
    tamperedEnvelope['signedPayload'] =
        (tamperedEnvelope['signedPayload'] as String).replaceFirst(
          'pk-sender',
          'pk-attacker',
        );

    bridge.commandLog.clear();
    await expectLater(
      decodeInboxMessage(bridge, groupRepo, {
        'from': 'transport-sender',
        'message': jsonEncode(tamperedEnvelope),
      }, 'group-1'),
      throwsA(
        isA<GroupOfflineReplaySignatureException>().having(
          (error) => error.reason,
          'reason',
          'sender_key_mismatch',
        ),
      ),
    );
    expect(bridge.commandLog, isNot(contains('payload.verify')));
    expect(bridge.commandLog, isNot(contains('group.decrypt')));
  });
}
