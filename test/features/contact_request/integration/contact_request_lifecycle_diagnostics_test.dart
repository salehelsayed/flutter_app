import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/repositories/direct_contact_conversation_purge.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../presentation/support/contact_request_sql_fixture.dart';
import '../support/contact_repair_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final local = TestEd25519Identity.fromSeedByte(0x71);
  final peer = TestEd25519Identity.fromSeedByte(0x72);
  const privateName = 'PRIVATE_CONTACT_DIAGNOSTICS_NAME';
  const privateIntro = 'PRIVATE_INTRODUCTION_DIAGNOSTICS_ID';
  late Directory directory;
  late Database db;
  late AppDiagnostics diagnostics;
  late Ed25519ContactRequestCryptoBus bus;
  late Ed25519ContactRequestBridge bridge;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('contact-diagnostics-');
    diagnostics = await AppDiagnostics.installForTesting(directory: directory);
    db = await openRepairTestDatabase();
    bus = Ed25519ContactRequestCryptoBus()
      ..register(local)
      ..register(peer);
    bridge = Ed25519ContactRequestBridge(bus);
  });

  tearDown(() async {
    await db.close();
    await diagnostics.dispose();
    await directory.delete(recursive: true);
  });

  Future<List<Map<String, dynamic>>> exported() async {
    final preview = await diagnostics.exportPreview();
    for (final secret in [
      privateName,
      privateIntro,
      peer.peerId,
      peer.publicKey,
      peer.privateKey,
      local.peerId,
      local.publicKey,
      repairRendezvous,
    ]) {
      expect(
        preview,
        isNot(contains(secret)),
        reason: 'private value escaped export',
      );
    }
    final document = jsonDecode(preview) as Map<String, dynamic>;
    return (document['events'] as List)
        .cast<Map<String, dynamic>>()
        .where((event) => event['feature'] == 'contact_request')
        .toList();
  }

  Future<void> expectEvent(
    String source,
    String consent,
    String action,
    String disposition,
  ) async {
    final events = await exported();
    expect(
      events.map((event) => event['values']),
      contains(
        allOf(
          containsPair('requestSource', source),
          containsPair('consentClass', consent),
          containsPair('requestAction', action),
          containsPair('requestDisposition', disposition),
        ),
      ),
    );
  }

  Future<void> withdraw() async {
    final contacts = _purgingContacts(db);
    await contacts.addContact(contactFor(peer));
    await deleteContactAndMessages(
      contactRepo: contacts,
      messageRepo: InMemoryMessageRepository(),
      peerId: peer.peerId,
      contactRequestRepo: buildWidgetRequestRepository(db),
    );
    expect(await contacts.getContact(peer.peerId), isNull);
    expect(
      (await db.query(
        'contact_relationship_consent',
        where: 'peer_id = ?',
        whereArgs: [peer.peerId],
      )).single['state'],
      'withdrawn',
    );
  }

  Future<HandleMessageResult> receive({
    String? ts,
    String intent = 'new_request',
  }) async {
    final wire = await buildRepairWire(
      bus: bus,
      signer: peer,
      recipientPublicKey: local.publicKey,
      ts: ts,
      intent: intent,
    );
    final (result, _, _) = await handleIncomingMessage(
      message: wire,
      bridge: bridge,
      requestRepo: buildWidgetRequestRepository(db),
      contactRepo: databaseContactRepository(db),
      ownPeerId: local.peerId,
      ownPrivateKey: local.privateKey,
      ownAccountPublicKey: local.publicKey,
      repairRepository: SqlContactRepairRepository(db),
    );
    return result;
  }

  test(
    'local withdrawal and signed QR readd survive private diagnostic export',
    () async {
      await withdraw();
      final identities = buildWidgetIdentityRepository(
        db,
        FakeSecureKeyStore(),
      );
      final (built, qr) = await buildQRPayload(
        repo: identities,
        cachedIdentity: testIdentityModel(peer, username: privateName),
        callSign: (data, _) async => {
          'ok': true,
          'signature': peer.signBase64(data),
        },
      );
      expect(built, BuildQRPayloadResult.success);
      final (parsed, contact) = await parseQRPayload(
        qrString: qr!,
        bridge: bridge,
        ownPeerId: local.peerId,
      );
      expect(parsed, ParseQRResult.success);
      expect(
        await addContact(
          repository: databaseContactRepository(db),
          contact: contact!,
        ),
        AddContactResult.success,
      );
      // Supersedes the initial 'withdrawn' diagnostic expectation: purge
      // deletedContact proves absence only. withdraw() separately proves the
      // SQL consent transition; telemetry cannot assume it without a read.
      await expectEvent('local_action', 'unknown', 'withdraw', 'committed');
      await expectEvent('local_action', 'active', 'local_add', 'committed');
    },
  );

  test(
    'mutual introduction readd emits local activation without private content',
    () async {
      await withdraw();
      final added = await handleMutualAcceptance(
        introduction: IntroductionModel(
          id: privateIntro,
          introducerId: 'PRIVATE_INTRODUCER_PEER',
          recipientId: local.peerId,
          introducedId: peer.peerId,
          recipientStatus: IntroductionStatus.accepted,
          introducedStatus: IntroductionStatus.accepted,
          status: IntroductionOverallStatus.mutualAccepted,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          introducedUsername: privateName,
          introducedPublicKey: peer.publicKey,
        ),
        contactRepo: databaseContactRepository(db),
        ownPeerId: local.peerId,
      );
      expect(added?.peerId, peer.peerId);
      await expectEvent(
        'local_action',
        'active',
        'mutual_intro_add',
        'committed',
      );
    },
  );

  test(
    'live automatic eligibility differs from stored pending replay',
    () async {
      expect(await receive(), HandleMessageResult.contactAutoAdded);
      final listener = ContactRequestListener(
        contactRequestStream: const Stream<ChatMessage>.empty(),
        requestRepo: buildWidgetRequestRepository(db),
        contactRepo: databaseContactRepository(db),
        bridge: bridge,
        getOwnPeerId: () => local.peerId,
        getOwnPrivateKey: () async => local.privateKey,
        repairRepository: SqlContactRepairRepository(db),
        downloadProfilePictureFn:
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
              bool retryPendingRequest = false,
            }) async => contactFor(peer),
      );
      try {
        final replay = await listener.requestStream.first.timeout(
          const Duration(seconds: 5),
        );
        expect(replay.peerId, peer.peerId);
        await expectEvent('live', 'none', 'admit', 'automatic');
        await expectEvent('stored_replay', 'unknown', 'replay', 'pending');
      } finally {
        listener.dispose();
      }
    },
  );

  test(
    'withdrawn fresh request is ignored regardless of outer intent',
    () async {
      await withdraw();
      final consent = (await SqlContactRepairRepository(
        db,
      ).readConsent(peer.peerId))!;
      final fresh = DateTime.fromMillisecondsSinceEpoch(
        consent.updatedAtMs + 1,
        isUtc: true,
      ).toIso8601String();
      expect(
        await receive(ts: fresh, intent: 'PRIVATE_UNSIGNED_HUMAN_INTENT'),
        HandleMessageResult.invalidMessage,
      );
      await expectEvent('live', 'withdrawn', 'admit', 'ignored');
      expect(
        await diagnostics.exportPreview(),
        isNot(contains('PRIVATE_UNSIGNED_HUMAN_INTENT')),
      );
    },
  );

  test(
    'predecision replay reports ignored with durable withdrawn consent',
    () async {
      await withdraw();
      final consent = (await SqlContactRepairRepository(
        db,
      ).readConsent(peer.peerId))!;
      final old = DateTime.fromMillisecondsSinceEpoch(
        consent.updatedAtMs,
        isUtc: true,
      ).toIso8601String();
      expect(await receive(ts: old), HandleMessageResult.invalidMessage);
      expect(
        await buildWidgetRequestRepository(db).getPendingRequests(),
        isEmpty,
      );
      await expectEvent('live', 'withdrawn', 'admit', 'ignored');
    },
  );

  test(
    'fresh request after decline records declined manual consent class',
    () async {
      final requests = buildWidgetRequestRepository(db);
      await requests.addRequest(
        ContactRequestModel(
          peerId: peer.peerId,
          publicKey: peer.publicKey,
          rendezvous: repairRendezvous,
          username: privateName,
          signature: 'PRIVATE_PREVIOUS_SIGNATURE',
          receivedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      await requests.updateStatus(peer.peerId, ContactRequestStatus.declined);
      final consent = (await SqlContactRepairRepository(
        db,
      ).readConsent(peer.peerId))!;
      final fresh = DateTime.fromMillisecondsSinceEpoch(
        consent.updatedAtMs + 1,
        isUtc: true,
      ).toIso8601String();
      expect(await receive(ts: fresh), HandleMessageResult.contactRequest);
      await expectEvent('live', 'declined', 'admit', 'pending');
      expect(
        await diagnostics.exportPreview(),
        isNot(contains('PRIVATE_PREVIOUS_SIGNATURE')),
      );
    },
  );

  test(
    'deleting a never-existing contact reports unknown, not withdrawal history',
    () async {
      await deleteContactAndMessages(
        contactRepo: _purgingContacts(db),
        messageRepo: InMemoryMessageRepository(),
        peerId: peer.peerId,
      );
      expect(await db.query('contact_relationship_consent'), isEmpty);
      await expectEvent('local_action', 'unknown', 'withdraw', 'committed');
      final events = await exported();
      expect(
        events.map((event) => (event['values'] as Map)['consentClass']),
        isNot(contains('withdrawn')),
      );
    },
  );

  test(
    'committed withdrawal stays observable when later reconciliation fails',
    () async {
      final contacts = _purgingContacts(db);
      await contacts.addContact(contactFor(peer));
      await expectLater(
        deleteContactAndMessages(
          contactRepo: contacts,
          messageRepo: _FailingPurgeReconciliation(),
          peerId: peer.peerId,
        ),
        throwsStateError,
      );
      expect(await contacts.getContact(peer.peerId), isNull);
      expect(
        (await db.query(
          'contact_relationship_consent',
          where: 'peer_id = ?',
          whereArgs: [peer.peerId],
        )).single['state'],
        'withdrawn',
      );
      await expectEvent('local_action', 'unknown', 'withdraw', 'committed');
    },
  );
}

// Match the foreground composition's final-purge capability, including its
// final-absence result. It cannot prove prior existence; delegates remain SQL.
ContactRepositoryImpl _purgingContacts(Database db) {
  final sql = databaseContactRepository(db);
  return ContactRepositoryImpl(
    dbLoadAllContacts: sql.dbLoadAllContacts,
    dbLoadContact: sql.dbLoadContact,
    dbUpsertContact: sql.dbUpsertContact,
    dbDeleteContact: sql.dbDeleteContact,
    dbGetContactCount: sql.dbGetContactCount,
    dbContactExists: sql.dbContactExists,
    dbArchiveContact: sql.dbArchiveContact,
    dbUnarchiveContact: sql.dbUnarchiveContact,
    dbLoadActiveContacts: sql.dbLoadActiveContacts,
    dbLoadArchivedContacts: sql.dbLoadArchivedContacts,
    dbBlockContact: sql.dbBlockContact,
    dbUnblockContact: sql.dbUnblockContact,
    dbDismissIntroBanner: sql.dbDismissIntroBanner,
    dbSetIntrosSentAt: sql.dbSetIntrosSentAt,
    dbPurgeDirectContactConversationAndContact: (peerId) async {
      final result = await dbPurgeDirectContactConversationAndContact(
        db,
        peerId,
      );
      return DirectContactConversationPurgeSummary(
        deletedTextCustodyRows: result.deletedTextCustodyRows,
        deletedEventCustodyRows: result.deletedEventCustodyRows,
        deletedReactions: result.deletedReactions,
        deletedMessages: result.deletedMessages,
        deletedContact: result.deletedContact,
      );
    },
  );
}

class _FailingPurgeReconciliation extends InMemoryMessageRepository
    implements DirectContactPurgeReconciliation {
  @override
  Future<void> reconcileDirectContactConversationPurge(String peerId) async {
    throw StateError('PRIVATE_RECONCILIATION_ERROR');
  }
}
