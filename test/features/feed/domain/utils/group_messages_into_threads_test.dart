import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/group_messages_into_threads.dart';

ConversationMessage _msg({
  required String id,
  required String contactPeerId,
  required String text,
  required String timestamp,
  required bool isIncoming,
  String? readAt,
  String status = 'delivered',
  String? quotedMessageId,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: isIncoming ? contactPeerId : 'self',
    text: text,
    timestamp: timestamp,
    status: status,
    isIncoming: isIncoming,
    createdAt: timestamp,
    readAt: readAt,
    quotedMessageId: quotedMessageId,
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

    test('single unread incoming message produces unread state', () {
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
      expect(result[0].conversationState, ConversationState.unread);
      expect(result[0].isUnreadCard, isTrue);
      expect(result[0].unreadCount, 1);
      expect(result[0].messages.length, 1);
      expect(result[0].contactUsername, 'Alice');
    });

    test('sent + received messages both appear in thread', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Hello from Alice',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T12:05:00.000Z',
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'Hi Alice!',
            timestamp: '2026-02-09T12:10:00.000Z',
            isIncoming: false,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result.length, 1);
      expect(result[0].messages.length, 2);
      expect(result[0].messages[0].isIncoming, isTrue);
      expect(result[0].messages[1].isIncoming, isFalse);
    });

    test('state derivation: unread — unread incoming, no sent', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'New message',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result[0].conversationState, ConversationState.unread);
    });

    test('state derivation: active — unread incoming + sent messages', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Hey',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'Hi back',
            timestamp: '2026-02-09T12:05:00.000Z',
            isIncoming: false,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result[0].conversationState, ConversationState.active);
      expect(result[0].isUnreadCard, isTrue);
    });

    test('state derivation: replied — all read + has sent', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Read message',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T12:05:00.000Z',
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'My reply',
            timestamp: '2026-02-09T12:10:00.000Z',
            isIncoming: false,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result[0].conversationState, ConversationState.replied);
      expect(result[0].hasReply, isTrue);
      expect(result[0].lastRepliedAt, isNotNull);
    });

    test('state derivation: read — all read, no sent', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Read msg',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T12:30:00.000Z',
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result[0].conversationState, ConversationState.read);
      expect(result[0].isUnreadCard, isFalse);
    });

    test('24-hour gap splits into separate thread cards', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Yesterday',
            timestamp: '2026-02-08T10:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-08T10:05:00.000Z',
          ),
          // 25 hour gap
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'Today',
            timestamp: '2026-02-09T11:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T11:05:00.000Z',
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result.length, 2);
      expect(result[0].messages[0].text, 'Today'); // newest first
      expect(result[1].messages[0].text, 'Yesterday');
    });

    test('unread/active sort before read/replied', () {
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
      expect(result[0].conversationState, ConversationState.unread);
      expect(result[0].contactUsername, 'Bob');
      expect(result[1].conversationState, ConversationState.read);
      expect(result[1].contactUsername, 'Alice');
    });

    test('exchangePreview returns last 2 messages', () {
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
            isIncoming: false,
          ),
          _msg(
            id: 'msg-3',
            contactPeerId: 'peer-A',
            text: 'Third',
            timestamp: '2026-02-09T12:10:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T12:30:00.000Z',
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result.length, 1);
      final preview = result[0].exchangePreview;
      expect(preview.length, 2);
      expect(preview[0].text, 'Second');
      expect(preview[1].text, 'Third');
    });

    test('lastRepliedAt is set to latest sent message timestamp', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Hello',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T12:05:00.000Z',
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'Reply 1',
            timestamp: '2026-02-09T12:10:00.000Z',
            isIncoming: false,
          ),
          _msg(
            id: 'msg-3',
            contactPeerId: 'peer-A',
            text: 'Reply 2',
            timestamp: '2026-02-09T12:20:00.000Z',
            isIncoming: false,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result[0].lastRepliedAt,
          DateTime.parse('2026-02-09T12:20:00.000Z'));
    });

    test('user sends first (no incoming) produces replied state', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'I start',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: false,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result.length, 1);
      expect(result[0].conversationState, ConversationState.replied);
      expect(result[0].hasReply, isTrue);
    });

    test('ThreadMessage preserves isIncoming and status', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Incoming',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'Outgoing',
            timestamp: '2026-02-09T12:05:00.000Z',
            isIncoming: false,
            status: 'delivered',
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result[0].messages[0].isIncoming, isTrue);
      expect(result[0].messages[0].status, isNull); // incoming has no status
      expect(result[0].messages[1].isIncoming, isFalse);
      expect(result[0].messages[1].status, 'delivered');
    });

    test('multiple contacts produce separate threads', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'From Alice',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-B',
            text: 'From Bob',
            timestamp: '2026-02-09T12:05:00.000Z',
            isIncoming: true,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice', 'peer-B': 'Bob'},
      );

      expect(result.length, 2);
      // Both are unread, newest first
      expect(result[0].contactUsername, 'Bob');
      expect(result[1].contactUsername, 'Alice');
    });

    test('blocked contact produces ThreadFeedItem with isBlocked=true', () {
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
        contactBlocked: {'peer-A': true},
      );

      expect(result.length, 1);
      expect(result[0].isBlocked, isTrue);
      expect(result[0].contactUsername, 'Alice');
    });

    test('non-blocked contact produces ThreadFeedItem with isBlocked=false', () {
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
        contactBlocked: {'peer-A': false},
      );

      expect(result.length, 1);
      expect(result[0].isBlocked, isFalse);
    });

    test('quotedMessageId propagates to ThreadMessage', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Original message',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-09T12:05:00.000Z',
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'Quote reply',
            timestamp: '2026-02-09T12:10:00.000Z',
            isIncoming: false,
            quotedMessageId: 'msg-1',
          ),
          _msg(
            id: 'msg-3',
            contactPeerId: 'peer-A',
            text: 'Normal message',
            timestamp: '2026-02-09T12:15:00.000Z',
            isIncoming: false,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result.length, 1);
      expect(result[0].messages.length, 3);
      expect(result[0].messages[0].quotedMessageId, isNull);
      expect(result[0].messages[1].quotedMessageId, 'msg-1');
      expect(result[0].messages[2].quotedMessageId, isNull);
    });

    test('burst within same contact stays in one thread', () {
      final result = groupMessagesIntoThreads(
        allMessages: [
          _msg(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'Msg 1',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
          ),
          _msg(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'Msg 2',
            timestamp: '2026-02-09T12:01:00.000Z',
            isIncoming: true,
          ),
          _msg(
            id: 'msg-3',
            contactPeerId: 'peer-A',
            text: 'Msg 3',
            timestamp: '2026-02-09T12:02:00.000Z',
            isIncoming: false,
          ),
        ],
        contactUsernames: {'peer-A': 'Alice'},
      );

      expect(result.length, 1);
      expect(result[0].messages.length, 3);
    });
  });
}
