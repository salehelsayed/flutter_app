import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/network_constants.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Result of sending a contact request.
enum SendContactRequestResult {
  /// Successfully sent the contact request.
  success,

  /// No identity found in repository.
  noIdentity,

  /// Signing operation failed.
  signingError,

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
/// 4. Wraps it in a contact_request message
/// 5. Sends via P2P to the target peer
///
/// Returns the result of the operation.
Future<SendContactRequestResult> sendContactRequest({
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  required Bridge bridge,
  required String targetPeerId,
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
  final unsignedPayload = SplayTreeMap<String, dynamic>.from({
    if (identity.mlKemPublicKey != null) 'mlkem': identity.mlKemPublicKey,
    'ns': identity.peerId,
    'pk': identity.publicKey,
    'rv': RENDEZVOUS_ADDRESS,
    'ts': timestamp,
    'un': identity.username,
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

  // 6. Wrap in contact_request message
  final message = {
    'type': 'contact_request',
    'version': '1',
    'payload': signedPayload,
  };
  final messageJson = jsonEncode(message);

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
      targetPeerId, messageJson, identity.peerId);
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

  // Attempt to send with exponential backoff (3 attempts)
  const maxAttempts = 3;
  const baseDelay = Duration(milliseconds: 500);

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      // Try to discover the peer first
      final peer = await p2pService.discoverPeer(targetPeerId);
      if (peer == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_REQUEST_SEND_PEER_NOT_FOUND',
          details: {'attempt': attempt, 'targetPeerId': targetPrefix},
        );

        if (attempt < maxAttempts) {
          await Future.delayed(baseDelay * attempt);
          continue;
        }
        break;
      }

      // Dial and send
      final dialed = await p2pService.dialPeer(
        targetPeerId,
        addresses: peer.addresses,
      );

      if (!dialed) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_REQUEST_SEND_DIAL_FAILED',
          details: {'attempt': attempt, 'targetPeerId': targetPrefix},
        );

        if (attempt < maxAttempts) {
          await Future.delayed(baseDelay * attempt);
          continue;
        }
        break;
      }

      final sent = await p2pService.sendMessage(targetPeerId, messageJson);
      if (!sent) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_REQUEST_SEND_MESSAGE_FAILED',
          details: {'attempt': attempt, 'targetPeerId': targetPrefix},
        );

        if (attempt < maxAttempts) {
          await Future.delayed(baseDelay * attempt);
          continue;
        }
        break;
      }

      // Success!
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_SEND_SUCCESS',
        details: {'targetPeerId': targetPrefix, 'attempts': attempt},
      );
      return SendContactRequestResult.success;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_SEND_ERROR',
        details: {'attempt': attempt, 'error': e.toString()},
      );

      if (attempt < maxAttempts) {
        await Future.delayed(baseDelay * attempt);
        continue;
      }
      break;
    }
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
        details: {
          'targetPeerId': targetPrefix,
          'via': 'inbox',
        },
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
