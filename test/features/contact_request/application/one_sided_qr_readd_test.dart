import 'package:flutter_app/features/contact_request/application/contact_repair_rollout.dart';
import 'package:flutter_app/features/contact_request/application/existing_contact_repair_policy.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';
import '../support/contact_repair_harness.dart';

// BL-21: the Pixel removed the iPhone and re-added it from the iPhone's QR.
// The iPhone still holds the Pixel as a full contact. Unless the iPhone sends
// its key back once, the Pixel keeps the iPhone with no ML-KEM key: calls are
// unavailable and the iPhone's messages never arrive.

final _bus = Ed25519ContactRequestCryptoBus();
final _stale = TestEd25519Identity.fromSeedByte(0xB1);
final _readder = TestEd25519Identity.fromSeedByte(0xB2);

void main() {
  setUpAll(() {
    _bus
      ..register(_stale)
      ..register(_readder);
  });

  late Database db;
  late ContactRepositoryImpl contacts;
  late SqlContactRepairRepository repair;
  final facts = <ContactRequestReceiveFacts>[];

  setUp(() async {
    db = await openRepairTestDatabase();
    contacts = databaseContactRepository(db);
    repair = SqlContactRepairRepository(db);
    facts.clear();
    await contacts.addContact(contactFor(_readder, mlKem: 'readder-mlkem'));
  });
  tearDown(() => db.close());

  test('a QR re-add from a release build makes the side that still holds '
      'the contact reply once with its key', () async {
    // What QRScannerWired sends by default (its shouldMarkContactRequest).
    final marked = await contactRepairRolloutEligible(_stale.peerId);
    final wire = await buildRepairWire(
      bus: _bus,
      signer: _readder,
      recipientPublicKey: _stale.publicKey,
      signedControl: marked ? newRequestControl(to: _stale.peerId) : null,
      mlKem: 'readder-mlkem',
    );

    final (result, _, _) = await handleIncomingMessage(
      message: wire,
      bridge: Ed25519ContactRequestBridge(_bus),
      requestRepo: InMemoryContactRequestRepository(),
      contactRepo: contacts,
      ownPeerId: _stale.peerId,
      ownPrivateKey: _stale.privateKey,
      repairRepository: repair,
      ownAccountPublicKey: _stale.publicKey,
      onReceiveFacts: facts.add,
    );

    expect(result, HandleMessageResult.alreadyContact);
    expect(
      facts.single.repairDecision,
      ExistingContactRepairDecision.claimReply,
    );
    expect(await db.query('contact_repair_requests'), hasLength(1));
  });
}
