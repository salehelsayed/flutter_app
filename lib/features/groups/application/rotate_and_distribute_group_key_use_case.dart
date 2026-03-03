import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Rotates the group encryption key and distributes it to remaining members.
///
/// Steps:
/// 1. Calls bridge to rotate the key → new key + epoch
/// 2. Saves the new key locally
/// 3. For each remaining member (except self) with mlKemPublicKey:
///    - Encrypts new key with member's ML-KEM public key
///    - Sends via 1:1 P2P as a group_key_update envelope
/// 4. Broadcasts a key_rotated system message on the group topic
///
/// Returns the new [GroupKeyInfo] on success, null on failure.
Future<GroupKeyInfo?> rotateAndDistributeGroupKey({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String selfPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  Future<bool> Function(String peerId, String message)? sendP2PMessage,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_ROTATE_KEY_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  // 1. Rotate key via bridge
  final rotateResult = await callGroupRotateKey(bridge, groupId);
  if (rotateResult['ok'] != true) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ROTATE_KEY_BRIDGE_ERROR',
      details: {'errorCode': rotateResult['errorCode']},
    );
    return null;
  }

  final newEpoch = rotateResult['keyEpoch'] as int;
  final newKey = rotateResult['groupKey'] as String;

  // 2. Save locally
  final keyInfo = GroupKeyInfo(
    groupId: groupId,
    keyGeneration: newEpoch,
    encryptedKey: newKey,
    createdAt: DateTime.now().toUtc(),
  );
  await groupRepo.saveKey(keyInfo);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_ROTATE_KEY_SAVED',
    details: {'newEpoch': newEpoch},
  );

  // 3. Distribute to remaining members via 1:1 encrypted P2P
  final members = await groupRepo.getMembers(groupId);
  for (final member in members) {
    if (member.peerId == selfPeerId) continue;
    if (member.mlKemPublicKey == null) continue;

    try {
      final encryptResult = await callEncryptMessage(
        bridge: bridge,
        recipientMlKemPublicKey: member.mlKemPublicKey!,
        plaintext: jsonEncode({
          'groupId': groupId,
          'keyGeneration': newEpoch,
          'encryptedKey': newKey,
        }),
      );

      if (encryptResult['ok'] != true) continue;

      final envelope = jsonEncode({
        'type': 'group_key_update',
        'version': '2',
        'encrypted': {
          'kem': encryptResult['kem'],
          'ciphertext': encryptResult['ciphertext'],
          'nonce': encryptResult['nonce'],
        },
      });

      if (sendP2PMessage != null) {
        await sendP2PMessage(member.peerId, envelope);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_DISTRIBUTE_ERROR',
        details: {
          'peerId': member.peerId.length > 8
              ? member.peerId.substring(0, 8)
              : member.peerId,
          'error': e.toString(),
        },
      );
    }
  }

  // 4. Broadcast key_rotated system message
  try {
    final sysMessage = jsonEncode({
      '__sys': 'key_rotated',
      'newKeyEpoch': newEpoch,
    });

    await callGroupPublish(
      bridge,
      groupId: groupId,
      text: sysMessage,
      senderPeerId: selfPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      senderUsername: senderUsername,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ROTATE_KEY_BROADCAST_ERROR',
      details: {'error': e.toString()},
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_ROTATE_KEY_DONE',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'newEpoch': newEpoch,
      'distributedTo': members.where((m) => m.peerId != selfPeerId).length,
    },
  );

  return keyInfo;
}
