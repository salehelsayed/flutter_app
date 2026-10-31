import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository_impl.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../presentation/support/contact_request_sql_fixture.dart';
import '../support/contact_repair_harness.dart';

final _owner = TestEd25519Identity.fromSeedByte(0xE1);
final _sender = TestEd25519Identity.fromSeedByte(0xE2);

/// Only the relay transport and encryption are seams. Production inbox drain,
/// staging SQL, verification, request decisions and contact SQL run unchanged.
final class _RetainedInboxBridge extends Bridge {
  _RetainedInboxBridge(this.crypto);
  final Ed25519ContactRequestBridge crypto;
  final held = <Map<String, Object?>>[];
  final acknowledged = <String>[];
  final stagedBeforeReplay = <String>{};
  late Database db;
  int retrieveCount = 0;

  void hold(String id, ChatMessage wire) => held.add({
    'id': id,
    'from': wire.from,
    'message': wire.content,
    'timestamp': wire.timestamp,
  });

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
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (request['cmd'] == 'node:start') {
      return jsonEncode({
        'ok': true,
        'peerId': _owner.peerId,
        'isStarted': true,
        'listenAddresses': <String>[],
        'circuitAddresses': <String>[],
        'connections': <Object>[],
        'relayState': 'offline',
        'healthyRelayCount': 0,
      });
    }
    if (request['cmd'] == 'inbox:retrieve_pending') {
      expect(
        (request['payload'] as Map)['custodyContract'],
        ackOrExpiryInboxCustodyContract,
      );
      stagedBeforeReplay.clear();
      retrieveCount++;
      return jsonEncode({
        'ok': true,
        'custodyContract': ackOrExpiryInboxCustodyContract,
        'messages': held.toList(),
        'hasMore': false,
      });
    }
    if (request['cmd'] == 'inbox:ack') {
      expect(
        (request['payload'] as Map)['custodyContract'],
        ackOrExpiryInboxCustodyContract,
      );
      final ids = ((request['payload'] as Map)['entryIds'] as List)
          .cast<String>();
      for (final id in ids) {
        expect(
          stagedBeforeReplay,
          contains(id),
          reason: 'relay ACK requires staging witnessed before semantic replay',
        );
        held.removeWhere((row) => row['id'] == id);
        acknowledged.add(id);
      }
      return jsonEncode({
        'ok': true,
        'acked': ids.length,
        'custodyContract': ackOrExpiryInboxCustodyContract,
      });
    }
    return crypto.send(message);
  }
}

InboxStagingRepositoryImpl _staging(Database db) => InboxStagingRepositoryImpl(
  dbInsertInboxStagingEntry: (row) => dbInsertInboxStagingEntry(db, row),
  dbLoadRecoverableInboxStagingEntries: ({limit = 50, entryIds}) =>
      dbLoadRecoverableInboxStagingEntries(
        db,
        limit: limit,
        entryIds: entryIds,
      ),
  dbLoadInboxStagingEntry: (id) => dbLoadInboxStagingEntry(db, id),
  dbDeleteInboxStagingEntry: (id) => dbDeleteInboxStagingEntry(db, id),
  dbMarkInboxStagingEntryRetryable: (id, {required reasonCode, reasonDetail}) =>
      dbMarkInboxStagingEntryRetryable(
        db,
        id,
        reasonCode: reasonCode,
        reasonDetail: reasonDetail,
      ),
  dbMarkInboxStagingEntryRejected: (id, {required reasonCode, reasonDetail}) =>
      dbMarkInboxStagingEntryRejected(
        db,
        id,
        reasonCode: reasonCode,
        reasonDetail: reasonDetail,
      ),
  dbMarkInboxStagingEntryQuarantined:
      (id, {required reasonCode, reasonDetail}) =>
          dbMarkInboxStagingEntryQuarantined(
            db,
            id,
            reasonCode: reasonCode,
            reasonDetail: reasonDetail,
          ),
  dbCountQuarantinedInboxStagingEntries: () =>
      dbCountQuarantinedInboxStagingEntries(db),
);

final class _Receiver {
  _Receiver(this.db, this.bridge);
  Database db;
  final _RetainedInboxBridge bridge;
  late ContactRequestListener listener;
  late P2PServiceImpl service;

  Future<void> start() async {
    bridge.db = db;
    listener = ContactRequestListener(
      contactRequestStream: const Stream.empty(),
      requestRepo: buildWidgetRequestRepository(db),
      contactRepo: databaseContactRepository(db),
      bridge: bridge,
      getOwnPeerId: () => _owner.peerId,
      getOwnPrivateKey: () async => _owner.privateKey,
      // No auto-consent callback: receipt must persist a pending request.
    );
    service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: _staging(db),
      replayRecoveredInboxContactRequest: (message) async {
        final held = bridge.held.singleWhere(
          (row) =>
              row['from'] == message.from && row['message'] == message.content,
        );
        final entryId = held['id'] as String;
        expect(
          await dbLoadInboxStagingEntry(bridge.db, entryId),
          isNotNull,
          reason: 'semantic replay requires an actual durable staging row',
        );
        bridge.stagedBeforeReplay.add(entryId);
        await listener.processIncomingMessage(message);
        return (
          disposition: RecoveredInboxChatDisposition.committed,
          reasonCode: 'contact_request_processed',
          reasonDetail: null,
        );
      },
    );
    expect(
      await service.startNodeCore(
        base64Encode(_owner.signingKey),
        _owner.peerId,
      ),
      isTrue,
    );
  }

  Future<void> reopen() async {
    service.dispose();
    listener.dispose();
    final path = db.path;
    await db.close();
    db = await openRepairTestDatabase(path);
    await start();
  }

  Future<void> dispose() async {
    service.dispose();
    listener.dispose();
    if (db.isOpen) await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(_Receiver, Directory, Ed25519ContactRequestCryptoBus)>
  fixture() async {
    final directory = await Directory.systemTemp.createTemp(
      'request-retention-',
    );
    final bus = Ed25519ContactRequestCryptoBus()
      ..register(_owner)
      ..register(_sender);
    final bridge = _RetainedInboxBridge(Ed25519ContactRequestBridge(bus));
    final receiver = _Receiver(
      await openRepairTestDatabase('${directory.path}/identity.db'),
      bridge,
    );
    await receiver.start();
    addTearDown(() async {
      await receiver.dispose();
      await directory.delete(recursive: true);
    });
    return (receiver, directory, bus);
  }

  test('CR-006 CONTACT-010 relay-held request below 24h recovers once after '
      'cold reopen and explicit acceptance survives another reopen', () async {
    final (receiver, _, bus) = await fixture();
    final timestamp = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 23, minutes: 55))
        .toIso8601String();
    final wire = await buildRepairWire(
      bus: bus,
      signer: _sender,
      recipientPublicKey: _owner.publicKey,
      ts: timestamp,
      outerTs: timestamp,
      mlKem: 'sender-mlkem-at-send',
    );
    receiver.bridge.hold('held-under-24h', wire);
    await receiver.reopen();
    await receiver.service.drainOfflineInbox();
    expect(receiver.bridge.retrieveCount, greaterThan(0));
    expect(receiver.bridge.acknowledged, ['held-under-24h']);
    var requests = buildWidgetRequestRepository(receiver.db);
    expect(await requests.getPendingRequests(), hasLength(1));
    expect(
      await databaseContactRepository(receiver.db).getContactCount(),
      0,
      reason: 'cold recovery cannot manufacture manual consent',
    );
    await receiver.reopen();
    receiver.bridge.hold('relay-redelivery-new-id', wire);
    await receiver.service.drainOfflineInbox();
    requests = buildWidgetRequestRepository(receiver.db);
    final pending = await requests.getPendingRequests();
    expect(pending, hasLength(1));
    expect(pending.single.peerId, _sender.peerId);
    expect(
      await acceptContactRequest(
        requestRepo: requests,
        contactRepo: databaseContactRepository(receiver.db),
        peerId: _sender.peerId,
        expectedRequest: pending.single,
      ),
      AcceptContactRequestResult.success,
    );
    await receiver.reopen();
    expect(
      await buildWidgetRequestRepository(receiver.db).getPendingRequests(),
      isEmpty,
    );
    expect(
      (await buildWidgetRequestRepository(
        receiver.db,
      ).getRequest(_sender.peerId))!.status,
      ContactRequestStatus.accepted,
    );
    expect(await databaseContactRepository(receiver.db).getContactCount(), 1);
    expect(
      (await databaseContactRepository(
        receiver.db,
      ).getContact(_sender.peerId))!.mlKemPublicKey,
      'sender-mlkem-at-send',
    );
  });

  test(
    'CR-006 CONTACT-010 request beyond seven days does not survive '
    'as consent; a fresh request preserves newer current-key authority',
    () async {
      final (receiver, _, bus) = await fixture();
      // This age is rejected by both the pinned base and the owner-approved
      // seven-day policy. Delivery at 24h..7days belongs to the separate approved
      // patch dbe6fcfc2a032b16e40969209863b94bc169ae05 and is not proved here.
      final expiredTs = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 7, minutes: 1))
          .toIso8601String();
      receiver.bridge.hold(
        'expired-held-request',
        await buildRepairWire(
          bus: bus,
          signer: _sender,
          recipientPublicKey: _owner.publicKey,
          ts: expiredTs,
          outerTs: expiredTs,
          mlKem: 'expired-mlkem',
        ),
      );
      await receiver.reopen();
      await receiver.service.drainOfflineInbox();
      await receiver.reopen();
      expect(
        await buildWidgetRequestRepository(receiver.db).getPendingRequests(),
        isEmpty,
      );
      expect(await databaseContactRepository(receiver.db).getContactCount(), 0);
      expect(
        await acceptContactRequest(
          requestRepo: buildWidgetRequestRepository(receiver.db),
          contactRepo: databaseContactRepository(receiver.db),
          peerId: _sender.peerId,
        ),
        AcceptContactRequestResult.notFound,
      );

      receiver.bridge.hold(
        'fresh-manual-request',
        await buildRepairWire(
          bus: bus,
          signer: _sender,
          recipientPublicKey: _owner.publicKey,
          mlKem: 'fresh-request-mlkem',
        ),
      );
      await receiver.service.drainOfflineInbox();
      await receiver.reopen();
      final requests = buildWidgetRequestRepository(receiver.db);
      final pending = (await requests.getPendingRequests()).single;
      expect(await databaseContactRepository(receiver.db).getContactCount(), 0);
      // A newer authenticated QR/key update wins while the old dialog remains
      // open. The atomic public accept decision must preserve that current row.
      final contacts = databaseContactRepository(receiver.db);
      await contacts.addContact(
        contactFor(
          _sender,
          mlKem: 'newer-current-mlkem',
          scannedAt: DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 1))
              .toIso8601String(),
        ),
      );
      expect(
        await acceptContactRequest(
          requestRepo: requests,
          contactRepo: contacts,
          peerId: _sender.peerId,
          expectedRequest: pending,
        ),
        AcceptContactRequestResult.success,
      );
      await receiver.reopen();
      expect(
        (await databaseContactRepository(
          receiver.db,
        ).getContact(_sender.peerId))!.mlKemPublicKey,
        'newer-current-mlkem',
      );
      expect(await databaseContactRepository(receiver.db).getContactCount(), 1);
      expect(
        await buildWidgetRequestRepository(receiver.db).getPendingRequests(),
        isEmpty,
      );
    },
  );
}
