import 'dart:math';

import 'package:clock/clock.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/mlkem_reannounce_marker.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_retry_journal.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_control.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/wake_token_pending_marker.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

final _incompleteKeyExchangeRetryLock = Lock();

typedef LoadPendingCallWakeHandleContactIds =
    Future<Iterable<String>> Function();

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
  // This provider is deliberately independent from the ordinary notification
  // wake-token marker. Its IDs may include archived contacts because archiving
  // does not revoke an already-issued call capability.
  LoadPendingCallWakeHandleContactIds? loadPendingCallWakeHandleContactIds,
  ResolveCallWakeHandle? resolveCallWakeHandle,
  OnCallWakeHandleDistributed? onCallWakeHandleDistributed,
  // Task 12b: peers verified as updated get the signed repair marker, so they
  // answer with one durable repair reply. Others stay unmarked.
  Future<bool> Function(String peerId)? shouldMarkAsNewRequest,
  // A local decline/withdrawal cannot authorize another automatic request.
  Future<ContactRelationshipConsent?> Function(String peerId)? readConsent,
}) => _incompleteKeyExchangeRetryLock.synchronized(() async {
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

  // 3. Get eligible contacts: missing ML-KEM key, pending re-announcement, or
  // a call-only capability whose encrypted distribution is still pending.
  final callWakeHandlePending = loadPendingCallWakeHandleContactIds == null
      ? const <String>{}
      : (await loadPendingCallWakeHandleContactIds())
            .where((peerId) => peerId.isNotEmpty)
            .toSet();
  final contacts = await contactRepo.getAllContacts();
  final consents = <String, ContactRelationshipConsent?>{
    if (readConsent != null)
      for (final contact in contacts)
        contact.peerId: await readConsent(contact.peerId),
  };
  ContactRequestRetryJournal? journal;
  if (secureKeyStore != null) {
    try {
      journal = await ContactRequestRetryJournal.reconcile(
        store: secureKeyStore,
        identity: identity,
        contacts: contacts,
        consents: consents,
        nowMs: clock.now().millisecondsSinceEpoch,
      );
    } on Object {
      // Durable custody is mandatory for dormant automatic work. A corrupt or
      // unavailable journal must not block independent explicit marker jobs.
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_KEY_EXCHANGE_ERROR',
        details: {'error': 'Contact retry journal unavailable'},
      );
    }
  }
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
  final eligible = contacts.where((c) {
    if (c.isBlocked ||
        !ContactRequestRetryJournal.consentAllows(consents[c.peerId])) {
      return false;
    }
    final callWakeDistributionPending = callWakeHandlePending.contains(
      c.peerId,
    );
    final incumbentRetryPending =
        !c.isArchived &&
        (c.mlKemPublicKey == null ||
            reannouncePending.contains(c.peerId) ||
            wakeTokenPending.contains(c.peerId));
    return incumbentRetryPending || callWakeDistributionPending;
  }).toList();

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
      final wakeToken = await resolveWakeToken?.call(contact.peerId);
      final hasWakeToken = wakeToken != null && wakeToken.isNotEmpty;
      if (!hasWakeToken &&
          contact.mlKemPublicKey != null &&
          !reannouncePending.contains(contact.peerId) &&
          !callWakeHandlePending.contains(contact.peerId)) {
        // Missing registration or an explicit emission rollback must keep
        // wake-only custody pending; an unrelated key send cannot settle it.
        continue;
      }
      final dormantKeyless =
          contact.mlKemPublicKey == null &&
          !reannouncePending.contains(contact.peerId) &&
          !wakeTokenPending.contains(contact.peerId) &&
          !callWakeHandlePending.contains(contact.peerId);
      final SendContactRequestResult result;
      if (dormantKeyless) {
        final custody = journal;
        if (custody == null) continue;
        final entry = await custody.reserve(
          contact,
          clock.now().millisecondsSinceEpoch,
        );
        if (entry == null) continue;
        var envelope = entry.envelope;
        if (envelope == null) {
          final marked =
              await shouldMarkAsNewRequest?.call(contact.peerId) ?? false;
          final build = await buildContactRequestEnvelope(
            identityRepo: identityRepo,
            bridge: bridge,
            targetPeerId: contact.peerId,
            recipientPublicKey: contact.publicKey,
            intent: ContactRequestSendIntent.keyExchangeRetry,
            resolveWakeToken: resolveWakeToken == null
                ? null
                : (_) async => wakeToken,
            resolveCallWakeHandle: resolveCallWakeHandle,
            control: marked
                ? ContactRequestControl.newRequest(
                    id: const Uuid().v4(),
                    to: contact.peerId,
                  )
                : null,
          );
          envelope = build.envelope;
          if (envelope == null) continue;
          if (!await custody.saveEnvelope(
            entry,
            envelope,
            clock.now().millisecondsSinceEpoch,
          )) {
            continue;
          }
        }
        // Build and secure persistence await external work. Recheck the exact
        // contact generation/consent before a saved envelope can leave custody.
        final current = await contactRepo.getContact(contact.peerId);
        final currentIdentity = await identityRepo.loadIdentity();
        final consent = await readConsent?.call(contact.peerId);
        if (currentIdentity == null ||
            current == null ||
            current.mlKemPublicKey != null ||
            current.isBlocked ||
            current.isArchived ||
            !ContactRequestRetryJournal.consentAllows(consent) ||
            ContactRequestRetryJournal.generation(currentIdentity, current) !=
                entry.generation ||
            clock.now().millisecondsSinceEpoch >= entry.expiresAtMs) {
          await custody.remove(contact.peerId);
          continue;
        }
        final outcome = await transmitContactRequestEnvelope(
          p2pService: p2pService,
          envelope: envelope,
        );
        if (outcome.exactCallWakeReceipt) {
          await markContactRequestCallWakeHandleDistributed(
            envelope: envelope,
            onCallWakeHandleDistributed: onCallWakeHandleDistributed,
          );
        }
        result = outcome.result;
      } else {
        result = await sendContactRequest(
          p2pService: p2pService,
          identityRepo: identityRepo,
          bridge: bridge,
          targetPeerId: contact.peerId,
          recipientPublicKey: contact.publicKey,
          intent: ContactRequestSendIntent.keyExchangeRetry,
          resolveWakeToken: resolveWakeToken == null
              ? null
              : (_) async => wakeToken,
          resolveCallWakeHandle: resolveCallWakeHandle,
          onCallWakeHandleDistributed: onCallWakeHandleDistributed,
          markAsNewRequest:
              await shouldMarkAsNewRequest?.call(contact.peerId) ?? false,
        );
      }

      if (result == SendContactRequestResult.success) {
        sent++;
        // Drain the marker entry only on success — partial failure keeps
        // the remainder for the next retry trigger.
        if (markerStore != null && reannouncePending.contains(contact.peerId)) {
          await completeMlKemReannouncePeer(markerStore, contact.peerId);
          reannouncePending = await readMlKemReannounceMarker(markerStore);
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
        if (markerStore != null &&
            hasWakeToken &&
            wakeTokenPending.contains(contact.peerId)) {
          await completeWakeTokenDistribution(
            secureKeyStore: markerStore,
            peerId: contact.peerId,
            token: wakeToken,
          );
          wakeTokenPending = await readWakeTokenPendingMarker(markerStore);
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
});
