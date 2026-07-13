import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

void main() {
  test(
    'foreground drained reaction still runs contextual notification gate',
    () async {
      var persisted = false;
      final drainedGroups = <String>[];
      const message = RemoteMessage(
        messageId: 'provider-copy-1',
        data: {
          'type': 'group_reaction',
          'groupId': 'group-1',
          'reactor_peer_id': 'peer-reactor',
          'event_id': 'transition-1',
          'target_message_id': 'target-1',
          'action': 'add',
        },
      );

      final result = await handleForegroundRemoteMessage(
        data: message.data,
        messageId: message.messageId,
        drainOfflineInbox: () async {
          fail('group reaction must not use the 1:1 drain');
        },
        drainGroupOfflineInboxForGroup: (groupId) async {
          drainedGroups.add(groupId);
          persisted = true;
        },
      );

      final notificationService = FakeNotificationService();
      final directory = await Directory.systemTemp.createTemp(
        'foreground-group-reaction-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final coordinator = DurableNotificationToneLease(directory: directory);
      final shown = await showForegroundPushFallbackNotificationIfNeeded(
        result: result,
        notificationService: notificationService,
        message: message,
        groupReactionNotificationResolver: (_) async {
          expect(persisted, isTrue, reason: 'display must follow inbox drain');
          return const BackgroundPushNotificationFallback(
            title: 'Team Chat',
            body: 'Alice reacted 👍 to your message',
            payload: 'group:group-1|message:target-1',
          );
        },
        groupConversationTracker: ActiveConversationTracker(),
        getAppLifecycleState: () => AppLifecycleState.resumed,
        durableReactionNotificationCoordinatorResolver: () async => coordinator,
      );

      expect(result, ForegroundRemoteMessageResult.notificationNeeded);
      expect(drainedGroups, ['group-1']);
      expect(shown, isTrue);
      expect(
        await coordinator.claimMessageEvent(
          type: 'message_reaction',
          eventIdentity: boundedReactionEventIdentity('transition-1'),
        ),
        isNull,
      );
      expect(notificationService.shown, hasLength(1));
      expect(notificationService.shown.single.senderUsername, 'Team Chat');
      expect(
        notificationService.shown.single.messageText,
        'Alice reacted 👍 to your message',
      );
      expect(
        notificationService.shown.single.payload,
        'group:group-1|message:target-1',
      );
    },
  );

  test(
    'real live listener and remote drain share one atomic transition claim',
    () async {
      const groupId = 'group-race';
      const targetId = 'target-race';
      const reactorPeerId = 'peer-reactor';
      const localPeerId = 'peer-local-author';
      const eventId = 'transition-race-1';
      final timestamp = DateTime.utc(2026, 7, 12, 9);
      final groups = InMemoryGroupRepository();
      final messages = InMemoryGroupMessageRepository();
      final reactions = FakeReactionRepository();
      await groups.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Team Chat',
          type: GroupType.chat,
          topicName: 'topic-race',
          createdAt: timestamp,
          createdBy: localPeerId,
          myRole: GroupRole.admin,
        ),
      );
      for (final member in <GroupMember>[
        GroupMember(
          groupId: groupId,
          peerId: localPeerId,
          username: 'Local Author',
          role: MemberRole.admin,
          joinedAt: timestamp,
        ),
        GroupMember(
          groupId: groupId,
          peerId: reactorPeerId,
          username: 'Alice',
          role: MemberRole.writer,
          joinedAt: timestamp,
        ),
      ]) {
        await groups.saveMember(member);
      }
      await messages.saveMessage(
        GroupMessage(
          id: targetId,
          groupId: groupId,
          senderPeerId: localPeerId,
          senderUsername: 'Local Author',
          text: 'Reaction target',
          timestamp: timestamp,
          isIncoming: false,
          createdAt: timestamp,
        ),
      );

      const message = RemoteMessage(
        data: {
          'type': 'group_reaction',
          'groupId': groupId,
          'reactor_peer_id': reactorPeerId,
          'event_id': eventId,
          'target_message_id': targetId,
          'action': 'add',
        },
      );
      final notificationService = _DismissibleNotificationService();
      final directory = Directory.systemTemp.createTempSync(
        'group-reaction-pipeline-',
      );
      final remoteGateDirectory = Directory.systemTemp.createTempSync(
        'group-reaction-remote-gate-',
      );
      final coordinator = DurableNotificationToneLease(directory: directory);
      final tracker = ActiveConversationTracker();
      final reactionSource = StreamController<Map<String, dynamic>>.broadcast();
      final remoteGate = RecentRemoteNotificationGate(
        filePath: '${remoteGateDirectory.path}/gate.json',
      );
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
        if (remoteGateDirectory.existsSync()) {
          remoteGateDirectory.deleteSync(recursive: true);
        }
      });
      addTearDown(reactionSource.close);

      final listener = GroupMessageListener(
        groupRepo: groups,
        msgRepo: messages,
        reactionRepo: reactions,
        getSelfPeerId: () async => localPeerId,
        notificationService: notificationService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        durableNotificationCoordinatorResolver: () async => coordinator,
        remoteNotificationGate: remoteGate,
      );
      listener.start(
        const Stream<Map<String, dynamic>>.empty(),
        incomingGroupReactions: reactionSource.stream,
      );
      addTearDown(listener.dispose);

      Future<bool> announceRemote({required String candidateEventId}) {
        return showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: RemoteMessage(
            data: <String, dynamic>{
              ...message.data,
              'event_id': candidateEventId,
            },
          ),
          groupReactionNotificationResolver: (_) async {
            if (tracker.isViewing('group:$groupId') ||
                tracker.isViewing('group:$groupId|message:$targetId')) {
              return null;
            }
            return const BackgroundPushNotificationFallback(
              title: 'Team Chat',
              body: 'Alice reacted 👍 to your message',
              payload: 'group:$groupId|message:$targetId',
            );
          },
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          durableReactionNotificationCoordinatorResolver: () async =>
              coordinator,
        );
      }

      final liveChange = listener.groupReactionChangeStream.first;
      reactionSource.add(<String, dynamic>{
        'groupId': groupId,
        'senderId': reactorPeerId,
        'reaction': jsonEncode(<String, Object?>{
          'id': 'state-race-1',
          'eventId': eventId,
          'messageId': targetId,
          'emoji': '👍',
          'action': 'add',
          'senderPeerId': reactorPeerId,
          'timestamp': timestamp
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        }),
      });
      final remoteResult = announceRemote(candidateEventId: eventId);

      await Future.wait<void>(<Future<void>>[
        notificationService.firstShown,
        liveChange.then<void>((_) {}),
      ]).timeout(const Duration(seconds: 5));
      final remoteShown = await remoteResult;

      expect(remoteShown || notificationService.shown.isNotEmpty, isTrue);
      expect(notificationService.shown, hasLength(1));
      expect(reactions.saveReactionCallCount, 1);
      expect(await reactions.getReactionsForMessage(targetId), hasLength(1));

      // A distinct transition received while this exact group route is active
      // still converges reaction state, but neither the listener nor the remote
      // foreground branch reaches the durable claim/card boundary.
      tracker.setActive('group:$groupId');
      final activeChange = listener.groupReactionChangeStream.first;
      reactionSource.add(<String, dynamic>{
        'groupId': groupId,
        'senderId': reactorPeerId,
        'reaction': jsonEncode(<String, Object?>{
          'id': 'state-race-active',
          'eventId': 'transition-race-active',
          'messageId': targetId,
          'emoji': '❤️',
          'action': 'add',
          'senderPeerId': reactorPeerId,
          'timestamp': timestamp
              .add(const Duration(minutes: 2))
              .toIso8601String(),
        }),
      });
      final activeRemoteShown = await announceRemote(
        candidateEventId: 'transition-race-active',
      );
      await activeChange.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);

      expect(activeRemoteShown, isFalse);
      expect(notificationService.shown, hasLength(1));
      expect(reactions.saveReactionCallCount, 2);
      expect(
        (await reactions.getReactionsForMessage(targetId)).single.emoji,
        '❤️',
      );
      expect(
        await coordinator.claimMessageEvent(
          type: 'message_reaction',
          eventIdentity: boundedReactionEventIdentity('transition-race-active'),
        ),
        isNotNull,
        reason: 'active-view suppression must not poison the event claim',
      );
    },
  );

  test(
    'chat and announcement reactions leave message unread state unchanged',
    () async {
      for (final type in <GroupType>[GroupType.chat, GroupType.announcement]) {
        final suffix = type.toValue();
        final groupId = 'group-$suffix';
        final messages = _TrackingGroupMessageRepository();
        final groups = InMemoryGroupRepository();
        final reactions = FakeReactionRepository();
        final notifications = _DismissibleNotificationService();
        final reactionSource =
            StreamController<Map<String, dynamic>>.broadcast();
        final readEvents = <String>[];
        final readSubscription = messages.groupConversationReadStream.listen(
          readEvents.add,
        );
        final timestamp = DateTime.utc(2026, 7, 12, 9);
        final gateDirectory = Directory.systemTemp.createTempSync(
          'group-reaction-unread-$suffix-',
        );
        final claimDirectory = Directory.systemTemp.createTempSync(
          'group-reaction-claim-$suffix-',
        );
        final coordinator = DurableNotificationToneLease(
          directory: claimDirectory,
        );
        final remoteGate = RecentRemoteNotificationGate(
          filePath: '${gateDirectory.path}/gate.json',
        );
        await groups.saveGroup(
          GroupModel(
            id: groupId,
            name: '$suffix group',
            type: type,
            topicName: 'topic-$suffix',
            createdAt: timestamp,
            createdBy: 'peer-local-author',
            myRole: GroupRole.admin,
          ),
        );
        for (final member in <GroupMember>[
          GroupMember(
            groupId: groupId,
            peerId: 'peer-local-author',
            username: 'Local Author',
            role: MemberRole.admin,
            joinedAt: timestamp,
          ),
          GroupMember(
            groupId: groupId,
            peerId: 'peer-reactor',
            username: 'Alice',
            role: MemberRole.writer,
            joinedAt: timestamp,
          ),
        ]) {
          await groups.saveMember(member);
        }
        await messages.saveMessage(
          GroupMessage(
            id: 'unread-$suffix',
            groupId: groupId,
            senderPeerId: 'peer-reactor',
            senderUsername: 'Alice',
            text: 'Genuine unread message',
            timestamp: timestamp,
            isIncoming: true,
            createdAt: timestamp,
          ),
        );
        await messages.saveMessage(
          GroupMessage(
            id: 'target-$suffix',
            groupId: groupId,
            senderPeerId: 'peer-local-author',
            senderUsername: 'Local Author',
            text: 'Reaction target',
            timestamp: timestamp,
            isIncoming: false,
            createdAt: timestamp,
          ),
        );
        final unreadBefore = await messages.getUnreadCount(groupId);
        final messageCountBefore = await messages.getMessageCount(groupId);
        final listener = GroupMessageListener(
          groupRepo: groups,
          msgRepo: messages,
          reactionRepo: reactions,
          getSelfPeerId: () async => 'peer-local-author',
          notificationService: notifications,
          groupConversationTracker: ActiveConversationTracker(),
          getAppLifecycleState: () => AppLifecycleState.resumed,
          durableNotificationCoordinatorResolver: () async => coordinator,
          remoteNotificationGate: remoteGate,
        );
        listener.start(
          const Stream<Map<String, dynamic>>.empty(),
          incomingGroupReactions: reactionSource.stream,
        );

        final receivedChange = listener.groupReactionChangeStream.first;
        reactionSource.add(<String, dynamic>{
          'groupId': groupId,
          'senderId': 'peer-reactor',
          'reaction': jsonEncode(<String, Object?>{
            'id': 'state-$suffix',
            'eventId': 'transition-$suffix',
            'messageId': 'target-$suffix',
            'emoji': '👍',
            'action': 'add',
            'senderPeerId': 'peer-reactor',
            'timestamp': timestamp
                .add(const Duration(minutes: 1))
                .toIso8601String(),
          }),
        });
        await Future.wait<void>(<Future<void>>[
          receivedChange.then<void>((_) {}),
          notifications.firstShown,
        ]).timeout(const Duration(seconds: 5));
        final eventClaim = File(
          '${claimDirectory.path}/'
          '${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'message_reaction', eventIdentity: boundedReactionEventIdentity('transition-$suffix'))}',
        );
        await _waitForCommittedNotificationClaim(eventClaim);
        final toneEntries = Directory(
          '${claimDirectory.path}/'
          '${DurableNotificationToneLease.toneLeasesDirectoryName}',
        ).listSync();
        expect(
          toneEntries.whereType<File>().where(
            (file) => file.path.endsWith('.lease'),
          ),
          hasLength(1),
          reason: '$suffix must commit one durable tone window',
        );
        expect(
          toneEntries.whereType<File>().where(
            (file) => file.path.endsWith(
              DurableNotificationToneLease.tonePendingReservationFileSuffix,
            ),
          ),
          isEmpty,
          reason: '$suffix must not tear down a pending tone reservation',
        );

        expect(notifications.shown, hasLength(1), reason: suffix);
        expect(
          notifications.shown.single.payload,
          'group:$groupId|message:target-$suffix',
          reason: suffix,
        );
        expect(await messages.getUnreadCount(groupId), unreadBefore);
        expect(unreadBefore, 1);
        expect(await messages.getMessageCount(groupId), messageCountBefore);
        expect(messageCountBefore, 2);
        expect(messages.markAsReadCalls, 0, reason: suffix);
        expect(readEvents, isEmpty, reason: suffix);
        expect(
          await reactions.getReactionsForMessage('target-$suffix'),
          hasLength(1),
        );

        // OS dismissal has no application read callback. Simulate the card
        // leaving Notification Center and prove the genuine unread row and the
        // Orbit read-event source remain untouched.
        notifications.dismissAll();
        await Future<void>.delayed(Duration.zero);
        expect(notifications.shown, isEmpty, reason: suffix);
        expect(await messages.getUnreadCount(groupId), 1, reason: suffix);
        expect(await messages.getMessageCount(groupId), 2, reason: suffix);
        expect(messages.markAsReadCalls, 0, reason: suffix);
        expect(readEvents, isEmpty, reason: suffix);

        listener.dispose();
        await reactionSource.close();
        await readSubscription.cancel();
        await remoteGate.clear();
        if (gateDirectory.existsSync()) {
          gateDirectory.deleteSync(recursive: true);
        }
        if (claimDirectory.existsSync()) {
          claimDirectory.deleteSync(recursive: true);
        }
      }
    },
  );
}

Future<void> _waitForCommittedNotificationClaim(File claim) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (await claim.exists() &&
        (await claim.readAsString()).contains('"state":"committed"')) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('notification claim did not commit before test teardown: ${claim.path}');
}

class _DismissibleNotificationService extends FakeNotificationService {
  final Completer<void> _firstShown = Completer<void>();

  Future<void> get firstShown => _firstShown.future;

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
  }) async {
    await super.showMessageNotification(
      contactPeerId: contactPeerId,
      senderUsername: senderUsername,
      messageText: messageText,
      payload: payload,
      silent: silent,
    );
    if (!_firstShown.isCompleted) _firstShown.complete();
  }

  void dismissAll() => shown.clear();
}

class _TrackingGroupMessageRepository extends InMemoryGroupMessageRepository {
  int markAsReadCalls = 0;

  @override
  Future<void> markAsRead(String groupId) async {
    markAsReadCalls += 1;
    await super.markAsRead(groupId);
  }
}
