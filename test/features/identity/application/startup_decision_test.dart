import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/application/startup_decision.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------
class _FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identityResult;

  @override
  Future<IdentityModel?> loadIdentity() async => identityResult;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

class _FakeContactRepository implements ContactRepository {
  int contactCountResult = 0;

  @override
  Future<int> getContactCount() async => contactCountResult;

  // Not needed for this test file
  @override
  Future<void> addContact(ContactModel contact) async {}
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<bool> contactExists(String peerId) async => false;
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
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
IdentityModel _makeIdentity() {
  return IdentityModel(
    peerId: '12D3KooWTestPeerId',
    publicKey: 'pk_base64',
    privateKey: 'sk_base64',
    mnemonic12: 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  );
}

void main() {
  late _FakeIdentityRepository identityRepo;
  late _FakeContactRepository contactRepo;

  setUp(() {
    flowEventLoggingEnabled = false;
    identityRepo = _FakeIdentityRepository();
    contactRepo = _FakeContactRepository();
  });

  group('decideStartupRoute', () {
    test('needsIdentity: returns needsIdentity when identity is null', () async {
      identityRepo.identityResult = null;

      final result = await decideStartupRoute(
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );

      expect(result, equals(StartupDecision.needsIdentity));
    });

    test('hasIdentityNoContacts: returns hasIdentityNoContacts when contactCount == 0',
        () async {
      identityRepo.identityResult = _makeIdentity();
      contactRepo.contactCountResult = 0;

      final result = await decideStartupRoute(
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );

      expect(result, equals(StartupDecision.hasIdentityNoContacts));
    });

    test('hasIdentityWithContacts: returns hasIdentityWithContacts when contactCount > 0',
        () async {
      identityRepo.identityResult = _makeIdentity();
      contactRepo.contactCountResult = 5;

      final result = await decideStartupRoute(
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );

      expect(result, equals(StartupDecision.hasIdentityWithContacts));
    });

    test('hasIdentityWithContacts: works with contactCount of 1', () async {
      identityRepo.identityResult = _makeIdentity();
      contactRepo.contactCountResult = 1;

      final result = await decideStartupRoute(
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );

      expect(result, equals(StartupDecision.hasIdentityWithContacts));
    });

    test('hasIdentityWithContacts: works with large contactCount', () async {
      identityRepo.identityResult = _makeIdentity();
      contactRepo.contactCountResult = 10000;

      final result = await decideStartupRoute(
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );

      expect(result, equals(StartupDecision.hasIdentityWithContacts));
    });
  });
}
