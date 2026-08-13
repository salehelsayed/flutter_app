import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_key_update_signature.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

String _diagnosticPrefix(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;

String _rotationOperationId(String groupId, String peerId) =>
    'rotate:${_diagnosticPrefix(groupId)}:${_diagnosticPrefix(peerId)}';

/// Hook invoked once per remaining member that could NOT be delivered the new
/// epoch during rotation (keyless at rotation time, or every device delivery
/// failed). Slice 1 wires a no-op default; Slice 2 supplies a durable
/// sender-side distribution queue so deferred members converge later.
typedef EnqueueDeferredGroupKeyDistribution =
    Future<void> Function({
      required String groupId,
      required String peerId,
      required int keyEpoch,
    });

/// Process-wide fallback sink for deferred distributions. When a caller does not
/// pass an explicit [EnqueueDeferredGroupKeyDistribution] (all production rotate
/// call sites — admin removal, voluntary leave, and the creator backstop — do
/// not), the rotation persists each deferred peer through this sink instead.
///
/// Wired once at startup (`main.dart`) to the `GroupPendingKeyDistribution`
/// repository, mirroring the existing `debugSetFlowEventSink` pattern — so the
/// Slice 2 queue is reached from every rotate path without threading a callback
/// through the entire widget DI chain. Tests set it to an in-memory repo (and
/// reset it to null in teardown) or pass the explicit param.
EnqueueDeferredGroupKeyDistribution? _deferredGroupKeyDistributionSink;

void setDeferredGroupKeyDistributionSink(
  EnqueueDeferredGroupKeyDistribution? sink,
) {
  _deferredGroupKeyDistributionSink = sink;
}

/// Process-wide trigger to ENQUEUE a deferred key distribution for [peerId] at
/// [keyEpoch] through the wired sink, mirroring
/// [triggerDeferredDistributionDrainForPeer] (the drain half). No-op when no
/// sink is wired; never throws.
///
/// Used by sibling-device admission (B1b): admitting a NEW device to an
/// already-keyed member produces no pending row on its own, so the drain alone
/// delivers nothing. Enqueueing the current epoch here creates the durable row
/// the runner then drains, re-distributing the current key to the member's
/// now-deliverable devices (including the freshly admitted one).
Future<void> triggerDeferredGroupKeyDistributionEnqueue({
  required String groupId,
  required String peerId,
  required int keyEpoch,
}) async {
  final sink = _deferredGroupKeyDistributionSink;
  if (sink == null) return;
  try {
    await sink(groupId: groupId, peerId: peerId, keyEpoch: keyEpoch);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_KEY_DISTRIBUTION_ENQUEUE_TRIGGER_ERROR',
      details: {
        'groupId': _diagnosticPrefix(groupId),
        'peerId': _diagnosticPrefix(peerId),
        'error': e.toString(),
      },
    );
  }
}

EnqueueDeferredGroupKeyDistribution? _deferredGroupKeyDistributionReopenSink;

void setDeferredGroupKeyDistributionReopenSink(
  EnqueueDeferredGroupKeyDistribution? sink,
) {
  _deferredGroupKeyDistributionReopenSink = sink;
}

/// Process-wide trigger to (re)OPEN a deferred distribution row for [peerId] to
/// PENDING at [keyEpoch], OVERRIDING a terminal (distributed/unreachable) row.
///
/// Distinct from [triggerDeferredGroupKeyDistributionEnqueue]: this is for when
/// the member's DEVICE SET changed (a sibling device was admitted) and the
/// current key must be re-distributed to the now-larger device set — so it
/// deliberately re-arms an exhausted/finalized row (the prior exhaustion was for
/// the old device set; INV-D4's "never mask exhaustion" applies to stale rotation
/// re-enqueues, not to a genuine device-set change). No-op when no reopen sink is
/// wired (the device then converges via the next group key rotation); never throws.
Future<void> triggerDeferredGroupKeyDistributionReopen({
  required String groupId,
  required String peerId,
  required int keyEpoch,
}) async {
  final sink = _deferredGroupKeyDistributionReopenSink;
  if (sink == null) return;
  try {
    await sink(groupId: groupId, peerId: peerId, keyEpoch: keyEpoch);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_KEY_DISTRIBUTION_REOPEN_TRIGGER_ERROR',
      details: {
        'groupId': _diagnosticPrefix(groupId),
        'peerId': _diagnosticPrefix(peerId),
        'error': e.toString(),
      },
    );
  }
}

/// Result of a [rotateAndDistributeGroupKey] attempt.
///
/// Distinguishes three outcomes that the old `GroupKeyInfo?` return conflated:
/// - **rotated + fully distributed** ([rotated] true, [fullyDistributed] true):
///   the new epoch was generated, promoted, and persisted locally, and every
///   remaining member was delivered the key.
/// - **rotated but partially distributed** ([rotated] true,
///   [fullyDistributed] false): the epoch was promoted (so the removed member
///   has lost the live key) but one or more remaining members are deferred —
///   they were keyless at rotation time or their delivery failed. This is NOT a
///   failure: forward secrecy for the boundary is intact; the deferred members
///   converge later.
/// - **not rotated** ([rotated] false): a genuine generate/promote failure;
///   the epoch did not advance and nothing changed.
class RotateGroupKeyOutcome {
  /// Non-null iff a new epoch was promoted and saved locally.
  final GroupKeyInfo? key;

  /// Count of device targets that confirmed delivery (direct or inbox).
  final int distributedDeviceCount;

  /// Remaining members NOT delivered the new epoch now (keyless OR
  /// delivery-failed). Empty when every remaining member received it.
  final List<String> deferredPeerIds;

  const RotateGroupKeyOutcome({
    this.key,
    this.distributedDeviceCount = 0,
    this.deferredPeerIds = const <String>[],
  });

  /// True when a new epoch was promoted (the removed member lost the live key).
  bool get rotated => key != null;

  /// True when the rotated epoch reached every remaining member.
  bool get fullyDistributed => deferredPeerIds.isEmpty;

  /// Canonical "no epoch was promoted" result (genuine failure).
  static const notRotated = RotateGroupKeyOutcome();
}

/// Generates the next group encryption key, distributes it to remaining
/// members, then promotes the admin validator and local key last.
///
/// Steps:
/// 1. Generates the next key without mutating Go validator state
/// 2. Distributes the new key to remaining members
/// 3. Promotes the admin validator and saves the new key locally
/// 4. Broadcasts a key_rotated system message on the group topic
///
/// Returns a [RotateGroupKeyOutcome]: [RotateGroupKeyOutcome.rotated] is true
/// whenever the epoch was promoted (even if some members are deferred);
/// [RotateGroupKeyOutcome.notRotated] is returned only on a genuine
/// generate/promote failure.
Future<RotateGroupKeyOutcome> rotateAndDistributeGroupKey({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String selfPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  String? sourceDeviceId,
  Future<bool> Function(String peerId, String message)? sendP2PMessage,
  Future<bool> Function(String peerId, String message)? storeP2PMessageInInbox,
  Duration perRecipientTimeout = const Duration(seconds: 5),
  Duration distributionTimeout = const Duration(seconds: 15),
  int distributionAttemptCount = 5,
  Duration distributionRetryDelay = const Duration(milliseconds: 500),
  EnqueueDeferredGroupKeyDistribution? enqueueDeferredDistribution,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_ROTATE_KEY_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  return _withSerializedGroupRotation<RotateGroupKeyOutcome>(groupId, () async {
    final group = await groupRepo.getGroup(groupId);
    if (group == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_GROUP_NOT_FOUND',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return RotateGroupKeyOutcome.notRotated;
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
      return RotateGroupKeyOutcome.notRotated;
    }

    if (group.createdBy != selfPeerId) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_PERMISSION_DENIED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return RotateGroupKeyOutcome.notRotated;
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
      return RotateGroupKeyOutcome.notRotated;
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
      return RotateGroupKeyOutcome.notRotated;
    }

    if (persistedKey == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_NO_PERSISTED_KEY',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return RotateGroupKeyOutcome.notRotated;
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
      return RotateGroupKeyOutcome.notRotated;
    }

    final members = await groupRepo.getMembers(groupId);
    // Promote-then-defer: a remaining member with no deliverable device (keyless
    // at rotation time) no longer ABORTS the rotation. Forward secrecy for the
    // *boundary* (the removed member) outranks synchronous convergence for an
    // already-broken insider. Keyless members are recorded as deferred; the
    // epoch is still generated and promoted, so the removed member loses the
    // live key unconditionally. Deferred members converge later (Slice 2 / a
    // future rotation / the receiver decrypt-retry runner).
    final keylessRemainingMembers = _undeliverableActiveMembers(
      members: members,
      selfPeerId: selfPeerId,
    );
    if (keylessRemainingMembers.isNotEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_KEYLESS_MEMBERS_DEFERRED',
        details: {
          'groupId': _diagnosticPrefix(groupId),
          'keylessCount': keylessRemainingMembers.length,
          'peerIds': keylessRemainingMembers
              .map((member) => _diagnosticPrefix(member.peerId))
              .toList(growable: false),
        },
      );
    }

    final distributionTargets = members
        .expand(
          (member) => _deliverableDevicesForRotation(member)
              .where(
                (device) =>
                    member.peerId != selfPeerId ||
                    sourceDevice == null ||
                    device.deviceId != sourceDevice.deviceId,
              )
              .map((device) => (member: member, device: device)),
        )
        .toList(growable: false);

    if (distributionTargets.isNotEmpty && sendP2PMessage == null) {
      // No transport available: every reachable member is treated as deferred
      // rather than aborting. The epoch is still generated and promoted below so
      // the removed member loses the live key. (Production removal always
      // supplies a transport via group_info_wired; this guards test/edge calls.)
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_TRANSPORT_UNAVAILABLE',
        details: {
          'groupId': _diagnosticPrefix(groupId),
          'targetCount': distributionTargets.length,
        },
      );
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
      return RotateGroupKeyOutcome.notRotated;
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
        return RotateGroupKeyOutcome.notRotated;
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
        return RotateGroupKeyOutcome.notRotated;
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
        return RotateGroupKeyOutcome.notRotated;
      }
    }
    // The current pending-draft schema only persists epoch, key, and createdAt.
    // Reusing createdAt stabilizes direct eventAt and signed audit on retry;
    // preTransitionStateHash is recomputed until the schema can persist it.
    final directKeyUpdateEventAt = generatedAt.toUtc();
    final maxDistributionAttempts = distributionAttemptCount < 1
        ? 1
        : distributionAttemptCount;

    // 2. Prepare target-qualified protected key authority before promoting the
    // local epoch. Each replay payload is the incumbent signed+encrypted direct
    // key update for that exact device; the protected envelope freezes the
    // complete pre-transition physical ACL but emits only the selected target.
    final protectedPreparations = <int, ProtectedGroupAuthorityPreparation>{};
    if (hasProtectedGroupAuthorityAdapter &&
        hasProtectedGroupPhysicalAuthority(members) &&
        distributionTargets.isNotEmpty) {
      if (sourceDevice == null) {
        return RotateGroupKeyOutcome.notRotated;
      }
      final frozenRecipients = freezeProtectedGroupPhysicalRecipients(members);
      final protectedTransitionId =
          'group_key_update:$groupId:$selfPeerId:$newEpoch:'
          '${directKeyUpdateEventAt.microsecondsSinceEpoch}';
      for (var index = 0; index < distributionTargets.length; index++) {
        final target = distributionTargets[index];
        final built = await _buildRotatedKeyDeviceEnvelope(
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
        );
        if (built == null) {
          for (final preparation in protectedPreparations.values) {
            await cancelProtectedGroupAuthority(preparation);
          }
          return RotateGroupKeyOutcome.notRotated;
        }
        final preparation = await prepareProtectedGroupAuthority(
          ProtectedGroupAuthorityPrepareRequest(
            groupId: groupId,
            transitionId: protectedTransitionId,
            control: ProtectedGroupAuthorityControl.groupKeyUpdate,
            replayData: <String, dynamic>{
              'groupId': groupId,
              'keyGeneration': newEpoch,
              'encryptedKey': newKey,
              'from': sourceDevice.transportPeerId,
              'to': target.device.transportPeerId,
              'content': built.envelope,
              'timestamp': directKeyUpdateEventAt.toIso8601String(),
            },
            actorAccountPeerId: selfPeerId,
            actorAccountPublicKey: senderPublicKey,
            actorAccountPrivateKey: senderPrivateKey,
            senderDevice: sourceDevice,
            frozenRecipients: frozenRecipients,
            deliveryRecipients: <GroupMemberDeviceIdentity>[target.device],
          ),
        );
        if (preparation == null || !preparation.hasRecipients) {
          for (final prepared in protectedPreparations.values) {
            await cancelProtectedGroupAuthority(prepared);
          }
          return RotateGroupKeyOutcome.notRotated;
        }
        protectedPreparations[index] = preparation;
      }
    }

    // Incumbent ordinary delivery is preserved only when the protected adapter
    // is absent. A protected target never races the live/generic inbox path.
    final distributionResults = <bool>[];
    for (var index = 0; index < distributionTargets.length; index++) {
      final target = distributionTargets[index];
      if (protectedPreparations.containsKey(index)) {
        distributionResults.add(false);
        continue;
      }
      try {
        final sent = await _distributeRotatedKeyToDeviceWithRetry(
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
          storeP2PMessageInInbox: storeP2PMessageInInbox,
          perRecipientTimeout: perRecipientTimeout,
          attemptCount: maxDistributionAttempts,
          retryDelay: distributionRetryDelay,
        );
        distributionResults.add(sent);
      } on Exception catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ROTATE_KEY_DISTRIBUTE_ERROR',
          details: {'error': e.toString()},
        );
        distributionResults.add(false);
      }
    }

    // 3. Promote the admin's own validator and local key. Prepared protected
    // bytes already exist, so a crash after this point cannot lose authority.
    try {
      await callGroupUpdateKey(
        bridge,
        groupId: groupId,
        groupKey: newKey,
        keyEpoch: newEpoch,
      );
    } catch (e) {
      for (final preparation in protectedPreparations.values) {
        await cancelProtectedGroupAuthority(preparation);
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_PROMOTE_ERROR',
        details: {'error': e.toString()},
      );
      return RotateGroupKeyOutcome.notRotated;
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

    for (final entry in protectedPreparations.entries) {
      try {
        distributionResults[entry.key] = await activateProtectedGroupAuthority(
          entry.value,
          requireAllCustody: true,
        );
      } catch (_) {
        // The exact prepared row remains the durable retry owner.
        distributionResults[entry.key] = false;
      }
    }

    final distributedDeviceCount = distributionResults.where((ok) => ok).length;
    final failedDistributionCount =
        distributionResults.length - distributedDeviceCount;

    // A remaining member is "delivered" when at least one of its device targets
    // has exact custody. All other current members retain the existing durable
    // pending-key-distribution owner.
    final memberDelivered = <String, bool>{};
    for (var i = 0; i < distributionTargets.length; i++) {
      final peerId = distributionTargets[i].member.peerId;
      memberDelivered[peerId] =
          (memberDelivered[peerId] ?? false) || distributionResults[i];
    }
    final deferredPeers = <String>[];
    for (final member in members) {
      if (member.peerId == selfPeerId) {
        continue;
      }
      if (!(memberDelivered[member.peerId] ?? false)) {
        deferredPeers.add(member.peerId);
      }
    }

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
    }

    // 3b. Enqueue deferred members for later distribution. The epoch is already
    // promoted, so these members are temporarily on the old epoch (a degraded
    // read for an already-broken member, NOT a security hole — the removed
    // member is durably excluded). Slice 2 supplies the durable drain; the
    // injected seam defaults to a no-op in Slice 1.
    final deferredSink =
        enqueueDeferredDistribution ?? _deferredGroupKeyDistributionSink;
    if (deferredPeers.isNotEmpty) {
      for (final peerId in deferredPeers) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ROTATE_KEY_DEFERRED_REPAIR_QUEUED',
          details: {
            'groupId': _diagnosticPrefix(groupId),
            'peerId': _diagnosticPrefix(peerId),
            'newEpoch': newEpoch,
          },
        );
        if (deferredSink != null) {
          try {
            await deferredSink(
              groupId: groupId,
              peerId: peerId,
              keyEpoch: newEpoch,
            );
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_ROTATE_KEY_DEFERRED_ENQUEUE_ERROR',
              details: {
                'peerId': _diagnosticPrefix(peerId),
                'error': e.toString(),
              },
            );
          }
        }
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ROTATE_KEY_PARTIAL_DISTRIBUTION',
        details: {
          'groupId': _diagnosticPrefix(groupId),
          'newEpoch': newEpoch,
          'deferredCount': deferredPeers.length,
          'distributedDeviceCount': distributedDeviceCount,
        },
      );
    }

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
        senderDeviceId: sourceDevice?.deviceId,
        senderTransportPeerId: sourceDevice?.transportPeerId,
        senderDevicePublicKey: sourceDevice?.deviceSigningPublicKey,
        senderKeyPackageId: sourceDevice?.keyPackageId,
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

    return RotateGroupKeyOutcome(
      key: keyInfo,
      distributedDeviceCount: distributedDeviceCount,
      deferredPeerIds: deferredPeers,
    );
  });
}

/// Slice 2 drainer entry: re-distributes the **current** persisted group key to
/// one previously-deferred [peerId]'s now-deliverable devices, reusing the exact
/// signed/encrypted direct key-update path a fresh rotation uses. Returns the
/// number of device targets that confirmed delivery (0 = still keyless /
/// undeliverable). It does NOT rotate the epoch, mutate group state, or touch
/// the pending-distribution queue — the caller (the runner) records attempts and
/// finalizes. INV-D2: always reads `getLatestKey`, never a stale epoch.
Future<int> distributeCurrentGroupKeyToDeferredPeer({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String peerId,
  required String selfPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  String? sourceDeviceId,
  required Future<bool> Function(String peerId, String message)? sendP2PMessage,
  Future<bool> Function(String peerId, String message)? storeP2PMessageInInbox,
  Duration perRecipientTimeout = const Duration(seconds: 5),
  int attemptCount = 3,
  Duration retryDelay = const Duration(milliseconds: 500),
}) async {
  final members = await groupRepo.getMembers(groupId);
  final selfMatches = members.where((member) => member.peerId == selfPeerId);
  final selfMember = selfMatches.isEmpty ? null : selfMatches.first;
  final targetMatches = members.where((member) => member.peerId == peerId);
  if (targetMatches.isEmpty) {
    return 0;
  }
  final target = targetMatches.first;

  final devices = _deliverableDevicesForRotation(target);
  if (devices.isEmpty) {
    // Still keyless on every active device.
    return 0;
  }

  final latestKey = await groupRepo.getLatestKey(groupId);
  if (latestKey == null) {
    return 0;
  }
  final sourceDevice = _resolveSourceDevice(
    selfMember: selfMember,
    senderPublicKey: senderPublicKey,
    sourceDeviceId: sourceDeviceId,
  );
  final preTransitionStateHash = await buildGroupTransitionStateHash(
    groupRepo,
    groupId,
  );
  final eventAt = DateTime.now().toUtc();

  // Once this group owns a distinct physical-device roster, deferred key
  // repair stays on the same target-qualified protected authority lane as a
  // fresh rotation. It must never fall back to live/group_store delivery.
  if (hasProtectedGroupAuthorityAdapter &&
      hasProtectedGroupPhysicalAuthority(members)) {
    if (sourceDevice == null) return 0;
    final frozenRecipients = freezeProtectedGroupPhysicalRecipients(members);
    final transitionId =
        'group_key_update_deferred:$groupId:$selfPeerId:$peerId:'
        '${latestKey.keyGeneration}';
    var protectedDelivered = 0;
    for (final device in devices) {
      try {
        final built = await _buildRotatedKeyDeviceEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          sourcePeerId: selfPeerId,
          sourceDevice: sourceDevice,
          senderPublicKey: senderPublicKey,
          senderPrivateKey: senderPrivateKey,
          senderUsername: senderUsername,
          member: target,
          device: device,
          newEpoch: latestKey.keyGeneration,
          newKey: latestKey.encryptedKey,
          eventAt: eventAt,
          preTransitionStateHash: preTransitionStateHash,
        );
        if (built == null) continue;
        final preparation = await prepareProtectedGroupAuthority(
          ProtectedGroupAuthorityPrepareRequest(
            groupId: groupId,
            transitionId: transitionId,
            control: ProtectedGroupAuthorityControl.groupKeyUpdate,
            replayData: <String, dynamic>{
              'groupId': groupId,
              'keyGeneration': latestKey.keyGeneration,
              'encryptedKey': latestKey.encryptedKey,
              'from': sourceDevice.transportPeerId,
              'to': device.transportPeerId,
              'content': built.envelope,
              'timestamp': eventAt.toIso8601String(),
            },
            actorAccountPeerId: selfPeerId,
            actorAccountPublicKey: senderPublicKey,
            actorAccountPrivateKey: senderPrivateKey,
            senderDevice: sourceDevice,
            frozenRecipients: frozenRecipients,
            deliveryRecipients: <GroupMemberDeviceIdentity>[device],
          ),
        );
        if (preparation == null || !preparation.hasRecipients) continue;
        if (await activateProtectedGroupAuthority(
          preparation,
          requireAllCustody: true,
        )) {
          protectedDelivered++;
        }
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_DISTRIBUTION_PROTECTED_RETRY_DEFERRED',
          details: {
            'peerId': _diagnosticPrefix(peerId),
            'error': error.toString(),
          },
        );
      }
    }
    return protectedDelivered;
  }

  final maxAttempts = attemptCount < 1 ? 1 : attemptCount;
  var delivered = 0;
  for (final device in devices) {
    try {
      final sent = await _distributeRotatedKeyToDeviceWithRetry(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        sourcePeerId: selfPeerId,
        sourceDevice: sourceDevice,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: senderPrivateKey,
        senderUsername: senderUsername,
        member: target,
        device: device,
        newEpoch: latestKey.keyGeneration,
        newKey: latestKey.encryptedKey,
        eventAt: eventAt,
        preTransitionStateHash: preTransitionStateHash,
        sendP2PMessage: sendP2PMessage,
        storeP2PMessageInInbox: storeP2PMessageInInbox,
        perRecipientTimeout: perRecipientTimeout,
        attemptCount: maxAttempts,
        retryDelay: retryDelay,
      );
      if (sent) {
        delivered++;
      }
    } on Exception catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_KEY_DISTRIBUTION_REDISTRIBUTE_ERROR',
        details: {'peerId': _diagnosticPrefix(peerId), 'error': e.toString()},
      );
    }
  }
  return delivered;
}

/// Targeted active-pull delivery (UDM-G responder): re-distributes the group key
/// at the EXACT requested [keyEpoch] (loaded via `getKeyByGeneration`, never
/// `getLatestKey`) to one [peerId]'s now-deliverable devices, reusing the exact
/// signed/encrypted direct key-update path a fresh rotation uses. Returns the
/// number of device targets that confirmed delivery (0 = still keyless /
/// undeliverable / the epoch is not held locally).
///
/// MINTS NO NEW EPOCH: it never calls `group:generateNextKey` / `group:updateKey`
/// / `saveKey` / a draft promote. The admin only re-delivers an epoch it already
/// holds — `getKeyByGeneration(groupId, keyEpoch)` returning null is a no-op.
Future<int> distributeGroupKeyAtEpochToPeer({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String peerId,
  required int keyEpoch,
  required String selfPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  String? sourceDeviceId,
  required Future<bool> Function(String peerId, String message)? sendP2PMessage,
  Future<bool> Function(String peerId, String message)? storeP2PMessageInInbox,
  Duration perRecipientTimeout = const Duration(seconds: 5),
  int attemptCount = 3,
  Duration retryDelay = const Duration(milliseconds: 500),
}) async {
  final epochKey = await groupRepo.getKeyByGeneration(groupId, keyEpoch);
  if (epochKey == null) {
    // The admin does not hold the requested epoch — never mint or substitute.
    return 0;
  }

  final members = await groupRepo.getMembers(groupId);
  final selfMatches = members.where((member) => member.peerId == selfPeerId);
  final selfMember = selfMatches.isEmpty ? null : selfMatches.first;
  final targetMatches = members.where((member) => member.peerId == peerId);
  if (targetMatches.isEmpty) {
    return 0;
  }
  final target = targetMatches.first;

  final devices = _deliverableDevicesForRotation(target);
  if (devices.isEmpty) {
    return 0;
  }

  final sourceDevice = _resolveSourceDevice(
    selfMember: selfMember,
    senderPublicKey: senderPublicKey,
    sourceDeviceId: sourceDeviceId,
  );
  final preTransitionStateHash = await buildGroupTransitionStateHash(
    groupRepo,
    groupId,
  );
  final eventAt = DateTime.now().toUtc();

  final maxAttempts = attemptCount < 1 ? 1 : attemptCount;
  var delivered = 0;
  for (final device in devices) {
    try {
      final sent = await _distributeRotatedKeyToDeviceWithRetry(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        sourcePeerId: selfPeerId,
        sourceDevice: sourceDevice,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: senderPrivateKey,
        senderUsername: senderUsername,
        member: target,
        device: device,
        newEpoch: epochKey.keyGeneration,
        newKey: epochKey.encryptedKey,
        eventAt: eventAt,
        preTransitionStateHash: preTransitionStateHash,
        sendP2PMessage: sendP2PMessage,
        storeP2PMessageInInbox: storeP2PMessageInInbox,
        perRecipientTimeout: perRecipientTimeout,
        attemptCount: maxAttempts,
        retryDelay: retryDelay,
      );
      if (sent) {
        delivered++;
      }
    } on Exception catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_KEY_REPAIR_REDISTRIBUTE_ERROR',
        details: {'peerId': _diagnosticPrefix(peerId), 'error': e.toString()},
      );
    }
  }
  return delivered;
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
  required Future<bool> Function(String peerId, String message)?
  storeP2PMessageInInbox,
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
      storeP2PMessageInInbox: storeP2PMessageInInbox,
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

class _BuiltRotatedKeyDeviceEnvelope {
  const _BuiltRotatedKeyDeviceEnvelope(this.envelope);

  final String envelope;
}

Future<_BuiltRotatedKeyDeviceEnvelope?> _buildRotatedKeyDeviceEnvelope({
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
      return null;
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
    if (encryptResult['ok'] != true) return null;
    return _BuiltRotatedKeyDeviceEnvelope(
      jsonEncode({
        'type': 'group_key_update',
        'version': '2',
        'encrypted': {
          'kem': encryptResult['kem'],
          'ciphertext': encryptResult['ciphertext'],
          'nonce': encryptResult['nonce'],
        },
      }),
    );
  } catch (_) {
    return null;
  }
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
  required Future<bool> Function(String peerId, String message)?
  storeP2PMessageInInbox,
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

    if (sendP2PMessage == null) {
      return false;
    }

    return await _sendDirectWithInboxFallback(
      transportPeerId: device.transportPeerId,
      envelope: envelope,
      sendP2PMessage: sendP2PMessage,
      storeP2PMessageInInbox: storeP2PMessageInInbox,
      perRecipientTimeout: perRecipientTimeout,
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

List<GroupMember> _undeliverableActiveMembers({
  required List<GroupMember> members,
  required String selfPeerId,
}) {
  return members
      .where((member) => member.peerId != selfPeerId)
      .where((member) => _deliverableDevicesForRotation(member).isEmpty)
      .toList(growable: false);
}

/// Public mirror of the rotation deferral deliverability predicate: the devices
/// of [member] eligible to receive a group-key distribution (active, usable
/// ML-KEM public key, with the legacy member-level fallback). Receive-side drain
/// triggers use this so "regained a usable key" means exactly what rotation's
/// promote/defer logic means — no second, drifting definition of "keyless".
List<GroupMemberDeviceIdentity> deliverableGroupKeyDevices(
  GroupMember member,
) => _deliverableDevicesForRotation(member);

List<GroupMemberDeviceIdentity> _deliverableDevicesForRotation(
  GroupMember member,
) {
  final candidates = member.devices.isEmpty
      ? member.activeDevicesWithLegacyFallback()
      : member.activeDevices;
  return candidates
      .where((device) => _hasUsableMlKemPublicKey(device.mlKemPublicKey))
      .toList(growable: false);
}

bool _hasUsableMlKemPublicKey(String? value) =>
    value != null && value.trim().isNotEmpty;

Future<bool> _sendDirectWithInboxFallback({
  required String transportPeerId,
  required String envelope,
  required Future<bool> Function(String peerId, String message) sendP2PMessage,
  required Future<bool> Function(String peerId, String message)?
  storeP2PMessageInInbox,
  required Duration perRecipientTimeout,
}) async {
  Future<bool>? directFuture;

  try {
    var directTimedOut = false;
    directFuture = sendP2PMessage(transportPeerId, envelope);
    var directSent = await directFuture.timeout(
      perRecipientTimeout,
      onTimeout: () {
        directTimedOut = true;
        return false;
      },
    );
    if (directTimedOut) {
      directSent = await _awaitLateDeliveryResult(directFuture);
    }
    if (directSent) {
      return true;
    }
    return await _tryInboxFallback(
      transportPeerId: transportPeerId,
      envelope: envelope,
      storeP2PMessageInInbox: storeP2PMessageInInbox,
      perRecipientTimeout: perRecipientTimeout,
    );
  } catch (_) {
    return await _tryInboxFallback(
      transportPeerId: transportPeerId,
      envelope: envelope,
      storeP2PMessageInInbox: storeP2PMessageInInbox,
      perRecipientTimeout: perRecipientTimeout,
    );
  }
}

Future<bool> _tryInboxFallback({
  required String transportPeerId,
  required String envelope,
  required Future<bool> Function(String peerId, String message)?
  storeP2PMessageInInbox,
  required Duration perRecipientTimeout,
}) async {
  if (storeP2PMessageInInbox == null) {
    return false;
  }

  Future<bool>? inboxFuture;
  try {
    var inboxTimedOut = false;
    inboxFuture = storeP2PMessageInInbox(transportPeerId, envelope);
    final stored = await inboxFuture.timeout(
      perRecipientTimeout,
      onTimeout: () {
        inboxTimedOut = true;
        return false;
      },
    );
    return inboxTimedOut ? await _awaitLateDeliveryResult(inboxFuture) : stored;
  } catch (_) {
    return false;
  }
}

Future<bool> _awaitLateDeliveryResult(Future<bool> future) async {
  try {
    return await future;
  } catch (_) {
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
