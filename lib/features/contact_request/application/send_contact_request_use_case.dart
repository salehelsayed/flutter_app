import 'dart:collection';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/network_constants.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_control.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:uuid/uuid.dart';

/// Result of sending a contact request.
enum SendContactRequestResult {
  /// Successfully sent the contact request.
  success,

  /// No identity found in repository.
  noIdentity,

  /// Signing operation failed.
  signingError,

  /// Encryption failed (v2). Does NOT fall back to v1.
  encryptionError,

  /// P2P node is not running.
  nodeNotRunning,

  /// Could not discover the target peer.
  peerNotFound,

  /// Failed to send the message.
  sendFailed,
}

/// High-level reason the contact request is being sent.
enum ContactRequestSendIntent {
  /// A user-facing request triggered by a real connect action.
  newRequest('new_request'),

  /// A silent retry to repair an incomplete ML-KEM key exchange.
  keyExchangeRetry('key_exchange_retry');

  const ContactRequestSendIntent(this.wireValue);

  final String wireValue;
}

typedef ResolveCallWakeHandle =
    Future<CallWakeHandleGrant?> Function(String peerId);
typedef OnCallWakeHandleDistributed =
    Future<void> Function(String peerId, CallWakeHandleGrant grant);

/// A fully built, signed and (for v2) encrypted contact-request message.
///
/// Durable repair retries persist this exact value and transmit it again, so a
/// retry reuses the same message ID, signed payload and ciphertext instead of
/// minting a new request.
final class BuiltContactRequestEnvelope {
  const BuiltContactRequestEnvelope({
    required this.senderPeerId,
    required this.targetPeerId,
    required this.messageJson,
    required this.encrypted,
    this.msgId,
    this.callWakeHandle,
    this.callWakeReceiptChallenge,
  });

  final String senderPeerId;
  final String targetPeerId;
  final String messageJson;
  final bool encrypted;
  final String? msgId;
  final CallWakeHandleGrant? callWakeHandle;
  final String? callWakeReceiptChallenge;

  Map<String, Object?> toJson() => <String, Object?>{
    'senderPeerId': senderPeerId,
    'targetPeerId': targetPeerId,
    'messageJson': messageJson,
    'encrypted': encrypted,
    'msgId': msgId,
    'callWakeHandle': callWakeHandle?.toCanonicalMap(),
    'callWakeReceiptChallenge': callWakeReceiptChallenge,
  };

  static BuiltContactRequestEnvelope fromJson(Map<String, Object?> json) {
    final rawGrant = json['callWakeHandle'];
    return BuiltContactRequestEnvelope(
      senderPeerId: json['senderPeerId'] as String,
      targetPeerId: json['targetPeerId'] as String,
      messageJson: json['messageJson'] as String,
      encrypted: json['encrypted'] as bool,
      msgId: json['msgId'] as String?,
      callWakeHandle: rawGrant == null
          ? null
          : CallWakeHandleGrant.fromCanonicalMap(rawGrant),
      callWakeReceiptChallenge: json['callWakeReceiptChallenge'] as String?,
    );
  }
}

/// Outcome of [buildContactRequestEnvelope]: an envelope, or the reason none
/// could be built.
final class ContactRequestEnvelopeBuild {
  const ContactRequestEnvelopeBuild.built(
    BuiltContactRequestEnvelope this.envelope, {
    this.equivalenceKey,
  }) : failure = null;

  const ContactRequestEnvelopeBuild.failed(
    SendContactRequestResult this.failure,
  ) : envelope = null,
      equivalenceKey = null;

  final BuiltContactRequestEnvelope? envelope;
  final SendContactRequestResult? failure;

  /// Local send coalescing only; never serialized or carried on the wire.
  final String? equivalenceKey;
}

/// Outcome of [transmitContactRequestEnvelope].
final class ContactRequestTransmitOutcome {
  const ContactRequestTransmitOutcome(
    this.result, {
    this.exactCallWakeReceipt = false,
  });

  final SendContactRequestResult result;

  /// True only when the receiver returned the exact receipt for this
  /// envelope's call-wake challenge.
  final bool exactCallWakeReceipt;
}

final class _EquivalentContactRequestAttempt {
  _EquivalentContactRequestAttempt(this.future);

  final Future<ContactRequestTransmitOutcome> future;
  DateTime? acceptedAt;
}

final _recentContactRequests =
    Expando<Map<String, _EquivalentContactRequestAttempt>>();
const _equivalentContactRequestWindow = Duration(seconds: 30);

Future<ContactRequestTransmitOutcome> _transmitEquivalentContactRequest({
  required P2PService p2pService,
  required BuiltContactRequestEnvelope envelope,
  required String equivalenceKey,
  required bool requireExactCallWakeReceipt,
  required bool requireFresh,
}) {
  final attempts = _recentContactRequests[p2pService] ??= {};
  final now = clock.now();
  attempts.removeWhere(
    (_, attempt) =>
        attempt.acceptedAt != null &&
        now.difference(attempt.acceptedAt!) >= _equivalentContactRequestWindow,
  );
  if (!requireFresh && !requireExactCallWakeReceipt) {
    final previous = attempts[equivalenceKey];
    if (previous != null) return previous.future;
  }

  late final _EquivalentContactRequestAttempt attempt;
  final future =
      transmitContactRequestEnvelope(
        p2pService: p2pService,
        envelope: envelope,
        requireExactCallWakeReceipt: requireExactCallWakeReceipt,
      ).then(
        (outcome) {
          if (outcome.result == SendContactRequestResult.success &&
              (envelope.callWakeHandle == null ||
                  outcome.exactCallWakeReceipt)) {
            attempt.acceptedAt = clock.now();
          } else {
            // A failed send or missing grant receipt must remain immediately retryable.
            if (identical(attempts[equivalenceKey], attempt)) {
              attempts.remove(equivalenceKey);
            }
          }
          return outcome;
        },
        onError: (Object error, StackTrace stack) {
          if (identical(attempts[equivalenceKey], attempt)) {
            attempts.remove(equivalenceKey);
          }
          Error.throwWithStackTrace(error, stack);
        },
      );
  attempt = _EquivalentContactRequestAttempt(future);
  attempts[equivalenceKey] = attempt;
  return future;
}

/// Sends a contact request to a peer after scanning their QR code.
///
/// This function:
/// 1. Verifies P2P node is running
/// 2. Loads own identity
/// 3. Builds and signs a contact request payload
/// 4. If [recipientPublicKey] is provided, encrypts as v2 envelope
/// 5. Otherwise sends as v1 plaintext
/// 6. Sends via P2P to the target peer
///
/// [markAsNewRequest] adds the signed Task 12b `cr` marker, which lets an
/// updated receiver answer with one durable repair reply. Callers set it only
/// for peers verified as updated: an older receiver rejects the marked
/// signature. A marked request must be encrypted (v2); there is no unmarked or
/// plaintext fallback.
///
/// Returns the result of the operation.
Future<SendContactRequestResult> sendContactRequest({
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  required Bridge bridge,
  required String targetPeerId,
  String? recipientPublicKey,
  ContactRequestSendIntent intent = ContactRequestSendIntent.newRequest,
  // FDC-09 §12 / CV-14: read-only per-send resolver for the wake-token THIS node
  // minted for [targetPeerId] (distributing to a contact the token it should
  // present to wake us). Emitted — signed, inside the v2 encrypted envelope —
  // ONLY when it returns non-null AND [recipientPublicKey] != null (v2). It NEVER
  // mints/registers (INV-5: that is once-per-cycle) and NEVER rides v1 (INV-6).
  // Null / gated-off ⇒ no `wt` (the dark-landing default).
  Future<String?> Function(String peerId)? resolveWakeToken,
  // Call-only capability transport. Like `wt`, this is resolved once per send,
  // signed inside the plaintext, and carried only by the encrypted v2 path.
  ResolveCallWakeHandle? resolveCallWakeHandle,
  // Invoked only after the cwh-bearing v2 request returns the receiver's exact
  // durable-store receipt. A callback failure leaves distribution pending but
  // cannot undo delivery.
  OnCallWakeHandleDistributed? onCallWakeHandleDistributed,
  // Call preflight can require a live, versioned receipt proof and disable the
  // inbox fallback. Every encrypted request carrying a call-wake grant still
  // asks for that exact receipt; ordinary contact delivery may succeed without
  // it, but the grant remains distribution-pending until proof arrives.
  bool requireExactCallWakeReceipt = false,
  // Soliciting a new remote reply cannot reuse an earlier acknowledgement.
  bool requireFresh = false,
  bool markAsNewRequest = false,
}) async {
  final targetPrefix = targetPeerId.length > 10
      ? targetPeerId.substring(0, 10)
      : targetPeerId;

  emitFlowEvent(
    layer: 'FL',
    event: 'CONTACT_REQUEST_SEND_START',
    details: {'targetPeerId': targetPrefix},
  );

  // 1. Check P2P node is running
  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_NODE_NOT_RUNNING',
      details: {'isStarted': p2pService.currentState.isStarted},
    );
    return SendContactRequestResult.nodeNotRunning;
  }

  final build = await buildContactRequestEnvelope(
    identityRepo: identityRepo,
    bridge: bridge,
    targetPeerId: targetPeerId,
    recipientPublicKey: recipientPublicKey,
    intent: intent,
    resolveWakeToken: resolveWakeToken,
    resolveCallWakeHandle: resolveCallWakeHandle,
    requireExactCallWakeReceipt: requireExactCallWakeReceipt,
    control: markAsNewRequest
        ? ContactRequestControl.newRequest(
            id: const Uuid().v4(),
            to: targetPeerId,
          )
        : null,
  );
  final envelope = build.envelope;
  if (envelope == null) return build.failure!;

  final outcome = await _transmitEquivalentContactRequest(
    p2pService: p2pService,
    envelope: envelope,
    equivalenceKey: build.equivalenceKey!,
    requireExactCallWakeReceipt: requireExactCallWakeReceipt,
    requireFresh: requireFresh || intent == ContactRequestSendIntent.newRequest,
  );
  if (outcome.exactCallWakeReceipt) {
    await markContactRequestCallWakeHandleDistributed(
      envelope: envelope,
      onCallWakeHandleDistributed: onCallWakeHandleDistributed,
    );
  }
  return outcome.result;
}

/// Reports an exactly-receipted call-wake grant as distributed. A callback
/// failure leaves distribution pending but cannot undo delivery.
Future<void> markContactRequestCallWakeHandleDistributed({
  required BuiltContactRequestEnvelope envelope,
  required OnCallWakeHandleDistributed? onCallWakeHandleDistributed,
}) async {
  final grant = envelope.callWakeHandle;
  if (grant == null || onCallWakeHandleDistributed == null) return;
  try {
    await onCallWakeHandleDistributed(envelope.targetPeerId, grant);
  } catch (_) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_WAKE_HANDLE_DISTRIBUTION_STATE_ERROR',
      details: {'reason': 'callback_failed'},
    );
  }
}

/// Builds, signs and (when [recipientPublicKey] is set) encrypts one contact
/// request. Each call mints a fresh message ID unless [control] fixes it.
///
/// When [control] is present the request is marked: `cr` is signed inside the
/// plaintext and the outer `msgId` equals `cr.id`. A marked request requires
/// [recipientPublicKey]; it is never sent as plaintext v1.
Future<ContactRequestEnvelopeBuild> buildContactRequestEnvelope({
  required IdentityRepository identityRepo,
  required Bridge bridge,
  required String targetPeerId,
  String? recipientPublicKey,
  ContactRequestSendIntent intent = ContactRequestSendIntent.newRequest,
  Future<String?> Function(String peerId)? resolveWakeToken,
  ResolveCallWakeHandle? resolveCallWakeHandle,
  bool requireExactCallWakeReceipt = false,
  ContactRequestControl? control,
}) async {
  final targetPrefix = targetPeerId.length > 10
      ? targetPeerId.substring(0, 10)
      : targetPeerId;

  // 2. Load own identity
  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_NO_IDENTITY',
      details: {},
    );
    return const ContactRequestEnvelopeBuild.failed(
      SendContactRequestResult.noIdentity,
    );
  }

  if (control != null && recipientPublicKey == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_MARKED_REQUIRES_ENCRYPTION',
      details: {},
    );
    return const ContactRequestEnvelopeBuild.failed(
      SendContactRequestResult.encryptionError,
    );
  }

  // 3. Build unsigned payload (same format as QR, plus mlkem key)
  final now = DateTime.now().toUtc();
  final timestamp = now.toIso8601String();
  final sanitizedUsername = sanitizeUsername(identity.username);
  // FDC-09 §12 / CV-14: resolve the wake-token to distribute — v2 (encrypted,
  // per-contact-private) ONLY, read-only. It MUST be added BEFORE dataToSign so
  // the recipient's signature covers it (their reconstruction re-includes `wt`).
  final wakeToken = (recipientPublicKey != null && resolveWakeToken != null)
      ? await resolveWakeToken(targetPeerId)
      : null;
  final resolvedCallWakeHandle =
      (recipientPublicKey != null && resolveCallWakeHandle != null)
      ? await resolveCallWakeHandle(targetPeerId)
      : null;
  final callWakeHandle =
      resolvedCallWakeHandle != null &&
          resolvedCallWakeHandle.isValidAt(now.millisecondsSinceEpoch)
      ? resolvedCallWakeHandle
      : null;
  if (requireExactCallWakeReceipt &&
      (recipientPublicKey == null || callWakeHandle == null)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_CALL_WAKE_RECEIPT_PRECONDITION_FAILED',
      details: {
        'targetPeerId': targetPrefix,
        'reason': 'encrypted_current_grant_required',
      },
    );
    return const ContactRequestEnvelopeBuild.failed(
      SendContactRequestResult.sendFailed,
    );
  }
  final callWakeReceiptChallenge = callWakeHandle == null
      ? null
      : const Uuid().v4();
  final unsignedPayload = SplayTreeMap<String, dynamic>.from({
    if (identity.mlKemPublicKey != null) 'mlkem': identity.mlKemPublicKey,
    'ns': identity.peerId,
    'pk': identity.publicKey,
    'rv': rendezvousAddress,
    'ts': timestamp,
    'un': sanitizedUsername,
    if (callWakeHandle != null) 'cwh': callWakeHandle.toCanonicalMap(),
    'cwr': ?callWakeReceiptChallenge,
    if (wakeToken != null && wakeToken.isNotEmpty) 'wt': wakeToken,
    if (control != null) 'cr': control.toCanonicalMap(),
  });
  final dataToSign = jsonEncode(unsignedPayload);
  // Fresh IDs, signature times and receipt challenges do not change the
  // identity/capability material already delivered to this exact recipient.
  final equivalentPayload = SplayTreeMap<String, dynamic>.from(unsignedPayload)
    ..remove('ts')
    ..remove('cwr');
  if (control != null) {
    // The marker earns a repair reply; only its generated ID is incidental.
    equivalentPayload['cr'] = control.toCanonicalMap()..remove('id');
  }
  final equivalenceKey = sha256
      .convert(
        utf8.encode(
          jsonEncode([targetPeerId, recipientPublicKey, equivalentPayload]),
        ),
      )
      .toString();

  // 4. Sign the payload
  emitFlowEvent(
    layer: 'FL',
    event: 'CONTACT_REQUEST_SEND_SIGNING',
    details: {},
  );

  final signResponse = await callSignPayload(
    bridge: bridge,
    dataToSign: dataToSign,
    privateKey: identity.privateKey,
  );

  if (signResponse['ok'] != true) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_SIGNING_ERROR',
      details: {
        'errorCode': signResponse['errorCode'],
        'errorMessage': signResponse['errorMessage'],
      },
    );
    return const ContactRequestEnvelopeBuild.failed(
      SendContactRequestResult.signingError,
    );
  }

  // 5. Add signature to payload
  final signature = signResponse['signature'] as String;
  final signedPayload = SplayTreeMap<String, dynamic>.from({
    ...unsignedPayload,
    'sig': signature,
  });
  final signedPayloadJson = jsonEncode(signedPayload);

  // 6. Build message envelope (v1 or v2)
  if (recipientPublicKey == null) {
    // v1: Plaintext envelope (backward compat)
    final v1Message = {
      'type': 'contact_request',
      'version': '1',
      'intent': intent.wireValue,
      'payload': signedPayload,
    };
    return ContactRequestEnvelopeBuild.built(
      BuiltContactRequestEnvelope(
        senderPeerId: identity.peerId,
        targetPeerId: targetPeerId,
        messageJson: jsonEncode(v1Message),
        encrypted: false,
      ),
      equivalenceKey: equivalenceKey,
    );
  }

  // v2: Encrypt the signed payload. A marked request's operation ID is its
  // message ID, so the encryption AAD and the signed marker agree.
  final msgId = control?.id ?? const Uuid().v4();
  final ts = DateTime.now().toUtc().toIso8601String();

  emitFlowEvent(
    layer: 'FL',
    event: 'CONTACT_REQUEST_SEND_ENCRYPTING',
    details: {'targetPeerId': targetPrefix},
  );

  final encryptResponse = await callEncryptContactRequest(
    bridge: bridge,
    recipientPublicKey: recipientPublicKey,
    signedPayloadJson: signedPayloadJson,
    msgId: msgId,
    ts: ts,
  );

  if (encryptResponse['ok'] != true) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_ENCRYPTION_ERROR',
      details: {
        'errorCode': encryptResponse['errorCode'],
        'errorMessage': encryptResponse['errorMessage'],
      },
    );
    // No silent downgrade: if encryption was requested but failed, return error.
    return const ContactRequestEnvelopeBuild.failed(
      SendContactRequestResult.encryptionError,
    );
  }

  // Validate required fields from encrypt response
  final ephemeralPublicKey = encryptResponse['ephemeralPublicKey'];
  final ciphertext = encryptResponse['ciphertext'];
  final nonce = encryptResponse['nonce'];

  if (ephemeralPublicKey is! String ||
      ciphertext is! String ||
      nonce is! String ||
      ephemeralPublicKey.isEmpty ||
      ciphertext.isEmpty ||
      nonce.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_ENCRYPTION_ERROR',
      details: {'reason': 'malformed encrypt response'},
    );
    return const ContactRequestEnvelopeBuild.failed(
      SendContactRequestResult.encryptionError,
    );
  }

  final v2Message = {
    'type': 'contact_request',
    'version': '2',
    'intent': intent.wireValue,
    'msgId': msgId,
    'ts': ts,
    if (sanitizedUsername.isNotEmpty) 'senderUsername': sanitizedUsername,
    'encrypted': {
      'ephemeralPublicKey': ephemeralPublicKey,
      'ciphertext': ciphertext,
      'nonce': nonce,
    },
  };
  return ContactRequestEnvelopeBuild.built(
    BuiltContactRequestEnvelope(
      senderPeerId: identity.peerId,
      targetPeerId: targetPeerId,
      messageJson: jsonEncode(v2Message),
      encrypted: true,
      msgId: msgId,
      callWakeHandle: callWakeHandle,
      callWakeReceiptChallenge: callWakeReceiptChallenge,
    ),
    equivalenceKey: equivalenceKey,
  );
}

/// Transmits an already built envelope, byte for byte: LAN (only without a
/// call-wake grant), then one direct discover/dial/send, then the relay inbox
/// unless an exact call-wake receipt is required.
Future<ContactRequestTransmitOutcome> transmitContactRequestEnvelope({
  required P2PService p2pService,
  required BuiltContactRequestEnvelope envelope,
  bool requireExactCallWakeReceipt = false,
}) async {
  final targetPeerId = envelope.targetPeerId;
  final targetPrefix = targetPeerId.length > 10
      ? targetPeerId.substring(0, 10)
      : targetPeerId;
  final messageJson = envelope.messageJson;
  final callWakeReceiptChallenge = envelope.callWakeReceiptChallenge;

  bool hasExactCallWakeReceipt(SendMessageResult sendResult) {
    if (callWakeReceiptChallenge == null ||
        !sendResult.sent ||
        sendResult.acked != true ||
        sendResult.reply == null) {
      return false;
    }
    try {
      final reply = jsonDecode(sendResult.reply!);
      return reply is Map<String, dynamic> &&
          reply['callWakeReceipt'] == callWakeReceiptChallenge;
    } on FormatException {
      return false;
    }
  }

  // 7. Try to send (with retries)
  emitFlowEvent(
    layer: 'FL',
    event: 'CONTACT_REQUEST_SEND_SENDING',
    details: {'targetPeerId': targetPrefix},
  );

  // 7.5. Try local WiFi delivery first
  // A boolean LAN success cannot prove that the receiver durably stored the
  // exact grant generation, so cwh-bearing requests always use a reply-capable
  // direct transport (then the ordinary inbox fallback when permitted).
  if (envelope.callWakeHandle == null && p2pService.isLocalPeer(targetPeerId)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_LOCAL_ATTEMPT',
      details: {'targetPeerId': targetPrefix},
    );
    final localSent = await p2pService.sendLocalMessage(
      targetPeerId,
      messageJson,
      envelope.senderPeerId,
    );
    if (localSent) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_SEND_LOCAL_SUCCESS',
        details: {'targetPeerId': targetPrefix},
      );
      return const ContactRequestTransmitOutcome(
        SendContactRequestResult.success,
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_LOCAL_FAILED',
      details: {'targetPeerId': targetPrefix},
    );
    // Fall through to relay path
  }

  // Single discover → dial → send attempt before inbox fallback.
  try {
    final peer = await p2pService.discoverPeer(targetPeerId);
    if (peer == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_SEND_PEER_NOT_FOUND',
        details: {'targetPeerId': targetPrefix},
      );
    } else {
      final dialed = await p2pService.dialPeer(
        targetPeerId,
        addresses: peer.addresses,
      );

      if (!dialed) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_REQUEST_SEND_DIAL_FAILED',
          details: {'targetPeerId': targetPrefix},
        );
      } else {
        final sendResult = await p2pService.sendMessageWithReply(
          targetPeerId,
          messageJson,
        );
        final messageAccepted = sendResult.sent && sendResult.acknowledged;
        final exactCallWakeReceipt = hasExactCallWakeReceipt(sendResult);
        final deliveryAccepted = requireExactCallWakeReceipt
            ? exactCallWakeReceipt
            : messageAccepted;
        if (!deliveryAccepted) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONTACT_REQUEST_SEND_MESSAGE_FAILED',
            details: {
              'targetPeerId': targetPrefix,
              'sent': sendResult.sent,
              'acked': sendResult.acknowledged,
            },
          );
        } else {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONTACT_REQUEST_SEND_SUCCESS',
            details: {'targetPeerId': targetPrefix},
          );
          return ContactRequestTransmitOutcome(
            SendContactRequestResult.success,
            exactCallWakeReceipt: exactCallWakeReceipt,
          );
        }
      }
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_ERROR',
      details: {'error': e.toString()},
    );
  }

  if (requireExactCallWakeReceipt) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_CALL_WAKE_RECEIPT_FAILED',
      details: {'targetPeerId': targetPrefix},
    );
    return const ContactRequestTransmitOutcome(
      SendContactRequestResult.sendFailed,
    );
  }

  // All retries exhausted — try offline inbox fallback.
  emitFlowEvent(
    layer: 'FL',
    event: 'CONTACT_REQUEST_SEND_INBOX_FALLBACK_START',
    details: {'targetPeerId': targetPrefix},
  );

  try {
    final storedInInbox = await p2pService.storeInInbox(
      targetPeerId,
      messageJson,
    );
    if (storedInInbox) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_SEND_SUCCESS',
        details: {'targetPeerId': targetPrefix, 'via': 'inbox'},
      );
      // Inbox acceptance proves storage by the relay, not durable application
      // storage by the receiver. Keep any cwh generation pending until a later
      // direct exchange returns its exact receipt.
      return const ContactRequestTransmitOutcome(
        SendContactRequestResult.success,
      );
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_INBOX_FALLBACK_ERROR',
      details: {'error': e.toString()},
    );
  }

  return const ContactRequestTransmitOutcome(
    SendContactRequestResult.sendFailed,
  );
}
