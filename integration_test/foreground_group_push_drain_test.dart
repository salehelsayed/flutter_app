import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
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

const _downloadedBytesHash =
    '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a';

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
    final foregroundKey = GroupKeyInfo(
      groupId: 'group-foreground',
      keyGeneration: 0,
      encryptedKey: 'foreground-key',
      createdAt: DateTime.now().toUtc(),
    );
    await admin.groupRepo.saveKey(foregroundKey);
    await member.groupRepo.saveKey(foregroundKey);

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

  Future<void> addSignedInboxPage(
    String groupId,
    String cursor,
    List<Map<String, dynamic>> payloads,
    String nextCursor,
  ) async {
    final messages = <Map<String, dynamic>>[];
    for (final payload in payloads) {
      final keyEpoch = payload['keyEpoch'] as int? ?? 0;
      final replayEnvelope = await buildGroupOfflineReplayEnvelope(
        bridge: admin.bridge,
        groupRepo: admin.groupRepo,
        groupId: groupId,
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode(payload),
        senderPeerId: admin.peerId,
        senderPublicKey: admin.publicKey,
        senderPrivateKey: admin.privateKey,
        keyInfo: GroupKeyInfo(
          groupId: groupId,
          keyGeneration: keyEpoch,
          encryptedKey: 'foreground-key',
          createdAt: DateTime.now().toUtc(),
        ),
        messageId: payload['messageId'] as String?,
        senderDeviceId: admin.deviceId,
        senderTransportPeerId: admin.deviceId,
        senderKeyPackageId: admin.deviceIdentity.keyPackageId,
        recipientPeerIds: <String>[member.peerId],
      );
      messages.add({
        'from': admin.deviceId,
        'message': replayEnvelope,
        'timestamp': payload['timestamp'],
      });
    }
    memberBridge.addPage(groupId, cursor, messages, nextCursor);
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
        await harness.addSignedInboxPage('group-foreground', '', [
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
        await harness.addSignedInboxPage('group-foreground', '', [
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
                'size': 4,
                'mediaType': 'image',
                'width': 640,
                'height': 480,
                'downloadStatus': 'pending',
                'contentHash': _downloadedBytesHash,
                'encryptionKeyBase64': 'key-fixture',
                'encryptionNonce': 'nonce-fixture',
                'encryptionScheme': 'blob_aes_256_gcm_v1',
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
      'foreground group push tampered media download fails before done display',
      (tester) async {
        final harness = await _ForegroundGroupPushHarness.create();
        addTearDown(harness.dispose);

        harness.member.unsubscribeFromGroup('group-foreground');
        await harness.addSignedInboxPage('group-foreground', '', [
          {
            'groupId': 'group-foreground',
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': '',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'messageId': 'group-media-tampered-msg',
            'media': [
              {
                'id': 'blob-foreground-tampered',
                'mime': 'image/jpeg',
                'size': 4,
                'mediaType': 'image',
                'downloadStatus': 'pending',
                'contentHash':
                    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                'encryptionKeyBase64': 'key-tampered-fixture',
                'encryptionNonce': 'nonce-tampered-fixture',
                'encryptionScheme': 'blob_aes_256_gcm_v1',
                'createdAt': DateTime.now().toUtc().toIso8601String(),
              },
            ],
          },
        ], '');

        await harness.runForegroundPush(
          groupMessageData(
            groupId: 'group-foreground',
            messageId: 'group-media-tampered-msg',
          ),
        );
        await tester.pumpAndSettle();
        await _settle();

        final messages = await harness.incomingMessages();
        expect(messages, hasLength(1));
        expect(messages.single.id, 'group-media-tampered-msg');

        final attachments = await harness.member.mediaAttachmentRepo
            .getAttachmentsForMessage('group-media-tampered-msg');
        expect(attachments, hasLength(1));
        expect(
          attachments.single.downloadStatus,
          kMediaDownloadStatusIntegrityFailed,
        );
        expect(attachments.single.localPath, isNull);
        expect(
          harness.memberBridge.commandLog.where(
            (cmd) => cmd == 'media:download',
          ),
          hasLength(1),
        );

        final downloadedPath = await FakeMediaFileManager()
            .localPathForAttachment(
              contactPeerId: 'group-foreground',
              blobId: 'blob-foreground-tampered',
              mime: 'image/jpeg',
            );
        expect(File(downloadedPath).existsSync(), isFalse);
      },
    );

    testWidgets(
      'foreground group push rejects oversized media before notification or download',
      (tester) async {
        final harness = await _ForegroundGroupPushHarness.create();
        addTearDown(harness.dispose);

        harness.member.unsubscribeFromGroup('group-foreground');
        await harness.addSignedInboxPage('group-foreground', '', [
          {
            'groupId': 'group-foreground',
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': '',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'messageId': 'group-oversized-media-msg',
            'media': [
              {
                'id': 'blob-foreground-oversized',
                'mime': 'image/jpeg',
                'size': kGroupMediaPerAttachmentLimitBytes + 1,
                'mediaType': 'image',
                'downloadStatus': 'pending',
                'createdAt': DateTime.now().toUtc().toIso8601String(),
              },
            ],
          },
        ], '');

        await harness.runForegroundPush(
          groupMessageData(
            groupId: 'group-foreground',
            messageId: 'group-oversized-media-msg',
          ),
        );
        await tester.pumpAndSettle();
        await _settle();

        final messages = await harness.incomingMessages();
        expect(messages, isEmpty);
        expect(
          await harness.member.mediaAttachmentRepo.getAttachmentsForMessage(
            'group-oversized-media-msg',
          ),
          isEmpty,
        );
        expect(harness.notificationService.shown, isEmpty);
        expect(
          harness.memberBridge.commandLog.where(
            (cmd) => cmd == 'media:download',
          ),
          isEmpty,
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

        await harness.addSignedInboxPage('group-foreground', '', [
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
        expect(
          await harness.member.msgRepo.getUnreadCount('group-foreground'),
          1,
        );
        expect(harness.notificationService.shown, hasLength(1));

        final distinctSentMessage = await harness.admin
            .sendGroupMessageViaBridge(
              groupId: 'group-foreground',
              text: 'Distinct follow-up',
              messageId: 'group-msg-distinct-1',
            );
        final distinctLiveMessage = distinctSentMessage.$2;
        expect(distinctLiveMessage, isNotNull);
        await tester.pumpAndSettle();
        await _settle();

        final messagesAfterDistinct = await harness.incomingMessages();
        expect(messagesAfterDistinct, hasLength(2));
        expect(
          messagesAfterDistinct.map((message) => message.id),
          containsAll(<String>[liveMessage.id, 'group-msg-distinct-1']),
        );
        expect(
          await harness.member.msgRepo.getUnreadCount('group-foreground'),
          2,
        );
        expect(harness.notificationService.shown, hasLength(2));
        expect(
          harness.notificationService.shown.last.payload,
          'group:group-foreground|message:group-msg-distinct-1',
        );
      },
    );

    testWidgets(
      'foreground group push after background announcement does not duplicate notification or unread',
      (tester) async {
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/foreground-group-push-dedupe-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(() async {
          await gate.clear();
          debugResetRecentRemoteNotificationGate();
        });

        final harness = await _ForegroundGroupPushHarness.create();
        addTearDown(harness.dispose);

        await gate.markAnnouncement(
          payload: 'group:group-foreground|message:group-msg-bg-1',
          messageId: 'group-msg-bg-1',
        );
        await gate.markAnnouncement(
          payload: 'group:group-foreground|message:unrelated-msg',
          messageId: 'unrelated-msg',
        );

        harness.member.unsubscribeFromGroup('group-foreground');
        await harness.addSignedInboxPage('group-foreground', '', [
          {
            'groupId': 'group-foreground',
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'Already announced remotely',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'messageId': 'group-msg-bg-1',
          },
        ], '');

        await harness.runForegroundPush(
          groupMessageData(
            groupId: 'group-foreground',
            messageId: 'group-msg-bg-1',
          ),
        );
        await tester.pumpAndSettle();
        await _settle();

        var messages = await harness.incomingMessages();
        expect(messages, hasLength(1));
        expect(messages.single.id, 'group-msg-bg-1');
        expect(
          await harness.member.msgRepo.getUnreadCount('group-foreground'),
          1,
        );
        expect(harness.notificationService.shown, isEmpty);
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-foreground|message:unrelated-msg',
            messageId: 'unrelated-msg',
          ),
          isTrue,
          reason: 'Same-message dedupe must not clear unrelated entries',
        );

        final followUpCursor =
            await harness.member.msgRepo.getInboxCursor('group-foreground') ??
            '';
        await harness.addSignedInboxPage('group-foreground', followUpCursor, [
          {
            'groupId': 'group-foreground',
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'Distinct foreground drain',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'messageId': 'group-msg-bg-2',
          },
        ], '');

        await harness.runForegroundPush(
          groupMessageData(
            groupId: 'group-foreground',
            messageId: 'group-msg-bg-2',
          ),
        );
        await tester.pumpAndSettle();
        await _settle();

        messages = await harness.incomingMessages();
        expect(messages, hasLength(2));
        expect(
          messages.map((message) => message.id),
          containsAll(<String>['group-msg-bg-1', 'group-msg-bg-2']),
        );
        expect(
          await harness.member.msgRepo.getUnreadCount('group-foreground'),
          2,
        );
        expect(harness.notificationService.shown, hasLength(1));
        expect(
          harness.notificationService.shown.single.payload,
          'group:group-foreground|message:group-msg-bg-2',
        );
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
