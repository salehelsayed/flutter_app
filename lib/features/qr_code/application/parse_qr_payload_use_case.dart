import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

/// Result of parsing a QR payload.
enum ParseQRResult {
  /// Successfully parsed and verified.
  success,

  /// The QR data has invalid JSON or an invalid timestamp.
  invalidJson,

  /// Required fields are missing from the payload.
  missingFields,

  /// The signature verification failed.
  invalidSignature,

  /// The timestamp is too old (expired).
  expired,

  /// User scanned their own QR code.
  selfScan,
}

/// Parses and validates a QR code payload string.
///
/// This function:
/// 1. Parses the JSON string
/// 2. Validates all required fields are present
/// 3. Checks the payload isn't expired (optional, based on maxAge)
/// 4. Verifies the signature using the bridge
/// 5. Checks the user isn't scanning their own QR code
///
/// Returns a tuple of (result, contact) where contact is non-null on success.
Future<(ParseQRResult, ContactModel?)> parseQRPayload({
  required String qrString,
  required Bridge bridge,
  required String ownPeerId,
  Duration maxAge = const Duration(hours: 24),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_PARSE_START',
    details: {'length': qrString.length},
  );

  // 1. Parse JSON
  Map<String, dynamic> json;
  try {
    json = jsonDecode(qrString) as Map<String, dynamic>;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_PARSE_INVALID_JSON',
      details: {'error': e.toString()},
    );
    return (ParseQRResult.invalidJson, null);
  }

  // 2. Validate required fields
  final requiredFields = ['pk', 'ns', 'rv', 'ts', 'sig'];
  for (final field in requiredFields) {
    if (json[field] == null || json[field].toString().isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'QR_PARSE_MISSING_FIELD',
        details: {'field': field},
      );
      return (ParseQRResult.missingFields, null);
    }
  }

  for (final field in ['rv', 'un', 'mlkem']) {
    if (json[field] != null && json[field] is! String) {
      emitFlowEvent(
        layer: 'FL',
        event: 'QR_PARSE_INVALID_FIELD_TYPE',
        details: {'field': field},
      );
      return (ParseQRResult.invalidJson, null);
    }
  }

  final rawPeerId = json['ns'];
  final rawPublicKey = json['pk'];
  final rawTimestamp = json['ts'];
  final rawSignature = json['sig'];
  if (rawPeerId is! String ||
      rawPublicKey is! String ||
      rawTimestamp is! String ||
      rawSignature is! String) {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_PARSE_IDENTITY_BINDING_MISMATCH',
      details: {},
    );
    return (ParseQRResult.invalidSignature, null);
  }
  final publicKey = rawPublicKey;
  final timestamp = rawTimestamp;
  final signature = rawSignature;

  // 2b. The peer ID must be the libp2p ID of the QR's own Ed25519 account key,
  //     checked before the payload can count as a self-scan or a contact.
  final peerId = ed25519PublicKeyCanonicalPeerId(
    base64PublicKey: publicKey,
    claimedPeerId: rawPeerId,
  );
  if (peerId == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_PARSE_IDENTITY_BINDING_MISMATCH',
      details: {},
    );
    return (ParseQRResult.invalidSignature, null);
  }

  // 3. Check for self-scan
  if (peerId == ownPeerId) {
    emitFlowEvent(layer: 'FL', event: 'QR_PARSE_SELF_SCAN', details: {});
    return (ParseQRResult.selfScan, null);
  }

  // 4. Admit only readable timestamps that are not in the future.
  final payloadTime = DateTime.tryParse(timestamp)?.toUtc();
  final now = DateTime.now().toUtc();
  if (payloadTime == null || payloadTime.isAfter(now)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_PARSE_TIMESTAMP_ERROR',
      details: {'reason': payloadTime == null ? 'unreadable' : 'future'},
    );
    return (ParseQRResult.invalidJson, null);
  }
  if (now.difference(payloadTime) > maxAge) {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_PARSE_EXPIRED',
      details: {'timestamp': timestamp},
    );
    return (ParseQRResult.expired, null);
  }

  // 5. Verify signature
  // Build the unsigned payload (same fields as signed, minus sig)
  final unsignedPayload = SplayTreeMap<String, dynamic>.from({
    if (json['mlkem'] != null) 'mlkem': json['mlkem'],
    'ns': json['ns'],
    'pk': json['pk'],
    'rv': json['rv'],
    'ts': json['ts'],
    if (json['un'] != null) 'un': json['un'],
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
      event: 'QR_PARSE_INVALID_SIGNATURE',
      details: {},
    );
    return (ParseQRResult.invalidSignature, null);
  }

  // 6. Create contact model
  final contact = ContactModel.fromQRPayload({...json, 'ns': peerId});

  emitFlowEvent(
    layer: 'FL',
    event: 'QR_PARSE_SUCCESS',
    details: {'peerId': peerId.substring(0, 10)},
  );

  return (ParseQRResult.success, contact);
}
