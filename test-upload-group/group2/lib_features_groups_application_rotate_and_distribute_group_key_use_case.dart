import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_key_update_signature.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

String _diagnosticPrefix(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;

String _rotationOperationId(String groupId, String peerId) =>
    'rotate:${_diagnosticPrefix(groupId)}:${_diagnosticPrefix(peerId)}';

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
  String? sourceDeviceId,
  Future<bool> Function(String peerId, String message)? sendP2PMessage,
  Duration perRecipientTimeout = const Duration(seconds: 5),
  Duration distributionTimeout = const Duration(seconds: 15),
  int distributionAttemptCount = 5,
  Duration distributionRetryDelay = const Duration(milliseconds: 500),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_ROTATE_KEY_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  return _withSerializedGroupRotation<GroupKeyInfo?>(groupId, () async {
    final group = await groupRepo.getGroup(groupId);
    if (group == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_GROUP_NOT_FOUND',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return null;
    }

    final selfMember = await groupRepo.getMember(groupId, selfPeerId);
    final canRotate = selfMember != null
        ? selfMember.permissions.allows(
            GroupMemberPermission.rotateKeys,
            selfMember.role,
          )
        : false;
    if (!canRotate) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_PERMISSION_DENIED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return null;
    }

    final sourceDevice = _resolveSourceDevice(
      selfMember: selfMember,
      senderPublicKey: senderPublicKey,
      sourceDeviceId: sourceDeviceId,
    );
    if (selfMember.devices.isNotEmpty && sourceDevice == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_UNBOUND_SOURCE_DEVICE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return null;
    }

    GroupKeyInfo? persistedKey;
    try {
      persistedKey = await groupRepo.getLatestKey(groupId);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_NO_PERSISTED_KEY',
        details: {'error': e.toString()},
      );
      return null;
    }

    if (persistedKey == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_NO_PERSISTED_KEY',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return null;
    }

    try {
      await callGroupUpdateKey(
        bridge,
        groupId: groupId,
        groupKey: persistedKey.encryptedKey,
        keyEpoch: persistedKey.keyGeneration,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_RESYNC_ERROR',
        details: {'error': e.toString()},
      );
      return null;
    }

    final preTransitionStateHash = await buildGroupTransitionStateHash(
      groupRepo,
      groupId,
    );
    final draftRepo = groupRepo is GroupKeyRotationDraftRepository
        ? groupRepo as GroupKeyRotationDraftRepository
        : null;
    final expectedEpoch = persistedKey.keyGeneration + 1;

    final pendingDraftResult = await _loadUsablePendingRotationDraft(
      draftRepo: draftRepo,
      groupId: groupId,
      persistedEpoch: persistedKey.keyGeneration,
      expectedEpoch: expectedEpoch,
    );
    if (pendingDraftResult.failedClosed) {
      return null;
    }
    final pendingDraft = pendingDraftResult.draft;

    late final int newEpoch;
    late final String newKey;
    late final DateTime generatedAt;

    if (pendingDraft != null) {
      newEpoch = pendingDraft.keyGeneration;
      newKey = pendingDraft.encryptedKey;
      generatedAt = pendingDraft.createdAt;
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_PENDING_DRAFT_REUSED',
        details: {'newEpoch': newEpoch},
      );
    } else {
      // 1. Generate the next key without updating Go state yet.
      final generateResult = await callGroupGenerateNextKey(bridge, groupId);
      if (generateResult['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ROTATE_KEY_BRIDGE_ERROR',
          details: {
            'groupId': _diagnosticPrefix(groupId),
            'keyEpoch': expectedEpoch,
            'membershipOperationId': _rotationOperationId(groupId, selfPeerId),
            'errorCode': generateResult['errorCode'],
          },
        );
        return null;
      }

      newEpoch = generateResult['keyEpoch'] as int;
      if (newEpoch != expectedEpoch) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ROTATE_KEY_EPOCH_MISMATCH',
          details: {
            'persistedEpoch': persistedKey.keyGeneration,
            'generatedEpoch': newEpoch,
          },
        );
        return null;
      }
      newKey = generateResult['groupKey'] as String;
      generatedAt = DateTime.now().toUtc();

      final savedDraft = await _savePendingRotationDraft(
        draftRepo: draftRepo,
        groupId: groupId,
        keyGeneration: newEpoch,
        encryptedKey: newKey,
        createdAt: generatedAt,
      );
      if (!savedDraft) {
        return null;
      }
    }
    final directKeyUpdateEventAt = DateTime.now().toUtc();
    final maxDistributionAttempts = distributionAttemptCount < 1
        ? 1
        : distributionAttemptCount;

    // 2. Distribute to remaining members via concurrent 1:1 encrypted P2P.
    final members = await groupRepo.getMembers(groupId);
    final distributionTargets = members
        .expand(
          (member) => member
              .activeDevicesWithLegacyFallback()
              .where((device) => device.mlKemPublicKey?.isNotEmpty == true)
              .where(
                (device) =>
                    member.peerId != selfPeerId ||
                    sourceDevice == null ||
                    device.deviceId != sourceDevice.deviceId,
              )
              .map((device) => (member: member, device: device)),
        )
        .toList(growable: false);
    final distributionFutures = distributionTargets
        .map(
          (target) => _distributeRotatedKeyToDeviceWithRetry(
            bridge: bridge,
            groupRepo: groupRepo,
            groupId: groupId,
            sourcePeerId: selfPeerId,
            sourceDevice: sourceDevice,
            senderPublicKey: senderPublicKey,
            senderPrivateKey: senderPrivateKey,
            senderUsername: senderUsername,
            member: target.member,
            device: target.device,
            newEpoch: newEpoch,
            newKey: newKey,
            eventAt: directKeyUpdateEventAt,
            preTransitionStateHash: preTransitionStateHash,
            sendP2PMessage: sendP2PMessage,
            perRecipientTimeout: perRecipientTimeout,
            attemptCount: maxDistributionAttempts,
            retryDelay: distributionRetryDelay,
          ),
        )
        .toList();

    var distributionResults = <bool>[];
    try {
      distributionResults =
          await Future.wait(distributionFutures, eagerError: false).timeout(
            distributionTimeout,
            onTimeout: () =>
                List<bool>.filled(distributionTargets.length, false),
          );
    } on Exception catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_DISTRIBUTE_ERROR',
        details: {'error': e.toString()},
      );
      distributionResults = List<bool>.filled(
        distributionTargets.length,
        false,
      );
    }

    final failedDistributionCount = distributionResults
        .where((ok) => !ok)
        .length;
    if (failedDistributionCount > 0) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_DISTRIBUTION_INCOMPLETE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'newEpoch': newEpoch,
          'targetCount': distributionTargets.length,
          'failedCount': failedDistributionCount,
        },
      );
      return null;
    }

    // 3. Promote the admin's own validator and local key only after
    // every required recipient confirms key delivery.
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
      createdAt: generatedAt,
    );
    await groupRepo.saveKey(keyInfo);
    await draftRepo?.clearPendingKeyRotation(groupId, newEpoch);

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ROTATE_KEY_SAVED',
      details: {'newEpoch': newEpoch},
    );

    // 4. Broadcast key_rotated system message after admin promotion.
    try {
      final rotatedAt = keyInfo.createdAt.toUtc();
      final sourceEventId =
          'key_rotated:$groupId:$selfPeerId:${rotatedAt.microsecondsSinceEpoch}:$newEpoch';
      final sysPayload = await signGroupSystemTransitionPayload(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        transitionType: 'key_rotated',
        sourceEventId: sourceEventId,
        eventAt: rotatedAt,
        actorPeerId: selfPeerId,
        actorUsername: senderUsername,
        actorSigningPublicKey: senderPublicKey,
        actorPrivateKey: senderPrivateKey,
        actorDeviceId: sourceDevice?.deviceId,
        actorTransportPeerId: sourceDevice?.transportPeerId,
        preTransitionStateHash: preTransitionStateHash,
        systemPayload: {'__sys': 'key_rotated', 'newKeyEpoch': newEpoch},
      );
      final sysMessage = jsonEncode(sysPayload);

      await callGroupPublish(
        bridge,
        groupId: groupId,
        text: sysMessage,
        senderPeerId: selfPeerId,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: senderPrivateKey,
        senderUsername: senderUsername,
        messageId: sourceEventId,
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
        'distributedTo': distributionTargets.length,
      },
    );

    return keyInfo;
  });
}

final Map<String, Future<void>> _groupRotationQueues = <String, Future<void>>{};

Future<({GroupKeyInfo? draft, bool failedClosed})>
_loadUsablePendingRotationDraft({
  required GroupKeyRotationDraftRepository? draftRepo,
  required String groupId,
  required int persistedEpoch,
  required int expectedEpoch,
}) async {
  if (draftRepo == null) {
    return (draft: null, failedClosed: false);
  }

  final pendingDraft = await draftRepo.getPendingKeyRotation(groupId);
  if (pendingDraft == null) {
    return (draft: null, failedClosed: false);
  }

  if (pendingDraft.keyGeneration <= persistedEpoch) {
    await draftRepo.clearPendingKeyRotation(
      groupId,
      pendingDraft.keyGeneration,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ROTATE_KEY_PENDING_DRAFT_STALE_CLEARED',
      details: {
        'persistedEpoch': persistedEpoch,
        'pendingEpoch': pendingDraft.keyGeneration,
      },
    );
    return (draft: null, failedClosed: false);
  }

  if (pendingDraft.keyGeneration != expectedEpoch ||
      pendingDraft.encryptedKey.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ROTATE_KEY_PENDING_DRAFT_EPOCH_MISMATCH',
      details: {
        'persistedEpoch': persistedEpoch,
        'expectedEpoch': expectedEpoch,
        'pendingEpoch': pendingDraft.keyGeneration,
      },
    );
    return (draft: null, failedClosed: true);
  }

  return (draft: pendingDraft, failedClosed: false);
}

Future<bool> _savePendingRotationDraft({
  required GroupKeyRotationDraftRepository? draftRepo,
  required String groupId,
  required int keyGeneration,
  required String encryptedKey,
  required DateTime createdAt,
}) async {
  if (draftRepo == null) {
    return true;
  }

  try {
    await draftRepo.savePendingKeyRotation(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: keyGeneration,
        encryptedKey: encryptedKey,
        createdAt: createdAt,
      ),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ROTATE_KEY_PENDING_DRAFT_SAVED',
      details: {'newEpoch': keyGeneration},
    );
    return true;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ROTATE_KEY_PENDING_DRAFT_SAVE_ERROR',
      details: {'error': e.toString()},
    );
    return false;
  }
}

Future<T> _withSerializedGroupRotation<T>(
  String groupId,
  Future<T> Function() body,
) async {
  final previous = _groupRotationQueues[groupId];
  final gate = Completer<void>();
  _groupRotationQueues[groupId] = gate.future;

  if (previous != null) {
    await previous;
  }

  try {
    return await body();
  } finally {
    gate.complete();
    if (identical(_groupRotationQueues[groupId], gate.future)) {
      _groupRotationQueues.remove(groupId);
    }
  }
}

Future<bool> _distributeRotatedKeyToDeviceWithRetry({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String sourcePeerId,
  required GroupMemberDeviceIdentity? sourceDevice,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  required GroupMember member,
  required GroupMemberDeviceIdentity device,
  required int newEpoch,
  required String newKey,
  required DateTime eventAt,
  required String preTransitionStateHash,
  required Future<bool> Function(String peerId, String message)? sendP2PMessage,
  required Duration perRecipientTimeout,
  required int attemptCount,
  required Duration retryDelay,
}) async {
  for (var attempt = 1; attempt <= attemptCount; attempt++) {
    final sent = await _distributeRotatedKeyToDevice(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      sourcePeerId: sourcePeerId,
      sourceDevice: sourceDevice,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      senderUsername: senderUsername,
      member: member,
      device: device,
      newEpoch: newEpoch,
      newKey: newKey,
      eventAt: eventAt,
      preTransitionStateHash: preTransitionStateHash,
      sendP2PMessage: sendP2PMessage,
      perRecipientTimeout: perRecipientTimeout,
    );
    if (sent) {
      return true;
    }
    if (attempt < attemptCount && retryDelay > Duration.zero) {
      await Future<void>.delayed(retryDelay);
    }
  }
  return false;
}

Future<bool> _distributeRotatedKeyToDevice({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String sourcePeerId,
  required GroupMemberDeviceIdentity? sourceDevice,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  required GroupMember member,
  required GroupMemberDeviceIdentity device,
  required int newEpoch,
  required String newKey,
  required DateTime eventAt,
  required String preTransitionStateHash,
  required Future<bool> Function(String peerId, String message)? sendP2PMessage,
  required Duration perRecipientTimeout,
}) async {
  try {
    final signedPayload = canonicalGroupKeyUpdateSignedPayload(
      groupId: groupId,
      sourcePeerId: sourcePeerId,
      sourceDeviceId: sourceDevice?.deviceId,
      sourceTransportPeerId: sourceDevice?.transportPeerId,
      recipientPeerId: member.peerId,
      recipientDeviceId: device.deviceId,
      recipientTransportPeerId: device.transportPeerId,
      recipientKeyPackageId: device.keyPackageId,
      keyGeneration: newEpoch,
      encryptedKey: newKey,
    );
    final signResult = await callSignPayload(
      bridge: bridge,
      dataToSign: signedPayload,
      privateKey: senderPrivateKey,
    );
    final signature = signResult['signature'];
    if (signResult['ok'] != true || signature is! String || signature.isEmpty) {
      return false;
    }
    final sourceEventId = _directKeyUpdateSourceEventId(
      groupId: groupId,
      sourcePeerId: sourcePeerId,
      sourceDevice: sourceDevice,
      recipientPeerId: member.peerId,
      recipientDevice: device,
      keyGeneration: newEpoch,
    );
    final transitionSubject = buildGroupKeyUpdateTransitionSubject(
      groupId: groupId,
      sourcePeerId: sourcePeerId,
      sourceDeviceId: sourceDevice?.deviceId,
      sourceTransportPeerId: sourceDevice?.transportPeerId,
      recipientPeerId: member.peerId,
      recipientDeviceId: device.deviceId,
      recipientTransportPeerId: device.transportPeerId,
      recipientKeyPackageId: device.keyPackageId,
      keyGeneration: newEpoch,
      encryptedKey: newKey,
    );
    final signedTransitionAudit = await signGroupTransitionAudit(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      transitionType: 'group_key_update',
      sourceEventId: sourceEventId,
      eventAt: eventAt,
      actorPeerId: sourcePeerId,
      actorUsername: senderUsername,
      actorSigningPublicKey:
          sourceDevice?.deviceSigningPublicKey ?? senderPublicKey,
      actorPrivateKey: senderPrivateKey,
      actorDeviceId: sourceDevice?.deviceId,
      actorTransportPeerId: sourceDevice?.transportPeerId,
      actorKeyPackageId: sourceDevice?.keyPackageId,
      preTransitionStateHash: preTransitionStateHash,
      transitionSubject: transitionSubject,
    );

    final encryptResult = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: device.mlKemPublicKey!,
      plaintext: jsonEncode({
        'groupId': groupId,
        'sourceEventId': sourceEventId,
        'eventAt': eventAt.toIso8601String(),
        'sourcePeerId': sourcePeerId,
        if (sourceDevice != null) 'sourceDeviceId': sourceDevice.deviceId,
        if (sourceDevice != null)
          'sourceTransportPeerId': sourceDevice.transportPeerId,
        'recipientPeerId': member.peerId,
        'recipientDeviceId': device.deviceId,
        'recipientTransportPeerId': device.transportPeerId,
        if (device.keyPackageId != null)
          'recipientKeyPackageId': device.keyPackageId,
        'keyGeneration': newEpoch,
        'encryptedKey': newKey,
        'signatureAlgorithm': groupKeyUpdateSignatureAlgorithm,
        'signedPayload': signedPayload,
        'signature': signature,
        signedGroupTransitionAuditField: signedTransitionAudit,
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
        sendP2PMessage?.call(device.transportPeerId, envelope) ??
        Future.value(true);
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
        'deviceId': device.deviceId.length > 8
            ? device.deviceId.substring(0, 8)
            : device.deviceId,
        'error': e.toString(),
      },
    );
    return false;
  }
}

String _directKeyUpdateSourceEventId({
  required String groupId,
  required String sourcePeerId,
  required GroupMemberDeviceIdentity? sourceDevice,
  required String recipientPeerId,
  required GroupMemberDeviceIdentity recipientDevice,
  required int keyGeneration,
}) {
  return [
    'group_key_update',
    groupId,
    sourcePeerId,
    sourceDevice?.deviceId ?? 'legacy-source',
    recipientPeerId,
    recipientDevice.deviceId,
    keyGeneration.toString(),
  ].join(':');
}

GroupMemberDeviceIdentity? _resolveSourceDevice({
  required GroupMember? selfMember,
  required String senderPublicKey,
  required String? sourceDeviceId,
}) {
  if (selfMember == null) {
    return null;
  }
  final requestedDeviceId = sourceDeviceId?.trim();
  if (requestedDeviceId != null && requestedDeviceId.isNotEmpty) {
    return selfMember.findDeviceById(
      requestedDeviceId,
      allowLegacyFallback: selfMember.devices.isEmpty,
    );
  }
  return selfMember.firstActiveDeviceForSigningKey(
    senderPublicKey,
    allowLegacyFallback: selfMember.devices.isEmpty,
  );
}
