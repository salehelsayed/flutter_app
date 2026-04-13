import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Result of handling an incoming P2P message.
enum HandleMessageResult {
  /// New contact request received and stored.
  contactRequest,

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
/// Returns a tuple of (result, request, peerId) where request is non-null
/// when result == contactRequest, and peerId is non-null when result ==
/// contactKeyUpdated (extracted from the decrypted payload).
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

  // 8. Check if already a contact (and update ML-KEM key if missing)
  final isContact = await contactRepo.contactExists(peerId);
  if (isContact) {
    final mlkemFromPayload = payload['mlkem'] as String?;
    final existingContact = await contactRepo.getContact(peerId);

    if (existingContact != null &&
        existingContact.mlKemPublicKey == null &&
        mlkemFromPayload != null) {
      await contactRepo.addContact(
        existingContact.copyWith(mlKemPublicKey: mlkemFromPayload),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_KEY_UPDATED',
        details: {'peerId': peerIdPrefix},
      );
      return (HandleMessageResult.contactKeyUpdated, null, peerId);
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_ALREADY_CONTACT',
      details: {'peerId': peerIdPrefix},
    );
    return (HandleMessageResult.alreadyContact, null, null);
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

  // 10. Create and store the request
  final request = ContactRequestModel.fromP2PPayload(payload);

  try {
    await requestRepo.addRequest(request);

    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_STORED',
      details: {'peerId': peerIdPrefix, 'username': request.username},
    );

    return (HandleMessageResult.contactRequest, request, null);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_STORE_ERROR',
      details: {'error': e.toString()},
    );
    return (HandleMessageResult.invalidMessage, null, null);
  }
}
