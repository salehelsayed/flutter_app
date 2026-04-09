import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/network_constants.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
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
  final timestamp = DateTime.now().toUtc().toIso8601String();
  final sanitizedUsername = sanitizeUsername(identity.username);
  final unsignedPayload = SplayTreeMap<String, dynamic>.from({
    if (identity.mlKemPublicKey != null) 'mlkem': identity.mlKemPublicKey,
    'ns': identity.peerId,
    'pk': identity.publicKey,
    'rv': RENDEZVOUS_ADDRESS,
    'ts': timestamp,
    'un': sanitizedUsername,
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
  if (p2pService.isLocalPeer(targetPeerId)) {
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
        if (!sendResult.sent || !sendResult.acknowledged) {
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
