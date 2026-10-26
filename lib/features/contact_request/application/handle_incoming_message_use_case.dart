import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';
import 'package:flutter_app/features/contact_request/application/existing_contact_repair_policy.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_control.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
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

  /// A signed repair reply from a peer that is not a current, unblocked
  /// contact. A reply never creates a contact or a pending request.
  repairReplyIgnored,
}

/// Verified facts about one received contact request, for the listener.
///
/// Delivered only after the payload was authenticated against the stored
/// signing authority (existing contact) or its own bound key (new peer).
final class ContactRequestReceiveFacts {
  const ContactRequestReceiveFacts({
    required this.authenticatedPeerId,
    required this.authenticatedPublicKey,
    required this.control,
    required this.repairDecision,
    this.repairClaim,
  });

  final String authenticatedPeerId;

  /// The Ed25519 key the payload was verified with (the stored key for an
  /// existing contact).
  final String authenticatedPublicKey;

  /// The signed `cr` marker, when present.
  final ContactRequestControl? control;
  final ExistingContactRepairDecision repairDecision;

  /// Outcome of the durable reply reservation, when one was attempted.
  final ContactRepairClaimOutcome? repairClaim;
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
  // Task 12b: durable relationship memory and the reply-once reservation. When
  // null, deletion/decline memory and automatic repair replies are off.
  ContactRepairRepository? repairRepository,
  // Our account Ed25519 public key, recorded with a reservation so a reply is
  // never sent under a different local identity.
  String? ownAccountPublicKey,
  // Our ACCOUNT peer ID, which a signed marker must name as its recipient. A
  // linked installation's transport ID ([ownPeerId]) is not the account ID.
  String? ownAccountPeerId,
  void Function(ContactRequestReceiveFacts facts)? onReceiveFacts,
  int Function()? nowMs,
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
  String? outerMsgId;

  if (version == '2') {
    // --- v2: Encrypted contact request ---
    final msgId = json['msgId'] as String?;
    final ts = json['ts'] as String?;
    final encrypted = json['encrypted'] as Map<String, dynamic>?;
    outerMsgId = msgId;

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

  // Task 12b: the signed operation marker. Only the encrypted v2 path may
  // carry it, its ID must be the outer message ID (so the AAD and the signed
  // identity agree), and it must be addressed to this account.
  ContactRequestControl? control;
  if (payload.containsKey('cr')) {
    if (version != '2') {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_CONTROL_V1_REJECTED',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
    try {
      control = ContactRequestControl.parse(payload['cr']);
    } on FormatException {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_CONTROL_MALFORMED',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
    if (control.id != outerMsgId ||
        control.to != (ownAccountPeerId ?? ownPeerId)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_CONTROL_BINDING_MISMATCH',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
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
  final rawPeerId = payload['ns'];
  final rawPublicKey = payload['pk'];
  final rawSignature = payload['sig'];
  if (rawPeerId is! String ||
      rawPublicKey is! String ||
      rawSignature is! String) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_FIELD_TYPE_INVALID',
      details: {},
    );
    return (HandleMessageResult.invalidMessage, null, null);
  }

  final peerId = rawPeerId;
  final publicKey = rawPublicKey;
  final signature = rawSignature;

  final peerIdPrefix = safePrefix(peerId);

  // 5. Verify sender matches claimed identity
  // Note: message.from may be "unknown" if JS layer doesn't populate it correctly.
  // That only skips this transport check; it never replaces the stored-key
  // authentication below.
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

  // 6b. Task 12b: the claimed peer ID must be the libp2p ID of the payload's
  // own Ed25519 key.
  if (ed25519PublicKeyCanonicalPeerId(
        base64PublicKey: publicKey,
        claimedPeerId: peerId,
      ) !=
      peerId) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_IDENTITY_BINDING_MISMATCH',
      details: {},
    );
    return (HandleMessageResult.invalidMessage, null, null);
  }

  // 6c. Task 12b: an existing contact is authenticated with the signing key
  // we already store for it, before any key, token, grant or intro write. A
  // valid signature under a different, payload-supplied key is a rogue claim.
  final storedBeforeVerify = await contactRepo.getContact(peerId);
  final String verificationKey;
  if (storedBeforeVerify != null) {
    if (!_sameEd25519Key(storedBeforeVerify.publicKey, publicKey)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_STORED_AUTHORITY_MISMATCH',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
    verificationKey = storedBeforeVerify.publicKey;
  } else {
    verificationKey = publicKey;
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
    // Task 12b: the signed operation marker, canonicalised.
    if (control != null) 'cr': control.toCanonicalMap(),
  });
  final dataToVerify = jsonEncode(unsignedPayload);

  final isValid = await callVerifyPayload(
    bridge: bridge,
    publicKey: verificationKey,
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

  // 7b. Re-read the authority after the verification await: a block, delete,
  // re-add or key replacement while crypto was pending invalidates this work.
  final existingContact = await contactRepo.getContact(peerId);
  if ((storedBeforeVerify == null) != (existingContact == null) ||
      (existingContact != null &&
          (existingContact.publicKey != storedBeforeVerify!.publicKey ||
              existingContact.isBlocked != storedBeforeVerify.isBlocked))) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_AUTHORITY_CHANGED_DURING_VERIFY',
      details: {},
    );
    return (HandleMessageResult.invalidMessage, null, null);
  }

  // The stored signing identity survives the in-memory replay cache. Ignore
  // the exact declined request before it can change request or wake authority;
  // a fresh signed request still follows the manual-consent path below.
  final priorRequest = await requestRepo.getRequest(peerId);
  if (priorRequest != null &&
      priorRequest.status == ContactRequestStatus.declined &&
      priorRequest.publicKey == publicKey &&
      priorRequest.signature == signature) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_DECLINED_REPLAY_IGNORED',
      details: {},
    );
    return (HandleMessageResult.invalidMessage, null, null);
  }

  final consent = await repairRepository?.readConsent(peerId);
  final blocked = existingContact?.isBlocked ?? false;
  // Known withdrawal (deleted or declined) with no current contact.
  final refused =
      existingContact == null &&
      consent != null &&
      consent.state != ContactRelationshipState.active;
  final requestDigest = contactRequestSignedDigest(dataToVerify);

  // 7c. The same signed request ID with a different signed body is a
  // conflict: reject it before applying anything it carries.
  if (control != null && repairRepository != null && existingContact != null) {
    final recordedDigest = await repairRepository.lookupRequestDigest(
      peerId: peerId,
      requestId: control.id,
    );
    if (recordedDigest != null && recordedDigest != requestDigest) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_CONTROL_ID_CONFLICT',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
  }

  final repairDecision = decideExistingContactRepair(
    control: control,
    existedBeforeRouting: existingContact != null,
    blocked: blocked,
  );
  void reportFacts([ContactRepairClaimOutcome? claim]) {
    onReceiveFacts?.call(
      ContactRequestReceiveFacts(
        authenticatedPeerId: peerId,
        authenticatedPublicKey: verificationKey,
        control: control,
        repairDecision: repairDecision,
        repairClaim: claim,
      ),
    );
  }

  // A blocked contact gets no key, token, grant, intro or reply through this
  // path. A signed repair reply from anyone who is not a current contact is
  // dropped: a reply never creates a contact.
  if (blocked) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_FROM_BLOCKED_IGNORED',
      details: {},
    );
    reportFacts();
    return (HandleMessageResult.alreadyContact, null, null);
  }
  if (control != null && !control.isNewRequest && existingContact == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_REPAIR_REPLY_IGNORED',
      details: {},
    );
    reportFacts();
    return (HandleMessageResult.repairReplyIgnored, null, null);
  }
  if (control != null && existingContact != null) {
    await repairRepository?.recordPeerSupportsMarked(peerId);
  }

  // Known withdrawn peers get no new authority state from a passive message.
  if (!refused) {
    var exactCallWakeHandleIsDurable = false;
    if (receivedCallWakeHandleStore != null && callWakeHandleGrant != null) {
      final nowMsValue = DateTime.now().toUtc().millisecondsSinceEpoch;
      final stored = await receivedCallWakeHandleStore.storeIfStrictlyNewer(
        issuerAccountPeerId: peerId,
        grant: callWakeHandleGrant,
        nowMs: nowMsValue,
      );
      final current = await receivedCallWakeHandleStore.readForIssuer(peerId);
      exactCallWakeHandleIsDurable =
          current == callWakeHandleGrant &&
          callWakeHandleGrant.isValidAt(nowMsValue);
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

    // FDC-09 §12 / CV-14: persist the recipient-issued `wt` on every verified
    // path before the silent-intro early return. Anti-rollback compares parsed
    // signed UTC instants: newer replaces, equal-identical is idempotent,
    // equal-different is a conflict, older is ignored.
    if (receivedWakeTokenStore != null) {
      final wt = payload['wt'];
      final wtTs = payload['ts'];
      final wtAtMs = parseSignedInstantMs(wtTs);
      if (wt is String && wt.isNotEmpty && wtTs is String && wtAtMs != null) {
        final existing = await receivedWakeTokenStore.readTokenFor(peerId);
        final storedAtMs = parseSignedInstantMs(existing?['ts']);
        final storedToken = existing?['tok'];
        if (storedAtMs == null || wtAtMs > storedAtMs) {
          await receivedWakeTokenStore.writeTokenFor(peerId, wt, wtTs);
          emitFlowEvent(
            layer: 'FL',
            event: 'WAKE_TOKEN_RECEIVED_STORED',
            details: {'peerId': peerIdPrefix},
          );
        } else {
          emitFlowEvent(
            layer: 'FL',
            event:
                wtAtMs == storedAtMs && storedToken != null && storedToken != wt
                ? 'WAKE_TOKEN_RECEIVED_CONFLICT_IGNORED'
                : 'WAKE_TOKEN_RECEIVED_ROLLBACK_IGNORED',
            details: {'peerId': peerIdPrefix},
          );
        }
      }
    }
  }

  Future<(HandleMessageResult, ContactRequestModel?, String?)> withRepair(
    HandleMessageResult result,
    String? verifiedPeerId,
  ) async {
    ContactRepairClaimOutcome? claim;
    if (repairDecision == ExistingContactRepairDecision.claimReply &&
        repairRepository != null) {
      final signedAtMs = parseSignedInstantMs(payload!['ts']);
      final String authorityFingerprint;
      try {
        authorityFingerprint = ed25519AuthorityFingerprint(
          existingContact!.publicKey,
        );
      } on FormatException {
        reportFacts();
        return (result, null, verifiedPeerId);
      }
      if (signedAtMs == null) {
        claim = const ContactRepairClaimOutcome(ContactRepairClaimStatus.stale);
      } else {
        claim = await repairRepository.claimReply(
          ContactRepairClaim(
            peerId: peerId,
            requestId: control!.id,
            requestDigest: requestDigest,
            signedAtMs: signedAtMs,
            authorityFingerprint: authorityFingerprint,
            localAuthorityFingerprint: _fingerprintOrEmpty(ownAccountPublicKey),
            relationshipRevision: consent?.revision ?? 0,
            wallNowMs:
                nowMs?.call() ?? DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REPAIR_REPLY_CLAIM',
        details: {'status': claim.status.name},
      );
    }
    reportFacts(claim);
    return (result, null, verifiedPeerId);
  }

  // Silent intro recovery runs only for peers whose relationship was not
  // withdrawn, and never for a signed reply: a reply cannot force an
  // introduction into acceptance.
  if (attemptSilentIntroRecovery != null &&
      !refused &&
      (control == null || control.isNewRequest)) {
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
      final (result, _, _) = await withRepair(
        HandleMessageResult.silentIntroRecovered,
        null,
      );
      return (result, null, null);
    }
  }

  // 8. Existing contact: accept an ML-KEM key update. Times are compared as
  // parsed UTC instants. A first key lands; a changed key needs a strictly
  // newer signed instant; an equal instant with a different key is a
  // conflict; an older key never rolls back.
  if (existingContact != null) {
    // Re-read after the grant, token and intro awaits: a delete or block that
    // landed meanwhile wins, and the write keeps the CURRENT row's flags.
    final current = await contactRepo.getContact(peerId);
    final currentConsent = await repairRepository?.readConsent(peerId);
    if (current == null ||
        current.isBlocked ||
        current.publicKey != existingContact.publicKey ||
        currentConsent?.revision != consent?.revision) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_RELATIONSHIP_CHANGED_DURING_RECEIVE',
        details: {},
      );
      return (HandleMessageResult.invalidMessage, null, null);
    }
    final mlkemFromPayload = payload['mlkem'] as String?;

    if (mlkemFromPayload != null &&
        mlkemFromPayload.isNotEmpty &&
        mlkemFromPayload.length <= _maxMlKemPublicKeyChars &&
        current.mlKemPublicKey != mlkemFromPayload) {
      final hadKey = current.mlKemPublicKey != null;
      final payloadTs = payload['ts'] as String?;
      final payloadAtMs = parseSignedInstantMs(payloadTs);
      final lastKeyUpdateTs = current.mlKemKeyUpdatedTs ?? current.scannedAt;
      final lastKeyUpdateAtMs = parseSignedInstantMs(lastKeyUpdateTs);
      final tsIsNewer =
          payloadAtMs != null &&
          (lastKeyUpdateAtMs == null || payloadAtMs > lastKeyUpdateAtMs);
      if (!hadKey || tsIsNewer) {
        await contactRepo.addContact(
          current.copyWith(
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
        return withRepair(HandleMessageResult.contactKeyUpdated, peerId);
      }

      emitFlowEvent(
        layer: 'FL',
        event: payloadAtMs != null && payloadAtMs == lastKeyUpdateAtMs
            ? 'CONTACT_REQUEST_KEY_CONFLICT_IGNORED'
            : 'CONTACT_REQUEST_KEY_ROLLBACK_IGNORED',
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
    return withRepair(HandleMessageResult.alreadyContact, peerId);
  }
  reportFacts();

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
    rethrow;
  }

  // 11 (171). One-scan auto-add eligibility. A NEW, recipient-bound (v2)
  // verified request from a non-declined, non-blocked peer is added tap-free
  // (the listener performs the add + reciprocal). v1 plaintext requests (no
  // recipient binding), any previously-declined peer and (Task 12b) any peer
  // whose deletion or decline we remember stay on the manual dialog (INV-2 /
  // INV-3): there is no passive re-add.
  final priorWasDeclined =
      existingRequest != null &&
      existingRequest.status == ContactRequestStatus.declined;
  if (version == '2' && !priorWasDeclined && !refused) {
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

/// Generous bound on an ML-KEM-768 public key in base64 (1184 bytes encode to
/// 1580 characters).
const int _maxMlKemPublicKeyChars = 4096;

bool _sameEd25519Key(String stored, String claimed) {
  try {
    final a = base64Decode(stored.trim());
    final b = base64Decode(claimed.trim());
    if (a.length != 32 || b.length != 32) return false;
    for (var i = 0; i < 32; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  } on FormatException {
    return false;
  }
}

String _fingerprintOrEmpty(String? base64PublicKey) {
  if (base64PublicKey == null) return '';
  try {
    return ed25519AuthorityFingerprint(base64PublicKey);
  } on FormatException {
    return '';
  }
}
