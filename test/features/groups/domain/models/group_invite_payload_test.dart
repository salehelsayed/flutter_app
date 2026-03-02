import 'dart:convert';

import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testGroupConfig = {
    'name': 'Book Club',
    'groupType': 'chat',
    'description': 'A test group',
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

  GroupInvitePayload makePayload() {
    return const GroupInvitePayload(
      id: 'invite-uuid-001',
      groupId: 'grp-abc123',
      groupKey: 'base64GroupKey==',
      keyEpoch: 1,
      groupConfig: testGroupConfig,
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      timestamp: '2026-03-02T12:00:00.000Z',
    );
  }

  group('GroupInvitePayload', () {
    // --- Cycle 1.1 ---
    test('toInnerJson serializes all required fields', () {
      final payload = makePayload();
      final json = payload.toInnerJson();
      final map = jsonDecode(json) as Map<String, dynamic>;

      expect(map['id'], equals('invite-uuid-001'));
      expect(map['groupId'], equals('grp-abc123'));
      expect(map['groupKey'], equals('base64GroupKey=='));
      expect(map['keyEpoch'], equals(1));
      expect(map['senderPeerId'], equals('12D3KooWAlice'));
      expect(map['senderUsername'], equals('Alice'));
      expect(map['timestamp'], equals('2026-03-02T12:00:00.000Z'));

      final config = map['groupConfig'] as Map<String, dynamic>;
      expect(config['name'], equals('Book Club'));
      expect(config['groupType'], equals('chat'));
      expect(config['createdBy'], equals('12D3KooWAlice'));
      expect(config['createdAt'], equals('2026-03-02T00:00:00.000Z'));

      final members = config['members'] as List<dynamic>;
      expect(members, hasLength(2));
      final firstMember = members[0] as Map<String, dynamic>;
      expect(firstMember['peerId'], equals('12D3KooWAlice'));
      expect(firstMember['role'], equals('admin'));
      expect(firstMember['publicKey'], equals('alicePubKey64'));
    });

    // --- Cycle 1.2 ---
    test('fromInnerJson round-trips with toInnerJson', () {
      final original = makePayload();
      final json = original.toInnerJson();
      final parsed = GroupInvitePayload.fromInnerJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.id, equals(original.id));
      expect(parsed.groupId, equals(original.groupId));
      expect(parsed.groupKey, equals(original.groupKey));
      expect(parsed.keyEpoch, equals(original.keyEpoch));
      expect(parsed.senderPeerId, equals(original.senderPeerId));
      expect(parsed.senderUsername, equals(original.senderUsername));
      expect(parsed.timestamp, equals(original.timestamp));

      final config = parsed.groupConfig;
      expect(config['name'], equals('Book Club'));
      final members = config['members'] as List<dynamic>;
      expect(members, hasLength(2));
    });

    // --- Cycle 1.3 ---
    group('fromInnerJson returns null for missing required fields', () {
      test('returns null when groupId is missing', () {
        final json = jsonEncode({
          'id': 'invite-1',
          // 'groupId' omitted
          'groupKey': 'key',
          'keyEpoch': 1,
          'groupConfig': testGroupConfig,
          'senderPeerId': 'peer1',
          'senderUsername': 'Alice',
          'timestamp': '2026-01-01T00:00:00Z',
        });
        expect(GroupInvitePayload.fromInnerJson(json), isNull);
      });

      test('returns null when groupKey is missing', () {
        final json = jsonEncode({
          'id': 'invite-1',
          'groupId': 'grp-1',
          // 'groupKey' omitted
          'keyEpoch': 1,
          'groupConfig': testGroupConfig,
          'senderPeerId': 'peer1',
          'senderUsername': 'Alice',
          'timestamp': '2026-01-01T00:00:00Z',
        });
        expect(GroupInvitePayload.fromInnerJson(json), isNull);
      });

      test('returns null when groupConfig is missing', () {
        final json = jsonEncode({
          'id': 'invite-1',
          'groupId': 'grp-1',
          'groupKey': 'key',
          'keyEpoch': 1,
          // 'groupConfig' omitted
          'senderPeerId': 'peer1',
          'senderUsername': 'Alice',
          'timestamp': '2026-01-01T00:00:00Z',
        });
        expect(GroupInvitePayload.fromInnerJson(json), isNull);
      });

      test('returns null when input is not valid JSON', () {
        expect(GroupInvitePayload.fromInnerJson('not valid json'), isNull);
      });
    });

    // --- Cycle 1.4 ---
    test('toJson wraps payload in v1 envelope with type group_invite', () {
      final payload = makePayload();
      final json = payload.toJson();
      final map = jsonDecode(json) as Map<String, dynamic>;

      expect(map['type'], equals('group_invite'));
      expect(map['version'], equals('1'));
      expect(map['payload'], isA<Map<String, dynamic>>());

      final inner = map['payload'] as Map<String, dynamic>;
      expect(inner['id'], equals('invite-uuid-001'));
      expect(inner['groupId'], equals('grp-abc123'));
      expect(inner['groupKey'], equals('base64GroupKey=='));
      expect(inner['keyEpoch'], equals(1));
      expect(inner['groupConfig'], isA<Map<String, dynamic>>());
    });

    // --- Cycle 1.5 ---
    test('fromJson parses v1 group_invite envelope', () {
      final payload = makePayload();
      final json = payload.toJson();
      final parsed = GroupInvitePayload.fromJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.id, equals('invite-uuid-001'));
      expect(parsed.groupId, equals('grp-abc123'));
      expect(parsed.groupKey, equals('base64GroupKey=='));
      expect(parsed.keyEpoch, equals(1));
      expect(parsed.senderPeerId, equals('12D3KooWAlice'));
      expect(parsed.senderUsername, equals('Alice'));
    });

    // --- Cycle 1.6 ---
    test('fromJson returns null for chat_message type', () {
      final json = jsonEncode({
        'type': 'chat_message',
        'version': '1',
        'payload': {
          'id': 'msg-1',
          'text': 'hello',
          'senderPeerId': 'peer1',
          'senderUsername': 'Alice',
          'timestamp': '2026-01-01T00:00:00Z',
        },
      });
      expect(GroupInvitePayload.fromJson(json), isNull);
    });

    // --- Cycle 1.7 ---
    test('buildEncryptedEnvelope produces v2 group_invite envelope', () {
      final envelope = GroupInvitePayload.buildEncryptedEnvelope(
        senderPeerId: '12D3KooWAlice',
        kem: 'fakeKem64',
        ciphertext: 'fakeCiphertext64',
        nonce: 'fakeNonce64',
      );

      final map = jsonDecode(envelope) as Map<String, dynamic>;
      expect(map['type'], equals('group_invite'));
      expect(map['version'], equals('2'));
      expect(map['senderPeerId'], equals('12D3KooWAlice'));

      final encrypted = map['encrypted'] as Map<String, dynamic>;
      expect(encrypted['kem'], equals('fakeKem64'));
      expect(encrypted['ciphertext'], equals('fakeCiphertext64'));
      expect(encrypted['nonce'], equals('fakeNonce64'));
    });

    // --- Cycle 1.8 ---
    group('parseEncryptedEnvelope', () {
      test('parses v2 group_invite envelope', () {
        final envelope = GroupInvitePayload.buildEncryptedEnvelope(
          senderPeerId: '12D3KooWAlice',
          kem: 'fakeKem64',
          ciphertext: 'fakeCiphertext64',
          nonce: 'fakeNonce64',
        );

        final result = GroupInvitePayload.parseEncryptedEnvelope(envelope);
        expect(result, isNotNull);
        expect(result!['type'], equals('group_invite'));
        expect(result['version'], equals('2'));
      });

      test('returns null for v2 chat_message (wrong type)', () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '2',
          'senderPeerId': 'peer1',
          'encrypted': {
            'kem': 'k',
            'ciphertext': 'c',
            'nonce': 'n',
          },
        });
        expect(GroupInvitePayload.parseEncryptedEnvelope(json), isNull);
      });

      test('returns null for v1 group_invite', () {
        final payload = makePayload();
        final v1 = payload.toJson();
        expect(GroupInvitePayload.parseEncryptedEnvelope(v1), isNull);
      });

      test('returns null for garbage JSON', () {
        expect(GroupInvitePayload.parseEncryptedEnvelope('not json'), isNull);
      });

      test('returns null when encrypted block is missing kem/ciphertext/nonce',
          () {
        final json = jsonEncode({
          'type': 'group_invite',
          'version': '2',
          'senderPeerId': 'peer1',
          'encrypted': {
            'kem': 'k',
            // 'ciphertext' missing
            // 'nonce' missing
          },
        });
        expect(GroupInvitePayload.parseEncryptedEnvelope(json), isNull);
      });
    });
  });
}
