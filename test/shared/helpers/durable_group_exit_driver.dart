import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/broadcast_voluntary_leave_use_case.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_exit_release_diagnostics.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

typedef LoadDurableGroupExitMessage =
    Future<GroupMessage?> Function(String messageId);
typedef RePushDurableGroupExitBroadcast =
    Future<bool> Function(GroupPendingBroadcast broadcast);
typedef AfterDurableGroupExitNoticeAttempt =
    Future<void> Function(GroupPendingBroadcast broadcast);

/// Immutable, runtime-derived proof that one coordinator action traversed the
/// durable runner rather than a manual broadcast/native/delete substitute.
class DurableGroupExitEvidence {
  const DurableGroupExitEvidence({
    required this.coordinatorStatus,
    required this.actionId,
    required this.sourceEventId,
    required this.pendingBroadcastId,
    required this.requestCount,
    required this.retryCount,
    required this.noticePrepareCount,
    required this.noticeAttemptCount,
    required this.rotationAttemptCount,
    required this.rotationOutcome,
    required this.nativeLeaveCount,
    required this.intentPresentAfter,
    required this.pendingBroadcastPresentAfter,
    required this.terminalIntentState,
  });

  final GroupExitIntentRequestStatus? coordinatorStatus;
  final String? actionId;
  final String? sourceEventId;
  final String? pendingBroadcastId;
  final int requestCount;
  final int retryCount;
  final int noticePrepareCount;
  final int noticeAttemptCount;
  final int rotationAttemptCount;
  final String? rotationOutcome;
  final int nativeLeaveCount;
  final bool intentPresentAfter;
  final bool pendingBroadcastPresentAfter;
  final GroupExitIntentState? terminalIntentState;

  Map<String, Object?> toJson() => <String, Object?>{
    'coordinatorStatus': coordinatorStatus?.name,
    'actionId': actionId,
    'sourceEventId': sourceEventId,
    'pendingBroadcastId': pendingBroadcastId,
    'requestCount': requestCount,
    'retryCount': retryCount,
    'noticePrepareCount': noticePrepareCount,
    'noticeAttemptCount': noticeAttemptCount,
    'rotationAttemptCount': rotationAttemptCount,
    'rotationOutcome': rotationOutcome,
    'nativeLeaveCount': nativeLeaveCount,
    'intentPresentAfter': intentPresentAfter,
    'pendingBroadcastPresentAfter': pendingBroadcastPresentAfter,
    'terminalIntentState': terminalIntentState?.name,
  };
}

class DurableGroupExitActionResult {
  const DurableGroupExitActionResult({
    required this.requestResult,
    required this.evidence,
  });

  final GroupExitIntentRequestResult requestResult;
  final DurableGroupExitEvidence evidence;
}

/// One production-shaped durable voluntary-exit composition with injected
/// storage and transport boundaries.
///
/// FFI host fixtures and real SQLCipher device stacks share this exact runner.
/// The wrappers below are also the sole source of phase counters and stable
/// action/source/pending identity, so a hand-written leave sequence cannot
/// fabricate successful driver evidence.
class DurableGroupExitDriver {
  DurableGroupExitDriver._({
    required this.intentRepository,
    required this.pendingRepository,
    required this.runner,
    required this.coordinator,
    required _MutableDurableGroupExitEvidence mutableEvidence,
  }) : _evidence = mutableEvidence;

  static DurableGroupExitDriver compose({
    required Bridge bridge,
    required GroupExitIntentRepository intentRepository,
    required GroupPendingBroadcastRepository pendingRepository,
    required GroupRepository groupRepository,
    required IdentityRepository identityRepository,
    required LoadDurableGroupExitMessage loadMessage,
    required RePushDurableGroupExitBroadcast rePushPendingBroadcast,
    required String Function() newId,
    required DateTime Function() now,
    GroupExitIntentRepository? coordinatorIntentRepository,
    Future<bool> Function(String peerId, String message)? sendP2PMessage,
    Future<bool> Function(String peerId, String message)?
    storeP2PMessageInInbox,
    AfterDurableGroupExitNoticeAttempt? afterNoticeAttempt,
    Future<void> Function(GroupExitIntent intent)? beforeNativeLeave,
  }) {
    final evidence = _MutableDurableGroupExitEvidence();
    final pendingRunner = GroupPendingBroadcastRunner(
      repository: pendingRepository,
      rePush: rePushPendingBroadcast,
    );

    final runner = GroupExitIntentRunner(
      intentRepository: intentRepository,
      pendingRepository: pendingRepository,
      pendingBroadcastRunner: pendingRunner,
      groupRepository: groupRepository,
      loadCurrentSelfPeerId: () async =>
          (await identityRepository.loadIdentity())?.peerId,
      prepareNotice:
          ({required intent, required sourceEventId, required eventAt}) async {
            evidence.observePrepare(intent, sourceEventId);
            final currentGroup = await groupRepository.getGroup(intent.groupId);
            if (currentGroup == null) {
              throw StateError('Group exit notice parent is unavailable.');
            }
            final result = await prepareVoluntaryLeaveNotice(
              bridge: bridge,
              groupRepo: groupRepository,
              group: currentGroup,
              identityRepo: identityRepository,
              expectedSelfPeerId: intent.selfPeerId,
              sourceEventId: sourceEventId,
              eventAt: eventAt,
            );
            final prepared = requirePreparedVoluntaryLeaveNotice(result);
            if (prepared.identity.peerId != intent.selfPeerId) {
              throw StateError(
                'Group exit notice identity does not own the intent.',
              );
            }
            evidence.timelineMessageId = prepared.timelineMessage.id;
            final pending = prepared.pendingBroadcast;
            return GroupExitPreparedNotice(
              timelineMessage: prepared.timelineMessage,
              pendingBroadcast: GroupPendingBroadcast(
                id: intent.pendingBroadcastId,
                groupId: pending.groupId,
                kind: pending.kind,
                sysText: pending.sysText,
                recipientPeerIds: pending.recipientPeerIds,
                eventAt: pending.eventAt,
                sourceMessageId: pending.sourceMessageId,
                createdAt: pending.createdAt,
                updatedAt: pending.updatedAt,
              ),
            );
          },
      attemptNotice: ({required intent, required pendingBroadcast}) async {
        evidence.observeNoticeAttempt(intent, pendingBroadcast);
        final identity = await identityRepository.loadIdentity();
        if (identity == null) {
          throw StateError('Group exit notice identity is unavailable.');
        }
        if (identity.peerId != intent.selfPeerId) {
          throw StateError('Group exit notice identity changed after prepare.');
        }
        final members = await groupRepository.getMembers(
          pendingBroadcast.groupId,
        );
        final selfMembers = members
            .where((member) => member.peerId == identity.peerId)
            .toList(growable: false);
        if (selfMembers.length != 1) {
          throw StateError(
            'Exact group exit sender membership is unavailable.',
          );
        }
        final remainingByPeerId = {
          for (final member in members)
            if (member.peerId != identity.peerId) member.peerId: member,
        };
        final remainingMembers = <GroupMember>[];
        for (final peerId in pendingBroadcast.recipientPeerIds) {
          final member = remainingByPeerId[peerId];
          if (member != null) remainingMembers.add(member);
        }
        final timelineIdentity = buildMemberRemovedTimelineMessage(
          groupId: pendingBroadcast.groupId,
          removedPeerId: identity.peerId,
          removedUsername: identity.username,
          senderId: identity.peerId,
          senderUsername: identity.username,
          eventAt: pendingBroadcast.eventAt,
        );
        final timelineMessage = await loadMessage(timelineIdentity.id);
        if (timelineMessage == null) {
          throw StateError(
            'Durable group exit timeline notice is unavailable.',
          );
        }
        final result = await attemptPreparedVoluntaryLeaveNotice(
          bridge: bridge,
          groupRepo: groupRepository,
          prepared: PreparedVoluntaryLeaveNotice(
            pendingBroadcast: pendingBroadcast,
            timelineMessage: timelineMessage,
            identity: identity,
            senderBinding: resolveGroupSenderDeviceBindingFromMember(
              member: selfMembers.single,
              senderPublicKey: identity.publicKey,
            ),
            remainingMembers: remainingMembers,
          ),
          expectedSelfPeerId: intent.selfPeerId,
        );
        if (result.canAdvance) {
          await afterNoticeAttempt?.call(pendingBroadcast);
        }
        return switch (result.classification) {
          VoluntaryLeaveNoticeAttemptClassification.delivered =>
            GroupExitNoticeAttemptDisposition.delivered,
          VoluntaryLeaveNoticeAttemptClassification.degraded =>
            GroupExitNoticeAttemptDisposition.degraded,
          VoluntaryLeaveNoticeAttemptClassification.retryable =>
            GroupExitNoticeAttemptDisposition.retryable,
        };
      },
      rotateKeys: (intent) async {
        evidence.observeRotationAttempt(intent);
        try {
          final rotation = await rotateVoluntaryLeaveGroupKeyBestEffort(
            bridge: bridge,
            groupRepo: groupRepository,
            groupId: intent.groupId,
            identityRepo: identityRepository,
            expectedSelfPeerId: intent.selfPeerId,
            sendP2PMessage: sendP2PMessage,
            storeP2PMessageInInbox: storeP2PMessageInInbox,
          );
          if (rotation.rotationDeferred) {
            evidence.rotationOutcome = 'deferred';
            throw const GroupExitRotationDeferred();
          }
          evidence.rotationOutcome = 'completed';
        } on GroupExitRotationDeferred {
          rethrow;
        } catch (_) {
          evidence.rotationOutcome = 'failed';
          rethrow;
        }
      },
      nativeLeave: (intent) async {
        evidence.observeNativeLeave(intent);
        await beforeNativeLeave?.call(intent);
        try {
          final identity = await identityRepository.loadIdentity();
          if (identity == null || identity.peerId != intent.selfPeerId) {
            throw StateError(
              'Group exit identity changed before native leave.',
            );
          }
        } catch (error, stackTrace) {
          throwGroupExitAuthorityFailure(error, stackTrace);
        }
        await runTypedGroupExitNativeLeave(
          () => callGroupLeave(bridge, intent.groupId),
        );
      },
      now: () => now().toUtc(),
    );
    final coordinator = GroupExitIntentCoordinator(
      intentRepository: coordinatorIntentRepository ?? intentRepository,
      pendingRepository: pendingRepository,
      pendingBroadcastRunner: pendingRunner,
      processor: runner,
      groupRepository: groupRepository,
      identityRepository: identityRepository,
      newId: newId,
      now: () => now().toUtc(),
    );
    return DurableGroupExitDriver._(
      intentRepository: intentRepository,
      pendingRepository: pendingRepository,
      runner: runner,
      coordinator: coordinator,
      mutableEvidence: evidence,
    );
  }

  final GroupExitIntentRepository intentRepository;
  final GroupPendingBroadcastRepository pendingRepository;
  final GroupExitIntentRunner runner;
  final GroupExitIntentCoordinator coordinator;
  final _MutableDurableGroupExitEvidence _evidence;

  int get noticePrepareCount => _evidence.noticePrepareCount;
  int get noticeAttemptCount => _evidence.noticeAttemptCount;
  int get rotationAttemptCount => _evidence.rotationAttemptCount;
  int get nativeLeaveCount => _evidence.nativeLeaveCount;
  String? get lastPreparedTimelineMessageId => _evidence.timelineMessageId;

  Future<DurableGroupExitActionResult> requestLeave(String groupId) async {
    _evidence.requestCount++;
    final result = await coordinator.requestLeave(groupId);
    return _completeAction(groupId, result);
  }

  Future<DurableGroupExitActionResult> retry(String groupId) async {
    _evidence.retryCount++;
    final result = await coordinator.retry(groupId);
    return _completeAction(groupId, result);
  }

  Future<DurableGroupExitActionResult> _completeAction(
    String groupId,
    GroupExitIntentRequestResult result,
  ) async {
    _evidence.coordinatorStatus = result.status;
    _evidence.observeResultIntent(result.intent);
    final evidence = await evidenceFor(groupId);
    return DurableGroupExitActionResult(
      requestResult: result,
      evidence: evidence,
    );
  }

  Future<DurableGroupExitEvidence> evidenceFor(String groupId) async {
    final terminalIntent = await intentRepository.forGroup(groupId);
    final pending = await pendingRepository.forGroup(groupId);
    final hasExitNotice = pending.any(
      (row) => row.kind == groupPendingBroadcastKindExitLeaveNotice,
    );
    return _evidence.snapshot(
      terminalIntent: terminalIntent,
      pendingBroadcastPresentAfter: hasExitNotice,
    );
  }
}

class _MutableDurableGroupExitEvidence {
  GroupExitIntentRequestStatus? coordinatorStatus;
  String? actionId;
  String? sourceEventId;
  String? pendingBroadcastId;
  int requestCount = 0;
  int retryCount = 0;
  int noticePrepareCount = 0;
  int noticeAttemptCount = 0;
  int rotationAttemptCount = 0;
  String? rotationOutcome;
  String? timelineMessageId;
  int nativeLeaveCount = 0;

  void observeResultIntent(GroupExitIntent? intent) {
    if (intent != null) _observeIntent(intent);
  }

  void observePrepare(GroupExitIntent intent, String sourceId) {
    noticePrepareCount++;
    _observeIntent(intent);
    _observeSource(sourceId);
  }

  void observeNoticeAttempt(
    GroupExitIntent intent,
    GroupPendingBroadcast pending,
  ) {
    noticeAttemptCount++;
    _observeIntent(intent);
    _observeSource(pending.sourceMessageId);
    if (pending.id != pendingBroadcastId) {
      throw StateError('Durable group exit pending identity changed.');
    }
  }

  void observeRotationAttempt(GroupExitIntent intent) {
    rotationAttemptCount++;
    _observeIntent(intent);
  }

  void observeNativeLeave(GroupExitIntent intent) {
    nativeLeaveCount++;
    _observeIntent(intent);
  }

  void _observeIntent(GroupExitIntent intent) {
    final existingActionId = actionId;
    if (existingActionId != null && existingActionId != intent.intentId) {
      throw StateError('Durable group exit action identity changed.');
    }
    final existingPendingId = pendingBroadcastId;
    if (existingPendingId != null &&
        existingPendingId != intent.pendingBroadcastId) {
      throw StateError('Durable group exit pending identity changed.');
    }
    final existingSourceId = sourceEventId;
    if (existingSourceId != null &&
        intent.sourceEventId != null &&
        existingSourceId != intent.sourceEventId) {
      throw StateError('Durable group exit source identity changed.');
    }
    actionId = intent.intentId;
    pendingBroadcastId = intent.pendingBroadcastId;
    _observeSource(intent.sourceEventId);
  }

  void _observeSource(String? sourceId) {
    if (sourceId == null) return;
    final existing = sourceEventId;
    if (existing != null && existing != sourceId) {
      throw StateError('Durable group exit source identity changed.');
    }
    sourceEventId = sourceId;
  }

  DurableGroupExitEvidence snapshot({
    required GroupExitIntent? terminalIntent,
    required bool pendingBroadcastPresentAfter,
  }) => DurableGroupExitEvidence(
    coordinatorStatus: coordinatorStatus,
    actionId: actionId,
    sourceEventId: sourceEventId,
    pendingBroadcastId: pendingBroadcastId,
    requestCount: requestCount,
    retryCount: retryCount,
    noticePrepareCount: noticePrepareCount,
    noticeAttemptCount: noticeAttemptCount,
    rotationAttemptCount: rotationAttemptCount,
    rotationOutcome: rotationOutcome,
    nativeLeaveCount: nativeLeaveCount,
    intentPresentAfter: terminalIntent != null,
    pendingBroadcastPresentAfter: pendingBroadcastPresentAfter,
    terminalIntentState: terminalIntent?.state,
  );
}
