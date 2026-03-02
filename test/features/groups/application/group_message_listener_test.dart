import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeBridge bridge;
  late GroupMessageListener listener;
  late StreamController<Map<String, dynamic>> sourceController;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    bridge = FakeBridge();
    sourceController = StreamController<Map<String, dynamic>>.broadcast();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-1',
      peerId: 'peer-sender',
      username: 'Sender',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    ));

    listener = GroupMessageListener(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      bridge: bridge,
    );
  });

  tearDown(() {
    listener.dispose();
    sourceController.close();
  });

  test('processes valid message', () async {
    listener.start(sourceController.stream);

    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Hello group!',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    // Allow async processing
    await Future.delayed(const Duration(milliseconds: 50));

    expect(msgRepo.count, 1);
    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest!.text, 'Hello group!');
  });

  test('ignores message for unknown group', () async {
    listener.start(sourceController.stream);

    sourceController.add({
      'groupId': 'unknown-group',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Hello',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    expect(msgRepo.count, 0);
  });

  test('emits to stream on valid message', () async {
    listener.start(sourceController.stream);

    final messages = <GroupMessage>[];
    final subscription = listener.groupMessageStream.listen(messages.add);

    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Streamed message',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    expect(messages.length, 1);
    expect(messages.first.text, 'Streamed message');

    await subscription.cancel();
  });

  test('disposes correctly', () async {
    listener.start(sourceController.stream);
    listener.dispose();

    // After disposal, adding data should not cause errors
    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'After dispose',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    // Message was not processed because subscription was cancelled
    expect(msgRepo.count, 0);
  });

  test('handles malformed data without crashing', () async {
    listener.start(sourceController.stream);

    // Missing required fields
    sourceController.add({
      'groupId': '',
      'senderId': '',
    });

    await Future.delayed(const Duration(milliseconds: 50));

    // Should not crash; message ignored
    expect(msgRepo.count, 0);
  });

  group('system messages', () {
    test('member_added saves member and calls updateConfig', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_added',
        'member': {
          'peerId': 'peer-charlie',
          'username': 'Charlie',
          'role': 'writer',
          'publicKey': 'pk-charlie',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
            {
              'peerId': 'peer-charlie',
              'role': 'writer',
              'publicKey': 'pk-charlie',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // System message should NOT be saved as a regular message
      expect(msgRepo.count, 0);

      // New member should be saved to the group repo
      final charlie = await groupRepo.getMember('group-1', 'peer-charlie');
      expect(charlie, isNotNull);
      expect(charlie!.username, 'Charlie');
      expect(charlie.role, MemberRole.writer);

      // Bridge should have received group:updateConfig
      expect(bridge.commandLog, contains('group:updateConfig'));
    });

    test('member_added is not emitted on groupMessageStream', () async {
      listener.start(sourceController.stream);

      final messages = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(messages.add);

      final sysText = jsonEncode({
        '__sys': 'member_added',
        'member': {
          'peerId': 'peer-charlie',
          'username': 'Charlie',
          'role': 'writer',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // No message emitted to the UI stream
      expect(messages, isEmpty);

      await subscription.cancel();
    });

    test('system message without bridge falls through as regular message',
        () async {
      // Create listener without bridge
      final noBridgeListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );
      noBridgeListener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_added',
        'member': {'peerId': 'peer-charlie'},
        'groupConfig': {},
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // Without bridge, treated as regular message and saved
      expect(msgRepo.count, 1);

      noBridgeListener.dispose();
    });
  });
}
