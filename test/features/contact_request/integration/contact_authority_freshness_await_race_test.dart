import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';
import 'package:flutter_app/features/call/infrastructure/received_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';
import 'package:flutter_app/features/contact_request/application/mlkem_reannounce_marker.dart';
import 'package:flutter_app/features/contact_request/application/wake_token_pending_marker.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';
import 'package:flutter_app/features/push/infrastructure/received_wake_token_store_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../presentation/support/contact_request_sql_fixture.dart';
import '../support/contact_repair_harness.dart';

// Host persistence and public receive-policy proof. Ed25519 signatures are
// real; the encryption bus and file-backed secure-store adapter are test seams.
// This does not exercise native SQLCipher or OS secure storage.
final _bus = Ed25519ContactRequestCryptoBus();
final _self = TestEd25519Identity.fromSeedByte(0x81);
final _peer = TestEd25519Identity.fromSeedByte(0x82);

enum _AwaitCut {
  signatureVerification,
  verifiedAuthorityRead,
  priorRequestRead,
  consentRead,
  grantWrite,
  grantRead,
  tokenRead,
  tokenWrite,
  finalContactRead,
  contactWrite,
}

enum _SupersedingAction {
  // A newer signed ML-KEM/grant/token update from the same account key.
  // This never changes the Ed25519 key bound to the logical peer ID.
  replaceAuthority,
  delete,
  block,
  decline,
}

final class _Pause {
  final entered = Completer<void>();
  final release = Completer<void>();

  Future<void> wait() async {
    if (entered.isCompleted) return;
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

final class _ReceiveBridge extends Bridge {
  _ReceiveBridge(this.inner, this.cut, this.pause);
  final Ed25519ContactRequestBridge inner;
  final _AwaitCut? cut;
  final _Pause pause;

  @override
  bool get isInitialized => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final result = await inner.send(message);
    if (cut == _AwaitCut.signatureVerification &&
        (jsonDecode(message) as Map)['cmd'] == 'payload.verify') {
      await pause.wait();
    }
    return result;
  }
}

final class _GrantBoundary implements ReceivedCallWakeHandleStore {
  _GrantBoundary(this.inner, this.cut, this.pause);
  final ReceivedCallWakeHandleStore inner;
  final _AwaitCut? cut;
  final _Pause pause;

  @override
  Future<bool> storeIfStrictlyNewer({
    required String issuerAccountPeerId,
    required CallWakeHandleGrant grant,
    required int nowMs,
    Future<bool> Function(Future<void> Function() write)? writeIfAuthorized,
  }) async {
    if (cut == _AwaitCut.grantWrite) await pause.wait();
    return inner.storeIfStrictlyNewer(
      issuerAccountPeerId: issuerAccountPeerId,
      grant: grant,
      nowMs: nowMs,
      writeIfAuthorized: writeIfAuthorized,
    );
  }

  @override
  Future<CallWakeHandleGrant?> readForIssuer(String peerId) async {
    final result = await inner.readForIssuer(peerId);
    if (cut == _AwaitCut.grantRead) await pause.wait();
    return result;
  }

  @override
  Future<void> removeForIssuer(String peerId) => inner.removeForIssuer(peerId);
  @override
  Future<void> clear() => inner.clear();
}

final class _TokenBoundary implements ReceivedWakeTokenStore {
  _TokenBoundary(this.inner, this.cut, this.pause);
  final ReceivedWakeTokenStore inner;
  final _AwaitCut? cut;
  final _Pause pause;

  @override
  Future<Map<String, String>?> readTokenFor(String peerId) async {
    final result = await inner.readTokenFor(peerId);
    if (cut == _AwaitCut.tokenRead) await pause.wait();
    return result;
  }

  @override
  Future<void> writeTokenFor(
    String peerId,
    String token,
    String ts, {
    Future<bool> Function(Future<void> Function() write)? writeIfAuthorized,
  }) async {
    if (cut == _AwaitCut.tokenWrite) await pause.wait();
    await inner.writeTokenFor(
      peerId,
      token,
      ts,
      writeIfAuthorized: writeIfAuthorized,
    );
  }

  @override
  Future<void> removeTokenFor(String peerId) => inner.removeTokenFor(peerId);
  @override
  Future<void> clear() => inner.clear();
}

// Forward actual authority persistence; unexpected repair reply operations
// still throw rather than fabricating a successful reply claim.
final class _ConsentBoundary implements ContactRepairRepository {
  _ConsentBoundary(this.inner, this.cut, this.pause);
  final SqlContactRepairRepository inner;
  final _AwaitCut? cut;
  final _Pause pause;

  @override
  Future<ContactRelationshipConsent?> readConsent(String peerId) async {
    final result = await inner.readConsent(peerId);
    if (cut == _AwaitCut.consentRead) await pause.wait();
    return result;
  }

  @override
  Future<bool> writeIfAuthorityCurrent({
    required String peerId,
    required String authorityFingerprint,
    required int relationshipRevision,
    required Future<void> Function() write,
  }) => inner.writeIfAuthorityCurrent(
    peerId: peerId,
    authorityFingerprint: authorityFingerprint,
    relationshipRevision: relationshipRevision,
    write: write,
  );

  @override
  Future<({bool authorized, bool updated, bool hadKey})>
  updateContactKeyIfAuthorityCurrent({
    required String peerId,
    required String authorityFingerprint,
    required int relationshipRevision,
    required String mlKemPublicKey,
    required String? signedAt,
  }) async {
    // The old upsert is now a conditional partial write. Keep the same
    // completed-supersession-before-write schedule at its actual admission.
    if (cut == _AwaitCut.contactWrite) await pause.wait();
    return inner.updateContactKeyIfAuthorityCurrent(
      peerId: peerId,
      authorityFingerprint: authorityFingerprint,
      relationshipRevision: relationshipRevision,
      mlKemPublicKey: mlKemPublicKey,
      signedAt: signedAt,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repair operation: ${invocation.memberName}');
}

ContactRepositoryImpl _contactsAtBoundary(
  Database db,
  _AwaitCut? cut,
  _Pause pause,
) {
  var reads = 0;
  return ContactRepositoryImpl(
    dbLoadContact: (peerId) async {
      final row = await dbLoadContact(db, peerId);
      reads++;
      if ((cut == _AwaitCut.verifiedAuthorityRead && reads == 2) ||
          (cut == _AwaitCut.finalContactRead && reads == 3)) {
        await pause.wait();
      }
      return row;
    },
    dbUpsertContact: (row) async {
      await dbUpsertContact(db, row);
    },
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

ContactRequestRepositoryImpl _requestsAtBoundary(
  Database db,
  _AwaitCut? cut,
  _Pause pause,
) => ContactRequestRepositoryImpl(
  dbLoadRequest: (peerId) async {
    final row = await dbLoadRequest(db, peerId);
    if (cut == _AwaitCut.priorRequestRead) await pause.wait();
    return row;
  },
  dbLoadPendingRequests: () => dbLoadPendingRequests(db),
  dbUpsertRequest: (row) => dbUpsertRequest(db, row),
  dbUpdateRequestStatus: (id, status) => dbUpdateRequestStatus(db, id, status),
  dbDeleteRequest: (id) => dbDeleteRequest(db, id),
  dbRequestExists: (id) => dbRequestExists(db, id),
  dbDecideRequest: (expected, accept, existingOnly, before) =>
      dbDecideContactRequest(db, expected, accept, existingOnly, before),
);

CallWakeHandleGrant _grant(int nowMs, {int generation = 1, String? handle}) =>
    CallWakeHandleGrant(
      handle: handle ?? '0123456789abcdef0123456789abcdef',
      recipientDevicePeerId: _peer.peerId,
      deviceKeyEpoch: 1,
      generation: generation,
      issuedAtMs: nowMs - 1000,
      expiresAtMs: nowMs + const Duration(hours: 1).inMilliseconds,
    );

void main() {
  setUpAll(() {
    _bus
      ..register(_self)
      ..register(_peer);
  });
  late Directory directory;
  late String dbPath;
  late Database db;
  late _FileKeyStore keys;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('contact_authority_');
    dbPath = '${directory.path}/account.db';
    db = await openRepairTestDatabase(dbPath);
    keys = _FileKeyStore(Directory('${directory.path}/keys'));
    await databaseContactRepository(db).addContact(
      contactFor(_peer, mlKem: 'old-key').copyWith(
        username: 'Trusted name',
        avatarPath: 'media/avatars/preserved.jpg',
        avatarVersion: 'avatar-current',
        introsBannerDismissed: true,
        introducedBy: 'Introducer',
        introducedByPeerId: 'introducer-peer-id',
      ),
    );
  });
  tearDown(() async {
    if (db.isOpen) await db.close();
    await directory.delete(recursive: true);
  });

  test('CR-019 key, token and grant ordering survives reopen: identical and '
      'equal-instant conflicts cannot replace newer authority', () async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final firstGrant = _grant(nowMs);
    final secondGrant = _grant(nowMs, generation: 2);
    final conflictGrant = _grant(
      nowMs,
      handle: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    final contacts = databaseContactRepository(db);
    await contacts.archiveContact(_peer.peerId);
    final preserved = (await contacts.getContact(_peer.peerId))!.toMap();
    for (final update
        in <
          ({
            String name,
            String key,
            String token,
            String signedAt,
            CallWakeHandleGrant grant,
            String expectedKey,
            String expectedToken,
            CallWakeHandleGrant expectedGrant,
          })
        >[
          (
            name: 'newer',
            key: 'key-1',
            token: 'token-1',
            signedAt: '2026-10-16T12:00:00.000Z',
            grant: firstGrant,
            expectedKey: 'key-1',
            expectedToken: 'token-1',
            expectedGrant: firstGrant,
          ),
          (
            name: 'identical replay',
            key: 'key-1',
            token: 'token-1',
            signedAt: '2026-10-16T12:00:00.000Z',
            grant: firstGrant,
            expectedKey: 'key-1',
            expectedToken: 'token-1',
            expectedGrant: firstGrant,
          ),
          (
            name: 'equal-instant conflict',
            key: 'conflicting-key',
            token: 'conflicting-token',
            signedAt: '2026-10-16T14:00:00.000+02:00',
            grant: conflictGrant,
            expectedKey: 'key-1',
            expectedToken: 'token-1',
            expectedGrant: firstGrant,
          ),
          (
            name: 'older replay',
            key: 'older-key',
            token: 'older-token',
            signedAt: '2026-10-16T11:00:00.000Z',
            grant: firstGrant,
            expectedKey: 'key-1',
            expectedToken: 'token-1',
            expectedGrant: firstGrant,
          ),
          (
            name: 'strictly newer',
            key: 'key-2',
            token: 'token-2',
            signedAt: '2026-10-16T12:00:01.000Z',
            grant: secondGrant,
            expectedKey: 'key-2',
            expectedToken: 'token-2',
            expectedGrant: secondGrant,
          ),
        ]) {
      final wire = await buildRepairWire(
        bus: _bus,
        signer: _peer,
        recipientPublicKey: _self.publicKey,
        mlKem: update.key,
        wakeToken: update.token,
        ts: update.signedAt,
        callWakeHandle: update.grant,
      );
      final (result, _, _) = await handleIncomingMessage(
        message: wire,
        bridge: Ed25519ContactRequestBridge(_bus),
        requestRepo: buildWidgetRequestRepository(db),
        contactRepo: databaseContactRepository(db),
        ownPeerId: _self.peerId,
        ownPrivateKey: _self.privateKey,
        receivedCallWakeHandleStore: ReceivedCallWakeHandleStoreImpl(
          secureKeyStore: keys,
        ),
        receivedWakeTokenStore: ReceivedWakeTokenStoreImpl(
          secureKeyStore: keys,
        ),
        repairRepository: SqlContactRepairRepository(db),
      );
      expect(
        result,
        anyOf(
          HandleMessageResult.contactKeyUpdated,
          HandleMessageResult.alreadyContact,
        ),
      );
      await db.close();
      db = await openRepairTestDatabase(dbPath);
      final row = (await databaseContactRepository(
        db,
      ).getContact(_peer.peerId))!.toMap();
      expect(row['ml_kem_public_key'], update.expectedKey, reason: update.name);
      expect(
        await ReceivedCallWakeHandleStoreImpl(
          secureKeyStore: keys,
        ).readForIssuer(_peer.peerId),
        update.expectedGrant,
        reason: update.name,
      );
      expect(
        (await ReceivedWakeTokenStoreImpl(
          secureKeyStore: keys,
        ).readTokenFor(_peer.peerId))?['tok'],
        update.expectedToken,
        reason: update.name,
      );
      for (final field in preserved.keys.where(
        (field) => !<String>{
          'ml_kem_public_key',
          'ml_kem_key_updated_ts',
        }.contains(field),
      )) {
        expect(row[field], preserved[field], reason: '${update.name}: $field');
      }
      expect(
        await buildWidgetRequestRepository(db).getPendingRequests(),
        isEmpty,
      );
      expect(await db.query('contact_repair_requests'), isEmpty);
    }
  });

  test(
    'CR-019 restored pending key and token distribution reopens and drains '
    'through the warm retry owner without rolling back receiver metadata',
    () async {
      final senderPath = '${directory.path}/restored-sender.db';
      var senderDb = await openRepairTestDatabase(senderPath);
      final senderKeyDirectory = Directory('${directory.path}/sender-keys');
      var senderKeys = _FileKeyStore(senderKeyDirectory);
      final grant = _grant(
        DateTime.now().toUtc().millisecondsSinceEpoch,
        generation: 2,
      );
      await buildWidgetIdentityRepository(senderDb, senderKeys).saveIdentity(
        testIdentityModel(
          _peer,
          username: 'Restored peer',
          mlKemPublicKey: 'restored-key',
        ),
      );
      await databaseContactRepository(
        senderDb,
      ).addContact(contactFor(_self, mlKem: 'self-key'));
      expect(
        await recordMlKemReannouncePending(
          secureKeyStore: senderKeys,
          contactRepo: databaseContactRepository(senderDb),
        ),
        1,
      );
      expect(
        await reconcileWakeTokenDistribution(
          secureKeyStore: senderKeys,
          registeredTokens: {_self.peerId: 'restored-token'},
        ),
        1,
      );
      await senderDb.close();
      senderDb = await openRepairTestDatabase(senderPath);
      senderKeys = _FileKeyStore(senderKeyDirectory);
      expect(await readMlKemReannounceMarker(senderKeys), [_self.peerId]);
      expect(await readWakeTokenPendingMarker(senderKeys), [_self.peerId]);
      final before = (await databaseContactRepository(
        db,
      ).getContact(_peer.peerId))!;
      final network = FakeP2PNetwork();
      final sender = FakeP2PService(peerId: _peer.peerId, network: network);
      final receiver = FakeP2PService(peerId: _self.peerId, network: network);
      final updated = Completer<void>();
      final receiveListener = ContactRequestListener(
        contactRequestStream: receiver.messageStream,
        requestRepo: buildWidgetRequestRepository(db),
        contactRepo: databaseContactRepository(db),
        bridge: Ed25519ContactRequestBridge(_bus),
        getOwnPeerId: () => _self.peerId,
        getOwnPrivateKey: () async => _self.privateKey,
        receivedCallWakeHandleStore: ReceivedCallWakeHandleStoreImpl(
          secureKeyStore: keys,
        ),
        receivedWakeTokenStore: ReceivedWakeTokenStoreImpl(
          secureKeyStore: keys,
        ),
        repairRepository: SqlContactRepairRepository(db),
        getOwnPublicKey: () async => _self.publicKey,
        downloadProfilePictureFn:
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
              bool retryPendingRequest = false,
            }) async => null,
      );
      final keySubscription = receiveListener.contactKeyUpdatedStream.listen((
        _,
      ) {
        if (!updated.isCompleted) updated.complete();
      });
      receiveListener.start();
      final warmOwner = KeyExchangeRetrier(
        p2pService: sender,
        contactRepo: databaseContactRepository(senderDb),
        identityRepo: buildWidgetIdentityRepository(senderDb, senderKeys),
        bridge: Ed25519ContactRequestBridge(_bus),
        secureKeyStore: senderKeys,
        resolveWakeToken: (_) async => 'restored-token',
        resolveCallWakeHandle: (_) async => grant,
      );
      addTearDown(() async {
        warmOwner.dispose();
        receiveListener.dispose();
        await keySubscription.cancel();
        sender.dispose();
        receiver.dispose();
        if (senderDb.isOpen) await senderDb.close();
      });
      expect(await warmOwner.retryNow(trigger: 'app_resumed'), 1);
      await updated.future.timeout(const Duration(seconds: 5));
      expect(await readMlKemReannounceMarker(senderKeys), isEmpty);
      expect(await readWakeTokenPendingMarker(senderKeys), isEmpty);
      expect(network.deliverCallCount, 1);
      expect(network.storeInInboxCallCount, 0);
      expect(
        await buildWidgetRequestRepository(db).getPendingRequests(),
        isEmpty,
      );
      receiveListener.dispose();
      await db.close();
      db = await openRepairTestDatabase(dbPath);
      final after = (await databaseContactRepository(
        db,
      ).getContact(_peer.peerId))!;
      expect(after.mlKemPublicKey, 'restored-key');
      expect(after.mlKemKeyUpdatedTs, isNotNull);
      final afterMetadata = after.toMap()
        ..remove('ml_kem_public_key')
        ..remove('ml_kem_key_updated_ts');
      final beforeMetadata = before.toMap()
        ..remove('ml_kem_public_key')
        ..remove('ml_kem_key_updated_ts');
      expect(afterMetadata, beforeMetadata);
      expect(
        await ReceivedCallWakeHandleStoreImpl(
          secureKeyStore: keys,
        ).readForIssuer(_peer.peerId),
        grant,
      );
      expect(
        (await ReceivedWakeTokenStoreImpl(
          secureKeyStore: keys,
        ).readTokenFor(_peer.peerId))?['tok'],
        'restored-token',
      );
      await senderDb.close();
      senderDb = await openRepairTestDatabase(senderPath);
      final reopenedSenderKeys = _FileKeyStore(senderKeyDirectory);
      expect(await readMlKemReannounceMarker(reopenedSenderKeys), isEmpty);
      expect(await readWakeTokenPendingMarker(reopenedSenderKeys), isEmpty);
    },
  );

  for (final cut in _AwaitCut.values) {
    for (final action in _SupersedingAction.values) {
      test('CR-019 ${action.name} at ${cut.name} fences all late key, grant '
          'and token authority after reopen', () async {
        final pause = _Pause();
        addTearDown(() {
          if (!pause.release.isCompleted) pause.release.complete();
        });
        final contacts = databaseContactRepository(db);
        final requests = buildWidgetRequestRepository(db);
        final grantStore = ReceivedCallWakeHandleStoreImpl(
          secureKeyStore: keys,
        );
        final tokenStore = ReceivedWakeTokenStoreImpl(secureKeyStore: keys);
        final pending = ContactRequestModel(
          peerId: _peer.peerId,
          publicKey: _peer.publicKey,
          rendezvous: repairRendezvous,
          username: 'Pending',
          signature: 'pending-signature',
          receivedAt: '2026-10-16T12:00:00.000Z',
        );
        await requests.addRequest(pending);
        final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
        final newerGrant = _grant(nowMs, generation: 2);
        const newerToken = <String, String>{
          'tok': 'newer-token',
          'ts': '2026-10-30T13:00:00.000Z',
        };
        final wire = await buildRepairWire(
          bus: _bus,
          signer: _peer,
          recipientPublicKey: _self.publicKey,
          mlKem: 'late-key',
          wakeToken: 'late-token',
          ts: '2026-10-30T12:00:00.000Z',
          callWakeHandle: _grant(nowMs),
        );
        final receive = handleIncomingMessage(
          message: wire,
          bridge: _ReceiveBridge(Ed25519ContactRequestBridge(_bus), cut, pause),
          requestRepo: _requestsAtBoundary(db, cut, pause),
          contactRepo: _contactsAtBoundary(db, cut, pause),
          ownPeerId: _self.peerId,
          ownPrivateKey: _self.privateKey,
          receivedCallWakeHandleStore: _GrantBoundary(grantStore, cut, pause),
          receivedWakeTokenStore: _TokenBoundary(tokenStore, cut, pause),
          repairRepository: _ConsentBoundary(
            SqlContactRepairRepository(db),
            cut,
            pause,
          ),
        );
        await pause.entered.future.timeout(const Duration(seconds: 5));
        switch (action) {
          case _SupersedingAction.replaceAuthority:
            // Supersede through the real receive path with a valid signature
            // under the SAME account key and newer clocks/capability generation.
            final newerWire = await buildRepairWire(
              bus: _bus,
              signer: _peer,
              recipientPublicKey: _self.publicKey,
              mlKem: 'newer-key',
              wakeToken: newerToken['tok'],
              ts: newerToken['ts'],
              callWakeHandle: newerGrant,
            );
            final (newerResult, _, _) = await handleIncomingMessage(
              message: newerWire,
              bridge: Ed25519ContactRequestBridge(_bus),
              requestRepo: requests,
              contactRepo: contacts,
              ownPeerId: _self.peerId,
              ownPrivateKey: _self.privateKey,
              receivedCallWakeHandleStore: grantStore,
              receivedWakeTokenStore: tokenStore,
              repairRepository: SqlContactRepairRepository(db),
            );
            expect(newerResult, HandleMessageResult.contactKeyUpdated);
            final newerContact = (await contacts.getContact(_peer.peerId))!;
            expect(newerContact.publicKey, _peer.publicKey);
            expect(newerContact.mlKemPublicKey, 'newer-key');
            expect(newerContact.mlKemKeyUpdatedTs, newerToken['ts']);
            await contacts.addContact(
              newerContact.copyWith(
                username: 'Newer valid name',
                isArchived: true,
                archivedAt: '2026-10-30T13:00:00.000Z',
                introsSentAt: '2026-10-30T13:00:00.000Z',
              ),
            );
          case _SupersedingAction.delete:
            await contacts.deleteContact(_peer.peerId);
          case _SupersedingAction.block:
            await contacts.blockContact(_peer.peerId);
          case _SupersedingAction.decline:
            await contacts.deleteContact(_peer.peerId);
            expect(
              await declineContactRequest(
                requestRepo: requests,
                peerId: _peer.peerId,
                expectedRequest: pending,
              ),
              DeclineContactRequestResult.success,
            );
        }
        final CallWakeHandleGrant? expectedGrant;
        final Map<String, String>? expectedToken;
        if (action == _SupersedingAction.replaceAuthority) {
          // Ordinary key rotation retains the newer live capabilities.
          expectedGrant = newerGrant;
          expectedToken = newerToken;
          expect(await grantStore.readForIssuer(_peer.peerId), newerGrant);
          expect(await tokenStore.readTokenFor(_peer.peerId), newerToken);
        } else {
          // Complete the revocation owner's cleanup through public stores.
          // A continuation must not recreate authority after this point.
          await grantStore.removeForIssuer(_peer.peerId);
          await tokenStore.removeTokenFor(_peer.peerId);
          expectedGrant = null;
          expectedToken = null;
        }
        final expectedRow = (await contacts.getContact(_peer.peerId))?.toMap();
        final expectedConsent = await SqlContactRepairRepository(
          db,
        ).readConsent(_peer.peerId);
        pause.release.complete();
        await receive.timeout(const Duration(seconds: 5));
        await db.close();
        db = await openRepairTestDatabase(dbPath);
        final reopenedKeys = _FileKeyStore(Directory('${directory.path}/keys'));
        final actual = (await databaseContactRepository(
          db,
        ).getContact(_peer.peerId))?.toMap();
        final persistedGrant = await ReceivedCallWakeHandleStoreImpl(
          secureKeyStore: reopenedKeys,
        ).readForIssuer(_peer.peerId);
        final persistedToken = await ReceivedWakeTokenStoreImpl(
          secureKeyStore: reopenedKeys,
        ).readTokenFor(_peer.peerId);
        final consent = await SqlContactRepairRepository(
          db,
        ).readConsent(_peer.peerId);
        expect(
          <String, Object?>{
            'contact': actual,
            'grant': persistedGrant?.toCanonicalMap(),
            'token': persistedToken,
          },
          <String, Object?>{
            'contact': expectedRow,
            'grant': expectedGrant?.toCanonicalMap(),
            'token': expectedToken,
          },
          reason:
              'superseding key, capability clocks and flags survive without stale writes',
        );
        expect(consent?.state, expectedConsent?.state);
        expect(consent?.revision, expectedConsent?.revision);
        if (action == _SupersedingAction.decline) {
          expect(
            (await buildWidgetRequestRepository(
              db,
            ).getRequest(_peer.peerId))?.status,
            ContactRequestStatus.declined,
          );
        }
        expect(await db.query('contact_repair_requests'), isEmpty);
      });
    }
  }

  test('CR-019 metadata changes during grant await retain current flags while '
      'the authorized newer key, grant and token become durable', () async {
    final pause = _Pause();
    addTearDown(() {
      if (!pause.release.isCompleted) pause.release.complete();
    });
    final grant = _grant(DateTime.now().toUtc().millisecondsSinceEpoch);
    final contacts = databaseContactRepository(db);
    final wire = await buildRepairWire(
      bus: _bus,
      signer: _peer,
      recipientPublicKey: _self.publicKey,
      mlKem: 'authorized-key',
      wakeToken: 'authorized-token',
      ts: '2026-10-30T12:00:00.000Z',
      callWakeHandle: grant,
    );
    final receive = handleIncomingMessage(
      message: wire,
      bridge: Ed25519ContactRequestBridge(_bus),
      requestRepo: buildWidgetRequestRepository(db),
      contactRepo: contacts,
      ownPeerId: _self.peerId,
      ownPrivateKey: _self.privateKey,
      receivedCallWakeHandleStore: _GrantBoundary(
        ReceivedCallWakeHandleStoreImpl(secureKeyStore: keys),
        _AwaitCut.grantWrite,
        pause,
      ),
      receivedWakeTokenStore: ReceivedWakeTokenStoreImpl(secureKeyStore: keys),
      repairRepository: SqlContactRepairRepository(db),
    );
    await pause.entered.future.timeout(const Duration(seconds: 5));
    await contacts.archiveContact(_peer.peerId);
    await contacts.setIntrosSentAt(_peer.peerId, '2026-10-30T11:00:00.000Z');
    final expected = (await contacts.getContact(_peer.peerId))!.copyWith(
      mlKemPublicKey: 'authorized-key',
      mlKemKeyUpdatedTs: '2026-10-30T12:00:00.000Z',
    );
    pause.release.complete();
    final (result, _, _) = await receive;
    expect(result, HandleMessageResult.contactKeyUpdated);
    await db.close();
    db = await openRepairTestDatabase(dbPath);
    expect(
      (await databaseContactRepository(db).getContact(_peer.peerId))!.toMap(),
      expected.toMap(),
    );
    expect(
      await ReceivedCallWakeHandleStoreImpl(
        secureKeyStore: keys,
      ).readForIssuer(_peer.peerId),
      grant,
    );
    expect(
      (await ReceivedWakeTokenStoreImpl(
        secureKeyStore: keys,
      ).readTokenFor(_peer.peerId))?['tok'],
      'authorized-token',
    );
  });
}
