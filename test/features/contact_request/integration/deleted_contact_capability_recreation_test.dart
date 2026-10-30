import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/infrastructure/received_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/push/infrastructure/received_wake_token_store_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../presentation/support/contact_request_sql_fixture.dart';
import '../support/contact_repair_harness.dart';

final class _Pause {
  final entered = Completer<void>();
  final release = Completer<void>();

  Future<void> wait() async {
    entered.complete();
    await release.future;
  }
}

final class _FileKeyStore implements SecureKeyStore {
  _FileKeyStore(this.directory);
  final Directory directory;
  File _file(String key) =>
      File('${directory.path}/${Uri.encodeComponent(key)}');

  @override
  Future<String?> read(String key) async {
    final file = _file(key);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
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

ContactRepositoryImpl _contactsAtVerifiedAuthorityRead(
  Database db,
  _Pause pause,
) {
  var reads = 0;
  return ContactRepositoryImpl(
    dbLoadContact: (peerId) async {
      final row = await dbLoadContact(db, peerId);
      if (++reads == 2) await pause.wait();
      return row;
    },
    dbUpsertContact: (row) => dbUpsertContact(db, row),
    dbLoadAllContacts: () => dbLoadAllContacts(db),
    dbDeleteContact: (id) => dbDeleteContact(db, id),
    dbGetContactCount: () => dbGetContactCount(db),
    dbContactExists: (id) => dbContactExists(db, id),
    dbArchiveContact: (id) => dbArchiveContact(db, id),
    dbUnarchiveContact: (id) => dbUnarchiveContact(db, id),
    dbLoadActiveContacts: () => dbLoadActiveContacts(db),
    dbLoadArchivedContacts: () => dbLoadArchivedContacts(db),
    dbBlockContact: (id) => dbBlockContact(db, id),
    dbUnblockContact: (id) => dbUnblockContact(db, id),
    dbDismissIntroBanner: (id) => dbDismissIntroBanner(db, id),
    dbSetIntrosSentAt: (id, ts) => dbSetIntrosSentAt(db, id, ts),
  );
}

void main() {
  test('CR-019 delete at verifiedAuthorityRead fences all late key, grant '
      'and token authority after reopen', () async {
    final bus = Ed25519ContactRequestCryptoBus();
    final self = TestEd25519Identity.fromSeedByte(0x81);
    final peer = TestEd25519Identity.fromSeedByte(0x82);
    bus
      ..register(self)
      ..register(peer);
    final directory = await Directory.systemTemp.createTemp(
      'contact_authority_',
    );
    final dbPath = '${directory.path}/account.db';
    var db = await openRepairTestDatabase(dbPath);
    final keys = _FileKeyStore(Directory('${directory.path}/keys'));
    final pause = _Pause();
    addTearDown(() async {
      if (!pause.release.isCompleted) pause.release.complete();
      if (db.isOpen) await db.close();
      await directory.delete(recursive: true);
    });
    final contacts = databaseContactRepository(db);
    await contacts.addContact(
      contactFor(peer, mlKem: 'old-key').copyWith(
        username: 'Trusted name',
        avatarPath: 'media/avatars/preserved.jpg',
        avatarVersion: 'avatar-current',
        introsBannerDismissed: true,
        introducedBy: 'Introducer',
        introducedByPeerId: 'introducer-peer-id',
      ),
    );
    final requests = buildWidgetRequestRepository(db);
    final grantStore = ReceivedCallWakeHandleStoreImpl(secureKeyStore: keys);
    final tokenStore = ReceivedWakeTokenStoreImpl(secureKeyStore: keys);
    await requests.addRequest(
      ContactRequestModel(
        peerId: peer.peerId,
        publicKey: peer.publicKey,
        rendezvous: repairRendezvous,
        username: 'Pending',
        signature: 'pending-signature',
        receivedAt: '2026-10-16T12:00:00.000Z',
      ),
    );
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final wire = await buildRepairWire(
      bus: bus,
      signer: peer,
      recipientPublicKey: self.publicKey,
      mlKem: 'late-key',
      wakeToken: 'late-token',
      ts: '2026-10-30T12:00:00.000Z',
      callWakeHandle: CallWakeHandleGrant(
        handle: '0123456789abcdef0123456789abcdef',
        recipientDevicePeerId: peer.peerId,
        deviceKeyEpoch: 1,
        generation: 1,
        issuedAtMs: nowMs - 1000,
        expiresAtMs: nowMs + const Duration(hours: 1).inMilliseconds,
      ),
    );
    final receive = handleIncomingMessage(
      message: wire,
      bridge: Ed25519ContactRequestBridge(bus),
      requestRepo: requests,
      contactRepo: _contactsAtVerifiedAuthorityRead(db, pause),
      ownPeerId: self.peerId,
      ownPrivateKey: self.privateKey,
      receivedCallWakeHandleStore: grantStore,
      receivedWakeTokenStore: tokenStore,
      repairRepository: SqlContactRepairRepository(db),
    );
    await pause.entered.future.timeout(const Duration(seconds: 5));
    await contacts.deleteContact(peer.peerId);
    // Complete the same public-store cleanup as Astra's selected case.
    await grantStore.removeForIssuer(peer.peerId);
    await tokenStore.removeTokenFor(peer.peerId);
    final expectedRow = (await contacts.getContact(peer.peerId))?.toMap();
    expect(expectedRow, isNull);
    final expectedConsent = await SqlContactRepairRepository(
      db,
    ).readConsent(peer.peerId);
    pause.release.complete();
    await receive.timeout(const Duration(seconds: 5));
    await db.close();
    db = await openRepairTestDatabase(dbPath);
    final reopenedKeys = _FileKeyStore(Directory('${directory.path}/keys'));
    final actual = (await databaseContactRepository(
      db,
    ).getContact(peer.peerId))?.toMap();
    final persistedGrant = await ReceivedCallWakeHandleStoreImpl(
      secureKeyStore: reopenedKeys,
    ).readForIssuer(peer.peerId);
    final persistedToken = await ReceivedWakeTokenStoreImpl(
      secureKeyStore: reopenedKeys,
    ).readTokenFor(peer.peerId);
    final consent = await SqlContactRepairRepository(
      db,
    ).readConsent(peer.peerId);
    expect(
      <String, Object?>{
        'contact': actual,
        'grant': persistedGrant?.toCanonicalMap(),
        'token': persistedToken,
      },
      <String, Object?>{'contact': expectedRow, 'grant': null, 'token': null},
      reason:
          'deleted contact capability cleanup survives the late continuation',
    );
    expect(consent?.state, expectedConsent?.state);
    expect(consent?.revision, expectedConsent?.revision);
    expect(await db.query('contact_repair_requests'), isEmpty);
  });
}
