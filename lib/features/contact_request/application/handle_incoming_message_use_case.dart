import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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
/// 3. Verifies the signature
/// 4. Checks not already a contact
/// 5. Checks no duplicate pending request
/// 6. Stores in contact_requests table
///
/// Returns a tuple of (result, request) where request is non-null
/// when result == contactRequest.
Future<(HandleMessageResult, ContactRequestModel?)> handleIncomingMessage({
  required ChatMessage message,
  required Bridge bridge,
  required ContactRequestRepository requestRepo,
  required ContactRepository contactRepo,
  required String ownPeerId,
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
    emitFlowEvent(
      layer: 'FL',
      event: 'INCOMING_MESSAGE_NOT_JSON',
      details: {},
    );
    return (HandleMessageResult.regularMessage, null);
  }

  // 2. Check if type == "contact_request"
  final type = json['type'] as String?;
  if (type != 'contact_request') {
    emitFlowEvent(
      layer: 'FL',
      event: 'INCOMING_MESSAGE_NOT_CONTACT_REQUEST',
      details: {'type': type},
    );
    return (HandleMessageResult.regularMessage, null);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CONTACT_REQUEST_RECEIVED',
    details: {},
  );

  // 3. Extract payload
  final payload = json['payload'] as Map<String, dynamic>?;
  if (payload == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_MISSING_PAYLOAD',
      details: {},
    );
    return (HandleMessageResult.invalidMessage, null);
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
      return (HandleMessageResult.invalidMessage, null);
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
    return (HandleMessageResult.invalidMessage, null);
  }

  // 6. Check not from self
  if (peerId == ownPeerId) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_FROM_SELF',
      details: {},
    );
    return (HandleMessageResult.invalidMessage, null);
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
    return (HandleMessageResult.invalidMessage, null);
  }

  // 8. Check if already a contact
  final isContact = await contactRepo.contactExists(peerId);
  if (isContact) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_ALREADY_CONTACT',
      details: {'peerId': peerIdPrefix},
    );
    return (HandleMessageResult.alreadyContact, null);
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
    return (HandleMessageResult.duplicateRequest, null);
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

    return (HandleMessageResult.contactRequest, request);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_STORE_ERROR',
      details: {'error': e.toString()},
    );
    return (HandleMessageResult.invalidMessage, null);
  }
}
