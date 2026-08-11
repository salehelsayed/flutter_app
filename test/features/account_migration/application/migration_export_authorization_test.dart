import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/account_migration/application/migration_pairing_session_repository_impl.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('migration export authorization', () {
    late FakeSecureKeyStore secureKeyStore;
    late SecureKeyStoreMigrationPairingSessionRepository repository;
    final now = DateTime.utc(2026, 1, 1, 12);

    MigrationQrPayload payload({
      String sessionId = 'mig-session-1',
      String publicKey = 'new-phone-mlkem-public',
    }) {
      return MigrationQrPayload(
        sessionId: sessionId,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
        newPhoneEphemeralPublicKey: publicKey,
      );
    }

    setUp(() {
      secureKeyStore = FakeSecureKeyStore();
      repository = SecureKeyStoreMigrationPairingSessionRepository(
        secureKeyStore: secureKeyStore,
      );
    });

    test(
      'authorization is issued only for consumed session and exact key',
      () async {
        final (result, authorization) = await authorizeMigrationExport(
          repository: repository,
          payload: payload(),
          authorizedAt: now,
        );

        expect(result, MigrationExportAuthorizationResult.authorized);
        expect(authorization, isNotNull);
        expect(await repository.isSessionConsumed('mig-session-1'), true);
        expect(
          authorization!.authorizes(
            sessionId: 'mig-session-1',
            newPhoneEphemeralPublicKey: 'new-phone-mlkem-public',
          ),
          true,
        );
      },
    );

    test('mismatched session ID or public key is rejected', () async {
      final (_, authorization) = await authorizeMigrationExport(
        repository: repository,
        payload: payload(),
        authorizedAt: now,
      );

      expect(
        authorization!.authorizes(
          sessionId: 'other-session',
          newPhoneEphemeralPublicKey: 'new-phone-mlkem-public',
        ),
        false,
      );
      expect(
        authorization.authorizes(
          sessionId: 'mig-session-1',
          newPhoneEphemeralPublicKey: 'different-public-key',
        ),
        false,
      );
    });

    test('reused consumed session cannot authorize export again', () async {
      await authorizeMigrationExport(
        repository: repository,
        payload: payload(),
        authorizedAt: now,
      );

      final (result, authorization) = await authorizeMigrationExport(
        repository: repository,
        payload: payload(),
        authorizedAt: now,
      );

      expect(result, MigrationExportAuthorizationResult.alreadyConsumed);
      expect(authorization, isNull);
    });

    test(
      'confirmation code requires authenticated channel transcript material',
      () {
        expect(
          () => AuthenticatedMigrationChannelTranscript(
            sessionId: 'mig-session-1',
            newPhoneEphemeralPublicKey: 'new-phone-mlkem-public',
            oldPhonePeerId: 'old-phone-peer',
            authenticatedChannelBinding: '',
            authorizationNonce: 'old-phone-authorization',
          ),
          throwsArgumentError,
        );

        final first = deriveMigrationConfirmationCode(
          AuthenticatedMigrationChannelTranscript(
            sessionId: 'mig-session-1',
            newPhoneEphemeralPublicKey: 'new-phone-mlkem-public',
            oldPhonePeerId: 'old-phone-peer',
            authenticatedChannelBinding: 'authenticated-channel-binding-a',
            authorizationNonce: 'old-phone-authorization',
          ),
        );
        final second = deriveMigrationConfirmationCode(
          AuthenticatedMigrationChannelTranscript(
            sessionId: 'mig-session-1',
            newPhoneEphemeralPublicKey: 'new-phone-mlkem-public',
            oldPhonePeerId: 'old-phone-peer',
            authenticatedChannelBinding: 'authenticated-channel-binding-b',
            authorizationNonce: 'old-phone-authorization',
          ),
        );

        expect(first, matches(RegExp(r'^\d{6}$')));
        expect(second, matches(RegExp(r'^\d{6}$')));
        expect(second, isNot(first));
      },
    );

    test('TC-360-01b v112 remote roster migrates while linked installation '
        'authority cannot move', () async {
      // A linked secondary does not own the account: its identity is a
      // restricted transport credential bound to a logical account whose
      // primary lives elsewhere. Exporting from here would hand a
      // destination an account this device was never the authority for,
      // while the real primary keeps running.
      final linkedStore = FakeSecureKeyStore();
      await linkedStore.write(
        canonicalRuntimeInstallationIdStorageKey,
        'installation-1',
      );
      final linkedAuthority = LinkedInstallationAuthority(
        secureKeyStore: linkedStore,
      );
      await linkedAuthority.markExpectedLinkedRole();

      final (result, authorization) = await authorizeMigrationExport(
        repository: repository,
        payload: payload(sessionId: 'linked-source-session'),
        authorizedAt: now,
        linkedInstallationAuthority: linkedAuthority,
      );
      expect(
        result,
        MigrationExportAuthorizationResult.linkedSecondaryInstallation,
      );
      expect(authorization, isNull);
      expect(
        await repository.isSessionConsumed('linked-source-session'),
        false,
        reason:
            'a refused source must not burn the pairing session; the user '
            'has to be able to retry from the real primary',
      );

      // An ordinary primary source is unaffected.
      final primaryAuthority = LinkedInstallationAuthority(
        secureKeyStore: FakeSecureKeyStore(),
      );
      final (
        primaryResult,
        primaryAuthorization,
      ) = await authorizeMigrationExport(
        repository: repository,
        payload: payload(sessionId: 'primary-source-session'),
        authorizedAt: now,
        linkedInstallationAuthority: primaryAuthority,
      );
      expect(primaryResult, MigrationExportAuthorizationResult.authorized);
      expect(primaryAuthorization, isNotNull);
    });
  });
}
