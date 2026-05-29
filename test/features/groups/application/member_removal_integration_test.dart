import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/broadcast_voluntary_leave_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_update_signature.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

Map<String, dynamic> _lastGroupInboxStorePayload(FakeBridge bridge) {
  final inboxMsg = bridge.sentMessages.lastWhere(
    (message) =>
        (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
        'group:inboxStore',
  );
  return (jsonDecode(inboxMsg) as Map<String, dynamic>)['payload']
      as Map<String, dynamic>;
}

Map<String, dynamic> _decodeDirectKeyUpdatePayload(String message) {
  final envelope = jsonDecode(message) as Map<String, dynamic>;
  final encrypted = envelope['encrypted'] as Map<String, dynamic>;
  return jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
}

Map<String, dynamic> _groupInboxStorePayloadForMessage(
  FakeBridge bridge,
  String messageId,
) {
  for (final raw in bridge.sentMessages.reversed) {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    if (parsed['cmd'] != 'group:inboxStore') continue;
    final payload = parsed['payload'] as Map<String, dynamic>;
    final replayEnvelope =
        jsonDecode(payload['message'] as String) as Map<String, dynamic>;
    if (replayEnvelope['messageId'] == messageId) {
      return payload;
    }
  }
  fail('missing group:inboxStore for $messageId');
}

Map<String, dynamic> _groupPublishPayloadForMessage(
  FakeBridge bridge,
  String messageId,
) {
  for (final raw in bridge.sentMessages.reversed) {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    if (parsed['cmd'] != 'group:publish') continue;
    final payload = parsed['payload'] as Map<String, dynamic>;
    if (payload['messageId'] == messageId) return payload;
  }
  fail('missing group:publish for $messageId');
}

Map<String, dynamic> _lastGroupUpdateConfigPayload(FakeBridge bridge) {
  final raw = bridge.sentMessages.lastWhere(
    (message) =>
        (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
        'group:updateConfig',
  );
  return (jsonDecode(raw) as Map<String, dynamic>)['payload']
      as Map<String, dynamic>;
}

List<String> _recipientPeerIdsFromRetryPayload(String inboxRetryPayload) {
  final retryPayload = jsonDecode(inboxRetryPayload) as Map<String, dynamic>;
  return (retryPayload['recipientPeerIds'] as List<dynamic>? ?? const [])
      .cast<String>();
}

class _InboxStoreFailPassthroughBridge extends PassthroughCryptoBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:inboxStore') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      throw Exception('Relay inbox store failed');
    }
    return super.send(message);
  }
}

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

    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'initial-key-epoch-1',
        createdAt: DateTime.now().toUtc(),
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
        sendP2PMessage: (_, _) async => true,
      );

      // Verify the sequence: updateConfig first, then generate the next key,
      // then encrypt/distribute, then promote updateKey, then publish key_rotated.
      final updateConfigIdx = bridge.commandLog.indexOf('group:updateConfig');
      int commandIndex(String command, {int? keyEpoch}) {
        for (var i = 0; i < bridge.sentMessages.length; i++) {
          final parsed =
              jsonDecode(bridge.sentMessages[i]) as Map<String, dynamic>;
          if (parsed['cmd'] != command) {
            continue;
          }
          if (keyEpoch == null) {
            return i;
          }
          final payload = parsed['payload'];
          if (payload is Map<String, dynamic> &&
              payload['keyEpoch'] == keyEpoch) {
            return i;
          }
        }
        return -1;
      }

      final resyncUpdateKeyIdx = commandIndex('group:updateKey', keyEpoch: 1);
      final generateIdx = commandIndex('group:generateNextKey');
      final firstEncryptIdx = commandIndex('message.encrypt');
      final promoteUpdateKeyIdx = commandIndex('group:updateKey', keyEpoch: 2);
      final publishIdx = commandIndex('group:publish');

      expect(updateConfigIdx, greaterThanOrEqualTo(0));
      expect(resyncUpdateKeyIdx, greaterThan(updateConfigIdx));
      expect(generateIdx, greaterThan(resyncUpdateKeyIdx));
      expect(firstEncryptIdx, greaterThan(generateIdx));
      expect(promoteUpdateKeyIdx, greaterThan(firstEncryptIdx));
      expect(publishIdx, greaterThan(promoteUpdateKeyIdx));
    },
  );

  test(
    'KE-006 removal rotates key and excludes removed member; rotated key is NOT distributed to removed member',
    () async {
      // Remove Alice
      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: 'peer-alice',
      );

      final remainingMembers = await groupRepo.getMembers(groupId);
      expect(
        remainingMembers.map((member) => member.peerId),
        containsAll(<String>[adminPeerId, 'peer-bob']),
      );
      expect(
        remainingMembers.map((member) => member.peerId),
        isNot(contains('peer-alice')),
      );

      // Collect who receives the P2P key update
      final sentMessages = <(String, String)>[];

      final rotatedKey = await rotateAndDistributeGroupKey(
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

      expect(rotatedKey, isNotNull);
      expect(rotatedKey!.keyGeneration, 2);
      expect(rotatedKey.encryptedKey, 'rotated-key-abc');

      final savedLatestKey = await groupRepo.getLatestKey(groupId);
      expect(savedLatestKey, isNotNull);
      expect(savedLatestKey!.keyGeneration, 2);
      expect(savedLatestKey.encryptedKey, 'rotated-key-abc');

      // Only Bob should receive the key (not Alice, not self)
      expect(sentMessages.length, 1);
      expect(sentMessages.first.$1, 'peer-bob');
      expect(
        sentMessages.map((entry) => entry.$1),
        isNot(contains('peer-alice')),
      );
      expect(
        sentMessages.map((entry) => entry.$1),
        isNot(contains(adminPeerId)),
      );

      // Verify it's a proper group_key_update envelope
      final envelope =
          jsonDecode(sentMessages.first.$2) as Map<String, dynamic>;
      expect(envelope['type'], 'group_key_update');
      expect(envelope['version'], '2');
      final keyPayload = _decodeDirectKeyUpdatePayload(sentMessages.first.$2);
      expect(keyPayload['groupId'], groupId);
      expect(keyPayload['recipientPeerId'], 'peer-bob');
      expect(keyPayload['keyGeneration'], 2);
      expect(keyPayload['encryptedKey'], 'rotated-key-abc');
    },
  );

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
    await receiverGroupRepo.saveMember(
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
      'sourcePeerId': adminPeerId,
      'keyGeneration': 2,
      'encryptedKey': 'rotated-key-abc',
      'signatureAlgorithm': groupKeyUpdateSignatureAlgorithm,
      'signedPayload': canonicalGroupKeyUpdateSignedPayload(
        groupId: groupId,
        sourcePeerId: adminPeerId,
        keyGeneration: 2,
        encryptedKey: 'rotated-key-abc',
      ),
      'signature': 'fake-signature',
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

  test(
    'direct membership update applies removal replay without relay drain',
    () async {
      final receiverBridge = PassthroughCryptoBridge();
      final receiverGroupRepo = InMemoryGroupRepository();
      final receiverMsgRepo = InMemoryGroupMessageRepository();
      final controller = StreamController<ChatMessage>.broadcast();
      final createdAt = DateTime.utc(2026, 5, 13, 8);

      await receiverGroupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Test Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdAt: createdAt,
          createdBy: adminPeerId,
          myRole: GroupRole.member,
        ),
      );
      await receiverGroupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: adminPeerId,
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          mlKemPublicKey: 'mlkem-pk-admin',
          joinedAt: createdAt,
        ),
      );
      await receiverGroupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-alice',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-pk-alice',
          joinedAt: createdAt,
        ),
      );
      await receiverGroupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'initial-key',
          createdAt: createdAt,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'initial-key',
          createdAt: createdAt,
        ),
      );

      final removedAt = createdAt.add(const Duration(minutes: 1));
      final sourceEventId =
          'member_removed:$groupId:$adminPeerId:${removedAt.microsecondsSinceEpoch}';
      final remainingMembers = (await groupRepo.getMembers(groupId))
          .where((member) => member.peerId != 'peer-alice')
          .toList(growable: false);
      final sysMessage = jsonEncode(<String, dynamic>{
        '__sys': 'member_removed',
        'member': <String, dynamic>{
          'peerId': 'peer-alice',
          'username': 'Alice',
        },
        'removedAt': removedAt.toIso8601String(),
        'groupConfig': buildGroupConfigPayload(
          (await groupRepo.getGroup(
            groupId,
          ))!.copyWith(lastMembershipEventAt: removedAt),
          remainingMembers,
        ),
      });
      final replayPlaintext = jsonEncode(<String, dynamic>{
        'groupId': groupId,
        'senderId': adminPeerId,
        'senderUsername': 'Admin',
        'text': sysMessage,
        'timestamp': removedAt.toIso8601String(),
        'messageId': sourceEventId,
      });
      final replayEnvelope = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: replayPlaintext,
        senderPeerId: adminPeerId,
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        messageId: sourceEventId,
        recipientPeerIds: const <String>['peer-alice'],
      );

      final groupListener = GroupMessageListener(
        groupRepo: receiverGroupRepo,
        msgRepo: receiverMsgRepo,
        bridge: receiverBridge,
        getSelfPeerId: () async => 'peer-alice',
      );
      final membershipListener = GroupMembershipUpdateListener(
        groupMembershipUpdateStream: controller.stream,
        groupRepo: receiverGroupRepo,
        bridge: receiverBridge,
        groupMessageListener: groupListener,
      );
      membershipListener.start();

      final removed = groupListener.groupRemovedStream.first;
      controller.add(
        ChatMessage(
          from: adminPeerId,
          to: 'peer-alice',
          content: buildGroupMembershipUpdateDirectEnvelope(
            groupId: groupId,
            senderPeerId: adminPeerId,
            replayEnvelope: replayEnvelope,
            timestamp: removedAt,
            messageId: sourceEventId,
          ),
          timestamp: removedAt.toIso8601String(),
          isIncoming: true,
        ),
      );

      expect(await removed.timeout(const Duration(seconds: 1)), groupId);
      expect(await receiverGroupRepo.getGroup(groupId), isNull);

      membershipListener.dispose();
      groupListener.dispose();
      await controller.close();
    },
  );

  test('direct membership update rejects relay sender mismatch', () async {
    final receiverBridge = PassthroughCryptoBridge();
    final receiverGroupRepo = InMemoryGroupRepository();
    final receiverMsgRepo = InMemoryGroupMessageRepository();
    final controller = StreamController<ChatMessage>.broadcast();
    final createdAt = DateTime.utc(2026, 5, 13, 8);

    await receiverGroupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Test Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: createdAt,
        createdBy: adminPeerId,
        myRole: GroupRole.member,
      ),
    );
    await receiverGroupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: adminPeerId,
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-admin',
        mlKemPublicKey: 'mlkem-pk-admin',
        joinedAt: createdAt,
      ),
    );
    await receiverGroupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-alice',
        username: 'Alice',
        role: MemberRole.writer,
        publicKey: 'pk-alice',
        mlKemPublicKey: 'mlkem-pk-alice',
        joinedAt: createdAt,
      ),
    );
    await receiverGroupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'initial-key',
        createdAt: createdAt,
      ),
    );

    final removedAt = createdAt.add(const Duration(minutes: 1));
    final sourceEventId =
        'member_removed:$groupId:$adminPeerId:${removedAt.microsecondsSinceEpoch}';
    final remainingMembers = (await groupRepo.getMembers(
      groupId,
    )).where((member) => member.peerId != 'peer-alice').toList(growable: false);
    final replayPlaintext = jsonEncode(<String, dynamic>{
      'groupId': groupId,
      'senderId': adminPeerId,
      'senderUsername': 'Admin',
      'text': jsonEncode(<String, dynamic>{
        '__sys': 'member_removed',
        'member': <String, dynamic>{
          'peerId': 'peer-alice',
          'username': 'Alice',
        },
        'removedAt': removedAt.toIso8601String(),
        'groupConfig': buildGroupConfigPayload(
          (await groupRepo.getGroup(
            groupId,
          ))!.copyWith(lastMembershipEventAt: removedAt),
          remainingMembers,
        ),
      }),
      'timestamp': removedAt.toIso8601String(),
      'messageId': sourceEventId,
    });
    final replayEnvelope = await buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: replayPlaintext,
      senderPeerId: adminPeerId,
      senderPublicKey: 'pk-admin',
      senderPrivateKey: 'sk-admin',
      messageId: sourceEventId,
      recipientPeerIds: const <String>['peer-alice'],
    );

    final groupListener = GroupMessageListener(
      groupRepo: receiverGroupRepo,
      msgRepo: receiverMsgRepo,
      bridge: receiverBridge,
      getSelfPeerId: () async => 'peer-alice',
    );
    final membershipListener = GroupMembershipUpdateListener(
      groupMembershipUpdateStream: controller.stream,
      groupRepo: receiverGroupRepo,
      bridge: receiverBridge,
      groupMessageListener: groupListener,
    );
    membershipListener.start();

    final removed = groupListener.groupRemovedStream.first;
    controller.add(
      ChatMessage(
        from: 'peer-impostor',
        to: 'peer-alice',
        content: buildGroupMembershipUpdateDirectEnvelope(
          groupId: groupId,
          senderPeerId: 'peer-impostor',
          replayEnvelope: replayEnvelope,
          timestamp: removedAt,
          messageId: sourceEventId,
        ),
        timestamp: removedAt.toIso8601String(),
        isIncoming: true,
      ),
    );

    await expectLater(
      removed.timeout(const Duration(milliseconds: 200)),
      throwsA(isA<TimeoutException>()),
    );
    expect(await receiverGroupRepo.getGroup(groupId), isNotNull);

    membershipListener.dispose();
    groupListener.dispose();
    await controller.close();
  });

  test('first post-removal send uses the rotated epoch', () async {
    final msgRepo = InMemoryGroupMessageRepository();
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'initial-key-epoch-1',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    bridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'msg-post-removal',
      'topicPeers': 1,
    };

    await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      memberPeerId: 'peer-alice',
    );

    final rotatedKey = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: adminPeerId,
      senderPublicKey: 'pk-admin',
      senderPrivateKey: 'sk-admin',
      senderUsername: 'Admin',
      sendP2PMessage: (_, _) async => true,
    );

    expect(rotatedKey, isNotNull);
    expect(rotatedKey!.keyGeneration, 2);

    final (result, message) = await group_send.sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: groupId,
      text: 'After removal',
      senderPeerId: adminPeerId,
      senderPublicKey: 'pk-admin',
      senderPrivateKey: 'sk-admin',
      senderUsername: 'Admin',
      messageId: 'msg-post-removal',
    );

    expect(result, group_send.SendGroupMessageResult.success);
    expect(message, isNotNull);
    expect(message!.keyGeneration, 2);
    expect(message.status, 'sent');

    final saved = await msgRepo.getMessage('msg-post-removal');
    expect(saved, isNotNull);
    expect(saved!.keyGeneration, 2);

    final inboxPayload = _lastGroupInboxStorePayload(bridge);
    final inboxEnvelope =
        jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
    expect(inboxEnvelope['keyEpoch'], 2);
    expect(inboxEnvelope['messageId'], 'msg-post-removal');

    final publishMessages = bridge.sentMessages
        .where(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        )
        .toList(growable: false);
    expect(publishMessages, hasLength(2));
    final lastPublishPayload =
        (jsonDecode(publishMessages.last) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    expect(lastPublishPayload['text'], 'After removal');
  });

  test(
    'EK004 voluntary leave stores signed member_removed replay envelope',
    () async {
      const leaverPeerId = 'peer-alice';
      final createdAt = DateTime.now().toUtc();
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Test Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdAt: createdAt,
          createdBy: leaverPeerId,
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: leaverPeerId,
          username: 'Alice',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(rotateKeys: true),
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-pk-alice',
          joinedAt: createdAt,
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
          joinedAt: createdAt.add(const Duration(seconds: 1)),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'initial-key-epoch-1',
          createdAt: createdAt,
        ),
      );
      bridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': 'rotated-leave-key-abc',
        'keyEpoch': 2,
      };
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'leave-sys-msg-id',
      };
      final identityRepo = FakeIdentityRepository()
        ..seed(
          IdentityModel(
            peerId: leaverPeerId,
            publicKey: 'pk-alice',
            privateKey: 'sk-alice',
            mnemonic12:
                'one two three four five six seven eight nine ten eleven twelve',
            mlKemPublicKey: 'mlkem-pk-alice',
            username: 'Alice',
            createdAt: createdAt.toIso8601String(),
            updatedAt: createdAt.toIso8601String(),
          ),
        );

      final result = await broadcastVoluntaryLeaveAndRotateKey(
        bridge: bridge,
        groupRepo: groupRepo,
        group: (await groupRepo.getGroup(groupId))!,
        identityRepo: identityRepo,
        msgRepo: InMemoryGroupMessageRepository(),
        sendP2PMessage: (_, _) async => true,
      );

      expect(result.didBroadcast, isTrue);
      final leaveInboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(
        leaveInboxPayload['recipientPeerIds'],
        unorderedEquals(<String>[adminPeerId, 'peer-bob']),
      );
      final leaveReplayEnvelope =
          jsonDecode(leaveInboxPayload['message'] as String)
              as Map<String, dynamic>;
      expect(leaveReplayEnvelope['kind'], 'group_offline_replay');
      expect(leaveReplayEnvelope['payloadType'], 'group_message');
      expect(leaveReplayEnvelope['keyEpoch'], 1);
      expect(leaveReplayEnvelope['senderPeerId'], leaverPeerId);
      expect(leaveReplayEnvelope['senderPublicKey'], 'pk-alice');
      expect(leaveReplayEnvelope['signatureAlgorithm'], 'ed25519');
      expect(leaveReplayEnvelope['signedPayload'], isA<String>());
      expect(leaveReplayEnvelope['signature'], isA<String>());
    },
  );

  test(
    'GM-015 blocked creator leave keeps remaining-member sends healthy',
    () async {
      const alicePeerId = 'peer-gm015-alice';
      const bobPeerId = 'peer-gm015-bob';
      const charliePeerId = 'peer-gm015-charlie';
      const gm015GroupId = 'group-gm015-creator-leave';
      final createdAt = DateTime.utc(2026, 5, 11, 1);
      final keyCreatedAt = createdAt.add(const Duration(seconds: 30));
      final msgRepo = InMemoryGroupMessageRepository();
      final keyUpdates = <(String, String)>[];

      await groupRepo.saveGroup(
        GroupModel(
          id: gm015GroupId,
          name: 'GM-015 Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$gm015GroupId',
          createdAt: createdAt,
          createdBy: alicePeerId,
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: gm015GroupId,
          peerId: alicePeerId,
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-gm015-alice',
          mlKemPublicKey: 'mlkem-pk-gm015-alice',
          joinedAt: createdAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: gm015GroupId,
          peerId: bobPeerId,
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-gm015-bob',
          mlKemPublicKey: 'mlkem-pk-gm015-bob',
          joinedAt: createdAt.add(const Duration(seconds: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: gm015GroupId,
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-gm015-charlie',
          mlKemPublicKey: 'mlkem-pk-gm015-charlie',
          joinedAt: createdAt.add(const Duration(seconds: 2)),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: gm015GroupId,
          keyGeneration: 1,
          encryptedKey: 'gm015-initial-key',
          createdAt: keyCreatedAt,
        ),
      );
      final identityRepo = FakeIdentityRepository()
        ..seed(
          IdentityModel(
            peerId: alicePeerId,
            publicKey: 'pk-gm015-alice',
            privateKey: 'sk-gm015-alice',
            mnemonic12:
                'one two three four five six seven eight nine ten eleven twelve',
            mlKemPublicKey: 'mlkem-pk-gm015-alice',
            username: 'Alice',
            createdAt: createdAt.toIso8601String(),
            updatedAt: createdAt.toIso8601String(),
          ),
        );

      final broadcastResult = await broadcastVoluntaryLeaveAndRotateKey(
        bridge: bridge,
        groupRepo: groupRepo,
        group: (await groupRepo.getGroup(gm015GroupId))!,
        identityRepo: identityRepo,
        msgRepo: msgRepo,
        sendP2PMessage: (peerId, message) async {
          keyUpdates.add((peerId, message));
          return true;
        },
      );

      expect(broadcastResult.didBroadcast, isFalse);
      expect(
        broadcastResult.skipReason,
        VoluntaryLeaveBroadcastSkipReason.lastAdmin,
      );
      expect(broadcastResult.remainingPeerIds, isEmpty);
      expect(broadcastResult.rotatedKey, isNull);
      expect(keyUpdates, isEmpty);
      expect(bridge.commandLog, isNot(contains('group:publish')));
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      expect(bridge.commandLog, isNot(contains('group:generateNextKey')));
      expect(await msgRepo.getMessageCount(gm015GroupId), 0);

      await expectLater(
        leaveGroup(bridge: bridge, groupRepo: groupRepo, groupId: gm015GroupId),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(lastAdminLeaveBlockedMessage),
          ),
        ),
      );

      final group = await groupRepo.getGroup(gm015GroupId);
      expect(group, isNotNull);
      expect(group!.createdBy, alicePeerId);
      expect(group.isDissolved, isFalse);
      final members = await groupRepo.getMembers(gm015GroupId);
      expect(members.map((member) => member.peerId), [
        alicePeerId,
        bobPeerId,
        charliePeerId,
      ]);
      expect(
        members.where((member) => member.role == MemberRole.admin),
        hasLength(1),
      );
      expect(
        members.singleWhere((member) => member.peerId == alicePeerId).role,
        MemberRole.admin,
      );
      final latestKey = await groupRepo.getLatestKey(gm015GroupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 1);
      expect(latestKey.encryptedKey, 'gm015-initial-key');
      expect(latestKey.createdAt, keyCreatedAt);
      expect(bridge.commandLog, isNot(contains('group:leave')));

      final (bobResult, bobMessage) = await group_send.sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: gm015GroupId,
        text: 'GM-015 Bob after blocked creator attempts',
        senderPeerId: bobPeerId,
        senderPublicKey: 'pk-gm015-bob',
        senderPrivateKey: 'sk-gm015-bob',
        senderUsername: 'Bob',
        messageId: 'gm015-bob-after-block',
      );
      final (charlieResult, charlieMessage) = await group_send.sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: gm015GroupId,
        text: 'GM-015 Charlie after blocked creator attempts',
        senderPeerId: charliePeerId,
        senderPublicKey: 'pk-gm015-charlie',
        senderPrivateKey: 'sk-gm015-charlie',
        senderUsername: 'Charlie',
        messageId: 'gm015-charlie-after-block',
      );

      expect(bobResult, group_send.SendGroupMessageResult.success);
      expect(charlieResult, group_send.SendGroupMessageResult.success);
      expect(bobMessage, isNotNull);
      expect(charlieMessage, isNotNull);
      expect(bobMessage!.keyGeneration, 1);
      expect(charlieMessage!.keyGeneration, 1);
      expect(bobMessage.status, 'sent');
      expect(charlieMessage.status, 'sent');

      final savedBob = await msgRepo.getMessage('gm015-bob-after-block');
      final savedCharlie = await msgRepo.getMessage(
        'gm015-charlie-after-block',
      );
      expect(savedBob, isNotNull);
      expect(savedCharlie, isNotNull);
      expect(savedBob!.status, 'sent');
      expect(savedCharlie!.status, 'sent');

      final inboxStores = bridge.sentMessages
          .where((message) {
            final parsed = jsonDecode(message) as Map<String, dynamic>;
            return parsed['cmd'] == 'group:inboxStore';
          })
          .toList(growable: false);
      expect(inboxStores, hasLength(2));
      final bobInboxPayload =
          (jsonDecode(inboxStores.first) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      final charlieInboxPayload =
          (jsonDecode(inboxStores.last) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      expect(
        bobInboxPayload['recipientPeerIds'],
        unorderedEquals(<String>[alicePeerId, charliePeerId]),
      );
      expect(
        charlieInboxPayload['recipientPeerIds'],
        unorderedEquals(<String>[alicePeerId, bobPeerId]),
      );
    },
  );

  test(
    'voluntary leave rotation excludes leaver and remaining members send on rotated epoch',
    () async {
      const leaverPeerId = 'peer-alice';
      final createdAt = DateTime.now().toUtc();
      final adminRepo = InMemoryGroupRepository();
      final bobRepo = InMemoryGroupRepository();
      final adminBridge = PassthroughCryptoBridge();
      final bobBridge = PassthroughCryptoBridge();
      final adminController = StreamController<ChatMessage>.broadcast();
      final bobController = StreamController<ChatMessage>.broadcast();
      final adminMsgRepo = InMemoryGroupMessageRepository();
      final leaverMsgRepo = InMemoryGroupMessageRepository();

      Future<void> seedRemainingRepo({
        required InMemoryGroupRepository repo,
        required GroupRole myRole,
      }) async {
        await repo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Test Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdAt: createdAt,
            createdBy: leaverPeerId,
            myRole: myRole,
          ),
        );
        await repo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: adminPeerId,
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
            joinedAt: createdAt,
          ),
        );
        await repo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: leaverPeerId,
            username: 'Alice',
            role: MemberRole.writer,
            permissions: const GroupMemberPermissions(rotateKeys: true),
            publicKey: 'pk-alice',
            mlKemPublicKey: 'mlkem-pk-alice',
            joinedAt: createdAt.add(const Duration(seconds: 1)),
          ),
        );
        await repo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-pk-bob',
            joinedAt: createdAt.add(const Duration(seconds: 2)),
          ),
        );
      }

      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Test Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdAt: createdAt,
          createdBy: leaverPeerId,
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: leaverPeerId,
          username: 'Alice',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(rotateKeys: true),
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-pk-alice',
          joinedAt: createdAt.add(const Duration(seconds: 1)),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'initial-key-epoch-1',
          createdAt: createdAt,
        ),
      );
      await seedRemainingRepo(repo: adminRepo, myRole: GroupRole.admin);
      await seedRemainingRepo(repo: bobRepo, myRole: GroupRole.member);

      final adminListener = GroupKeyUpdateListener(
        groupKeyUpdateStream: adminController.stream,
        groupRepo: adminRepo,
        bridge: adminBridge,
        getOwnMlKemSecretKey: () async => 'admin-mlkem-secret',
        getOwnPeerId: () async => adminPeerId,
        getOwnDeviceId: () async => adminPeerId,
      )..start();
      final bobListener = GroupKeyUpdateListener(
        groupKeyUpdateStream: bobController.stream,
        groupRepo: bobRepo,
        bridge: bobBridge,
        getOwnMlKemSecretKey: () async => 'bob-mlkem-secret',
        getOwnPeerId: () async => 'peer-bob',
        getOwnDeviceId: () async => 'peer-bob',
      )..start();
      addTearDown(() async {
        adminListener.dispose();
        bobListener.dispose();
        await adminController.close();
        await bobController.close();
      });

      bridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': 'rotated-leave-key-abc',
        'keyEpoch': 2,
      };
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'leave-sys-msg-id',
      };
      final keyUpdates = <(String, String)>[];
      final identityRepo = FakeIdentityRepository()
        ..seed(
          IdentityModel(
            peerId: leaverPeerId,
            publicKey: 'pk-alice',
            privateKey: 'sk-alice',
            mnemonic12:
                'one two three four five six seven eight nine ten eleven twelve',
            mlKemPublicKey: 'mlkem-pk-alice',
            username: 'Alice',
            createdAt: createdAt.toIso8601String(),
            updatedAt: createdAt.toIso8601String(),
          ),
        );

      final leaveResult = await broadcastVoluntaryLeaveAndRotateKey(
        bridge: bridge,
        groupRepo: groupRepo,
        group: (await groupRepo.getGroup(groupId))!,
        identityRepo: identityRepo,
        msgRepo: leaverMsgRepo,
        sendP2PMessage: (peerId, message) async {
          keyUpdates.add((peerId, message));
          return true;
        },
      );

      final rotatedKey = leaveResult.rotatedKey;
      expect(leaveResult.didBroadcast, isTrue);
      expect(
        leaveResult.remainingPeerIds,
        unorderedEquals(<String>[adminPeerId, 'peer-bob']),
      );
      expect(rotatedKey, isNotNull);
      expect(rotatedKey!.keyGeneration, 2);
      expect(
        keyUpdates.map((entry) => entry.$1),
        unorderedEquals(<String>[adminPeerId, 'peer-bob']),
      );
      expect(
        keyUpdates.map((entry) => entry.$1),
        isNot(contains(leaverPeerId)),
      );
      final leaveInboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(
        leaveInboxPayload['recipientPeerIds'],
        unorderedEquals(<String>[adminPeerId, 'peer-bob']),
      );
      final leaveReplayEnvelope =
          jsonDecode(leaveInboxPayload['message'] as String)
              as Map<String, dynamic>;
      expect(leaveReplayEnvelope['kind'], 'group_offline_replay');
      expect(leaveReplayEnvelope['payloadType'], 'group_message');
      expect(leaveReplayEnvelope['keyEpoch'], 1);
      expect(leaveReplayEnvelope['senderPeerId'], leaverPeerId);
      expect(leaveReplayEnvelope['senderPublicKey'], 'pk-alice');
      expect(leaveReplayEnvelope['signatureAlgorithm'], 'ed25519');
      expect(leaveReplayEnvelope['signedPayload'], isA<String>());
      expect(leaveReplayEnvelope['signature'], isA<String>());

      for (final update in keyUpdates) {
        final controller = update.$1 == adminPeerId
            ? adminController
            : bobController;
        controller.add(
          ChatMessage(
            from: leaverPeerId,
            to: update.$1,
            content: update.$2,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);

      final adminKey = await adminRepo.getLatestKey(groupId);
      final bobKey = await bobRepo.getLatestKey(groupId);
      expect(adminKey, isNotNull);
      expect(adminKey!.keyGeneration, 2);
      expect(adminKey.encryptedKey, 'rotated-leave-key-abc');
      expect(bobKey, isNotNull);
      expect(bobKey!.keyGeneration, 2);
      expect(bobKey.encryptedKey, 'rotated-leave-key-abc');
      expect(adminBridge.commandLog, contains('group:updateKey'));
      expect(bobBridge.commandLog, contains('group:updateKey'));

      await adminRepo.removeMember(groupId, leaverPeerId);
      await bobRepo.removeMember(groupId, leaverPeerId);
      await leaveGroup(bridge: bridge, groupRepo: groupRepo, groupId: groupId);

      expect(await groupRepo.getGroup(groupId), isNull);
      expect(await groupRepo.getMembers(groupId), isEmpty);
      expect(await groupRepo.getLatestKey(groupId), isNull);
      expect(bridge.commandLog, contains('group:leave'));

      adminBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-post-voluntary-leave',
        'topicPeers': 1,
      };
      final (result, message) = await group_send.sendGroupMessage(
        bridge: adminBridge,
        groupRepo: adminRepo,
        msgRepo: adminMsgRepo,
        groupId: groupId,
        text: 'After voluntary leave',
        senderPeerId: adminPeerId,
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        senderUsername: 'Admin',
        messageId: 'msg-post-voluntary-leave',
      );

      expect(result, group_send.SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.keyGeneration, 2);
      expect(message.status, 'sent');

      final inboxPayload = _lastGroupInboxStorePayload(adminBridge);
      expect(
        inboxPayload['recipientPeerIds'],
        unorderedEquals(<String>['peer-bob']),
      );
      final inboxEnvelope =
          jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
      expect(inboxEnvelope['keyEpoch'], 2);
      expect(inboxEnvelope['messageId'], 'msg-post-voluntary-leave');

      final normalDrainRetrieveCount = bridge.commandLog
          .where((command) => command == 'group:inboxRetrieveCursor')
          .length;
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: leaverMsgRepo,
      );
      expect(
        bridge.commandLog
            .where((command) => command == 'group:inboxRetrieveCursor')
            .length,
        normalDrainRetrieveCount,
      );

      bridge.responses['group:inboxRetrieveCursor'] = {
        'ok': true,
        'messages': [
          {
            'from': adminPeerId,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'message': inboxPayload['message'],
          },
        ],
        'cursor': '',
      };
      await drainGroupOfflineInboxForGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: leaverMsgRepo,
        groupId: groupId,
      );

      final leaverFutureMessage = await leaverMsgRepo.getMessage(
        'msg-post-voluntary-leave',
      );
      expect(leaverFutureMessage, isNull);
    },
  );

  test(
    'GM-017 removal installs remaining-member config without invoking stale member leave',
    () async {
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'gm017-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: 'peer-bob',
        selfPeerId: adminPeerId,
        actorUsername: 'Admin',
        msgRepo: InMemoryGroupMessageRepository(),
      );

      final updateConfigMessages = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:updateConfig')
          .toList(growable: false);
      expect(updateConfigMessages, hasLength(1));
      final payload = updateConfigMessages.single['payload'] as Map;
      final groupConfig = payload['groupConfig'] as Map;
      final members = (groupConfig['members'] as List).cast<Map>();
      expect(
        members.map((member) => member['peerId']),
        unorderedEquals(<String>[adminPeerId, 'peer-alice']),
      );
      expect(
        members.map((member) => member['peerId']),
        isNot(contains('peer-bob')),
      );
      expect(bridge.commandLog, isNot(contains('group:leave')));
      expect(await groupRepo.getMember(groupId, 'peer-bob'), isNull);
      expect(await groupRepo.getLatestKey(groupId), isNotNull);
    },
  );

  test(
    'GM-028 removal config excludes pre-existing empty PeerId member',
    () async {
      await groupRepo.saveMemberBypassingValidationForTest(
        GroupMember(
          groupId: groupId,
          peerId: '   ',
          username: 'Blank Peer',
          role: MemberRole.writer,
          publicKey: 'pk-gm028-blank',
          mlKemPublicKey: 'mlkem-gm028-blank',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'gm028-blank-device',
              transportPeerId: 'gm028-blank-device',
              deviceSigningPublicKey: 'pk-gm028-blank-device',
              mlKemPublicKey: 'mlkem-gm028-blank-device',
              keyPackageId: 'kp-gm028-blank-device',
              keyPackagePublicMaterial: 'public-kp-gm028-blank-device',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 11, 10, 45),
        ),
      );

      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: 'peer-alice',
        selfPeerId: adminPeerId,
        actorUsername: 'Admin',
        msgRepo: InMemoryGroupMessageRepository(),
      );

      final payload = _lastGroupUpdateConfigPayload(bridge);
      final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
      expect(
        isGroupConfigStateHashValid(groupId: groupId, groupConfig: groupConfig),
        isTrue,
      );
      final members = (groupConfig['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(members.map((member) => member['peerId']).toSet(), <String>{
        adminPeerId,
        'peer-bob',
      });
      expect(
        members.where(
          (member) => (member['peerId'] as String?)?.trim().isEmpty ?? true,
        ),
        isEmpty,
      );
      expect(jsonEncode(groupConfig), isNot(contains('gm028-blank-device')));
      expect(await groupRepo.getMember(groupId, 'peer-alice'), isNull);
    },
  );

  test(
    'GM-018 repeated post-removal sends keep durable recipients Bob-only',
    () async {
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'gm018-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: 'peer-alice',
        selfPeerId: adminPeerId,
        actorUsername: 'Admin',
        msgRepo: InMemoryGroupMessageRepository(),
      );

      bridge.sentMessages.clear();
      bridge.commandLog.clear();

      for (var i = 1; i <= 3; i++) {
        final messageId = 'gm018-alice-to-bob-$i';
        final (result, message) = await group_send.sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: InMemoryGroupMessageRepository(),
          groupId: groupId,
          text: 'GM-018 remaining member delivery $i',
          senderPeerId: adminPeerId,
          senderPublicKey: 'pk-admin',
          senderPrivateKey: 'sk-admin',
          senderUsername: 'Admin',
          messageId: messageId,
        );

        expect(
          result,
          isIn(<group_send.SendGroupMessageResult>[
            group_send.SendGroupMessageResult.success,
            group_send.SendGroupMessageResult.successNoPeers,
          ]),
        );
        expect(message, isNotNull);

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        expect(inboxPayload['recipientPeerIds'], <String>['peer-bob']);
        expect(inboxPayload['recipientPeerIds'], isNot(contains('peer-alice')));
        final inboxEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(inboxEnvelope['messageId'], messageId);
      }

      final remainingMembers = await groupRepo.getMembers(groupId);
      expect(
        remainingMembers.map((member) => member.peerId),
        unorderedEquals(<String>[adminPeerId, 'peer-bob']),
      );
    },
  );

  test(
    'GM-019 durable recipients exclude Charlie during removal and include Charlie after re-add',
    () async {
      const charliePeerId = 'peer-charlie';
      final baseAt = DateTime.utc(2026, 5, 11, 8);
      final removedAt = baseAt.add(const Duration(minutes: 10));
      final removedWindowSentAt = removedAt.add(const Duration(seconds: 1));
      final readdAt = removedAt.add(const Duration(minutes: 5));
      final group = await groupRepo.getGroup(groupId);
      await groupRepo.saveGroup(
        group!.copyWith(createdAt: baseAt.subtract(const Duration(minutes: 1))),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          mlKemPublicKey: 'mlkem-pk-bob',
          joinedAt: baseAt,
        ),
      );

      await groupRepo.removeMember(groupId, 'peer-alice');
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          mlKemPublicKey: 'mlkem-pk-charlie',
          joinedAt: baseAt,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'gm019-key',
          createdAt: baseAt,
        ),
      );

      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: charliePeerId,
        selfPeerId: adminPeerId,
        actorUsername: 'Admin',
        eventAt: removedAt,
        msgRepo: InMemoryGroupMessageRepository(),
      );

      await addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        newMember: GroupMember(
          groupId: groupId,
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          mlKemPublicKey: 'mlkem-pk-charlie',
          joinedAt: readdAt,
        ),
        selfPeerId: adminPeerId,
      );

      bridge.sentMessages.clear();
      bridge.commandLog.clear();

      final (removedResult, removedMessage) = await group_send.sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: InMemoryGroupMessageRepository(),
        groupId: groupId,
        text: 'GM-019 delayed removed-window message',
        senderPeerId: adminPeerId,
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        senderUsername: 'Admin',
        messageId: 'gm019-removed-window',
        timestamp: removedWindowSentAt,
      );

      expect(removedResult, group_send.SendGroupMessageResult.success);
      expect(removedMessage, isNotNull);
      final removedPayload = _groupInboxStorePayloadForMessage(
        bridge,
        'gm019-removed-window',
      );
      expect(removedPayload['recipientPeerIds'], <String>['peer-bob']);
      expect(
        removedPayload['recipientPeerIds'],
        isNot(contains(charliePeerId)),
      );

      final (postReaddResult, postReaddMessage) = await group_send
          .sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: InMemoryGroupMessageRepository(),
            groupId: groupId,
            text: 'GM-019 post-readd message',
            senderPeerId: adminPeerId,
            senderPublicKey: 'pk-admin',
            senderPrivateKey: 'sk-admin',
            senderUsername: 'Admin',
            messageId: 'gm019-post-readd',
            timestamp: readdAt.add(const Duration(seconds: 1)),
          );

      expect(postReaddResult, group_send.SendGroupMessageResult.success);
      expect(postReaddMessage, isNotNull);
      final postReaddPayload = _groupInboxStorePayloadForMessage(
        bridge,
        'gm019-post-readd',
      );
      expect(
        postReaddPayload['recipientPeerIds'],
        unorderedEquals(<String>['peer-bob', charliePeerId]),
      );
      expect(
        postReaddPayload['recipientPeerIds'],
        hasLength(
          (postReaddPayload['recipientPeerIds'] as List).toSet().length,
        ),
      );
    },
  );

  test(
    'GM-020 remove-then-send immediately keeps durable recipients Bob-only',
    () async {
      bridge = _InboxStoreFailPassthroughBridge();
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'gm020',
        'topicPeers': 2,
      };
      const charliePeerId = 'peer-charlie';
      final msgRepo = InMemoryGroupMessageRepository();
      final baseAt = DateTime.utc(2026, 5, 11, 8);
      final removedAt = baseAt.add(const Duration(minutes: 1));
      final firstSentAt = removedAt.add(const Duration(seconds: 1));
      final secondSentAt = removedAt.add(const Duration(seconds: 2));

      await groupRepo.removeMember(groupId, 'peer-alice');
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          mlKemPublicKey: 'mlkem-pk-charlie',
          joinedAt: baseAt,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'gm020-key',
          createdAt: baseAt,
        ),
      );

      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: charliePeerId,
        selfPeerId: adminPeerId,
        actorUsername: 'Admin',
        eventAt: removedAt,
        msgRepo: msgRepo,
      );

      bridge.sentMessages.clear();
      bridge.commandLog.clear();

      for (final proof in <({String id, String text, DateTime timestamp})>[
        (
          id: 'gm020-immediate-post-removal',
          text: 'GM-020 immediate post-removal send',
          timestamp: firstSentAt,
        ),
        (
          id: 'gm020-repeated-post-removal',
          text: 'GM-020 repeated post-removal send',
          timestamp: secondSentAt,
        ),
      ]) {
        final (result, message) = await group_send.sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: groupId,
          text: proof.text,
          senderPeerId: adminPeerId,
          senderPublicKey: 'pk-admin',
          senderPrivateKey: 'sk-admin',
          senderUsername: 'Admin',
          messageId: proof.id,
          timestamp: proof.timestamp,
        );

        expect(result, group_send.SendGroupMessageResult.success);
        expect(message, isNotNull);

        final payload = _groupInboxStorePayloadForMessage(bridge, proof.id);
        expect(payload['recipientPeerIds'], <String>['peer-bob']);
        expect(payload['recipientPeerIds'], isNot(contains(adminPeerId)));
        expect(payload['recipientPeerIds'], isNot(contains(charliePeerId)));
        expect(
          payload['recipientPeerIds'],
          hasLength((payload['recipientPeerIds'] as List).toSet().length),
        );

        final saved = await msgRepo.getMessage(proof.id);
        expect(saved?.inboxRetryPayload, isNotNull);
        expect(
          _recipientPeerIdsFromRetryPayload(saved!.inboxRetryPayload!),
          <String>['peer-bob'],
        );
      }
    },
  );

  test(
    'GM-021 re-add persists only fresh Charlie package and sends with it',
    () async {
      const charliePeerId = 'peer-charlie';
      const charlieDeviceId = 'charlie-device-active';
      const oldKeyPackageId = 'kp-charlie-old';
      const freshKeyPackageId = 'kp-charlie-fresh';
      final msgRepo = InMemoryGroupMessageRepository();
      final baseAt = DateTime.utc(2026, 5, 11, 8);
      final removedAt = baseAt.add(const Duration(minutes: 1));
      final readdAt = removedAt.add(const Duration(minutes: 5));

      GroupMember charlieMember(String keyPackageId, DateTime joinedAt) {
        return GroupMember(
          groupId: groupId,
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          mlKemPublicKey: 'mlkem-pk-charlie',
          devices: <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: charlieDeviceId,
              transportPeerId: charlieDeviceId,
              deviceSigningPublicKey: 'pk-charlie',
              mlKemPublicKey: 'mlkem-charlie-device',
              keyPackageId: keyPackageId,
              keyPackagePublicMaterial: 'public-$keyPackageId',
            ),
          ],
          joinedAt: joinedAt,
        );
      }

      await groupRepo.removeMember(groupId, 'peer-alice');
      await groupRepo.saveMember(charlieMember(oldKeyPackageId, baseAt));
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'gm021-key',
          createdAt: baseAt,
        ),
      );

      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: charliePeerId,
        selfPeerId: adminPeerId,
        actorUsername: 'Admin',
        eventAt: removedAt,
        msgRepo: msgRepo,
      );
      expect(await groupRepo.getMember(groupId, charliePeerId), isNull);

      await addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        newMember: charlieMember(freshKeyPackageId, readdAt),
        selfPeerId: adminPeerId,
      );

      final activeCharlie = await groupRepo.getMember(groupId, charliePeerId);
      expect(activeCharlie, isNotNull);
      expect(activeCharlie!.activeDevices, hasLength(1));
      expect(
        activeCharlie.activeDevices.single.keyPackageId,
        freshKeyPackageId,
      );
      expect(
        activeCharlie.activeDevices
            .map((device) => device.keyPackageId)
            .whereType<String>(),
        isNot(contains(oldKeyPackageId)),
      );

      final updateConfigPayload = _lastGroupUpdateConfigPayload(bridge);
      final groupConfig =
          updateConfigPayload['groupConfig'] as Map<String, dynamic>;
      final configMembers = (groupConfig['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final configCharlie = configMembers.singleWhere(
        (member) => member['peerId'] == charliePeerId,
      );
      final configDevices = (configCharlie['devices'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(configDevices, hasLength(1));
      expect(configDevices.single['keyPackageId'], freshKeyPackageId);
      expect(jsonEncode(groupConfig), isNot(contains(oldKeyPackageId)));

      bridge.sentMessages.clear();
      bridge.commandLog.clear();
      final (result, message) = await group_send.sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: 'GM-021 Charlie fresh package send',
        senderPeerId: charliePeerId,
        senderDeviceId: charlieDeviceId,
        senderTransportPeerId: charlieDeviceId,
        senderPublicKey: 'pk-charlie',
        senderPrivateKey: 'sk-charlie',
        senderUsername: 'Charlie',
        messageId: 'gm021-charlie-fresh-send',
        timestamp: readdAt.add(const Duration(seconds: 1)),
      );

      expect(result, group_send.SendGroupMessageResult.success);
      expect(message, isNotNull);
      final publishPayload = _groupPublishPayloadForMessage(
        bridge,
        'gm021-charlie-fresh-send',
      );
      expect(publishPayload['senderDeviceId'], charlieDeviceId);
      expect(publishPayload['senderTransportPeerId'], charlieDeviceId);
      expect(publishPayload['senderKeyPackageId'], freshKeyPackageId);

      final inboxPayload = _groupInboxStorePayloadForMessage(
        bridge,
        'gm021-charlie-fresh-send',
      );
      final replayEnvelope =
          jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
      expect(replayEnvelope['senderKeyPackageId'], freshKeyPackageId);
      expect(jsonEncode(replayEnvelope), isNot(contains(oldKeyPackageId)));
    },
  );

  test(
    'GM-022 twenty remove re-add cycles leave one Charlie and unique durable recipients',
    () async {
      const charliePeerId = 'peer-charlie';
      const charlieDeviceId = 'charlie-device-active';
      final msgRepo = InMemoryGroupMessageRepository();
      final baseAt = DateTime.utc(2026, 5, 11, 9);

      GroupMember charlieMember(int cycle, DateTime joinedAt) {
        final keyPackageId = 'kp-gm022-charlie-$cycle';
        return GroupMember(
          groupId: groupId,
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          mlKemPublicKey: 'mlkem-pk-charlie',
          devices: <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: charlieDeviceId,
              transportPeerId: charlieDeviceId,
              deviceSigningPublicKey: 'pk-charlie',
              mlKemPublicKey: 'mlkem-charlie-device',
              keyPackageId: keyPackageId,
              keyPackagePublicMaterial: 'public-$keyPackageId',
            ),
          ],
          joinedAt: joinedAt,
        );
      }

      await groupRepo.removeMember(groupId, 'peer-alice');
      await groupRepo.saveMember(charlieMember(0, baseAt));
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 2,
          encryptedKey: 'gm022-key',
          createdAt: baseAt,
        ),
      );

      for (var cycle = 1; cycle <= 20; cycle++) {
        final removedAt = baseAt.add(Duration(minutes: cycle * 2));
        final readdAt = removedAt.add(const Duration(minutes: 1));
        await removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          memberPeerId: charliePeerId,
          selfPeerId: adminPeerId,
          actorUsername: 'Admin',
          eventAt: removedAt,
          msgRepo: msgRepo,
        );
        expect(await groupRepo.getMember(groupId, charliePeerId), isNull);

        await addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          newMember: charlieMember(cycle, readdAt),
          selfPeerId: adminPeerId,
        );

        final members = await groupRepo.getMembers(groupId);
        final peerIds = members.map((member) => member.peerId).toList();
        expect(peerIds.where((peerId) => peerId == charliePeerId), [
          charliePeerId,
        ]);
        expect(peerIds, hasLength(peerIds.toSet().length));

        final updateConfigPayload = _lastGroupUpdateConfigPayload(bridge);
        final groupConfig =
            updateConfigPayload['groupConfig'] as Map<String, dynamic>;
        final configMembers = (groupConfig['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final configPeerIds = configMembers
            .map((member) => member['peerId'] as String)
            .toList();
        expect(configPeerIds.where((peerId) => peerId == charliePeerId), [
          charliePeerId,
        ]);
        expect(configPeerIds, hasLength(configPeerIds.toSet().length));
        final charlieConfig = configMembers.singleWhere(
          (member) => member['peerId'] == charliePeerId,
        );
        final devices = (charlieConfig['devices'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(devices, hasLength(1));
        expect(devices.single['keyPackageId'], 'kp-gm022-charlie-$cycle');
      }

      bridge.sentMessages.clear();
      bridge.commandLog.clear();
      final (result, message) = await group_send.sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: 'GM-022 Charlie after repeated re-add',
        senderPeerId: charliePeerId,
        senderDeviceId: charlieDeviceId,
        senderTransportPeerId: charlieDeviceId,
        senderPublicKey: 'pk-charlie',
        senderPrivateKey: 'sk-charlie',
        senderUsername: 'Charlie',
        messageId: 'gm022-charlie-after-readd',
        timestamp: baseAt.add(const Duration(hours: 2)),
      );

      expect(result, group_send.SendGroupMessageResult.success);
      expect(message, isNotNull);
      final publishPayload = _groupPublishPayloadForMessage(
        bridge,
        'gm022-charlie-after-readd',
      );
      expect(publishPayload['senderDeviceId'], charlieDeviceId);
      expect(publishPayload['senderKeyPackageId'], 'kp-gm022-charlie-20');

      final inboxPayload = _groupInboxStorePayloadForMessage(
        bridge,
        'gm022-charlie-after-readd',
      );
      final recipients = (inboxPayload['recipientPeerIds'] as List<dynamic>)
          .cast<String>();
      expect(recipients.toSet(), {adminPeerId, 'peer-bob'});
      expect(recipients, hasLength(recipients.toSet().length));
      expect(recipients, isNot(contains(charliePeerId)));
      final replayEnvelope =
          jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
      expect(replayEnvelope['senderKeyPackageId'], 'kp-gm022-charlie-20');
    },
  );

  test(
    'GM-023 inactive Charlie shadow before active Charlie keeps durable recipients unique',
    () async {
      const charliePeerId = 'peer-charlie';
      const charlieDeviceId = 'charlie-device-active';
      const inactiveKeyPackageId = 'kp-gm023-charlie-inactive';
      const activeKeyPackageId = 'kp-gm023-charlie-active';
      final msgRepo = InMemoryGroupMessageRepository();
      final baseAt = DateTime.utc(2026, 5, 11, 10);

      GroupMember charlieMember({
        required String keyPackageId,
        required DateTime joinedAt,
        required GroupMemberDeviceStatus status,
        DateTime? revokedAt,
      }) {
        return GroupMember(
          groupId: groupId,
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          mlKemPublicKey: 'mlkem-pk-charlie',
          devices: <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: charlieDeviceId,
              transportPeerId: charlieDeviceId,
              deviceSigningPublicKey: 'pk-charlie',
              mlKemPublicKey: 'mlkem-charlie-device',
              keyPackageId: keyPackageId,
              keyPackagePublicMaterial: 'public-$keyPackageId',
              status: status,
              revokedAt: revokedAt,
            ),
          ],
          joinedAt: joinedAt,
        );
      }

      await groupRepo.removeMember(groupId, 'peer-alice');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 2,
          encryptedKey: 'gm023-key',
          createdAt: baseAt,
        ),
      );
      final group = await groupRepo.getGroup(groupId);
      final admin = await groupRepo.getMember(groupId, adminPeerId);
      final bob = await groupRepo.getMember(groupId, 'peer-bob');
      final inactiveShadow = charlieMember(
        keyPackageId: inactiveKeyPackageId,
        joinedAt: baseAt,
        status: GroupMemberDeviceStatus.revoked,
        revokedAt: baseAt.add(const Duration(minutes: 1)),
      );
      final activeCharlie = charlieMember(
        keyPackageId: activeKeyPackageId,
        joinedAt: baseAt.add(const Duration(minutes: 10)),
        status: GroupMemberDeviceStatus.active,
      );

      final groupConfig = buildGroupConfigPayload(group!, [
        admin!,
        inactiveShadow,
        bob!,
        activeCharlie,
      ]);
      final configMembers = (groupConfig['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        configMembers
            .map((member) => member['peerId'])
            .where((peerId) => peerId == charliePeerId),
        [charliePeerId],
      );
      final charlieConfig = configMembers.singleWhere(
        (member) => member['peerId'] == charliePeerId,
      );
      final configDevices = (charlieConfig['devices'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(configDevices, hasLength(1));
      expect(configDevices.single['status'], 'active');
      expect(configDevices.single['keyPackageId'], activeKeyPackageId);
      expect(jsonEncode(groupConfig), isNot(contains(inactiveKeyPackageId)));

      await groupRepo.saveMember(activeCharlie);
      bridge.sentMessages.clear();
      bridge.commandLog.clear();
      final (result, message) = await group_send.sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: 'GM-023 Charlie after inactive shadow',
        senderPeerId: charliePeerId,
        senderDeviceId: charlieDeviceId,
        senderTransportPeerId: charlieDeviceId,
        senderPublicKey: 'pk-charlie',
        senderPrivateKey: 'sk-charlie',
        senderUsername: 'Charlie',
        messageId: 'gm023-charlie-after-inactive-shadow',
        timestamp: baseAt.add(const Duration(hours: 1)),
      );

      expect(result, group_send.SendGroupMessageResult.success);
      expect(message, isNotNull);
      final inboxPayload = _groupInboxStorePayloadForMessage(
        bridge,
        'gm023-charlie-after-inactive-shadow',
      );
      final recipients = (inboxPayload['recipientPeerIds'] as List<dynamic>)
          .cast<String>();
      expect(recipients.toSet(), {adminPeerId, 'peer-bob'});
      expect(recipients, hasLength(recipients.toSet().length));
      expect(recipients, isNot(contains(charliePeerId)));
      final replayEnvelope =
          jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
      expect(replayEnvelope['senderKeyPackageId'], activeKeyPackageId);
      expect(jsonEncode(replayEnvelope), isNot(contains(inactiveKeyPackageId)));
    },
  );

  test(
    'GM-024 member display state converges after Charlie remove and re-add',
    () async {
      const alicePeerId = adminPeerId;
      const bobPeerId = 'peer-bob';
      const charliePeerId = 'peer-charlie';
      const aliceDeviceId = 'alice-device-current';
      const bobDeviceId = 'bob-device-current';
      const charlieDeviceId = 'charlie-device-current';
      const charlieKeyPackageId = 'kp-gm024-charlie-current';
      final msgRepo = InMemoryGroupMessageRepository();
      final baseAt = DateTime.utc(2026, 5, 11, 11);
      final removedAt = baseAt.add(const Duration(minutes: 1));
      final readdAt = baseAt.add(const Duration(minutes: 5));

      GroupMemberDeviceIdentity device({
        required String deviceId,
        required String publicKey,
        String? keyPackageId,
      }) {
        return GroupMemberDeviceIdentity(
          deviceId: deviceId,
          transportPeerId: deviceId,
          deviceSigningPublicKey: publicKey,
          mlKemPublicKey: 'mlkem-$deviceId',
          keyPackageId: keyPackageId ?? 'kp-$deviceId',
          keyPackagePublicMaterial: 'public-${keyPackageId ?? 'kp-$deviceId'}',
        );
      }

      Future<void> bindActiveDevice({
        required String peerId,
        required String publicKey,
        required String deviceId,
      }) async {
        final member = await groupRepo.getMember(groupId, peerId);
        expect(member, isNotNull);
        await groupRepo.saveMember(
          member!.copyWith(
            devices: <GroupMemberDeviceIdentity>[
              device(deviceId: deviceId, publicKey: publicKey),
            ],
          ),
        );
      }

      await groupRepo.removeMember(groupId, 'peer-alice');
      await bindActiveDevice(
        peerId: alicePeerId,
        publicKey: 'pk-admin',
        deviceId: aliceDeviceId,
      );
      await bindActiveDevice(
        peerId: bobPeerId,
        publicKey: 'pk-bob',
        deviceId: bobDeviceId,
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 2,
          encryptedKey: 'gm024-key',
          createdAt: baseAt,
        ),
      );

      final initialCharlie = GroupMember(
        groupId: groupId,
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        publicKey: 'pk-charlie',
        mlKemPublicKey: 'mlkem-pk-charlie',
        devices: <GroupMemberDeviceIdentity>[
          device(
            deviceId: charlieDeviceId,
            publicKey: 'pk-charlie',
            keyPackageId: 'kp-gm024-charlie-old',
          ),
        ],
        joinedAt: baseAt,
      );
      await groupRepo.saveMember(initialCharlie);

      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: charliePeerId,
        selfPeerId: alicePeerId,
        actorUsername: 'Alice',
        eventAt: removedAt,
        msgRepo: msgRepo,
      );
      expect(await groupRepo.getMember(groupId, charliePeerId), isNull);

      final readdedCharlie = initialCharlie.copyWith(
        joinedAt: readdAt,
        devices: <GroupMemberDeviceIdentity>[
          device(
            deviceId: charlieDeviceId,
            publicKey: 'pk-charlie',
            keyPackageId: charlieKeyPackageId,
          ),
        ],
      );
      await addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        newMember: readdedCharlie,
        selfPeerId: alicePeerId,
      );

      final members = await groupRepo.getMembers(groupId);
      final memberPeerIds = members.map((member) => member.peerId).toList();
      expect(memberPeerIds.toSet(), {alicePeerId, bobPeerId, charliePeerId});
      expect(memberPeerIds, hasLength(memberPeerIds.toSet().length));

      final charlieRows = members
          .where((member) => member.peerId == charliePeerId)
          .toList(growable: false);
      expect(charlieRows, hasLength(1));
      expect(charlieRows.single.role, MemberRole.writer);
      expect(charlieRows.single.joinedAt, readdAt);
      expect(charlieRows.single.activeDevices, hasLength(1));
      expect(
        charlieRows.single.activeDevices.single.transportPeerId,
        charlieDeviceId,
      );
      expect(
        charlieRows.single.activeDevices.single.keyPackageId,
        charlieKeyPackageId,
      );
      expect(await groupRepo.getLatestKey(groupId), isNotNull);
      expect((await groupRepo.getLatestKey(groupId))!.keyGeneration, 2);

      final updateConfigPayload = _lastGroupUpdateConfigPayload(bridge);
      final groupConfig =
          updateConfigPayload['groupConfig'] as Map<String, dynamic>;
      final configMembers = (groupConfig['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(configMembers.map((member) => member['peerId']).toSet(), {
        alicePeerId,
        bobPeerId,
        charliePeerId,
      });
      final configCharlie = configMembers.singleWhere(
        (member) => member['peerId'] == charliePeerId,
      );
      expect(configCharlie['role'], 'writer');
      final configDevices = (configCharlie['devices'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(configDevices, hasLength(1));
      expect(configDevices.single['transportPeerId'], charlieDeviceId);
      expect(configDevices.single['keyPackageId'], charlieKeyPackageId);

      Future<Map<String, dynamic>> sendAndAssert({
        required String senderPeerId,
        required String senderUsername,
        required String senderPublicKey,
        required String senderPrivateKey,
        required String senderDeviceId,
        required String messageId,
        required String text,
        required Set<String> expectedRecipients,
        required DateTime timestamp,
      }) async {
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': messageId,
          'topicPeers': expectedRecipients.length,
        };
        final (result, message) = await group_send.sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: groupId,
          text: text,
          senderPeerId: senderPeerId,
          senderDeviceId: senderDeviceId,
          senderTransportPeerId: senderDeviceId,
          senderPublicKey: senderPublicKey,
          senderPrivateKey: senderPrivateKey,
          senderUsername: senderUsername,
          messageId: messageId,
          timestamp: timestamp,
        );

        expect(result, group_send.SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message.keyGeneration, 2);

        final publishPayload = _groupPublishPayloadForMessage(
          bridge,
          messageId,
        );
        expect(publishPayload['senderPeerId'], senderPeerId);
        expect(publishPayload['senderDeviceId'], senderDeviceId);
        expect(publishPayload['senderTransportPeerId'], senderDeviceId);

        final inboxPayload = _groupInboxStorePayloadForMessage(
          bridge,
          messageId,
        );
        final recipients = (inboxPayload['recipientPeerIds'] as List<dynamic>)
            .cast<String>();
        expect(recipients.toSet(), expectedRecipients);
        expect(recipients, hasLength(recipients.toSet().length));
        final replayEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(replayEnvelope['senderDeviceId'], senderDeviceId);
        expect(replayEnvelope['senderTransportPeerId'], senderDeviceId);
        if (senderPeerId == charliePeerId) {
          expect(replayEnvelope['senderKeyPackageId'], charlieKeyPackageId);
        }
        return <String, dynamic>{
          'messageId': messageId,
          'senderPeerId': senderPeerId,
          'senderDeviceId': senderDeviceId,
          'keyEpoch': message.keyGeneration,
          'topicPeerCount': expectedRecipients.length,
          'recipientPeerIds': recipients,
          'actualDurablePayloadProof': true,
        };
      }

      final aliceSend = await sendAndAssert(
        senderPeerId: alicePeerId,
        senderUsername: 'Alice',
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        senderDeviceId: aliceDeviceId,
        messageId: 'gm024-alice-after-readd',
        text: 'GM-024 Alice after Charlie re-add',
        expectedRecipients: {bobPeerId, charliePeerId},
        timestamp: readdAt.add(const Duration(seconds: 1)),
      );
      final bobSend = await sendAndAssert(
        senderPeerId: bobPeerId,
        senderUsername: 'Bob',
        senderPublicKey: 'pk-bob',
        senderPrivateKey: 'sk-bob',
        senderDeviceId: bobDeviceId,
        messageId: 'gm024-bob-after-readd',
        text: 'GM-024 Bob after Charlie re-add',
        expectedRecipients: {alicePeerId, charliePeerId},
        timestamp: readdAt.add(const Duration(seconds: 2)),
      );
      final charlieSend = await sendAndAssert(
        senderPeerId: charliePeerId,
        senderUsername: 'Charlie',
        senderPublicKey: 'pk-charlie',
        senderPrivateKey: 'sk-charlie',
        senderDeviceId: charlieDeviceId,
        messageId: 'gm024-charlie-after-readd',
        text: 'GM-024 Charlie after re-add',
        expectedRecipients: {alicePeerId, bobPeerId},
        timestamp: readdAt.add(const Duration(seconds: 3)),
      );

      for (final proof in <Map<String, dynamic>>[
        aliceSend,
        bobSend,
        charlieSend,
      ]) {
        expect(proof['topicPeerCount'], 2);
        expect(proof['actualDurablePayloadProof'], isTrue);
      }
    },
  );

  test(
    'GM-025 re-add replaces Charlie role permissions before action policy',
    () async {
      const alicePeerId = adminPeerId;
      const bobPeerId = 'peer-bob';
      const charliePeerId = 'peer-charlie';
      final msgRepo = InMemoryGroupMessageRepository();
      final baseAt = DateTime.utc(2026, 5, 11, 12);
      final removedAt = baseAt.add(const Duration(minutes: 1));
      final readdAt = baseAt.add(const Duration(minutes: 5));

      await groupRepo.removeMember(groupId, 'peer-alice');

      final oldCharlie = GroupMember(
        groupId: groupId,
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        permissions: const GroupMemberPermissions(removeMembers: true),
        publicKey: 'pk-charlie',
        mlKemPublicKey: 'mlkem-pk-charlie',
        devices: const <GroupMemberDeviceIdentity>[
          GroupMemberDeviceIdentity(
            deviceId: 'charlie-device-old',
            transportPeerId: 'charlie-device-old',
            deviceSigningPublicKey: 'pk-charlie',
            mlKemPublicKey: 'mlkem-charlie-device-old',
            keyPackageId: 'kp-gm025-charlie-old',
            keyPackagePublicMaterial: 'public-kp-gm025-charlie-old',
          ),
        ],
        joinedAt: baseAt,
      );
      await groupRepo.saveMember(oldCharlie);
      expect(
        oldCharlie.permissions.allows(
          GroupMemberPermission.removeMembers,
          oldCharlie.role,
        ),
        isTrue,
      );

      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: charliePeerId,
        selfPeerId: alicePeerId,
        actorUsername: 'Alice',
        eventAt: removedAt,
        msgRepo: msgRepo,
      );
      expect(await groupRepo.getMember(groupId, charliePeerId), isNull);

      final readdedCharlie = GroupMember(
        groupId: groupId,
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        permissions: GroupMemberPermissions.empty,
        publicKey: 'pk-charlie',
        mlKemPublicKey: 'mlkem-pk-charlie',
        devices: const <GroupMemberDeviceIdentity>[
          GroupMemberDeviceIdentity(
            deviceId: 'charlie-device-current',
            transportPeerId: 'charlie-device-current',
            deviceSigningPublicKey: 'pk-charlie',
            mlKemPublicKey: 'mlkem-charlie-device-current',
            keyPackageId: 'kp-gm025-charlie-current',
            keyPackagePublicMaterial: 'public-kp-gm025-charlie-current',
          ),
        ],
        joinedAt: readdAt,
      );
      await addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        newMember: readdedCharlie,
        selfPeerId: alicePeerId,
      );

      final members = await groupRepo.getMembers(groupId);
      final charlieRows = members
          .where((member) => member.peerId == charliePeerId)
          .toList(growable: false);
      expect(charlieRows, hasLength(1));
      final currentCharlie = charlieRows.single;
      expect(currentCharlie.role, MemberRole.writer);
      expect(currentCharlie.joinedAt, readdAt);
      expect(currentCharlie.permissions.removeMembers, isNull);
      expect(
        currentCharlie.permissions.allows(
          GroupMemberPermission.removeMembers,
          currentCharlie.role,
        ),
        isFalse,
      );

      final updateConfigPayload = _lastGroupUpdateConfigPayload(bridge);
      final groupConfig =
          updateConfigPayload['groupConfig'] as Map<String, dynamic>;
      final configMembers = (groupConfig['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        configMembers
            .map((member) => member['peerId'])
            .where((peerId) => peerId == charliePeerId),
        [charliePeerId],
      );
      final configCharlie = configMembers.singleWhere(
        (member) => member['peerId'] == charliePeerId,
      );
      expect(configCharlie['role'], 'writer');
      expect(configCharlie['permissions'], isNull);
      final configDevices = (configCharlie['devices'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(configDevices, hasLength(1));
      expect(configDevices.single['keyPackageId'], 'kp-gm025-charlie-current');
      expect(jsonEncode(groupConfig), isNot(contains('kp-gm025-charlie-old')));
      expect(jsonEncode(groupConfig), isNot(contains('"removeMembers":true')));

      await expectLater(
        removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          memberPeerId: bobPeerId,
          selfPeerId: charliePeerId,
          actorUsername: 'Charlie',
          eventAt: readdAt.add(const Duration(seconds: 1)),
          msgRepo: msgRepo,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await groupRepo.getMember(groupId, bobPeerId), isNotNull);
      expect(
        bridge.commandLog.where((command) => command == 'group:updateConfig'),
        hasLength(2),
      );
    },
  );
}
