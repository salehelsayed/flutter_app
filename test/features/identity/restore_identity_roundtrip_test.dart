import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contact_request/application/mlkem_reannounce_marker.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../core/secure_storage/fake_secure_key_store.dart';
import '../contacts/domain/repositories/fake_contact_repository.dart';

/// 124 Phase 8 — restore_identity gap.
///
/// Pins the REAL, current restore-from-mnemonic contract, with focus on the
/// audit's "post-restore stale ML-KEM" P0 loss class.
///
/// What the production flow actually does (verified against
/// `restoreIdentityFromMnemonic` in
/// lib/features/identity/application/restore_identity_use_case.dart):
///
///   1. The SIGNING identity is reproduced DETERMINISTICALLY from the
///      12-word mnemonic — `callRestore(mnemonic)` returns the same
///      peerId / publicKey / privateKey for the same mnemonic. The restored
///      IdentityModel preserves that mnemonic.
///
///   2. The ML-KEM-768 key is intentionally NOT mnemonic-derived. It is
///      produced by an INDEPENDENT `callMlKemKeygen()` call, so a restored
///      device deliberately holds a FRESH ML-KEM keypair (different from the
///      key the old device had). This is the documented root of the
///      "post-restore stale ML-KEM" loss class.
///
///   3. To close that loss class, a successful restore (when given a
///      SecureKeyStore + ContactRepository) records the one-shot ML-KEM
///      re-announce marker (`kMlKemReannouncePendingKey`) listing every active,
///      non-blocked contact. A later sweep drains that marker to re-announce
///      the NEW ML-KEM key to those contacts, so they stop encrypting to the
///      stale (old-device) key.
///
/// These are GREEN host tests using the existing identity/contact/secure-store
/// fakes. They pin behavior, not a fix; the actual ML-KEM keygen randomness
/// lives in the native GoBridge and is represented here by a fake that mints a
/// distinct key per call (mirroring the real non-deterministic contract).
///
/// LIMITATION: the genuine cryptographic re-derivation of the signing keypair
/// from the mnemonic, and the true randomness of ML-KEM keygen, run inside the
/// native Go bridge and cannot be exercised host-side. A separate device test
/// would be required to prove the bridge actually reproduces the same signing
/// peerId across two physical restores and mints a genuinely random ML-KEM key.
/// Here we faithfully model both contracts via injected bridge fakes.

class _FakeIdentityRepo implements IdentityRepository {
  IdentityModel? savedIdentity;

  @override
  Future<IdentityModel?> loadIdentity() async => savedIdentity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    savedIdentity = identity;
  }
}

const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

/// Faithful model of `identity.restore`: the same mnemonic deterministically
/// reproduces the SAME signing identity (peerId / public / private key).
Future<Map<String, dynamic>> _deterministicRestore(String mnemonic) async {
  // A real bridge derives these from the mnemonic seed; the determinism is the
  // contract we pin. Same input mnemonic -> identical signing material.
  final seed = mnemonic.hashCode.toRadixString(16);
  return {
    'ok': true,
    'identity': {
      'peerId': '12D3KooW_$seed',
      'publicKey': 'pub_$seed',
      'privateKey': 'priv_$seed',
      'mnemonic12': mnemonic,
      'createdAt': '2024-01-01T00:00:00Z',
      'updatedAt': '2024-01-01T00:00:00Z',
    },
  };
}

ContactModel _contact(String peerId, {bool blocked = false}) => ContactModel(
      peerId: peerId,
      publicKey: 'pk_$peerId',
      rendezvous: 'rv_$peerId',
      username: 'u_$peerId',
      signature: 'sig_$peerId',
      scannedAt: '2024-01-01T00:00:00Z',
      mlKemPublicKey: 'oldPeerKey_$peerId',
      isBlocked: blocked,
    );

void main() {
  group('restore identity roundtrip — signing identity is mnemonic-derived',
      () {
    test(
        'restore reproduces the SAME signing identity from the same mnemonic '
        '(deterministic) and preserves the mnemonic', () async {
      final repoA = _FakeIdentityRepo();
      final repoB = _FakeIdentityRepo();

      // ML-KEM keygen counter proves each restore mints a distinct key.
      var keygenCalls = 0;
      Future<Map<String, dynamic>> freshMlKem() async {
        keygenCalls++;
        return {
          'ok': true,
          'publicKey': 'mlkemPub_$keygenCalls',
          'secretKey': 'mlkemSec_$keygenCalls',
        };
      }

      final resultA = await restoreIdentityFromMnemonic(
        input: _validMnemonic,
        callRestore: _deterministicRestore,
        callMlKemKeygen: freshMlKem,
        repo: repoA,
      );
      final resultB = await restoreIdentityFromMnemonic(
        input: _validMnemonic,
        callRestore: _deterministicRestore,
        callMlKemKeygen: freshMlKem,
        repo: repoB,
      );

      expect(resultA, RestoreIdentityResult.success);
      expect(resultB, RestoreIdentityResult.success);

      final a = repoA.savedIdentity!;
      final b = repoB.savedIdentity!;

      // Signing identity is reproduced identically from the same mnemonic.
      expect(a.peerId, b.peerId);
      expect(a.publicKey, b.publicKey);
      expect(a.privateKey, b.privateKey);
      // The mnemonic itself is preserved on the restored identity.
      expect(a.mnemonic12, _validMnemonic);
    });
  });

  group('restore identity roundtrip — ML-KEM is intentionally FRESH', () {
    test(
        'two restores of the SAME mnemonic yield DIFFERENT ML-KEM keys '
        '(ML-KEM is NOT mnemonic-derived — the "stale ML-KEM" root cause)',
        () async {
      final repoA = _FakeIdentityRepo();
      final repoB = _FakeIdentityRepo();

      var keygenCalls = 0;
      Future<Map<String, dynamic>> freshMlKem() async {
        keygenCalls++;
        return {
          'ok': true,
          'publicKey': 'mlkemPub_$keygenCalls',
          'secretKey': 'mlkemSec_$keygenCalls',
        };
      }

      await restoreIdentityFromMnemonic(
        input: _validMnemonic,
        callRestore: _deterministicRestore,
        callMlKemKeygen: freshMlKem,
        repo: repoA,
      );
      await restoreIdentityFromMnemonic(
        input: _validMnemonic,
        callRestore: _deterministicRestore,
        callMlKemKeygen: freshMlKem,
        repo: repoB,
      );

      final a = repoA.savedIdentity!;
      final b = repoB.savedIdentity!;

      // Same signing identity ...
      expect(a.peerId, b.peerId);
      // ... but the ML-KEM key is fresh each time (random-per-restore).
      expect(a.mlKemPublicKey, isNotNull);
      expect(b.mlKemPublicKey, isNotNull);
      expect(
        a.mlKemPublicKey,
        isNot(b.mlKemPublicKey),
        reason: 'ML-KEM keygen is independent of the mnemonic; each restore '
            'mints a new keypair, so the new device holds a different ML-KEM '
            'key than the old device did.',
      );
      expect(keygenCalls, 2);
    });
  });

  group('restore identity roundtrip — re-announce path fires (P0-B)', () {
    test(
        'successful restore records the one-shot ML-KEM re-announce marker '
        'for every active, non-blocked contact', () async {
      final repo = _FakeIdentityRepo();
      final secureKeyStore = FakeSecureKeyStore();
      final contactRepo = FakeContactRepository();

      contactRepo.seed([
        _contact('peerActive1'),
        _contact('peerActive2'),
        _contact('peerBlocked', blocked: true),
      ]);
      // Marker must start empty.
      expect(await readMlKemReannounceMarker(secureKeyStore), isEmpty);

      final result = await restoreIdentityFromMnemonic(
        input: _validMnemonic,
        callRestore: _deterministicRestore,
        callMlKemKeygen: () async => const {
          'ok': true,
          'publicKey': 'mlkemPubNew',
          'secretKey': 'mlkemSecNew',
        },
        repo: repo,
        secureKeyStore: secureKeyStore,
        contactRepo: contactRepo,
      );

      expect(result, RestoreIdentityResult.success);

      // Re-announce marker now lists exactly the active, non-blocked contacts
      // so they can learn the NEW ML-KEM key and stop using the stale one.
      final marked = await readMlKemReannounceMarker(secureKeyStore);
      expect(marked, containsAll(['peerActive1', 'peerActive2']));
      expect(marked, isNot(contains('peerBlocked')));
      expect(marked, hasLength(2));

      // And the raw secure-storage entry is the JSON encoding written by the
      // production marker writer (not some other key).
      final raw = await secureKeyStore.read(kMlKemReannouncePendingKey);
      expect(raw, isNotNull);
      final decoded = (jsonDecode(raw!) as List).cast<String>();
      expect(decoded.toSet(), {'peerActive1', 'peerActive2'});
    });

    test(
        'restore WITHOUT secureKeyStore/contactRepo still succeeds and writes '
        'NO marker (deps are optional; marker only when both supplied)',
        () async {
      final repo = _FakeIdentityRepo();
      final secureKeyStore = FakeSecureKeyStore();

      final result = await restoreIdentityFromMnemonic(
        input: _validMnemonic,
        callRestore: _deterministicRestore,
        callMlKemKeygen: () async => const {
          'ok': true,
          'publicKey': 'mlkemPubNew',
          'secretKey': 'mlkemSecNew',
        },
        repo: repo,
        // secureKeyStore + contactRepo intentionally omitted.
      );

      expect(result, RestoreIdentityResult.success);
      expect(await readMlKemReannounceMarker(secureKeyStore), isEmpty);
    });

    test(
        'marker is NOT written when restore fails (ML-KEM keygen error) — '
        'no spurious re-announce on a failed restore', () async {
      final repo = _FakeIdentityRepo();
      final secureKeyStore = FakeSecureKeyStore();
      final contactRepo = FakeContactRepository();
      contactRepo.seed([_contact('peerActive1')]);

      final result = await restoreIdentityFromMnemonic(
        input: _validMnemonic,
        callRestore: _deterministicRestore,
        callMlKemKeygen: () async =>
            const {'ok': false, 'errorCode': 'MLKEM_FAIL'},
        repo: repo,
        secureKeyStore: secureKeyStore,
        contactRepo: contactRepo,
      );

      expect(result, RestoreIdentityResult.coreLibError);
      expect(repo.savedIdentity, isNull);
      expect(await readMlKemReannounceMarker(secureKeyStore), isEmpty);
    });

    test(
        're-announce marker write failure does NOT fail the restore '
        '(marker is best-effort)', () async {
      final repo = _FakeIdentityRepo();
      final contactRepo = FakeContactRepository();
      contactRepo.seed([_contact('peerActive1')]);

      // A SecureKeyStore that throws on write to simulate marker-write failure.
      final throwingStore = _ThrowOnWriteSecureKeyStore();

      final result = await restoreIdentityFromMnemonic(
        input: _validMnemonic,
        callRestore: _deterministicRestore,
        callMlKemKeygen: () async => const {
          'ok': true,
          'publicKey': 'mlkemPubNew',
          'secretKey': 'mlkemSecNew',
        },
        repo: repo,
        secureKeyStore: throwingStore,
        contactRepo: contactRepo,
      );

      // Restore still succeeds: the identity was saved before the marker write.
      expect(result, RestoreIdentityResult.success);
      expect(repo.savedIdentity, isNotNull);
    });
  });
}

/// SecureKeyStore that throws on write — used to prove the re-announce marker
/// write is best-effort and does not roll back a successful restore.
class _ThrowOnWriteSecureKeyStore extends FakeSecureKeyStore {
  @override
  Future<void> write(String key, String value) async {
    throw Exception('secure storage write failed');
  }
}
