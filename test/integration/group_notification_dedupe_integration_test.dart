import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';

import '../shared/fakes/fake_notification_service.dart';
import '../shared/fakes/in_memory_group_message_repository.dart';
import '../shared/fakes/in_memory_group_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'background push announcement suppresses later local group notification for the same message',
    () async {
      flowEventLoggingEnabled = false;

      final gate = RecentRemoteNotificationGate(
        filePath:
            '${Directory.systemTemp.path}/group-notification-dedupe-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      debugSetRecentRemoteNotificationGate(gate);
      addTearDown(() async {
        await gate.clear();
        debugResetRecentRemoteNotificationGate();
      });

      await firebaseMessagingBackgroundHandler(
        const RemoteMessage(
          notification: RemoteNotification(
            title: 'Team Chat',
            body: 'Alice: hello',
          ),
          data: {
            'type': 'group_message',
            'groupId': 'group-1',
            'message_id': 'group-msg-1',
          },
        ),
      );

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-1',
          name: 'Team Chat',
          type: GroupType.chat,
          topicName: 'topic-group-1',
          description: null,
          createdAt: DateTime.utc(2026, 4, 4, 12),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-sender',
          username: 'Alice',
          role: MemberRole.writer,
          joinedAt: DateTime.utc(2026, 4, 4, 12),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Me',
          role: MemberRole.admin,
          joinedAt: DateTime.utc(2026, 4, 4, 12),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'group-key-1',
          createdAt: DateTime.utc(2026, 4, 4, 12),
        ),
      );

      final notificationService = FakeNotificationService();
      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: InMemoryGroupMessageRepository(),
        getSelfPeerId: () async => 'peer-self',
        notificationService: notificationService,
        groupConversationTracker: ActiveConversationTracker(),
        getAppLifecycleState: () => AppLifecycleState.paused,
        remoteNotificationGate: gate,
      );

      final source = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(source.close);
      listener.start(source.stream);
      addTearDown(listener.dispose);

      source.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Alice',
        'keyEpoch': 1,
        'text': 'hello',
        'timestamp': '2026-04-04T12:00:01.000Z',
        'messageId': 'group-msg-1',
      });

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(notificationService.shown, isEmpty);
      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: 'group:group-1|message:group-msg-1',
          messageId: 'group-msg-1',
        ),
        isFalse,
      );
    },
  );
}
