import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';

void main() {
  const contact = ContactModel(
    peerId: 'peer-1234567890',
    publicKey: 'pk',
    rendezvous: '/dns4/relay',
    username: 'Alice',
    signature: 'sig',
    scannedAt: '2026-01-01T00:00:00.000Z',
    isArchived: true,
    isBlocked: false,
  );

  group('OrbitFriend', () {
    test('delegates peerId from contact', () {
      final friend = OrbitFriend(
        contact: contact,
        messageCount: 5,
      );

      expect(friend.peerId, contact.peerId);
    });

    test('delegates username from contact', () {
      final friend = OrbitFriend(
        contact: contact,
        messageCount: 5,
      );

      expect(friend.username, contact.username);
    });

    test('delegates isArchived from contact', () {
      final friend = OrbitFriend(
        contact: contact,
        messageCount: 5,
      );

      expect(friend.isArchived, contact.isArchived);
      expect(friend.isArchived, isTrue);
    });

    test('delegates isBlocked from contact', () {
      final friend = OrbitFriend(
        contact: contact,
        messageCount: 5,
      );

      expect(friend.isBlocked, contact.isBlocked);
      expect(friend.isBlocked, isFalse);
    });

    test('unreadCount defaults to 0', () {
      final friend = OrbitFriend(
        contact: contact,
        messageCount: 10,
      );

      expect(friend.unreadCount, 0);
    });

    test('delegates scannedAt from contact', () {
      final friend = OrbitFriend(
        contact: contact,
        messageCount: 3,
      );

      expect(friend.scannedAt, contact.scannedAt);
    });

    test('delegates avatarPath from contact', () {
      final contactWithAvatar = ContactModel(
        peerId: 'peer-1234567890',
        publicKey: 'pk',
        rendezvous: '/dns4/relay',
        username: 'Alice',
        signature: 'sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
        avatarPath: '/path/to/avatar.jpg',
      );

      final friend = OrbitFriend(
        contact: contactWithAvatar,
        messageCount: 1,
      );

      expect(friend.avatarPath, '/path/to/avatar.jpg');
    });

    test('avatarPath is null when contact has no avatar', () {
      final friend = OrbitFriend(
        contact: contact,
        messageCount: 1,
      );

      expect(friend.avatarPath, isNull);
    });
  });
}
