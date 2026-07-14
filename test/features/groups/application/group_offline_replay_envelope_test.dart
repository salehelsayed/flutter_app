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
    'EK004 decodes account-signed replay from a known sender before device bootstrap',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.admin,
          publicKey: 'pk-sender',
          devices: const [],
          joinedAt: DateTime.utc(2026, 5, 2),
        ),
      );

      final plaintext = jsonEncode({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderDeviceId': 'device-sender',
        'transportPeerId': 'transport-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 7,
        'text': 'signed replay before device bootstrap',
        'timestamp': '2026-05-02T07:15:00.000Z',
        'messageId': 'msg-ek004-device-bootstrap',
      });

      final rawEnvelope = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: plaintext,
        messageId: 'msg-ek004-device-bootstrap',
        senderPeerId: 'peer-sender',
        senderPublicKey: 'pk-sender',
        senderPrivateKey: 'sk-sender',
        senderDeviceId: 'device-sender',
        senderTransportPeerId: 'transport-sender',
      );

      final decoded = await decodeInboxMessage(bridge, groupRepo, {
        'from': 'transport-sender',
        'message': rawEnvelope,
      }, 'group-1');

      expect(decoded['messageId'], 'msg-ek004-device-bootstrap');
      expect(decoded['senderDeviceId'], 'device-sender');
      expect(decoded['transportPeerId'], 'transport-sender');
      expect(decoded['text'], 'signed replay before device bootstrap');
      expect(bridge.commandLog, contains('payload.verify'));
      expect(bridge.commandLog, contains('group.decrypt'));
    },
  );

  test(
    'EK004 decodes metadata replay from a known sender with a stale local device',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.admin,
          publicKey: 'pk-sender',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'device-sender-stale',
              transportPeerId: 'transport-sender-stale',
              deviceSigningPublicKey: 'pk-sender',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 2),
        ),
      );

      final sysText = jsonEncode({
        '__sys': 'group_metadata_updated',
        'updatedAt': '2026-05-02T07:15:00.000Z',
        'groupConfig': {
          'id': 'group-1',
          'name': 'test me',
          'groupType': 'chat',
          'createdBy': 'peer-sender',
          'createdAt': '2026-05-02T00:00:00.000Z',
          'members': [
            {
              'peerId': 'peer-sender',
              'username': 'Sender',
              'role': 'admin',
              'publicKey': 'pk-sender',
              'joinedAt': '2026-05-02T00:00:00.000Z',
              'devices': [
                {
                  'deviceId': 'device-sender-current',
                  'transportPeerId': 'transport-sender-current',
                  'deviceSigningPublicKey': 'pk-sender',
                  'status': 'active',
                },
              ],
            },
          ],
        },
      });
      final plaintext = jsonEncode({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderDeviceId': 'device-sender-current',
        'transportPeerId': 'transport-sender-current',
        'senderUsername': 'Sender',
        'keyEpoch': 7,
        'text': sysText,
        'timestamp': '2026-05-02T07:15:00.000Z',
        'messageId': 'metadata-stale-device-replay',
      });

      final rawEnvelope = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: plaintext,
        messageId: 'metadata-stale-device-replay',
        senderPeerId: 'peer-sender',
        senderPublicKey: 'pk-sender',
        senderPrivateKey: 'sk-sender',
        senderDeviceId: 'device-sender-current',
        senderTransportPeerId: 'transport-sender-current',
      );

      final decoded = await decodeInboxMessage(bridge, groupRepo, {
        'from': 'transport-sender-current',
        'message': rawEnvelope,
      }, 'group-1');

      expect(decoded['messageId'], 'metadata-stale-device-replay');
      expect(decoded['senderDeviceId'], 'device-sender-current');
      expect(decoded['transportPeerId'], 'transport-sender-current');
      expect(decoded['text'], sysText);
      expect(bridge.commandLog, contains('payload.verify'));
      expect(bridge.commandLog, contains('group.decrypt'));
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

  test(
    'group reaction notification extension preserves base v1 and verifies event parity',
    () async {
      final plaintext = jsonEncode({
        'id': 'group-reaction-add-state-1',
        'messageId': 'target-message-1',
        'emoji': '👍',
        'action': 'add',
        'senderPeerId': 'peer-sender',
        'timestamp': '2026-05-02T07:15:00.000Z',
        'eventId': 'transition-event-1',
      });
      const replayRecipients = <String>[
        'transport-author-a',
        'transport-author-b',
        'transport-bystander',
      ];

      final legacyRaw = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        payloadType: groupOfflineReplayPayloadTypeReaction,
        plaintext: plaintext,
        messageId: 'group-reaction-add-state-1',
        senderPeerId: 'peer-sender',
        senderPublicKey: 'pk-sender',
        senderPrivateKey: 'sk-sender',
        senderDeviceId: 'device-sender',
        senderTransportPeerId: 'transport-sender',
        recipientPeerIds: replayRecipients,
      );
      final upgradedRaw = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        payloadType: groupOfflineReplayPayloadTypeReaction,
        plaintext: plaintext,
        messageId: 'group-reaction-add-state-1',
        senderPeerId: 'peer-sender',
        senderPublicKey: 'pk-sender',
        senderPrivateKey: 'sk-sender',
        senderDeviceId: 'device-sender',
        senderTransportPeerId: 'transport-sender',
        recipientPeerIds: replayRecipients,
        reactionNotificationExtension:
            const GroupReactionNotificationExtensionInput(
              transitionId: 'transition-event-1',
              action: 'add',
              targetMessageId: 'target-message-1',
              reactorPeerId: 'peer-sender',
              reactorTransportPeerId: 'transport-sender',
              notificationRecipientTransportPeerIds: [
                'transport-author-a',
                'transport-author-b',
              ],
            ),
      );

      final legacy = jsonDecode(legacyRaw) as Map<String, dynamic>;
      final upgraded = jsonDecode(upgradedRaw) as Map<String, dynamic>;
      final upgradedBase = Map<String, dynamic>.from(upgraded)
        ..remove('notificationExtension');
      expect(upgradedBase, legacy);

      final extension =
          upgraded['notificationExtension'] as Map<String, dynamic>;
      expect(extension['version'], 1);
      expect(extension['transitionId'], 'transition-event-1');
      expect(extension['action'], 'add');
      expect(extension['targetMessageId'], 'target-message-1');
      expect(extension['reactorPeerId'], 'peer-sender');
      expect(extension['reactorTransportPeerId'], 'transport-sender');
      expect(extension['notificationRecipientTransportPeerIds'], [
        'transport-author-a',
        'transport-author-b',
      ]);
      expect(extension['signedPayload'], isA<String>());
      expect(extension['signature'], 'fake-signature');

      // This fixture intentionally models the reader that shipped before
      // notificationExtension existed. It parses and reconstructs the literal
      // v1 base contract without calling the current replay-envelope decoder.
      // Corrupting the new extension demonstrates that the old reader ignores
      // the entire unknown top-level field, rather than accidentally relying
      // on today's extension-aware implementation.
      final frozenReaderEnvelope =
          jsonDecode(upgradedRaw) as Map<String, dynamic>;
      final ignoredExtension =
          Map<String, dynamic>.from(
              frozenReaderEnvelope['notificationExtension']
                  as Map<String, dynamic>,
            )
            ..['transitionId'] = 'ignored-by-pre-extension-v1-reader'
            ..['futureOptionalField'] = const {'version': 2};
      frozenReaderEnvelope['notificationExtension'] = ignoredExtension;
      frozenReaderEnvelope['futureOptionalTopLevelField'] = const {
        'ignored': true,
      };

      final frozenRead = _readFrozenPreNotificationExtensionV1Fixture(
        jsonEncode(frozenReaderEnvelope),
        expectedPlaintext: plaintext,
      );
      expect(frozenRead.messageId, 'group-reaction-add-state-1');
      expect(frozenRead.signature, 'fake-signature');
      expect(frozenRead.signedPayload, upgraded['signedPayload']);

      final changedMessageId = _cloneJsonMap(frozenReaderEnvelope)
        ..['messageId'] = 'changed-base-message-id';
      expect(
        () => _readFrozenPreNotificationExtensionV1Fixture(
          jsonEncode(changedMessageId),
          expectedPlaintext: plaintext,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('messageId'),
          ),
        ),
      );

      final changedSignedPayload = _cloneJsonMap(frozenReaderEnvelope)
        ..['signedPayload'] = '${upgraded['signedPayload']} ';
      expect(
        () => _readFrozenPreNotificationExtensionV1Fixture(
          jsonEncode(changedSignedPayload),
          expectedPlaintext: plaintext,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('signedPayload'),
          ),
        ),
      );

      final changedSignature = _cloneJsonMap(frozenReaderEnvelope)
        ..['signature'] = 'changed-base-signature';
      expect(
        () => _readFrozenPreNotificationExtensionV1Fixture(
          jsonEncode(changedSignature),
          expectedPlaintext: plaintext,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('signature'),
          ),
        ),
      );

      expect(
        await decryptGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          envelope: upgraded,
          expectedRelayPeerId: 'transport-sender',
          expectedRecipientPeerId: 'transport-author-a',
        ),
        plaintext,
      );
      expect(
        await decryptGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          envelope: legacy,
          expectedRelayPeerId: 'transport-sender',
          expectedRecipientPeerId: 'transport-author-a',
        ),
        plaintext,
      );

      final tampered = jsonDecode(upgradedRaw) as Map<String, dynamic>;
      (tampered['notificationExtension']
              as Map<String, dynamic>)['transitionId'] =
          'attacker-event';
      await expectLater(
        decryptGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          envelope: tampered,
          expectedRelayPeerId: 'transport-sender',
        ),
        throwsA(
          isA<GroupOfflineReplaySignatureException>().having(
            (error) => error.reason,
            'reason',
            'notification_signed_payload_mismatch',
          ),
        ),
      );
    },
  );
}

/// Frozen wire reader for the pre-notification-extension v1 fixture above.
///
/// Keep this independent from [decryptGroupOfflineReplayEnvelope], the current
/// envelope constants, and the production canonicalizer. Its literal schema is
/// the compatibility sentinel: a base v1 wire-contract change must make this
/// reader reject the newly built envelope, while unknown top-level fields stay
/// ignorable as they were for the original reader.
_FrozenPreNotificationExtensionV1Envelope
_readFrozenPreNotificationExtensionV1Fixture(
  String rawEnvelope, {
  required String expectedPlaintext,
}) {
  final decoded = jsonDecode(rawEnvelope);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('frozen v1 envelope must be a JSON object');
  }

  _expectFrozenV1Field(decoded, 'kind', 'group_offline_replay');
  _expectFrozenV1Field(decoded, 'version', 1);
  _expectFrozenV1Field(decoded, 'groupId', 'group-1');
  _expectFrozenV1Field(decoded, 'payloadType', 'group_reaction');
  _expectFrozenV1Field(decoded, 'keyEpoch', 7);
  _expectFrozenV1Field(decoded, 'messageId', 'group-reaction-add-state-1');
  _expectFrozenV1Field(decoded, 'senderPeerId', 'peer-sender');
  _expectFrozenV1Field(decoded, 'senderDeviceId', 'device-sender');
  _expectFrozenV1Field(decoded, 'senderTransportPeerId', 'transport-sender');
  _expectFrozenV1Field(decoded, 'senderPublicKey', 'pk-sender');
  _expectFrozenV1Field(decoded, 'signatureAlgorithm', 'ed25519');

  const expectedRecipients = <String>[
    'transport-author-a',
    'transport-author-b',
    'transport-bystander',
  ];
  final recipients = decoded['recipientPeerIds'];
  if (recipients is! List ||
      jsonEncode(recipients) != jsonEncode(expectedRecipients)) {
    throw const FormatException('frozen v1 field recipientPeerIds changed');
  }

  final ciphertext = _readFrozenV1String(decoded, 'ciphertext');
  final nonce = _readFrozenV1String(decoded, 'nonce');
  if (ciphertext != expectedPlaintext) {
    throw const FormatException('frozen v1 ciphertext contract changed');
  }
  _expectFrozenV1Field(decoded, 'nonce', 'fake-group-nonce');

  final expectedRecipientSetHash = _frozenV1Hash(
    jsonEncode(expectedRecipients),
  );
  _expectFrozenV1Field(decoded, 'recipientSetHash', expectedRecipientSetHash);

  // Keys are written in the exact lexicographic order used by the original v1
  // canonical signed-payload format. This does not call today's canonicalizer.
  final expectedSignedPayload = jsonEncode(<String, Object?>{
    'ciphertextHash': _frozenV1Hash(ciphertext),
    'groupId': 'group-1',
    'keyEpoch': 7,
    'kind': 'group_offline_replay',
    'messageId': 'group-reaction-add-state-1',
    'nonceHash': _frozenV1Hash(nonce),
    'payloadType': 'group_reaction',
    'plaintextHash': _frozenV1Hash(expectedPlaintext),
    'recipientSetHash': expectedRecipientSetHash,
    'schemaVersion': 1,
    'senderDeviceId': 'device-sender',
    'senderPeerId': 'peer-sender',
    'senderSigningPublicKey': 'pk-sender',
    'senderTransportPeerId': 'transport-sender',
  });
  final signedPayload = _readFrozenV1String(decoded, 'signedPayload');
  if (signedPayload != expectedSignedPayload) {
    throw const FormatException('frozen v1 canonical signedPayload changed');
  }

  final signature = _readFrozenV1String(decoded, 'signature');
  if (signature != 'fake-signature') {
    throw const FormatException('frozen v1 signature contract changed');
  }

  return _FrozenPreNotificationExtensionV1Envelope(
    messageId: decoded['messageId'] as String,
    signedPayload: signedPayload,
    signature: signature,
  );
}

void _expectFrozenV1Field(
  Map<String, dynamic> envelope,
  String field,
  Object expected,
) {
  if (envelope[field] != expected) {
    throw FormatException('frozen v1 field $field changed');
  }
}

String _readFrozenV1String(Map<String, dynamic> envelope, String field) {
  final value = envelope[field];
  if (value is! String || value.isEmpty) {
    throw FormatException('frozen v1 field $field changed');
  }
  return value;
}

String _frozenV1Hash(String value) =>
    sha256.convert(utf8.encode(value)).toString();

Map<String, dynamic> _cloneJsonMap(Map<String, dynamic> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>;

class _FrozenPreNotificationExtensionV1Envelope {
  const _FrozenPreNotificationExtensionV1Envelope({
    required this.messageId,
    required this.signedPayload,
    required this.signature,
  });

  final String messageId;
  final String signedPayload;
  final String signature;
}
