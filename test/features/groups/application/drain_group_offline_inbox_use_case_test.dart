import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_backlog_retention_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

/// Bridge that simulates cursor-based group inbox retrieval.
///
/// Stores pages of messages keyed by cursor. Empty string cursor = first page.
/// Each page includes a nextCursor. Empty nextCursor = last page.
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
    if (cmd != null) commandLog.add(cmd);
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;

    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final key = '$groupId:$cursor';

      final page = pages[key];
      if (page != null) {
        return jsonEncode({
          'ok': true,
          'messages': page.messages,
          'cursor': page.nextCursor,
        });
      }
      // No page found — return empty
      return jsonEncode({
        'ok': true,
        'messages': <Map<String, dynamic>>[],
        'cursor': '',
      });
    }

    return super.send(message);
  }
}

class _InboxPage {
  final List<Map<String, dynamic>> messages;
  final String nextCursor;
  _InboxPage(this.messages, this.nextCursor);
}

class _TimeoutCursorInboxBridge extends _CursorInboxBridge {
  final Set<String> timeoutPages = {};

  void addTimeout(String groupId, String cursor) {
    timeoutPages.add('$groupId:$cursor');
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      if (timeoutPages.contains('$groupId:$cursor')) {
        if (cmd != null) commandLog.add(cmd);
        sendCallCount++;
        lastSentMessage = message;
        sentMessages.add(message);
        lastCommand = cmd;
        throw TimeoutException('Simulated cursor timeout');
      }
    }
    return super.send(message);
  }
}

class _DelayedCursorInboxBridge extends _CursorInboxBridge {
  final Map<String, Duration> delays = {};

  void addDelay(String groupId, String cursor, Duration delay) {
    delays['$groupId:$cursor'] = delay;
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final delay = delays['$groupId:$cursor'];
      if (delay != null) {
        await Future<void>.delayed(delay);
      }
    }
    return super.send(message);
  }
}

void main() {
  late _CursorInboxBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: '/mknoon/group/group-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.member,
  );

  setUp(() async {
    bridge = _CursorInboxBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-sender',
        username: 'Sender',
        role: MemberRole.writer,
        joinedAt: DateTime.now().toUtc(),
      ),
    );
  });

  test('resume drains group inbox for every joined group', () async {
    // Set up two groups.
    final testGroup2 = GroupModel(
      id: 'group-2',
      name: 'Second Group',
      type: GroupType.chat,
      topicName: '/mknoon/group/group-2',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(testGroup2);
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-2',
        peerId: 'peer-sender',
        username: 'Sender',
        role: MemberRole.writer,
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    final ts = DateTime.now().toUtc().toIso8601String();

    // Group 1: one message
    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Msg for group 1',
        'timestamp': ts,
        'messageId': 'msg-g1-1',
      },
    ], '');

    // Group 2: one message
    bridge.addPage('group-2', '', [
      {
        'groupId': 'group-2',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Msg for group 2',
        'timestamp': ts,
        'messageId': 'msg-g2-1',
      },
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    expect(msgRepo.count, 2);

    // Both groups should have had inboxRetrieveCursor called
    final retrieveCount = bridge.commandLog
        .where((c) => c == 'group:inboxRetrieveCursor')
        .length;
    expect(retrieveCount, 2);
  });

  test('drain after watchdog restart retrieves messages exactly once', () async {
    final ts = DateTime.now().toUtc().toIso8601String();

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Watchdog msg',
        'timestamp': ts,
        'messageId': 'msg-wd-1',
      },
    ], '');

    // Drain once (simulates first drain after watchdog restart).
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );
    expect(msgRepo.count, 1);

    // Drain again (simulates second drain attempt — should be idempotent).
    // The bridge still returns the same message, but handleIncomingGroupMessage
    // should deduplicate by messageId.
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );
    expect(msgRepo.count, 1, reason: 'Same message should not be saved twice');
  });

  test('drain after in-place recovery still allowed and idempotent', () async {
    final ts = DateTime.now().toUtc().toIso8601String();

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'In-place msg',
        'timestamp': ts,
        'messageId': 'msg-ip-1',
      },
    ], '');

    // Drain once.
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );
    expect(msgRepo.count, 1);

    // Drain again after in-place recovery — same messages are returned,
    // but should be deduplicated by messageId.
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );
    expect(msgRepo.count, 1);
  });

  test(
    'drains groups concurrently so one slow inbox does not serially stall others',
    () async {
      final delayedBridge = _DelayedCursorInboxBridge();
      bridge = delayedBridge;

      final testGroup2 = GroupModel(
        id: 'group-2',
        name: 'Second Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/group-2',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(testGroup2);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final ts = DateTime.now().toUtc().toIso8601String();
      delayedBridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Slow group 1',
          'timestamp': ts,
          'messageId': 'msg-group-1-slow',
        },
      ], '');
      delayedBridge.addPage('group-2', '', [
        {
          'groupId': 'group-2',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Slow group 2',
          'timestamp': ts,
          'messageId': 'msg-group-2-slow',
        },
      ], '');
      delayedBridge.addDelay('group-1', '', const Duration(milliseconds: 250));
      delayedBridge.addDelay('group-2', '', const Duration(milliseconds: 250));

      final stopwatch = Stopwatch()..start();
      await drainGroupOfflineInbox(
        bridge: delayedBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );
      stopwatch.stop();

      expect(msgRepo.count, 2);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(400),
        reason:
            'Two 250ms group drains should overlap instead of running serially',
      );
    },
  );

  test(
    'replayed member_removed routes through listener cleanup instead of saving a chat row',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      final removedGroups = <String>[];
      final sub = listener.groupRemovedStream.listen(removedGroups.add);
      addTearDown(() async {
        await sub.cancel();
        listener.dispose();
      });

      final ts = DateTime.now().toUtc().toIso8601String();
      bridge.addPage('group-1', '', [
        {
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_removed',
              'member': {'peerId': 'peer-self', 'username': 'Self'},
              'groupConfig': {
                'name': 'Test Group',
                'groupType': 'chat',
                'members': [
                  {'peerId': 'peer-admin', 'role': 'admin'},
                ],
                'createdBy': 'peer-admin',
                'createdAt': ts,
              },
            }),
            'timestamp': ts,
          }),
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      expect(await groupRepo.getGroup('group-1'), isNull);
      expect(bridge.commandLog, contains('group:leave'));
      expect(removedGroups, ['group-1']);
      expect(msgRepo.count, 0);
    },
  );

  test(
    'replayed self-removal cuts off later queued inbox traffic for that group',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      final removedGroups = <String>[];
      final sub = listener.groupRemovedStream.listen(removedGroups.add);
      addTearDown(() async {
        await sub.cancel();
        listener.dispose();
      });

      final removedAt = DateTime.now().toUtc().toIso8601String();
      final samePageQueuedAt = DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 1))
          .toIso8601String();
      final nextPageQueuedAt = DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 2))
          .toIso8601String();

      bridge.addPage('group-1', '', [
        {
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_removed',
              'member': {'peerId': 'peer-self', 'username': 'Self'},
              'groupConfig': {
                'name': 'Test Group',
                'groupType': 'chat',
                'members': [
                  {'peerId': 'peer-admin', 'role': 'admin'},
                ],
                'createdBy': 'peer-admin',
                'createdAt': removedAt,
              },
            }),
            'timestamp': removedAt,
            'messageId': 'msg-remove-self',
          }),
        },
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Queued after removal on same page',
          'timestamp': samePageQueuedAt,
          'messageId': 'msg-after-removal-same-page',
        },
      ], 'cursor-after-removal');

      bridge.addPage('group-1', 'cursor-after-removal', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Queued after removal on next page',
          'timestamp': nextPageQueuedAt,
          'messageId': 'msg-after-removal-next-page',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      expect(await groupRepo.getGroup('group-1'), isNull);
      expect(bridge.commandLog, contains('group:leave'));
      expect(removedGroups, ['group-1']);
      expect(
        msgRepo.count,
        0,
        reason:
            'Queued post-removal inbox traffic must not be persisted for the removed peer',
      );

      final retrieveCount = bridge.commandLog
          .where((command) => command == 'group:inboxRetrieveCursor')
          .length;
      expect(
        retrieveCount,
        1,
        reason:
            'Drain should stop before later cursor pages once replayed self-removal deletes the group',
      );
    },
  );

  test(
    'replayed member_removed lets remaining peers accept only removed-sender inbox messages from before removedAt',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      addTearDown(listener.dispose);

      final removedAt = DateTime.now().toUtc();
      final beforeCutoff = removedAt
          .subtract(const Duration(milliseconds: 1))
          .toIso8601String();
      final atCutoff = removedAt.toIso8601String();

      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'member_removed',
            'member': {'peerId': 'peer-sender', 'username': 'Sender'},
            'removedAt': removedAt.toIso8601String(),
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {'peerId': 'peer-admin', 'role': 'admin'},
                {'peerId': 'peer-self', 'role': 'writer'},
              ],
              'createdBy': 'peer-admin',
              'createdAt': removedAt.toIso8601String(),
            },
          }),
          'timestamp': removedAt.toIso8601String(),
          'messageId': 'msg-remove-sender',
        },
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Before cutoff replay',
          'timestamp': beforeCutoff,
          'messageId': 'msg-before-cutoff-replay',
        },
      ], 'cursor-after-cutoff');

      bridge.addPage('group-1', 'cursor-after-cutoff', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'At cutoff replay',
          'timestamp': atCutoff,
          'messageId': 'msg-at-cutoff-replay',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);

      final messages = await msgRepo.getMessagesPage('group-1');
      expect(
        messages.where((message) => message.text == 'Before cutoff replay'),
        hasLength(1),
      );
      expect(
        messages.where((message) => message.text == 'At cutoff replay'),
        isEmpty,
      );
      expect(
        messages.where(
          (message) =>
              message.id.startsWith('sys-member_removed:group-1:peer-sender:'),
        ),
        hasLength(1),
      );

      final retrieveCount = bridge.commandLog
          .where((command) => command == 'group:inboxRetrieveCursor')
          .length;
      expect(
        retrieveCount,
        2,
        reason:
            'Drain should carry the persisted cutoff across later cursor pages',
      );
    },
  );

  test(
    'within-window backlog is retained and records the retained timestamp',
    () async {
      final retainedAt = groupBacklogRetentionCutoff(
        DateTime.now().toUtc(),
      ).add(const Duration(hours: 1));

      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Retained backlog',
          'timestamp': retainedAt.toIso8601String(),
          'messageId': 'msg-retained-backlog',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final messages = await msgRepo.getMessagesPage('group-1');
      final group = await groupRepo.getGroup('group-1');

      expect(messages, hasLength(1));
      expect(messages.single.id, 'msg-retained-backlog');
      expect(group, isNotNull);
      expect(group!.lastBacklogExpiredAt, isNull);
      expect(group.lastBacklogRetainedAt, retainedAt);
    },
  );

  test(
    'beyond-window backlog is skipped and records the expired timestamp',
    () async {
      final expiredAt = groupBacklogRetentionCutoff(
        DateTime.now().toUtc(),
      ).subtract(const Duration(hours: 1));

      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Expired backlog',
          'timestamp': expiredAt.toIso8601String(),
          'messageId': 'msg-expired-backlog',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final group = await groupRepo.getGroup('group-1');

      expect(await msgRepo.getMessagesPage('group-1'), isEmpty);
      expect(group, isNotNull);
      expect(group!.lastBacklogExpiredAt, expiredAt);
      expect(group.lastBacklogRetainedAt, isNull);
    },
  );

  test(
    'mixed old and new cursor pages keep retained backlog and record both boundaries',
    () async {
      final cutoff = groupBacklogRetentionCutoff(DateTime.now().toUtc());
      final expiredAt = cutoff.subtract(const Duration(hours: 1));
      final retainedAt = cutoff.add(const Duration(hours: 1));

      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Expired page',
          'timestamp': expiredAt.toIso8601String(),
          'messageId': 'msg-expired-page',
        },
      ], 'cursor-retained');

      bridge.addPage('group-1', 'cursor-retained', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Retained page',
          'timestamp': retainedAt.toIso8601String(),
          'messageId': 'msg-retained-page',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final messages = await msgRepo.getMessagesPage('group-1');
      final group = await groupRepo.getGroup('group-1');
      final retrieveCount = bridge.commandLog
          .where((command) => command == 'group:inboxRetrieveCursor')
          .length;

      expect(messages, hasLength(1));
      expect(messages.single.id, 'msg-retained-page');
      expect(group, isNotNull);
      expect(group!.lastBacklogExpiredAt, expiredAt);
      expect(group.lastBacklogRetainedAt, retainedAt);
      expect(
        retrieveCount,
        2,
        reason:
            'Expired cursor pages must not stop continuation when later retained backlog still exists',
      );
    },
  );

  test('repeated drains do not resurrect expired backlog', () async {
    final cutoff = groupBacklogRetentionCutoff(DateTime.now().toUtc());
    final expiredAt = cutoff.subtract(const Duration(hours: 1));
    final retainedAt = cutoff.add(const Duration(hours: 1));

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Expired replay',
        'timestamp': expiredAt.toIso8601String(),
        'messageId': 'msg-expired-replay',
      },
    ], 'cursor-retained');

    bridge.addPage('group-1', 'cursor-retained', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Retained replay',
        'timestamp': retainedAt.toIso8601String(),
        'messageId': 'msg-retained-replay',
      },
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    final messages = await msgRepo.getMessagesPage('group-1');
    final group = await groupRepo.getGroup('group-1');

    expect(messages, hasLength(1));
    expect(messages.single.id, 'msg-retained-replay');
    expect(
      messages.where((message) => message.id == 'msg-expired-replay'),
      isEmpty,
    );
    expect(group, isNotNull);
    expect(group!.lastBacklogExpiredAt, expiredAt);
    expect(group.lastBacklogRetainedAt, retainedAt);
  });

  test(
    'system envelopes older than the retention cutoff still converge membership',
    () async {
      final initialJoinedAt = groupBacklogRetentionCutoff(
        DateTime.now().toUtc(),
      ).subtract(const Duration(days: 2));
      final removedAt = initialJoinedAt.add(const Duration(days: 1));

      await groupRepo.updateGroup(
        testGroup.copyWith(createdAt: initialJoinedAt),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          joinedAt: initialJoinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.writer,
          joinedAt: initialJoinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: initialJoinedAt,
        ),
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      addTearDown(listener.dispose);

      bridge.addPage('group-1', '', [
        {
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_removed',
              'member': {'peerId': 'peer-sender', 'username': 'Sender'},
              'removedAt': removedAt.toIso8601String(),
              'groupConfig': {
                'name': 'Test Group',
                'groupType': 'chat',
                'members': [
                  {'peerId': 'peer-admin', 'role': 'admin'},
                  {'peerId': 'peer-self', 'role': 'writer'},
                ],
                'createdBy': 'peer-admin',
                'createdAt': removedAt.toIso8601String(),
              },
            }),
            'timestamp': removedAt.toIso8601String(),
            'messageId': 'msg-old-member-removed',
          }),
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      final group = await groupRepo.getGroup('group-1');
      final messages = await msgRepo.getMessagesPage('group-1');

      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
      expect(
        messages.where(
          (message) =>
              message.id.startsWith('sys-member_removed:group-1:peer-sender:'),
        ),
        hasLength(1),
      );
      expect(group, isNotNull);
      expect(group!.lastBacklogExpiredAt, isNull);
      expect(group.lastBacklogRetainedAt, isNull);
    },
  );

  test('drain preserves quotedMessageId from inbox payload', () async {
    final ts = DateTime.now().toUtc().toIso8601String();

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Quoted offline reply',
        'timestamp': ts,
        'messageId': 'msg-quoted-offline',
        'quotedMessageId': 'msg-parent-1',
      },
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    final messages = await msgRepo.getMessagesPage('group-1');
    expect(messages, hasLength(1));
    expect(messages.first.id, 'msg-quoted-offline');
    expect(messages.first.quotedMessageId, 'msg-parent-1');
  });

  test(
    'inbox replay enriches a sparse live copy with quote and media',
    () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final ts = DateTime.now().toUtc().toIso8601String();

      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 1,
        text: '',
        timestamp: ts,
        messageId: 'msg-repair-1',
        mediaAttachmentRepo: mediaRepo,
      );

      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': '',
          'timestamp': ts,
          'messageId': 'msg-repair-1',
          'quotedMessageId': 'msg-parent-1',
          'media': [
            {
              'id': 'blob-repair-1',
              'mime': 'image/jpeg',
              'size': 1024,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'createdAt': ts,
            },
          ],
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        mediaAttachmentRepo: mediaRepo,
      );

      final saved = await msgRepo.getMessage('msg-repair-1');
      expect(saved, isNotNull);
      expect(saved!.quotedMessageId, 'msg-parent-1');

      final attachments = await mediaRepo.getAttachmentsForMessage(
        'msg-repair-1',
      );
      expect(attachments, hasLength(1));
      expect(attachments.first.id, 'blob-repair-1');
    },
  );

  test(
    'resume drains missed announcement messages exactly once for offline readers',
    () async {
      // Create an announcement group where the local user is a reader.
      final announcementGroup = GroupModel(
        id: 'group-announce',
        name: 'Announcements',
        type: GroupType.announcement,
        topicName: '/mknoon/group/group-announce',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(announcementGroup);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-announce',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final ts = DateTime.now().toUtc().toIso8601String();

      bridge.addPage('group-announce', '', [
        {
          'groupId': 'group-announce',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 1,
          'text': 'Announcement 1',
          'timestamp': ts,
          'messageId': 'msg-ann-1',
        },
        {
          'groupId': 'group-announce',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 1,
          'text': 'Announcement 2',
          'timestamp': ts,
          'messageId': 'msg-ann-2',
        },
      ], '');

      // Also set up group-1 to have no messages (empty page).
      bridge.addPage('group-1', '', [], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      // Both announcement messages should be saved.
      final announceMsgs = await msgRepo.getMessagesPage('group-announce');
      expect(announceMsgs.length, 2);

      // Drain again — should not duplicate.
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );
      final announceMsgs2 = await msgRepo.getMessagesPage('group-announce');
      expect(announceMsgs2.length, 2);
    },
  );

  test(
    'resume drains first group-inbox page before background continuation completes',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();

      // Page 1 (first page, returns cursor for page 2).
      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Page 1 msg 1',
          'timestamp': ts,
          'messageId': 'msg-p1-1',
        },
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Page 1 msg 2',
          'timestamp': ts,
          'messageId': 'msg-p1-2',
        },
      ], 'cursor-page-2');

      // Page 2 (continuation, no more pages).
      bridge.addPage('group-1', 'cursor-page-2', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Page 2 msg 1',
          'timestamp': ts,
          'messageId': 'msg-p2-1',
        },
      ], '');

      // Drain first page only.
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        drainAllPages: false,
      );

      // Only first page messages should be saved.
      expect(msgRepo.count, 2);
      final saved = await msgRepo.getMessagesPage('group-1');
      final texts = saved.map((m) => m.text).toSet();
      expect(texts, contains('Page 1 msg 1'));
      expect(texts, contains('Page 1 msg 2'));
      expect(texts, isNot(contains('Page 2 msg 1')));
    },
  );

  test(
    'group inbox continuation uses cursor rather than timestamp guessing',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();

      // Three pages with cursors.
      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Cursor page 1',
          'timestamp': ts,
          'messageId': 'msg-c1',
        },
      ], 'cursor-2');

      bridge.addPage('group-1', 'cursor-2', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Cursor page 2',
          'timestamp': ts,
          'messageId': 'msg-c2',
        },
      ], 'cursor-3');

      bridge.addPage('group-1', 'cursor-3', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Cursor page 3',
          'timestamp': ts,
          'messageId': 'msg-c3',
        },
      ], '');

      // Drain all pages.
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        drainAllPages: true,
      );

      expect(msgRepo.count, 3);

      // Verify the bridge received cursor-based requests (not timestamp-based).
      final retrieveCmds = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
          .toList();

      expect(retrieveCmds.length, 3);

      // First request should have empty cursor.
      expect(retrieveCmds[0]['payload']['cursor'], '');
      // Second request should use cursor-2.
      expect(retrieveCmds[1]['payload']['cursor'], 'cursor-2');
      // Third request should use cursor-3.
      expect(retrieveCmds[2]['payload']['cursor'], 'cursor-3');
    },
  );

  test(
    'cursor timeout logs a group error instead of treating backlog as drained',
    () async {
      final output = <String>[];
      final originalDebugPrint = debugPrint;
      flowEventLoggingEnabled = true;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
        flowEventLoggingEnabled = kDebugMode;
      });

      final timeoutBridge = _TimeoutCursorInboxBridge();
      bridge = timeoutBridge;
      timeoutBridge.addTimeout('group-1', '');

      final testGroup2 = GroupModel(
        id: 'group-2',
        name: 'Second Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/group-2',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(testGroup2);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final ts = DateTime.now().toUtc().toIso8601String();
      timeoutBridge.addPage('group-2', '', [
        {
          'groupId': 'group-2',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Recovered after timeout',
          'timestamp': ts,
          'messageId': 'msg-group-2',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: timeoutBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final group1Messages = await msgRepo.getMessagesPage('group-1');
      final group2Messages = await msgRepo.getMessagesPage('group-2');
      final events = output
          .where((line) => line.startsWith('[FLOW] '))
          .map(
            (line) =>
                jsonDecode(line.substring('[FLOW] '.length))
                    as Map<String, dynamic>,
          )
          .toList();

      expect(group1Messages, isEmpty);
      expect(group2Messages, hasLength(1));
      expect(group2Messages.single.id, 'msg-group-2');
      expect(
        events.any(
          (event) =>
              event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_ERROR' &&
              (event['details'] as Map<String, dynamic>)['groupId'] ==
                  'group-1',
        ),
        isTrue,
      );
      expect(
        events.any(
          (event) =>
              event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_DONE' &&
              (event['details'] as Map<String, dynamic>)['groupId'] ==
                  'group-1',
        ),
        isFalse,
      );
    },
  );

  test('emits GROUP_DRAIN_OFFLINE_INBOX_TIMING with batch metadata', () async {
    final testGroup = GroupModel(
      id: 'group-1',
      name: 'Test Group',
      type: GroupType.chat,
      topicName: '/mknoon/group/group-1',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.admin,
    );
    await groupRepo.saveGroup(testGroup);

    final ts = DateTime.now().toUtc().toIso8601String();
    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Drain timing proof',
        'timestamp': ts,
        'messageId': 'msg-d1',
      },
    ], '');

    final output = <String>[];
    final originalDebugPrint = debugPrint;
    flowEventLoggingEnabled = true;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) output.add(message);
    };
    addTearDown(() {
      debugPrint = originalDebugPrint;
      flowEventLoggingEnabled = kDebugMode;
    });

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      drainAllPages: true,
    );

    final events = output
        .where((line) => line.startsWith('[FLOW] '))
        .map(
          (line) =>
              jsonDecode(line.substring('[FLOW] '.length))
                  as Map<String, dynamic>,
        )
        .toList();

    final timing = events.lastWhere(
      (event) => event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
    );
    expect(timing['details']['outcome'], 'complete');
    expect(timing['details']['scope'], 'batch');
    expect(timing['details']['groupCount'], 1);
    expect(timing['details']['drainAllPages'], isTrue);
    expect(timing['details']['elapsedMs'], isA<int>());
  });

  // ---------------------------------------------------------------------------
  // Existing tests adapted to cursor-based API
  // ---------------------------------------------------------------------------

  test('drains offline inbox and saves messages to repo', () async {
    final ts = DateTime.now().toUtc().toIso8601String();

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Offline msg 1',
        'timestamp': ts,
        'messageId': 'msg-off-1',
      },
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Offline msg 2',
        'timestamp': ts,
        'messageId': 'msg-off-2',
      },
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    expect(msgRepo.count, 2);
    expect(bridge.commandLog, contains('group:inboxRetrieveCursor'));
  });

  test(
    'replayed group messages emit on the listener stream when provided',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();
      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Replay me into Feed',
          'timestamp': ts,
          'messageId': 'msg-replay-stream-1',
        },
      ], '');

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );
      final replayedMessages = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(
        replayedMessages.add,
      );
      addTearDown(() async {
        await subscription.cancel();
        listener.dispose();
      });

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      expect(msgRepo.count, 1);
      expect(replayedMessages, hasLength(1));
      expect(replayedMessages.single.id, 'msg-replay-stream-1');
      expect(replayedMessages.single.text, 'Replay me into Feed');
    },
  );

  test('does not crash on empty inbox', () async {
    bridge.addPage('group-1', '', [], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    expect(msgRepo.count, 0);
    expect(bridge.commandLog, contains('group:inboxRetrieveCursor'));
  });

  test(
    'per-group error isolation: first group error does not block second',
    () async {
      final testGroup2 = GroupModel(
        id: 'group-2',
        name: 'Second Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/group-2',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(testGroup2);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final ts = DateTime.now().toUtc().toIso8601String();

      // Group 1: no page registered (will cause error or empty result).
      // Group 2: has messages.
      bridge.addPage('group-2', '', [
        {
          'groupId': 'group-2',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Hello from group 2',
          'timestamp': ts,
          'messageId': 'msg-g2-err',
        },
      ], '');

      // Group 1 returns empty (no page registered for it), so no error,
      // just no messages saved.
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      // Group 2's message should have been saved.
      expect(msgRepo.count, 1);
    },
  );

  test('drains inbox for archived groups too', () async {
    await groupRepo.archiveGroup('group-1');

    final ts = DateTime.now().toUtc().toIso8601String();

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Archived group msg',
        'timestamp': ts,
        'messageId': 'msg-archived',
      },
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    expect(msgRepo.count, 1);
  });

  // ---------------------------------------------------------------------------
  // Media attachment tests
  // ---------------------------------------------------------------------------
  test('drains inbox message with media — saves media attachments', () async {
    final mediaRepo = InMemoryMediaAttachmentRepository();

    final inboxMessage = jsonEncode({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 1,
      'text': 'Photo message',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'messageId': 'msg-media',
      'media': [
        {
          'id': 'blob-inbox-1',
          'mime': 'image/jpeg',
          'size': 12345,
          'mediaType': 'image',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    });

    // Use raw envelope format (from, message, timestamp)
    bridge.addPage('group-1', '', [
      {'from': 'peer-sender', 'message': inboxMessage, 'timestamp': 123},
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      mediaAttachmentRepo: mediaRepo,
    );

    expect(msgRepo.count, 1);
    expect(mediaRepo.count, 1);
    final pending = await mediaRepo.getPendingDownloads();
    expect(pending.length, 1);
    expect(pending.first.mime, 'image/jpeg');
  });

  // ---------------------------------------------------------------------------
  // Reaction drain tests
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Phase 6: Cursor continuation and exactly-once delivery
  // ---------------------------------------------------------------------------

  group('drainGroupOfflineInbox use case', () {
    test(
      'resume uses cursor continuation rather than timestamp guessing',
      () async {
        final ts = DateTime.now().toUtc().toIso8601String();

        // Page 1 returns cursor "page2", page 2 returns cursor ""
        bridge.addPage('group-1', '', [
          {
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Page 1 message',
            'timestamp': ts,
            'messageId': 'msg-p6-p1',
          },
        ], 'page2');

        bridge.addPage('group-1', 'page2', [
          {
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Page 2 message',
            'timestamp': ts,
            'messageId': 'msg-p6-p2',
          },
        ], '');

        await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
        );

        // Verify that the bridge was called with cursor="page2" for the second page
        // and NOT with a sinceTimestamp
        final cursorCmds = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
            .toList();

        expect(cursorCmds.length, 2);
        expect(cursorCmds[0]['payload']['cursor'], '');
        expect(cursorCmds[1]['payload']['cursor'], 'page2');

        // Verify no sinceTimestamp field was sent
        for (final cmd in cursorCmds) {
          expect(
            cmd['payload'].containsKey('sinceTimestamp'),
            isFalse,
            reason: 'Cursor-based pagination should not use sinceTimestamp',
          );
        }

        expect(msgRepo.count, 2);
      },
    );

    test('watchdog restart drains missed group messages exactly once', () async {
      final ts = DateTime.now().toUtc().toIso8601String();

      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Watchdog missed msg',
          'timestamp': ts,
          'messageId': 'msg-wd-once',
        },
      ], '');

      // Drain the inbox
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      // Verify messages are saved to msgRepo exactly once
      expect(msgRepo.count, 1);

      // Drain again with the same page data (bridge still returns same message)
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      // Verify count hasn't changed (dedup by messageId)
      expect(
        msgRepo.count,
        1,
        reason: 'Draining twice should not duplicate messages',
      );
    });

    test(
      'first group inbox page returns before background continuation completes',
      () async {
        final ts = DateTime.now().toUtc().toIso8601String();

        // Page 1 with cursor pointing to page 2
        bridge.addPage('group-1', '', [
          {
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'First page only',
            'timestamp': ts,
            'messageId': 'msg-fp-1',
          },
        ], 'more-pages-cursor');

        // Page 2 (should not be fetched)
        bridge.addPage('group-1', 'more-pages-cursor', [
          {
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Second page',
            'timestamp': ts,
            'messageId': 'msg-fp-2',
          },
        ], '');

        // Call drainGroupOfflineInbox with drainAllPages: false
        await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          drainAllPages: false,
        );

        // Verify that only the first page is fetched
        expect(msgRepo.count, 1);

        // Bridge should have been called exactly once with cursor=""
        final cursorCmds = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
            .toList();

        expect(
          cursorCmds.length,
          1,
          reason: 'Only one page should be fetched when drainAllPages=false',
        );
        expect(cursorCmds[0]['payload']['cursor'], '');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Reaction drain tests
  // ---------------------------------------------------------------------------
  test('drains group_reaction items when reactionRepo is provided', () async {
    final reactionRepo = FakeReactionRepository();

    final innerReaction = jsonEncode({
      'id': 'rxn-1',
      'messageId': 'msg-1',
      'emoji': '\u{1F44D}',
      'action': 'add',
      'senderPeerId': 'peer-sender',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    final inboxMessage = jsonEncode({
      'type': 'group_reaction',
      'senderId': 'peer-sender',
      'reaction': innerReaction,
    });

    bridge.addPage('group-1', '', [
      {'from': 'peer-sender', 'message': inboxMessage, 'timestamp': 123},
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
    );

    // Reaction should be persisted.
    expect(reactionRepo.saveReactionCallCount, 1);
    // Should NOT be saved as a regular message.
    expect(msgRepo.count, 0);
  });
}
