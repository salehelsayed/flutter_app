import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

String _diagnosticPrefix(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;

String _addMemberOperationId(String groupId, String peerId) =>
    'add:${_diagnosticPrefix(groupId)}:${_diagnosticPrefix(peerId)}';

String? _bridgeErrorCode(Object error) =>
    error is BridgeCommandException ? error.errorCode : null;

const addGroupMemberGroupMismatchMessage =
    'Group member belongs to a different group';
const addGroupMemberElevatedTargetBlockedMessage =
    'Only admins can add admins or assign member permission overrides';
const groupMembershipMutationDissolvedMessage =
    'Cannot mutate membership of a dissolved group';
const staleGroupMembershipEventMessage = 'Stale group membership event';

class PreparedGroupMemberAddAuthority {
  const PreparedGroupMemberAddAuthority({
    required this.activate,
    required this.rollback,
  });

  final Future<void> Function() activate;
  final Future<void> Function() rollback;
}

/// The protected member-add projection may have committed even though a
/// repository projection, native config response, or local watermark write
/// failed. Callers must retain the exact durable PREPARED authority and let
/// restart recovery reconcile it; treating this as a proven rejection could
/// strand or publish an authority transition with a different projection.
class GroupMemberAddCommitAmbiguous implements Exception {
  const GroupMemberAddCommitAmbiguous({
    required this.cause,
    this.rollbackError,
  });

  final Object cause;
  final Object? rollbackError;

  @override
  String toString() {
    final rollback = rollbackError;
    return rollback == null
        ? 'Group member add commit outcome is ambiguous: $cause'
        : 'Group member add commit outcome is ambiguous: $cause; '
              'local rollback or durable abort also failed: $rollback';
  }
}

typedef PrepareGroupMemberAddAuthority =
    Future<PreparedGroupMemberAddAuthority?> Function({
      required GroupModel group,
      required List<GroupMember> members,
      required GroupMember addedMember,
      required DateTime eventAt,
      required String eventId,
    });

bool _sameOptionalString(String? left, String? right) {
  String? normalize(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  return normalize(left) == normalize(right);
}

bool _sameOptionalDateTime(DateTime? left, DateTime? right) {
  if (left == null || right == null) return left == right;
  return left.toUtc().isAtSameMomentAs(right.toUtc());
}

bool _samePermissions(
  GroupMemberPermissions left,
  GroupMemberPermissions right,
) {
  return left.inviteMembers == right.inviteMembers &&
      left.removeMembers == right.removeMembers &&
      left.manageRoles == right.manageRoles &&
      left.rotateKeys == right.rotateKeys &&
      left.editMetadata == right.editMetadata &&
      left.pinMessages == right.pinMessages &&
      left.deleteMessages == right.deleteMessages;
}

bool _sameDeviceIdentity(
  GroupMemberDeviceIdentity left,
  GroupMemberDeviceIdentity right,
) {
  return left.deviceId == right.deviceId &&
      left.transportPeerId == right.transportPeerId &&
      left.deviceSigningPublicKey == right.deviceSigningPublicKey &&
      _sameOptionalString(left.mlKemPublicKey, right.mlKemPublicKey) &&
      _sameOptionalString(left.keyPackageId, right.keyPackageId) &&
      _sameOptionalString(
        left.keyPackagePublicMaterial,
        right.keyPackagePublicMaterial,
      ) &&
      left.status == right.status &&
      _sameOptionalDateTime(left.revokedAt, right.revokedAt);
}

bool _sameDeviceSet(
  List<GroupMemberDeviceIdentity> left,
  List<GroupMemberDeviceIdentity> right,
) {
  if (left.isEmpty || right.isEmpty || left.length != right.length) {
    return false;
  }
  final rightByDeviceId = {for (final device in right) device.deviceId: device};
  if (rightByDeviceId.length != right.length) return false;
  for (final leftDevice in left) {
    final rightDevice = rightByDeviceId[leftDevice.deviceId];
    if (rightDevice == null || !_sameDeviceIdentity(leftDevice, rightDevice)) {
      return false;
    }
  }
  return true;
}

bool _isIdenticalDuplicateMemberAdd({
  required GroupMember existingMember,
  required GroupMember newMember,
}) {
  return existingMember.groupId == newMember.groupId &&
      existingMember.peerId == newMember.peerId &&
      _sameOptionalString(existingMember.username, newMember.username) &&
      existingMember.role == newMember.role &&
      _samePermissions(existingMember.permissions, newMember.permissions) &&
      _sameOptionalString(existingMember.publicKey, newMember.publicKey) &&
      _sameOptionalString(
        existingMember.mlKemPublicKey,
        newMember.mlKemPublicKey,
      ) &&
      _sameDeviceSet(existingMember.devices, newMember.devices) &&
      existingMember.joinedAt.toUtc().isAtSameMomentAs(
        newMember.joinedAt.toUtc(),
      );
}

bool _memberAllows(
  GroupMember? member,
  GroupRole fallbackRole,
  GroupMemberPermission permission,
) {
  return member != null
      ? member.permissions.allows(permission, member.role)
      : fallbackRole == GroupRole.admin;
}

/// Adds a new member to a group.
///
/// The caller must be an admin of the group. Saves the member to the
/// local repository. Key distribution happens at a higher level via
/// 1:1 ML-KEM encrypted messages.
Future<void> addGroupMember({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required GroupMember newMember,
  required String selfPeerId,
  bool syncBridgeConfig = true,
  // B5 (Part B, optional forward secrecy): when opted in AND the caller supplies
  // identity credentials, rotate the group key after a successful add so a joiner
  // cannot read prior-epoch live/GossipSub traffic. Default OFF — enabling it adds
  // a full key rotation + per-device distribution to every add, a deliberate
  // cost/latency trade-off the caller opts into. Rotation is creator-gated inside
  // rotateAndDistributeGroupKey, so non-creator adders are a safe no-op.
  bool rotateKeyOnAdd = false,
  String? senderPublicKey,
  String? senderPrivateKey,
  String? senderUsername,
  Future<bool> Function(String peerId, String message)? sendP2PMessage,
  Future<bool> Function(String peerId, String message)? storeP2PMessageInInbox,
  PrepareGroupMemberAddAuthority? prepareAuthority,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_ADD_MEMBER_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'peerId': newMember.peerId.length > 8
          ? newMember.peerId.substring(0, 8)
          : newMember.peerId,
    },
  );

  if (isGroupRecoveryInProgress()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_RECOVERY_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    throw StateError(groupRecoveryPendingError);
  }

  await runGroupMembershipMutationLocked<void>(
    groupId: groupId,
    action: () async {
      // 1. Load group, verify caller is admin
      final group = await groupRepo.getGroup(groupId);
      if (group == null) {
        throw StateError('Group not found: $groupId');
      }
      if (group.isDissolved) {
        throw StateError(groupMembershipMutationDissolvedMessage);
      }

      final selfMember = await groupRepo.getMember(groupId, selfPeerId);
      final canInvite = _memberAllows(
        selfMember,
        group.myRole,
        GroupMemberPermission.inviteMembers,
      );
      final canManageRoles = _memberAllows(
        selfMember,
        group.myRole,
        GroupMemberPermission.manageRoles,
      );
      if (!canInvite) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ADD_MEMBER_USE_CASE_NOT_ADMIN',
          details: {'role': group.myRole.toValue()},
        );
        throw StateError(
          'Only admins can add members unless invite permission is granted',
        );
      }

      final memberToAdd = newMember.copyWith(peerId: newMember.peerId.trim());
      if (memberToAdd.groupId != groupId) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ADD_MEMBER_USE_CASE_GROUP_MISMATCH',
          details: {
            'groupId': _diagnosticPrefix(groupId),
            'memberGroupId': _diagnosticPrefix(memberToAdd.groupId),
          },
        );
        throw ArgumentError.value(
          memberToAdd.groupId,
          'newMember.groupId',
          addGroupMemberGroupMismatchMessage,
        );
      }
      if ((memberToAdd.role == MemberRole.admin ||
              memberToAdd.permissions.hasOverrides) &&
          !canManageRoles) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ADD_MEMBER_USE_CASE_ROLE_BOUNDARY_BLOCKED',
          details: {
            'groupId': _diagnosticPrefix(groupId),
            'peerId': _diagnosticPrefix(memberToAdd.peerId),
          },
        );
        throw StateError(addGroupMemberElevatedTargetBlockedMessage);
      }
      if (!hasDeliverableGroupMemberIdentity(memberToAdd)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ADD_MEMBER_USE_CASE_INVALID_INVITE_TARGET',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'peerId': memberToAdd.peerId.length > 8
                ? memberToAdd.peerId.substring(0, 8)
                : memberToAdd.peerId,
          },
        );
        throw StateError('Cannot add group member without a delivery identity');
      }

      final existingMember = await groupRepo.getMember(
        groupId,
        memberToAdd.peerId,
      );
      if (existingMember != null) {
        if (_isIdenticalDuplicateMemberAdd(
          existingMember: existingMember,
          newMember: memberToAdd,
        )) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_ADD_MEMBER_USE_CASE_DUPLICATE_IDEMPOTENT',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
              'peerId': memberToAdd.peerId.length > 8
                  ? memberToAdd.peerId.substring(0, 8)
                  : memberToAdd.peerId,
            },
          );
          return;
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ADD_MEMBER_USE_CASE_ALREADY_MEMBER',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'peerId': memberToAdd.peerId.length > 8
                ? memberToAdd.peerId.substring(0, 8)
                : memberToAdd.peerId,
          },
        );
        throw StateError('Member already exists');
      }

      final membershipEventAt = memberToAdd.joinedAt.toUtc();
      if (isStaleGroupMembershipEvent(
        eventAt: membershipEventAt,
        lastMembershipEventAt: group.lastMembershipEventAt,
      )) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ADD_MEMBER_USE_CASE_STALE_EVENT',
          details: {
            'groupId': _diagnosticPrefix(groupId),
            'peerId': _diagnosticPrefix(memberToAdd.peerId),
            'eventAt': membershipEventAt.toIso8601String(),
          },
        );
        throw StateError(staleGroupMembershipEventMessage);
      }

      final currentMembers = await groupRepo.getMembers(groupId);
      ensureWithinGroupMembershipLimit(
        currentMemberCount: currentMembers.length,
        requestedAdditionalMembers: 1,
      );

      final keyMaterialRejectReason = groupMemberKeyMaterialRejectReason(
        memberToAdd,
      );
      if (keyMaterialRejectReason != null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ADD_MEMBER_USE_CASE_INVALID_KEY_MATERIAL',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'peerId': memberToAdd.peerId.length > 8
                ? memberToAdd.peerId.substring(0, 8)
                : memberToAdd.peerId,
            'reason': keyMaterialRejectReason,
          },
        );
        throw ArgumentError(
          'Invalid group member key material: $keyMaterialRejectReason',
        );
      }

      final sourceEventId = canonicalMembershipEventId(
        transitionType: 'member_added',
        groupId: groupId,
        actorPeerId: selfPeerId,
        eventAt: membershipEventAt,
      );
      final preparedAuthority = await prepareAuthority?.call(
        group: group,
        members: currentMembers,
        addedMember: memberToAdd,
        eventAt: membershipEventAt,
        eventId: sourceEventId,
      );

      // A protected PREPARED fact owns a signed config and may egress from the
      // restart runner. It therefore cannot use the contact picker's legacy
      // "save now, batch native sync later" path: exact native config and the
      // exact event watermark must converge before activation can COMPLETE it.
      final mustSyncBridgeConfig =
          syncBridgeConfig || preparedAuthority != null;

      // 2. Save member to repo
      try {
        await groupRepo.saveMember(memberToAdd);
      } catch (error, stackTrace) {
        if (preparedAuthority != null) {
          // GroupRepositoryImpl writes SQL before its fallible external
          // projection. Once issued, a throw cannot prove the member is absent.
          Error.throwWithStackTrace(
            GroupMemberAddCommitAmbiguous(cause: error),
            stackTrace,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }

      // Slice 2 (Finding 03): a (re-)added member with valid key material may be
      // owed a deferred key distribution from an earlier rotation that deferred
      // it while keyless — drain it promptly (fire-and-forget; the member passed
      // key-material validation above, so it is deliverable; app resume is the
      // catch-all for in-place key regenerations).
      await triggerDeferredDistributionDrainForPeer(
        groupId: groupId,
        peerId: memberToAdd.peerId,
      );

      if (!mustSyncBridgeConfig) {
        await _activatePreparedAddAuthority(
          preparedAuthority,
          groupId: groupId,
          memberPeerId: memberToAdd.peerId,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ADD_MEMBER_USE_CASE_SKIPPED_SYNC',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          },
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ADD_MEMBER_USE_CASE_SUCCESS',
          details: {
            'peerId': memberToAdd.peerId.length > 8
                ? memberToAdd.peerId.substring(0, 8)
                : memberToAdd.peerId,
          },
        );
        return;
      }

      try {
        // Every fallible read/build after the local write is inside the same
        // ambiguous boundary. A repository may have committed the member even
        // when a subsequent projection-backed roster load fails.
        final allMembers = await groupRepo.getMembers(groupId);
        final groupConfig = buildGroupConfigPayload(
          group.copyWith(lastMembershipEventAt: membershipEventAt),
          allMembers,
          configVersionOverride: membershipEventAt,
        );
        await callGroupUpdateConfig(
          bridge,
          groupId: groupId,
          groupConfig: groupConfig,
        );
        await recordGroupMembershipEventWatermark(
          groupRepo: groupRepo,
          groupId: groupId,
          eventAt: membershipEventAt,
          eventId: sourceEventId,
        );

        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ADD_MEMBER_USE_CASE_SUCCESS',
          details: {
            'peerId': memberToAdd.peerId.length > 8
                ? memberToAdd.peerId.substring(0, 8)
                : memberToAdd.peerId,
          },
        );
      } catch (e, stackTrace) {
        // An explicit `{ok:false}` response proves the native command rejected
        // this exact config. Only that outcome permits local rollback followed
        // by durable authority abort. Timeout/transport loss, projection
        // failure, and post-native watermark failure remain restart-repairable.
        if (preparedAuthority != null && e is! BridgeCommandException) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_ADD_MEMBER_USE_CASE_COMMIT_AMBIGUOUS',
            details: {
              'groupId': _diagnosticPrefix(groupId),
              'peerId': _diagnosticPrefix(memberToAdd.peerId),
            },
          );
          Error.throwWithStackTrace(
            GroupMemberAddCommitAmbiguous(cause: e),
            stackTrace,
          );
        }

        Object? rollbackError;
        try {
          await groupRepo.removeMember(groupId, memberToAdd.peerId);
          // Abort only after the local rollback is known to have completed.
          await preparedAuthority?.rollback();
        } catch (rollbackFailure) {
          rollbackError = rollbackFailure;
        }
        final errorCode = _bridgeErrorCode(e);
        emitFlowEvent(
          layer: 'FL',
          event: rollbackError == null
              ? 'GROUP_ADD_MEMBER_USE_CASE_REVERTED'
              : 'GROUP_ADD_MEMBER_USE_CASE_COMMIT_AMBIGUOUS',
          details: {
            'groupId': _diagnosticPrefix(groupId),
            'peerId': _diagnosticPrefix(memberToAdd.peerId),
            'membershipOperationId': _addMemberOperationId(
              groupId,
              memberToAdd.peerId,
            ),
            'errorCode': ?errorCode,
            'error': e.toString(),
            'rollbackFailed': rollbackError != null,
          },
        );
        if (rollbackError != null && preparedAuthority != null) {
          Error.throwWithStackTrace(
            GroupMemberAddCommitAmbiguous(
              cause: e,
              rollbackError: rollbackError,
            ),
            stackTrace,
          );
        }
        Error.throwWithStackTrace(e, stackTrace);
      }

      await _activatePreparedAddAuthority(
        preparedAuthority,
        groupId: groupId,
        memberPeerId: memberToAdd.peerId,
      );

      // B5: forward rotation on add. Runs ONLY after the member is added AND the
      // config-sync committed (the catch above rethrows on sync failure, so we
      // never reach here with an un-synced member). A rotation failure is
      // best-effort/logged and does NOT revert the member — the member is
      // legitimately added, so reverting would diverge state; missing forward
      // secrecy on one add is the acceptable degradation.
      if (rotateKeyOnAdd &&
          senderPublicKey != null &&
          senderPrivateKey != null &&
          senderUsername != null) {
        try {
          final outcome = await rotateAndDistributeGroupKey(
            bridge: bridge,
            groupRepo: groupRepo,
            groupId: groupId,
            selfPeerId: selfPeerId,
            senderPublicKey: senderPublicKey,
            senderPrivateKey: senderPrivateKey,
            senderUsername: senderUsername,
            sendP2PMessage: sendP2PMessage,
            storeP2PMessageInInbox: storeP2PMessageInInbox,
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_ADD_MEMBER_FORWARD_ROTATION',
            details: {
              'groupId': _diagnosticPrefix(groupId),
              'rotated': outcome.rotated,
              'fullyDistributed': outcome.fullyDistributed,
            },
          );
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_ADD_MEMBER_FORWARD_ROTATION_ERROR',
            details: {
              'groupId': _diagnosticPrefix(groupId),
              'error': e.toString(),
            },
          );
        }
      }
    },
  );
}

Future<void> _activatePreparedAddAuthority(
  PreparedGroupMemberAddAuthority? prepared, {
  required String groupId,
  required String memberPeerId,
}) async {
  if (prepared == null) return;
  try {
    await prepared.activate();
  } catch (error, stackTrace) {
    // The prepared outbox remains the retry owner. Surface the unresolved
    // COMPLETE boundary so callers stop ordinary publish/fanout; never roll
    // back a locally/native-committed membership transition.
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_PROTECTED_ACTIVATION_DEFERRED',
      details: {
        'groupId': _diagnosticPrefix(groupId),
        'peerId': _diagnosticPrefix(memberPeerId),
        'error': error.toString(),
      },
    );
    Error.throwWithStackTrace(
      GroupMemberAddCommitAmbiguous(cause: error),
      stackTrace,
    );
  }
}
