import 'dart:convert';
import 'dart:collection';

import 'package:flutter_app/core/constants/network_constants.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Result of building a QR payload
enum BuildQRPayloadResult {
  /// Successfully built and signed the payload
  success,

  /// No identity found in repository
  noIdentity,

  /// Signing operation failed
  signingError,
}

/// Builds a signed QR payload containing the user's identity information.
///
/// Returns a tuple of (result, jsonString?).
/// On success, jsonString contains the canonical JSON ready for QR encoding.
/// Pass [cachedIdentity] to skip the redundant `repo.loadIdentity()` call.
Future<(BuildQRPayloadResult, String?)> buildQRPayload({
  required IdentityRepository repo,
  required Future<Map<String, dynamic>> Function(String, String) callSign,
  IdentityModel? cachedIdentity,
}) async {
  // Step 1: Emit start event
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BUILD_PAYLOAD_START',
    details: {},
  );

  // Step 2: Use cached identity or load from repository
  final identity = cachedIdentity ?? await repo.loadIdentity();

  // Step 3: Check if identity exists
  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_BUILD_PAYLOAD_NO_IDENTITY',
      details: {},
    );
    return (BuildQRPayloadResult.noIdentity, null);
  }

  // Step 4: Emit identity found event
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BUILD_PAYLOAD_IDENTITY_LOADED',
    details: {'peerId': identity.peerId.substring(0, 12)},
  );

  // Step 5: Build unsigned payload with sorted keys
  // Note: ML-KEM public key is NOT included in QR — it's exchanged via
  // contact request message to keep the QR code compact and scannable.
  final timestamp = DateTime.now().toUtc().toIso8601String();
  final unsignedPayload = SplayTreeMap<String, dynamic>.from({
    'ns': identity.peerId,
    'pk': identity.publicKey,
    'rv': RENDEZVOUS_ADDRESS,
    'ts': timestamp,
    'un': identity.username,
  });

  // Step 6: Serialize to canonical JSON (sorted keys, no extra whitespace)
  final dataToSign = jsonEncode(unsignedPayload);

  // Step 7: Emit signing event
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BUILD_PAYLOAD_SIGNING',
    details: {},
  );

  // Step 8: Call bridge to sign
  final signResponse = await callSign(dataToSign, identity.privateKey);

  // Step 9: Check signing result
  if (signResponse['ok'] != true) {
    final errorCode = signResponse['errorCode'] ?? 'UNKNOWN';
    final errorMessage = signResponse['errorMessage'] ?? '';
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_BUILD_PAYLOAD_ERROR',
      details: {'errorCode': errorCode, 'errorMessage': errorMessage},
    );
    return (BuildQRPayloadResult.signingError, null);
  }

  // Step 10: Add signature to payload (maintaining sorted keys)
  final signature = signResponse['signature'] as String;
  final signedPayload = SplayTreeMap<String, dynamic>.from({
    ...unsignedPayload,
    'sig': signature,
  });

  // Step 11: Serialize final signed payload
  final finalJson = jsonEncode(signedPayload);

  // Step 12: Emit success event
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BUILD_PAYLOAD_SUCCESS',
    details: {},
  );

  // Step 13: Return success with JSON string
  return (BuildQRPayloadResult.success, finalJson);
}
