import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late PassthroughCryptoBridge bridge;
  late InMemoryGroupRepository groupRepo;

  const selfPeerId = 'peer-self';
  const groupId = 'group-1';

  setUp(() async {
    bridge = PassthroughCryptoBridge();
    groupRepo = InMemoryGroupRepository();

    await groupRepo.saveGroup(GroupModel(
      id: groupId,
      name: 'Test Group',
      type: GroupType.chat,
      topicName: '/mknoon/group/$groupId',
      createdAt: DateTime.now().toUtc(),
      createdBy: selfPeerId,
      myRole: GroupRole.admin,
    ));

    await groupRepo.saveMember(GroupMember(
      groupId: groupId,
      peerId: selfPeerId,
      username: 'Self',
      role: MemberRole.admin,
      publicKey: 'selfPubKey',
      mlKemPublicKey: 'selfMlKem',
      joinedAt: DateTime.now().toUtc(),
    ));

    await groupRepo.saveMember(GroupMember(
      groupId: groupId,
      peerId: 'peer-bob',
      username: 'Bob',
      role: MemberRole.writer,
      publicKey: 'bobPubKey',
      mlKemPublicKey: 'bobMlKem',
      joinedAt: DateTime.now().toUtc(),
    ));

    await groupRepo.saveMember(GroupMember(
      groupId: groupId,
      peerId: 'peer-carol',
      username: 'Carol',
      role: MemberRole.writer,
      publicKey: 'carolPubKey',
      mlKemPublicKey: 'carolMlKem',
      joinedAt: DateTime.now().toUtc(),
    ));

    await groupRepo.saveKey(GroupKeyInfo(
      groupId: groupId,
      keyGeneration: 1,
      encryptedKey: 'oldKey==',
      createdAt: DateTime.now().toUtc(),
    ));

    bridge.responses['group:rotateKey'] = {
      'ok': true,
      'groupKey': 'newKey==',
      'keyEpoch': 2,
    };

    bridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'sys-msg-id',
    };
  });

  test('rotates key and saves locally', () async {
    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
    );

    expect(result, isNotNull);
    expect(result!.keyGeneration, 2);
    expect(result.encryptedKey, 'newKey==');

    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 2);
  });

  test('calls bridge to encrypt key for each non-self member', () async {
    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
    );

    // message.encrypt should be called twice (Bob + Carol, not self)
    final encryptCount =
        bridge.commandLog.where((c) => c == 'message.encrypt').length;
    expect(encryptCount, 2);
  });

  test('broadcasts key_rotated system message', () async {
    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
    );

    // group:publish should be called for the system message
    expect(bridge.commandLog, contains('group:publish'));

    // Parse the published text to verify it's a key_rotated system message
    final publishMsg = bridge.sentMessages.firstWhere((m) {
      final parsed = jsonDecode(m) as Map<String, dynamic>;
      return parsed['cmd'] == 'group:publish';
    });
    final publishPayload =
        (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    final sysText = jsonDecode(publishPayload['text'] as String)
        as Map<String, dynamic>;
    expect(sysText['__sys'], 'key_rotated');
    expect(sysText['newKeyEpoch'], 2);
  });

  test('sends key update to each non-self member via p2p', () async {
    final sentMessages = <(String, String)>[];

    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: (peerId, message) async {
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Should send to Bob and Carol (not self)
    expect(sentMessages.length, 2);
    final peerIds = sentMessages.map((m) => m.$1).toSet();
    expect(peerIds, contains('peer-bob'));
    expect(peerIds, contains('peer-carol'));

    // Each message should be a group_key_update envelope
    for (final (_, msg) in sentMessages) {
      final parsed = jsonDecode(msg) as Map<String, dynamic>;
      expect(parsed['type'], 'group_key_update');
      expect(parsed['version'], '2');
      expect(parsed['encrypted'], isNotNull);
    }
  });

  test('returns null when rotate fails (ok: false)', () async {
    bridge.responses['group:rotateKey'] = {
      'ok': false,
      'errorCode': 'ROTATE_FAILED',
    };

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
    );

    expect(result, isNull);

    // Verify no new key was saved — latest key should still be generation 1
    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
  });

  test('skips members without mlKemPublicKey', () async {
    // Add Dave without an ML-KEM public key
    await groupRepo.saveMember(GroupMember(
      groupId: groupId,
      peerId: 'peer-dave',
      username: 'Dave',
      role: MemberRole.writer,
      publicKey: 'davePubKey',
      mlKemPublicKey: null,
      joinedAt: DateTime.now().toUtc(),
    ));

    final sentMessages = <(String, String)>[];

    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: (peerId, message) async {
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Only Bob and Carol should receive P2P messages (Dave skipped)
    expect(sentMessages.length, 2);
    final peerIds = sentMessages.map((m) => m.$1).toSet();
    expect(peerIds, contains('peer-bob'));
    expect(peerIds, contains('peer-carol'));
    expect(peerIds, isNot(contains('peer-dave')));

    // message.encrypt should be called only twice (not three times)
    final encryptCount =
        bridge.commandLog.where((c) => c == 'message.encrypt').length;
    expect(encryptCount, 2);
  });

  test('continues distribution when per-member encrypt fails', () async {
    // Use a custom bridge that fails encrypt for Bob but succeeds for Carol
    final selectiveBridge = _SelectiveEncryptFailBridge();
    selectiveBridge.responses['group:rotateKey'] = {
      'ok': true,
      'groupKey': 'newKey==',
      'keyEpoch': 2,
    };
    selectiveBridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'sys-msg-id',
    };

    final sentMessages = <(String, String)>[];

    await rotateAndDistributeGroupKey(
      bridge: selectiveBridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: (peerId, message) async {
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Only Carol should receive a P2P message (Bob's encrypt failed)
    expect(sentMessages.length, 1);
    expect(sentMessages.first.$1, 'peer-carol');
  });

  test('continues distribution when sendP2PMessage throws', () async {
    var callCount = 0;
    final sentMessages = <(String, String)>[];

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      sendP2PMessage: (peerId, message) async {
        callCount++;
        if (callCount == 1) {
          throw Exception('Network error for first peer');
        }
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Function should still complete and return a result
    expect(result, isNotNull);
    expect(result!.keyGeneration, 2);

    // The second member's message should still have been sent
    expect(sentMessages.length, 1);
  });
}

class _SelectiveEncryptFailBridge extends PassthroughCryptoBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'message.encrypt') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      if (payload['recipientPublicKey'] == 'bobMlKem') {
        sendCallCount++;
        lastSentMessage = message;
        sentMessages.add(message);
        lastCommand = cmd;
        commandLog.add(cmd!);
        return jsonEncode({'ok': false, 'errorCode': 'ENCRYPT_FAILED'});
      }
    }
    return super.send(message);
  }
}
