import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late PassthroughCryptoBridge bridge;
  late InMemoryGroupRepository groupRepo;

  const adminPeerId = 'peer-admin';
  const groupId = 'group-1';

  setUp(() async {
    bridge = PassthroughCryptoBridge();
    groupRepo = InMemoryGroupRepository();

    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Test Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: DateTime.now().toUtc(),
        createdBy: adminPeerId,
        myRole: GroupRole.admin,
      ),
    );

    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: adminPeerId,
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-admin',
        mlKemPublicKey: 'mlkem-pk-admin',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-alice',
        username: 'Alice',
        role: MemberRole.writer,
        publicKey: 'pk-alice',
        mlKemPublicKey: 'mlkem-pk-alice',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-bob',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-bob',
        mlKemPublicKey: 'mlkem-pk-bob',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    bridge.responses['group:generateNextKey'] = {
      'ok': true,
      'groupKey': 'rotated-key-abc',
      'keyEpoch': 2,
    };
    bridge.responses['group:publish'] = {'ok': true, 'messageId': 'sys-msg-id'};
  });

  test(
    'complete admin removal flow produces correct bridge command sequence',
    () async {
      // Step 1: Remove member (DB + updateConfig)
      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: 'peer-alice',
      );

      // Step 2: Rotate and distribute key
      await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: adminPeerId,
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        senderUsername: 'Admin',
      );

      // Verify the sequence: updateConfig first, then generate the next key,
      // then encrypt/distribute, then updateKey, then publish key_rotated.
      final updateConfigIdx = bridge.commandLog.indexOf('group:updateConfig');
      final generateIdx = bridge.commandLog.indexOf('group:generateNextKey');
      final firstEncryptIdx = bridge.commandLog.indexOf('message.encrypt');
      final updateKeyIdx = bridge.commandLog.indexOf('group:updateKey');
      final publishIdx = bridge.commandLog.indexOf('group:publish');

      expect(updateConfigIdx, greaterThanOrEqualTo(0));
      expect(generateIdx, greaterThan(updateConfigIdx));
      expect(firstEncryptIdx, greaterThan(generateIdx));
      expect(updateKeyIdx, greaterThan(firstEncryptIdx));
      expect(publishIdx, greaterThan(updateKeyIdx));
    },
  );

  test('rotated key is NOT distributed to removed member', () async {
    // Remove Alice
    await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      memberPeerId: 'peer-alice',
    );

    // Collect who receives the P2P key update
    final sentMessages = <(String, String)>[];

    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: adminPeerId,
      senderPublicKey: 'pk-admin',
      senderPrivateKey: 'sk-admin',
      senderUsername: 'Admin',
      sendP2PMessage: (peerId, message) async {
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Only Bob should receive the key (not Alice, not self)
    expect(sentMessages.length, 1);
    expect(sentMessages.first.$1, 'peer-bob');

    // Verify it's a proper group_key_update envelope
    final envelope = jsonDecode(sentMessages.first.$2) as Map<String, dynamic>;
    expect(envelope['type'], 'group_key_update');
    expect(envelope['version'], '2');
  });

  test('receiver processes key update and syncs Go validator', () async {
    // Simulate: admin rotates key and sends encrypted envelope to Bob
    // Bob's listener receives it and should: decrypt → updateKey → saveKey

    final receiverBridge = PassthroughCryptoBridge();
    final receiverGroupRepo = InMemoryGroupRepository();
    final controller = StreamController<ChatMessage>.broadcast();

    // Bob needs to have the group in his repo
    await receiverGroupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Test Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: DateTime.now().toUtc(),
        createdBy: adminPeerId,
        myRole: GroupRole.member,
      ),
    );

    final listener = GroupKeyUpdateListener(
      groupKeyUpdateStream: controller.stream,
      groupRepo: receiverGroupRepo,
      bridge: receiverBridge,
      getOwnMlKemSecretKey: () async => 'bob-mlkem-secret',
    );
    listener.start();

    // Build the encrypted envelope (PassthroughCryptoBridge treats
    // ciphertext as plaintext, so we put the key JSON in ciphertext)
    final keyPayload = jsonEncode({
      'groupId': groupId,
      'keyGeneration': 2,
      'encryptedKey': 'rotated-key-abc',
    });
    final envelope = jsonEncode({
      'encrypted': {
        'kem': 'fake-kem',
        'ciphertext': keyPayload,
        'nonce': 'fake-nonce',
      },
    });

    controller.add(
      ChatMessage(
        from: adminPeerId,
        to: 'peer-bob',
        content: envelope,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ),
    );

    await Future<void>.delayed(Duration.zero);

    // Verify: message.decrypt was called
    expect(receiverBridge.commandLog, contains('message.decrypt'));

    // Verify: key saved to DB with correct epoch
    final savedKey = await receiverGroupRepo.getLatestKey(groupId);
    expect(savedKey, isNotNull);
    expect(savedKey!.keyGeneration, 2);
    expect(savedKey.encryptedKey, 'rotated-key-abc');

    // Verify: group:updateKey called with matching epoch
    expect(receiverBridge.commandLog, contains('group:updateKey'));
    final updateKeyMsg = receiverBridge.sentMessages.firstWhere((m) {
      final parsed = jsonDecode(m) as Map<String, dynamic>;
      return parsed['cmd'] == 'group:updateKey';
    });
    final payload =
        (jsonDecode(updateKeyMsg) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    expect(payload['groupId'], groupId);
    expect(payload['groupKey'], 'rotated-key-abc');
    expect(payload['keyEpoch'], 2);

    listener.dispose();
    controller.close();
  });
}
