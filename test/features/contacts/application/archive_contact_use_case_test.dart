import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contacts/application/archive_contact_use_case.dart';

class FakeContactRepository implements ContactRepository {
  final List<String> archivedPeerIds = [];
  bool shouldThrow = false;

  @override
  Future<void> archiveContact(String peerId) async {
    if (shouldThrow) throw Exception('DB error');
    archivedPeerIds.add(peerId);
  }

  @override
  Future<void> addContact(ContactModel contact) async {}
  @override
  Future<bool> contactExists(String peerId) async => false;
  @override
  Future<void> deleteContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getAllContacts() async => [];
  @override
  Future<ContactModel?> getContact(String peerId) async => null;
  @override
  Future<int> getContactCount() async => 0;
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getActiveContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
}

void main() {
  group('archiveContact use case', () {
    test('calls repo.archiveContact with peerId', () async {
      final repo = FakeContactRepository();
      await archiveContact(
        contactRepo: repo,
        peerId: 'peer-1234567890',
      );
      expect(repo.archivedPeerIds, ['peer-1234567890']);
    });

    test('rethrows errors from repository', () async {
      final repo = FakeContactRepository()..shouldThrow = true;
      expect(
        () => archiveContact(
          contactRepo: repo,
          peerId: 'peer-1234567890',
        ),
        throwsException,
      );
    });
  });
}
