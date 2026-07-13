import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';

void main() {
  late ContactRepositoryImpl repo;
  late List<String> archiveCalls;
  late List<String> unarchiveCalls;
  late List<String> blockCalls;
  late List<String> unblockCalls;

  ContactModel makeContact(String peerId, {bool isArchived = false}) {
    return ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/dns4/relay/tcp/443',
      username: 'User-$peerId',
      signature: 'sig-$peerId',
      scannedAt: '2026-01-01T00:00:00.000Z',
      isArchived: isArchived,
      archivedAt: isArchived ? '2026-02-01T00:00:00.000Z' : null,
    );
  }

  setUp(() {
    archiveCalls = [];
    unarchiveCalls = [];
    blockCalls = [];
    unblockCalls = [];

    final active = [makeContact('peer-A'), makeContact('peer-B')];
    final archived = [makeContact('peer-C', isArchived: true)];
    final all = [...active, ...archived];

    repo = ContactRepositoryImpl(
      dbLoadAllContacts: () async => all.map((c) => c.toMap()).toList(),
      dbLoadContact: (peerId) async {
        final c = all.where((c) => c.peerId == peerId).firstOrNull;
        return c?.toMap();
      },
      dbUpsertContact: (_) async {},
      dbDeleteContact: (_) async {},
      dbGetContactCount: () async => all.length,
      dbContactExists: (peerId) async => all.any((c) => c.peerId == peerId),
      dbArchiveContact: (peerId) async => archiveCalls.add(peerId),
      dbUnarchiveContact: (peerId) async => unarchiveCalls.add(peerId),
      dbLoadActiveContacts: () async => active.map((c) => c.toMap()).toList(),
      dbLoadArchivedContacts: () async =>
          archived.map((c) => c.toMap()).toList(),
      dbBlockContact: (peerId) async => blockCalls.add(peerId),
      dbUnblockContact: (peerId) async => unblockCalls.add(peerId),
      dbDismissIntroBanner: (peerId) async {},
      dbSetIntrosSentAt: (peerId, timestamp) async {},
    );
  });

  group('archiveContact', () {
    test('calls dbArchiveContact with correct peerId', () async {
      await repo.archiveContact('peer-A0000000');
      expect(archiveCalls, ['peer-A0000000']);
    });
  });

  group('unarchiveContact', () {
    test('calls dbUnarchiveContact with correct peerId', () async {
      await repo.unarchiveContact('peer-C0000000');
      expect(unarchiveCalls, ['peer-C0000000']);
    });
  });

  group('getActiveContacts', () {
    test('returns only non-archived contacts', () async {
      final result = await repo.getActiveContacts();
      expect(result.length, 2);
      expect(result.every((c) => !c.isArchived), isTrue);
    });
  });

  group('getArchivedContacts', () {
    test('returns only archived contacts', () async {
      final result = await repo.getArchivedContacts();
      expect(result.length, 1);
      expect(result.every((c) => c.isArchived), isTrue);
    });
  });

  group('blockContact', () {
    test('calls dbBlockContact with correct peerId', () async {
      await repo.blockContact('peer-A0000000');
      expect(blockCalls, ['peer-A0000000']);
    });
  });

  group('unblockContact', () {
    test('calls dbUnblockContact with correct peerId', () async {
      await repo.unblockContact('peer-A0000000');
      expect(unblockCalls, ['peer-A0000000']);
    });
  });

  test(
    'repository mutations and backfill keep direct reaction projection current',
    () async {
      final rows = <String, Map<String, Object?>>{};
      final projection = DirectReactionNotificationProjection(
        store: _MemorySecureKeyStore(),
      );
      final projectedRepo = ContactRepositoryImpl(
        dbLoadAllContacts: () async => rows.values.toList(),
        dbLoadContact: (peerId) async => rows[peerId],
        dbUpsertContact: (row) async =>
            rows[row['peer_id'] as String] = Map<String, Object?>.from(row),
        dbDeleteContact: (peerId) async => rows.remove(peerId),
        dbGetContactCount: () async => rows.length,
        dbContactExists: (peerId) async => rows.containsKey(peerId),
        dbArchiveContact: (peerId) async => rows[peerId]?['is_archived'] = 1,
        dbUnarchiveContact: (peerId) async => rows[peerId]?['is_archived'] = 0,
        dbLoadActiveContacts: () async => rows.values.toList(),
        dbLoadArchivedContacts: () async => const <Map<String, Object?>>[],
        dbBlockContact: (peerId) async => rows[peerId]?['is_blocked'] = 1,
        dbUnblockContact: (peerId) async => rows[peerId]?['is_blocked'] = 0,
        dbDismissIntroBanner: (_) async {},
        dbSetIntrosSentAt: (peerId, timestamp) async {},
        directReactionProjection: projection,
      );
      final contact = makeContact('peer-projected');
      await projection.replaceLocalIdentity(accountPeerId: 'peer-local');

      await projectedRepo.addContact(contact);
      expect(await projection.readContacts(), contains(contact.peerId));
      await projectedRepo.blockContact(contact.peerId);
      expect(
        (await projection.readContacts())[contact.peerId]?['blocked'],
        isTrue,
      );
      await projectedRepo.unblockContact(contact.peerId);
      expect(
        (await projection.readContacts())[contact.peerId]?['blocked'],
        isFalse,
      );
      await projectedRepo.archiveContact(contact.peerId);
      expect(
        (await projection.readContacts())[contact.peerId]?['archived'],
        isTrue,
      );
      await projectedRepo.unarchiveContact(contact.peerId);
      expect(
        (await projection.readContacts())[contact.peerId]?['archived'],
        isFalse,
      );

      await projection.removeContact(contact.peerId);
      await projectedRepo.mirrorAllDirectReactionContacts();
      expect(await projection.readContacts(), contains(contact.peerId));

      await projectedRepo.deleteContact(contact.peerId);
      expect(await projection.readContacts(), isNot(contains(contact.peerId)));
    },
  );
}

class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
