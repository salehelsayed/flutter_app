import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';

void main() {
  late ContactRepositoryImpl repo;
  late List<String> archiveCalls;
  late List<String> unarchiveCalls;
  late List<String> blockCalls;
  late List<String> unblockCalls;

  ContactModel _makeContact(String peerId, {bool isArchived = false}) {
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

    final active = [_makeContact('peer-A'), _makeContact('peer-B')];
    final archived = [_makeContact('peer-C', isArchived: true)];
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
      dbLoadActiveContacts: () async =>
          active.map((c) => c.toMap()).toList(),
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
}
