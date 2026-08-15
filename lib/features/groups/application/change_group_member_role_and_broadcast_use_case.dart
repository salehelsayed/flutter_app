import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart'
    show groupMembershipMutationDissolvedMessage;
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/application/update_group_member_role_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

enum ChangeGroupMemberRoleAndBroadcastOutcome {
  unchanged,
  readyToLeave,
  pendingSync,
}

class ChangeGroupMemberRoleAndBroadcastResult {
  const ChangeGroupMemberRoleAndBroadcastResult({
    required this.outcome,
    required this.updatedMember,
    this.eventAt,
    this.sourceEventId,
    this.publishResult,
  });

  final ChangeGroupMemberRoleAndBroadcastOutcome outcome;
  final GroupMember updatedMember;
  final DateTime? eventAt;
  final String? sourceEventId;
  final Map<String, dynamic>? publishResult;
}

const groupRoleCandidateNoLongerEligibleMessage =
    'The selected member has not finished joining this group.';
const groupRoleTransitionStateChangedMessage =
    'The group changed while this role update was being prepared.';

final Map<String, DateTime> _lastPreparedRoleEventAtByGroup =
    <String, DateTime>{};
final Map<String, Future<void>> _groupRoleBroadcastActionLocks =
    <String, Future<void>>{};

Future<ChangeGroupMemberRoleAndBroadcastResult>
changeGroupMemberRoleAndBroadcast({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required IdentityRepository identityRepo,
  required String groupId,
  required String memberPeerId,
  required MemberRole role,
  GroupMessageRepository? messageRepo,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  String? senderDeviceId,
  Future<bool> Function(String peerId, String message)? sendP2PMessage,
  Future<void> Function(GroupPendingBroadcast broadcast)? enqueuePending,
  Future<List<GroupPendingBroadcast>> Function(String groupId)? loadPending,
  Future<void> Function(String id)? removePending,
}) => _runGroupRoleBroadcastActionLocked(groupId, () async {
  final identity = await identityRepo.loadIdentity();
  if (identity == null) throw StateError('No identity found');

  final group = await groupRepo.getGroup(groupId);
  final targetMember = await groupRepo.getMember(groupId, memberPeerId);
  final members = await groupRepo.getMembers(groupId);
  if (group == null || group.isDissolved || targetMember == null) {
    throw StateError('Group member not found');
  }
  if (targetMember.role == role) {
    return ChangeGroupMemberRoleAndBroadcastResult(
      outcome: ChangeGroupMemberRoleAndBroadcastOutcome.unchanged,
      updatedMember: targetMember,
    );
  }

  final isPromotion = role == MemberRole.admin;
  if (isPromotion &&
      !await _isCurrentPromotionCandidate(
        groupRepo: groupRepo,
        messageRepo: messageRepo,
        inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
        groupId: groupId,
        selfPeerId: identity.peerId,
        memberPeerId: memberPeerId,
      )) {
    throw StateError(groupRoleCandidateNoLongerEligibleMessage);
  }

  final eventAt = _nextPreparedRoleEventAt(group);
  final sourceEventId = canonicalMembershipEventId(
    transitionType: 'member_role_updated',
    groupId: groupId,
    actorPeerId: identity.peerId,
    eventAt: eventAt,
  );
  final proposedMember = targetMember.copyWith(role: role);
  final proposedMembers = members
      .map((member) => member.peerId == memberPeerId ? proposedMember : member)
      .toList(growable: false);
  final proposedGroup = memberPeerId == identity.peerId
      ? group.copyWith(
          myRole: role == MemberRole.admin ? GroupRole.admin : GroupRole.member,
          lastMembershipEventAt: eventAt,
        )
      : group.copyWith(lastMembershipEventAt: eventAt);
  final preTransitionStateHash = await buildGroupTransitionStateHash(
    groupRepo,
    groupId,
  );
  final senderBinding = await resolveGroupSenderDeviceBinding(
    groupRepo: groupRepo,
    groupId: groupId,
    senderPeerId: identity.peerId,
    preferredDeviceId: senderDeviceId,
    preferredTransportPeerId: senderDeviceId,
    senderPublicKey: identity.publicKey,
  );
  final signedPayload = await signGroupSystemTransitionPayload(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    transitionType: 'member_role_updated',
    sourceEventId: sourceEventId,
    eventAt: eventAt,
    actorPeerId: identity.peerId,
    actorUsername: identity.username,
    actorSigningPublicKey: identity.publicKey,
    actorPrivateKey: identity.privateKey,
    actorDeviceId: senderBinding.deviceId,
    actorTransportPeerId: senderBinding.transportPeerId,
    actorKeyPackageId: senderBinding.keyPackageId,
    preTransitionStateHash: preTransitionStateHash,
    systemPayload: {
      '__sys': 'member_role_updated',
      'eventAt': eventAt.toUtc().toIso8601String(),
      'previousRole': targetMember.role.toValue(),
      'member': proposedMember.toConfigJson(),
      'groupConfig': buildGroupConfigPayload(
        proposedGroup,
        proposedMembers,
        configVersionOverride: eventAt,
      ),
    },
  );
  final sysText = jsonEncode(signedPayload);
  final recipients = proposedMembers
      .where((member) => member.peerId != identity.peerId)
      .map((member) => member.peerId.trim())
      .where((peerId) => peerId.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (recipients.isEmpty) {
    throw StateError('Role transition requires at least one recipient');
  }
  // Signing and candidate construction are intentionally outside the shared
  // authority phase. They may involve bridge crypto and must not prevent a
  // competing terminal membership transition from committing. Everything
  // from durable PREPARED authority through the local/native role commit stays
  // in one membership mutation phase. The established final pre-commit state
  // recheck below either commits the signed transition or durably ABORTS every
  // prepared owner.
  return runGroupMembershipMutationLocked(
    groupId: groupId,
    action: () async {
      ProtectedGroupAuthorityPreparation? protectedPreparation;
      if (hasProtectedGroupAuthorityAdapter &&
          hasProtectedGroupPhysicalAuthority(members)) {
        final actor = members.singleWhere(
          (member) => member.peerId == identity.peerId,
        );
        final senderDevice = resolveProtectedGroupSenderDevice(
          actor: actor,
          senderPublicKey: senderBinding.devicePublicKey ?? identity.publicKey,
          senderDeviceId: senderBinding.deviceId,
          senderTransportPeerId:
              senderBinding.transportPeerId ?? identity.peerId,
        );
        if (senderDevice == null) {
          throw StateError(
            'Role transition sender device is not authoritative',
          );
        }
        protectedPreparation = await prepareProtectedGroupAuthority(
          ProtectedGroupAuthorityPrepareRequest(
            groupId: groupId,
            transitionId: sourceEventId,
            control: ProtectedGroupAuthorityControl.memberRole,
            replayData: <String, dynamic>{
              'groupId': groupId,
              'senderId': identity.peerId,
              'senderUsername': identity.username,
              if (senderBinding.deviceId != null)
                'senderDeviceId': senderBinding.deviceId,
              if (senderBinding.transportPeerId != null)
                'transportPeerId': senderBinding.transportPeerId,
              'text': sysText,
              'timestamp': eventAt.toUtc().toIso8601String(),
              'messageId': sourceEventId,
            },
            actorAccountPeerId: identity.peerId,
            actorAccountPublicKey: identity.publicKey,
            actorAccountPrivateKey: identity.privateKey,
            senderDevice: senderDevice,
            frozenRecipients: freezeProtectedGroupPhysicalRecipients(members),
          ),
        );
        if (protectedPreparation == null ||
            !protectedPreparation.hasAuthenticatedAuthority) {
          throw StateError('Role transition protected preparation failed');
        }
      }
      final createdAt = DateTime.now().toUtc();
      final pendingId = 'pending_group_broadcast:$groupId:$sourceEventId';
      final preparedPendingRow = GroupPendingBroadcast(
        id: pendingId,
        groupId: groupId,
        kind: groupPendingBroadcastKindMemberRolePrepared,
        sysText: sysText,
        recipientPeerIds: recipients,
        eventAt: eventAt,
        sourceMessageId: sourceEventId,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final pendingRow = GroupPendingBroadcast(
        id: pendingId,
        groupId: groupId,
        kind: groupPendingBroadcastKindMemberRoleUpdated,
        sysText: sysText,
        recipientPeerIds: recipients,
        eventAt: eventAt,
        sourceMessageId: sourceEventId,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      // Production always wires this outbox. A prepared row is durable before the
      // role/config commit and becomes the ordinary retry row after commit. A
      // concurrent runner retains it while this process is preparing; after a
      // restart it sends only when local role state proves the commit happened.
      final usesDurableOutbox =
          enqueuePending != null || hasGroupPendingBroadcastEnqueueSink;
      if (usesDurableOutbox) {
        markGroupRolePreparationInFlight(pendingId);
        try {
          await runGroupAuthorityPhaseIfNeeded(
            groupId: groupId,
            authorityPhaseHeld: isGroupAuthorityPhaseHeld(groupId),
            action: () async {
              // The prepared row is the decisive role-transition claim. Serialize
              // it with exit enqueue and Dissolve's final preflight. A winner that
              // already dissolved the group is also rejected before custom/fake
              // outbox implementations can persist an orphan row.
              final currentGroup = await groupRepo.getGroup(groupId);
              if (currentGroup == null || currentGroup.isDissolved) {
                throw StateError(groupMembershipMutationDissolvedMessage);
              }
              await _enqueueAndVerifyPending(
                preparedPendingRow,
                enqueuePending: enqueuePending,
                loadPending: loadPending,
              );
            },
          );
        } catch (queueError) {
          // Verification failure does not prove that the row at this deterministic
          // id belongs to this invocation. Preserve any collision rather than
          // deleting another durable transition; no role/config write has occurred.
          try {
            await _requireProtectedRoleAbort(protectedPreparation);
          } catch (abortError) {
            throw StateError(
              'Role transition was not committed because its durable prepared row '
              'could not be verified ($queueError), and its protected preparation '
              'could not be durably aborted ($abortError)',
            );
          } finally {
            clearGroupRolePreparationInFlight(pendingId);
          }
          throw StateError(
            'Role transition was not committed because its durable prepared row '
            'could not be verified: $queueError',
          );
        }
        // From this point the exact ordinary PREPARED row is a proven durable
        // owner of the same transition. Include it in a future protected abort so
        // ABORTED and retirement of every owner commit in one transaction.
        protectedPreparation = protectedPreparation?.withAbortRows(
          <GroupPendingBroadcast>[preparedPendingRow],
        );
      }

      ({DateTime eventAt, String eventId})? committed;
      try {
        committed = await updateGroupMemberRole(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          memberPeerId: memberPeerId,
          role: role,
          selfPeerId: identity.peerId,
          eventAt: eventAt,
          beforeCommit: () async {
            if (isPromotion &&
                !await _isCurrentPromotionCandidate(
                  groupRepo: groupRepo,
                  messageRepo: messageRepo,
                  inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
                  groupId: groupId,
                  selfPeerId: identity.peerId,
                  memberPeerId: memberPeerId,
                )) {
              throw StateError(groupRoleCandidateNoLongerEligibleMessage);
            }
            // The signed audit and groupConfig above describe one exact pre-state.
            // Fail closed if membership, metadata, dissolution, or key generation
            // changed while signing or durably preparing the outbox row; otherwise
            // native config could commit a fresh state beside a stale signed audit.
            // Keep this as the final awaited check before the first local write.
            final currentPreTransitionStateHash =
                await buildGroupTransitionStateHash(groupRepo, groupId);
            if (currentPreTransitionStateHash != preTransitionStateHash) {
              throw StateError(groupRoleTransitionStateChangedMessage);
            }
          },
        );
      } catch (commitError) {
        Object? abortError;
        Object? discardError;
        final commitIsAmbiguous = commitError is GroupMemberRoleCommitAmbiguous;
        final protectedAbortOwnsOrdinary =
            protectedPreparation?.abortRows.any(
              (row) => sameExactGroupPendingBroadcast(row, preparedPendingRow),
            ) ??
            false;
        if (commitIsAmbiguous) {
          // Native may already enforce the signed config. Keep the exact ordinary
          // and protected PREPARED owners as the durable convergence / exit fence;
          // only a proven pre-native failure is safe to abort.
          if (usesDurableOutbox) {
            clearGroupRolePreparationInFlight(pendingId);
          }
        } else {
          // ABORTED is the durable negative fact that prevents a surviving
          // authenticated PREPARED fact from being rediscovered as recoverable.
          // Establish it before retiring the ordinary owner; if abort cannot be
          // proven, leave that owner in place and fail closed.
          try {
            await _requireProtectedRoleAbort(protectedPreparation);
          } catch (error) {
            abortError = error;
          }
          if (abortError == null &&
              usesDurableOutbox &&
              !protectedAbortOwnsOrdinary) {
            try {
              await (removePending ?? removeGroupPendingBroadcast)(pendingId);
            } catch (error) {
              discardError = error;
            }
          }
          if (usesDurableOutbox) {
            clearGroupRolePreparationInFlight(pendingId);
          }
        }
        if (abortError != null) {
          throw StateError(
            'Role transition commit failed ($commitError) and its protected '
            'preparation could not be durably aborted ($abortError); the exact '
            'ordinary prepared row was retained',
          );
        }
        if (discardError != null) {
          throw StateError(
            'Role transition commit failed ($commitError) and its prepared row '
            'could not be removed ($discardError)',
          );
        }
        rethrow;
      }
      if (committed == null) {
        Object? abortError;
        final protectedAbortOwnsOrdinary =
            protectedPreparation?.abortRows.any(
              (row) => sameExactGroupPendingBroadcast(row, preparedPendingRow),
            ) ??
            false;
        try {
          await _requireProtectedRoleAbort(protectedPreparation);
        } catch (error) {
          abortError = error;
        }
        if (abortError == null &&
            usesDurableOutbox &&
            !protectedAbortOwnsOrdinary) {
          try {
            await (removePending ?? removeGroupPendingBroadcast)(pendingId);
          } catch (error) {
            clearGroupRolePreparationInFlight(pendingId);
            throw StateError(
              'No role transition was committed, its protected preparation was '
              'aborted, but its ordinary prepared row could not be removed '
              '($error)',
            );
          }
        }
        if (usesDurableOutbox) {
          clearGroupRolePreparationInFlight(pendingId);
        }
        if (abortError != null) {
          throw StateError(
            'No role transition was committed and its protected preparation could '
            'not be durably aborted ($abortError); the exact ordinary prepared row '
            'was retained',
          );
        }
        final current = await groupRepo.getMember(groupId, memberPeerId);
        return ChangeGroupMemberRoleAndBroadcastResult(
          outcome: ChangeGroupMemberRoleAndBroadcastOutcome.unchanged,
          updatedMember: current ?? proposedMember,
        );
      }
      if (!committed.eventAt.isAtSameMomentAs(eventAt) ||
          committed.eventId != sourceEventId) {
        if (usesDurableOutbox) {
          clearGroupRolePreparationInFlight(pendingId);
        }
        throw StateError('Committed role event did not match its signed event');
      }

      var protectedActivated = protectedPreparation == null;
      try {
        protectedActivated = await activateProtectedGroupAuthority(
          protectedPreparation,
          requireAllCustody: false,
        );
      } catch (error) {
        // The durable protected row remains retryable. The role transition is
        // already committed, so a transport failure cannot turn into a caller-
        // visible mutation failure that invites a conflicting retry.
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_ROLE_PROTECTED_ACTIVATION_DEFERRED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'memberPeerId': memberPeerId.length > 8
                ? memberPeerId.substring(0, 8)
                : memberPeerId,
            'error': error.toString(),
          },
        );
      }
      if (!protectedActivated) {
        if (usesDurableOutbox) {
          clearGroupRolePreparationInFlight(pendingId);
        }
        return ChangeGroupMemberRoleAndBroadcastResult(
          outcome: ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync,
          updatedMember: proposedMember,
          eventAt: eventAt,
          sourceEventId: sourceEventId,
        );
      }

      // Keep the ordinary row in PREPARED while protected activation verifies or
      // repairs the exact local projection and advances authenticated COMPLETE.
      // Otherwise a false/failed activation could expose the role transition via
      // the generic publish/inbox runner before protected recovery owns it.
      if (usesDurableOutbox) {
        try {
          await _enqueueAndVerifyPending(
            pendingRow,
            enqueuePending: enqueuePending,
            loadPending: loadPending,
          );
        } catch (_) {
          clearGroupRolePreparationInFlight(pendingId);
          return ChangeGroupMemberRoleAndBroadcastResult(
            outcome: ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync,
            updatedMember: proposedMember,
            eventAt: eventAt,
            sourceEventId: sourceEventId,
          );
        }
        clearGroupRolePreparationInFlight(pendingId);
      }

      Map<String, dynamic>? publishResult;
      try {
        final roleTimelineMessage = buildMemberRoleUpdatedTimelineMessage(
          groupId: groupId,
          updatedPeerId: proposedMember.peerId,
          updatedUsername: proposedMember.username,
          previousRole: targetMember.role,
          newRole: proposedMember.role,
          senderId: identity.peerId,
          senderUsername: identity.username,
          eventAt: eventAt,
        );
        await messageRepo?.saveMessage(roleTimelineMessage);

        publishResult = await callGroupPublish(
          bridge,
          groupId: groupId,
          text: sysText,
          senderPeerId: identity.peerId,
          senderPublicKey: identity.publicKey,
          senderPrivateKey: identity.privateKey,
          senderUsername: identity.username,
          senderDeviceId: senderBinding.deviceId,
          senderTransportPeerId: senderBinding.transportPeerId,
          senderDevicePublicKey: senderBinding.devicePublicKey,
          senderKeyPackageId: senderBinding.keyPackageId,
          messageId: sourceEventId,
        );
        if (publishResult['ok'] != true) {
          throw StateError('Role transition publish did not complete');
        }

        final inboxPayload = jsonEncode({
          'groupId': groupId,
          'senderId': identity.peerId,
          'senderUsername': identity.username,
          if (senderBinding.deviceId != null)
            'senderDeviceId': senderBinding.deviceId,
          if (senderBinding.transportPeerId != null)
            'transportPeerId': senderBinding.transportPeerId,
          'text': sysText,
          'timestamp': eventAt.toUtc().toIso8601String(),
          'messageId': sourceEventId,
        });
        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: inboxPayload,
          senderPeerId: identity.peerId,
          senderPublicKey: identity.publicKey,
          senderPrivateKey: identity.privateKey,
          senderDeviceId: senderBinding.deviceId,
          senderTransportPeerId: senderBinding.transportPeerId,
          senderKeyPackageId: senderBinding.keyPackageId,
          messageId: roleTimelineMessage.id,
          recipientPeerIds: recipients,
        );
        await callGroupInboxStore(
          bridge,
          groupId,
          replayEnvelope,
          recipientPeerIds: recipients,
          preserveRecipientPeerIds: true,
        );

        if (sendP2PMessage != null) {
          final directTargets = groupMembershipUpdateDirectTargets(
            members: proposedMembers,
            excludingPeerId: identity.peerId,
          );
          for (final target in directTargets) {
            unawaited(
              sendGroupMembershipUpdateDirect(
                sendP2PMessage: sendP2PMessage,
                recipientPeerId: target.deliveryPeerId,
                groupId: groupId,
                senderPeerId: identity.peerId,
                replayEnvelope: replayEnvelope,
                timestamp: eventAt,
                messageId: sourceEventId,
              ),
            );
          }
        }
      } catch (_) {
        if (!usesDurableOutbox) {
          await _enqueueAndVerifyPending(
            pendingRow,
            enqueuePending: enqueuePending,
            loadPending: loadPending,
          );
        }
        return ChangeGroupMemberRoleAndBroadcastResult(
          outcome: ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync,
          updatedMember: proposedMember,
          eventAt: eventAt,
          sourceEventId: sourceEventId,
          publishResult: publishResult,
        );
      }

      List<GroupPendingBroadcast> pendingAfterSuccess;
      try {
        if (usesDurableOutbox) {
          await (removePending ?? removeGroupPendingBroadcast)(pendingRow.id);
        }
        pendingAfterSuccess = await (loadPending ?? loadGroupPendingBroadcasts)(
          groupId,
        );
      } catch (_) {
        return ChangeGroupMemberRoleAndBroadcastResult(
          outcome: ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync,
          updatedMember: proposedMember,
          eventAt: eventAt,
          sourceEventId: sourceEventId,
          publishResult: publishResult,
        );
      }
      if (_containsExactRoleRow(pendingAfterSuccess, sourceEventId)) {
        return ChangeGroupMemberRoleAndBroadcastResult(
          outcome: ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync,
          updatedMember: proposedMember,
          eventAt: eventAt,
          sourceEventId: sourceEventId,
          publishResult: publishResult,
        );
      }
      return ChangeGroupMemberRoleAndBroadcastResult(
        outcome: ChangeGroupMemberRoleAndBroadcastOutcome.readyToLeave,
        updatedMember: proposedMember,
        eventAt: eventAt,
        sourceEventId: sourceEventId,
        publishResult: publishResult,
      );
    },
  );
});

Future<T> _runGroupRoleBroadcastActionLocked<T>(
  String groupId,
  Future<T> Function() action,
) async {
  final previous = _groupRoleBroadcastActionLocks[groupId];
  final gate = Completer<void>();
  final current = (previous ?? Future<void>.value())
      .catchError((_) {})
      .then((_) => gate.future);
  _groupRoleBroadcastActionLocks[groupId] = current;

  if (previous != null) {
    try {
      await previous;
    } catch (_) {
      // Completion of the prior action, not its outcome, releases this turn.
    }
  }
  try {
    return await action();
  } finally {
    if (!gate.isCompleted) gate.complete();
    if (identical(_groupRoleBroadcastActionLocks[groupId], current)) {
      _groupRoleBroadcastActionLocks.remove(groupId);
    }
  }
}

Future<bool> retryPendingGroupRoleTransition({
  required String groupId,
  required String sourceEventId,
  Future<int> Function(String groupId)? drain,
  Future<List<GroupPendingBroadcast>> Function(String groupId)? loadPending,
}) async {
  await (drain ?? drainGroupPendingBroadcastsForGroup)(groupId);
  final pending = await (loadPending ?? loadGroupPendingBroadcasts)(groupId);
  return !_containsExactRoleRow(pending, sourceEventId);
}

Future<bool> _isCurrentPromotionCandidate({
  required GroupRepository groupRepo,
  required GroupMessageRepository? messageRepo,
  required GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  required String groupId,
  required String selfPeerId,
  required String memberPeerId,
}) async {
  final current = await groupRepo.getMember(groupId, memberPeerId);
  if (current == null ||
      current.peerId == selfPeerId ||
      current.role == MemberRole.admin) {
    return false;
  }
  final joinedAt = await messageRepo?.getLatestSystemEventTimestampForTarget(
    groupId,
    eventType: 'member_joined',
    targetId: memberPeerId,
  );
  final removedAt = await messageRepo?.getLatestSystemEventTimestampForTarget(
    groupId,
    eventType: 'member_removed',
    targetId: memberPeerId,
  );
  final attempt = await inviteDeliveryAttemptRepo?.getAttempt(
    groupId: groupId,
    peerId: memberPeerId,
  );
  return hasCurrentGroupJoinEvidence(
    memberJoinedAt: joinedAt,
    memberRemovedAt: removedAt,
    inviteAttempt: attempt,
  );
}

Future<void> _enqueueAndVerifyPending(
  GroupPendingBroadcast pending, {
  Future<void> Function(GroupPendingBroadcast broadcast)? enqueuePending,
  Future<List<GroupPendingBroadcast>> Function(String groupId)? loadPending,
}) async {
  await (enqueuePending ?? enqueueGroupPendingBroadcast)(pending);
  final rows = await (loadPending ?? loadGroupPendingBroadcasts)(
    pending.groupId,
  );
  if (!rows.any((row) => _isExactPendingRow(row, pending))) {
    throw StateError('The exact durable role transition row was not stored');
  }
}

DateTime _nextPreparedRoleEventAt(GroupModel group) {
  final candidate = nextMembershipEventAt(group.lastMembershipEventAt);
  final previous = _lastPreparedRoleEventAtByGroup[group.id];
  final eventAt = previous != null && !candidate.isAfter(previous)
      ? previous.add(const Duration(microseconds: 1))
      : candidate;
  _lastPreparedRoleEventAtByGroup[group.id] = eventAt;
  return eventAt;
}

bool _isExactPendingRow(
  GroupPendingBroadcast actual,
  GroupPendingBroadcast expected,
) =>
    actual.id == expected.id &&
    actual.groupId == expected.groupId &&
    actual.kind == expected.kind &&
    actual.sysText == expected.sysText &&
    _sameRecipients(actual.recipientPeerIds, expected.recipientPeerIds) &&
    actual.eventAt.toUtc().isAtSameMomentAs(expected.eventAt.toUtc()) &&
    actual.sourceMessageId == expected.sourceMessageId;

bool _sameRecipients(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _containsExactRoleRow(
  Iterable<GroupPendingBroadcast> rows,
  String sourceEventId,
) => rows.any(
  (row) =>
      isPendingGroupMemberRoleBroadcastKind(row.kind) &&
      row.sourceMessageId == sourceEventId,
);

Future<void> _requireProtectedRoleAbort(
  ProtectedGroupAuthorityPreparation? preparation,
) async {
  if (!await cancelProtectedGroupAuthority(preparation)) {
    throw StateError('authenticated protected authority abort was refused');
  }
}
