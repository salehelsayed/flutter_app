import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Rotates the encryption key for a group.
///
/// Calls the bridge to generate a new key, saves it to the repository,
/// and returns the new [GroupKeyInfo].
Future<GroupKeyInfo> rotateGroupKey({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_ROTATE_KEY_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  // 1. Call bridge to rotate the key
  final result = await callGroupRotateKey(bridge, groupId);
  if (result['ok'] != true) {
    throw Exception(
      result['errorMessage'] ?? 'Failed to rotate group key',
    );
  }

  // 2. Parse result
  final newKeyGeneration = result['keyGeneration'] as int? ?? 1;
  final newEncryptedKey = result['encryptedKey'] as String? ?? '';
  final now = DateTime.now().toUtc();

  // 3. Save new key to repo
  final keyInfo = GroupKeyInfo(
    groupId: groupId,
    keyGeneration: newKeyGeneration,
    encryptedKey: newEncryptedKey,
    createdAt: now,
  );
  await groupRepo.saveKey(keyInfo);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_ROTATE_KEY_USE_CASE_SUCCESS',
    details: {'newKeyGeneration': newKeyGeneration},
  );

  return keyInfo;
}
