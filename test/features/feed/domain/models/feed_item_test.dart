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
}
