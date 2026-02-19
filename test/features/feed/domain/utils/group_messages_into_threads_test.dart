import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/domain/utils/group_messages_into_threads.dart';

ConversationMessage _msg({
  required String id,
  required String contactPeerId,
  required String text,
  required String timestamp,
  required bool isIncoming,
  String? readAt,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: isIncoming ? contactPeerId : 'self',
    text: text,
    timestamp: timestamp,
    status: 'delivered',
    isIncoming: isIncoming,
    createdAt: timestamp,
    readAt: readAt,
  );
}

void main() {
  group('groupMessagesIntoThreads', () {
    test('empty input returns empty output', () {
      final result = groupMessagesIntoThreads(
        allMessages: [],
        contactUsernames: {},
      );
      expect(result, isEmpty);
    });

    test('single unread message produces one unread stack with badge', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Hello',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result.length, 1);
      expect(result[0].isUnreadCard, isTrue);
      expect(result[0].unreadCount, 1);
      expect(result[0].messages.length, 1);
      expect(result[0].contactUsername, 'Alice');
    });

    test('multiple unread messages from same contact grouped into one stack', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'First',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'Second',
            timestamp: '2026-02-09T12:05:00.000Z',
            isIncoming: true,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result.length, 1);
      expect(result[0].messages.length, 2);
      expect(result[0].messages[0].text, 'First');
      expect(result[0].messages[1].text, 'Second');
    });

    test('read messages from same session stay grouped without badge', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'First',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T12:30:00.000Z',
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'Second',
            timestamp: '2026-02-09T12:05:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T12:30:00.000Z', // same readAt = same session
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result.length, 1);
      expect(result[0].messages.length, 2);
      expect(result[0].unreadCount, 0);
      expect(result[0].isUnreadCard, isFalse);
    });

    test('different read sessions produce separate stacks', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          // First read session
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Session 1 msg',
            timestamp: '2026-02-09T10:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T10:30:00.000Z',
          ),
          // Second read session
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'Session 2 msg',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T12:30:00.000Z',
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      // Two separate read stacks from the same contact
      expect(result.length, 2);
      expect(result.every((t) => !t.isUnreadCard), isTrue);
      // Newest session first
      expect(result[0].messages[0].text, 'Session 2 msg');
      expect(result[1].messages[0].text, 'Session 1 msg');
    });

    test('unread stacks sort before read stacks', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Read msg',
            timestamp: '2026-02-09T14:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T14:30:00.000Z',
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-B',
            text: 'Unread msg',
            timestamp: '2026-02-09T11:00:00.000Z',
            isIncoming: true,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice', 'peer-B': 'Bob'},
      );

      expect(result.length, 2);
      expect(result[0].isUnreadCard, isTrue);
      expect(result[0].contactUsername, 'Bob');
      expect(result[1].isUnreadCard, isFalse);
      expect(result[1].contactUsername, 'Alice');
    });

    test('sent messages are filtered out', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Sent by me',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: false,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result, isEmpty);
    });

    test('new unread stack appears above old read stack from same contact', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Old read message',
            timestamp: '2026-02-09T10:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T10:30:00.000Z',
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'New unread message',
            timestamp: '2026-02-09T14:00:00.000Z',
            isIncoming: true,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result.length, 2);
      // Unread stack first
      expect(result[0].isUnreadCard, isTrue);
      expect(result[0].unreadCount, 1);
      expect(result[0].messages[0].text, 'New unread message');
      // Read stack second
      expect(result[1].isUnreadCard, isFalse);
      expect(result[1].messages[0].text, 'Old read message');
    });
  });
}
