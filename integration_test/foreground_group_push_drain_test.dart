import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';
import 'package:integration_test/integration_test.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/features/push/application/remote_message_fixtures.dart';
import '../test/shared/fakes/fake_group_pubsub_network.dart';
import '../test/shared/fakes/fake_media_file_manager.dart';
import '../test/shared/fakes/fake_notification_service.dart';
import '../test/shared/fakes/group_test_user.dart';

class _CursorInboxBridge extends FakeBridge {
  final Map<String, _InboxPage> pages = {};

  void addPage(
    String groupId,
    String cursor,
    List<Map<String, dynamic>> messages,
    String nextCursor,
  ) {
    pages['$groupId:$cursor'] = _InboxPage(messages, nextCursor);
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd != null) {
      commandLog.add(cmd);
    }
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;

    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final page = pages['$groupId:$cursor'];
      if (page != null) {
        return jsonEncode({
          'ok': true,
          'messages': page.messages,
          'cursor': page.nextCursor,
        });
      }
      return jsonEncode({
        'ok': true,
        'messages': <Map<String, dynamic>>[],
        'cursor': '',
      });
    }

    if (cmd == 'media:download') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final outputPath = payload['outputPath'] as String;
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[1, 2, 3, 4]);

      return jsonEncode({'ok': true, 'id': payload['id'], 'size': 4});
    }

    return super.send(message);
  }
}

class _InboxPage {
  const _InboxPage(this.messages, this.nextCursor);

  final List<Map<String, dynamic>> messages;
  final String nextCursor;
}

class _ForegroundGroupPushHarness {
  _ForegroundGroupPushHarness._({
    required this.network,
    required this.admin,
    required this.member,
    required this.memberBridge,
    required this.notificationService,
  });

  final FakeGroupPubSubNetwork network;
  final GroupTestUser admin;
  final GroupTestUser member;
  final _CursorInboxBridge memberBridge;
  final FakeNotificationService notificationService;

  static Future<_ForegroundGroupPushHarness> create() async {
    final network = FakeGroupPubSubNetwork();
    final notificationService = FakeNotificationService();
    final memberBridge = _CursorInboxBridge();

    final admin = GroupTestUser.create(
      peerId: 'alice-peer',
      username: 'Alice',
      network: network,
    );
    final member = GroupTestUser.create(
      peerId: 'bob-peer',
      username: 'Bob',
      network: network,
      bridge: memberBridge,
      mediaFileManager: FakeMediaFileManager(),
      notificationService: notificationService,
      groupConversationTracker: ActiveConversationTracker(),
      getAppLifecycleState: () => AppLifecycleState.resumed,
    );

    await admin.createGroup(groupId: 'group-foreground', name: 'Weekend Crew');
    await admin.addMember(groupId: 'group-foreground', invitee: member);
    await member.groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-foreground',
        keyGeneration: 0,
        encryptedKey: 'foreground-key',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    member.start();
    return _ForegroundGroupPushHarness._(
      network: network,
      admin: admin,
      member: member,
      memberBridge: memberBridge,
      notificationService: notificationService,
    );
  }

  Future<void> runForegroundPush(Map<String, dynamic> data) {
    return handleForegroundRemoteMessage(
      data: data,
      messageId: data['message_id']?.toString(),
      drainOfflineInbox: () async {},
      drainGroupOfflineInboxForGroup: (groupId) =>
          drainGroupOfflineInboxForGroup(
            bridge: member.bridge,
            groupRepo: member.groupRepo,
            msgRepo: member.msgRepo,
            groupId: groupId,
            mediaAttachmentRepo: member.mediaAttachmentRepo,
            reactionRepo: member.reactionRepo,
            groupMessageListener: member.groupMessageListener,
          ),
    );
  }

  Future<List<GroupMessage>> incomingMessages() async {
    return (await member.loadGroupMessages(
      'group-foreground',
    )).where((message) => message.isIncoming).toList();
  }

  void dispose() {
    admin.dispose();
    member.dispose();
  }
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('foreground group push drain', () {
    testWidgets(
      'foreground group push drains the targeted group inbox and surfaces one in-app notification',
      (tester) async {
        final harness = await _ForegroundGroupPushHarness.create();
        addTearDown(harness.dispose);

        harness.member.unsubscribeFromGroup('group-foreground');
        harness.memberBridge.addPage('group-foreground', '', [
          {
            'groupId': 'group-foreground',
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'While you were away',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'messageId': 'group-msg-1',
          },
        ], '');

        await harness.runForegroundPush(
          groupMessageData(
            groupId: 'group-foreground',
            messageId: 'group-msg-1',
          ),
        );
        await tester.pumpAndSettle();
        await _settle();

        final messages = await harness.incomingMessages();
        expect(messages, hasLength(1));
        expect(messages.single.id, 'group-msg-1');
        expect(messages.single.text, 'While you were away');
        expect(harness.notificationService.shown, hasLength(1));
        expect(
          harness.notificationService.shown.single.payload,
          'group:group-foreground|message:group-msg-1',
        );
      },
    );

    testWidgets(
      'foreground group push drains media exactly once with descriptor and download trigger',
      (tester) async {
        final harness = await _ForegroundGroupPushHarness.create();
        addTearDown(harness.dispose);

        harness.member.unsubscribeFromGroup('group-foreground');
        harness.memberBridge.addPage('group-foreground', '', [
          {
            'groupId': 'group-foreground',
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': '',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'messageId': 'group-media-msg-1',
            'media': [
              {
                'id': 'blob-foreground-image',
                'mime': 'image/jpeg',
                'size': 2048,
                'mediaType': 'image',
                'width': 640,
                'height': 480,
                'downloadStatus': 'pending',
                'createdAt': DateTime.now().toUtc().toIso8601String(),
              },
            ],
          },
        ], '');

        final pushData = groupMessageData(
          groupId: 'group-foreground',
          messageId: 'group-media-msg-1',
        );
        await harness.runForegroundPush(pushData);
        await tester.pumpAndSettle();
        await _settle();

        await harness.runForegroundPush(pushData);
        await tester.pumpAndSettle();
        await _settle();

        final messages = await harness.incomingMessages();
        expect(messages, hasLength(1));
        expect(messages.single.id, 'group-media-msg-1');
        expect(messages.single.text, isEmpty);

        final attachments = await harness.member.mediaAttachmentRepo
            .getAttachmentsForMessage('group-media-msg-1');
        expect(attachments, hasLength(1));
        final image = attachments.single;
        expect(image.id, 'blob-foreground-image');
        expect(image.mediaType, 'image');
        expect(image.mime, 'image/jpeg');
        expect(image.width, 640);
        expect(image.height, 480);
        expect(image.downloadStatus, 'done');
        expect(image.localPath, isNotNull);

        expect(harness.notificationService.shown, hasLength(1));
        expect(
          harness.notificationService.shown.single.payload,
          'group:group-foreground|message:group-media-msg-1',
        );
        expect(
          harness.notificationService.shown.single.messageText,
          'Alice: Photo',
        );
        expect(
          harness.memberBridge.commandLog.where(
            (cmd) => cmd == 'media:download',
          ),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'foreground group push does not duplicate a message or notification already received live',
      (tester) async {
        final harness = await _ForegroundGroupPushHarness.create();
        addTearDown(harness.dispose);

        final sentMessage = await harness.admin.sendGroupMessageViaBridge(
          groupId: 'group-foreground',
          text: 'Live first, push later',
        );
        final liveMessage = sentMessage.$2;
        expect(liveMessage, isNotNull);
        await _settle();

        harness.memberBridge.addPage('group-foreground', '', [
          {
            'groupId': 'group-foreground',
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': liveMessage!.keyGeneration,
            'text': liveMessage.text,
            'timestamp': liveMessage.timestamp.toUtc().toIso8601String(),
            'messageId': liveMessage.id,
          },
        ], '');

        await harness.runForegroundPush(
          groupMessageData(
            groupId: 'group-foreground',
            messageId: liveMessage.id,
          ),
        );
        await tester.pumpAndSettle();
        await _settle();

        final messages = await harness.incomingMessages();
        expect(messages, hasLength(1));
        expect(messages.single.id, liveMessage.id);
        expect(harness.notificationService.shown, hasLength(1));
      },
    );

    testWidgets('foreground 1:1 push still drains the 1:1 inbox only', (
      tester,
    ) async {
      var oneToOneCalls = 0;
      final drainedGroups = <String>[];

      await handleForegroundRemoteMessage(
        data: newMessageData(senderId: 'peer-chat'),
        messageId: 'chat-msg-1',
        drainOfflineInbox: () async {
          oneToOneCalls += 1;
        },
        drainGroupOfflineInboxForGroup: (groupId) async {
          drainedGroups.add(groupId);
        },
      );
      await tester.pumpAndSettle();

      expect(oneToOneCalls, 1);
      expect(drainedGroups, isEmpty);
    });

    testWidgets('foreground post push does not trigger any drain', (
      tester,
    ) async {
      var oneToOneCalls = 0;
      final drainedGroups = <String>[];

      await handleForegroundRemoteMessage(
        data: postCreateData(postId: 'post-foreground'),
        messageId: 'post-msg-1',
        drainOfflineInbox: () async {
          oneToOneCalls += 1;
        },
        drainGroupOfflineInboxForGroup: (groupId) async {
          drainedGroups.add(groupId);
        },
      );
      await tester.pumpAndSettle();

      expect(oneToOneCalls, 0);
      expect(drainedGroups, isEmpty);
    });
  });
}
