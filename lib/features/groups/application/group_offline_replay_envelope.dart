import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const groupOfflineReplayEnvelopeKind = 'group_offline_replay';
const groupOfflineReplayPayloadTypeMessage = 'group_message';
const groupOfflineReplayPayloadTypeReaction = 'group_reaction';
const groupOfflineReplaySignatureVersion = 1;
const groupOfflineReplaySignatureAlgorithm = 'ed25519';

class GroupOfflineReplaySignatureException implements Exception {
  GroupOfflineReplaySignatureException(this.reason);

  final String reason;

  @override
  String toString() => 'GroupOfflineReplaySignatureException($reason)';
}

class _ReplaySignatureVerification {
  const _ReplaySignatureVerification({
    required this.payloadType,
    required this.messageId,
    required this.senderPeerId,
    required this.senderDeviceId,
    required this.senderTransportPeerId,
    required this.plaintextHash,
  });

  final String payloadType;
  final String? messageId;
  final String senderPeerId;
  final String? senderDeviceId;
  final String? senderTransportPeerId;
  final String plaintextHash;
}

Future<String> buildGroupOfflineReplayEnvelope({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String payloadType,
  required String plaintext,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  GroupKeyInfo? keyInfo,
  String? messageId,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderKeyPackageId,
  List<String>? recipientPeerIds,
}) async {
  final resolvedKey = keyInfo ?? await _loadReplayKey(groupRepo, groupId);
  final encryptResult = await callGroupEncrypt(
    bridge,
    resolvedKey.encryptedKey,
    plaintext,
  );

  final ciphertext = encryptResult['ciphertext'];
  final nonce = encryptResult['nonce'];
  if (encryptResult['ok'] != true ||
      ciphertext is! String ||
      ciphertext.isEmpty ||
      nonce is! String ||
      nonce.isEmpty) {
    throw BridgeCommandException(
      'group.encrypt',
      encryptResult['errorCode']?.toString() ?? 'GROUP_ENCRYPT_FAILED',
      encryptResult['errorMessage']?.toString() ??
          'group.encrypt did not return ciphertext and nonce',
    );
  }

  final resolvedSenderPeerId = _requiredTrimmed(senderPeerId, 'senderPeerId');
  final resolvedSenderPublicKey = _requiredTrimmed(
    senderPublicKey,
    'senderPublicKey',
  );
  final normalizedDeviceId =
      _trimToNull(senderDeviceId) ?? resolvedSenderPeerId;
  final normalizedTransportPeerId =
      _trimToNull(senderTransportPeerId) ?? normalizedDeviceId;
  final normalizedMessageId = _trimToNull(messageId);
  final recipientSetHash = _recipientSetHash(recipientPeerIds);
  final signedPayload = _buildReplaySignedPayload(
    groupId: groupId,
    payloadType: payloadType,
    keyEpoch: resolvedKey.keyGeneration,
    ciphertext: ciphertext,
    nonce: nonce,
    plaintext: plaintext,
    messageId: normalizedMessageId,
    senderPeerId: resolvedSenderPeerId,
    senderDeviceId: normalizedDeviceId,
    senderTransportPeerId: normalizedTransportPeerId,
    senderPublicKey: resolvedSenderPublicKey,
    senderKeyPackageId: _trimToNull(senderKeyPackageId),
    recipientSetHash: recipientSetHash,
  );
  final signResult = await callSignPayload(
    bridge: bridge,
    dataToSign: signedPayload,
    privateKey: senderPrivateKey,
  );
  final signature = signResult['signature'];
  if (signResult['ok'] != true || signature is! String || signature.isEmpty) {
    throw StateError('Failed to sign group offline replay envelope');
  }

  return jsonEncode({
    'kind': groupOfflineReplayEnvelopeKind,
    'version': 1,
    'groupId': groupId,
    'payloadType': payloadType,
    'keyEpoch': resolvedKey.keyGeneration,
    if (normalizedMessageId != null) 'messageId': normalizedMessageId,
    'senderPeerId': resolvedSenderPeerId,
    'senderDeviceId': normalizedDeviceId,
    'senderTransportPeerId': normalizedTransportPeerId,
    'senderPublicKey': resolvedSenderPublicKey,
    if (_trimToNull(senderKeyPackageId) != null)
      'senderKeyPackageId': _trimToNull(senderKeyPackageId),
    'recipientSetHash': recipientSetHash,
    'ciphertext': ciphertext,
    'nonce': nonce,
    'signatureAlgorithm': groupOfflineReplaySignatureAlgorithm,
    'signedPayload': signedPayload,
    'signature': signature,
  });
}

Future<void> storeGroupOfflineReplayEnvelope({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String payloadType,
  required String plaintext,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  GroupKeyInfo? keyInfo,
  String? messageId,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderKeyPackageId,
  List<String>? recipientPeerIds,
}) async {
  final replayEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    payloadType: payloadType,
    plaintext: plaintext,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderPrivateKey: senderPrivateKey,
    keyInfo: keyInfo,
    messageId: messageId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderKeyPackageId: senderKeyPackageId,
    recipientPeerIds: recipientPeerIds,
  );

  await callGroupInboxStore(
    bridge,
    groupId,
    replayEnvelope,
    recipientPeerIds: recipientPeerIds,
  );
}

String encodeGroupOfflineReplayInboxRetryPayload({
  required String groupId,
  required String message,
  List<String>? recipientPeerIds,
}) {
  return jsonEncode({
    'groupId': groupId,
    'message': message,
    if (recipientPeerIds != null && recipientPeerIds.isNotEmpty)
      'recipientPeerIds': recipientPeerIds,
  });
}

Future<String> buildGroupOfflineReplayInboxRetryPayload({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String payloadType,
  required String plaintext,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  GroupKeyInfo? keyInfo,
  String? messageId,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderKeyPackageId,
  List<String>? recipientPeerIds,
}) async {
  final replayEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    payloadType: payloadType,
    plaintext: plaintext,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderPrivateKey: senderPrivateKey,
    keyInfo: keyInfo,
    messageId: messageId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderKeyPackageId: senderKeyPackageId,
    recipientPeerIds: recipientPeerIds,
  );

  return encodeGroupOfflineReplayInboxRetryPayload(
    groupId: groupId,
    message: replayEnvelope,
    recipientPeerIds: recipientPeerIds,
  );
}

Future<void> storeGroupOfflineReplayFromRetryPayload({
  required Bridge bridge,
  required String inboxRetryPayload,
}) async {
  final payload = jsonDecode(inboxRetryPayload) as Map<String, dynamic>;
  final groupId = payload['groupId'] as String;
  final message = payload['message'] as String;
  final recipientPeerIds = (payload['recipientPeerIds'] as List<dynamic>?)
      ?.cast<String>();
  await callGroupInboxStore(
    bridge,
    groupId,
    message,
    recipientPeerIds: recipientPeerIds,
  );
}

bool isGroupOfflineReplayEnvelope(Map<String, dynamic> envelope) {
  return envelope['kind'] == groupOfflineReplayEnvelopeKind &&
      envelope['ciphertext'] is String &&
      envelope['nonce'] is String &&
      envelope['keyEpoch'] is int;
}

Future<String> decryptGroupOfflineReplayEnvelope({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required Map<String, dynamic> envelope,
  String? expectedRelayPeerId,
}) async {
  final verification = await _verifyReplaySignature(
    bridge: bridge,
    groupRepo: groupRepo,
    fallbackGroupId: groupId,
    envelope: envelope,
    expectedRelayPeerId: expectedRelayPeerId,
  );
  final keyEpoch = envelope['keyEpoch'] as int;
  final keyInfo = await groupRepo.getKeyByGeneration(groupId, keyEpoch);
  if (keyInfo == null) {
    throw StateError(
      'Missing group replay key for group $groupId at epoch $keyEpoch',
    );
  }

  return callGroupDecrypt(
    bridge,
    keyInfo.encryptedKey,
    envelope['ciphertext'] as String,
    envelope['nonce'] as String,
  ).then((plaintext) {
    _verifyPlaintextBinding(plaintext, verification, fallbackGroupId: groupId);
    return plaintext;
  });
}

Future<_ReplaySignatureVerification> _verifyReplaySignature({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String fallbackGroupId,
  required Map<String, dynamic> envelope,
  String? expectedRelayPeerId,
}) async {
  final groupId = _readRequiredString(
    envelope,
    'groupId',
    reason: 'missing_group_id',
  );
  if (groupId != fallbackGroupId) {
    throw GroupOfflineReplaySignatureException('group_mismatch');
  }
  final payloadType = _readRequiredString(
    envelope,
    'payloadType',
    reason: 'missing_payload_type',
  );
  final keyEpoch = envelope['keyEpoch'];
  if (keyEpoch is! int) {
    throw GroupOfflineReplaySignatureException('missing_key_epoch');
  }
  final ciphertext = _readRequiredString(
    envelope,
    'ciphertext',
    reason: 'missing_ciphertext',
  );
  final nonce = _readRequiredString(envelope, 'nonce', reason: 'missing_nonce');
  final senderPeerId = _readRequiredString(
    envelope,
    'senderPeerId',
    reason: 'missing_sender',
  );
  final senderPublicKey = _readRequiredString(
    envelope,
    'senderPublicKey',
    reason: 'missing_sender_key',
  );
  final senderDeviceId = _trimToNull(envelope['senderDeviceId'] as String?);
  final senderTransportPeerId = _trimToNull(
    envelope['senderTransportPeerId'] as String?,
  );
  final senderKeyPackageId = _trimToNull(
    envelope['senderKeyPackageId'] as String?,
  );
  final messageId = _trimToNull(envelope['messageId'] as String?);
  final recipientSetHash = _readRequiredString(
    envelope,
    'recipientSetHash',
    reason: 'missing_recipient_hash',
  );

  if (envelope['signatureAlgorithm'] != groupOfflineReplaySignatureAlgorithm) {
    throw GroupOfflineReplaySignatureException('signature_algorithm_invalid');
  }
  final signedPayload = _readRequiredString(
    envelope,
    'signedPayload',
    reason: 'missing_signed_payload',
  );
  final signature = _readRequiredString(
    envelope,
    'signature',
    reason: 'missing_signature',
  );
  final decodedSignedPayload = _decodeStringMap(signedPayload);
  if (decodedSignedPayload == null ||
      canonicalizeGroupEventLogPayload(decodedSignedPayload) != signedPayload) {
    throw GroupOfflineReplaySignatureException('signed_payload_malformed');
  }

  final plaintextHash = _readRequiredString(
    decodedSignedPayload,
    'plaintextHash',
    reason: 'missing_plaintext_hash',
  );
  final expectedSignedPayload = _buildReplaySignedPayloadFromHashes(
    groupId: groupId,
    payloadType: payloadType,
    keyEpoch: keyEpoch,
    ciphertextHash: _hashString(ciphertext),
    nonceHash: _hashString(nonce),
    plaintextHash: plaintextHash,
    messageId: messageId,
    senderPeerId: senderPeerId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderPublicKey: senderPublicKey,
    senderKeyPackageId: senderKeyPackageId,
    recipientSetHash: recipientSetHash,
  );
  if (expectedSignedPayload != signedPayload) {
    throw GroupOfflineReplaySignatureException('signed_payload_mismatch');
  }

  var member = await groupRepo.getMember(groupId, senderPeerId);
  var device = _resolveSigningDevice(
    member: member,
    senderPublicKey: senderPublicKey,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
  );
  if (member == null) {
    final snapshotRepo = groupRepo is RemovedGroupMemberSnapshotRepository
        ? groupRepo as RemovedGroupMemberSnapshotRepository
        : null;
    member = await snapshotRepo?.getRemovedMemberSnapshot(
      groupId,
      senderPeerId,
    );
    device = _resolveSigningDevice(
      member: member,
      senderPublicKey: senderPublicKey,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
    );
    if (member == null || device == null) {
      throw GroupOfflineReplaySignatureException('unknown_sender');
    }
  }
  if (device == null) {
    final inactiveDevice = _resolveSigningDevice(
      member: member,
      senderPublicKey: senderPublicKey,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      activeOnly: false,
    );
    if (inactiveDevice != null && !inactiveDevice.isActive) {
      throw GroupOfflineReplaySignatureException('revoked_device');
    }
    throw GroupOfflineReplaySignatureException('unknown_sender');
  }
  if (device.deviceSigningPublicKey != senderPublicKey) {
    throw GroupOfflineReplaySignatureException('sender_key_mismatch');
  }
  if (senderDeviceId != null && device.deviceId != senderDeviceId) {
    throw GroupOfflineReplaySignatureException('sender_device_mismatch');
  }
  if (senderTransportPeerId != null &&
      device.transportPeerId != senderTransportPeerId) {
    throw GroupOfflineReplaySignatureException('sender_transport_mismatch');
  }

  final relayPeerId = _trimToNull(expectedRelayPeerId);
  if (relayPeerId != null &&
      relayPeerId != senderPeerId &&
      relayPeerId != senderTransportPeerId) {
    throw GroupOfflineReplaySignatureException('relay_sender_mismatch');
  }

  final validSignature = await callVerifyPayload(
    bridge: bridge,
    publicKey: device.deviceSigningPublicKey,
    data: signedPayload,
    signature: signature,
  );
  if (!validSignature) {
    throw GroupOfflineReplaySignatureException('signature_invalid');
  }

  return _ReplaySignatureVerification(
    payloadType: payloadType,
    messageId: messageId,
    senderPeerId: senderPeerId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    plaintextHash: plaintextHash,
  );
}

void _verifyPlaintextBinding(
  String plaintext,
  _ReplaySignatureVerification verification, {
  required String fallbackGroupId,
}) {
  if (_hashString(plaintext) != verification.plaintextHash) {
    throw GroupOfflineReplaySignatureException('plaintext_hash_mismatch');
  }
  final payload = _decodeStringMap(plaintext);
  if (payload == null) {
    throw GroupOfflineReplaySignatureException('plaintext_malformed');
  }

  final payloadGroupId = payload['groupId'];
  if (payloadGroupId is String &&
      payloadGroupId.isNotEmpty &&
      payloadGroupId != fallbackGroupId) {
    throw GroupOfflineReplaySignatureException('payload_group_mismatch');
  }
  final keyEpoch = payload['keyEpoch'];
  if (keyEpoch != null && keyEpoch is! int) {
    throw GroupOfflineReplaySignatureException('payload_epoch_malformed');
  }

  final payloadSender =
      verification.payloadType == groupOfflineReplayPayloadTypeReaction
      ? _trimToNull(payload['senderPeerId'] as String?)
      : _trimToNull(payload['senderId'] as String?);
  if (payloadSender != null && payloadSender != verification.senderPeerId) {
    throw GroupOfflineReplaySignatureException('payload_sender_mismatch');
  }
  final payloadDeviceId = _trimToNull(payload['senderDeviceId'] as String?);
  if (payloadDeviceId != null &&
      verification.senderDeviceId != null &&
      payloadDeviceId != verification.senderDeviceId) {
    throw GroupOfflineReplaySignatureException('payload_device_mismatch');
  }
  final payloadTransportPeerId = _trimToNull(
    payload['transportPeerId'] as String?,
  );
  if (payloadTransportPeerId != null &&
      verification.senderTransportPeerId != null &&
      payloadTransportPeerId != verification.senderTransportPeerId) {
    throw GroupOfflineReplaySignatureException('payload_transport_mismatch');
  }
  final payloadMessageId =
      verification.payloadType == groupOfflineReplayPayloadTypeReaction
      ? _trimToNull(payload['id'] as String?)
      : _trimToNull(payload['messageId'] as String?);
  if (verification.messageId != null &&
      payloadMessageId != null &&
      payloadMessageId != verification.messageId) {
    throw GroupOfflineReplaySignatureException('payload_message_mismatch');
  }
}

GroupMemberDeviceIdentity? _resolveSigningDevice({
  required GroupMember? member,
  required String senderPublicKey,
  required String? senderDeviceId,
  required String? senderTransportPeerId,
  bool activeOnly = true,
}) {
  if (member == null) return null;
  if (senderDeviceId != null) {
    return member.findDeviceById(
      senderDeviceId,
      activeOnly: activeOnly,
      allowLegacyFallback: true,
    );
  }
  if (senderTransportPeerId != null) {
    return member.findDeviceByTransportPeerId(
      senderTransportPeerId,
      activeOnly: activeOnly,
      allowLegacyFallback: true,
    );
  }
  return _firstDeviceForSigningKey(
    member,
    senderPublicKey,
    activeOnly: activeOnly,
    allowLegacyFallback: true,
  );
}

GroupMemberDeviceIdentity? _firstDeviceForSigningKey(
  GroupMember member,
  String? signingPublicKey, {
  bool activeOnly = true,
  bool allowLegacyFallback = false,
}) {
  final normalized = signingPublicKey?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  final devices = activeOnly ? member.activeDevices : member.devices;
  for (final device in devices) {
    if (device.deviceSigningPublicKey == normalized) {
      return device;
    }
  }
  if (allowLegacyFallback) {
    final legacy = member.legacyDeviceIdentity;
    if (legacy?.deviceSigningPublicKey == normalized) {
      return legacy;
    }
  }
  return null;
}

String _buildReplaySignedPayload({
  required String groupId,
  required String payloadType,
  required int keyEpoch,
  required String ciphertext,
  required String nonce,
  required String plaintext,
  required String? messageId,
  required String senderPeerId,
  required String? senderDeviceId,
  required String? senderTransportPeerId,
  required String senderPublicKey,
  required String? senderKeyPackageId,
  required String recipientSetHash,
}) {
  return _buildReplaySignedPayloadFromHashes(
    groupId: groupId,
    payloadType: payloadType,
    keyEpoch: keyEpoch,
    ciphertextHash: _hashString(ciphertext),
    nonceHash: _hashString(nonce),
    plaintextHash: _hashString(plaintext),
    messageId: messageId,
    senderPeerId: senderPeerId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderPublicKey: senderPublicKey,
    senderKeyPackageId: senderKeyPackageId,
    recipientSetHash: recipientSetHash,
  );
}

String _buildReplaySignedPayloadFromHashes({
  required String groupId,
  required String payloadType,
  required int keyEpoch,
  required String ciphertextHash,
  required String nonceHash,
  required String plaintextHash,
  required String? messageId,
  required String senderPeerId,
  required String? senderDeviceId,
  required String? senderTransportPeerId,
  required String senderPublicKey,
  required String? senderKeyPackageId,
  required String recipientSetHash,
}) {
  return canonicalizeGroupEventLogPayload({
    'schemaVersion': groupOfflineReplaySignatureVersion,
    'kind': groupOfflineReplayEnvelopeKind,
    'groupId': groupId,
    'payloadType': payloadType,
    'keyEpoch': keyEpoch,
    if (messageId != null) 'messageId': messageId,
    'senderPeerId': senderPeerId,
    if (senderDeviceId != null) 'senderDeviceId': senderDeviceId,
    if (senderTransportPeerId != null)
      'senderTransportPeerId': senderTransportPeerId,
    'senderSigningPublicKey': senderPublicKey,
    if (senderKeyPackageId != null) 'senderKeyPackageId': senderKeyPackageId,
    'ciphertextHash': ciphertextHash,
    'nonceHash': nonceHash,
    'plaintextHash': plaintextHash,
    'recipientSetHash': recipientSetHash,
  });
}

String _recipientSetHash(List<String>? recipientPeerIds) {
  final normalized =
      (recipientPeerIds ?? const <String>[])
          .map((peerId) => peerId.trim())
          .where((peerId) => peerId.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return _hashString(jsonEncode(normalized));
}

String _hashString(String value) =>
    sha256.convert(utf8.encode(value)).toString();

String _requiredTrimmed(String value, String field) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, field, 'must not be empty');
  }
  return trimmed;
}

String _readRequiredString(
  Map<String, Object?> payload,
  String field, {
  required String reason,
}) {
  final value = payload[field];
  if (value is! String || value.trim().isEmpty) {
    throw GroupOfflineReplaySignatureException(reason);
  }
  return value.trim();
}

Map<String, Object?>? _decodeStringMap(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map) return null;
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  } catch (_) {
    return null;
  }
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

Future<GroupKeyInfo> _loadReplayKey(
  GroupRepository groupRepo,
  String groupId,
) async {
  final keyInfo = await groupRepo.getLatestKey(groupId);
  if (keyInfo == null) {
    throw StateError('Missing group replay key for group $groupId');
  }
  return keyInfo;
}
