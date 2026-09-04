import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';

/// Result of handling an incoming P2P message.
enum HandleMessageResult {
  /// New contact request received and stored.
  contactRequest,

  /// 171: New v2 (recipient-bound) request from a non-declined, non-blocked
  /// peer — stored pending (audit) and eligible for tap-free auto-add +
  /// reciprocal by the listener. v1 / declined / blocked stay on
  /// [contactRequest] (manual dialog).
  contactAutoAdded,

  /// Request from this peer is already pending.
  duplicateRequest,

  /// Sender is already a contact.
  alreadyContact,

  /// Existing contact's ML-KEM key was updated from verified payload.
  contactKeyUpdated,

  /// Intro-related contact repair completed silently.
  silentIntroRecovered,

  /// Not a contact request message (regular chat).
  regularMessage,

  /// Message failed parsing or validation.
  invalidMessage,
}

typedef OnCallWakeHandleReceiptEvaluated =
    void Function(String challenge, bool exactCurrent);

final RegExp _callWakeReceiptChallengePattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Parses an incoming P2P message and handles contact requests.
///
/// This function:
/// 1. Parses message content as JSON
/// 2. Checks if type == "contact_request"
/// 3. For v2: decrypts, then signature-verifies
/// 4. For v1: signature-verifies directly
/// 5. Checks not already a contact
/// 6. Checks no duplicate pending request
/// 7. Stores in contact_requests table
///
/// Returns a tuple of (result, request, verifiedPeerId) where request is
/// non-null when result == contactRequest, and verifiedPeerId is non-null for
/// existing-contact outcomes that may need authenticated follow-up
/// (contactKeyUpdated or alreadyContact). The peer ID comes from the
/// signature-verified payload, never from transport metadata.
Future<(HandleMessageResult, ContactRequestModel?, String?)>
handleIncomingMessage({
  required ChatMessage message,
  required Bridge bridge,
  required ContactRequestRepository requestRepo,
  required ContactRepository contactRepo,
  required String ownPeerId,
  String? ownPrivateKey,
  Set<String>? seenMessageIds,
  AttemptSilentIntroContactRequestRecovery? attemptSilentIntroRecovery,
  // FDC-09 §12 / CV-14: when present, the recipient-issued `wt` distributed
  // inside this signed contact_request is persisted here (keyed by the sender's
  // peerId), so our later `inbox:store` frames to that peer can present it.
  ReceivedWakeTokenStore? receivedWakeTokenStore,
  // Call-only capability ledger. This is separate from `wt` storage and accepts
  // only a verified, current, strictly newer v2 `cwh` grant.
  ReceivedCallWakeHandleStore? receivedCallWakeHandleStore,
  // Best-effort notification for UI owners that cache per-contact callability.
  // It runs only after a verified `cwh` has been durably stored as newer.
  Future<void> Function()? onCallWakeHandleStored,
  // A versioned direct sender may require proof that its exact signed grant is
  // current in the receiver's durable ledger. The listener turns a positive
  // evaluation into an opaque deferred-ACK receipt; false withholds that ACK.
  OnCallWakeHandleReceiptEvaluated? onCallWakeHandleReceiptEvaluated,
}) async {
  // Safe prefix for logging (handles short strings like "unknown")
  String safePrefix(String s) => s.length > 10 ? s.substring(0, 10) : s;

  emitFlowEvent(
    layer: 'FL',
    event: 'INCOMING_MESSAGE_HANDLE_START',
    details: {'from': safePrefix(message.from)},
  );

  // 1. Parse message content as JSON
  Map<String, dynamic> json;
  try {
    json = jsonDecode(message.content) as Map<String, dynamic>;
  } catch (e) {
    // Not JSON - treat as regular message
    emitFlowEvent(layer: 'FL', event: 'INCOMING_MESSAGE_NOT_JSON', details: {});
    return (HandleMessageResult.regularMessage, null, null);
  }

  // 2. Check if type == "contact_request"
  final type = json['type'] as String?;
  if (type != 'contact_request') {
    emitFlowEvent(
      layer: 'FL',
      event: 'INCOMING_MESSAGE_NOT_CONTACT_REQUEST',
      details: {'type': type},
    );
    return (HandleMessageResult.regularMessage, null, null);
  }

  emitFlowEvent(layer: 'FL', event: 'CONTACT_REQUEST_RECEIVED', details: {});

  // 3. Determine version and extract payload
  final version = json['version'] as String? ?? '1';
  Map<String, dynamic>? payload;

  if (version == '2') {
    // --- v2: Encrypted contact request ---
    final msgId = json['msgId'] as String?;
    final ts = json['ts'] as String?;
    final encrypted = json['encrypted'] as Map<String, dynamic>?;

    // Validate v2 structure
    if (msgId == null || ts == null || encrypted == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_V2_MISSING_FIELDS',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }

    final ephemeralPublicKey = encrypted['ephemeralPublicKey'] as String?;
    final ciphertext = encrypted['ciphertext'] as String?;
    final nonce = encrypted['nonce'] as String?;

    if (ephemeralPublicKey == null || ciphertext == null || nonce == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_V2_INCOMPLETE_ENCRYPTED',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }

    // Pre-decrypt replay check: msgId dedup
    if (seenMessageIds != null && seenMessageIds.contains(msgId)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_V2_REPLAY_DETECTED',
        details: {'msgId': msgId},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }

    // Pre-decrypt timestamp check
    final parsedTs = DateTime.tryParse(ts);
    if (parsedTs == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_V2_INVALID_TS',
        details: {'ts': ts},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }

    final now = DateTime.now().toUtc();
    final age = now.difference(parsedTs);
    if (age > const Duration(hours: 24)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_V2_EXPIRED',
        details: {'ageMinutes': age.inMinutes},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
    if (age < const Duration(minutes: -5)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_V2_FUTURE_TS',
        details: {'ageMinutes': age.inMinutes},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }

    // Need own private key for decryption
    if (ownPrivateKey == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_V2_NO_PRIVATE_KEY',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }

    // Decrypt
    final decryptResponse = await callDecryptContactRequest(
      bridge: bridge,
      ownPrivateKey: ownPrivateKey,
      ephemeralPublicKey: ephemeralPublicKey,
      ciphertext: ciphertext,
      nonce: nonce,
      msgId: msgId,
      ts: ts,
    );

    if (decryptResponse['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_V2_DECRYPTION_FAILED',
        details: {
          'errorCode': decryptResponse['errorCode'],
          'errorMessage': decryptResponse['errorMessage'],
        },
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }

    // Parse decrypted payload
    final plaintext = decryptResponse['plaintext'];
    if (plaintext is! String || plaintext.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_V2_MALFORMED_DECRYPT',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
    try {
      payload = jsonDecode(plaintext) as Map<String, dynamic>;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_V2_INVALID_PAYLOAD',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
  } else {
    // --- v1: Plaintext contact request ---
    payload = json['payload'] as Map<String, dynamic>?;
  }

  if (payload == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_MISSING_PAYLOAD',
      details: {},
    );
    return (HandleMessageResult.invalidMessage, null, null);
  }

  CallWakeHandleGrant? callWakeHandleGrant;
  if (payload.containsKey('cwh')) {
    // Call wake authority is recipient-private and must never ride the v1
    // plaintext compatibility envelope.
    if (version != '2') {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_CALL_WAKE_HANDLE_V1_REJECTED',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
    try {
      callWakeHandleGrant = CallWakeHandleGrant.fromCanonicalMap(
        payload['cwh'],
      );
    } on FormatException {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_CALL_WAKE_HANDLE_MALFORMED',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
  }
  final rawCallWakeReceiptChallenge = payload['cwr'];
  final callWakeReceiptChallenge = rawCallWakeReceiptChallenge is String
      ? rawCallWakeReceiptChallenge
      : null;
  if (payload.containsKey('cwr') &&
      (version != '2' ||
          callWakeHandleGrant == null ||
          callWakeReceiptChallenge == null ||
          !_callWakeReceiptChallengePattern.hasMatch(
            callWakeReceiptChallenge,
          ))) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_CALL_WAKE_RECEIPT_MALFORMED',
      details: {},
    );
    return (HandleMessageResult.invalidMessage, null, null);
  }

  // 4. Validate required fields
  final requiredFields = ['pk', 'ns', 'rv', 'ts', 'sig'];
  for (final field in requiredFields) {
    if (payload[field] == null || payload[field].toString().isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_MISSING_FIELD',
        details: {'field': field},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
  }

  final peerId = payload['ns'] as String;
  final publicKey = payload['pk'] as String;
  final signature = payload['sig'] as String;

  final peerIdPrefix = safePrefix(peerId);

  // 5. Verify sender matches claimed identity
  // Note: message.from may be "unknown" if JS layer doesn't populate it correctly.
  // In that case, we skip this check and rely on signature verification instead.
  if (message.from != 'unknown' && peerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SENDER_MISMATCH',
      details: {'claimed': peerIdPrefix, 'actual': safePrefix(message.from)},
    );
    return (HandleMessageResult.invalidMessage, null, null);
  }

  // 6. Check not from self
  if (peerId == ownPeerId) {
    emitFlowEvent(layer: 'FL', event: 'CONTACT_REQUEST_FROM_SELF', details: {});
    return (HandleMessageResult.invalidMessage, null, null);
  }

  // 7. Verify signature
  final unsignedPayload = SplayTreeMap<String, dynamic>.from({
    if (payload['mlkem'] != null) 'mlkem': payload['mlkem'],
    'ns': payload['ns'],
    'pk': payload['pk'],
    'rv': payload['rv'],
    'ts': payload['ts'],
    if (payload['un'] != null) 'un': payload['un'],
    if (callWakeHandleGrant != null)
      'cwh': callWakeHandleGrant.toCanonicalMap(),
    'cwr': ?callWakeReceiptChallenge,
    // FDC-09 §12 / CV-14: `wt` is a conditionally-included SIGNED field (same
    // idiom as `mlkem`/`un`). It MUST be reconstructed here or a wt-carrying
    // request's signature fails to verify — after backfill that would drop every
    // contact-add + key rotation (INV-1). A no-`wt` request keeps the old shape.
    if (payload['wt'] != null) 'wt': payload['wt'],
  });
  final dataToVerify = jsonEncode(unsignedPayload);

  final isValid = await callVerifyPayload(
    bridge: bridge,
    publicKey: publicKey,
    data: dataToVerify,
    signature: signature,
  );

  if (!isValid) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_INVALID_SIGNATURE',
      details: {'peerId': peerIdPrefix},
    );
    return (HandleMessageResult.invalidMessage, null, null);
  }

  var exactCallWakeHandleIsDurable = false;
  if (receivedCallWakeHandleStore != null && callWakeHandleGrant != null) {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final stored = await receivedCallWakeHandleStore.storeIfStrictlyNewer(
      issuerAccountPeerId: peerId,
      grant: callWakeHandleGrant,
      nowMs: nowMs,
    );
    final current = await receivedCallWakeHandleStore.readForIssuer(peerId);
    exactCallWakeHandleIsDurable =
        current == callWakeHandleGrant && callWakeHandleGrant.isValidAt(nowMs);
    emitFlowEvent(
      layer: 'FL',
      event: stored
          ? 'CALL_WAKE_HANDLE_RECEIVED_STORED'
          : 'CALL_WAKE_HANDLE_RECEIVED_IGNORED',
      details: {'peerId': peerIdPrefix},
    );
    if (stored && onCallWakeHandleStored != null) {
      try {
        await onCallWakeHandleStored();
      } catch (_) {
        // The verified grant is already durable. A presentation refresh must
        // never turn an accepted contact request into a retry/failure.
        emitFlowEvent(
          layer: 'FL',
          event: 'CALL_WAKE_HANDLE_REFRESH_FAILED',
          details: {'peerId': peerIdPrefix},
        );
      }
    }
  }
  if (callWakeReceiptChallenge != null) {
    onCallWakeHandleReceiptEvaluated?.call(
      callWakeReceiptChallenge,
      exactCallWakeHandleIsDurable,
    );
  }

  // FDC-09 §12 / CV-14: extract + persist the recipient-issued `wt` NOW —
  // immediately after the signature check and BEFORE the silent-intro-recovery
  // early-return below — so it is captured on ALL verified paths (new contact,
  // already-contact key rotation, AND silent-intro-recovered, which returns
  // before the contact checks). Anti-rollback: the signed `ts` must be strictly
  // newer than the stored ts (own comparison — the ML-KEM anti-rollback guard is
  // keyed off contact-table state absent on the new-contact / intro paths).
  if (receivedWakeTokenStore != null) {
    final wt = payload['wt'] as String?;
    final wtTs = payload['ts'] as String?;
    if (wt != null && wt.isNotEmpty && wtTs != null) {
      final existing = await receivedWakeTokenStore.readTokenFor(peerId);
      final storedTs = existing?['ts'];
      if (storedTs == null || wtTs.compareTo(storedTs) > 0) {
        await receivedWakeTokenStore.writeTokenFor(peerId, wt, wtTs);
        emitFlowEvent(
          layer: 'FL',
          event: 'WAKE_TOKEN_RECEIVED_STORED',
          details: {'peerId': peerIdPrefix},
        );
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'WAKE_TOKEN_RECEIVED_ROLLBACK_IGNORED',
          details: {'peerId': peerIdPrefix},
        );
      }
    }
  }

  if (attemptSilentIntroRecovery != null) {
    final recoveryResult = await attemptSilentIntroRecovery(
      VerifiedContactRequestEnvelope(
        peerId: peerId,
        publicKey: publicKey,
        rendezvous: payload['rv'] as String,
        username: payload['un'] as String? ?? 'Unknown',
        signature: signature,
        mlKemPublicKey: payload['mlkem'] as String?,
      ),
    );
    if (recoveryResult.action == IntroContactRequestRecoveryAction.recovered) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_SILENT_INTRO_RECOVERED',
        details: {'peerId': peerIdPrefix},
      );
      return (HandleMessageResult.silentIntroRecovered, null, null);
    }
  }

  // 8. Check if already a contact (and accept ML-KEM key updates)
  final isContact = await contactRepo.contactExists(peerId);
  if (isContact) {
    final mlkemFromPayload = payload['mlkem'] as String?;
    final existingContact = await contactRepo.getContact(peerId);
    final payloadTs = payload['ts'] as String?;

    if (existingContact != null &&
        mlkemFromPayload != null &&
        existingContact.mlKemPublicKey != mlkemFromPayload) {
      // First key, or a rotation announced after a restore (P0-B). Both
      // arrive inside the Ed25519-signed payload, already verified above.
      // Anti-rollback: a CHANGED key is only accepted when the signed ts is
      // strictly newer than the last accepted key update (falling back to
      // scannedAt when the key was never updated).
      final hadKey = existingContact.mlKemPublicKey != null;
      final lastKeyUpdateTs =
          existingContact.mlKemKeyUpdatedTs ?? existingContact.scannedAt;
      final tsIsNewer =
          payloadTs != null && payloadTs.compareTo(lastKeyUpdateTs) > 0;
      if (!hadKey || tsIsNewer) {
        await contactRepo.addContact(
          existingContact.copyWith(
            mlKemPublicKey: mlkemFromPayload,
            mlKemKeyUpdatedTs:
                payloadTs ?? DateTime.now().toUtc().toIso8601String(),
          ),
        );
        emitFlowEvent(
          layer: 'FL',
          event: hadKey ? 'CONTACT_KEY_ROTATED' : 'CONTACT_REQUEST_KEY_UPDATED',
          details: {'peerId': peerIdPrefix},
        );
        return (HandleMessageResult.contactKeyUpdated, null, peerId);
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_KEY_ROLLBACK_IGNORED',
        details: {
          'peerId': peerIdPrefix,
          'payloadTs': payloadTs ?? '<missing>',
          'lastKeyUpdateTs': lastKeyUpdateTs,
        },
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_ALREADY_CONTACT',
      details: {'peerId': peerIdPrefix},
    );
    return (HandleMessageResult.alreadyContact, null, peerId);
  }

  // 9. Check if request already pending
  final existingRequest = await requestRepo.getRequest(peerId);
  if (existingRequest != null &&
      existingRequest.status == ContactRequestStatus.pending) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_DUPLICATE',
      details: {'peerId': peerIdPrefix},
    );
    return (HandleMessageResult.duplicateRequest, null, null);
  }

  // 10. Create and store the request (pending — the audit trail for BOTH the
  //     manual-dialog path and the 171 tap-free auto-add path; the listener
  //     loads this pending row to accept + reciprocate).
  final request = ContactRequestModel.fromP2PPayload(payload);

  try {
    await requestRepo.addRequest(request);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_STORE_ERROR',
      details: {'error': e.toString()},
    );
    return (HandleMessageResult.invalidMessage, null, null);
  }

  // 11 (171). One-scan auto-add eligibility. A NEW, recipient-bound (v2)
  // verified request from a non-declined, non-blocked peer is added tap-free
  // (the listener performs the add + reciprocal). v1 plaintext requests (no
  // recipient binding) and any previously-declined peer stay on the manual
  // dialog (INV-2 / INV-3). step-8 (contactExists) already short-circuited
  // existing — and therefore blocked — contacts to alreadyContact; the
  // isBlocked guard here is defense-in-depth against a future reorder.
  final priorWasDeclined =
      existingRequest != null &&
      existingRequest.status == ContactRequestStatus.declined;
  final blockedGuard =
      (await contactRepo.getContact(peerId))?.isBlocked == true;
  if (version == '2' && !priorWasDeclined && !blockedGuard) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_AUTO_ADD_ELIGIBLE',
      details: {'peerId': peerIdPrefix, 'username': request.username},
    );
    return (HandleMessageResult.contactAutoAdded, request, null);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CONTACT_REQUEST_STORED',
    details: {'peerId': peerIdPrefix, 'username': request.username},
  );
  return (HandleMessageResult.contactRequest, request, null);
}
