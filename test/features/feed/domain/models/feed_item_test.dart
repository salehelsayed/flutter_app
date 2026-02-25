import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';

void main() {
  group('ConnectionFeedItem', () {
    test('has type connection', () {
      final item = ConnectionFeedItem(
        id: 'conn-1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: '12D3KooWPeer1',
        contactUsername: 'Alice',
      );
      expect(item.type, FeedItemType.connection);
    });

    test('fromContact creates correct item', () {
      final contact = ContactModel(
        peerId: '12D3KooWTestPeerId1234567890',
        publicKey: 'pk-base64',
        rendezvous: '/dns4/relay.example.com/tcp/443/p2p/relay-peer',
        username: 'Bob',
        signature: 'sig-base64',
        scannedAt: '2026-02-09T15:00:00.000Z',
      );

      final item = ConnectionFeedItem.fromContact(contact);
      expect(item.id, 'connection_12D3KooWTestPeerId1234567890');
      expect(item.contactPeerId, '12D3KooWTestPeerId1234567890');
      expect(item.contactUsername, 'Bob');
      expect(item.type, FeedItemType.connection);
      expect(item.timestamp, DateTime.utc(2026, 2, 9, 15, 0, 0));
    });
  });

  group('MessageFeedItem', () {
    test('has type message', () {
      final item = MessageFeedItem(
        id: 'message_msg-1',
        timestamp: DateTime.now(),
        contactPeerId: '12D3KooWPeer1',
        contactUsername: 'Alice',
        messageId: 'msg-1',
        messageText: 'Hello!',
        messageTime: '3:30 PM',
      );
      expect(item.type, FeedItemType.message);
    });

    test('stores all required fields', () {
      final ts = DateTime(2026, 2, 9, 15, 30);
      final item = MessageFeedItem(
        id: 'message_msg-2',
        timestamp: ts,
        contactPeerId: '12D3KooWPeer2',
        contactUsername: 'Bob',
        messageId: 'msg-2',
        messageText: 'Greetings!',
        messageTime: '3:30 PM',
      );

      expect(item.id, 'message_msg-2');
      expect(item.timestamp, ts);
      expect(item.contactPeerId, '12D3KooWPeer2');
      expect(item.contactUsername, 'Bob');
      expect(item.messageId, 'msg-2');
      expect(item.messageText, 'Greetings!');
      expect(item.messageTime, '3:30 PM');
    });
  });

  group('ThreadFeedItem', () {
    test('has type thread', () {
      final item = ThreadFeedItem(
        id: 'thread_unread_peer1',
        timestamp: DateTime.now(),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'msg-1',
            text: 'Hello',
            time: '3:30 PM',
            timestamp: DateTime(2026, 2, 9, 15, 30),
          ),
        ],
      );
      expect(item.type, FeedItemType.thread);
    });

    test('isMultiMessage returns true for multiple messages', () {
      final item = ThreadFeedItem(
        id: 'thread_unread_peer1',
        timestamp: DateTime(2026, 2, 9, 15, 30),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'msg-1',
            text: 'First',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
          ),
          ThreadMessage(
            id: 'msg-2',
            text: 'Second',
            time: '3:30 PM',
            timestamp: DateTime(2026, 2, 9, 15, 30),
          ),
        ],
      );

      expect(item.isMultiMessage, isTrue);
      expect(item.additionalCount, 1);
      expect(item.latestMessage.text, 'Second');
    });

    test('isMultiMessage returns false for single message', () {
      final item = ThreadFeedItem(
        id: 'thread_unread_peer1',
        timestamp: DateTime(2026, 2, 9, 15, 30),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'msg-1',
            text: 'Only one',
            time: '3:30 PM',
            timestamp: DateTime(2026, 2, 9, 15, 30),
          ),
        ],
      );

      expect(item.isMultiMessage, isFalse);
      expect(item.additionalCount, 0);
    });

    test('stores unread metadata correctly', () {
      final item = ThreadFeedItem(
        id: 'thread_unread_peer1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: const [],
        unreadCount: 3,
        isUnreadCard: true,
      );

      expect(item.unreadCount, 3);
      expect(item.isUnreadCard, isTrue);
    });
  });

  group('ThreadFeedItem computed properties', () {
    ThreadMessage _msg({
      required String id,
      bool isUnread = false,
      bool isIncoming = true,
      DateTime? timestamp,
    }) {
      final ts = timestamp ?? DateTime(2026, 2, 9, 15, 0);
      return ThreadMessage(
        id: id,
        text: 'msg $id',
        time: '3:00 PM',
        timestamp: ts,
        isUnread: isUnread,
        isIncoming: isIncoming,
      );
    }

    test('unreadMessages returns only unread incoming in chronological order',
        () {
      final item = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg(id: 'm1'), // read incoming
          _msg(id: 'm2', isIncoming: false), // sent
          _msg(id: 'm3', isUnread: true), // unread incoming
          _msg(id: 'm4', isUnread: true), // unread incoming
          _msg(id: 'm5', isUnread: true, isIncoming: false), // unread sent
        ],
      );

      final unread = item.unreadMessages;
      expect(unread.length, 2);
      expect(unread[0].id, 'm3');
      expect(unread[1].id, 'm4');
    });

    test('previewMessages returns first 3 unread when unread > 3', () {
      final item = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg(id: 'm1', isUnread: true),
          _msg(id: 'm2', isUnread: true),
          _msg(id: 'm3', isUnread: true),
          _msg(id: 'm4', isUnread: true),
          _msg(id: 'm5', isUnread: true),
        ],
      );

      final preview = item.previewMessages;
      expect(preview.length, 3);
      expect(preview[0].id, 'm1');
      expect(preview[2].id, 'm3');
    });

    test('previewMessages returns all unread when unread <= 3', () {
      final item = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg(id: 'm1', isUnread: true),
          _msg(id: 'm2', isUnread: true),
        ],
      );

      expect(item.previewMessages.length, 2);
    });

    test('hasEarlierHistory true when read messages exist before first unread',
        () {
      final item = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg(id: 'm1'), // read
          _msg(id: 'm2'), // read
          _msg(id: 'm3', isUnread: true), // unread
        ],
      );

      expect(item.hasEarlierHistory, isTrue);
    });

    test('hasEarlierHistory false when all messages are unread', () {
      final item = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg(id: 'm1', isUnread: true),
          _msg(id: 'm2', isUnread: true),
        ],
      );

      expect(item.hasEarlierHistory, isFalse);
    });

    test('isOpenMode true for unread, false for read', () {
      final unread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg(id: 'm1')],
        conversationState: ConversationState.unread,
      );
      expect(unread.isOpenMode, isTrue);

      final active = ThreadFeedItem(
        id: 'thread_2',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg(id: 'm1')],
        conversationState: ConversationState.active,
      );
      expect(active.isOpenMode, isTrue);

      final read = ThreadFeedItem(
        id: 'thread_3',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg(id: 'm1')],
        conversationState: ConversationState.read,
      );
      expect(read.isOpenMode, isFalse);

      final replied = ThreadFeedItem(
        id: 'thread_4',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg(id: 'm1')],
        conversationState: ConversationState.replied,
      );
      expect(replied.isOpenMode, isFalse);
    });

    test('lastSentMessage returns most recent outgoing, null when none', () {
      final withSent = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg(id: 'm1'), // incoming
          _msg(id: 'm2', isIncoming: false), // sent
          _msg(id: 'm3'), // incoming
          _msg(id: 'm4', isIncoming: false), // sent (latest)
        ],
      );
      expect(withSent.lastSentMessage?.id, 'm4');

      final noSent = ThreadFeedItem(
        id: 'thread_2',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg(id: 'm1'),
          _msg(id: 'm2'),
        ],
      );
      expect(noSent.lastSentMessage, isNull);
    });

    test('collapsedPreviewMessage always returns latestMessage', () {
      final withSent = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg(id: 'm1'),
          _msg(id: 'm2', isIncoming: false),
          _msg(id: 'm3'), // latestMessage
        ],
      );
      // Always returns latest message regardless of direction
      expect(withSent.collapsedPreviewMessage.id, 'm3');

      final noSent = ThreadFeedItem(
        id: 'thread_2',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg(id: 'm1'),
          _msg(id: 'm2'),
        ],
      );
      expect(noSent.collapsedPreviewMessage.id, 'm2');
    });
  });

  group('recentInteractionMessages', () {
    ThreadMessage _msg({
      required String id,
      bool isUnread = false,
      bool isIncoming = true,
    }) {
      return ThreadMessage(
        id: id,
        text: 'msg $id',
        time: '3:00 PM',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        isUnread: isUnread,
        isIncoming: isIncoming,
      );
    }

    ThreadFeedItem _thread(List<ThreadMessage> messages) {
      return ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: messages,
        conversationState: ConversationState.read,
      );
    }

    test('empty thread returns empty list', () {
      final item = _thread([]);
      expect(item.recentInteractionMessages, isEmpty);
    });

    test('1 unread incoming returns it', () {
      final item = _thread([_msg(id: 'm1', isUnread: true)]);
      expect(item.recentInteractionMessages.length, 1);
      expect(item.recentInteractionMessages[0].id, 'm1');
    });

    test('3 read + 2 unread returns from first unread onward', () {
      final item = _thread([
        _msg(id: 'm1'),
        _msg(id: 'm2'),
        _msg(id: 'm3'),
        _msg(id: 'm4', isUnread: true),
        _msg(id: 'm5', isUnread: true),
      ]);
      final result = item.recentInteractionMessages;
      expect(result.length, 2);
      expect(result[0].id, 'm4');
      expect(result[1].id, 'm5');
    });

    test('1 unread + 2 sent after returns all 3', () {
      final item = _thread([
        _msg(id: 'm1'),
        _msg(id: 'm2', isUnread: true),
        _msg(id: 'm3', isIncoming: false),
        _msg(id: 'm4', isIncoming: false),
      ]);
      final result = item.recentInteractionMessages;
      expect(result.length, 3);
      expect(result[0].id, 'm2');
      expect(result[1].id, 'm3');
      expect(result[2].id, 'm4');
    });

    test('5 unread returns all 5', () {
      final item = _thread([
        _msg(id: 'm1', isUnread: true),
        _msg(id: 'm2', isUnread: true),
        _msg(id: 'm3', isUnread: true),
        _msg(id: 'm4', isUnread: true),
        _msg(id: 'm5', isUnread: true),
      ]);
      expect(item.recentInteractionMessages.length, 5);
    });

    test('0 unread, 7 total returns last 3 (maxPreview)', () {
      final item = _thread([
        _msg(id: 'm1'),
        _msg(id: 'm2'),
        _msg(id: 'm3'),
        _msg(id: 'm4'),
        _msg(id: 'm5'),
        _msg(id: 'm6'),
        _msg(id: 'm7'),
      ]);
      final result = item.recentInteractionMessages;
      expect(result.length, 3);
      expect(result[0].id, 'm5');
      expect(result[1].id, 'm6');
      expect(result[2].id, 'm7');
    });

    test('0 unread, 2 total returns both', () {
      final item = _thread([
        _msg(id: 'm1'),
        _msg(id: 'm2'),
      ]);
      expect(item.recentInteractionMessages.length, 2);
    });

    test('interleaved: read, sent, unread, sent, unread → from first unread', () {
      final item = _thread([
        _msg(id: 'm1'),               // read incoming
        _msg(id: 'm2', isIncoming: false),  // sent
        _msg(id: 'm3', isUnread: true),     // unread incoming
        _msg(id: 'm4', isIncoming: false),  // sent
        _msg(id: 'm5', isUnread: true),     // unread incoming
      ]);
      final result = item.recentInteractionMessages;
      expect(result.length, 3);
      expect(result[0].id, 'm3');
    });

    test('only sent, 5 total returns last 3', () {
      final item = _thread([
        _msg(id: 'm1', isIncoming: false),
        _msg(id: 'm2', isIncoming: false),
        _msg(id: 'm3', isIncoming: false),
        _msg(id: 'm4', isIncoming: false),
        _msg(id: 'm5', isIncoming: false),
      ]);
      final result = item.recentInteractionMessages;
      expect(result.length, 3);
      expect(result[0].id, 'm3');
    });

    test('only 1 message returns that message', () {
      final item = _thread([_msg(id: 'm1')]);
      expect(item.recentInteractionMessages.length, 1);
      expect(item.recentInteractionMessages[0].id, 'm1');
    });
  });

  group('hasEarlierInteractionHistory', () {
    ThreadMessage _msg({
      required String id,
      bool isUnread = false,
      bool isIncoming = true,
    }) {
      return ThreadMessage(
        id: id,
        text: 'msg $id',
        time: '3:00 PM',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        isUnread: isUnread,
        isIncoming: isIncoming,
      );
    }

    ThreadFeedItem _thread(List<ThreadMessage> messages) {
      return ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: messages,
        conversationState: ConversationState.read,
      );
    }

    test('empty thread returns false', () {
      expect(_thread([]).hasEarlierInteractionHistory, isFalse);
    });

    test('all unread from start returns false', () {
      final item = _thread([
        _msg(id: 'm1', isUnread: true),
        _msg(id: 'm2', isUnread: true),
      ]);
      expect(item.hasEarlierInteractionHistory, isFalse);
    });

    test('read messages before first unread returns true', () {
      final item = _thread([
        _msg(id: 'm1'),
        _msg(id: 'm2'),
        _msg(id: 'm3', isUnread: true),
      ]);
      expect(item.hasEarlierInteractionHistory, isTrue);
    });

    test('0 unread, more than maxPreview returns true', () {
      final item = _thread([
        _msg(id: 'm1'),
        _msg(id: 'm2'),
        _msg(id: 'm3'),
        _msg(id: 'm4'),
      ]);
      expect(item.hasEarlierInteractionHistory, isTrue);
    });

    test('0 unread, exactly maxPreview returns false', () {
      final item = _thread([
        _msg(id: 'm1'),
        _msg(id: 'm2'),
        _msg(id: 'm3'),
      ]);
      expect(item.hasEarlierInteractionHistory, isFalse);
    });

    test('0 unread, less than maxPreview returns false', () {
      final item = _thread([
        _msg(id: 'm1'),
        _msg(id: 'm2'),
      ]);
      expect(item.hasEarlierInteractionHistory, isFalse);
    });
  });

  group('ThreadMessage', () {
    test('stores all fields', () {
      final ts = DateTime(2026, 2, 9, 15, 30);
      final msg = ThreadMessage(
        id: 'msg-1',
        text: 'Hello world',
        time: '3:30 PM',
        timestamp: ts,
        isUnread: true,
      );

      expect(msg.id, 'msg-1');
      expect(msg.text, 'Hello world');
      expect(msg.time, '3:30 PM');
      expect(msg.timestamp, ts);
      expect(msg.isUnread, isTrue);
    });

    test('isUnread defaults to false', () {
      final msg = ThreadMessage(
        id: 'msg-1',
        text: 'Hello',
        time: '3:30 PM',
        timestamp: DateTime(2026, 2, 9, 15, 30),
      );

      expect(msg.isUnread, isFalse);
    });
  });
}
