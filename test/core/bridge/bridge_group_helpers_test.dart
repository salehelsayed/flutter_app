import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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

class _SequencedBridge extends FakeBridge {
  _SequencedBridge(this.sequences);

  final Map<String, List<Map<String, dynamic>>> sequences;

  @override
  Future<String> send(String message) {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    final queued = cmd == null ? null : sequences[cmd];
    if (cmd != null && queued != null && queued.isNotEmpty) {
      responses[cmd] = queued.removeAt(0);
    }
    return super.send(message);
  }
}

Matcher _bridgeCommandError({
  required String command,
  required String errorCode,
}) {
  return isA<BridgeCommandException>()
      .having((error) => error.command, 'command', command)
      .having((error) => error.errorCode, 'errorCode', errorCode);
}

void main() {
  late FakeBridge bridge;

  setUp(() {
    bridge = FakeBridge();
  });

  group('BB-002 NOT_INITIALIZED', () {
    Map<String, dynamic> notInitialized() => {
      'ok': false,
      'errorCode': 'NOT_INITIALIZED',
      'errorMessage': 'native node not initialized',
    };

    test('group:create preserves explicit failure response', () async {
      bridge.responses['group:create'] = notInitialized();

      final result = await callGroupCreate(
        bridge,
        name: 'Pre-init group',
        type: 'chat',
        creatorPeerId: 'peer-creator',
        creatorPublicKey: 'pk-creator',
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], 'NOT_INITIALIZED');
    });

    test('group:join preserves explicit failure for config joins', () async {
      bridge.responses['group:join'] = notInitialized();

      await expectLater(
        callGroupJoin(
          bridge,
          groupId: 'group-bb002-join',
          topicName: '/mknoon/group/group-bb002-join',
        ),
        throwsA(
          _bridgeCommandError(
            command: 'group:join',
            errorCode: 'LEGACY_JOIN_UNSUPPORTED',
          ),
        ),
      );
      expect(bridge.sendCallCount, 0);

      await expectLater(
        callGroupJoinWithConfig(
          bridge,
          groupId: 'group-bb002-join',
          groupConfig: {'name': 'Pre-init group'},
          groupKey: 'group-key',
          keyEpoch: 1,
        ),
        throwsA(
          _bridgeCommandError(
            command: 'group:join',
            errorCode: 'NOT_INITIALIZED',
          ),
        ),
      );
    });

    test('group:publish preserves explicit failure response', () async {
      bridge.responses['group:publish'] = notInitialized();

      final result = await callGroupPublish(
        bridge,
        groupId: 'group-bb002-publish',
        text: 'before native init',
        senderPeerId: 'peer-sender',
        senderPublicKey: 'pk-sender',
        senderPrivateKey: 'sk-sender',
      );

      expect(result['ok'], isFalse);
      expect(result['errorCode'], 'NOT_INITIALIZED');
    });

    test('group:updateKey preserves explicit failure exception', () async {
      bridge.responses['group:updateKey'] = notInitialized();

      await expectLater(
        callGroupUpdateKey(
          bridge,
          groupId: 'group-bb002-key',
          groupKey: 'next-key',
          keyEpoch: 2,
        ),
        throwsA(
          _bridgeCommandError(
            command: 'group:updateKey',
            errorCode: 'NOT_INITIALIZED',
          ),
        ),
      );
    });

    test('group:inboxRetrieve preserves explicit failure exception', () async {
      bridge.responses['group:inboxRetrieve'] = notInitialized();

      await expectLater(
        callGroupInboxRetrieve(bridge, 'group-bb002-inbox', 0),
        throwsA(
          _bridgeCommandError(
            command: 'group:inboxRetrieve',
            errorCode: 'NOT_INITIALIZED',
          ),
        ),
      );
    });
  });

  group('BB-015 structured native failures', () {
    test('BB-015 group helpers surface structured native failures', () async {
      bridge.responses['group:create'] = {
        'ok': false,
        'errorCode': 'NULL_RESPONSE',
        'errorMessage': 'Native bridge returned null',
      };
      final createResult = await callGroupCreate(
        bridge,
        name: 'BB-015 create failure',
        type: 'chat',
        creatorPeerId: 'peer-bb015',
        creatorPublicKey: 'pk-bb015',
        creatorMlKemPublicKey: 'mlkem-bb015',
      );
      expect(createResult['ok'], isFalse);
      expect(createResult['errorCode'], 'NULL_RESPONSE');

      bridge.responses['group:join'] = {
        'ok': false,
        'errorCode': 'MISSING_PLUGIN',
        'errorMessage': 'Rebuild the app with the updated native bridge.',
      };
      await expectLater(
        callGroupJoinWithConfig(
          bridge,
          groupId: 'group-bb015',
          groupConfig: {'members': <Map<String, dynamic>>[]},
          groupKey: 'group-key',
          keyEpoch: 1,
        ),
        throwsA(
          _bridgeCommandError(
            command: 'group:join',
            errorCode: 'MISSING_PLUGIN',
          ),
        ),
      );

      bridge.responses['group:publish'] = {
        'ok': false,
        'errorCode': 'PLATFORM_ERROR',
        'errorMessage': 'Platform channel error',
      };
      final publishResult = await callGroupPublish(
        bridge,
        groupId: 'group-bb015',
        text: 'publish fails explicitly',
        senderPeerId: 'peer-bb015',
        senderPublicKey: 'pk-bb015',
        senderPrivateKey: 'sk-bb015',
      );
      expect(publishResult['ok'], isFalse);
      expect(publishResult['errorCode'], 'PLATFORM_ERROR');

      bridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'MALFORMED_RESPONSE',
        'errorMessage': 'Native bridge returned malformed JSON',
      };
      await expectLater(
        callGroupInboxStore(bridge, 'group-bb015', 'message-body'),
        throwsA(
          _bridgeCommandError(
            command: 'group:inboxStore',
            errorCode: 'MALFORMED_RESPONSE',
          ),
        ),
      );

      bridge.responses['group.keygen'] = {
        'ok': false,
        'errorCode': 'GROUP_ERROR',
        'errorMessage': 'native keygen failed',
      };
      await expectLater(
        callGroupKeygen(bridge),
        throwsA(
          _bridgeCommandError(
            command: 'group.keygen',
            errorCode: 'GROUP_ERROR',
          ),
        ),
      );
    });
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

    test(
      'BB-005 callGroupCreate preserves unsupported group type rejection',
      () async {
        bridge.responses['group:create'] = {
          'ok': false,
          'errorCode': 'INVALID_INPUT',
          'errorMessage': 'unsupported groupType: public',
        };

        final result = await callGroupCreate(
          bridge,
          name: 'Unsupported Group',
          type: 'public',
          creatorPeerId: 'peer-bb005-creator',
          creatorPublicKey: 'pk-bb005-creator',
          creatorMlKemPublicKey: 'mlkem-pk-bb005-creator',
        );

        expect(result['ok'], isFalse);
        expect(result['errorCode'], 'INVALID_INPUT');
        expect(result['errorMessage'], contains('public'));
        expect(result, isNot(contains('groupId')));
        expect(result, isNot(contains('topicName')));
        expect(result, isNot(contains('groupKey')));
        expect(result, isNot(contains('keyEpoch')));
        expect(result, isNot(contains('groupConfig')));
        expect(bridge.commandLog, ['group:create']);

        final sent =
            jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
        expect(sent['cmd'], 'group:create');
        final payload = sent['payload'] as Map<String, dynamic>;
        expect(payload['groupType'], 'public');
      },
    );

    test('BB-013 group:create timeout returns explicit failure map', () async {
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
      'BB-004 preserves coherent create state and publishes with created group id',
      () async {
        const groupId = 'bb004-helper-group-id';
        const groupKey = 'bb004-helper-group-key-base64';
        final groupConfig = <String, dynamic>{
          'name': 'BB-004 Helper Group',
          'groupType': 'chat',
          'createdBy': 'peer-bb004-creator',
          'createdAt': '2026-05-10T20:00:00Z',
          'members': [
            {
              'peerId': 'peer-bb004-creator',
              'role': 'admin',
              'publicKey': 'pk-bb004-creator',
              'mlKemPublicKey': 'mlkem-pk-bb004-creator',
            },
          ],
        };

        bridge.responses['group:create'] = {
          'ok': true,
          'groupId': groupId,
          'groupConfig': groupConfig,
          'groupKey': groupKey,
          'keyEpoch': 1,
        };

        final createResult = await callGroupCreate(
          bridge,
          name: 'BB-004 Helper Group',
          type: 'chat',
          creatorPeerId: 'peer-bb004-creator',
          creatorPublicKey: 'pk-bb004-creator',
          creatorMlKemPublicKey: 'mlkem-pk-bb004-creator',
        );

        expect(createResult['ok'], isTrue);
        expect(createResult['groupId'], groupId);
        expect(createResult['groupConfig'], equals(groupConfig));
        expect(createResult['groupKey'], groupKey);
        expect(createResult['keyEpoch'], 1);

        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'bb004-first-message-id',
          'topicPeers': 0,
        };

        final publishResult = await callGroupPublish(
          bridge,
          groupId: createResult['groupId'] as String,
          text: 'BB-004 first publish',
          senderPeerId: 'peer-bb004-creator',
          senderPublicKey: 'pk-bb004-creator',
          senderPrivateKey: 'sk-bb004-creator',
          senderUsername: 'BB-004 Creator',
        );

        expect(publishResult['ok'], isTrue);
        expect(publishResult['messageId'], 'bb004-first-message-id');
        expect(publishResult['topicPeers'], 0);
        expect(bridge.commandLog, ['group:create', 'group:publish']);

        final createMessage =
            jsonDecode(bridge.sentMessages[0]) as Map<String, dynamic>;
        expect(createMessage['cmd'], 'group:create');
        final createPayload = createMessage['payload'] as Map<String, dynamic>;
        expect(createPayload['name'], 'BB-004 Helper Group');
        expect(createPayload['groupType'], 'chat');
        expect(createPayload['creatorPeerId'], 'peer-bb004-creator');
        expect(createPayload['creatorPublicKey'], 'pk-bb004-creator');
        expect(
          createPayload['creatorMlKemPublicKey'],
          'mlkem-pk-bb004-creator',
        );

        final publishMessage =
            jsonDecode(bridge.sentMessages[1]) as Map<String, dynamic>;
        expect(publishMessage['cmd'], 'group:publish');
        final publishPayload =
            publishMessage['payload'] as Map<String, dynamic>;
        expect(publishPayload['groupId'], groupId);
        expect(publishPayload['text'], 'BB-004 first publish');
        expect(publishPayload['senderPeerId'], 'peer-bb004-creator');
        expect(publishPayload['senderPublicKey'], 'pk-bb004-creator');
        expect(publishPayload['senderPrivateKey'], 'sk-bb004-creator');
      },
    );

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

    test('BB-013 group:publish timeout returns explicit failure map', () async {
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
    test('BB-006 rejects topic-name-only helper before bridge send', () async {
      bridge.responses['group:join'] = {'ok': true};

      await expectLater(
        callGroupJoin(
          bridge,
          groupId: 'grp-join-001',
          topicName: '/mknoon/group/grp-join-001',
        ),
        throwsA(
          _bridgeCommandError(
            command: 'group:join',
            errorCode: 'LEGACY_JOIN_UNSUPPORTED',
          ),
        ),
      );
      expect(bridge.sendCallCount, 0);
      expect(bridge.lastSentMessage, isNull);
    });

    test('fails locally instead of waiting on a slow bridge', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupJoin(
          slowBridge,
          groupId: 'grp-slow',
          topicName: '/mknoon/group/grp-slow',
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(
          _bridgeCommandError(
            command: 'group:join',
            errorCode: 'LEGACY_JOIN_UNSUPPORTED',
          ),
        ),
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

    test('BB-013 group:join timeout rethrows TimeoutException', () async {
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
      'BB-016 group create and update config preserve metadata fields',
      () async {
        bridge.responses['group:create'] = {
          'ok': true,
          'groupId': 'bb016-helper-group',
          'topicName': '/mknoon/group/bb016-helper-group',
          'groupConfig': {
            'name': 'BB-016 Helper',
            'groupType': 'chat',
            'description': 'Native description echo',
          },
        };

        await callGroupCreate(
          bridge,
          name: 'BB-016 Helper',
          type: 'chat',
          creatorPeerId: 'peer-bb016-admin',
          creatorPublicKey: 'pk-bb016-admin',
          creatorMlKemPublicKey: 'mlkem-bb016-admin',
          description: 'Native description echo',
        );

        final createMessage =
            jsonDecode(bridge.sentMessages.single) as Map<String, dynamic>;
        final createPayload = createMessage['payload'] as Map<String, dynamic>;
        expect(createPayload['description'], 'Native description echo');
        expect(createPayload['creatorMlKemPublicKey'], 'mlkem-bb016-admin');

        final config = <String, dynamic>{
          'name': 'BB-016 Helper Updated',
          'groupType': 'chat',
          'description': 'Updated helper description',
          'avatarBlobId': 'blob-bb016-avatar',
          'avatarMime': 'image/png',
          'metadataUpdatedAt': '2026-05-15T10:42:00.000Z',
          'configVersion': '2026-05-15T10:42:00.000Z',
          'stateHash': 'bb016-helper-state-hash',
          'members': [
            {
              'peerId': 'peer-bb016-admin',
              'role': 'admin',
              'publicKey': 'pk-bb016-admin',
              'mlKemPublicKey': 'mlkem-bb016-admin',
            },
          ],
          'createdBy': 'peer-bb016-admin',
          'createdAt': '2026-05-15T09:42:00.000Z',
        };

        await callGroupUpdateConfig(
          bridge,
          groupId: 'bb016-helper-group',
          groupConfig: config,
        );

        final updateMessage =
            jsonDecode(bridge.sentMessages.last) as Map<String, dynamic>;
        expect(updateMessage['cmd'], 'group:updateConfig');
        final updatePayload = updateMessage['payload'] as Map<String, dynamic>;
        expect(updatePayload['groupId'], 'bb016-helper-group');
        expect(updatePayload['groupConfig'], equals(config));
      },
    );

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

    test(
      'BB-013 group:updateConfig timeout rethrows TimeoutException',
      () async {
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
      },
    );
  });

  // ---------------------------------------------------------------------------
  // callGroupUpdateKey
  // ---------------------------------------------------------------------------
  group('callGroupUpdateKey', () {
    test('BB-013 group:updateKey timeout rethrows TimeoutException', () async {
      final slowBridge = _SlowBridge();

      expect(
        () => callGroupUpdateKey(
          slowBridge,
          groupId: 'grp-slow-key',
          groupKey: 'next-key',
          keyEpoch: 2,
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
    test(
      'KE-014 fails closed locally without sending bridge command',
      () async {
        bridge.responses['group:rotateKey'] = {
          'ok': true,
          'groupKey': 'newKeyBase64==',
          'keyEpoch': 2,
        };

        final result = await callGroupRotateKey(bridge, 'grp-rotate-001');

        expect(result['ok'], isFalse);
        expect(result['errorCode'], equals('LEGACY_ROTATE_KEY_UNSUPPORTED'));
        expect(result['errorMessage'], contains('rotateAndDistributeGroupKey'));
        expect(result.containsKey('groupKey'), isFalse);
        expect(result.containsKey('keyEpoch'), isFalse);
        expect(bridge.sendCallCount, 0);
        expect(bridge.lastSentMessage, isNull);
        expect(bridge.commandLog, isEmpty);
      },
    );
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
      'includes recipientPeerIds and omits plaintext preview fields',
      () async {
        bridge.responses['group:inboxStore'] = {'ok': true};

        await callGroupInboxStore(
          bridge,
          'grp-inbox-push',
          'encrypted-msg-data',
          recipientPeerIds: const ['peer-b', 'peer-c'],
        );

        final sent =
            jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
        final payload = sent['payload'] as Map<String, dynamic>;
        expect(payload['recipientPeerIds'], equals(['peer-b', 'peer-c']));
        expect(payload.containsKey('pushTitle'), isFalse);
        expect(payload.containsKey('pushBody'), isFalse);
      },
    );

    test('omits optional fields when recipient list is empty', () async {
      bridge.responses['group:inboxStore'] = {'ok': true};

      await callGroupInboxStore(
        bridge,
        'grp-inbox-empty',
        'encrypted-msg-data',
        recipientPeerIds: const [],
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

    test('BB-013 group:inboxStore timeout rethrows TimeoutException', () async {
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

    test(
      'BB-013 group:inboxRetrieve timeout rethrows TimeoutException',
      () async {
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
      },
    );
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

    test(
      'IR-002 parses GroupInboxPage cursor metadata for paged replay',
      () async {
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            {'messageId': 'ir002-page-1', 'text': 'IR-002 first'},
            {'messageId': 'ir002-page-2', 'text': 'IR-002 second'},
          ],
          'cursor': 'ir002-next-page',
          'historyGaps': [
            {
              'groupId': 'ir002-group',
              'gapId': 'ir002-gap',
              'missingAfterMessageId': 'ir002-page-1',
              'missingBeforeMessageId': 'ir002-page-2',
              'expectedRangeHash': 'ir002-range-hash',
              'expectedHeadMessageId': 'ir002-page-2',
              'candidateSourcePeerIds': ['peer-source'],
            },
          ],
        };

        final page = await callGroupInboxRetrieveWithCursor(
          bridge,
          'ir002-group',
          'ir002-start-cursor',
          2,
        );

        expect(
          page.messages.map((message) => message['messageId']),
          equals(['ir002-page-1', 'ir002-page-2']),
        );
        expect(page.cursor, 'ir002-next-page');
        expect(page.historyGaps, hasLength(1));
        expect(page.historyGaps.single.gapId, 'ir002-gap');
        expect(page.historyGaps.single.candidateSourcePeerIds, ['peer-source']);

        final sent =
            jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
        expect(sent['cmd'], 'group:inboxRetrieveCursor');
        final payload = sent['payload'] as Map<String, dynamic>;
        expect(payload['groupId'], 'ir002-group');
        expect(payload['cursor'], 'ir002-start-cursor');
        expect(payload['limit'], 2);
      },
    );

    test('parses valid history gap metadata from cursor response', () async {
      bridge.responses['group:inboxRetrieveCursor'] = {
        'ok': true,
        'messages': <Map<String, dynamic>>[],
        'cursor': '',
        'historyGaps': [
          {
            'groupId': 'grp-gap',
            'gapId': 'gap-1',
            'missingAfterMessageId': 'msg-before-gap',
            'missingBeforeMessageId': 'msg-after-gap',
            'expectedRangeHash': 'range-hash',
            'expectedHeadMessageId': 'msg-after-gap',
            'candidateSourcePeerIds': [' peer-source ', ''],
          },
          {
            'groupId': 'grp-gap',
            'gapId': '',
            'missingAfterMessageId': 'msg-before-gap',
            'missingBeforeMessageId': 'msg-after-gap',
            'expectedRangeHash': 'range-hash',
            'expectedHeadMessageId': 'msg-after-gap',
            'candidateSourcePeerIds': ['peer-source'],
          },
        ],
      };

      final page = await callGroupInboxRetrieveWithCursor(
        bridge,
        'grp-gap',
        'stale-cursor',
        10,
      );

      expect(page.messages, isEmpty);
      expect(page.cursor, isEmpty);
      expect(page.historyGaps, hasLength(1));

      final gap = page.historyGaps.single;
      expect(gap.groupId, equals('grp-gap'));
      expect(gap.gapId, equals('gap-1'));
      expect(gap.missingAfterMessageId, equals('msg-before-gap'));
      expect(gap.missingBeforeMessageId, equals('msg-after-gap'));
      expect(gap.expectedRangeHash, equals('range-hash'));
      expect(gap.expectedHeadMessageId, equals('msg-after-gap'));
      expect(gap.candidateSourcePeerIds, equals(['peer-source']));
    });

    test(
      'IR-010 parses and surfaces valid cursor historyGaps while filtering invalid entries',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink((payload) {
          flowEvents.add(Map<String, dynamic>.from(payload));
        });
        addTearDown(() => debugSetFlowEventSink(null));

        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': <Map<String, dynamic>>[],
          'cursor': 'ir010-next-cursor',
          'historyGaps': [
            {
              'groupId': '  ir010-group  ',
              'gapId': '  ir010-gap-valid  ',
              'missingAfterMessageId': '  ir010-before  ',
              'missingBeforeMessageId': '  ir010-after  ',
              'expectedRangeHash': '  ir010-range-hash  ',
              'expectedHeadMessageId': '  ir010-head  ',
              'candidateSourcePeerIds': [
                ' peer-source-a ',
                '',
                42,
                'peer-source-b ',
              ],
            },
            {
              'groupId': 'ir010-group',
              'gapId': '',
              'missingAfterMessageId': 'ir010-before',
              'missingBeforeMessageId': 'ir010-after',
              'expectedRangeHash': 'ir010-range-hash',
              'expectedHeadMessageId': 'ir010-head',
              'candidateSourcePeerIds': ['peer-source-a'],
            },
            {
              'groupId': 'ir010-group',
              'gapId': 'ir010-gap-no-source',
              'missingAfterMessageId': 'ir010-before',
              'missingBeforeMessageId': 'ir010-after',
              'expectedRangeHash': 'ir010-range-hash',
              'expectedHeadMessageId': 'ir010-head',
              'candidateSourcePeerIds': ['  ', 42],
            },
            {
              'groupId': 'ir010-group',
              'gapId': 'ir010-gap-missing-boundary',
              'missingAfterMessageId': 'ir010-before',
              'missingBeforeMessageId': '',
              'expectedRangeHash': 'ir010-range-hash',
              'expectedHeadMessageId': 'ir010-head',
              'candidateSourcePeerIds': ['peer-source-a'],
            },
            'not-a-gap-map',
          ],
        };

        final page = await callGroupInboxRetrieveWithCursor(
          bridge,
          'ir010-group',
          'ir010-cursor',
          20,
        );

        expect(page.messages, isEmpty);
        expect(page.cursor, 'ir010-next-cursor');
        expect(page.historyGaps, hasLength(1));

        final gap = page.historyGaps.single;
        expect(gap.groupId, 'ir010-group');
        expect(gap.gapId, 'ir010-gap-valid');
        expect(gap.missingAfterMessageId, 'ir010-before');
        expect(gap.missingBeforeMessageId, 'ir010-after');
        expect(gap.expectedRangeHash, 'ir010-range-hash');
        expect(gap.expectedHeadMessageId, 'ir010-head');
        expect(gap.candidateSourcePeerIds, ['peer-source-a', 'peer-source-b']);

        final responseEvent = flowEvents.lastWhere(
          (payload) =>
              payload['event'] ==
              'GROUP_FL_BRIDGE_INBOX_RETRIEVE_CURSOR_RESPONSE',
        );
        final details = responseEvent['details'] as Map<String, dynamic>;
        expect(details['historyGapCount'], 1);
      },
    );

    test(
      'BB-013 group:inboxRetrieveCursor timeout rethrows TimeoutException',
      () async {
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
      },
    );

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

    test('reconnects and retries transient relay EOF cursor failures', () async {
      final retryBridge = _SequencedBridge({
        'group:inboxRetrieveCursor': [
          {
            'ok': false,
            'errorCode': 'GROUP_INBOX_ERROR',
            'errorMessage':
                'all 1 relays failed, last error: read response: read length: EOF',
          },
          {
            'ok': true,
            'messages': [
              {'messageId': 'msg-after-reconnect', 'text': 'Recovered'},
            ],
            'cursor': '',
          },
        ],
      });
      retryBridge.responses['relay:reconnect'] = {
        'ok': true,
        'recoveryMode': 'in_place',
      };

      final page = await callGroupInboxRetrieveWithCursor(
        retryBridge,
        'grp-retry-cursor',
        'cursor-before-error',
        10,
        transientRetryDelay: Duration.zero,
      );

      expect(page.messages, hasLength(1));
      expect(page.messages.single['messageId'], 'msg-after-reconnect');
      expect(
        retryBridge.commandLog,
        equals([
          'group:inboxRetrieveCursor',
          'relay:reconnect',
          'group:inboxRetrieveCursor',
        ]),
      );
    });

    test(
      'transient cursor EOF shrinks page size before retrying oversized replay pages',
      () async {
        final retryBridge = _SequencedBridge({
          'group:inboxRetrieveCursor': [
            {
              'ok': false,
              'errorCode': 'GROUP_INBOX_ERROR',
              'errorMessage':
                  'all 1 relays failed, last error: read response: read length: EOF',
            },
            {
              'ok': false,
              'errorCode': 'GROUP_INBOX_ERROR',
              'errorMessage':
                  'all 1 relays failed, last error: read response: read length: EOF',
            },
            {
              'ok': true,
              'messages': [
                {'messageId': 'msg-after-limit-shrink', 'text': 'Recovered'},
              ],
              'cursor': '',
            },
          ],
        });
        retryBridge.responses['relay:reconnect'] = {
          'ok': true,
          'recoveryMode': 'in_place',
        };

        final page = await callGroupInboxRetrieveWithCursor(
          retryBridge,
          'grp-oversized-page',
          '',
          50,
          transientRetryDelay: Duration.zero,
        );

        expect(page.messages.single['messageId'], 'msg-after-limit-shrink');

        final retryLimits = retryBridge.sentMessages
            .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
            .map((message) {
              final payload = message['payload'] as Map<String, dynamic>;
              return payload['limit'] as int;
            })
            .toList(growable: false);
        expect(retryLimits, [50, 25, 12]);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Bridge error propagation (Finding 5)
  // ---------------------------------------------------------------------------
  group('BridgeCommandException on ok:false', () {
    test(
      'throws BridgeCommandException when legacy group:join is used',
      () async {
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'TOPIC_ERROR',
          'errorMessage': 'failed',
        };

        expect(
          () => callGroupJoin(bridge, groupId: 'grp-1', topicName: '/t/grp-1'),
          throwsA(
            _bridgeCommandError(
              command: 'group:join',
              errorCode: 'LEGACY_JOIN_UNSUPPORTED',
            ),
          ),
        );
        expect(bridge.sendCallCount, 0);
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
