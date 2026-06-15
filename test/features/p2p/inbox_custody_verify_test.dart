// 124 Phase 8 — inbox_custody_verify end-to-end coverage.
//
// Closes the audit gap: the relay-inbox custody contract has two halves that
// must hold together —
//
//   (1) SENDER custody verify: `verifyInboxCustody` re-stores the stored
//       envelope against the relay and CONFIRMS the relay still holds the copy
//       ('duplicate'/'stored'), keeping the row 'inboxed' until a real receipt
//       lands. If the relay no longer holds it, custody is SURFACED as lost
//       (downgraded to 'sent').
//
//   (2) RECEIVER ack-gated delete: the relay deletes an inbox entry ONLY after
//       the receiver has durably staged it AND acked it (`inbox:ack`). A plain
//       retrieve (retrieve_pending) leaves the relay copy in place; the delete
//       is strictly post-ack.
//
// This test wires the REAL `verifyInboxCustody` use case (sender) and the REAL
// `P2PServiceImpl` drain→stage→ack pipeline (receiver) against one shared
// ack-gated relay double, and asserts the relay deletes the entry ONLY after
// the receiver acks — never on the sender's custody re-store, never on a bare
// retrieve.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/application/verify_inbox_custody_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../conversation/domain/repositories/fake_message_repository.dart';

/// Minimal ack-gated relay double shared by both sides of the contract.
///
/// Models the production relay (`go-relay-server/inbox.go`): an entry is
/// retained on `store` and on `retrievePending`, and removed ONLY by `ack`.
/// A re-store of an already-held entry answers `duplicate` (custody confirmed),
/// exactly like the real InboxBackend dedup.
class _AckGatedRelay {
  // entryId -> {from, message, timestamp}
  final Map<String, Map<String, dynamic>> _entries = {};
  // Stable entry id keyed by the wire-message bytes, so a re-store of the same
  // envelope is recognised as a duplicate of the still-held entry.
  final Map<String, String> _entryIdByMessage = {};
  int _seq = 0;

  int get heldCount => _entries.length;
  bool holds(String entryId) => _entries.containsKey(entryId);

  /// Sender store path (also the custody-verify re-store path).
  InboxStoreOutcome store(String toPeerId, String message) {
    final existing = _entryIdByMessage[message];
    if (existing != null && _entries.containsKey(existing)) {
      // Relay still holds the copy — custody is intact.
      return const InboxStoreOutcome(
        status: InboxStoreStatus.duplicate,
        storeStatus: 'duplicate',
      );
    }
    final entryId = 'entry-${_seq++}';
    _entries[entryId] = {
      'from': 'remote-sender',
      'message': message,
      'timestamp': '2026-06-13T00:00:00.000Z',
    };
    _entryIdByMessage[message] = entryId;
    return const InboxStoreOutcome(
      status: InboxStoreStatus.stored,
      storeStatus: 'stored',
    );
  }

  /// Receiver retrieve path — relay KEEPS the entries (pending), never deletes.
  List<Map<String, dynamic>> retrievePending() {
    return _entries.entries
        .map((e) => {'id': e.key, ...e.value})
        .toList(growable: false);
  }

  /// The ONLY delete path — strictly post-ack.
  int ack(List<String> entryIds) {
    var removed = 0;
    for (final id in entryIds) {
      if (_entries.remove(id) != null) removed++;
    }
    return removed;
  }
}

/// Bridge double that routes the receiver's inbox commands to [_AckGatedRelay].
class _RelayBackedBridge extends Bridge {
  final _AckGatedRelay relay;
  final List<String> calledCommands = [];
  bool _initialized = false;

  _RelayBackedBridge(this.relay);

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async => _initialized = true;

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;
    final payload = request['payload'] as Map<String, dynamic>?;
    calledCommands.add(cmd);

    switch (cmd) {
      case 'node:start':
        return jsonEncode({
          'ok': true,
          'peerId': 'self-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': [],
          'connections': [],
        });
      case 'inbox:retrieve_pending':
        return jsonEncode({
          'ok': true,
          'messages': relay.retrievePending(),
          'hasMore': false,
        });
      case 'inbox:ack':
        final ids =
            (payload?['entryIds'] as List?)?.cast<String>() ?? const [];
        return jsonEncode({'ok': true, 'acked': relay.ack(ids)});
      default:
        return jsonEncode({
          'ok': false,
          'errorCode': 'UNHANDLED',
          'errorMessage': 'no handler for $cmd',
        });
    }
  }
}

ConversationMessage _inboxedSenderRow({
  required String id,
  required String wireEnvelope,
}) {
  final base = DateTime.utc(2026, 6, 13, 10);
  return ConversationMessage(
    id: id,
    contactPeerId: 'self-peer',
    senderPeerId: 'remote-sender',
    text: 'awaiting receipt',
    timestamp: base.toIso8601String(),
    status: 'inboxed',
    isIncoming: false,
    createdAt: base.toIso8601String(),
    transport: 'inbox',
    wireEnvelope: wireEnvelope,
    // null relay_expires_at => every sweep re-proves custody (old-relay path).
    relayExpiresAt: null,
  );
}

void main() {
  group('inbox custody verify + ack-gated relay delete (end-to-end)', () {
    // A real chat envelope the relay holds for the offline receiver.
    final envelope = jsonEncode({
      'type': 'chat_message',
      'version': '1',
      'payload': {
        'id': 'msg-custody-e2e',
        'text': 'hello while offline',
        'senderPeerId': 'remote-sender',
        'senderUsername': 'Alice',
        'timestamp': '2026-06-13T00:00:00.000Z',
      },
    });

    late _AckGatedRelay relay;
    late FakeMessageRepository messageRepo;
    late ConversationMessage senderRow;
    late List<({String id, int? expiresAtMs})> custodyMarks;

    setUp(() {
      relay = _AckGatedRelay();
      messageRepo = FakeMessageRepository();
      custodyMarks = [];
      senderRow = _inboxedSenderRow(id: 'msg-custody-e2e', wireEnvelope: envelope);
      messageRepo.seed([senderRow]);
      // The sender originally stored the envelope at relay; it is now held.
      expect(relay.store('self-peer', envelope).status, InboxStoreStatus.stored);
      expect(relay.heldCount, 1);
    });

    Future<int> runCustodyVerify() {
      return verifyInboxCustody(
        loadInboxCustody: ({required Duration recheckOlderThan}) async =>
            [senderRow],
        storeInInboxDetailed: (toPeerId, message, {int? timeoutMs}) async =>
            relay.store(toPeerId, message),
        markCustodyChecked: (messageId, {int? relayExpiresAtMs}) async {
          custodyMarks.add((id: messageId, expiresAtMs: relayExpiresAtMs));
        },
        messageRepo: messageRepo,
      );
    }

    test(
      'sender custody verify CONFIRMS the relay copy and keeps the row inboxed; '
      'the relay copy is NOT deleted by the custody re-store',
      () async {
        final checked = await runCustodyVerify();

        expect(checked, 1, reason: 'the held row was re-checked');
        // Re-store hit a still-held entry -> duplicate -> custody confirmed.
        expect(custodyMarks.single.id, 'msg-custody-e2e');
        // Row stays inboxed (still awaiting the receiver receipt).
        expect((await messageRepo.getMessage('msg-custody-e2e'))!.status, 'inboxed');
        // The custody re-store must NEVER delete the relay copy.
        expect(
          relay.heldCount,
          1,
          reason: 'custody verify proves custody, it does not consume it',
        );
      },
    );

    test(
      'the relay deletes the entry ONLY after the receiver stages + acks; '
      'a bare retrieve_pending does not delete',
      () async {
        // Receiver custody verify still passes BEFORE the receiver acks: the
        // relay holds the copy, so the sender keeps the row inboxed.
        await runCustodyVerify();
        expect(relay.heldCount, 1);

        // --- Receiver drains: real P2PServiceImpl stage -> ack pipeline ---
        final bridge = _RelayBackedBridge(relay);
        final stagingRepo = InMemoryInboxStagingRepository();
        final replayed = <String>[];
        final receiver = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: stagingRepo,
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                final payload =
                    (jsonDecode(message.content) as Map<String, dynamic>)['payload']
                        as Map<String, dynamic>;
                replayed.add(payload['id'] as String);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'stored',
                  reasonDetail: null,
                );
              },
        );
        addTearDown(receiver.dispose);

        await receiver.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await receiver.drainOfflineInbox();

        // The receiver retrieved (pending), staged durably, then ACKed.
        expect(bridge.calledCommands, contains('inbox:retrieve_pending'));
        expect(bridge.calledCommands, contains('inbox:ack'));
        expect(replayed, ['msg-custody-e2e']);

        // The ack MUST come AFTER the retrieve — delete is strictly post-receive.
        final retrieveIdx = bridge.calledCommands.indexOf('inbox:retrieve_pending');
        final ackIdx = bridge.calledCommands.indexOf('inbox:ack');
        expect(
          ackIdx,
          greaterThan(retrieveIdx),
          reason: 'delete (ack) only after the receiver has the message',
        );

        // The relay copy is gone ONLY now — deleted by the ack, not the retrieve.
        expect(
          relay.heldCount,
          0,
          reason: 'ack is the only delete path; it ran post-stage',
        );
      },
    );

    test(
      'gate denial at the ACK boundary keeps the relay copy alive '
      '(no ack -> no delete), and custody verify still confirms it',
      () async {
        final bridge = _RelayBackedBridge(relay);
        final stagingRepo = InMemoryInboxStagingRepository();
        // Block the post-stage ack (mirrors a Move Account export pause).
        const blockedOp = 'p2p_inbox_ack_after_stage';
        final receiver = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: stagingRepo,
          accountMigrationNetworkGate: ({peerId, required operation}) async =>
              operation != blockedOp,
        );
        addTearDown(receiver.dispose);

        await receiver.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await receiver.drainOfflineInbox();

        // Staged, but the ACK boundary was gated -> relay never acked.
        expect(bridge.calledCommands, contains('inbox:retrieve_pending'));
        expect(bridge.calledCommands, isNot(contains('inbox:ack')));
        expect(
          relay.heldCount,
          1,
          reason: 'no ack means no delete — the copy survives for the new phone',
        );

        // Because the relay still holds it, the sender custody verify continues
        // to confirm custody (duplicate) and keeps the row inboxed.
        final checked = await runCustodyVerify();
        expect(checked, 1);
        expect((await messageRepo.getMessage('msg-custody-e2e'))!.status, 'inboxed');
      },
    );

    test(
      'when the relay has lost the copy (no entry held), custody verify '
      'SURFACES the loss by downgrading the row to sent',
      () async {
        // Simulate a relay that dropped the entry (TTL prune / full) and now
        // reports the re-store as failed/rejected rather than duplicate.
        final lossRelay = _AckGatedRelay(); // empty -> no held copy
        final restored = await verifyInboxCustody(
          loadInboxCustody: ({required Duration recheckOlderThan}) async =>
              [senderRow],
          storeInInboxDetailed: (toPeerId, message, {int? timeoutMs}) async {
            // Relay full: cannot re-accept, custody is genuinely lost.
            return const InboxStoreOutcome(
              status: InboxStoreStatus.rejectedFull,
              errorCode: 'INBOX_FULL',
            );
          },
          markCustodyChecked: (messageId, {int? relayExpiresAtMs}) async {
            custodyMarks.add((id: messageId, expiresAtMs: relayExpiresAtMs));
          },
          messageRepo: messageRepo,
        );

        expect(restored, 1);
        expect(lossRelay.heldCount, 0);
        final after = await messageRepo.getMessage('msg-custody-e2e');
        expect(
          after!.status,
          'sent',
          reason: 'lost custody must be surfaced as non-delivered, not inboxed',
        );
        expect(after.wireEnvelope, isNotNull);
      },
    );
  });
}
