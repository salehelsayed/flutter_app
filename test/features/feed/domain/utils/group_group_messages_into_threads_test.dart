import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/group_group_messages_into_threads.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

GroupModel _makeGroup(
  String id,
  String name, {
  GroupType type = GroupType.chat,
}) {
  return GroupModel(
    id: id,
    name: name,
    type: type,
    topicName: '/mknoon/group/$id',
    createdAt: DateTime(2026, 1, 1),
    createdBy: 'admin-peer',
    myRole: GroupRole.member,
  );
}

GroupMessage _makeMsg({
  required String id,
  required String groupId,
  required String senderPeerId,
  required String text,
  required DateTime timestamp,
  bool isIncoming = true,
  DateTime? readAt,
  String? quotedMessageId,
}) {
  return GroupMessage(
    id: id,
    groupId: groupId,
    senderPeerId: senderPeerId,
    senderUsername: 'User',
    text: text,
    timestamp: timestamp,
    isIncoming: isIncoming,
    readAt: readAt,
    quotedMessageId: quotedMessageId,
    createdAt: timestamp,
  );
}

void main() {
  group('groupGroupMessagesIntoThreads', () {
    test('returns empty list when no messages', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [],
        groups: [_makeGroup('g1', 'Group 1')],
      );
      expect(result, isEmpty);
    });

    test('returns empty list when no groups', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Hello',
            timestamp: DateTime(2026, 2, 9, 12, 0),
          ),
        ],
        groups: [],
      );
      expect(result, isEmpty);
    });

    test('creates one thread per group', () {
      final groups = [_makeGroup('g1', 'Alpha'), _makeGroup('g2', 'Beta')];
      final messages = [
        _makeMsg(
          id: 'm1',
          groupId: 'g1',
          senderPeerId: 'p1',
          text: 'Hello Alpha',
          timestamp: DateTime(2026, 2, 9, 12, 0),
        ),
        _makeMsg(
          id: 'm2',
          groupId: 'g2',
          senderPeerId: 'p2',
          text: 'Hello Beta',
          timestamp: DateTime(2026, 2, 9, 13, 0),
        ),
      ];

      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: messages,
        groups: groups,
      );

      expect(result.length, 2);
      expect(result[0].groupName, 'Beta'); // 13:00 newest first
      expect(result[1].groupName, 'Alpha'); // 12:00
    });

    test('derives unread state when unread incoming with no sent', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Unread',
            timestamp: DateTime(2026, 2, 9, 12, 0),
          ),
        ],
        groups: [_makeGroup('g1', 'Group')],
      );

      expect(result.length, 1);
      expect(result[0].conversationState, ConversationState.unread);
      expect(result[0].unreadCount, 1);
    });

    test('derives active state when unread incoming + sent messages', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'From other',
            timestamp: DateTime(2026, 2, 9, 12, 0),
          ),
          _makeMsg(
            id: 'm2',
            groupId: 'g1',
            senderPeerId: 'me',
            text: 'My reply',
            timestamp: DateTime(2026, 2, 9, 12, 5),
            isIncoming: false,
          ),
        ],
        groups: [_makeGroup('g1', 'Group')],
      );

      expect(result[0].conversationState, ConversationState.active);
    });

    test('derives replied state when all read + sent messages', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Read msg',
            timestamp: DateTime(2026, 2, 9, 12, 0),
            readAt: DateTime(2026, 2, 9, 12, 1),
          ),
          _makeMsg(
            id: 'm2',
            groupId: 'g1',
            senderPeerId: 'me',
            text: 'Reply',
            timestamp: DateTime(2026, 2, 9, 12, 5),
            isIncoming: false,
          ),
        ],
        groups: [_makeGroup('g1', 'Group')],
      );

      expect(result[0].conversationState, ConversationState.replied);
    });

    test('derives read state when all incoming are read, no sent', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Read',
            timestamp: DateTime(2026, 2, 9, 12, 0),
            readAt: DateTime(2026, 2, 9, 12, 1),
          ),
        ],
        groups: [_makeGroup('g1', 'Group')],
      );

      expect(result[0].conversationState, ConversationState.read);
    });

    test('sorts unread/active before read/replied', () {
      final groups = [
        _makeGroup('g1', 'ReadGroup'),
        _makeGroup('g2', 'UnreadGroup'),
      ];
      final messages = [
        _makeMsg(
          id: 'm1',
          groupId: 'g1',
          senderPeerId: 'p1',
          text: 'Read',
          timestamp: DateTime(2026, 2, 9, 14, 0),
          readAt: DateTime(2026, 2, 9, 14, 1),
        ),
        _makeMsg(
          id: 'm2',
          groupId: 'g2',
          senderPeerId: 'p2',
          text: 'Unread',
          timestamp: DateTime(2026, 2, 9, 10, 0),
        ),
      ];

      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: messages,
        groups: groups,
      );

      expect(result.length, 2);
      // Unread first even though timestamp is older
      expect(result[0].groupName, 'UnreadGroup');
      expect(result[1].groupName, 'ReadGroup');
    });

    test('ignores messages for unknown groups', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'unknown-group',
            senderPeerId: 'p1',
            text: 'Hello',
            timestamp: DateTime(2026, 2, 9, 12, 0),
          ),
        ],
        groups: [_makeGroup('g1', 'Known Group')],
      );

      expect(result, isEmpty);
    });

    test('messages sorted chronologically within thread', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm3',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Third',
            timestamp: DateTime(2026, 2, 9, 15, 0),
          ),
          _makeMsg(
            id: 'm1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'First',
            timestamp: DateTime(2026, 2, 9, 12, 0),
          ),
          _makeMsg(
            id: 'm2',
            groupId: 'g1',
            senderPeerId: 'p2',
            text: 'Second',
            timestamp: DateTime(2026, 2, 9, 13, 0),
          ),
        ],
        groups: [_makeGroup('g1', 'Group')],
      );

      expect(result[0].messages.length, 3);
      expect(result[0].messages[0].text, 'First');
      expect(result[0].messages[1].text, 'Second');
      expect(result[0].messages[2].text, 'Third');
    });

    test('preserves group type in thread item', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Hello',
            timestamp: DateTime(2026, 2, 9, 12, 0),
          ),
        ],
        groups: [
          _makeGroup('g1', 'Announcements', type: GroupType.announcement),
        ],
      );

      expect(result[0].groupType, GroupType.announcement);
    });

    test('preserves myRole and derives canWrite for announcement groups', () {
      final adminGroup = _makeGroup(
        'g1',
        'Announcements',
        type: GroupType.announcement,
      ).copyWith(myRole: GroupRole.admin);
      final memberGroup = _makeGroup(
        'g2',
        'Announcements',
        type: GroupType.announcement,
      );

      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Admin update',
            timestamp: DateTime(2026, 2, 9, 12, 0),
          ),
          _makeMsg(
            id: 'm2',
            groupId: 'g2',
            senderPeerId: 'p2',
            text: 'Member update',
            timestamp: DateTime(2026, 2, 9, 13, 0),
          ),
        ],
        groups: [adminGroup, memberGroup],
      );

      expect(
        result.singleWhere((item) => item.groupId == 'g1').myRole,
        GroupRole.admin,
      );
      expect(
        result.singleWhere((item) => item.groupId == 'g1').canWrite,
        isTrue,
      );
      expect(
        result.singleWhere((item) => item.groupId == 'g1').canReact,
        isTrue,
      );
      expect(
        result.singleWhere((item) => item.groupId == 'g2').myRole,
        GroupRole.member,
      );
      expect(
        result.singleWhere((item) => item.groupId == 'g2').canWrite,
        isFalse,
      );
      expect(
        result.singleWhere((item) => item.groupId == 'g2').canReact,
        isTrue,
      );
    });

    test('preserves dissolved state and freezes write and reaction entry', () {
      final dissolvedGroup = _makeGroup('g1', 'Frozen Group').copyWith(
        isDissolved: true,
        dissolvedAt: DateTime.utc(2026, 2, 9, 11, 59),
        dissolvedBy: 'admin-peer',
      );

      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Frozen history',
            timestamp: DateTime.utc(2026, 2, 9, 12, 0),
          ),
        ],
        groups: [dissolvedGroup],
      );

      expect(result.single.isDissolved, isTrue);
      expect(result.single.canWrite, isFalse);
      expect(result.single.canReact, isFalse);
    });

    test('preserves quotedMessageId on projected thread messages', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Parent',
            timestamp: DateTime(2026, 2, 9, 12, 0),
          ),
          _makeMsg(
            id: 'm2',
            groupId: 'g1',
            senderPeerId: 'p2',
            text: 'Reply',
            timestamp: DateTime(2026, 2, 9, 12, 1),
            quotedMessageId: 'm1',
          ),
        ],
        groups: [_makeGroup('g1', 'Quoted Group')],
      );

      expect(result.single.messages.last.quotedMessageId, 'm1');
    });

    test('thread id is group_thread_ + groupId', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'abc-123',
            senderPeerId: 'p1',
            text: 'Hello',
            timestamp: DateTime(2026, 2, 9, 12, 0),
          ),
        ],
        groups: [_makeGroup('abc-123', 'Group')],
      );

      expect(result[0].id, 'group_thread_abc-123');
    });

    test('timestamp is latest message timestamp', () {
      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'm1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Old',
            timestamp: DateTime(2026, 2, 8, 12, 0),
          ),
          _makeMsg(
            id: 'm2',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'New',
            timestamp: DateTime(2026, 2, 9, 15, 0),
          ),
        ],
        groups: [_makeGroup('g1', 'Group')],
      );

      expect(result[0].timestamp, DateTime(2026, 2, 9, 15, 0));
    });

    test('MS003 orders equal-timestamp group feed messages by id', () {
      final sameTimestamp = DateTime.utc(2026, 4, 30, 12);

      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'ms003-b',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'B at same time',
            timestamp: sameTimestamp,
          ),
          _makeMsg(
            id: 'ms003-a',
            groupId: 'g1',
            senderPeerId: 'p2',
            text: 'A at same time',
            timestamp: sameTimestamp,
          ),
        ],
        groups: [_makeGroup('g1', 'Skewed Group')],
      );

      expect(result.single.messages.map((message) => message.id), [
        'ms003-a',
        'ms003-b',
      ]);
      expect(result.single.messages.last.text, 'B at same time');
    });

    test('MS004 places quoted parent before reply in group feed', () {
      final parentTimestamp = DateTime.utc(2026, 4, 30, 12, 0, 1);
      final replyTimestamp = DateTime.utc(2026, 4, 30, 12);

      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: [
          _makeMsg(
            id: 'aa-ms004-reply',
            groupId: 'g1',
            senderPeerId: 'p2',
            text: 'Reply',
            timestamp: replyTimestamp,
            quotedMessageId: 'zz-ms004-parent',
          ),
          _makeMsg(
            id: 'zz-ms004-parent',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Parent',
            timestamp: parentTimestamp,
          ),
          _makeMsg(
            id: 'mm-ms004-peer',
            groupId: 'g1',
            senderPeerId: 'p3',
            text: 'Concurrent peer',
            timestamp: replyTimestamp,
          ),
        ],
        groups: [_makeGroup('g1', 'Causal Group')],
      );

      expect(result.single.messages.map((message) => message.id), [
        'mm-ms004-peer',
        'zz-ms004-parent',
        'aa-ms004-reply',
      ]);
      expect(result.single.messages.last.quotedMessageId, 'zz-ms004-parent');
    });

    test(
      'ThreadMessage includes senderUsername and senderPeerId from GroupMessage',
      () {
        final result = groupGroupMessagesIntoThreads(
          allGroupMessages: [
            _makeMsg(
              id: 'm1',
              groupId: 'g1',
              senderPeerId: 'peer-alice',
              text: 'Hi from Alice',
              timestamp: DateTime(2026, 2, 9, 12, 0),
            ),
            _makeMsg(
              id: 'm2',
              groupId: 'g1',
              senderPeerId: 'peer-bob',
              text: 'Hi from Bob',
              timestamp: DateTime(2026, 2, 9, 12, 5),
            ),
          ],
          groups: [_makeGroup('g1', 'Group')],
        );

        expect(result[0].messages[0].senderPeerId, 'peer-alice');
        expect(result[0].messages[0].senderUsername, 'User');
        expect(result[0].messages[1].senderPeerId, 'peer-bob');
        expect(result[0].messages[1].senderUsername, 'User');
      },
    );

    test('multiple unread groups sorted newest-first within above section', () {
      final groups = [
        _makeGroup('g1', 'OlderUnread'),
        _makeGroup('g2', 'NewerUnread'),
      ];
      final messages = [
        _makeMsg(
          id: 'm1',
          groupId: 'g1',
          senderPeerId: 'p1',
          text: 'Msg',
          timestamp: DateTime(2026, 2, 9, 10, 0),
        ),
        _makeMsg(
          id: 'm2',
          groupId: 'g2',
          senderPeerId: 'p2',
          text: 'Msg',
          timestamp: DateTime(2026, 2, 9, 14, 0),
        ),
      ];

      final result = groupGroupMessagesIntoThreads(
        allGroupMessages: messages,
        groups: groups,
      );

      expect(result[0].groupName, 'NewerUnread');
      expect(result[1].groupName, 'OlderUnread');
    });
  });
}
