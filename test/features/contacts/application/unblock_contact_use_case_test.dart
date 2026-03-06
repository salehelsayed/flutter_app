import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contacts/application/unblock_contact_use_case.dart';

class FakeContactRepository implements ContactRepository {
  final List<String> unblockedPeerIds = [];
  bool shouldThrow = false;

  @override
  Future<void> unblockContact(String peerId) async {
    if (shouldThrow) throw Exception('DB error');
    unblockedPeerIds.add(peerId);
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
  Future<void> blockContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getActiveContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

void main() {
  group('unblockContact use case', () {
    test('calls repo.unblockContact with peerId', () async {
      final repo = FakeContactRepository();
      await unblockContact(
        contactRepo: repo,
        peerId: 'peer-1234567890',
      );
      expect(repo.unblockedPeerIds, ['peer-1234567890']);
    });

    test('rethrows errors from repository', () async {
      final repo = FakeContactRepository()..shouldThrow = true;
      expect(
        () => unblockContact(
          contactRepo: repo,
          peerId: 'peer-1234567890',
        ),
        throwsException,
      );
    });
  });
}
