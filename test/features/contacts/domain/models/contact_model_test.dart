import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

void main() {
  group('ContactModel archive fields', () {
    test('fromMap reads archive fields', () {
      final model = ContactModel.fromMap({
        'peer_id': 'peer-1234567890',
        'public_key': 'pk-1',
        'rendezvous': '/dns4/relay/tcp/443',
        'username': 'Alice',
        'signature': 'sig-1',
        'scanned_at': '2026-01-01T00:00:00.000Z',
        'is_archived': 1,
        'archived_at': '2026-02-01T00:00:00.000Z',
      });

      expect(model.isArchived, isTrue);
      expect(model.archivedAt, '2026-02-01T00:00:00.000Z');
    });

    test('fromMap defaults when archive fields missing', () {
      final model = ContactModel.fromMap({
        'peer_id': 'peer-1234567890',
        'public_key': 'pk-1',
        'rendezvous': '/dns4/relay/tcp/443',
        'username': 'Alice',
        'signature': 'sig-1',
        'scanned_at': '2026-01-01T00:00:00.000Z',
      });

      expect(model.isArchived, isFalse);
      expect(model.archivedAt, isNull);
    });

    test('toMap writes archive fields as int', () {
      final model = ContactModel(
        peerId: 'peer-1234567890',
        publicKey: 'pk-1',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig-1',
        scannedAt: '2026-01-01T00:00:00.000Z',
        isArchived: true,
        archivedAt: '2026-02-01T00:00:00.000Z',
      );

      final map = model.toMap();
      expect(map['is_archived'], 1);
      expect(map['archived_at'], '2026-02-01T00:00:00.000Z');
    });

    test('toMap writes 0 for non-archived contact', () {
      final model = ContactModel(
        peerId: 'peer-1234567890',
        publicKey: 'pk-1',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig-1',
        scannedAt: '2026-01-01T00:00:00.000Z',
      );

      final map = model.toMap();
      expect(map['is_archived'], 0);
      expect(map['archived_at'], isNull);
    });

    test('copyWith updates archive fields', () {
      final model = ContactModel(
        peerId: 'peer-1234567890',
        publicKey: 'pk-1',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig-1',
        scannedAt: '2026-01-01T00:00:00.000Z',
      );

      final archived = model.copyWith(
        isArchived: true,
        archivedAt: '2026-02-01T00:00:00.000Z',
      );

      expect(archived.isArchived, isTrue);
      expect(archived.archivedAt, '2026-02-01T00:00:00.000Z');
      expect(archived.username, 'Alice'); // preserved
    });

    test('copyWith clearArchivedAt clears archivedAt', () {
      final model = ContactModel(
        peerId: 'peer-1234567890',
        publicKey: 'pk-1',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig-1',
        scannedAt: '2026-01-01T00:00:00.000Z',
        isArchived: true,
        archivedAt: '2026-02-01T00:00:00.000Z',
      );

      final unarchived = model.copyWith(
        isArchived: false,
        clearArchivedAt: true,
      );

      expect(unarchived.isArchived, isFalse);
      expect(unarchived.archivedAt, isNull);
    });
  });

  group('ContactModel block fields', () {
    test('fromMap reads block fields', () {
      final model = ContactModel.fromMap({
        'peer_id': 'peer-1234567890',
        'public_key': 'pk-1',
        'rendezvous': '/dns4/relay/tcp/443',
        'username': 'Alice',
        'signature': 'sig-1',
        'scanned_at': '2026-01-01T00:00:00.000Z',
        'is_blocked': 1,
        'blocked_at': '2026-02-15T00:00:00.000Z',
      });

      expect(model.isBlocked, isTrue);
      expect(model.blockedAt, '2026-02-15T00:00:00.000Z');
    });

    test('fromMap defaults when block fields missing', () {
      final model = ContactModel.fromMap({
        'peer_id': 'peer-1234567890',
        'public_key': 'pk-1',
        'rendezvous': '/dns4/relay/tcp/443',
        'username': 'Alice',
        'signature': 'sig-1',
        'scanned_at': '2026-01-01T00:00:00.000Z',
      });

      expect(model.isBlocked, isFalse);
      expect(model.blockedAt, isNull);
    });

    test('toMap writes block fields as int', () {
      final model = ContactModel(
        peerId: 'peer-1234567890',
        publicKey: 'pk-1',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig-1',
        scannedAt: '2026-01-01T00:00:00.000Z',
        isBlocked: true,
        blockedAt: '2026-02-15T00:00:00.000Z',
      );

      final map = model.toMap();
      expect(map['is_blocked'], 1);
      expect(map['blocked_at'], '2026-02-15T00:00:00.000Z');
    });

    test('toMap writes 0 for non-blocked contact', () {
      final model = ContactModel(
        peerId: 'peer-1234567890',
        publicKey: 'pk-1',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig-1',
        scannedAt: '2026-01-01T00:00:00.000Z',
      );

      final map = model.toMap();
      expect(map['is_blocked'], 0);
      expect(map['blocked_at'], isNull);
    });

    test('copyWith updates block fields', () {
      final model = ContactModel(
        peerId: 'peer-1234567890',
        publicKey: 'pk-1',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig-1',
        scannedAt: '2026-01-01T00:00:00.000Z',
      );

      final blocked = model.copyWith(
        isBlocked: true,
        blockedAt: '2026-02-15T00:00:00.000Z',
      );

      expect(blocked.isBlocked, isTrue);
      expect(blocked.blockedAt, '2026-02-15T00:00:00.000Z');
      expect(blocked.username, 'Alice'); // preserved
    });

    test('copyWith clearBlockedAt clears blockedAt', () {
      final model = ContactModel(
        peerId: 'peer-1234567890',
        publicKey: 'pk-1',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig-1',
        scannedAt: '2026-01-01T00:00:00.000Z',
        isBlocked: true,
        blockedAt: '2026-02-15T00:00:00.000Z',
      );

      final unblocked = model.copyWith(
        isBlocked: false,
        clearBlockedAt: true,
      );

      expect(unblocked.isBlocked, isFalse);
      expect(unblocked.blockedAt, isNull);
    });
  });
}
