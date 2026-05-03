import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';

const groupKeyUpdateSignatureAlgorithm = 'ed25519';
const groupKeyUpdateSignatureSchemaVersion = 1;
const groupKeyUpdateSignedPayloadType = 'group_key_update';

String canonicalGroupKeyUpdateSignedPayload({
  required String groupId,
  required String sourcePeerId,
  required int keyGeneration,
  required String encryptedKey,
  String? sourceDeviceId,
  String? sourceTransportPeerId,
  String? recipientPeerId,
  String? recipientDeviceId,
  String? recipientTransportPeerId,
  String? recipientKeyPackageId,
}) {
  return canonicalizeGroupEventLogPayload({
    'schemaVersion': groupKeyUpdateSignatureSchemaVersion,
    'type': groupKeyUpdateSignedPayloadType,
    'groupId': groupId,
    'sourcePeerId': sourcePeerId,
    if (sourceDeviceId != null && sourceDeviceId.isNotEmpty)
      'sourceDeviceId': sourceDeviceId,
    if (sourceTransportPeerId != null && sourceTransportPeerId.isNotEmpty)
      'sourceTransportPeerId': sourceTransportPeerId,
    if (recipientPeerId != null && recipientPeerId.isNotEmpty)
      'recipientPeerId': recipientPeerId,
    if (recipientDeviceId != null && recipientDeviceId.isNotEmpty)
      'recipientDeviceId': recipientDeviceId,
    if (recipientTransportPeerId != null && recipientTransportPeerId.isNotEmpty)
      'recipientTransportPeerId': recipientTransportPeerId,
    if (recipientKeyPackageId != null && recipientKeyPackageId.isNotEmpty)
      'recipientKeyPackageId': recipientKeyPackageId,
    'keyGeneration': keyGeneration,
    'encryptedKey': encryptedKey,
  });
}
