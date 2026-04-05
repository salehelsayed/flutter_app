import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
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

GroupInvitePayload _makePayload({
  String groupId = 'grp-abc123',
  String? overrideGroupKey,
}) {
  return GroupInvitePayload(
    id: 'invite-uuid-001',
    groupId: groupId,
    groupKey: overrideGroupKey ?? 'base64GroupKey==',
    keyEpoch: 1,
    groupConfig: _testGroupConfig,
    senderPeerId: '12D3KooWAlice',
    senderUsername: 'Alice',
    timestamp: '2026-03-02T12:00:00.000Z',
  );
}

ChatMessage _makeV1Message({GroupInvitePayload? payload}) {
  final p = payload ?? _makePayload();
  return ChatMessage(
    from: p.senderPeerId,
    to: 'myPeerId',
    content: p.toJson(),
    timestamp: DateTime.now().toUtc().toIso8601String(),
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
    to: 'myPeerId',
    content: envelope,
    timestamp: DateTime.now().toUtc().toIso8601String(),
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
    // --- Cycle 4.1 ---
    test(
      'persists group, members, and key for a valid invite payload',
      () async {
        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
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
      'persists avatar metadata and downloaded path when invite carries it',
      () async {
        final groupConfigWithAvatar = {
          ..._testGroupConfig,
          'avatarBlobId': 'blob-1',
          'avatarMime': 'image/jpeg',
          'metadataUpdatedAt': '2026-04-05T12:25:00.000Z',
        };
        final payload = GroupInvitePayload(
          id: 'invite-uuid-002',
          groupId: 'grp-avatar',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: groupConfigWithAvatar,
          senderPeerId: '12D3KooWAlice',
          senderUsername: 'Alice',
          timestamp: '2026-03-02T12:00:00.000Z',
        );

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV1Message(payload: payload),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
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

      final (result, _) = await handleIncomingGroupInvite(
        message: _makeV1Message(),
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      expect(result, equals(HandleGroupInviteResult.duplicateGroup));

      // Group is unchanged
      final group = await groupRepo.getGroup('grp-abc123');
      expect(group!.name, equals('Original Name'));
      expect(group.createdBy, equals('12D3KooWOriginal'));

      // Bridge group:join NOT called
      expect(bridge.lastCommand, isNull);
    });

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
        );

        final group = await groupRepo.getGroup('grp-abc123');
        expect(group!.myRole, equals(GroupRole.member));
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
      );

      // Group IS still persisted to local DB
      final group = await groupRepo.getGroup('grp-abc123');
      expect(group, isNotNull);
      expect(group!.name, equals('Book Club'));

      expect(result, equals(HandleGroupInviteResult.bridgeError));
    });

    // --- Cycle 4.10 ---
    test('decrypts v2 invite envelope and processes inner payload', () async {
      final cryptoBridge = PassthroughCryptoBridge();

      final (result, _) = await handleIncomingGroupInvite(
        message: _makeV2Message(),
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: cryptoBridge,
        ownMlKemSecretKey: 'mySecretKey',
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

      final payload = GroupInvitePayload(
        id: 'invite-uuid-003',
        groupId: 'grp-trio',
        groupKey: 'trioKey==',
        keyEpoch: 1,
        groupConfig: threePersonConfig,
        senderPeerId: '12D3KooWAlice',
        senderUsername: 'Alice',
        timestamp: '2026-03-02T12:00:00.000Z',
      );

      final msg = _makeV1Message(payload: payload);

      final (result, groupId) = await handleIncomingGroupInvite(
        message: msg,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
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

    test(
      'handles bridge group:join timeout without losing persisted data',
      () async {
        final timeoutBridge = _TimeoutJoinBridge();

        final (result, groupId) = await handleIncomingGroupInvite(
          message: _makeV1Message(),
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: timeoutBridge,
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
  });
}
