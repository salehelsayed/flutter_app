import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const groupOfflineReplayEnvelopeKind = 'group_offline_replay';
const groupOfflineReplayPayloadTypeMessage = 'group_message';
const groupOfflineReplayPayloadTypeReaction = 'group_reaction';

Future<String> buildGroupOfflineReplayEnvelope({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String payloadType,
  required String plaintext,
  GroupKeyInfo? keyInfo,
  String? messageId,
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

  return jsonEncode({
    'kind': groupOfflineReplayEnvelopeKind,
    'version': 1,
    'payloadType': payloadType,
    'keyEpoch': resolvedKey.keyGeneration,
    if (messageId != null && messageId.isNotEmpty) 'messageId': messageId,
    'ciphertext': ciphertext,
    'nonce': nonce,
  });
}

Future<void> storeGroupOfflineReplayEnvelope({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String payloadType,
  required String plaintext,
  GroupKeyInfo? keyInfo,
  String? messageId,
  List<String>? recipientPeerIds,
}) async {
  final replayEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    payloadType: payloadType,
    plaintext: plaintext,
    keyInfo: keyInfo,
    messageId: messageId,
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
  GroupKeyInfo? keyInfo,
  String? messageId,
  List<String>? recipientPeerIds,
}) async {
  final replayEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    payloadType: payloadType,
    plaintext: plaintext,
    keyInfo: keyInfo,
    messageId: messageId,
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
}) async {
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
  );
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
