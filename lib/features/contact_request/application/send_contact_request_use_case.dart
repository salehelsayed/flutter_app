import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/network_constants.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
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

  // 2. Load own identity
  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_NO_IDENTITY',
      details: {},
    );
    return SendContactRequestResult.noIdentity;
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
    return SendContactRequestResult.sendFailed;
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
  });
  final dataToSign = jsonEncode(unsignedPayload);

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
    return SendContactRequestResult.signingError;
  }

  // 5. Add signature to payload
  final signature = signResponse['signature'] as String;
  final signedPayload = SplayTreeMap<String, dynamic>.from({
    ...unsignedPayload,
    'sig': signature,
  });
  final signedPayloadJson = jsonEncode(signedPayload);

  Future<void> markCallWakeHandleDistributed() async {
    if (callWakeHandle == null || onCallWakeHandleDistributed == null) return;
    try {
      await onCallWakeHandleDistributed(targetPeerId, callWakeHandle);
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_WAKE_HANDLE_DISTRIBUTION_STATE_ERROR',
        details: {'targetPeerId': targetPrefix, 'reason': 'callback_failed'},
      );
    }
  }

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

  // 6. Build message envelope (v1 or v2)
  String messageJson;

  if (recipientPublicKey != null) {
    // v2: Encrypt the signed payload
    final msgId = const Uuid().v4();
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
      return SendContactRequestResult.encryptionError;
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
      return SendContactRequestResult.encryptionError;
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
    messageJson = jsonEncode(v2Message);
  } else {
    // v1: Plaintext envelope (backward compat)
    final v1Message = {
      'type': 'contact_request',
      'version': '1',
      'intent': intent.wireValue,
      'payload': signedPayload,
    };
    messageJson = jsonEncode(v1Message);
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
  if (callWakeHandle == null && p2pService.isLocalPeer(targetPeerId)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_LOCAL_ATTEMPT',
      details: {'targetPeerId': targetPrefix},
    );
    final localSent = await p2pService.sendLocalMessage(
      targetPeerId,
      messageJson,
      identity.peerId,
    );
    if (localSent) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_SEND_LOCAL_SUCCESS',
        details: {'targetPeerId': targetPrefix},
      );
      await markCallWakeHandleDistributed();
      return SendContactRequestResult.success;
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
          if (exactCallWakeReceipt) {
            await markCallWakeHandleDistributed();
          }
          return SendContactRequestResult.success;
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
    return SendContactRequestResult.sendFailed;
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
      return SendContactRequestResult.success;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SEND_INBOX_FALLBACK_ERROR',
      details: {'error': e.toString()},
    );
  }

  return SendContactRequestResult.sendFailed;
}
