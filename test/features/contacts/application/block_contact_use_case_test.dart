import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contacts/application/block_contact_use_case.dart';

class FakeContactRepository implements ContactRepository {
  final List<String> blockedPeerIds = [];
  bool shouldThrow = false;

  @override
  Future<void> blockContact(String peerId) async {
    if (shouldThrow) throw Exception('DB error');
    blockedPeerIds.add(peerId);
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
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getActiveContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
}

void main() {
  group('blockContact use case', () {
    test('calls repo.blockContact with peerId', () async {
      final repo = FakeContactRepository();
      await blockContact(
        contactRepo: repo,
        peerId: 'peer-1234567890',
      );
      expect(repo.blockedPeerIds, ['peer-1234567890']);
    });

    test('rethrows errors from repository', () async {
      final repo = FakeContactRepository()..shouldThrow = true;
      expect(
        () => blockContact(
          contactRepo: repo,
          peerId: 'peer-1234567890',
        ),
        throwsException,
      );
    });
  });
}
