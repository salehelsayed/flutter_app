import 'dart:convert';

import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
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

const _deviceBoundGroupConfig = {
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
      'devices': [
        {
          'deviceId': 'alice-device-1',
          'transportPeerId': 'alice-device-1',
          'deviceSigningPublicKey': 'alicePubKey64',
          'mlKemPublicKey': 'aliceMlKem64',
          'keyPackageId': 'alice-kp-1',
          'status': 'active',
        },
      ],
    },
    {
      'peerId': '12D3KooWBob',
      'username': 'Bob',
      'role': 'writer',
      'publicKey': 'bobPubKey64',
      'mlKemPublicKey': 'bobMlKem64',
      'devices': [
        {
          'deviceId': 'bob-device-1',
          'transportPeerId': 'bob-device-1',
          'deviceSigningPublicKey': 'bobPubKey64',
          'mlKemPublicKey': 'bobMlKem64',
          'keyPackageId': 'bob-kp-1',
          'keyPackagePublicMaterial': 'bob-kpm-1',
          'status': 'active',
        },
      ],
    },
  ],
  'createdBy': '12D3KooWAlice',
  'createdAt': '2026-03-02T00:00:00.000Z',
};

const _parallelGroupConfig = {
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
    {
      'peerId': '12D3KooWCharlie',
      'username': 'Charlie',
      'role': 'writer',
      'publicKey': 'charliePubKey64',
      'mlKemPublicKey': 'charlieMlKem64',
    },
    {
      'peerId': '12D3KooWDave',
      'username': 'Dave',
      'role': 'writer',
      'publicKey': 'davePubKey64',
      'mlKemPublicKey': 'daveMlKem64',
    },
    {
      'peerId': '12D3KooWEvil',
      'username': 'Evil',
      'role': 'writer',
      'publicKey': 'evilPubKey64',
      'mlKemPublicKey': 'badKey',
    },
  ],
  'createdBy': '12D3KooWAlice',
  'createdAt': '2026-03-02T00:00:00.000Z',
};

final _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

Future<InMemoryGroupRepository> _repoFromConfig(
  Map<String, dynamic> groupConfig, {
  String groupId = 'grp-abc123',
  String groupKey = 'base64GroupKey==',
  int keyEpoch = 1,
}) async {
  final repo = InMemoryGroupRepository();
  final createdAt =
      DateTime.tryParse(groupConfig['createdAt'] as String? ?? '')?.toUtc() ??
      DateTime.utc(2026, 3, 2);
  await repo.saveGroup(
    GroupModel(
      id: groupId,
      name: groupConfig['name'] as String? ?? 'Book Club',
      type: GroupType.fromValue(groupConfig['groupType'] as String? ?? 'chat'),
      topicName: '/mknoon/group/$groupId',
      description: groupConfig['description'] as String?,
      createdAt: createdAt,
      createdBy: groupConfig['createdBy'] as String? ?? '12D3KooWAlice',
      myRole: GroupRole.admin,
      lastMembershipEventAt: createdAt,
      lastMetadataEventAt: createdAt,
    ),
  );
  for (final member in groupConfig['members'] as List<dynamic>? ?? const []) {
    await repo.saveMember(
      GroupMember.fromConfigMap(
        groupId: groupId,
        map: Map<String, dynamic>.from(member as Map),
        joinedAt: createdAt,
      ),
    );
  }
  await repo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: keyEpoch,
      encryptedKey: groupKey,
      createdAt: createdAt,
    ),
  );
  return repo;
}

/// A [FakeP2PService] that delays each sendMessage by [delay].
class _SlowFakeP2PService extends FakeP2PService {
  final Duration delay;

  _SlowFakeP2PService({required this.delay, super.initialState});

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
          groupRepo: await _repoFromConfig(_testGroupConfig),
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
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

    test(
      'device-bound invite sends to the registered recipient device transport',
      () async {
        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: await _repoFromConfig(_deviceBoundGroupConfig),
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          recipientDeviceId: 'bob-device-1',
          senderDeviceId: 'alice-device-1',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: _deviceBoundGroupConfig,
        );

        expect(result, SendGroupInviteResult.success);
        expect(p2pService.lastSendMessagePeerId, 'bob-device-1');

        final envelope = GroupInvitePayload.parseEncryptedEnvelope(
          p2pService.lastSendMessageContent!,
        )!;
        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final payload = GroupInvitePayload.fromInnerJson(
          encrypted['ciphertext'] as String,
        )!;
        expect(payload.recipientPeerId, '12D3KooWBob');
        expect(payload.recipientDeviceId, 'bob-device-1');
        expect(payload.recipientTransportPeerId, 'bob-device-1');
        expect(payload.recipientKeyPackageId, 'bob-kp-1');
        expect(payload.welcomeKeyPackage, isNotNull);
        expect(payload.welcomeKeyPackage!.packageId, 'bob-kp-1');
        expect(
          payload.invitePolicy.welcomeKeyPackageId,
          payload.welcomeKeyPackage!.packageId,
        );
        expect(payload.senderDeviceId, 'alice-device-1');
      },
    );

    test(
      'RA-013 sends separate device-bound re-add invites for same user devices',
      () async {
        final multiDeviceConfig = {
          ..._deviceBoundGroupConfig,
          'members': [
            (_deviceBoundGroupConfig['members'] as List<dynamic>)[0],
            {
              ...((_deviceBoundGroupConfig['members'] as List<dynamic>)[1]
                  as Map<String, dynamic>),
              'devices': [
                {
                  'deviceId': 'bob-phone',
                  'transportPeerId': 'bob-phone',
                  'deviceSigningPublicKey': 'bobPhonePubKey64',
                  'mlKemPublicKey': 'bobPhoneMlKem64',
                  'keyPackageId': 'bob-phone-kp',
                  'keyPackagePublicMaterial': 'bob-phone-kpm',
                  'status': 'active',
                },
                {
                  'deviceId': 'bob-tablet',
                  'transportPeerId': 'bob-tablet',
                  'deviceSigningPublicKey': 'bobTabletPubKey64',
                  'mlKemPublicKey': 'bobTabletMlKem64',
                  'keyPackageId': 'bob-tablet-kp',
                  'keyPackagePublicMaterial': 'bob-tablet-kpm',
                  'status': 'active',
                },
              ],
            },
          ],
        };
        final repo = await _repoFromConfig(multiDeviceConfig);

        Future<GroupInvitePayload> sendForDevice({
          required String deviceId,
          required String mlKemPublicKey,
        }) async {
          final result = await sendGroupInvite(
            p2pService: p2pService,
            bridge: bridge,
            groupRepo: repo,
            recipientPeerId: '12D3KooWBob',
            recipientMlKemPublicKey: mlKemPublicKey,
            recipientDeviceId: deviceId,
            senderDeviceId: 'alice-device-1',
            senderPeerId: '12D3KooWAlice',
            senderPublicKey: 'alicePubKey64',
            senderPrivateKey: 'alicePrivateKey64',
            senderUsername: 'Alice',
            groupId: 'grp-abc123',
            groupKey: 'base64GroupKey==',
            keyEpoch: 1,
            groupConfig: multiDeviceConfig,
          );
          expect(result, SendGroupInviteResult.success);

          final envelope = GroupInvitePayload.parseEncryptedEnvelope(
            p2pService.lastSendMessageContent!,
          )!;
          final encrypted = envelope['encrypted'] as Map<String, dynamic>;
          return GroupInvitePayload.fromInnerJson(
            encrypted['ciphertext'] as String,
          )!;
        }

        final phonePayload = await sendForDevice(
          deviceId: 'bob-phone',
          mlKemPublicKey: 'bobPhoneMlKem64',
        );
        final tabletPayload = await sendForDevice(
          deviceId: 'bob-tablet',
          mlKemPublicKey: 'bobTabletMlKem64',
        );

        expect(
          p2pService.sentMessageLog.map((entry) => entry.peerId).toList(),
          ['bob-phone', 'bob-tablet'],
        );
        expect(phonePayload.recipientPeerId, '12D3KooWBob');
        expect(phonePayload.recipientDeviceId, 'bob-phone');
        expect(phonePayload.invitePolicy.allowedDevices, ['bob-phone']);
        expect(phonePayload.welcomeKeyPackage!.recipientDeviceId, 'bob-phone');
        expect(tabletPayload.recipientPeerId, '12D3KooWBob');
        expect(tabletPayload.recipientDeviceId, 'bob-tablet');
        expect(tabletPayload.invitePolicy.allowedDevices, ['bob-tablet']);
        expect(
          tabletPayload.welcomeKeyPackage!.recipientDeviceId,
          'bob-tablet',
        );
        expect(phonePayload.id, isNot(tabletPayload.id));
      },
    );

    test(
      'EK011 rejects weak recipient key-package material before signing or encryption',
      () async {
        final weakPackageConfig = {
          ..._deviceBoundGroupConfig,
          'members': [
            (_deviceBoundGroupConfig['members'] as List<dynamic>)[0],
            {
              ...((_deviceBoundGroupConfig['members'] as List<dynamic>)[1]
                  as Map<String, dynamic>),
              'devices': [
                {
                  ...((((_deviceBoundGroupConfig['members'] as List<dynamic>)[1]
                              as Map<String, dynamic>)['devices']
                          as List<dynamic>)[0]
                      as Map<String, dynamic>),
                  'keyPackagePublicMaterial': 'weak',
                },
              ],
            },
          ],
        };

        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: await _repoFromConfig(weakPackageConfig),
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          recipientDeviceId: 'bob-device-1',
          senderDeviceId: 'alice-device-1',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: weakPackageConfig,
        );

        expect(result, SendGroupInviteResult.invalidPayload);
        expect(bridge.commandLog, isNot(contains('payload.sign')));
        expect(bridge.commandLog, isNot(contains('message.encrypt')));
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'device-bound invite rejects an unregistered requested recipient device before encryption',
      () async {
        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: await _repoFromConfig(_testGroupConfig),
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          recipientDeviceId: 'bob-device-2',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: _deviceBoundGroupConfig,
        );

        expect(result, SendGroupInviteResult.invalidPayload);
        expect(bridge.commandLog, isNot(contains('message.encrypt')));
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    // --- Cycle 5.2 ---
    test(
      'returns encryptionRequired when recipientMlKemPublicKey is null',
      () async {
        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: await _repoFromConfig(_testGroupConfig),
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: null,
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
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
        groupRepo: await _repoFromConfig(_testGroupConfig),
        recipientPeerId: '12D3KooWBob',
        recipientMlKemPublicKey: 'bobMlKem64',
        senderPeerId: '12D3KooWAlice',
        senderPublicKey: 'alicePubKey64',
        senderPrivateKey: 'alicePrivateKey64',
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
        groupRepo: await _repoFromConfig(_testGroupConfig),
        recipientPeerId: '12D3KooWBob',
        recipientMlKemPublicKey: 'bobMlKem64',
        senderPeerId: '12D3KooWAlice',
        senderPublicKey: 'alicePubKey64',
        senderPrivateKey: 'alicePrivateKey64',
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
          groupRepo: await _repoFromConfig(_testGroupConfig),
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
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
        groupRepo: await _repoFromConfig(_testGroupConfig),
        recipientPeerId: '12D3KooWBob',
        recipientMlKemPublicKey: 'bobMlKem64',
        senderPeerId: '12D3KooWAlice',
        senderPublicKey: 'alicePubKey64',
        senderPrivateKey: 'alicePrivateKey64',
        senderUsername: 'Alice',
        groupId: 'grp-abc123',
        groupKey: 'base64GroupKey==',
        keyEpoch: 1,
        groupConfig: _testGroupConfig,
      );

      expect(result, equals(SendGroupInviteResult.queued));

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
          groupRepo: await _repoFromConfig(_testGroupConfig),
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
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
        expect(inner['recipientPeerId'], equals('12D3KooWBob'));

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

    test(
      'keeps join material and policy details inside encrypted invite payload',
      () async {
        for (final directSendSucceeds in [true, false]) {
          final scopedP2P = FakeP2PService(
            initialState: const NodeState(isStarted: true),
            sendMessageResult: directSendSucceeds,
            storeInInboxResult: true,
          );
          addTearDown(scopedP2P.dispose);

          final result = await sendGroupInvite(
            p2pService: scopedP2P,
            bridge: bridge,
            groupRepo: await _repoFromConfig(_testGroupConfig),
            recipientPeerId: '12D3KooWBob',
            recipientMlKemPublicKey: 'bobMlKem64',
            senderPeerId: '12D3KooWAlice',
            senderPublicKey: 'alicePubKey64',
            senderPrivateKey: 'alicePrivateKey64',
            senderUsername: 'Alice',
            groupId: 'grp-abc123',
            groupKey: 'base64GroupKey==',
            keyEpoch: 1,
            groupConfig: _testGroupConfig,
          );

          expect(
            result,
            directSendSucceeds
                ? SendGroupInviteResult.success
                : SendGroupInviteResult.queued,
          );
          final envelopeJson = directSendSucceeds
              ? scopedP2P.lastSendMessageContent!
              : scopedP2P.lastStoreInInboxMessage!;
          final envelope = jsonDecode(envelopeJson) as Map<String, dynamic>;
          final encrypted = envelope['encrypted'] as Map<String, dynamic>;
          final cleartextEnvelope = Map<String, dynamic>.from(envelope)
            ..remove('encrypted');

          expect(
            cleartextEnvelope.keys,
            unorderedEquals([
              'type',
              'version',
              'id',
              'senderPeerId',
              'senderUsername',
              'groupId',
              'groupName',
            ]),
          );
          expect(cleartextEnvelope['groupId'], 'grp-abc123');
          expect(cleartextEnvelope['groupName'], 'Book Club');

          final cleartextPreview = cleartextEnvelope.toString();
          expect(cleartextPreview, isNot(contains('base64GroupKey==')));
          expect(cleartextPreview, isNot(contains('alicePubKey64')));
          expect(cleartextPreview, isNot(contains('bobMlKem64')));
          expect(cleartextPreview, isNot(contains('allowedDevices')));
          expect(cleartextPreview, isNot(contains('invitePermissions')));
          expect(cleartextPreview, isNot(contains('joinMaterialRef')));
          expect(cleartextPreview, isNot(contains('invitePolicy')));

          final inner =
              jsonDecode(encrypted['ciphertext'] as String)
                  as Map<String, dynamic>;
          expect(inner['groupKey'], 'base64GroupKey==');
          expect(inner['keyEpoch'], 1);
          expect(inner['recipientPeerId'], '12D3KooWBob');
          expect(inner['invitePolicy'], isA<Map<String, dynamic>>());

          final policy = inner['invitePolicy'] as Map<String, dynamic>;
          expect(policy['allowedDevices'], ['12D3KooWBob']);
          expect(policy['invitePermissions']['assignedRole'], 'writer');
          expect(policy['invitePermissions']['canInviteOthers'], isFalse);
          expect(policy['joinMaterialRef']['kind'], 'inlineGroupKey');
          expect(policy['joinMaterialRef']['keyEpoch'], 1);

          final config = inner['groupConfig'] as Map<String, dynamic>;
          expect(config.containsKey('allowedDevices'), isFalse);
          expect(config.containsKey('invitePermissions'), isFalse);
          expect(config.containsKey('joinMaterialRef'), isFalse);

          final members = config['members'] as List<dynamic>;
          final alice = members.first as Map<String, dynamic>;
          final bob = members[1] as Map<String, dynamic>;
          expect(alice['publicKey'], 'alicePubKey64');
          expect(bob['mlKemPublicKey'], 'bobMlKem64');
        }
      },
    );

    test(
      'SP003 direct invite ids are unique UUID v4 values in both envelopes',
      () async {
        final inviteIds = <String>{};

        for (var i = 0; i < 2; i++) {
          final result = await sendGroupInvite(
            p2pService: p2pService,
            bridge: bridge,
            groupRepo: await _repoFromConfig(_testGroupConfig),
            recipientPeerId: '12D3KooWBob',
            recipientMlKemPublicKey: 'bobMlKem64',
            senderPeerId: '12D3KooWAlice',
            senderPublicKey: 'alicePubKey64',
            senderPrivateKey: 'alicePrivateKey64',
            senderUsername: 'Alice',
            groupId: 'grp-abc123',
            groupKey: 'base64GroupKey==',
            keyEpoch: 1,
            groupConfig: _testGroupConfig,
          );

          expect(result, SendGroupInviteResult.success);
          final envelope =
              jsonDecode(p2pService.lastSendMessageContent!)
                  as Map<String, dynamic>;
          final inviteId = envelope['id'] as String;
          expect(_uuidV4Pattern.hasMatch(inviteId), isTrue);
          expect(inviteIds.add(inviteId), isTrue);

          final encrypted = envelope['encrypted'] as Map<String, dynamic>;
          final inner =
              jsonDecode(encrypted['ciphertext'] as String)
                  as Map<String, dynamic>;
          expect(inner['id'], inviteId);
        }
      },
    );

    test(
      'IJ001 returns invalidPayload before encryption or delivery when policy derivation fails',
      () async {
        final invalidConfig = <String, dynamic>{
          ..._testGroupConfig,
          'members': [(_testGroupConfig['members'] as List<dynamic>).first],
        };

        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: await _repoFromConfig(invalidConfig),
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: invalidConfig,
        );

        expect(result, SendGroupInviteResult.invalidPayload);
        expect(bridge.sendCallCount, 0);
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test('IJ005 direct invites default to single-use reuse policy', () async {
      final result = await sendGroupInvite(
        p2pService: p2pService,
        bridge: bridge,
        groupRepo: await _repoFromConfig(_testGroupConfig),
        recipientPeerId: '12D3KooWBob',
        recipientMlKemPublicKey: 'bobMlKem64',
        senderPeerId: '12D3KooWAlice',
        senderPublicKey: 'alicePubKey64',
        senderPrivateKey: 'alicePrivateKey64',
        senderUsername: 'Alice',
        groupId: 'grp-abc123',
        groupKey: 'base64GroupKey==',
        keyEpoch: 1,
        groupConfig: _testGroupConfig,
      );

      expect(result, SendGroupInviteResult.success);

      final envelope =
          jsonDecode(p2pService.lastSendMessageContent!)
              as Map<String, dynamic>;
      final cleartextEnvelope = Map<String, dynamic>.from(envelope)
        ..remove('encrypted');
      expect(cleartextEnvelope.toString(), isNot(contains('reusePolicy')));
      final encrypted = envelope['encrypted'] as Map<String, dynamic>;
      final inner =
          jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
      final policy = inner['invitePolicy'] as Map<String, dynamic>;
      expect(policy['reusePolicy'], {'mode': 'singleUse'});
    });

    test('IJ005 direct invites can explicitly request multi-use', () async {
      final result = await sendGroupInvite(
        p2pService: p2pService,
        bridge: bridge,
        groupRepo: await _repoFromConfig(_testGroupConfig),
        recipientPeerId: '12D3KooWBob',
        recipientMlKemPublicKey: 'bobMlKem64',
        senderPeerId: '12D3KooWAlice',
        senderPublicKey: 'alicePubKey64',
        senderPrivateKey: 'alicePrivateKey64',
        senderUsername: 'Alice',
        groupId: 'grp-abc123',
        groupKey: 'base64GroupKey==',
        keyEpoch: 1,
        groupConfig: _testGroupConfig,
        reusePolicy: GroupInviteReusePolicy.multiUse,
      );

      expect(result, SendGroupInviteResult.success);

      final envelope =
          jsonDecode(p2pService.lastSendMessageContent!)
              as Map<String, dynamic>;
      final encrypted = envelope['encrypted'] as Map<String, dynamic>;
      final inner =
          jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
      final payload = GroupInvitePayload.fromInnerJson(jsonEncode(inner));
      expect(payload, isNotNull);
      expect(
        payload!.invitePolicy.reusePolicy,
        GroupInviteReusePolicy.multiUse,
      );
    });

    test(
      'IJ002 signs canonical invite payload before encryption and delivery',
      () async {
        bridge.responses['payload.sign'] = {
          'ok': true,
          'signature': 'signed-invite-by-alice',
        };

        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: await _repoFromConfig(_testGroupConfig),
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: _testGroupConfig,
        );

        expect(result, SendGroupInviteResult.success);
        expect(bridge.commandLog, contains('payload.sign'));
        expect(
          bridge.commandLog.indexOf('payload.sign'),
          lessThan(bridge.commandLog.indexOf('message.encrypt')),
        );

        final signRequest = bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .firstWhere((message) => message['cmd'] == 'payload.sign');
        final signPayload = signRequest['payload'] as Map<String, dynamic>;
        expect(signPayload['privateKey'], 'alicePrivateKey64');

        final sentContent = p2pService.lastSendMessageContent!;
        final envelope = jsonDecode(sentContent) as Map<String, dynamic>;
        final cleartextEnvelope = Map<String, dynamic>.from(envelope)
          ..remove('encrypted');
        expect(
          cleartextEnvelope.toString(),
          isNot(contains('inviteSignature')),
        );
        expect(cleartextEnvelope.toString(), isNot(contains('signedPayload')));
        expect(cleartextEnvelope.toString(), isNot(contains('signature')));

        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final inner =
            jsonDecode(encrypted['ciphertext'] as String)
                as Map<String, dynamic>;
        final inviteSignature =
            inner['inviteSignature'] as Map<String, dynamic>;
        expect(inviteSignature['signatureAlgorithm'], 'ed25519');
        expect(inviteSignature['signature'], 'signed-invite-by-alice');
        expect(inviteSignature['signedPayload'], signPayload['data']);
      },
    );

    test(
      'PREREQ-INVITER-FRESHNESS refuses to sign invite from stale caller config after inviter removal or invite permission revocation',
      () async {
        final currentConfigWithoutAlice = {
          ..._testGroupConfig,
          'members': [(_testGroupConfig['members'] as List<dynamic>)[1]],
        };
        final groupRepo = await _repoFromConfig(currentConfigWithoutAlice);

        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: groupRepo,
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: _testGroupConfig,
        );

        expect(result, SendGroupInviteResult.invalidPayload);
        expect(bridge.commandLog, isNot(contains('payload.sign')));
        expect(bridge.commandLog, isNot(contains('message.encrypt')));
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'rejects stale caller groupKey and keyEpoch before signing or encryption',
      () async {
        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: await _repoFromConfig(
            _testGroupConfig,
            groupKey: 'currentGroupKey==',
            keyEpoch: 2,
          ),
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: _testGroupConfig,
        );

        expect(result, SendGroupInviteResult.invalidPayload);
        expect(bridge.commandLog, isNot(contains('payload.sign')));
        expect(bridge.commandLog, isNot(contains('message.encrypt')));
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'ML-013 bare writer cannot sign encrypt or deliver a group invite',
      () async {
        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: await _repoFromConfig(_testGroupConfig),
          recipientPeerId: '12D3KooWCharlie',
          recipientMlKemPublicKey: 'charlieMlKem64',
          senderPeerId: '12D3KooWBob',
          senderPublicKey: 'bobPubKey64',
          senderPrivateKey: 'bobPrivateKey64',
          senderUsername: 'Bob',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: _testGroupConfig,
        );

        expect(result, SendGroupInviteResult.invalidPayload);
        expect(bridge.commandLog, isNot(contains('payload.sign')));
        expect(bridge.commandLog, isNot(contains('message.encrypt')));
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'IJ002 returns invalidPayload without encryption or delivery when invite signing fails',
      () async {
        bridge.responses['payload.sign'] = {
          'ok': false,
          'errorCode': 'SIGN_FAILED',
        };

        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: await _repoFromConfig(_testGroupConfig),
          recipientPeerId: '12D3KooWBob',
          recipientMlKemPublicKey: 'bobMlKem64',
          senderPeerId: '12D3KooWAlice',
          senderPublicKey: 'alicePubKey64',
          senderPrivateKey: 'alicePrivateKey64',
          senderUsername: 'Alice',
          groupId: 'grp-abc123',
          groupKey: 'base64GroupKey==',
          keyEpoch: 1,
          groupConfig: _testGroupConfig,
        );

        expect(result, SendGroupInviteResult.invalidPayload);
        expect(bridge.commandLog, contains('payload.sign'));
        expect(bridge.commandLog, isNot(contains('message.encrypt')));
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );
  });

  group('sendGroupInvitesInParallel', () {
    const sharedArgs = (
      senderPeerId: '12D3KooWAlice',
      senderPublicKey: 'alicePubKey64',
      senderPrivateKey: 'alicePrivateKey64',
      senderUsername: 'Alice',
      groupId: 'grp-abc123',
      groupKey: 'base64GroupKey==',
      keyEpoch: 1,
      groupConfig: _parallelGroupConfig,
    );

    test(
      'sends invites to all recipients and returns per-recipient outcomes',
      () async {
        final recipients = [
          (
            peerId: '12D3KooWBob',
            username: 'Bob' as String?,
            mlKemPublicKey: 'bobMlKem64' as String?,
          ),
          (
            peerId: '12D3KooWCharlie',
            username: 'Charlie' as String?,
            mlKemPublicKey: 'charlieMlKem64' as String?,
          ),
        ];

        final result = await sendGroupInvitesInParallel(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: await _repoFromConfig(sharedArgs.groupConfig),
          senderPeerId: sharedArgs.senderPeerId,
          senderPublicKey: sharedArgs.senderPublicKey,
          senderPrivateKey: sharedArgs.senderPrivateKey,
          senderUsername: sharedArgs.senderUsername,
          groupId: sharedArgs.groupId,
          groupKey: sharedArgs.groupKey,
          keyEpoch: sharedArgs.keyEpoch,
          groupConfig: sharedArgs.groupConfig,
          recipients: recipients,
        );

        expect(result.successCount, equals(2));
        expect(result.failures, isEmpty);
        expect(p2pService.sentMessageLog.length, equals(2));
      },
    );

    test(
      'targets each active registered device for one recipient from current config',
      () async {
        final currentConfig = {
          ..._parallelGroupConfig,
          'members': [
            (_parallelGroupConfig['members'] as List<dynamic>)[0],
            {
              ...((_parallelGroupConfig['members'] as List<dynamic>)[1]
                  as Map<String, dynamic>),
              'devices': [
                {
                  'deviceId': 'bob-phone',
                  'transportPeerId': 'bob-phone',
                  'deviceSigningPublicKey': 'bobPhonePubKey64',
                  'mlKemPublicKey': 'bobPhoneMlKem64',
                  'keyPackageId': 'bob-phone-kp',
                  'keyPackagePublicMaterial': 'bob-phone-kpm',
                  'status': 'active',
                },
                {
                  'deviceId': 'bob-tablet',
                  'transportPeerId': 'bob-tablet',
                  'deviceSigningPublicKey': 'bobTabletPubKey64',
                  'mlKemPublicKey': 'bobTabletMlKem64',
                  'keyPackageId': 'bob-tablet-kp',
                  'keyPackagePublicMaterial': 'bob-tablet-kpm',
                  'status': 'active',
                },
                {
                  'deviceId': 'bob-old-phone',
                  'transportPeerId': 'bob-old-phone',
                  'deviceSigningPublicKey': 'bobOldPubKey64',
                  'mlKemPublicKey': 'bobOldMlKem64',
                  'keyPackageId': 'bob-old-kp',
                  'keyPackagePublicMaterial': 'bob-old-kpm',
                  'status': 'revoked',
                },
              ],
            },
          ],
        };

        final result = await sendGroupInvitesInParallel(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: await _repoFromConfig(currentConfig),
          senderPeerId: sharedArgs.senderPeerId,
          senderPublicKey: sharedArgs.senderPublicKey,
          senderPrivateKey: sharedArgs.senderPrivateKey,
          senderUsername: sharedArgs.senderUsername,
          groupId: sharedArgs.groupId,
          groupKey: sharedArgs.groupKey,
          keyEpoch: sharedArgs.keyEpoch,
          groupConfig: _parallelGroupConfig,
          recipients: [
            (
              peerId: '12D3KooWBob',
              username: 'Bob' as String?,
              mlKemPublicKey: 'staleBobMlKem64' as String?,
            ),
          ],
        );

        expect(result.attempts, hasLength(2));
        expect(result.successCount, 2);
        expect(
          p2pService.sentMessageLog.map((entry) => entry.peerId),
          unorderedEquals(['bob-phone', 'bob-tablet']),
        );

        final payloadsByDevice = <String, GroupInvitePayload>{};
        for (final entry in p2pService.sentMessageLog) {
          final envelope = GroupInvitePayload.parseEncryptedEnvelope(
            entry.content,
          )!;
          final encrypted = envelope['encrypted'] as Map<String, dynamic>;
          payloadsByDevice[entry.peerId] = GroupInvitePayload.fromInnerJson(
            encrypted['ciphertext'] as String,
          )!;
        }

        expect(payloadsByDevice['bob-phone']!.recipientDeviceId, 'bob-phone');
        expect(
          payloadsByDevice['bob-phone']!.recipientMlKemPublicKey,
          'bobPhoneMlKem64',
        );
        expect(payloadsByDevice['bob-phone']!.invitePolicy.allowedDevices, [
          'bob-phone',
        ]);
        expect(payloadsByDevice['bob-tablet']!.recipientDeviceId, 'bob-tablet');
        expect(
          payloadsByDevice['bob-tablet']!.recipientMlKemPublicKey,
          'bobTabletMlKem64',
        );
        expect(payloadsByDevice['bob-tablet']!.invitePolicy.allowedDevices, [
          'bob-tablet',
        ]);
        expect(payloadsByDevice.containsKey('bob-old-phone'), isFalse);
      },
    );

    test('runs invites concurrently', () async {
      final slowP2P = _SlowFakeP2PService(
        delay: const Duration(milliseconds: 100),
        initialState: const NodeState(isStarted: true),
      );

      final recipients = [
        (
          peerId: '12D3KooWBob',
          username: 'Bob' as String?,
          mlKemPublicKey: 'bobMlKem64' as String?,
        ),
        (
          peerId: '12D3KooWCharlie',
          username: 'Charlie' as String?,
          mlKemPublicKey: 'charlieMlKem64' as String?,
        ),
        (
          peerId: '12D3KooWDave',
          username: 'Dave' as String?,
          mlKemPublicKey: 'daveMlKem64' as String?,
        ),
      ];

      final sw = Stopwatch()..start();
      final result = await sendGroupInvitesInParallel(
        p2pService: slowP2P,
        bridge: bridge,
        groupRepo: await _repoFromConfig(sharedArgs.groupConfig),
        senderPeerId: sharedArgs.senderPeerId,
        senderPublicKey: sharedArgs.senderPublicKey,
        senderPrivateKey: sharedArgs.senderPrivateKey,
        senderUsername: sharedArgs.senderUsername,
        groupId: sharedArgs.groupId,
        groupKey: sharedArgs.groupKey,
        keyEpoch: sharedArgs.keyEpoch,
        groupConfig: sharedArgs.groupConfig,
        recipients: recipients,
      );
      sw.stop();

      expect(result.successCount, equals(3));
      expect(slowP2P.sentMessageLog.length, equals(3));
      // Sequential would be ~300ms+; parallel should be ~100ms
      expect(sw.elapsedMilliseconds, lessThan(250));

      slowP2P.dispose();
    });

    test('counts only successful invites when some fail', () async {
      final recipients = [
        (
          peerId: '12D3KooWBob',
          username: 'Bob' as String?,
          mlKemPublicKey: 'bobMlKem64' as String?,
        ),
        (
          peerId: '12D3KooWNoKey',
          username: 'NoKey' as String?,
          mlKemPublicKey: null as String?,
        ),
        (
          peerId: '12D3KooWCharlie',
          username: 'Charlie' as String?,
          mlKemPublicKey: 'charlieMlKem64' as String?,
        ),
      ];

      final result = await sendGroupInvitesInParallel(
        p2pService: p2pService,
        bridge: bridge,
        groupRepo: await _repoFromConfig(sharedArgs.groupConfig),
        senderPeerId: sharedArgs.senderPeerId,
        senderPublicKey: sharedArgs.senderPublicKey,
        senderPrivateKey: sharedArgs.senderPrivateKey,
        senderUsername: sharedArgs.senderUsername,
        groupId: sharedArgs.groupId,
        groupKey: sharedArgs.groupKey,
        keyEpoch: sharedArgs.keyEpoch,
        groupConfig: sharedArgs.groupConfig,
        recipients: recipients,
      );

      expect(result.successCount, equals(2));
      expect(result.failures, hasLength(1));
      expect(result.failures.single.displayName, equals('NoKey'));
      expect(
        result.failures.single.result,
        equals(SendGroupInviteResult.encryptionRequired),
      );
    });

    test('returns 0 for empty recipients list', () async {
      final result = await sendGroupInvitesInParallel(
        p2pService: p2pService,
        bridge: bridge,
        groupRepo: await _repoFromConfig(sharedArgs.groupConfig),
        senderPeerId: sharedArgs.senderPeerId,
        senderPublicKey: sharedArgs.senderPublicKey,
        senderPrivateKey: sharedArgs.senderPrivateKey,
        senderUsername: sharedArgs.senderUsername,
        groupId: sharedArgs.groupId,
        groupKey: sharedArgs.groupKey,
        keyEpoch: sharedArgs.keyEpoch,
        groupConfig: sharedArgs.groupConfig,
        recipients: [],
      );

      expect(result.successCount, equals(0));
      expect(result.attempts, isEmpty);
      expect(p2pService.sendMessageCallCount, equals(0));
    });

    test('continues sending when one invite throws', () async {
      final throwBridge = _ThrowOnKeyBridge(throwForKey: 'badKey');

      final recipients = [
        (
          peerId: '12D3KooWBob',
          username: 'Bob' as String?,
          mlKemPublicKey: 'bobMlKem64' as String?,
        ),
        (
          peerId: '12D3KooWEvil',
          username: 'Evil' as String?,
          mlKemPublicKey: 'badKey' as String?,
        ),
        (
          peerId: '12D3KooWCharlie',
          username: 'Charlie' as String?,
          mlKemPublicKey: 'charlieMlKem64' as String?,
        ),
      ];

      final result = await sendGroupInvitesInParallel(
        p2pService: p2pService,
        bridge: throwBridge,
        groupRepo: await _repoFromConfig(sharedArgs.groupConfig),
        senderPeerId: sharedArgs.senderPeerId,
        senderPublicKey: sharedArgs.senderPublicKey,
        senderPrivateKey: sharedArgs.senderPrivateKey,
        senderUsername: sharedArgs.senderUsername,
        groupId: sharedArgs.groupId,
        groupKey: sharedArgs.groupKey,
        keyEpoch: sharedArgs.keyEpoch,
        groupConfig: sharedArgs.groupConfig,
        recipients: recipients,
      );

      expect(result.successCount, equals(2));
      expect(result.failures, hasLength(1));
      expect(result.failures.single.displayName, equals('Evil'));
      expect(p2pService.sentMessageLog.length, equals(2));
    });
  });
}
