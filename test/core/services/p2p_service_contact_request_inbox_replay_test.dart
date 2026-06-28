import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

import '../../shared/fakes/in_memory_contact_repository.dart';
import '../../shared/fakes/in_memory_contact_request_repository.dart';
import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

// ---------------------------------------------------------------------------
// 171: cold-receiver relay-inbox replay of a contact_request must reach the
// SAME mutual outcome (durable add + reciprocal) as the live broadcast — and
// persist BEFORE the staged entry is deleted (INV-1). These are the host
// closure tests for the dominant bug.
// ---------------------------------------------------------------------------

const _ownPeerId = '12D3KooWSelfBReceiverPeerId00';
const _aPeerId = '12D3KooWScannerAPeerId1234567';

/// Self-contained bridge: handles node lifecycle + an inbox drain that finds
/// nothing on the relay, and the contact-request decrypt/verify the listener
/// needs. [decryptPlaintext] is the JSON payload the next decrypt returns.
class _FakeBridge extends Bridge {
  String decryptPlaintext = '';
  bool verifyValid = true;
  final List<String> commandLog = [];

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
    final cmd = req['cmd'] as String?;
    commandLog.add(cmd ?? '');
    switch (cmd) {
      case 'node:start':
        return jsonEncode({
          'ok': true,
          'peerId': _ownPeerId,
          'isStarted': true,
          'listenAddresses': <String>[],
          'circuitAddresses': <String>[],
          'connections': <dynamic>[],
          'relayState': 'offline',
          'healthyRelayCount': 0,
        });
      case 'inbox:retrieve':
        return jsonEncode({'ok': true, 'messages': [], 'hasMore': false});
      case 'inbox:ack':
        return jsonEncode({'ok': true, 'acked': 1});
      case 'contactrequest.decrypt':
        return jsonEncode({'ok': true, 'plaintext': decryptPlaintext});
      case 'payload.verify':
        return jsonEncode({'ok': true, 'valid': verifyValid});
      default:
        return jsonEncode({'ok': true});
    }
  }
}

/// Records addContact ordering + count against a shared call-log.
class _RecordingContactRepo extends InMemoryContactRepository {
  _RecordingContactRepo(this.log);
  final List<String> log;
  int addContactCount = 0;

  @override
  Future<void> addContact(ContactModel contact) async {
    addContactCount++;
    log.add('addContact:${contact.peerId}');
    await super.addContact(contact);
  }
}

/// Records addRequest ordering against a shared call-log.
class _RecordingRequestRepo extends InMemoryContactRequestRepository {
  _RecordingRequestRepo(this.log);
  final List<String> log;

  @override
  Future<void> addRequest(ContactRequestModel request) async {
    log.add('addRequest:${request.peerId}');
    await super.addRequest(request);
  }
}

/// Records deleteEntry ordering against a shared call-log.
class _DeleteSpyStagingRepo extends InMemoryInboxStagingRepository {
  _DeleteSpyStagingRepo(this.log);
  final List<String> log;

  @override
  Future<void> deleteEntry(String entryId) async {
    log.add('deleteEntry:$entryId');
    await super.deleteEntry(entryId);
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

String _v2Envelope(String peerId, {String? msgId}) => jsonEncode({
  'type': 'contact_request',
  'version': '2',
  'msgId': msgId ?? 'cr-$peerId',
  'ts': DateTime.now().toUtc().toIso8601String(),
  'encrypted': {
    'ephemeralPublicKey': 'e',
    'ciphertext': 'c',
    'nonce': 'n',
  },
});

InboxStagingEntry _contactRequestEntry(
  String fromPeerId, {
  String entryId = 'relay:cr-1',
  String? msgId,
}) => InboxStagingEntry(
  entryId: entryId,
  ownerPeerId: _ownPeerId,
  senderPeerId: fromPeerId,
  relayTimestamp: DateTime.now().toUtc().toIso8601String(),
  envelope: _v2Envelope(fromPeerId, msgId: msgId),
  stagedAt: DateTime.now().toUtc().toIso8601String(),
  messageType: 'contact_request',
);

void main() {
  late _FakeBridge bridge;
  late List<String> callLog;
  late _RecordingRequestRepo requestRepo;
  late _RecordingContactRepo contactRepo;
  late _DeleteSpyStagingRepo staging;
  late List<String> reciprocals;
  late P2PServiceImpl service;
  late ContactRequestListener listener;

  /// Builds the listener + service wired exactly like main.dart: the inbox arm
  /// routes through the REAL ContactRequestListener.processIncomingMessage, and
  /// auto-accept is the injected seam that adds the contact + fires the
  /// reciprocal (the production binding is acceptAndReciprocate).
  void wire() {
    listener = ContactRequestListener(
      contactRequestStream: const Stream.empty(),
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => _ownPeerId,
      getOwnPrivateKey: () async => 'ownPrivKeyBase64',
      autoAcceptAndReciprocate: (peerId) async {
        reciprocals.add(peerId);
        final req = await requestRepo.getRequest(peerId);
        if (req != null) {
          // mimic acceptAndReciprocate's local add + status flip
          await contactRepo.addContact(req.toContactModel());
          await requestRepo.updateStatus(
            peerId,
            ContactRequestStatus.accepted,
          );
        }
        return AcceptContactRequestResult.success;
      },
    );

    service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: staging,
      replayRecoveredInboxContactRequest: (message) async {
        try {
          await listener.processIncomingMessage(message);
          return (
            disposition: RecoveredInboxChatDisposition.committed,
            reasonCode: 'contact_request_processed',
            reasonDetail: null,
          );
        } catch (e) {
          return (
            disposition: RecoveredInboxChatDisposition.retryable,
            reasonCode: 'contact_request_processing_error',
            reasonDetail: e.toString(),
          );
        }
      },
    );
  }

  Future<void> startNode() async {
    await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', _ownPeerId);
  }

  setUp(() {
    bridge = _FakeBridge();
    callLog = <String>[];
    reciprocals = <String>[];
    requestRepo = _RecordingRequestRepo(callLog);
    contactRepo = _RecordingContactRepo(callLog);
    staging = _DeleteSpyStagingRepo(callLog);
    bridge.decryptPlaintext = jsonEncode(_payloadFor(_aPeerId));
    wire();
  });

  tearDown(() {
    listener.dispose();
    service.dispose();
  });

  int firstIndexWithPrefix(String prefix) =>
      callLog.indexWhere((e) => e.startsWith(prefix));

  // TC-04: the drained contact_request DURABLY PERSISTS (a real addRequest
  // write) BEFORE deleteEntry — a flow event alone is not accepted as proof.
  test('drained contact_request durably persists before deleteEntry', () async {
    await startNode();
    staging.seed(_contactRequestEntry(_aPeerId));

    await service.drainOfflineInbox();

    final addRequestIdx = firstIndexWithPrefix('addRequest:');
    final deleteIdx = firstIndexWithPrefix('deleteEntry:');
    expect(addRequestIdx, greaterThanOrEqualTo(0),
        reason: 'a durable request write must occur');
    expect(deleteIdx, greaterThanOrEqualTo(0),
        reason: 'the staged entry must be deleted on commit');
    expect(addRequestIdx, lessThan(deleteIdx),
        reason: 'persist BEFORE delete (INV-1)');
  });

  // TC-14: the cold-B inbox path runs the FULL processing — a durable A-contact
  // row is written AND the reciprocal fires — BOTH before deleteEntry. This is
  // the only host test proving the cold-B (dominant-bug) recovery is mutual.
  test('cold-B inbox path auto-adds + reciprocates before deleteEntry', () async {
    await startNode();
    staging.seed(_contactRequestEntry(_aPeerId));

    await service.drainOfflineInbox();

    // Mutual: A is now a durable contact AND the reciprocal (B->A) fired.
    expect(await contactRepo.contactExists(_aPeerId), isTrue);
    expect(reciprocals, equals([_aPeerId]));

    final addContactIdx = firstIndexWithPrefix('addContact:');
    final reciprocalIdxOk = reciprocals.isNotEmpty;
    final deleteIdx = firstIndexWithPrefix('deleteEntry:');
    expect(addContactIdx, greaterThanOrEqualTo(0));
    expect(reciprocalIdxOk, isTrue);
    expect(addContactIdx, lessThan(deleteIdx),
        reason: 'the contact row must be written before the entry is deleted');
  });

  // TC-15: after a restart (FRESH listener with an empty in-memory replay
  // cache), a redelivered v2 request for an ALREADY-durable contact must NOT
  // re-add or re-reciprocate — dedup falls back to the DURABLE contact row
  // (step-8), not the volatile cache.
  test('redelivered v2 after restart does not re-add/re-reciprocate', () async {
    // A is already a durable contact (survived the restart).
    contactRepo.addTestContact(
      ContactModel(
        peerId: _aPeerId,
        publicKey: 'pk-$_aPeerId',
        rendezvous: '/dns4/relay.example/tcp/4001/p2p/$_aPeerId',
        username: 'User-$_aPeerId',
        signature: 'sig-$_aPeerId',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    await startNode();
    staging.seed(_contactRequestEntry(_aPeerId, entryId: 'relay:cr-redeliver'));

    await service.drainOfflineInbox();

    // No new contact write, no reciprocal — alreadyContact short-circuits.
    expect(contactRepo.addContactCount, equals(0));
    expect(reciprocals, isEmpty);
    // The entry is still committed (deleted) — terminal result, not retryable.
    expect(firstIndexWithPrefix('deleteEntry:'), greaterThanOrEqualTo(0));
  });

  // TC-16 Shape B: a re-sent request (from the offline null-ML-KEM retry)
  // arriving at a still-cold B is durably staged + auto-adds — the offline
  // one-scan case is eventually consistent once connectivity returns.
  test('re-sent request lands on a cold B and auto-adds', () async {
    await startNode();
    staging.seed(
      _contactRequestEntry(_aPeerId, entryId: 'relay:cr-resend', msgId: 'resend-1'),
    );

    await service.drainOfflineInbox();

    expect(await contactRepo.contactExists(_aPeerId), isTrue);
    expect(reciprocals, equals([_aPeerId]));
  });
}
