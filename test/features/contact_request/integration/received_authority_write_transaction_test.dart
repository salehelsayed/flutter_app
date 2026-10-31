import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/infrastructure/received_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/contact_request/application/existing_contact_repair_policy.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/push/infrastructure/received_wake_token_store_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../support/contact_repair_harness.dart';

// Real file persistence with one pause at the actual secure-store write. This
// does not exercise native keychain/keystore or SQLCipher encryption.
final class _HeldFileKeyStore implements SecureKeyStore {
  _HeldFileKeyStore(this.directory, {this.holdKey});

  final Directory directory;
  final String? holdKey;
  final entered = Completer<void>();
  final release = Completer<void>();
  var writes = 0;
  var writeHeldInsideTransaction = false;

  File _file(String key) =>
      File('${directory.path}/${Uri.encodeComponent(key)}');

  @override
  Future<String?> read(String key) async {
    final file = _file(key);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (key == holdKey && !entered.isCompleted) {
      writeHeldInsideTransaction = isInsideDbWriteTransaction();
      entered.complete();
      await release.future;
    }
    await directory.create(recursive: true);
    await _file(key).writeAsString(value, flush: true);
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> containsKey(String key) => _file(key).exists();
}

void main() {
  final peer = TestEd25519Identity.fromSeedByte(0x82);
  const nowMs = 1793448000000;
  final grant = CallWakeHandleGrant(
    handle: '0123456789abcdef0123456789abcdef',
    recipientDevicePeerId: peer.peerId,
    deviceKeyEpoch: 1,
    generation: 1,
    issuedAtMs: nowMs - 1000,
    expiresAtMs: nowMs + const Duration(hours: 1).inMilliseconds,
  );

  for (final capability in ['grant', 'token']) {
    test('CR-019 $capability secure write holds authority until revocation '
        'can commit', () async {
      final directory = await Directory.systemTemp.createTemp(
        'received_authority_write_',
      );
      final databasePath = '${directory.path}/account.db';
      var db = await openRepairTestDatabase(databasePath);
      final keys = _HeldFileKeyStore(
        Directory('${directory.path}/keys'),
        holdKey: capability == 'grant'
            ? receivedCallWakeHandlesSecureStorageKey
            : receivedWakeTokensSecureStorageKey,
      );
      Future<void>? pendingWrite;
      Future<void>? pendingRevocation;
      addTearDown(() async {
        if (!keys.release.isCompleted) keys.release.complete();
        try {
          await pendingWrite;
        } catch (_) {}
        try {
          await pendingRevocation;
        } catch (_) {}
        if (db.isOpen) await db.close();
        await directory.delete(recursive: true);
      });
      final contacts = databaseContactRepository(db);
      await contacts.addContact(contactFor(peer, mlKem: 'current-key'));
      final repair = SqlContactRepairRepository(db);
      final consent = await repair.readConsent(peer.peerId);
      final grants = ReceivedCallWakeHandleStoreImpl(secureKeyStore: keys);
      final tokens = ReceivedWakeTokenStoreImpl(secureKeyStore: keys);
      Future<bool> writeIfAuthorized(Future<void> Function() write) =>
          repair.writeIfAuthorityCurrent(
            peerId: peer.peerId,
            authorityFingerprint: ed25519AuthorityFingerprint(peer.publicKey),
            relationshipRevision: consent!.revision,
            write: write,
          );

      Future<void> writeCapability() async {
        if (capability == 'grant') {
          expect(
            await grants.storeIfStrictlyNewer(
              issuerAccountPeerId: peer.peerId,
              grant: grant,
              nowMs: nowMs,
              writeIfAuthorized: writeIfAuthorized,
            ),
            isTrue,
          );
        } else {
          await tokens.writeTokenFor(
            peer.peerId,
            'received-token',
            '2026-10-31T12:00:00.000Z',
            writeIfAuthorized: writeIfAuthorized,
          );
        }
      }

      pendingWrite = writeCapability();
      await keys.entered.future.timeout(const Duration(seconds: 5));
      expect(keys.writeHeldInsideTransaction, isTrue);
      final revocationEntered = Completer<void>();
      var revocationCompleted = false;
      Future<void> revoke() async {
        await dbWriteTransaction(db, (txn) async {
          revocationEntered.complete();
          await dbDeleteContactWithinTransaction(txn, peer.peerId);
        });
        await grants.removeForIssuer(peer.peerId);
        await tokens.removeTokenFor(peer.peerId);
        revocationCompleted = true;
      }

      pendingRevocation = revoke();
      // Give the queued transaction a turn without releasing secure I/O.
      await Future<void>.delayed(Duration.zero);
      expect(revocationEntered.isCompleted, isFalse);
      expect(revocationCompleted, isFalse);

      keys.release.complete();
      await pendingWrite;
      await pendingRevocation;
      expect(revocationEntered.isCompleted, isTrue);
      expect(revocationCompleted, isTrue);
      expect(keys.writes, 1);

      await db.close();
      db = await openRepairTestDatabase(databasePath);
      final reopenedKeys = _HeldFileKeyStore(keys.directory);
      expect(
        await databaseContactRepository(db).getContact(peer.peerId),
        isNull,
      );
      expect(
        (await SqlContactRepairRepository(db).readConsent(peer.peerId))?.state,
        ContactRelationshipState.withdrawn,
      );
      expect(
        await ReceivedCallWakeHandleStoreImpl(
          secureKeyStore: reopenedKeys,
        ).readForIssuer(peer.peerId),
        isNull,
      );
      expect(
        await ReceivedWakeTokenStoreImpl(
          secureKeyStore: reopenedKeys,
        ).readTokenFor(peer.peerId),
        isNull,
      );
    });
  }

  test(
    'CR-019 revoked authority refuses both secure writes before admission',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'received_authority_refused_',
      );
      final db = await openRepairTestDatabase();
      addTearDown(() async {
        await db.close();
        await directory.delete(recursive: true);
      });
      final keys = _HeldFileKeyStore(directory);
      final contacts = databaseContactRepository(db);
      await contacts.addContact(contactFor(peer));
      final repair = SqlContactRepairRepository(db);
      final consent = await repair.readConsent(peer.peerId);
      await contacts.deleteContact(peer.peerId);
      Future<bool> writeIfAuthorized(Future<void> Function() write) =>
          repair.writeIfAuthorityCurrent(
            peerId: peer.peerId,
            authorityFingerprint: ed25519AuthorityFingerprint(peer.publicKey),
            relationshipRevision: consent!.revision,
            write: write,
          );
      final grants = ReceivedCallWakeHandleStoreImpl(secureKeyStore: keys);
      final tokens = ReceivedWakeTokenStoreImpl(secureKeyStore: keys);
      expect(
        await grants.storeIfStrictlyNewer(
          issuerAccountPeerId: peer.peerId,
          grant: grant,
          nowMs: nowMs,
          writeIfAuthorized: writeIfAuthorized,
        ),
        isFalse,
      );
      await tokens.writeTokenFor(
        peer.peerId,
        'refused-token',
        '2026-10-31T12:00:00.000Z',
        writeIfAuthorized: writeIfAuthorized,
      );
      expect(keys.writes, 0);
      expect(await grants.readForIssuer(peer.peerId), isNull);
      expect(await tokens.readTokenFor(peer.peerId), isNull);
    },
  );
}
