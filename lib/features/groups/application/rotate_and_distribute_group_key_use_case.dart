import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Generates the next group encryption key, distributes it to remaining
/// members, then promotes the admin validator and local key last.
///
/// Steps:
/// 1. Generates the next key without mutating Go validator state
/// 2. Distributes the new key to remaining members concurrently
/// 3. Promotes the admin validator and saves the new key locally
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
  Duration perRecipientTimeout = const Duration(seconds: 5),
  Duration distributionTimeout = const Duration(seconds: 15),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_ROTATE_KEY_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  // 1. Generate the next key without updating Go state yet.
  final generateResult = await callGroupGenerateNextKey(bridge, groupId);
  if (generateResult['ok'] != true) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ROTATE_KEY_BRIDGE_ERROR',
      details: {'errorCode': generateResult['errorCode']},
    );
    return null;
  }

  final newEpoch = generateResult['keyEpoch'] as int;
  final newKey = generateResult['groupKey'] as String;

  // 2. Distribute to remaining members via concurrent 1:1 encrypted P2P.
  final members = await groupRepo.getMembers(groupId);
  final distributionFutures = members
      .where((member) => member.peerId != selfPeerId)
      .where((member) => member.mlKemPublicKey != null)
      .map(
        (member) => _distributeRotatedKeyToMember(
          bridge: bridge,
          groupId: groupId,
          member: member,
          newEpoch: newEpoch,
          newKey: newKey,
          sendP2PMessage: sendP2PMessage,
          perRecipientTimeout: perRecipientTimeout,
        ),
      )
      .toList();

  try {
    await Future.wait(
      distributionFutures,
      eagerError: false,
    ).timeout(distributionTimeout, onTimeout: () => <bool>[]);
  } on Exception catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ROTATE_KEY_DISTRIBUTE_ERROR',
      details: {'error': e.toString()},
    );
  }

  // 3. Promote the admin's own validator and local key only after
  // distribution completes or times out.
  try {
    await callGroupUpdateKey(
      bridge,
      groupId: groupId,
      groupKey: newKey,
      keyEpoch: newEpoch,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ROTATE_KEY_PROMOTE_ERROR',
      details: {'error': e.toString()},
    );
    return null;
  }

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

  // 4. Broadcast key_rotated system message after admin promotion.
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

Future<bool> _distributeRotatedKeyToMember({
  required Bridge bridge,
  required String groupId,
  required GroupMember member,
  required int newEpoch,
  required String newKey,
  required Future<bool> Function(String peerId, String message)? sendP2PMessage,
  required Duration perRecipientTimeout,
}) async {
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

    if (encryptResult['ok'] != true) {
      return false;
    }

    final envelope = jsonEncode({
      'type': 'group_key_update',
      'version': '2',
      'encrypted': {
        'kem': encryptResult['kem'],
        'ciphertext': encryptResult['ciphertext'],
        'nonce': encryptResult['nonce'],
      },
    });

    final sendFuture =
        sendP2PMessage?.call(member.peerId, envelope) ?? Future.value(true);
    return await sendFuture.timeout(
      perRecipientTimeout,
      onTimeout: () => false,
    );
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
    return false;
  }
}
