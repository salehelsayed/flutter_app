import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';
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
  int getContactCountCallCount = 0;

  @override
  Future<int> getContactCount() async {
    getContactCountCallCount++;
    return contactCountResult;
  }

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

class _FakeAccountMigrationAuthorityRepository
    implements AccountMigrationAuthorityRepository {
  AccountMigrationAuthorityRecord? authority;
  int loadAuthorityCallCount = 0;

  @override
  Future<AccountMigrationAuthorityRecord?> loadAuthority() async {
    loadAuthorityCallCount++;
    return authority;
  }

  @override
  Future<void> saveAuthority(AccountMigrationAuthorityRecord record) async {
    authority = record;
  }

  @override
  Future<void> clearAuthority() async {
    authority = null;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
IdentityModel _makeIdentity() {
  return IdentityModel(
    peerId: '12D3KooWTestPeerId',
    publicKey: 'pk_base64',
    privateKey: 'sk_base64',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  );
}

void main() {
  late _FakeIdentityRepository identityRepo;
  late _FakeContactRepository contactRepo;
  late _FakeAccountMigrationAuthorityRepository authorityRepo;

  setUp(() {
    flowEventLoggingEnabled = false;
    identityRepo = _FakeIdentityRepository();
    contactRepo = _FakeContactRepository();
    authorityRepo = _FakeAccountMigrationAuthorityRepository();
  });

  group('decideStartupRoute', () {
    test(
      'needsIdentity: returns needsIdentity when identity is null',
      () async {
        identityRepo.identityResult = null;

        final result = await decideStartupRoute(
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );

        expect(result, equals(StartupDecision.needsIdentity));
      },
    );

    test(
      'hasIdentityNoContacts: returns hasIdentityNoContacts when contactCount == 0',
      () async {
        identityRepo.identityResult = _makeIdentity();
        contactRepo.contactCountResult = 0;

        final result = await decideStartupRoute(
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );

        expect(result, equals(StartupDecision.hasIdentityNoContacts));
      },
    );

    test(
      'hasIdentityWithContacts: returns hasIdentityWithContacts when contactCount > 0',
      () async {
        identityRepo.identityResult = _makeIdentity();
        contactRepo.contactCountResult = 5;

        final result = await decideStartupRoute(
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );

        expect(result, equals(StartupDecision.hasIdentityWithContacts));
      },
    );

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

    test('missing authority preserves no-identity onboarding route', () async {
      identityRepo.identityResult = null;

      final result = await decideStartupRoute(
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        migrationAuthorityRepository: authorityRepo,
      );

      expect(result, equals(StartupDecision.needsIdentity));
      expect(authorityRepo.loadAuthorityCallCount, 1);
    });

    test(
      'missing authority preserves returning-user route with contacts',
      () async {
        identityRepo.identityResult = _makeIdentity();
        contactRepo.contactCountResult = 2;

        final result = await decideStartupRoute(
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          migrationAuthorityRepository: authorityRepo,
        );

        expect(result, equals(StartupDecision.hasIdentityWithContacts));
      },
    );

    test(
      'active authority preserves identity-without-contacts startup',
      () async {
        identityRepo.identityResult = _makeIdentity();
        contactRepo.contactCountResult = 0;
        authorityRepo.authority = AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.active,
          accountPeerId: '12D3KooWTestPeerId',
        );

        final result = await decideStartupRoute(
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          migrationAuthorityRepository: authorityRepo,
        );

        expect(result, equals(StartupDecision.hasIdentityNoContacts));
      },
    );

    test(
      'active authority preserves returning-user route with contacts',
      () async {
        identityRepo.identityResult = _makeIdentity();
        contactRepo.contactCountResult = 4;
        authorityRepo.authority = AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.active,
          accountPeerId: '12D3KooWTestPeerId',
        );

        final result = await decideStartupRoute(
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          migrationAuthorityRepository: authorityRepo,
        );

        expect(result, equals(StartupDecision.hasIdentityWithContacts));
      },
    );

    test(
      'non-active migration authority blocks normal startup before contacts',
      () async {
        identityRepo.identityResult = _makeIdentity();

        for (final state in [
          AccountMigrationAuthorityState.migratedOut,
          AccountMigrationAuthorityState.migrationCutoverPendingBlocked,
          AccountMigrationAuthorityState.migrationImportStaging,
          AccountMigrationAuthorityState.migrationFailedCleanupRequired,
        ]) {
          contactRepo.getContactCountCallCount = 0;
          authorityRepo.authority = AccountMigrationAuthorityRecord(
            state: state,
            accountPeerId: '12D3KooWTestPeerId',
          );

          final result = await decideStartupRoute(
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            migrationAuthorityRepository: authorityRepo,
          );

          expect(
            result,
            equals(StartupDecision.accountMigrationBlocked),
            reason: state.wireName,
          );
          expect(
            contactRepo.getContactCountCallCount,
            0,
            reason: state.wireName,
          );
        }
      },
    );

    test(
      'interrupted export pause self-heals to active authority at startup',
      () async {
        // An export pause persisted across a process restart means the app
        // died mid Move Account export; the old phone must come back as the
        // active device, not land on the blocked screen or stay offline.
        identityRepo.identityResult = _makeIdentity();
        contactRepo.contactCountResult = 2;
        authorityRepo.authority = AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.migrationExportingNetworkPaused,
          accountPeerId: '12D3KooWTestPeerId',
        );

        final result = await decideStartupRoute(
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          migrationAuthorityRepository: authorityRepo,
        );

        expect(result, equals(StartupDecision.hasIdentityWithContacts));
        expect(
          authorityRepo.authority?.state,
          AccountMigrationAuthorityState.migrationFailedActiveRestored,
        );
        expect(authorityRepo.authority?.accountPeerId, '12D3KooWTestPeerId');
        expect(
          authorityRepo.authority?.state.allowsNormalStartup,
          isTrue,
        );
      },
    );

    test(
      'export pause self-heal emits recovery event and works without identity',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));

        identityRepo.identityResult = null;
        authorityRepo.authority = AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.migrationExportingNetworkPaused,
          accountPeerId: '12D3KooWTestPeerId',
        );

        final result = await decideStartupRoute(
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          migrationAuthorityRepository: authorityRepo,
        );

        expect(result, equals(StartupDecision.needsIdentity));
        expect(
          authorityRepo.authority?.state,
          AccountMigrationAuthorityState.migrationFailedActiveRestored,
        );
        expect(
          flowEvents.where(
            (event) =>
                event['event'] == 'ID_STARTUP_MIGRATION_EXPORT_PAUSE_RECOVERED',
          ),
          hasLength(1),
        );
      },
    );
  });
}
