import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';

// ---------------------------------------------------------------------------
// 171 TC-08: one-scan mutual convergence (two live listeners over a fake net).
//
// A scans B (A pre-adds B locally + sends a v2 request). B's LIVE listener
// auto-adds A tap-free and reciprocates. A's listener receives the reciprocal,
// sees B is already a contact (alreadyContact), and issues ZERO reciprocals —
// the loop terminates. Each side ends with exactly one contact row (INV-4).
//
// NOTE: this is NOT the cold-B subscribe-race proof (two synchronous listeners
// can't reproduce the unbuffered-broadcast drop). That is TC-04/TC-14/TC-13.
// ---------------------------------------------------------------------------

const _aPeerId = '12D3KooWAaaaScannerPeerId0001';
const _bPeerId = '12D3KooWBbbbScannedPeerId0002';

class _StaticDecryptBridge extends Bridge {
  _StaticDecryptBridge(this.incomingPayload);
  final Map<String, dynamic> incomingPayload;

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
    final req = jsonDecode(message) as Map<String, dynamic>;
    switch (req['cmd']) {
      case 'contactrequest.decrypt':
        return jsonEncode({'ok': true, 'plaintext': jsonEncode(incomingPayload)});
      case 'payload.verify':
        return jsonEncode({'ok': true, 'valid': true});
      default:
        return jsonEncode({'ok': true});
    }
  }
}

Map<String, dynamic> _payloadFor(String peerId) => {
  'ns': peerId,
  'pk': 'pk-$peerId',
  'rv': '/dns4/relay.example/tcp/4001/p2p/$peerId',
  'ts': DateTime.now().toUtc().toIso8601String(),
  'sig': 'sig-$peerId',
  'un': 'User-$peerId',
};

ChatMessage _v2RequestFrom(String fromPeerId) => ChatMessage(
  from: fromPeerId,
  to: 'recipient',
  content: jsonEncode({
    'type': 'contact_request',
    'version': '2',
    'msgId': 'cr-$fromPeerId-${DateTime.now().microsecondsSinceEpoch}',
    'ts': DateTime.now().toUtc().toIso8601String(),
    'encrypted': {'ephemeralPublicKey': 'e', 'ciphertext': 'c', 'nonce': 'n'},
  }),
  timestamp: DateTime.now().toUtc().toIso8601String(),
  isIncoming: true,
);

void main() {
  test('B fresh auto-adds A and reciprocates; A no loop; one row each', () async {
    // --- A: already has B as a contact (A scanned B) ---
    final aContacts = InMemoryContactRepository();
    final aRequests = InMemoryContactRequestRepository();
    aContacts.addTestContact(
      ContactModel(
        peerId: _bPeerId,
        publicKey: 'pk-$_bPeerId',
        rendezvous: '/dns4/relay.example/tcp/4001/p2p/$_bPeerId',
        username: 'User-$_bPeerId',
        signature: 'sig-$_bPeerId',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    // A's bridge decrypts B's (reciprocal) payload.
    final aBridge = _StaticDecryptBridge(_payloadFor(_bPeerId));

    // --- B: cold, knows nobody ---
    final bContacts = InMemoryContactRepository();
    final bRequests = InMemoryContactRequestRepository();
    // B's bridge decrypts A's (initial) payload.
    final bBridge = _StaticDecryptBridge(_payloadFor(_aPeerId));

    var aReciprocalCount = 0;
    var bReciprocalCount = 0;

    late final ContactRequestListener aListener;

    aListener = ContactRequestListener(
      contactRequestStream: const Stream.empty(),
      requestRepo: aRequests,
      contactRepo: aContacts,
      bridge: aBridge,
      getOwnPeerId: () => _aPeerId,
      getOwnPrivateKey: () async => 'a-priv',
      // A must NEVER reciprocate B's reciprocal (B is already a contact).
      autoAcceptAndReciprocate: (peerId) async {
        aReciprocalCount++;
        return AcceptContactRequestResult.success;
      },
    );

    final bListener = ContactRequestListener(
      contactRequestStream: const Stream.empty(),
      requestRepo: bRequests,
      contactRepo: bContacts,
      bridge: bBridge,
      getOwnPeerId: () => _bPeerId,
      getOwnPrivateKey: () async => 'b-priv',
      // B accepts A + reciprocates (mimics acceptAndReciprocate: local add +
      // deliver a reciprocal v2 request to A's live listener).
      autoAcceptAndReciprocate: (peerId) async {
        bReciprocalCount++;
        final req = await bRequests.getRequest(peerId);
        if (req != null) {
          await bContacts.addContact(req.toContactModel());
          await bRequests.updateStatus(peerId, ContactRequestStatus.accepted);
        }
        // Reciprocal B -> A over the fake net.
        await aListener.processIncomingMessage(_v2RequestFrom(_bPeerId));
        return AcceptContactRequestResult.success;
      },
    );

    addTearDown(aListener.dispose);
    addTearDown(bListener.dispose);

    // A -> B initial request lands on B's live listener.
    final bResult = await bListener.processIncomingMessage(
      _v2RequestFrom(_aPeerId),
    );

    expect(bResult, equals(HandleMessageResult.contactAutoAdded));
    // B is now mutual with A (one row), tap-free.
    expect(await bContacts.contactExists(_aPeerId), isTrue);
    expect((await bContacts.getAllContacts()).length, equals(1));
    // A still has exactly one contact (B) — unchanged.
    expect(await aContacts.contactExists(_bPeerId), isTrue);
    expect((await aContacts.getAllContacts()).length, equals(1));
    // INV-4: B reciprocated once; A issued ZERO reciprocals (loop terminates).
    expect(bReciprocalCount, equals(1));
    expect(aReciprocalCount, equals(0));
  });
}

// HandleMessageResult is re-exported via the listener's use-case import.
