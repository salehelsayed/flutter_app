import 'dart:io';

import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';
import '../support/contact_repair_harness.dart';

// Task 12b listener duties: the inbound ACK follows the durable reservation
// and never waits for the reply send; a full queue withholds the ACK and stays
// retryable; concurrent copies on independent handles converge on one reply.

final _bus = Ed25519ContactRequestCryptoBus();
final _self = TestEd25519Identity.fromSeedByte(0x61);
final _peer = TestEd25519Identity.fromSeedByte(0x62);

ContactRequestListener _listener(
  Database db,
  Ed25519ContactRequestBridge bridge, {
  void Function()? onQueued,
}) => ContactRequestListener(
  contactRequestStream: const Stream<ChatMessage>.empty(),
  requestRepo: InMemoryContactRequestRepository(),
  contactRepo: databaseContactRepository(db),
  bridge: bridge,
  getOwnPeerId: () => _self.peerId,
  getOwnPrivateKey: () async => _self.privateKey,
  getOwnPublicKey: () async => _self.publicKey,
  repairRepository: SqlContactRepairRepository(db),
  onRepairReplyQueued: onQueued,
);

Future<ChatMessage> _marked({String? confirmNonce}) => buildRepairWire(
  bus: _bus,
  signer: _peer,
  recipientPublicKey: _self.publicKey,
  signedControl: newRequestControl(to: _self.peerId),
  confirmNonce: confirmNonce,
);

List<Map<String, dynamic>> _confirms(Ed25519ContactRequestBridge bridge) =>
    bridge.commands
        .where((c) => c['cmd'] == 'message:confirm')
        .map((c) => c['payload'] as Map<String, dynamic>)
        .toList();

void main() {
  setUpAll(() {
    _bus
      ..register(_self)
      ..register(_peer);
  });

  late Database db;
  setUp(() async {
    db = await openRepairTestDatabase();
    await databaseContactRepository(db).addContact(contactFor(_peer));
  });
  tearDown(() => db.close());

  test('the direct ACK is released after the reservation is durable and '
      'before the reply is sent', () async {
    final bridge = Ed25519ContactRequestBridge(_bus);
    final order = <String>[];
    var reservedAtAck = -1;
    final listener = _listener(db, bridge, onQueued: () => order.add('queued'));
    addTearDown(listener.dispose);

    final message = await _marked(confirmNonce: 'nonce-1');
    bridge.onCommand = (command) {
      if (command['cmd'] == 'message:confirm') {
        order.add('ack');
        db
            .query('contact_repair_requests')
            .then((rows) => reservedAtAck = rows.length);
      }
    };
    final result = await listener.processIncomingMessage(message);
    await Future<void>.delayed(Duration.zero);

    expect(result, HandleMessageResult.alreadyContact);
    expect(order, ['ack', 'queued']);
    expect(reservedAtAck, 1);
    expect(_confirms(bridge).single, {'nonce': 'nonce-1', 'ok': true});
    expect(
      bridge.encrypts,
      isEmpty,
      reason: 'the listener never sends the reply',
    );
  });

  test(
    'a full queue withholds the ACK, reserves nothing and stays retryable',
    () async {
      final bridge = Ed25519ContactRequestBridge(_bus);
      final listener = _listener(db, bridge);
      addTearDown(listener.dispose);
      for (var i = 0; i < 4; i++) {
        await listener.processIncomingMessage(await _marked());
      }
      expect(await db.query('contact_repair_requests'), hasLength(4));

      final fifth = await _marked(confirmNonce: 'nonce-full');
      await expectLater(
        listener.processIncomingMessage(fifth),
        throwsA(isA<ContactRepairDeferredException>()),
      );
      expect(_confirms(bridge).last, {'nonce': 'nonce-full', 'ok': false});
      expect(await db.query('contact_repair_requests'), hasLength(4));

      // Capacity frees; the SAME message is accepted on redelivery (it was not
      // remembered as a replay).
      await db.update('contact_repair_requests', {'state': 'completed'});
      expect(
        await listener.processIncomingMessage(fifth),
        HandleMessageResult.alreadyContact,
      );
      expect(await db.query('contact_repair_requests'), hasLength(5));
    },
  );

  test('the same request delivered live and from the inbox to two listeners '
      'on independent handles reserves one reply', () async {
    final dir = await Directory.systemTemp.createTemp('repair_listeners');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/account.db';
    final h1 = await openRepairTestDatabase(path);
    final h2 = await openRepairTestDatabase(path);
    addTearDown(() async {
      await h1.close();
      await h2.close();
    });
    await databaseContactRepository(h1).addContact(contactFor(_peer));
    final live = _listener(h1, Ed25519ContactRequestBridge(_bus));
    final inbox = _listener(h2, Ed25519ContactRequestBridge(_bus));
    addTearDown(live.dispose);
    addTearDown(inbox.dispose);
    final message = await _marked();

    Future<Object?> deliver(ContactRequestListener l) => l
        .processIncomingMessage(message)
        .then<Object?>((r) => r, onError: (Object e) => e);
    final first = await Future.wait([deliver(live), deliver(inbox)]);
    // A copy that lost the write race is retryable (inbox redelivery).
    for (var i = 0; i < 2; i++) {
      if (first[i] is! HandleMessageResult) {
        await (i == 0 ? live : inbox).processIncomingMessage(message);
      }
    }
    expect(await h1.query('contact_repair_requests'), hasLength(1));
  });
}
