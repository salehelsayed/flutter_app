import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------
class _FakeContactRepository implements ContactRepository {
  bool existsResult = false;
  bool throwOnExists = false;
  bool throwOnAdd = false;
  ContactModel? lastAdded;

  @override
  Future<bool> contactExists(String peerId) async {
    if (throwOnExists) throw Exception('db error on exists');
    return existsResult;
  }

  @override
  Future<void> addContact(ContactModel contact) async {
    if (throwOnAdd) throw Exception('db error on add');
    lastAdded = contact;
  }

  // Not needed for this test file
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> deleteContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getActiveContacts() async => [];
  @override
  Future<List<ContactModel>> getAllContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<ContactModel?> getContact(String peerId) async => null;
  @override
  Future<int> getContactCount() async => 0;
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------
ContactModel _makeContact({String peerId = '12D3KooWTestPeerId123456'}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk_base64',
    rendezvous: '/dns4/example.com/tcp/4001/p2p/12D3KooW...',
    username: 'Alice',
    signature: 'sig_base64',
    scannedAt: '2024-01-01T00:00:00Z',
  );
}

void main() {
  late _FakeContactRepository repo;

  setUp(() {
    flowEventLoggingEnabled = false;
    repo = _FakeContactRepository();
  });

  group('addContact', () {
    test('success: returns success when contact does not exist', () async {
      repo.existsResult = false;

      final result = await addContact(
        repository: repo,
        contact: _makeContact(),
      );

      expect(result, equals(AddContactResult.success));
    });

    test('alreadyExists: returns alreadyExists when contact exists', () async {
      repo.existsResult = true;

      final result = await addContact(
        repository: repo,
        contact: _makeContact(),
      );

      expect(result, equals(AddContactResult.alreadyExists));
    });

    test('dbError: returns dbError when contactExists throws', () async {
      repo.throwOnExists = true;

      final result = await addContact(
        repository: repo,
        contact: _makeContact(),
      );

      expect(result, equals(AddContactResult.dbError));
    });

    test('dbError: returns dbError when addContact throws', () async {
      repo.existsResult = false;
      repo.throwOnAdd = true;

      final result = await addContact(
        repository: repo,
        contact: _makeContact(),
      );

      expect(result, equals(AddContactResult.dbError));
    });

    test('calls addContact on repository with correct model', () async {
      repo.existsResult = false;
      final contact = _makeContact(peerId: '12D3KooWSpecificPeerId1234');

      await addContact(repository: repo, contact: contact);

      expect(repo.lastAdded, isNotNull);
      expect(repo.lastAdded!.peerId, equals('12D3KooWSpecificPeerId1234'));
      expect(repo.lastAdded!.username, equals('Alice'));
    });
  });
}
