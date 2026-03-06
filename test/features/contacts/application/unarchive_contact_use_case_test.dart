import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contacts/application/unarchive_contact_use_case.dart';

class FakeContactRepository implements ContactRepository {
  final List<String> unarchivedPeerIds = [];
  bool shouldThrow = false;

  @override
  Future<void> unarchiveContact(String peerId) async {
    if (shouldThrow) throw Exception('DB error');
    unarchivedPeerIds.add(peerId);
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
  Future<List<ContactModel>> getActiveContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

void main() {
  group('unarchiveContact use case', () {
    test('calls repo.unarchiveContact with peerId', () async {
      final repo = FakeContactRepository();
      await unarchiveContact(
        contactRepo: repo,
        peerId: 'peer-1234567890',
      );
      expect(repo.unarchivedPeerIds, ['peer-1234567890']);
    });

    test('rethrows errors from repository', () async {
      final repo = FakeContactRepository()..shouldThrow = true;
      expect(
        () => unarchiveContact(
          contactRepo: repo,
          peerId: 'peer-1234567890',
        ),
        throwsException,
      );
    });
  });
}
