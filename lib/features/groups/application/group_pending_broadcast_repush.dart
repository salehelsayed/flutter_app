import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/application/group_role_update_authorization.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/application/self_removed_group_lifecycle_guard.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

enum ProtectedPreparedAuthorityGate {
  notProtected,
  complete,
  aborted,
  retryable,
}

typedef ResolveProtectedPreparedAuthorityGate =
    Future<ProtectedPreparedAuthorityGate> Function({
      required String groupId,
      required String eventId,
    });

/// Builds the [GroupPendingBroadcastRunner] re-push function: re-publishes a
/// stored (already-signed) broadcast verbatim and re-stores it to the relay
/// inbox for its recipients. Returns `true` only when both legs succeed, so a
/// partial failure retains the row for the next drain (idempotent — the
/// receive-side dedups by the broadcast's source message id).
Future<bool> Function(GroupPendingBroadcast broadcast)
buildGroupPendingBroadcastRePush({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required Future<IdentityModel?> Function() loadIdentity,
  GroupPendingBroadcastRepository? pendingRepository,
  ResolveProtectedPreparedAuthorityGate? resolveProtectedPreparedAuthority,
}) {
  return (broadcast) async {
    if (broadcast.kind == groupPendingBroadcastKindExitLeaveNotice) {
      return false;
    }
    final guarded = await runSelfRemovedGroupLifecycleLeaf<bool>(
      groupRepo: groupRepo,
      groupId: broadcast.groupId,
      action: (group) async {
        IdentityModel? identity;
        GroupSenderDeviceBinding? senderBinding;
        // A remote dissolve can commit after this row was shortlisted. The
        // fresh lifecycle read inside the membership phase is authoritative;
        // never publish a payload for a group that has since dissolved.
        if (group.isDissolved) return false;

        Future<bool> finishExact() async {
          final repository = pendingRepository;
          if (repository == null) return true;
          return removeGroupPendingBroadcastIfExact(repository, broadcast);
        }

        if (pendingRepository != null) {
          final exactRows = await pendingRepository.forGroup(broadcast.groupId);
          final stillLoaded = exactRows.any(
            (current) => sameExactGroupPendingBroadcast(current, broadcast),
          );
          if (!stillLoaded) return false;
        }

        if (isPendingGroupMemberRoleBroadcastKind(broadcast.kind)) {
          if (broadcast.kind == groupPendingBroadcastKindMemberRolePrepared &&
              isGroupRolePreparationInFlight(broadcast.id)) {
            return false;
          }
          identity = await loadIdentity();
          final loadedIdentity = identity;
          if (loadedIdentity == null) return false;
          senderBinding = await resolveGroupSenderDeviceBinding(
            groupRepo: groupRepo,
            groupId: broadcast.groupId,
            senderPeerId: loadedIdentity.peerId,
            senderPublicKey: loadedIdentity.publicKey,
          );
          // Recheck after identity/device reads: an in-process preparation that
          // activated while those awaits were pending still owns this row.
          if (broadcast.kind == groupPendingBroadcastKindMemberRolePrepared &&
              isGroupRolePreparationInFlight(broadcast.id)) {
            return false;
          }
          if (!await _hasExactSignedRoleBroadcastAuthority(
            bridge: bridge,
            broadcast: broadcast,
            identity: loadedIdentity,
            senderBinding: senderBinding,
          )) {
            return false;
          }
        }

        if (broadcast.kind == groupPendingBroadcastKindMemberRolePrepared) {
          // This check must precede every await. A runner that loaded the prepared
          // row before activation must not later delete the activated row as stale.
          if (isGroupRolePreparationInFlight(broadcast.id)) return false;
          final preparedMember = _preparedRoleMember(broadcast.sysText);
          if (preparedMember == null) return false;
          var currentMember = await groupRepo.getMember(
            broadcast.groupId,
            preparedMember.peerId,
          );
          var currentGroup = await groupRepo.getGroup(broadcast.groupId);
          final sourceEventId = broadcast.sourceMessageId;
          var protectedAuthorityComplete = false;
          if (sourceEventId != null &&
              resolveProtectedPreparedAuthority != null) {
            final gate = await resolveProtectedPreparedAuthority(
              groupId: broadcast.groupId,
              eventId: sourceEventId,
            );
            switch (gate) {
              case ProtectedPreparedAuthorityGate.aborted:
                return finishExact();
              case ProtectedPreparedAuthorityGate.retryable:
                return false;
              case ProtectedPreparedAuthorityGate.complete:
                protectedAuthorityComplete = true;
              case ProtectedPreparedAuthorityGate.notProtected:
                break;
            }
          }
          var hasExactCommitProof =
              sourceEventId != null &&
              currentGroup?.lastMembershipEventId == sourceEventId &&
              currentGroup?.lastMembershipEventAt != null &&
              currentGroup!.lastMembershipEventAt!.toUtc().isAtSameMomentAs(
                broadcast.eventAt.toUtc(),
              );
          if (protectedAuthorityComplete) {
            if (currentMember?.role.toValue() != preparedMember.role) {
              return false;
            }
          } else if (!hasExactCommitProof ||
              currentMember?.role.toValue() != preparedMember.role) {
            final watermarkAt = currentGroup?.lastMembershipEventAt?.toUtc();
            final watermarkId = currentGroup?.lastMembershipEventId;
            final isSuperseded =
                sourceEventId != null &&
                watermarkAt != null &&
                (watermarkAt.isAfter(broadcast.eventAt.toUtc()) ||
                    (watermarkAt.isAtSameMomentAs(broadcast.eventAt.toUtc()) &&
                        watermarkId != null &&
                        watermarkId.compareTo(sourceEventId) > 0));
            if (isSuperseded) {
              // A newer authoritative membership event makes this prepared row
              // obsolete. It is safe to clear without publishing stale state.
              return finishExact();
            }
            final loadedIdentity = identity;
            if (loadedIdentity == null || sourceEventId == null) return false;
            final reconciled = await _reconcilePreparedRoleCommit(
              bridge: bridge,
              groupRepo: groupRepo,
              broadcast: broadcast,
              identity: loadedIdentity,
              preparedMember: preparedMember,
              hasExactCommitProof: hasExactCommitProof,
              currentGroup: currentGroup,
              currentMember: currentMember,
            );
            if (!reconciled) return false;
            currentMember = await groupRepo.getMember(
              broadcast.groupId,
              preparedMember.peerId,
            );
            currentGroup = await groupRepo.getGroup(broadcast.groupId);
            hasExactCommitProof =
                currentGroup?.lastMembershipEventId == sourceEventId &&
                currentGroup?.lastMembershipEventAt != null &&
                currentGroup!.lastMembershipEventAt!.toUtc().isAtSameMomentAs(
                  broadcast.eventAt.toUtc(),
                );
            if (!hasExactCommitProof ||
                currentMember?.role.toValue() != preparedMember.role) {
              return false;
            }
          }
        }

        identity ??= await loadIdentity();
        final loadedIdentity = identity;
        if (loadedIdentity == null) return false;

        senderBinding ??= await resolveGroupSenderDeviceBinding(
          groupRepo: groupRepo,
          groupId: broadcast.groupId,
          senderPeerId: loadedIdentity.peerId,
          senderPublicKey: loadedIdentity.publicKey,
        );
        final resolvedSenderBinding = senderBinding;

        final publishResult = await callGroupPublish(
          bridge,
          groupId: broadcast.groupId,
          text: broadcast.sysText,
          senderPeerId: loadedIdentity.peerId,
          senderPublicKey: loadedIdentity.publicKey,
          senderPrivateKey: loadedIdentity.privateKey,
          senderUsername: loadedIdentity.username,
          senderDeviceId: resolvedSenderBinding.deviceId,
          senderTransportPeerId: resolvedSenderBinding.transportPeerId,
          senderDevicePublicKey: resolvedSenderBinding.devicePublicKey,
          senderKeyPackageId: resolvedSenderBinding.keyPackageId,
          messageId: broadcast.sourceMessageId,
        );
        if (publishResult['ok'] != true) return false;

        if (broadcast.recipientPeerIds.isEmpty) {
          return finishExact();
        }

        final inboxPayload = jsonEncode({
          'groupId': broadcast.groupId,
          'senderId': loadedIdentity.peerId,
          'senderUsername': loadedIdentity.username,
          if (resolvedSenderBinding.deviceId != null)
            'senderDeviceId': resolvedSenderBinding.deviceId,
          if (resolvedSenderBinding.transportPeerId != null)
            'transportPeerId': resolvedSenderBinding.transportPeerId,
          'text': broadcast.sysText,
          'timestamp': broadcast.eventAt.toUtc().toIso8601String(),
          'messageId': broadcast.sourceMessageId,
        });
        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: broadcast.groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: inboxPayload,
          senderPeerId: loadedIdentity.peerId,
          senderPublicKey: loadedIdentity.publicKey,
          senderPrivateKey: loadedIdentity.privateKey,
          senderDeviceId: resolvedSenderBinding.deviceId,
          senderTransportPeerId: resolvedSenderBinding.transportPeerId,
          senderKeyPackageId: resolvedSenderBinding.keyPackageId,
          messageId: broadcast.sourceMessageId,
          recipientPeerIds: broadcast.recipientPeerIds,
        );
        await callGroupInboxStore(
          bridge,
          broadcast.groupId,
          replayEnvelope,
          recipientPeerIds: broadcast.recipientPeerIds,
          preserveRecipientPeerIds: true,
        );
        return finishExact();
      },
    );
    return guarded.didRun && (guarded.value ?? false);
  };
}

Future<bool> _hasExactSignedRoleBroadcastAuthority({
  required Bridge bridge,
  required GroupPendingBroadcast broadcast,
  required IdentityModel identity,
  required GroupSenderDeviceBinding senderBinding,
}) async {
  try {
    final sourceEventId = broadcast.sourceMessageId;
    final payload = _decodeStringMap(broadcast.sysText);
    final audit = _stringMap(payload?[signedGroupTransitionAuditField]);
    final signedPayloadText = audit?['signedPayload'];
    final signedPayload = signedPayloadText is String
        ? _decodeStringMap(signedPayloadText)
        : null;
    final actor = _stringMap(signedPayload?['actor']);
    if (sourceEventId == null ||
        payload == null ||
        payload['__sys'] != 'member_role_updated' ||
        payload['eventAt'] != broadcast.eventAt.toUtc().toIso8601String() ||
        actor == null ||
        actor['deviceId'] != senderBinding.deviceId ||
        actor['transportPeerId'] != senderBinding.transportPeerId ||
        actor['keyPackageId'] != senderBinding.keyPackageId) {
      return false;
    }
    final verification = await verifyGroupTransitionAudit(
      bridge: bridge,
      containerPayload: payload,
      groupId: broadcast.groupId,
      transitionType: 'member_role_updated',
      sourceEventId: sourceEventId,
      eventAt: broadcast.eventAt,
      actorPeerId: identity.peerId,
      actorUsername: identity.username,
      actorSigningPublicKey: identity.publicKey,
      actorDeviceId: senderBinding.deviceId,
      actorTransportPeerId: senderBinding.transportPeerId,
      expectedTransitionSubject: buildGroupSystemTransitionSubject(payload),
    );
    return verification.isValid;
  } catch (_) {
    return false;
  }
}

Future<bool> _reconcilePreparedRoleCommit({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupPendingBroadcast broadcast,
  required IdentityModel identity,
  required ({String peerId, String role}) preparedMember,
  required bool hasExactCommitProof,
  required GroupModel? currentGroup,
  required GroupMember? currentMember,
}) async {
  try {
    final sourceEventId = broadcast.sourceMessageId;
    final payload = _decodeStringMap(broadcast.sysText);
    final storedGroupConfig = _stringMap(payload?['groupConfig']);
    if (sourceEventId == null ||
        payload == null ||
        payload['__sys'] != 'member_role_updated' ||
        payload['eventAt'] != broadcast.eventAt.toUtc().toIso8601String() ||
        storedGroupConfig == null ||
        currentGroup == null ||
        currentMember == null) {
      return false;
    }
    final proposedRole = MemberRole.fromValue(preparedMember.role);
    if (canonicalMembershipEventId(
          transitionType: 'member_role_updated',
          groupId: broadcast.groupId,
          actorPeerId: identity.peerId,
          eventAt: broadcast.eventAt,
        ) !=
        sourceEventId) {
      return false;
    }

    final members = await groupRepo.getMembers(broadcast.groupId);
    final actorMatches = members
        .where((member) => member.peerId == identity.peerId)
        .toList(growable: false);
    final targetMatches = members
        .where((member) => member.peerId == preparedMember.peerId)
        .toList(growable: false);
    if (actorMatches.length != 1 || targetMatches.length != 1) return false;
    final proposedMembers = members
        .map(
          (member) => member.peerId == preparedMember.peerId
              ? member.copyWith(role: proposedRole)
              : member,
        )
        .toList(growable: false);
    if (!proposedMembers.any((member) => member.role == MemberRole.admin)) {
      return false;
    }
    final proposedGroup = preparedMember.peerId == identity.peerId
        ? currentGroup.copyWith(
            myRole: proposedRole == MemberRole.admin
                ? GroupRole.admin
                : GroupRole.member,
          )
        : currentGroup;
    final expectedGroupConfig = buildGroupConfigPayload(
      proposedGroup.copyWith(lastMembershipEventAt: broadcast.eventAt),
      proposedMembers,
      configVersionOverride: broadcast.eventAt,
    );
    if (canonicalizeGroupEventLogPayload(expectedGroupConfig) !=
        canonicalizeGroupEventLogPayload(storedGroupConfig)) {
      return false;
    }

    var authorizationMembers = members;
    var authorizationTargetRole = currentMember.role;

    if (!hasExactCommitProof) {
      // A prepared row without the exact watermark is retryable from either
      // its exact signed pre-state or the exact one-write post-state left when
      // member SQL committed before a projection threw. Reconstructing and
      // hashing the latter proves that no metadata, key, watermark, device, or
      // other membership state drifted alongside the target role.
      final signedPreStateHash = _signedPreTransitionStateHash(payload);
      final currentStateHash = await buildGroupTransitionStateHash(
        groupRepo,
        broadcast.groupId,
      );
      if (signedPreStateHash == null) return false;
      final isExactSignedPreState =
          currentMember.role != proposedRole &&
          currentStateHash == signedPreStateHash;
      var isExactSingleRoleWritePostState = false;
      if (currentMember.role == proposedRole) {
        final previousRoleValue = payload['previousRole'];
        if (previousRoleValue is! String) return false;
        final previousRole = MemberRole.fromValue(previousRoleValue);
        if (previousRole == proposedRole) return false;
        authorizationTargetRole = previousRole;
        authorizationMembers = members
            .map(
              (member) => member.peerId == preparedMember.peerId
                  ? member.copyWith(role: previousRole)
                  : member,
            )
            .toList(growable: false);
        final latestKey = await groupRepo.getLatestKey(broadcast.groupId);
        isExactSingleRoleWritePostState =
            buildGroupTransitionStateHashFromSnapshot(
              groupId: broadcast.groupId,
              group: currentGroup,
              members: authorizationMembers,
              latestKeyGeneration: latestKey?.keyGeneration,
            ) ==
            signedPreStateHash;
      }
      if (!isExactSignedPreState && !isExactSingleRoleWritePostState) {
        return false;
      }
      final authorizationActors = authorizationMembers
          .where((member) => member.peerId == identity.peerId)
          .toList(growable: false);
      final authorizationTargets = authorizationMembers
          .where((member) => member.peerId == preparedMember.peerId)
          .toList(growable: false);
      if (authorizationActors.length != 1 ||
          authorizationTargets.length != 1 ||
          !canApplyGroupMemberRoleUpdate(
            actor: authorizationActors.single,
            newRole: proposedRole,
            existingRole: authorizationTargetRole,
            existingPermissions: authorizationTargets.single.permissions,
          )) {
        return false;
      }
      await callGroupUpdateConfig(
        bridge,
        groupId: broadcast.groupId,
        groupConfig: storedGroupConfig,
      );
      // This watermark is written only after a definite successful native
      // response. If a later local write fails, the next retry can safely
      // complete that exact local projection without reissuing the config.
      await recordGroupMembershipEventWatermark(
        groupRepo: groupRepo,
        groupId: broadcast.groupId,
        eventAt: broadcast.eventAt,
        eventId: sourceEventId,
      );
    } else {
      final actorMember = actorMatches.single;
      if (!canApplyGroupMemberRoleUpdate(
        actor: actorMember,
        newRole: proposedRole,
        existingRole: currentMember.role,
        existingPermissions: currentMember.permissions,
      )) {
        return false;
      }
    }

    final roleAfterNative = await groupRepo.getMember(
      broadcast.groupId,
      preparedMember.peerId,
    );
    if (roleAfterNative?.role != proposedRole) {
      await groupRepo.updateMemberRole(
        broadcast.groupId,
        preparedMember.peerId,
        proposedRole,
      );
    }
    await _synchronizePreparedSelfRoleProjection(
      groupRepo: groupRepo,
      groupId: broadcast.groupId,
      selfPeerId: identity.peerId,
      targetPeerId: preparedMember.peerId,
      role: proposedRole,
    );

    final committedGroup = await groupRepo.getGroup(broadcast.groupId);
    final committedMember = await groupRepo.getMember(
      broadcast.groupId,
      preparedMember.peerId,
    );
    return committedGroup?.lastMembershipEventId == sourceEventId &&
        committedGroup?.lastMembershipEventAt != null &&
        committedGroup!.lastMembershipEventAt!.toUtc().isAtSameMomentAs(
          broadcast.eventAt.toUtc(),
        ) &&
        committedMember?.role == proposedRole;
  } catch (_) {
    return false;
  }
}

Future<void> _synchronizePreparedSelfRoleProjection({
  required GroupRepository groupRepo,
  required String groupId,
  required String selfPeerId,
  required String targetPeerId,
  required MemberRole role,
}) async {
  if (targetPeerId != selfPeerId) return;
  final group = await groupRepo.getGroup(groupId);
  if (group == null) return;
  final expected = role == MemberRole.admin
      ? GroupRole.admin
      : GroupRole.member;
  if (group.myRole != expected) {
    await groupRepo.updateGroup(group.copyWith(myRole: expected));
  }
}

Map<String, dynamic>? _decodeStringMap(String source) {
  try {
    return _stringMap(jsonDecode(source));
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

String? _signedPreTransitionStateHash(Map<String, dynamic> payload) {
  final audit = _stringMap(payload[signedGroupTransitionAuditField]);
  final signedPayload = audit?['signedPayload'];
  if (signedPayload is! String) return null;
  final decoded = _decodeStringMap(signedPayload);
  final value = decoded?['preTransitionStateHash'];
  return value is String && value.isNotEmpty ? value : null;
}

({String peerId, String role})? _preparedRoleMember(String sysText) {
  try {
    final payload = jsonDecode(sysText);
    if (payload is! Map<String, dynamic>) return null;
    final member = payload['member'];
    if (member is! Map<String, dynamic>) return null;
    final peerId = (member['peerId'] as String?)?.trim();
    final role = (member['role'] as String?)?.trim();
    if (peerId == null || peerId.isEmpty || role == null || role.isEmpty) {
      return null;
    }
    return (peerId: peerId, role: role);
  } catch (_) {
    return null;
  }
}
