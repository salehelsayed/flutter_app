import 'dart:convert';

import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';

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
      'role': 'member',
      'publicKey': 'bobPubKey64',
      'mlKemPublicKey': 'bobMlKem64',
    },
  ],
  'createdBy': '12D3KooWAlice',
  'createdAt': '2026-03-02T00:00:00.000Z',
};

/// A [FakeP2PService] that delays each sendMessage by [delay].
class _SlowFakeP2PService extends FakeP2PService {
  final Duration delay;

  _SlowFakeP2PService({
    required this.delay,
    super.initialState,
    super.sendMessageResult,
  });

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    await Future.delayed(delay);
    return super.sendMessage(peerId, message);
  }
}

/// A bridge that throws on encrypt for a specific ML-KEM public key.
class _ThrowOnKeyBridge extends PassthroughCryptoBridge {
  final String throwForKey;

  _ThrowOnKeyBridge({required this.throwForKey});

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'message.encrypt') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      if (payload['recipientPublicKey'] == throwForKey) {
        sendCallCount++;
        lastSentMessage = message;
        lastCommand = cmd;
        throw Exception('Encrypt failed for key $throwForKey');
      }
    }
    return super.send(message);
  }
}

/// A bridge that returns ok=false for message.encrypt
class _FailEncryptBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastSentMessage = message;

    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    lastCommand = cmd;

    if (cmd == 'message.encrypt') {
      return jsonEncode({
        'ok': false,
        'errorCode': 'ENCRYPT_FAILED',
        'errorMessage': 'Cannot encrypt',
      });
    }

    return super.send(message);
  }
}

void main() {
  late FakeP2PService p2pService;
  late PassthroughCryptoBridge bridge;

  setUp(() {
    p2pService = FakeP2PService(initialState: const NodeState(isStarted: true));
    bridge = PassthroughCryptoBridge();
  });

  tearDown(() {
    p2pService.dispose();
  });

  group('sendGroupInvite', () {
    // --- Cycle 5.1 ---
    test(
      'encrypts invite payload and sends to recipient via p2pService',
      () async {
        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: _testGroupConfig,
        );

        expect(result, equals(SendGroupInviteResult.success));

        // p2pService.sendMessage was called with the recipient
        expect(p2pService.sendMessageCallCount, equals(1));
        expect(p2pService.lastSendMessagePeerId, equals('12D3KooWBob'));

        // The sent message is a v2 group_invite envelope
        final sentContent = p2pService.lastSendMessageContent!;
        final parsed = GroupInvitePayload.parseEncryptedEnvelope(sentContent);
        expect(parsed, isNotNull);
        expect(parsed!['type'], equals('group_invite'));
        expect(parsed['version'], equals('2'));
        expect(parsed['id'], isA<String>());
        expect(parsed['senderUsername'], equals('Alice'));
        expect(parsed['groupId'], equals('grp-abc123'));
        expect(parsed['groupName'], equals('Book Club'));
      },
    );

    // --- Cycle 5.2 ---
    test(
      'returns encryptionRequired when recipientMlKemPublicKey is null',
      () async {
        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: null,
          senderPeerId: '12D3KooWAlice',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: _testGroupConfig,
        );

        expect(result, equals(SendGroupInviteResult.encryptionRequired));
        expect(p2pService.sendMessageCallCount, equals(0));
      },
    );

    // --- Cycle 5.3 ---
    test('returns nodeNotRunning when p2pService is not started', () async {
      final stoppedP2P = FakeP2PService(initialState: NodeState.stopped);

      final result = await sendGroupInvite(
        p2pService: stoppedP2P,
        bridge: bridge,
        recipientPeerId: '12D3KooWBob',
        recipientMlKemPublicKey: 'bobMlKem64',
        senderPeerId: '12D3KooWAlice',
        senderUsername: 'Alice',
        groupId: 'grp-abc123',
        groupKey: 'base64GroupKey==',
        keyEpoch: 1,
        groupConfig: _testGroupConfig,
      );

      expect(result, equals(SendGroupInviteResult.nodeNotRunning));
      stoppedP2P.dispose();
    });

    // --- Cycle 5.4 ---
    test('returns sendFailed when bridge encrypt returns ok=false', () async {
      final failBridge = _FailEncryptBridge();

      final result = await sendGroupInvite(
        p2pService: p2pService,
        bridge: failBridge,
        recipientPeerId: '12D3KooWBob',
        recipientMlKemPublicKey: 'bobMlKem64',
        senderPeerId: '12D3KooWAlice',
        senderUsername: 'Alice',
        groupId: 'grp-abc123',
        groupKey: 'base64GroupKey==',
        keyEpoch: 1,
        groupConfig: _testGroupConfig,
      );

      expect(result, equals(SendGroupInviteResult.sendFailed));
    });

    // --- Cycle 5.5 ---
    test(
      'returns sendFailed when p2pService returns false and inbox fails',
      () async {
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = false;

        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: _testGroupConfig,
        );

        expect(result, equals(SendGroupInviteResult.sendFailed));
      },
    );

    // --- Cycle 5.6 ---
    test('stores invite in inbox when direct send fails', () async {
      p2pService.sendMessageResult = false;
      p2pService.storeInInboxResult = true;

      final result = await sendGroupInvite(
        p2pService: p2pService,
        bridge: bridge,
        recipientPeerId: '12D3KooWBob',
        recipientMlKemPublicKey: 'bobMlKem64',
        senderPeerId: '12D3KooWAlice',
        senderUsername: 'Alice',
        groupId: 'grp-abc123',
        groupKey: 'base64GroupKey==',
        keyEpoch: 1,
        groupConfig: _testGroupConfig,
      );

      expect(result, equals(SendGroupInviteResult.success));

      expect(p2pService.storeInInboxCallCount, equals(1));
      expect(p2pService.lastStoreInInboxPeerId, equals('12D3KooWBob'));

      // The inbox message is a v2 group_invite envelope
      final inboxContent = p2pService.lastStoreInInboxMessage!;
      final parsed = GroupInvitePayload.parseEncryptedEnvelope(inboxContent);
      expect(parsed, isNotNull);
      expect(parsed!['id'], isA<String>());
      expect(parsed['senderUsername'], equals('Alice'));
      expect(parsed['groupId'], equals('grp-abc123'));
      expect(parsed['groupName'], equals('Book Club'));
    });

    // --- Cycle 5.7 ---
    test(
      'invite payload includes full groupConfig with members array',
      () async {
        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: _testGroupConfig,
        );

        expect(result, equals(SendGroupInviteResult.success));

        // With PassthroughCryptoBridge, ciphertext == plaintext (inner JSON)
        final sentContent = p2pService.lastSendMessageContent!;
        final envelope = jsonDecode(sentContent) as Map<String, dynamic>;
        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final innerJson = encrypted['ciphertext'] as String;

        final inner = jsonDecode(innerJson) as Map<String, dynamic>;
        expect(inner['groupId'], equals('grp-abc123'));
        expect(inner['groupKey'], equals('base64GroupKey=='));
        expect(inner['keyEpoch'], equals(1));

        final config = inner['groupConfig'] as Map<String, dynamic>;
        expect(config['name'], equals('Book Club'));
        final members = config['members'] as List<dynamic>;
        expect(members, hasLength(2));

        final firstMember = members[0] as Map<String, dynamic>;
        expect(firstMember['peerId'], equals('12D3KooWAlice'));
        expect(firstMember['role'], equals('admin'));
        expect(firstMember['publicKey'], equals('alicePubKey64'));
        expect(firstMember['mlKemPublicKey'], equals('aliceMlKem64'));
      },
    );
  });

  group('sendGroupInvitesInParallel', () {
    const sharedArgs = (
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      groupId: 'grp-abc123',
      groupKey: 'base64GroupKey==',
      keyEpoch: 1,
      groupConfig: _testGroupConfig,
    );

    test('sends invites to all recipients and returns success count', () async {
      final recipients = [
        (peerId: '12D3KooWBob', mlKemPublicKey: 'bobMlKem64' as String?),
        (
          peerId: '12D3KooWCharlie',
          mlKemPublicKey: 'charlieMlKem64' as String?,
        ),
      ];

      final sent = await sendGroupInvitesInParallel(
        p2pService: p2pService,
        bridge: bridge,
        senderPeerId: sharedArgs.senderPeerId,
        senderUsername: sharedArgs.senderUsername,
        groupId: sharedArgs.groupId,
        groupKey: sharedArgs.groupKey,
        keyEpoch: sharedArgs.keyEpoch,
        groupConfig: sharedArgs.groupConfig,
        recipients: recipients,
      );

      expect(sent, equals(2));
      expect(p2pService.sentMessageLog.length, equals(2));
    });

    test('runs invites concurrently', () async {
      final slowP2P = _SlowFakeP2PService(
        delay: const Duration(milliseconds: 100),
        initialState: const NodeState(isStarted: true),
      );

      final recipients = [
        (peerId: '12D3KooWBob', mlKemPublicKey: 'bobMlKem64' as String?),
        (
          peerId: '12D3KooWCharlie',
          mlKemPublicKey: 'charlieMlKem64' as String?,
        ),
        (peerId: '12D3KooWDave', mlKemPublicKey: 'daveMlKem64' as String?),
      ];

      final sw = Stopwatch()..start();
      final sent = await sendGroupInvitesInParallel(
        p2pService: slowP2P,
        bridge: bridge,
        senderPeerId: sharedArgs.senderPeerId,
        senderUsername: sharedArgs.senderUsername,
        groupId: sharedArgs.groupId,
        groupKey: sharedArgs.groupKey,
        keyEpoch: sharedArgs.keyEpoch,
        groupConfig: sharedArgs.groupConfig,
        recipients: recipients,
      );
      sw.stop();

      expect(sent, equals(3));
      expect(slowP2P.sentMessageLog.length, equals(3));
      // Sequential would be ~300ms+; parallel should be ~100ms
      expect(sw.elapsedMilliseconds, lessThan(250));

      slowP2P.dispose();
    });

    test('counts only successful invites when some fail', () async {
      final recipients = [
        (peerId: '12D3KooWBob', mlKemPublicKey: 'bobMlKem64' as String?),
        (peerId: '12D3KooWNoKey', mlKemPublicKey: null as String?),
        (
          peerId: '12D3KooWCharlie',
          mlKemPublicKey: 'charlieMlKem64' as String?,
        ),
      ];

      final sent = await sendGroupInvitesInParallel(
        p2pService: p2pService,
        bridge: bridge,
        senderPeerId: sharedArgs.senderPeerId,
        senderUsername: sharedArgs.senderUsername,
        groupId: sharedArgs.groupId,
        groupKey: sharedArgs.groupKey,
        keyEpoch: sharedArgs.keyEpoch,
        groupConfig: sharedArgs.groupConfig,
        recipients: recipients,
      );

      expect(sent, equals(2));
    });

    test('returns 0 for empty recipients list', () async {
      final sent = await sendGroupInvitesInParallel(
        p2pService: p2pService,
        bridge: bridge,
        senderPeerId: sharedArgs.senderPeerId,
        senderUsername: sharedArgs.senderUsername,
        groupId: sharedArgs.groupId,
        groupKey: sharedArgs.groupKey,
        keyEpoch: sharedArgs.keyEpoch,
        groupConfig: sharedArgs.groupConfig,
        recipients: [],
      );

      expect(sent, equals(0));
      expect(p2pService.sendMessageCallCount, equals(0));
    });

    test('continues sending when one invite throws', () async {
      final throwBridge = _ThrowOnKeyBridge(throwForKey: 'badKey');

      final recipients = [
        (peerId: '12D3KooWBob', mlKemPublicKey: 'bobMlKem64' as String?),
        (peerId: '12D3KooWEvil', mlKemPublicKey: 'badKey' as String?),
        (
          peerId: '12D3KooWCharlie',
          mlKemPublicKey: 'charlieMlKem64' as String?,
        ),
      ];

      final sent = await sendGroupInvitesInParallel(
        p2pService: p2pService,
        bridge: throwBridge,
        senderPeerId: sharedArgs.senderPeerId,
        senderUsername: sharedArgs.senderUsername,
        groupId: sharedArgs.groupId,
        groupKey: sharedArgs.groupKey,
        keyEpoch: sharedArgs.keyEpoch,
        groupConfig: sharedArgs.groupConfig,
        recipients: recipients,
      );

      expect(sent, equals(2));
      expect(p2pService.sentMessageLog.length, equals(2));
    });
  });
}
