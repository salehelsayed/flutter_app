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
