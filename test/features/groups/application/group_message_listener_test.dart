import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

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

    test('members_added saves all members and calls updateConfig', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'members_added',
        'members': [
          {
            'peerId': 'peer-dave',
            'username': 'Dave',
            'role': 'writer',
            'publicKey': 'pk-dave',
          },
          {
            'peerId': 'peer-eve',
            'username': 'Eve',
            'role': 'writer',
            'publicKey': 'pk-eve',
          },
        ],
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {
              'peerId': 'peer-admin',
              'role': 'admin',
              'publicKey': 'pk-admin',
            },
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
            {
              'peerId': 'peer-dave',
              'role': 'writer',
              'publicKey': 'pk-dave',
            },
            {
              'peerId': 'peer-eve',
              'role': 'writer',
              'publicKey': 'pk-eve',
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

      // Both members saved
      final dave = await groupRepo.getMember('group-1', 'peer-dave');
      expect(dave, isNotNull);
      expect(dave!.username, 'Dave');
      final eve = await groupRepo.getMember('group-1', 'peer-eve');
      expect(eve, isNotNull);
      expect(eve!.username, 'Eve');

      // Config updated once
      final updateConfigCalls = bridge.commandLog
          .where((c) => c == 'group:updateConfig')
          .length;
      expect(updateConfigCalls, 1);

      // Not saved as regular message
      expect(msgRepo.count, 0);
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

  group('member_removed system messages', () {
    test('member_removed removes other member and calls updateConfig',
        () async {
      // Verify the member exists first
      final before = await groupRepo.getMember('group-1', 'peer-sender');
      expect(before, isNotNull);

      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {
          'peerId': 'peer-sender',
          'username': 'Sender',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {
              'peerId': 'peer-admin',
              'role': 'admin',
              'publicKey': 'pk-admin',
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

      // Member should be removed from the group repo
      final after = await groupRepo.getMember('group-1', 'peer-sender');
      expect(after, isNull);

      // Bridge should have received group:updateConfig
      expect(bridge.commandLog, contains('group:updateConfig'));
    });

    test('member_removed is not emitted on groupMessageStream', () async {
      listener.start(sourceController.stream);

      final messages = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(messages.add);

      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {
          'peerId': 'peer-sender',
          'username': 'Sender',
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

    test('self-removal calls leaveGroup and emits on groupRemovedStream',
        () async {
      // Create a listener that knows its own peerId
      final selfListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );

      // Add self as a member of the group
      await groupRepo.saveMember(GroupMember(
        groupId: 'group-1',
        peerId: 'peer-self',
        username: 'Me',
        role: MemberRole.writer,
        joinedAt: DateTime.now().toUtc(),
      ));

      selfListener.start(sourceController.stream);

      final removedGroups = <String>[];
      final sub = selfListener.groupRemovedStream.listen(removedGroups.add);

      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {
          'peerId': 'peer-self',
          'username': 'Me',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin'},
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

      // Bridge should have received group:leave
      expect(bridge.commandLog, contains('group:leave'));

      // Group should be deleted from local DB
      final group = await groupRepo.getGroup('group-1');
      expect(group, isNull);

      // groupRemovedStream should have emitted the group ID
      expect(removedGroups, ['group-1']);

      // No regular message saved
      expect(msgRepo.count, 0);

      await sub.cancel();
      selfListener.dispose();
    });

    test('handles key_rotated system message without error', () async {
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
      );
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'key_rotated',
        'newKeyEpoch': 2,
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

      // No crash, no error — just handled gracefully
    });

    test('removal of other member does NOT call leaveGroup', () async {
      // Create a listener that knows its own peerId
      final selfListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      selfListener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {
          'peerId': 'peer-sender',
          'username': 'Sender',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin'},
            {'peerId': 'peer-self', 'role': 'writer'},
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

      // Bridge should NOT have received group:leave
      expect(bridge.commandLog, isNot(contains('group:leave')));

      // Bridge should have received group:updateConfig
      expect(bridge.commandLog, contains('group:updateConfig'));

      // Group should still exist
      final group = await groupRepo.getGroup('group-1');
      expect(group, isNotNull);

      selfListener.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Media forwarding tests
  // ---------------------------------------------------------------------------
  group('media forwarding', () {
    test('forwards media field from event to handleIncomingGroupMessage',
        () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final mediaListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
      );
      final mediaSource =
          StreamController<Map<String, dynamic>>.broadcast();

      mediaListener.start(mediaSource.stream);

      mediaSource.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Photo message',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'media': [
          {
            'id': 'blob-event-1',
            'mime': 'image/jpeg',
            'size': 12345,
            'mediaType': 'image',
            'downloadStatus': 'pending',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      });

      await Future.delayed(const Duration(milliseconds: 100));

      expect(msgRepo.count, 1);
      expect(mediaRepo.count, 1);

      mediaListener.dispose();
      await mediaSource.close();
    });

    test('handles event without media field (backward compat)', () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final mediaListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
      );
      final mediaSource =
          StreamController<Map<String, dynamic>>.broadcast();

      mediaListener.start(mediaSource.stream);

      mediaSource.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Text only',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 100));

      expect(msgRepo.count, 1);
      expect(mediaRepo.count, 0);

      mediaListener.dispose();
      await mediaSource.close();
    });
  });

  // ---------------------------------------------------------------------------
  // Group notifications
  // ---------------------------------------------------------------------------
  group('group notifications', () {
    test('shows notification for incoming group message', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Hello group!',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, hasLength(1));
      expect(notifService.shown.first.contactPeerId, 'group:group-1');
      expect(notifService.shown.first.senderUsername, 'Test Group');
      expect(notifService.shown.first.messageText, 'Sender: Hello group!');

      notifListener.dispose();
    });

    test('suppresses notification when viewing group conversation', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();
      tracker.setActive('group:group-1');

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Hello group!',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, isEmpty);

      notifListener.dispose();
    });

    test('does not notify for own messages', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-sender',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'My own message',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, isEmpty);

      notifListener.dispose();
    });

    test('does not notify when notification deps are null', () async {
      // Default listener without notification params (current behavior)
      listener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'No crash please',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // No crash, message still persisted
      expect(msgRepo.count, 1);
    });

    test('shows notification when viewing different group', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();
      tracker.setActive('group:other-group');

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Hello!',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, hasLength(1));

      notifListener.dispose();
    });
  });
}
