import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/debug/ios_sender_projection_fixture_contract.dart';
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

  test(
    'SIMS seed survives launch mirror and same-name ingest then cleans exactly',
    () async {
      final rows = <String, Map<String, Object?>>{};
      final projection = DirectReactionNotificationProjection(
        store: _MemorySecureKeyStore(),
      );
      final cleanupMutationOrder = <String>[];
      var replayStaleMirrorAfterProjectionDelete = false;
      await projection.replaceLocalIdentity(accountPeerId: 'peer-local');
      final projectedRepo = ContactRepositoryImpl(
        dbLoadAllContacts: () async => rows.values.toList(),
        dbLoadContact: (peerId) async => rows[peerId],
        dbUpsertContact: (row) async =>
            rows[row['peer_id'] as String] = Map<String, Object?>.from(row),
        dbDeleteContact: (peerId) async => rows.remove(peerId),
        dbGetContactCount: () async => rows.length,
        dbContactExists: (peerId) async => rows.containsKey(peerId),
        dbArchiveContact: (_) async {},
        dbUnarchiveContact: (_) async {},
        dbLoadActiveContacts: () async => rows.values.toList(),
        dbLoadArchivedContacts: () async => const <Map<String, Object?>>[],
        dbBlockContact: (_) async {},
        dbUnblockContact: (_) async {},
        dbDismissIntroBanner: (_) async {},
        dbSetIntrosSentAt: (_, _) async {},
        directReactionProjection: projection,
      );
      final store = IosSenderProjectionFixtureStore(
        loadLocalAccountPeerId: () async => 'peer-local',
        loadProjectionAccountPeerId: projection.readLocalAccountPeerId,
        loadContact: projectedRepo.getContact,
        insertContactIfAbsent: (contact) async {
          if (rows.containsKey(contact.peerId)) return false;
          rows[contact.peerId] = contact.toMap();
          return true;
        },
        deleteContactIfExact: (contact) async {
          cleanupMutationOrder.add('db');
          final current = rows[contact.peerId];
          if (current == null || !_sameMap(current, contact.toMap())) {
            return false;
          }
          rows.remove(contact.peerId);
          return true;
        },
        loadProjectedContact: (peerId) async =>
            (await projection.readContacts())[peerId],
        insertProjectedContactIfAbsent: (request) =>
            projection.insertSimsFixtureContactIfAbsent(
              peerId: request.senderPeerId,
              username: request.senderUsername,
              fixtureDigest: request.fixtureDigest,
            ),
        deleteProjectedContactIfExact: (request) async {
          cleanupMutationOrder.add('projection');
          final removed = await projection.removeSimsFixtureContactIfExact(
            peerId: request.senderPeerId,
            username: request.senderUsername,
            fixtureDigest: request.fixtureDigest,
          );
          if (removed && replayStaleMirrorAfterProjectionDelete) {
            replayStaleMirrorAfterProjectionDelete = false;
            await projection.replaceContacts(<ContactModel>[
              request.fixtureContact,
            ]);
          }
          return removed;
        },
      );
      final coordinator = IosSenderProjectionFixtureCoordinator(store);
      final now = DateTime.utc(2030, 3, 17, 12);
      final seed = _simsRequest(
        action: iosSenderProjectionSeedAction,
        now: now,
      );
      final cleanup = _simsRequest(
        action: iosSenderProjectionCleanupAction,
        now: now.add(const Duration(seconds: 1)),
      );

      final seeded = await coordinator.execute(seed);
      expect(seeded.status, 'seeded');
      expect(seeded.resultCode, 'ok');
      await projectedRepo.mirrorAllDirectReactionContacts();
      expect(
        (await projection.readContacts())[seed
            .senderPeerId]?[iosSenderProjectionDigestField],
        seed.fixtureDigest,
      );

      // This is the production ingest branch: an equal decrypted username is
      // a no-op and must leave the fixture signature/generation intact.
      final beforeIngest = await projectedRepo.getContact(seed.senderPeerId);
      expect(beforeIngest?.username, seed.senderUsername);
      if (beforeIngest!.username != seed.senderUsername) {
        await projectedRepo.addContact(
          beforeIngest.copyWith(username: seed.senderUsername),
        );
      }
      expect(
        (await projectedRepo.getContact(seed.senderPeerId))?.signature,
        'mknoon-sims-ios:${seed.fixtureDigest}',
      );

      cleanupMutationOrder.clear();
      replayStaleMirrorAfterProjectionDelete = true;
      final cleaned = await coordinator.execute(cleanup);
      expect(cleaned.status, 'cleaned');
      expect(cleaned.resultCode, 'ok');
      expect(cleanupMutationOrder, <String>['db', 'projection']);
      expect(rows, isNot(contains(seed.senderPeerId)));
      expect(
        await projection.readContacts(),
        isNot(contains(seed.senderPeerId)),
      );

      final reseeded = await coordinator.execute(seed);
      expect(reseeded.status, 'seeded');
      final concurrentRealContact = ContactModel(
        peerId: seed.senderPeerId,
        publicKey: 'real-public-key',
        rendezvous: '/dns4/real.example/tcp/443',
        username: seed.senderUsername,
        signature: 'real-signature',
        scannedAt: '2030-03-17T13:00:00.000Z',
      );
      rows[seed.senderPeerId] = concurrentRealContact.toMap();
      await projection.upsertContact(concurrentRealContact);

      // A concurrent real/contact-like replacement at the same peer is neither
      // blessed by backfill nor removable by the disposable generation.
      await projectedRepo.mirrorAllDirectReactionContacts();
      expect(
        (await projection.readContacts())[seed.senderPeerId]?.containsKey(
          iosSenderProjectionDigestField,
        ),
        isFalse,
      );
      final collision = await coordinator.execute(seed);
      expect(collision.status, 'rejected');
      expect(collision.resultCode, 'sender_state_collision');
      final refused = await coordinator.execute(cleanup);
      expect(refused.status, 'rejected');
      expect(refused.resultCode, 'cleanup_state_mismatch');
      expect(rows, contains(seed.senderPeerId));
    },
  );
}

IosSenderProjectionRequest _simsRequest({
  required String action,
  required DateTime now,
}) => IosSenderProjectionRequest.tryParse(<String, Object?>{
  'schema': iosSenderProjectionRequestSchema,
  'action': action,
  'captureNonce': 'nonce-contact-backfill-1234',
  'receiverDeviceId': '00008110-001A123E0E91801E',
  'bundleId': iosSenderProjectionBundleId,
  'senderPeerId': '12D3KooW${'3' * 44}',
  'senderUsername': 'Encrypted fixture title',
  'apnsPayloadSha256': 'c' * 64,
  'createdAt': now.toIso8601String(),
  'expiresAt': now.add(const Duration(minutes: 2)).toIso8601String(),
}, now: now)!;

bool _sameMap(Map<String, Object?> left, Map<String, Object?> right) =>
    left.length == right.length &&
    right.entries.every((entry) => left[entry.key] == entry.value);

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
