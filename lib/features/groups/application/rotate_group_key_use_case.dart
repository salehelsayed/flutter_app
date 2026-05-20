import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Legacy group key rotation entry point.
///
/// This path cannot own durable key distribution, so it fails closed before a
/// generated key can be saved. New callers must use `rotateAndDistributeGroupKey`.
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

  final result = await callGroupRotateKey(bridge, groupId);
  if (result['ok'] != true) {
    throw Exception(
      result['errorMessage']?.toString() ?? 'Failed to rotate group key',
    );
  }

  final newKeyGeneration = result['keyGeneration'] as int? ?? 1;
  final newEncryptedKey = result['encryptedKey'] as String? ?? '';
  final now = DateTime.now().toUtc();

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
