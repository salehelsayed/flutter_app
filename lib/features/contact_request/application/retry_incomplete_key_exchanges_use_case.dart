import 'dart:math';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Retries sending contact requests to all contacts missing their ML-KEM key.
///
/// The contacts table serves as an implicit outbox: a contact with
/// `mlKemPublicKey == null` means the key exchange never completed.
/// This function loads active non-blocked contacts, filters for those
/// missing the key, and sequentially re-sends contact requests with
/// jitter to avoid startup bursts.
///
/// Returns the count of successfully sent requests.
Future<int> retryIncompleteKeyExchanges({
  required ContactRepository contactRepo,
  required IdentityRepository identityRepo,
  required P2PService p2pService,
  required Bridge bridge,
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

  // 3. Get eligible contacts (active, not blocked, missing ML-KEM key)
  final contacts = await contactRepo.getActiveContacts();
  final eligible = contacts
      .where((c) => c.mlKemPublicKey == null && !c.isBlocked)
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
      );

      if (result == SendContactRequestResult.success) sent++;

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
