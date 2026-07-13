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
const groupReactionNotificationExtensionKind = 'group_reaction_notification';
const groupReactionNotificationExtensionVersion = 1;

/// Sender-authored, content-free notification hints that are signed separately
/// from the byte-compatible v1 replay payload. Display authority remains local
/// to the recipient; this extension only allows the relay to select a typed
/// wake and a transition identity.
class GroupReactionNotificationExtensionInput {
  const GroupReactionNotificationExtensionInput({
    required this.transitionId,
    required this.action,
    required this.targetMessageId,
    required this.reactorPeerId,
    required this.reactorTransportPeerId,
    required this.notificationRecipientTransportPeerIds,
  });

  final String transitionId;
  final String action;
  final String targetMessageId;
  final String reactorPeerId;
  final String reactorTransportPeerId;
  final List<String> notificationRecipientTransportPeerIds;
}

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
    this.reactionNotificationExtension,
  });

  final String payloadType;
  final String? messageId;
  final String senderPeerId;
  final String? senderDeviceId;
  final String? senderTransportPeerId;
  final String plaintextHash;
  final _VerifiedGroupReactionNotificationExtension?
  reactionNotificationExtension;
}

class _VerifiedGroupReactionNotificationExtension {
  const _VerifiedGroupReactionNotificationExtension({
    required this.transitionId,
    required this.action,
    required this.targetMessageId,
    required this.reactorPeerId,
    required this.reactorTransportPeerId,
  });

  final String transitionId;
  final String action;
  final String targetMessageId;
  final String reactorPeerId;
  final String reactorTransportPeerId;
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
  GroupReactionNotificationExtensionInput? reactionNotificationExtension,
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
  final relayVisibleMessageId = _relayVisibleReplayMessageId(
    normalizedMessageId,
  );
  final normalizedRecipientPeerIds = _normalizedRecipientPeerIds(
    recipientPeerIds,
  );
  final recipientSetHash = _recipientSetHashFromNormalized(
    normalizedRecipientPeerIds,
  );
  final normalizedSenderKeyPackageId = _trimToNull(senderKeyPackageId);
  final signedPayload = _buildReplaySignedPayload(
    groupId: groupId,
    payloadType: payloadType,
    keyEpoch: resolvedKey.keyGeneration,
    ciphertext: ciphertext,
    nonce: nonce,
    plaintext: plaintext,
    messageId: relayVisibleMessageId,
    senderPeerId: resolvedSenderPeerId,
    senderDeviceId: normalizedDeviceId,
    senderTransportPeerId: normalizedTransportPeerId,
    senderPublicKey: resolvedSenderPublicKey,
    senderKeyPackageId: normalizedSenderKeyPackageId,
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

  final baseEnvelope = <String, Object?>{
    'kind': groupOfflineReplayEnvelopeKind,
    'version': 1,
    'groupId': groupId,
    'payloadType': payloadType,
    'keyEpoch': resolvedKey.keyGeneration,
    'messageId': ?relayVisibleMessageId,
    'senderPeerId': resolvedSenderPeerId,
    'senderDeviceId': normalizedDeviceId,
    'senderTransportPeerId': normalizedTransportPeerId,
    'senderPublicKey': resolvedSenderPublicKey,
    'senderKeyPackageId': ?normalizedSenderKeyPackageId,
    if (normalizedRecipientPeerIds.isNotEmpty)
      'recipientPeerIds': normalizedRecipientPeerIds,
    'recipientSetHash': recipientSetHash,
    'ciphertext': ciphertext,
    'nonce': nonce,
    'signatureAlgorithm': groupOfflineReplaySignatureAlgorithm,
    'signedPayload': signedPayload,
    'signature': signature,
  };

  final notificationInput = reactionNotificationExtension;
  if (notificationInput == null) {
    return jsonEncode(baseEnvelope);
  }
  if (payloadType != groupOfflineReplayPayloadTypeReaction) {
    throw ArgumentError(
      'Reaction notification extensions require payloadType=group_reaction',
    );
  }
  final extension = await _buildGroupReactionNotificationExtension(
    bridge: bridge,
    baseEnvelope: baseEnvelope,
    input: notificationInput,
    senderPeerId: resolvedSenderPeerId,
    senderTransportPeerId: normalizedTransportPeerId,
    senderPrivateKey: senderPrivateKey,
    replayRecipientPeerIds: normalizedRecipientPeerIds,
    replayRecipientSetHash: recipientSetHash,
  );
  return jsonEncode({...baseEnvelope, 'notificationExtension': extension});
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
  bool preserveRecipientPeerIds = false,
  GroupReactionNotificationExtensionInput? reactionNotificationExtension,
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
    reactionNotificationExtension: reactionNotificationExtension,
  );

  await callGroupInboxStore(
    bridge,
    groupId,
    replayEnvelope,
    recipientPeerIds: recipientPeerIds,
    preserveRecipientPeerIds: preserveRecipientPeerIds,
  );
}

Future<Map<String, Object?>> _buildGroupReactionNotificationExtension({
  required Bridge bridge,
  required Map<String, Object?> baseEnvelope,
  required GroupReactionNotificationExtensionInput input,
  required String senderPeerId,
  required String senderTransportPeerId,
  required String senderPrivateKey,
  required List<String> replayRecipientPeerIds,
  required String replayRecipientSetHash,
}) async {
  final transitionId = _requiredTrimmed(input.transitionId, 'transitionId');
  final action = _requiredTrimmed(input.action, 'action');
  if (action != 'add' && action != 'remove') {
    throw ArgumentError.value(action, 'action', 'must be add or remove');
  }
  final targetMessageId = _requiredTrimmed(
    input.targetMessageId,
    'targetMessageId',
  );
  final reactorPeerId = _requiredTrimmed(input.reactorPeerId, 'reactorPeerId');
  final reactorTransportPeerId = _requiredTrimmed(
    input.reactorTransportPeerId,
    'reactorTransportPeerId',
  );
  if (reactorPeerId != senderPeerId ||
      reactorTransportPeerId != senderTransportPeerId) {
    throw ArgumentError(
      'Reaction notification actor must match the base replay sender',
    );
  }
  final notificationRecipients = _normalizedRecipientPeerIds(
    input.notificationRecipientTransportPeerIds,
  );
  final replayRecipients = replayRecipientPeerIds.toSet();
  if (notificationRecipients.any(
    (recipient) => !replayRecipients.contains(recipient),
  )) {
    throw ArgumentError(
      'Reaction notification recipients must be a replay-recipient subset',
    );
  }

  final baseEnvelopeHash = _hashString(
    canonicalizeGroupEventLogPayload(baseEnvelope),
  );
  final signedPayload = canonicalizeGroupEventLogPayload({
    'kind': groupReactionNotificationExtensionKind,
    'version': groupReactionNotificationExtensionVersion,
    'transitionId': transitionId,
    'action': action,
    'targetMessageId': targetMessageId,
    'reactorPeerId': reactorPeerId,
    'reactorTransportPeerId': reactorTransportPeerId,
    'replayRecipientSetHash': replayRecipientSetHash,
    'notificationRecipientTransportPeerIds': notificationRecipients,
    'baseEnvelopeHash': baseEnvelopeHash,
  });
  final signResult = await callSignPayload(
    bridge: bridge,
    dataToSign: signedPayload,
    privateKey: senderPrivateKey,
  );
  final signature = signResult['signature'];
  if (signResult['ok'] != true || signature is! String || signature.isEmpty) {
    throw StateError('Failed to sign group reaction notification extension');
  }

  return <String, Object?>{
    'version': groupReactionNotificationExtensionVersion,
    'transitionId': transitionId,
    'action': action,
    'targetMessageId': targetMessageId,
    'reactorPeerId': reactorPeerId,
    'reactorTransportPeerId': reactorTransportPeerId,
    'replayRecipientSetHash': replayRecipientSetHash,
    'notificationRecipientTransportPeerIds': notificationRecipients,
    'baseEnvelopeHash': baseEnvelopeHash,
    'signatureAlgorithm': groupOfflineReplaySignatureAlgorithm,
    'signedPayload': signedPayload,
    'signature': signature,
  };
}

String encodeGroupOfflineReplayInboxRetryPayload({
  required String groupId,
  required String message,
  List<String>? recipientPeerIds,
}) {
  return jsonEncode({
    'groupId': groupId,
    'message': message,
    'recipientPeerIds': ?recipientPeerIds,
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
  GroupReactionNotificationExtensionInput? reactionNotificationExtension,
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
    reactionNotificationExtension: reactionNotificationExtension,
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
  final preservesRecipientPeerIds = payload.containsKey('recipientPeerIds');
  final recipientPeerIds = (payload['recipientPeerIds'] as List<dynamic>?)
      ?.cast<String>();
  await callGroupInboxStore(
    bridge,
    groupId,
    message,
    recipientPeerIds: recipientPeerIds,
    preserveRecipientPeerIds: preservesRecipientPeerIds,
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
  String? expectedRecipientPeerId,
}) async {
  final verification = await _verifyReplaySignature(
    bridge: bridge,
    groupRepo: groupRepo,
    fallbackGroupId: groupId,
    envelope: envelope,
    expectedRelayPeerId: expectedRelayPeerId,
    expectedRecipientPeerId: expectedRecipientPeerId,
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
  String? expectedRecipientPeerId,
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
  final recipientPeerIds = _readOptionalRecipientPeerIds(
    envelope['recipientPeerIds'],
  );
  if (recipientPeerIds != null &&
      _recipientSetHashFromNormalized(recipientPeerIds) != recipientSetHash) {
    throw GroupOfflineReplaySignatureException('recipient_hash_mismatch');
  }
  final expectedRecipient = _trimToNull(expectedRecipientPeerId);
  if (expectedRecipient != null &&
      recipientPeerIds != null &&
      !recipientPeerIds.contains(expectedRecipient)) {
    throw GroupOfflineReplaySignatureException('recipient_not_entitled');
  }

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

  final reactionNotificationExtension =
      await _verifyGroupReactionNotificationExtension(
        bridge: bridge,
        envelope: envelope,
        payloadType: payloadType,
        senderPeerId: senderPeerId,
        senderTransportPeerId: senderTransportPeerId,
        senderPublicKey: senderPublicKey,
        replayRecipientPeerIds: recipientPeerIds ?? const <String>[],
        replayRecipientSetHash: recipientSetHash,
      );

  return _ReplaySignatureVerification(
    payloadType: payloadType,
    messageId: messageId,
    senderPeerId: senderPeerId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    plaintextHash: plaintextHash,
    reactionNotificationExtension: reactionNotificationExtension,
  );
}

Future<_VerifiedGroupReactionNotificationExtension?>
_verifyGroupReactionNotificationExtension({
  required Bridge bridge,
  required Map<String, dynamic> envelope,
  required String payloadType,
  required String senderPeerId,
  required String? senderTransportPeerId,
  required String senderPublicKey,
  required List<String> replayRecipientPeerIds,
  required String replayRecipientSetHash,
}) async {
  final rawExtension = envelope['notificationExtension'];
  if (rawExtension == null) return null;
  if (payloadType != groupOfflineReplayPayloadTypeReaction ||
      rawExtension is! Map) {
    throw GroupOfflineReplaySignatureException(
      'notification_extension_malformed',
    );
  }
  final extension = rawExtension.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
  if (extension['version'] != groupReactionNotificationExtensionVersion ||
      extension['signatureAlgorithm'] != groupOfflineReplaySignatureAlgorithm) {
    throw GroupOfflineReplaySignatureException(
      'notification_extension_version_invalid',
    );
  }
  final transitionId = _readRequiredString(
    extension,
    'transitionId',
    reason: 'notification_transition_missing',
  );
  final action = _readRequiredString(
    extension,
    'action',
    reason: 'notification_action_missing',
  );
  if (action != 'add' && action != 'remove') {
    throw GroupOfflineReplaySignatureException('notification_action_invalid');
  }
  final targetMessageId = _readRequiredString(
    extension,
    'targetMessageId',
    reason: 'notification_target_missing',
  );
  final reactorPeerId = _readRequiredString(
    extension,
    'reactorPeerId',
    reason: 'notification_reactor_missing',
  );
  final reactorTransportPeerId = _readRequiredString(
    extension,
    'reactorTransportPeerId',
    reason: 'notification_reactor_transport_missing',
  );
  final extensionReplaySetHash = _readRequiredString(
    extension,
    'replayRecipientSetHash',
    reason: 'notification_replay_hash_missing',
  );
  final baseEnvelopeHash = _readRequiredString(
    extension,
    'baseEnvelopeHash',
    reason: 'notification_base_hash_missing',
  );
  final notificationRecipients = _readExactRecipientPeerIds(
    extension['notificationRecipientTransportPeerIds'],
    reason: 'notification_recipient_list_malformed',
  );
  final signedPayload = _readRequiredString(
    extension,
    'signedPayload',
    reason: 'notification_signed_payload_missing',
  );
  final signature = _readRequiredString(
    extension,
    'signature',
    reason: 'notification_signature_missing',
  );

  final expectedTransport = _trimToNull(senderTransportPeerId);
  if (reactorPeerId != senderPeerId ||
      expectedTransport == null ||
      reactorTransportPeerId != expectedTransport ||
      extensionReplaySetHash != replayRecipientSetHash) {
    throw GroupOfflineReplaySignatureException(
      'notification_sender_or_replay_mismatch',
    );
  }
  final replaySet = replayRecipientPeerIds.toSet();
  if (notificationRecipients.any(
    (recipient) => !replaySet.contains(recipient),
  )) {
    throw GroupOfflineReplaySignatureException(
      'notification_recipient_not_replay_subset',
    );
  }
  final baseEnvelope = Map<String, Object?>.from(envelope)
    ..remove('notificationExtension');
  final expectedBaseHash = _hashString(
    canonicalizeGroupEventLogPayload(baseEnvelope),
  );
  if (baseEnvelopeHash != expectedBaseHash) {
    throw GroupOfflineReplaySignatureException(
      'notification_base_hash_mismatch',
    );
  }
  final expectedSignedPayload = canonicalizeGroupEventLogPayload({
    'kind': groupReactionNotificationExtensionKind,
    'version': groupReactionNotificationExtensionVersion,
    'transitionId': transitionId,
    'action': action,
    'targetMessageId': targetMessageId,
    'reactorPeerId': reactorPeerId,
    'reactorTransportPeerId': reactorTransportPeerId,
    'replayRecipientSetHash': extensionReplaySetHash,
    'notificationRecipientTransportPeerIds': notificationRecipients,
    'baseEnvelopeHash': baseEnvelopeHash,
  });
  if (signedPayload != expectedSignedPayload) {
    throw GroupOfflineReplaySignatureException(
      'notification_signed_payload_mismatch',
    );
  }
  final valid = await callVerifyPayload(
    bridge: bridge,
    publicKey: senderPublicKey,
    data: signedPayload,
    signature: signature,
  );
  if (!valid) {
    throw GroupOfflineReplaySignatureException(
      'notification_signature_invalid',
    );
  }
  return _VerifiedGroupReactionNotificationExtension(
    transitionId: transitionId,
    action: action,
    targetMessageId: targetMessageId,
    reactorPeerId: reactorPeerId,
    reactorTransportPeerId: reactorTransportPeerId,
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

  final notificationExtension = verification.reactionNotificationExtension;
  if (notificationExtension != null) {
    final eventId = _trimToNull(payload['eventId'] as String?);
    final action = _trimToNull(payload['action'] as String?);
    final targetMessageId = _trimToNull(payload['messageId'] as String?);
    final reactorPeerId = _trimToNull(payload['senderPeerId'] as String?);
    if (eventId != notificationExtension.transitionId ||
        action != notificationExtension.action ||
        targetMessageId != notificationExtension.targetMessageId ||
        reactorPeerId != notificationExtension.reactorPeerId) {
      throw GroupOfflineReplaySignatureException(
        'notification_plaintext_parity_mismatch',
      );
    }
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
  GroupMemberDeviceIdentity? device;
  if (senderDeviceId != null) {
    device = member.findDeviceById(
      senderDeviceId,
      activeOnly: activeOnly,
      allowLegacyFallback: true,
    );
    if (device != null) return device;
    return _accountSignedUnboundTransportDevice(
      member: member,
      senderPublicKey: senderPublicKey,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
    );
  }
  if (senderTransportPeerId != null) {
    device = member.findDeviceByTransportPeerId(
      senderTransportPeerId,
      activeOnly: activeOnly,
      allowLegacyFallback: true,
    );
    if (device != null) return device;
    return _accountSignedUnboundTransportDevice(
      member: member,
      senderPublicKey: senderPublicKey,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
    );
  }
  return _firstDeviceForSigningKey(
    member,
    senderPublicKey,
    activeOnly: activeOnly,
    allowLegacyFallback: true,
  );
}

GroupMemberDeviceIdentity? _accountSignedUnboundTransportDevice({
  required GroupMember member,
  required String senderPublicKey,
  required String? senderDeviceId,
  required String? senderTransportPeerId,
}) {
  final trustedMemberPublicKey = member.publicKey?.trim();
  if (trustedMemberPublicKey == null ||
      trustedMemberPublicKey.isEmpty ||
      trustedMemberPublicKey != senderPublicKey.trim()) {
    return null;
  }

  final normalizedDeviceId = _trimToNull(senderDeviceId);
  final normalizedTransportPeerId = _trimToNull(senderTransportPeerId);
  final resolvedDeviceId = normalizedDeviceId ?? normalizedTransportPeerId;
  if (resolvedDeviceId == null || resolvedDeviceId.isEmpty) {
    return null;
  }
  final existingById = member.findDeviceById(
    resolvedDeviceId,
    activeOnly: false,
  );
  final existingByTransport = member.findDeviceByTransportPeerId(
    normalizedTransportPeerId,
    activeOnly: false,
  );
  if (existingById != null || existingByTransport != null) {
    return null;
  }
  return GroupMemberDeviceIdentity(
    deviceId: resolvedDeviceId,
    transportPeerId: normalizedTransportPeerId ?? resolvedDeviceId,
    deviceSigningPublicKey: trustedMemberPublicKey,
    mlKemPublicKey: member.mlKemPublicKey,
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
    'messageId': ?messageId,
    'senderPeerId': senderPeerId,
    'senderDeviceId': ?senderDeviceId,
    'senderTransportPeerId': ?senderTransportPeerId,
    'senderSigningPublicKey': senderPublicKey,
    'senderKeyPackageId': ?senderKeyPackageId,
    'ciphertextHash': ciphertextHash,
    'nonceHash': nonceHash,
    'plaintextHash': plaintextHash,
    'recipientSetHash': recipientSetHash,
  });
}

List<String> _normalizedRecipientPeerIds(List<String>? recipientPeerIds) {
  final normalized =
      (recipientPeerIds ?? const <String>[])
          .map((peerId) => peerId.trim())
          .where((peerId) => peerId.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return normalized;
}

String _recipientSetHashFromNormalized(List<String> recipientPeerIds) =>
    _hashString(jsonEncode(recipientPeerIds));

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

List<String>? _readOptionalRecipientPeerIds(Object? value) {
  if (value == null) return null;
  if (value is! List) {
    throw GroupOfflineReplaySignatureException('recipient_list_malformed');
  }
  final recipientPeerIds = <String>[];
  for (final entry in value) {
    if (entry is! String || entry.trim().isEmpty) {
      throw GroupOfflineReplaySignatureException('recipient_list_malformed');
    }
    recipientPeerIds.add(entry.trim());
  }
  return _normalizedRecipientPeerIds(recipientPeerIds);
}

List<String> _readExactRecipientPeerIds(
  Object? value, {
  required String reason,
}) {
  if (value is! List) {
    throw GroupOfflineReplaySignatureException(reason);
  }
  final raw = <String>[];
  for (final entry in value) {
    if (entry is! String || entry.trim().isEmpty || entry != entry.trim()) {
      throw GroupOfflineReplaySignatureException(reason);
    }
    raw.add(entry);
  }
  final normalized = _normalizedRecipientPeerIds(raw);
  if (raw.length != normalized.length) {
    throw GroupOfflineReplaySignatureException(reason);
  }
  for (var index = 0; index < raw.length; index++) {
    if (raw[index] != normalized[index]) {
      throw GroupOfflineReplaySignatureException(reason);
    }
  }
  return normalized;
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

String? _relayVisibleReplayMessageId(String? messageId) {
  if (messageId == null || _isMembershipReplayMessageId(messageId)) {
    return null;
  }
  return messageId;
}

bool _isMembershipReplayMessageId(String messageId) {
  final normalized = messageId.trim().toLowerCase();
  const membershipPrefixes = <String>[
    'sys-member_',
    'member_added:',
    'members_added:',
    'member_joined:',
    'member_removed:',
    'member_role_updated:',
  ];
  return membershipPrefixes.any(normalized.startsWith);
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
