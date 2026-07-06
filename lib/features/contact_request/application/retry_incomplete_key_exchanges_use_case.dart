import 'dart:math';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/mlkem_reannounce_marker.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/wake_token_pending_marker.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Retries sending contact requests to all contacts missing their ML-KEM key,
/// plus any contacts in the post-restore re-announce marker (P0-B).
///
/// The contacts table serves as an implicit outbox: a contact with
/// `mlKemPublicKey == null` means the key exchange never completed. The
/// re-announce marker covers the inverse case — OUR key changed and contacts
/// who already hold the old one must receive the new one. Marker entries are
/// removed only after their send succeeds, so a partial failure keeps the
/// remainder for the next trigger.
///
/// Returns the count of successfully sent requests.
Future<int> retryIncompleteKeyExchanges({
  required ContactRepository contactRepo,
  required IdentityRepository identityRepo,
  required P2PService p2pService,
  required Bridge bridge,
  SecureKeyStore? secureKeyStore,
  // FDC-09 §12 / CV-14: the read-only wake-token resolver threaded into each
  // (emission-gated) send. This is a DISTRIBUTION path only — it never mints or
  // registers (that is once-per-cycle, INV-5).
  Future<String?> Function(String peerId)? resolveWakeToken,
}) async {
  // 1. Guard: own ML-KEM key must exist (resend would be pointless without it)
  final identity = await identityRepo.loadIdentity();
  if (identity == null || identity.mlKemPublicKey == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_KEY_EXCHANGE_SKIP_NO_OWN_KEY',
      details: {},
    );
    return 0;
  }

  // 2. Guard: node must be running
  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_KEY_EXCHANGE_SKIP_NODE_NOT_RUNNING',
      details: {},
    );
    return 0;
  }

  // 3. Get eligible contacts: missing ML-KEM key, OR pending re-announcement
  final contacts = await contactRepo.getActiveContacts();
  final markerStore = secureKeyStore;
  var reannouncePending = markerStore != null
      ? await readMlKemReannounceMarker(markerStore)
      : const <String>[];
  // FDC-09 §12 / CV-14 backfill: a contact pending wake-token distribution is
  // eligible for a (re-)send even when its ML-KEM key is already complete. This
  // is a DISTINCT marker from the ML-KEM re-announce — drained in its own block.
  var wakeTokenPending = markerStore != null
      ? await readWakeTokenPendingMarker(markerStore)
      : const <String>[];
  final eligible = contacts
      .where(
        (c) =>
            !c.isBlocked &&
            (c.mlKemPublicKey == null ||
                reannouncePending.contains(c.peerId) ||
                wakeTokenPending.contains(c.peerId)),
      )
      .toList();

  if (eligible.isEmpty) return 0;

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_KEY_EXCHANGE_START',
    details: {'count': eligible.length},
  );

  // 4. Send sequentially with jitter (100-500ms between each)
  int sent = 0;
  final rng = Random();

  for (final contact in eligible) {
    try {
      final result = await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: contact.peerId,
        recipientPublicKey: contact.publicKey,
        intent: ContactRequestSendIntent.keyExchangeRetry,
        resolveWakeToken: resolveWakeToken,
      );

      if (result == SendContactRequestResult.success) {
        sent++;
        // Drain the marker entry only on success — partial failure keeps
        // the remainder for the next retry trigger.
        if (markerStore != null && reannouncePending.contains(contact.peerId)) {
          reannouncePending = reannouncePending
              .where((peerId) => peerId != contact.peerId)
              .toList();
          await writeMlKemReannounceMarker(markerStore, reannouncePending);
          emitFlowEvent(
            layer: 'FL',
            event: 'KEY_REANNOUNCE_SENT',
            details: {
              'peerId': contact.peerId.length > 10
                  ? contact.peerId.substring(0, 10)
                  : contact.peerId,
              'remaining': reannouncePending.length,
            },
          );
        }
        // FDC-09 §12 / CV-14 wake-token distribution drain — its OWN block, keyed
        // off the DISTINCT wake marker. Drain a peerId only after its send
        // succeeded; a partial failure keeps the remainder for the next trigger.
        if (markerStore != null && wakeTokenPending.contains(contact.peerId)) {
          wakeTokenPending = wakeTokenPending
              .where((peerId) => peerId != contact.peerId)
              .toList();
          await writeWakeTokenPendingMarker(markerStore, wakeTokenPending);
          emitFlowEvent(
            layer: 'FL',
            event: 'WAKE_TOKEN_DISTRIBUTED',
            details: {
              'peerId': contact.peerId.length > 10
                  ? contact.peerId.substring(0, 10)
                  : contact.peerId,
              'remaining': wakeTokenPending.length,
            },
          );
        }
      }

      final prefix = contact.peerId.length > 10
          ? contact.peerId.substring(0, 10)
          : contact.peerId;
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_KEY_EXCHANGE_RESULT',
        details: {'peerId': prefix, 'result': result.name},
      );
    } catch (e) {
      final prefix = contact.peerId.length > 10
          ? contact.peerId.substring(0, 10)
          : contact.peerId;
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_KEY_EXCHANGE_ERROR',
        details: {'peerId': prefix, 'error': e.toString()},
      );
    }

    // Jitter: 100-500ms between sends
    if (contact != eligible.last) {
      await Future.delayed(Duration(milliseconds: 100 + rng.nextInt(400)));
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_KEY_EXCHANGE_COMPLETE',
    details: {'sent': sent, 'total': eligible.length},
  );

  return sent;
}
