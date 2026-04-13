import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_bridge.dart';

/// A bridge whose [send] never completes, to exercise timeout paths.
class _SlowBridge extends Bridge {
  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) {
    return Future.delayed(const Duration(hours: 1), () => '');
  }
}

void main() {
  late FakeBridge bridge;

  setUp(() {
    bridge = FakeBridge();
  });

  // ---------------------------------------------------------------------------
  // callGroupCreate  (MOST IMPORTANT — bug-fix regression tests)
  // ---------------------------------------------------------------------------
  group('callGroupCreate', () {
    test('sends group:create with correct payload fields', () async {
      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': 'grp-abc123',
        'topicName': '/mknoon/group/grp-abc123',
      };

      final result = await callGroupCreate(
        bridge,
        name: 'Book Club',
        type: 'private',
        creatorPeerId: '12D3KooWCreator',
        creatorPublicKey: 'pubKeyBase64',
        creatorMlKemPublicKey: 'mlkemPubBase64',
      );

      expect(result['ok'], isTrue);
      expect(result['groupId'], equals('grp-abc123'));
      expect(result['topicName'], equals('/mknoon/group/grp-abc123'));

      // Verify the payload that was sent to the bridge
      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group:create'));

      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['name'], equals('Book Club'));
      expect(payload['creatorPeerId'], equals('12D3KooWCreator'));
      expect(payload['creatorPublicKey'], equals('pubKeyBase64'));
      expect(payload['creatorMlKemPublicKey'], equals('mlkemPubBase64'));
    });

    test('sends groupType NOT type in the payload (bug fix)', () async {
      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': 'grp-1',
        'topicName': '/mknoon/group/grp-1',
      };

      await callGroupCreate(
        bridge,
        name: 'Test Group',
        type: 'private',
        creatorPeerId: 'peer1',
        creatorPublicKey: 'pk1',
      );

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;

      // MUST use 'groupType', NOT 'type'
      expect(payload['groupType'], equals('private'));
      expect(
        payload.containsKey('type'),
        isFalse,
        reason: 'Payload must use "groupType" not "type"',
      );
    });

    test('includes optional description when provided', () async {
      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': 'grp-desc',
        'topicName': '/mknoon/group/grp-desc',
      };

      await callGroupCreate(
        bridge,
        name: 'Described Group',
        type: 'public',
        creatorPeerId: 'peer2',
        creatorPublicKey: 'pk2',
        description: 'A group about testing',
      );

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['description'], equals('A group about testing'));
    });

    test('excludes optional fields when null', () async {
      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': 'grp-minimal',
        'topicName': '/mknoon/group/grp-minimal',
      };

      await callGroupCreate(
        bridge,
        name: 'Minimal Group',
        type: 'private',
        creatorPeerId: 'peer3',
        creatorPublicKey: 'pk3',
        // creatorMlKemPublicKey: null (default)
        // description: null (default)
      );

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;

      expect(
        payload.containsKey('creatorMlKemPublicKey'),
        isFalse,
        reason: 'creatorMlKemPublicKey should be omitted when null',
      );
      expect(
        payload.containsKey('description'),
        isFalse,
        reason: 'description should be omitted when null',
      );
    });

    test('returns parsed response on success', () async {
      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': 'grp-success',
        'topicName': '/mknoon/group/grp-success',
      };

      final result = await callGroupCreate(
        bridge,
        name: 'Success Group',
        type: 'private',
        creatorPeerId: 'peer4',
        creatorPublicKey: 'pk4',
      );

      expect(result, isA<Map<String, dynamic>>());
      expect(result['ok'], isTrue);
      expect(result['groupId'], equals('grp-success'));
      expect(result['topicName'], equals('/mknoon/group/grp-success'));
    });

    test('returns error map on bridge error', () async {
      bridge.responses['group:create'] = {
        'ok': false,
        'errorCode': 'GROUP_EXISTS',
        'errorMessage': 'Group already exists',
      };

      final result = await callGroupCreate(
        bridge,
        name: 'Dupe Group',
        type: 'private',
        creatorPeerId: 'peer5',
        creatorPublicKey: 'pk5',
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('GROUP_EXISTS'));
      expect(result['errorMessage'], equals('Group already exists'));
    });

    test('returns timeout error on timeout', () async {
      final slowBridge = _SlowBridge();

      final result = await callGroupCreate(
        slowBridge,
        name: 'Timeout Group',
        type: 'private',
        creatorPeerId: 'peer6',
        creatorPublicKey: 'pk6',
        timeout: const Duration(milliseconds: 1),
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('BRIDGE_TIMEOUT'));
      expect(result['errorMessage'], contains('timed out'));
    });

    test('includes creatorMlKemPublicKey when provided', () async {
      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': 'grp-mlkem',
        'topicName': '/mknoon/group/grp-mlkem',
      };

      await callGroupCreate(
        bridge,
        name: 'ML-KEM Group',
        type: 'private',
        creatorPeerId: 'peer7',
        creatorPublicKey: 'pk7',
        creatorMlKemPublicKey: 'mlkemPub7',
      );

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['creatorMlKemPublicKey'], equals('mlkemPub7'));
    });

    test(
      'groupType field carries the correct value for different types',
      () async {
        for (final groupType in ['private', 'public', 'broadcast']) {
          bridge.responses['group:create'] = {
            'ok': true,
            'groupId': 'grp-$groupType',
            'topicName': '/mknoon/group/grp-$groupType',
          };

          await callGroupCreate(
            bridge,
            name: '$groupType Group',
            type: groupType,
            creatorPeerId: 'peer',
            creatorPublicKey: 'pk',
          );

          final sent =
              jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
          final payload = sent['payload'] as Map<String, dynamic>;
          expect(payload['groupType'], equals(groupType));
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // callGroupKeygen
  // ---------------------------------------------------------------------------
  group('callGroupKeygen', () {
    test('sends group.keygen and returns key string on success', () async {
      bridge.responses['group.keygen'] = {
        'ok': true,
        'groupKey': 'base64SymmetricKeyData==',
      };

      final key = await callGroupKeygen(bridge);

      expect(key, equals('base64SymmetricKeyData=='));

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group.keygen'));
      expect(sent['payload'], isEmpty);
    });

    test('rethrows TimeoutException on timeout', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupKeygen(
          slowBridge,
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupPublish
  // ---------------------------------------------------------------------------
  group('callGroupPublish', () {
    test(
      'sends group:publish with correct payload and returns messageId',
      () async {
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-pub-001',
        };

        final result = await callGroupPublish(
          bridge,
          groupId: 'grp-abc123',
          text: 'Hello group!',
          senderPeerId: 'peer-123',
          senderPublicKey: 'pk-123',
          senderPrivateKey: 'sk-123',
          senderUsername: 'alice',
        );

        expect(result['ok'], isTrue);
        expect(result['messageId'], equals('msg-pub-001'));

        final sent =
            jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
        expect(sent['cmd'], equals('group:publish'));

        final sentPayload = sent['payload'] as Map<String, dynamic>;
        expect(sentPayload['groupId'], equals('grp-abc123'));
        expect(sentPayload['text'], equals('Hello group!'));
        expect(sentPayload['senderPeerId'], equals('peer-123'));
        expect(sentPayload['senderPublicKey'], equals('pk-123'));
        expect(sentPayload['senderPrivateKey'], equals('sk-123'));
        expect(sentPayload['senderUsername'], equals('alice'));
      },
    );

    test('returns error map on bridge error', () async {
      bridge.responses['group:publish'] = {
        'ok': false,
        'errorCode': 'NOT_SUBSCRIBED',
        'errorMessage': 'Not subscribed to group topic',
      };

      final result = await callGroupPublish(
        bridge,
        groupId: 'grp-unknown',
        text: 'test',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('NOT_SUBSCRIBED'));
    });

    test('returns timeout error on timeout', () async {
      final slowBridge = _SlowBridge();

      final result = await callGroupPublish(
        slowBridge,
        groupId: 'grp-slow',
        text: 'test',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        timeout: const Duration(milliseconds: 1),
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('BRIDGE_TIMEOUT'));
    });

    test('includes media in payload when provided', () async {
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-media-001',
      };

      final media = [
        {'id': 'blob-1', 'mime': 'image/jpeg', 'size': 12345},
        {'id': 'blob-2', 'mime': 'audio/mp4', 'durationMs': 5000},
      ];

      await callGroupPublish(
        bridge,
        groupId: 'grp-media',
        text: 'Check this out',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'alice',
        media: media,
      );

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['media'], isNotNull);
      expect(payload['media'], isList);
      expect((payload['media'] as List).length, 2);
      expect((payload['media'] as List)[0]['id'], 'blob-1');
    });

    test('includes quotedMessageId when provided', () async {
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-quoted-001',
      };

      await callGroupPublish(
        bridge,
        groupId: 'grp-quoted',
        text: 'Reply to parent',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        quotedMessageId: 'msg-parent-1',
      );

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['quotedMessageId'], 'msg-parent-1');
    });

    test('omits media when null', () async {
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-no-media',
      };

      await callGroupPublish(
        bridge,
        groupId: 'grp-text',
        text: 'Hello',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload.containsKey('media'), isFalse);
    });

    test('omits media when empty list', () async {
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-empty-media',
      };

      await callGroupPublish(
        bridge,
        groupId: 'grp-empty',
        text: 'Hello',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        media: [],
      );

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload.containsKey('media'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupEncrypt
  // ---------------------------------------------------------------------------
  group('callGroupEncrypt', () {
    test('sends group.encrypt with groupKey and plaintext', () async {
      bridge.responses['group.encrypt'] = {
        'ok': true,
        'ciphertext': 'encryptedBase64==',
        'nonce': 'nonceBase64==',
      };

      final result = await callGroupEncrypt(
        bridge,
        'symmetricKeyBase64==',
        'Hello group plaintext!',
      );

      expect(result['ok'], isTrue);
      expect(result['ciphertext'], equals('encryptedBase64=='));
      expect(result['nonce'], equals('nonceBase64=='));

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group.encrypt'));

      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['groupKey'], equals('symmetricKeyBase64=='));
      expect(payload['plaintext'], equals('Hello group plaintext!'));
    });

    test('returns timeout error map on timeout', () async {
      final slowBridge = _SlowBridge();

      final result = await callGroupEncrypt(
        slowBridge,
        'key',
        'plaintext',
        timeout: const Duration(milliseconds: 1),
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('BRIDGE_TIMEOUT'));
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupDecrypt
  // ---------------------------------------------------------------------------
  group('callGroupDecrypt', () {
    test('sends group.decrypt with groupKey, ciphertext, and nonce', () async {
      bridge.responses['group.decrypt'] = {
        'ok': true,
        'plaintext': 'Decrypted hello!',
      };

      final plaintext = await callGroupDecrypt(
        bridge,
        'symmetricKeyBase64==',
        'ciphertextBase64==',
        'nonceBase64==',
      );

      expect(plaintext, equals('Decrypted hello!'));

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group.decrypt'));

      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['groupKey'], equals('symmetricKeyBase64=='));
      expect(payload['ciphertext'], equals('ciphertextBase64=='));
      expect(payload['nonce'], equals('nonceBase64=='));
    });

    test('rethrows TimeoutException on timeout', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupDecrypt(
          slowBridge,
          'key',
          'ct',
          'nonce',
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupJoin
  // ---------------------------------------------------------------------------
  group('callGroupJoin', () {
    test('sends group:join with groupId and topicName', () async {
      await callGroupJoin(
        bridge,
        groupId: 'grp-join-001',
        topicName: '/mknoon/group/grp-join-001',
      );

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group:join'));

      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], equals('grp-join-001'));
      expect(payload['topicName'], equals('/mknoon/group/grp-join-001'));
    });

    test('completes without error on success', () async {
      // Default FakeBridge returns {"ok": true}
      await expectLater(
        callGroupJoin(
          bridge,
          groupId: 'grp-join-ok',
          topicName: '/mknoon/group/grp-join-ok',
        ),
        completes,
      );
    });

    test('rethrows TimeoutException on timeout', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupJoin(
          slowBridge,
          groupId: 'grp-slow',
          topicName: '/mknoon/group/grp-slow',
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupJoinWithConfig
  // ---------------------------------------------------------------------------
  group('callGroupJoinWithConfig', () {
    test(
      'sends group:join with groupId, groupConfig, groupKey, keyEpoch',
      () async {
        final config = {
          'name': 'Book Club',
          'groupType': 'chat',
          'members': [
            {'peerId': '12D3KooWAlice', 'role': 'admin'},
          ],
        };

        await callGroupJoinWithConfig(
          bridge,
          groupId: 'grp-join-cfg-001',
          groupConfig: config,
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
        );

        expect(bridge.lastCommand, equals('group:join'));

        final sent =
            jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
        expect(sent['cmd'], equals('group:join'));

        final payload = sent['payload'] as Map<String, dynamic>;
        expect(payload['groupId'], equals('grp-join-cfg-001'));
        expect(payload['groupConfig'], isA<Map<String, dynamic>>());
        expect((payload['groupConfig'] as Map)['name'], equals('Book Club'));
        expect(payload['groupKey'], equals('base64GroupKey=='));
        expect(payload['keyEpoch'], equals(1));
      },
    );

    test('completes without error on success', () async {
      await expectLater(
        callGroupJoinWithConfig(
          bridge,
          groupId: 'grp-join-cfg-ok',
          groupConfig: {'name': 'Test'},
          groupKey: 'key',
          keyEpoch: 1,
        ),
        completes,
      );
    });

    test('rethrows TimeoutException on timeout', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupJoinWithConfig(
          slowBridge,
          groupId: 'grp-slow',
          groupConfig: {'name': 'Test'},
          groupKey: 'key',
          keyEpoch: 1,
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupAcknowledgeRecovery
  // ---------------------------------------------------------------------------
  group('callGroupAcknowledgeRecovery', () {
    test('sends group:acknowledgeRecovery', () async {
      await callGroupAcknowledgeRecovery(bridge);

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group:acknowledgeRecovery'));
    });

    test('completes without error on success', () async {
      await expectLater(callGroupAcknowledgeRecovery(bridge), completes);
    });

    test('rethrows TimeoutException on timeout', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupAcknowledgeRecovery(
          slowBridge,
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupLeave
  // ---------------------------------------------------------------------------
  group('callGroupLeave', () {
    test('sends group:leave with groupId', () async {
      await callGroupLeave(bridge, 'grp-leave-001');

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group:leave'));

      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], equals('grp-leave-001'));
    });

    test('completes without error on success', () async {
      await expectLater(callGroupLeave(bridge, 'grp-leave-ok'), completes);
    });

    test('rethrows TimeoutException on timeout', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupLeave(
          slowBridge,
          'grp-slow',
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupUpdateConfig
  // ---------------------------------------------------------------------------
  group('callGroupUpdateConfig', () {
    test(
      'sends group:updateConfig with groupId and full groupConfig',
      () async {
        final config = {
          'name': 'New Name',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-1', 'role': 'admin', 'publicKey': 'pk-1'},
            {'peerId': 'peer-2', 'role': 'writer', 'publicKey': 'pk-2'},
          ],
          'createdBy': 'peer-1',
          'createdAt': '2026-01-01T00:00:00Z',
        };

        await callGroupUpdateConfig(
          bridge,
          groupId: 'grp-cfg-001',
          groupConfig: config,
        );

        final sent =
            jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
        expect(sent['cmd'], equals('group:updateConfig'));

        final payload = sent['payload'] as Map<String, dynamic>;
        expect(payload['groupId'], equals('grp-cfg-001'));
        expect(payload['groupConfig'], isNotNull);
        final sentConfig = payload['groupConfig'] as Map<String, dynamic>;
        expect(sentConfig['name'], equals('New Name'));
        expect((sentConfig['members'] as List).length, equals(2));
      },
    );

    test('rethrows TimeoutException on timeout', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupUpdateConfig(
          slowBridge,
          groupId: 'grp-slow',
          groupConfig: {'name': 'x', 'groupType': 'chat', 'members': []},
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupGenerateNextKey
  // ---------------------------------------------------------------------------
  group('callGroupGenerateNextKey', () {
    test('sends group:generateNextKey and returns key info', () async {
      bridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': 'nextKeyBase64==',
        'keyEpoch': 2,
      };

      final result = await callGroupGenerateNextKey(bridge, 'grp-generate-001');

      expect(result['ok'], isTrue);
      expect(result['keyEpoch'], equals(2));
      expect(result['groupKey'], equals('nextKeyBase64=='));

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group:generateNextKey'));
      expect(sent['payload']['groupId'], equals('grp-generate-001'));
    });

    test('returns timeout error on timeout', () async {
      final slowBridge = _SlowBridge();

      final result = await callGroupGenerateNextKey(
        slowBridge,
        'grp-slow',
        timeout: const Duration(milliseconds: 1),
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('BRIDGE_TIMEOUT'));
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupRotateKey
  // ---------------------------------------------------------------------------
  group('callGroupRotateKey legacy helper', () {
    test('sends group:rotateKey and returns key info', () async {
      bridge.responses['group:rotateKey'] = {
        'ok': true,
        'groupKey': 'newKeyBase64==',
        'keyEpoch': 2,
      };

      final result = await callGroupRotateKey(bridge, 'grp-rotate-001');

      expect(result['ok'], isTrue);
      expect(result['keyEpoch'], equals(2));
      expect(result['groupKey'], equals('newKeyBase64=='));

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group:rotateKey'));
      expect(sent['payload']['groupId'], equals('grp-rotate-001'));
    });

    test('returns timeout error on timeout', () async {
      final slowBridge = _SlowBridge();

      final result = await callGroupRotateKey(
        slowBridge,
        'grp-slow',
        timeout: const Duration(milliseconds: 1),
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], equals('BRIDGE_TIMEOUT'));
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupInboxStore
  // ---------------------------------------------------------------------------
  group('callGroupInboxStore', () {
    test('sends group:inboxStore with groupId and message', () async {
      bridge.responses['group:inboxStore'] = {'ok': true};

      await callGroupInboxStore(bridge, 'grp-inbox-001', 'encrypted-msg-data');

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group:inboxStore'));

      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], equals('grp-inbox-001'));
      expect(payload['message'], equals('encrypted-msg-data'));
    });

    test(
      'includes recipientPeerIds, pushTitle, and pushBody when provided',
      () async {
        bridge.responses['group:inboxStore'] = {'ok': true};

        await callGroupInboxStore(
          bridge,
          'grp-inbox-push',
          'encrypted-msg-data',
          recipientPeerIds: const ['peer-b', 'peer-c'],
          pushTitle: 'Test Group',
          pushBody: 'Alice: hello',
        );

        final sent =
            jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
        final payload = sent['payload'] as Map<String, dynamic>;
        expect(payload['recipientPeerIds'], equals(['peer-b', 'peer-c']));
        expect(payload['pushTitle'], equals('Test Group'));
        expect(payload['pushBody'], equals('Alice: hello'));
      },
    );

    test('omits empty optional push fields', () async {
      bridge.responses['group:inboxStore'] = {'ok': true};

      await callGroupInboxStore(
        bridge,
        'grp-inbox-empty',
        'encrypted-msg-data',
        recipientPeerIds: const [],
        pushTitle: '',
        pushBody: '',
      );

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload.containsKey('recipientPeerIds'), isFalse);
      expect(payload.containsKey('pushTitle'), isFalse);
      expect(payload.containsKey('pushBody'), isFalse);
    });

    test('throws BridgeCommandException on ok:false', () async {
      bridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'GROUP_INBOX_ERROR',
        'errorMessage': 'store failed',
      };

      expect(
        () => callGroupInboxStore(bridge, 'grp-inbox-fail', 'msg'),
        throwsA(isA<BridgeCommandException>()),
      );
    });

    test('rethrows TimeoutException on timeout', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupInboxStore(
          slowBridge,
          'grp-slow',
          'msg',
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupInboxRetrieve
  // ---------------------------------------------------------------------------
  group('callGroupInboxRetrieve', () {
    test('sends group:inboxRetrieve and returns list of messages', () async {
      bridge.responses['group:inboxRetrieve'] = {
        'ok': true,
        'messages': [
          {'id': 'msg1', 'body': 'Hello'},
          {'id': 'msg2', 'body': 'World'},
        ],
      };

      final messages = await callGroupInboxRetrieve(
        bridge,
        'grp-inbox-002',
        1700000000,
      );

      expect(messages, hasLength(2));
      expect(messages[0]['id'], equals('msg1'));
      expect(messages[1]['body'], equals('World'));

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group:inboxRetrieve'));

      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], equals('grp-inbox-002'));
      expect(payload['sinceTimestamp'], equals(1700000000));
    });

    test('returns empty list when no messages', () async {
      bridge.responses['group:inboxRetrieve'] = {'ok': true, 'messages': []};

      final messages = await callGroupInboxRetrieve(bridge, 'grp-empty', 0);

      expect(messages, isEmpty);
    });

    test('returns empty list when messages field is null', () async {
      bridge.responses['group:inboxRetrieve'] = {'ok': true};

      final messages = await callGroupInboxRetrieve(bridge, 'grp-null', 0);

      expect(messages, isEmpty);
    });

    test('throws BridgeCommandException on ok:false', () async {
      bridge.responses['group:inboxRetrieve'] = {
        'ok': false,
        'errorCode': 'GROUP_INBOX_ERROR',
        'errorMessage': 'retrieve failed',
      };

      expect(
        () => callGroupInboxRetrieve(bridge, 'grp-error', 0),
        throwsA(isA<BridgeCommandException>()),
      );
    });

    test('rethrows TimeoutException on timeout', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupInboxRetrieve(
          slowBridge,
          'grp-slow',
          0,
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // callGroupInboxRetrieveWithCursor
  // ---------------------------------------------------------------------------
  group('callGroupInboxRetrieveWithCursor', () {
    test('encodes cursor and page metadata and returns next cursor', () async {
      bridge.responses['group:inboxRetrieveCursor'] = {
        'ok': true,
        'messages': [
          {'messageId': 'msg-cursor-1', 'text': 'Hello cursor'},
        ],
        'cursor': 'opaque-next-cursor',
      };

      final page = await callGroupInboxRetrieveWithCursor(
        bridge,
        'grp-inbox-cursor',
        'opaque-prev-cursor',
        25,
      );

      expect(page.messages, hasLength(1));
      expect(page.messages.single['messageId'], equals('msg-cursor-1'));
      expect(page.cursor, equals('opaque-next-cursor'));

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['cmd'], equals('group:inboxRetrieveCursor'));

      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], equals('grp-inbox-cursor'));
      expect(payload['cursor'], equals('opaque-prev-cursor'));
      expect(payload['limit'], equals(25));
    });

    test('rethrows TimeoutException on timeout', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupInboxRetrieveWithCursor(
          slowBridge,
          'grp-slow-cursor',
          '',
          10,
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('throws BridgeCommandException on ok:false', () async {
      bridge.responses['group:inboxRetrieveCursor'] = {
        'ok': false,
        'errorCode': 'GROUP_INBOX_ERROR',
        'errorMessage': 'cursor retrieve failed',
      };

      expect(
        () => callGroupInboxRetrieveWithCursor(
          bridge,
          'grp-error-cursor',
          '',
          10,
        ),
        throwsA(isA<BridgeCommandException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Bridge error propagation (Finding 5)
  // ---------------------------------------------------------------------------
  group('BridgeCommandException on ok:false', () {
    test(
      'throws BridgeCommandException when group:join returns ok:false',
      () async {
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'TOPIC_ERROR',
          'errorMessage': 'failed',
        };

        expect(
          () => callGroupJoin(bridge, groupId: 'grp-1', topicName: '/t/grp-1'),
          throwsA(isA<BridgeCommandException>()),
        );
      },
    );

    test(
      'throws BridgeCommandException when group:join (with config) returns ok:false',
      () async {
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'CONFIG_ERROR',
          'errorMessage': 'bad config',
        };

        expect(
          () => callGroupJoinWithConfig(
            bridge,
            groupId: 'grp-1',
            groupConfig: {'name': 'Test'},
            groupKey: 'key',
            keyEpoch: 1,
          ),
          throwsA(isA<BridgeCommandException>()),
        );
      },
    );

    test(
      'throws BridgeCommandException when group:leave returns ok:false',
      () async {
        bridge.responses['group:leave'] = {
          'ok': false,
          'errorCode': 'NOT_SUBSCRIBED',
          'errorMessage': 'not in group',
        };

        expect(
          () => callGroupLeave(bridge, 'grp-1'),
          throwsA(isA<BridgeCommandException>()),
        );
      },
    );

    test(
      'throws BridgeCommandException when group:updateConfig returns ok:false',
      () async {
        bridge.responses['group:updateConfig'] = {
          'ok': false,
          'errorCode': 'PERMISSION_DENIED',
          'errorMessage': 'not admin',
        };

        expect(
          () => callGroupUpdateConfig(
            bridge,
            groupId: 'grp-1',
            groupConfig: {'name': 'x', 'groupType': 'chat', 'members': []},
          ),
          throwsA(isA<BridgeCommandException>()),
        );
      },
    );
  });
}
