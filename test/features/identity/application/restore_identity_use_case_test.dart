import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_cleanup.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/application/linked_secondary_setup_use_case.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/test_user.dart';

class _FakeIdentityRepo implements IdentityRepository {
  IdentityModel? savedIdentity;
  bool shouldThrowOnSave = false;

  @override
  Future<IdentityModel?> loadIdentity() async => savedIdentity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    if (shouldThrowOnSave) throw Exception('DB write failed');
    savedIdentity = identity;
  }
}

const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

final _fakeIdentityResponse = {
  'ok': true,
  'identity': {
    'peerId': '12D3KooWTestRestore',
    'publicKey': 'publicKeyBase64',
    'privateKey': 'privateKeyBase64',
    'mnemonic12': _validMnemonic,
    'createdAt': '2024-01-01T00:00:00Z',
    'updatedAt': '2024-01-01T00:00:00Z',
  },
};

const _fakeMlKemResponse = {
  'ok': true,
  'publicKey': 'mlkemPub',
  'secretKey': 'mlkemSec',
};

void main() {
  late _FakeIdentityRepo repo;
  late List<String> progressStages;
  late String? lastRestoredMnemonic;

  setUp(() {
    repo = _FakeIdentityRepo();
    progressStages = [];
    lastRestoredMnemonic = null;
  });

  Future<Map<String, dynamic>> fakeRestore(String mnemonic) async {
    lastRestoredMnemonic = mnemonic;
    return _fakeIdentityResponse;
  }

  test('success: restores identity with normalized mnemonic', () async {
    final result = await restoreIdentityFromMnemonic(
      input:
          '  Abandon  ABANDON   abandon abandon abandon abandon abandon abandon abandon abandon abandon about  ',
      callRestore: fakeRestore,
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
      onProgress: (s) => progressStages.add(s),
    );

    expect(result, equals(RestoreIdentityResult.success));
    expect(repo.savedIdentity, isNotNull);
    expect(repo.savedIdentity!.peerId, equals('12D3KooWTestRestore'));
    expect(repo.savedIdentity!.mlKemPublicKey, equals('mlkemPub'));
    // Verify normalization: lowercase, trimmed, single spaces
    expect(lastRestoredMnemonic, equals(_validMnemonic));
    expect(progressStages, contains('generating_keys'));
    expect(progressStages, contains('saving'));
  });

  test('invalidMnemonicFormat: too few words', () async {
    final result = await restoreIdentityFromMnemonic(
      input: 'only three words',
      callRestore: fakeRestore,
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.invalidMnemonicFormat));
    expect(repo.savedIdentity, isNull);
  });

  test('invalidMnemonicFormat: too many words', () async {
    final result = await restoreIdentityFromMnemonic(
      input: 'a b c d e f g h i j k l m',
      callRestore: fakeRestore,
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.invalidMnemonicFormat));
  });

  test('invalidMnemonicCore: bridge returns INVALID_MNEMONIC', () async {
    final result = await restoreIdentityFromMnemonic(
      input: _validMnemonic,
      callRestore: (_) async => {
        'ok': false,
        'errorCode': 'INVALID_MNEMONIC',
        'errorMessage': 'Not a valid BIP39 mnemonic',
      },
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.invalidMnemonicCore));
  });

  test('coreLibError: bridge returns other error', () async {
    final result = await restoreIdentityFromMnemonic(
      input: _validMnemonic,
      callRestore: (_) async => {
        'ok': false,
        'errorCode': 'INTERNAL_ERROR',
        'errorMessage': 'Something went wrong',
      },
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.coreLibError));
  });

  test('coreLibError: bridge throws exception', () async {
    final result = await restoreIdentityFromMnemonic(
      input: _validMnemonic,
      callRestore: (_) async => throw Exception('Bridge crashed'),
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.coreLibError));
  });

  test('coreLibError: ML-KEM keygen fails', () async {
    final result = await restoreIdentityFromMnemonic(
      input: _validMnemonic,
      callRestore: fakeRestore,
      callMlKemKeygen: () async => {'ok': false, 'errorCode': 'MLKEM_FAIL'},
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.coreLibError));
  });

  test('dbError: repo.saveIdentity throws', () async {
    repo.shouldThrowOnSave = true;

    final result = await restoreIdentityFromMnemonic(
      input: _validMnemonic,
      callRestore: fakeRestore,
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.dbError));
  });

  test(
    'success: restored identity can receive queued messages after device recovery',
    () async {
      final result = await restoreIdentityFromMnemonic(
        input: _validMnemonic,
        callRestore: fakeRestore,
        callMlKemKeygen: () async => _fakeMlKemResponse,
        repo: repo,
      );

      expect(result, RestoreIdentityResult.success);
      final restoredIdentity = repo.savedIdentity;
      expect(restoredIdentity, isNotNull);

      final network = FakeP2PNetwork();
      final alice = TestUser.create(
        peerId: 'alice-restore-sender',
        username: 'Alice',
        network: network,
      );
      final restoredUser = TestUser.create(
        peerId: restoredIdentity!.peerId,
        username: 'Recovered',
        network: network,
      );

      alice.addContact(restoredUser);
      restoredUser.addContact(alice);

      alice.start();
      restoredUser.start();
      restoredUser.p2pService.setOnline(false);

      try {
        final (sendResult, _) = await alice.sendMessage(
          restoredUser.peerId,
          'Welcome back after restore',
        );
        expect(sendResult, SendChatMessageResult.success);

        restoredUser.p2pService.setOnline(true);
        final drained = await restoredUser.drainOfflineInbox();
        expect(drained, 1);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        final restoredConversation = await restoredUser.loadConversationWith(
          alice.peerId,
        );
        expect(restoredConversation, hasLength(1));
        expect(restoredConversation.single.isIncoming, isTrue);
        expect(restoredConversation.single.text, 'Welcome back after restore');
        expect(restoredConversation.single.senderPeerId, alice.peerId);
      } finally {
        alice.dispose();
        restoredUser.dispose();
      }
    },
  );

  group('TC-360-01a crash-safe linked-secondary setup ordering', () {
    // Real Go-derived pairs so the authority's own peer-derivation guard is
    // exercised rather than bypassed.
    const accountPublicKey = 'xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo=';
    const accountPeerId =
        '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj';
    const transportPublicKey = 'xvKsVZiXDHljNxTT61w017/D6S2ljHNUs3mW2aSvOrI=';
    const transportPeerId =
        '12D3KooWPCyWnZCXR3VGdrQjLr5d8TBaAHD956XZvo6xoCXYB5AR';
    const secondTransportPublicKey =
        '8MoQw54eBrJfQtZUoNSQt5eZ9LeEseHxRKYv2zhyy58=';
    const secondTransportPeerId =
        '12D3KooWS2Jiwq8amLufp2meksG2jhWkZzhvAmetUsPdWv5xk7ZY';

    late FakeSecureKeyStore secureKeyStore;
    late LinkedInstallationAuthority authority;
    late List<String> writeOrder;

    Map<String, dynamic> accountRestoreResponse() => <String, dynamic>{
      'ok': true,
      'identity': <String, dynamic>{
        'peerId': accountPeerId,
        'publicKey': accountPublicKey,
        'privateKey': 'account-private-key',
        'mnemonic12': _validMnemonic,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
      },
    };

    Map<String, dynamic> transportIdentityResponse({
      String peerId = transportPeerId,
      String publicKey = transportPublicKey,
    }) => <String, dynamic>{
      'ok': true,
      'identity': <String, dynamic>{
        'peerId': peerId,
        'publicKey': publicKey,
        'privateKey': 'transport-private-key-$peerId',
        'mnemonic12': _validMnemonic,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
      },
    };

    Future<Map<String, dynamic>> fakeSign(
      String data,
      String privateKey,
    ) async => <String, dynamic>{
      'ok': true,
      'signature': 'sig:$privateKey:$data',
    };

    Future<bool> fakeVerify({
      required String publicKey,
      required String data,
      required String signature,
    }) async => signature.startsWith('sig:');

    setUp(() async {
      writeOrder = <String>[];
      secureKeyStore = _RecordingSecureKeyStore(writeOrder);
      await secureKeyStore.write(
        canonicalRuntimeInstallationIdStorageKey,
        'installation-1',
      );
      writeOrder.clear();
      authority = LinkedInstallationAuthority(secureKeyStore: secureKeyStore);
    });

    test('TC-360-01a linked-secondary transport identity is distinct stable '
        'and fail-closed', () async {
      final repo = _FakeIdentityRepo();

      // ── Selector OFF creates nothing at all. ──
      expect(
        await setUpLinkedSecondaryInstallation(
          mnemonic: _validMnemonic,
          authority: authority,
          identityRepo: repo,
          callRestore: (_) async => accountRestoreResponse(),
          callMlKemKeygen: () async =>
              Map<String, dynamic>.from(_fakeMlKemResponse),
          callIdentityGenerate: () async => transportIdentityResponse(),
          callSign: fakeSign,
          callVerify: fakeVerify,
          selector: const DirectLinkedDeviceSelector.disabled(),
        ),
        LinkedSecondarySetupResult.selectorDisabled,
      );
      expect(writeOrder, isEmpty);
      expect(repo.savedIdentity, isNull);
      expect(
        (await authority.load()).disposition,
        LinkedInstallationDisposition.primary,
        reason: 'an installation that never began setup stays primary',
      );

      // ── Full setup writes in the exact required order. ──
      expect(
        await setUpLinkedSecondaryInstallation(
          mnemonic: _validMnemonic,
          authority: authority,
          identityRepo: repo,
          callRestore: (_) async => accountRestoreResponse(),
          callMlKemKeygen: () async =>
              Map<String, dynamic>.from(_fakeMlKemResponse),
          callIdentityGenerate: () async => transportIdentityResponse(),
          callSign: fakeSign,
          callVerify: fakeVerify,
          selector: const DirectLinkedDeviceSelector.enabled(),
        ),
        LinkedSecondarySetupResult.success,
      );
      expect(
        writeOrder,
        <String>[
          linkedInstallationRoleStorageKey,
          linkedInstallationTransportCredentialStorageKey,
          linkedInstallationTransportCredentialStorageKey,
        ],
        reason:
            'marker FIRST, then exactly one credential (preparing), then the '
            'same credential activated LAST',
      );
      expect(repo.savedIdentity!.peerId, accountPeerId);
      expect(
        repo.savedIdentity!.mlKemPublicKey,
        _fakeMlKemResponse['publicKey'],
        reason: 'the installation-local ML-KEM is re-minted, not inherited',
      );

      final active = await authority.load(expectedAccountPeerId: accountPeerId);
      expect(active.isActiveLinkedSecondary, isTrue);
      expect(active.credential!.transportPeerId, transportPeerId);
      expect(active.credential!.accountPeerId, accountPeerId);
      expect(
        active.credential!.transportPeerId,
        isNot(active.credential!.accountPeerId),
      );
      expect(active.credential!.deviceId, 'installation-1');

      // Raw secret material never leaves secure storage.
      expect(
        repo.savedIdentity!.privateKey,
        isNot(contains(active.credential!.transportPrivateKey)),
      );

      // ── Crash after step 1 (marker only): refuses startup, and setup may
      // still mint its FIRST credential. ──
      final markerOnlyStore = FakeSecureKeyStore();
      await markerOnlyStore.write(
        canonicalRuntimeInstallationIdStorageKey,
        'installation-1',
      );
      final markerOnlyAuthority = LinkedInstallationAuthority(
        secureKeyStore: markerOnlyStore,
      );
      await markerOnlyAuthority.markExpectedLinkedRole();
      final markerOnly = await markerOnlyAuthority.load();
      expect(
        markerOnly.disposition,
        LinkedInstallationDisposition.awaitingCredential,
      );
      expect(markerOnly.refusesStartup, isTrue);
      expect(markerOnly.isOrdinaryPrimary, isFalse);

      // ── Crash after step 2 (preparing): refuses startup, and RESUME
      // re-adopts the SAME bytes. Minting a second identity here would
      // strand any QR already handed out. ──
      final (firstResult, firstCredential) = await markerOnlyAuthority
          .createOrResumeTransportCredential(
            accountPeerId: accountPeerId,
            accountPublicKey: accountPublicKey,
            callIdentityGenerate: () async => transportIdentityResponse(),
            callSign: fakeSign,
            callVerify: fakeVerify,
          );
      expect(firstResult, LinkedInstallationSetupResult.success);
      final preparing = await markerOnlyAuthority.load();
      expect(preparing.disposition, LinkedInstallationDisposition.preparing);
      expect(preparing.refusesStartup, isTrue);

      final (resumeResult, resumedCredential) = await markerOnlyAuthority
          .createOrResumeTransportCredential(
            accountPeerId: accountPeerId,
            accountPublicKey: accountPublicKey,
            // A generator that would mint a DIFFERENT identity. Resume must
            // never reach it.
            callIdentityGenerate: () async => transportIdentityResponse(
              peerId: secondTransportPeerId,
              publicKey: secondTransportPublicKey,
            ),
            callSign: fakeSign,
            callVerify: fakeVerify,
          );
      expect(resumeResult, LinkedInstallationSetupResult.success);
      expect(
        resumedCredential!.transportPeerId,
        firstCredential!.transportPeerId,
      );
      expect(
        resumedCredential.transportPrivateKey,
        firstCredential.transportPrivateKey,
      );

      // ── Credential without a marker is FAIL-CLOSED, never adopted. ──
      final orphanStore = FakeSecureKeyStore();
      await orphanStore.write(
        canonicalRuntimeInstallationIdStorageKey,
        'installation-1',
      );
      await orphanStore.write(
        linkedInstallationTransportCredentialStorageKey,
        await secureKeyStore.read(
              linkedInstallationTransportCredentialStorageKey,
            ) ??
            '',
      );
      final orphan = await LinkedInstallationAuthority(
        secureKeyStore: orphanStore,
      ).load();
      expect(orphan.disposition, LinkedInstallationDisposition.failClosed);
      expect(orphan.failClosedReason, 'credential_without_role_marker');

      // ── Corrupt envelope is FAIL-CLOSED, never regenerated. ──
      final corruptStore = FakeSecureKeyStore();
      await corruptStore.write(
        canonicalRuntimeInstallationIdStorageKey,
        'installation-1',
      );
      await corruptStore.write(
        linkedInstallationRoleStorageKey,
        linkedInstallationRoleMarkerValue,
      );
      await corruptStore.write(
        linkedInstallationTransportCredentialStorageKey,
        '{not json',
      );
      expect(
        (await LinkedInstallationAuthority(
          secureKeyStore: corruptStore,
        ).load()).failClosedReason,
        'corrupt_credential',
      );

      // ── Cross-account credential is FAIL-CLOSED. ──
      expect(
        (await authority.load(
          expectedAccountPeerId: 'someone-elses-account',
        )).failClosedReason,
        'cross_account_credential',
      );

      // ── A reset/missing canonical installation ID REFUSES rather than
      // rotating transport identity: rotating would orphan every binding a
      // contact already verified. ──
      await secureKeyStore.delete(canonicalRuntimeInstallationIdStorageKey);
      expect(
        (await authority.load(
          expectedAccountPeerId: accountPeerId,
        )).failClosedReason,
        'canonical_device_id_mismatch',
      );
      await secureKeyStore.write(
        canonicalRuntimeInstallationIdStorageKey,
        'a-different-installation',
      );
      expect(
        (await authority.load(
          expectedAccountPeerId: accountPeerId,
        )).failClosedReason,
        'canonical_device_id_mismatch',
      );
      await secureKeyStore.write(
        canonicalRuntimeInstallationIdStorageKey,
        'installation-1',
      );

      // ── Setup refuses to re-run over ACTIVE authority. ──
      expect(
        await setUpLinkedSecondaryInstallation(
          mnemonic: _validMnemonic,
          authority: authority,
          identityRepo: repo,
          callRestore: (_) async => accountRestoreResponse(),
          callMlKemKeygen: () async =>
              Map<String, dynamic>.from(_fakeMlKemResponse),
          callIdentityGenerate: () async => transportIdentityResponse(
            peerId: secondTransportPeerId,
            publicKey: secondTransportPublicKey,
          ),
          callSign: fakeSign,
          callVerify: fakeVerify,
          selector: const DirectLinkedDeviceSelector.enabled(),
        ),
        LinkedSecondarySetupResult.refused,
      );
      expect(
        (await authority.load(
          expectedAccountPeerId: accountPeerId,
        )).credential!.transportPeerId,
        transportPeerId,
        reason: 'the active credential is never replaced by a second run',
      );

      // ── Explicit reset clears marker, credential, and installation ID
      // together through the incumbent local-reset authority. ──
      await MigrationSecureStorageCleanup(
        staging: MigrationSecureStorageStaging(
          primaryStore: secureKeyStore,
          sharedStore: secureKeyStore,
        ),
      ).eraseAccount(
        registryKeys: MigrationSecureStorageRegistry.resolve(),
        explicitLocalReset: true,
      );
      expect(
        await secureKeyStore.read(linkedInstallationRoleStorageKey),
        isNull,
      );
      expect(
        await secureKeyStore.read(
          linkedInstallationTransportCredentialStorageKey,
        ),
        isNull,
      );
      expect(
        await secureKeyStore.read(canonicalRuntimeInstallationIdStorageKey),
        isNull,
      );
      expect(
        (await authority.load()).disposition,
        LinkedInstallationDisposition.primary,
      );
    });
  });
}

/// Records the ORDER of secure writes so the crash-safe sequence is provable.
class _RecordingSecureKeyStore extends FakeSecureKeyStore {
  _RecordingSecureKeyStore(this.writeOrder);

  final List<String> writeOrder;

  @override
  Future<void> write(String key, String value) async {
    writeOrder.add(key);
    await super.write(key, value);
  }
}
