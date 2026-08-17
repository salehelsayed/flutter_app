import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';

/// Result of sending an emoji reaction to a group message.
enum SendGroupReactionResult {
  /// Live publish was accepted and local/replay state was queued.
  ///
  /// This is not a remote delivery confirmation.
  success,

  /// Live publish failed or threw, but the reaction was durably staged in the
  /// replay outbox and optimistically persisted locally. The existing retry
  /// driver will re-drive it — it is NOT a hard drop. (INV-R1)
  queuedForRetry,
  groupNotFound,
  groupDissolved,
  messageNotFound,
  notMember,
  unauthorizedSenderKey,
  publishFailed,
}

/// Sends an emoji reaction to a group message via live publish plus replay outbox.
///
/// 1. Validates group exists and sender is a member
/// 2. Validates the target message exists
/// 3. Builds reaction payload and publishes via bridge
/// 4. Stages roster-wide replay custody
/// 5. Persists locally (optimistic)
///
/// Returns (result, MessageReaction?) — reaction is non-null when the local
/// optimistic state was queued. This is not a delivery receipt.
Future<(SendGroupReactionResult, MessageReaction?)> sendGroupReaction({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required ReactionRepository reactionRepo,
  required GroupReactionReplayOutboxRepository reactionReplayOutboxRepo,
  required String groupId,
  required String messageId,
  required String emoji,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  String Function()? transitionIdFactory,
  GroupContentAuthoringContext? groupContentAuthoring,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  DateTime? authoredAt,
}) async {
  final snapshot = await runGroupAuthorityPhase(
    groupId: groupId,
    action: () async {
      final group = await groupRepo.getGroup(groupId);
      final member = await groupRepo.getMember(groupId, senderPeerId);
      final resolution = member == null
          ? const (
              kind: GroupContentAuthoringResolutionKind.refuse,
              context: null,
            )
          : await resolveGroupContentAuthoring(
              resolverOwner: groupRepo,
              groupId: groupId,
              senderPeerId: senderPeerId,
              senderPublicKey: senderPublicKey,
              senderMember: member,
              explicitContext: groupContentAuthoring,
            );
      final strictDevice =
          resolution.kind == GroupContentAuthoringResolutionKind.strict &&
              member != null
          ? resolveStrictGroupReactionSenderDevice(
              member: member,
              senderPublicKey: senderPublicKey,
              context: resolution.context!,
            )
          : null;
      final strictMembers = strictDevice == null
          ? null
          : await groupRepo.getMembers(groupId);
      final recipients = strictDevice == null
          ? const <String>[]
          : await loadStrictGroupReactionRecipientPeerIds(
              groupRepo: groupRepo,
              groupId: groupId,
              senderTransportPeerId: strictDevice.transportPeerId,
              inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
              members: strictMembers,
            );
      final authorBindingUnique =
          resolution.kind != GroupContentAuthoringResolutionKind.strict ||
          (strictDevice != null &&
              hasUniqueStrictGroupContentAuthorBinding(
                members: strictMembers!,
                senderPeerId: senderPeerId,
                senderDeviceId: strictDevice.deviceId,
                senderTransportPeerId: strictDevice.transportPeerId,
                senderPublicKey: strictDevice.deviceSigningPublicKey,
              ));
      final target = await msgRepo.getMessage(messageId);
      final targetEligible =
          target != null &&
          msgRepo is GroupMessageStrictReactionTargetRepository &&
          await (msgRepo as GroupMessageStrictReactionTargetRepository)
              .isStrictReactionTargetEligible(target);
      return (
        group: group,
        member: member,
        resolution: resolution,
        recipients: recipients,
        targetEligible: targetEligible,
        authorBindingUnique: authorBindingUnique,
      );
    },
  );
  // Preserve the incumbent validation result ordering. A missing group/member
  // is not a signer-authority failure, and both conditions are terminal before
  // any crypto, local projection, or network effect.
  if (snapshot.group == null) {
    return (SendGroupReactionResult.groupNotFound, null);
  }
  if (snapshot.group!.isDissolved) {
    return (SendGroupReactionResult.groupDissolved, null);
  }
  if (snapshot.member == null) {
    return (SendGroupReactionResult.notMember, null);
  }
  final resolverAbsentLegacy = isResolverAbsentLegacyGroupContentAuthoring(
    owner: groupRepo,
    explicitContext: groupContentAuthoring,
  );
  if (snapshot.resolution.kind == GroupContentAuthoringResolutionKind.refuse ||
      (snapshot.member?.hasInitializedDeviceAuthority == true &&
          !resolverAbsentLegacy &&
          snapshot.resolution.kind !=
              GroupContentAuthoringResolutionKind.strict)) {
    return (SendGroupReactionResult.unauthorizedSenderKey, null);
  }
  if (snapshot.resolution.kind == GroupContentAuthoringResolutionKind.strict &&
      !snapshot.authorBindingUnique) {
    return (SendGroupReactionResult.unauthorizedSenderKey, null);
  }
  if (snapshot.resolution.kind == GroupContentAuthoringResolutionKind.strict &&
      !snapshot.targetEligible) {
    return (SendGroupReactionResult.messageNotFound, null);
  }
  return _sendGroupReaction(
    bridge: bridge,
    groupRepo: groupRepo,
    msgRepo: msgRepo,
    reactionRepo: reactionRepo,
    reactionReplayOutboxRepo: reactionReplayOutboxRepo,
    groupId: groupId,
    messageId: messageId,
    emoji: emoji,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderPrivateKey: senderPrivateKey,
    transitionIdFactory: transitionIdFactory,
    groupContentAuthoring: snapshot.resolution.context,
    authoringKind: snapshot.resolution.kind,
    frozenRecipientPeerIds: snapshot.recipients,
    explicitGroupContentAuthoring: groupContentAuthoring,
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
    authoredAt: authoredAt,
  );
}

Future<(SendGroupReactionResult, MessageReaction?)> _sendGroupReaction({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required ReactionRepository reactionRepo,
  required GroupReactionReplayOutboxRepository reactionReplayOutboxRepo,
  required String groupId,
  required String messageId,
  required String emoji,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  String Function()? transitionIdFactory,
  GroupContentAuthoringContext? groupContentAuthoring,
  required GroupContentAuthoringResolutionKind authoringKind,
  required List<String> frozenRecipientPeerIds,
  GroupContentAuthoringContext? explicitGroupContentAuthoring,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  DateTime? authoredAt,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REACTION_SEND_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
    },
  );

  // 1. Validate group exists
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_GROUP_NOT_FOUND',
      details: {},
    );
    return (SendGroupReactionResult.groupNotFound, null);
  }

  if (group.isDissolved) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_GROUP_DISSOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        if (group.dissolvedAt != null)
          'dissolvedAt': group.dissolvedAt!.toUtc().toIso8601String(),
      },
    );
    return (SendGroupReactionResult.groupDissolved, null);
  }

  // 2. Validate sender is a member (any member can react, even in announcement groups)
  final member = await groupRepo.getMember(groupId, senderPeerId);
  if (member == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_NOT_MEMBER',
      details: {},
    );
    return (SendGroupReactionResult.notMember, null);
  }
  final strictContext = groupContentAuthoring;
  final strictSelected =
      authoringKind == GroupContentAuthoringResolutionKind.strict;
  if (strictSelected && strictContext == null) {
    return (SendGroupReactionResult.unauthorizedSenderKey, null);
  }
  final selectedStrictContext = strictSelected ? strictContext! : null;
  final linkedCredential = strictSelected
      ? selectedStrictContext!.linkedTransportCredential
      : null;
  final validLinkedCredential =
      linkedCredential != null &&
      linkedCredential.state == LinkedTransportCredentialState.active &&
      linkedCredential.accountPeerId == senderPeerId;
  if (strictSelected &&
      (!selectedStrictContext!
              .directLinkedDeviceSelector
              .allowsLinkedDeviceAuthoring ||
          !selectedStrictContext.multiDeviceSyncEnabled ||
          selectedStrictContext.authorityVersion == null ||
          selectedStrictContext.inboxStore == null ||
          (selectedStrictContext.requireLinkedTransportCredential &&
              !validLinkedCredential))) {
    return (SendGroupReactionResult.unauthorizedSenderKey, null);
  }
  final signingPrivateKey = validLinkedCredential
      ? linkedCredential.transportPrivateKey
      : senderPrivateKey;
  final senderDevice = strictSelected
      ? resolveStrictGroupReactionSenderDevice(
          member: member,
          senderPublicKey: senderPublicKey,
          context: selectedStrictContext!,
        )
      : member.firstActiveDeviceForSigningKey(
          senderPublicKey,
          allowLegacyFallback: true,
        );
  if (senderDevice == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_UNAUTHORIZED_SENDER_KEY',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderPeerId.length > 8
            ? senderPeerId.substring(0, 8)
            : senderPeerId,
      },
    );
    return (SendGroupReactionResult.unauthorizedSenderKey, null);
  }

  // 3. Validate message exists
  final message = await msgRepo.getMessage(messageId);
  if (message == null || message.groupId != groupId) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_MSG_NOT_FOUND',
      details: {
        if (message != null) 'reason': 'message_group_mismatch',
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
      },
    );
    return (SendGroupReactionResult.messageNotFound, null);
  }

  if (strictSelected) {
    if (message.privateMediaPolicy.isPrivate ||
        message.media.isNotEmpty ||
        message.isForwarded ||
        message.quotedMessageId?.isNotEmpty == true ||
        message.text.trimLeft().startsWith(r'{"__sys":')) {
      return (SendGroupReactionResult.messageNotFound, null);
    }
    return sendStrictGroupReactionContent(
      bridge: bridge,
      groupRepo: groupRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: groupId,
      message: message,
      emoji: emoji,
      senderPeerId: senderPeerId,
      senderDevice: senderDevice,
      senderPrivateKey: signingPrivateKey,
      context: selectedStrictContext!,
      explicitContext: explicitGroupContentAuthoring,
      senderAccountPublicKey: senderPublicKey,
      messageRepository: msgRepo,
      frozenRecipientPeerIds: frozenRecipientPeerIds,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
      authoredAt: authoredAt ?? DateTime.now().toUtc(),
      action: GroupReactionPayload.actionAdd,
    );
  }

  if (authoringKind !=
          GroupContentAuthoringResolutionKind.legacyUninitialized ||
      !await _legacyReactionAuthorityStillUninitialized(
        groupRepo: groupRepo,
        groupId: groupId,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        expectedMessage: message,
        messageRepository: msgRepo,
        explicitContext: explicitGroupContentAuthoring,
      )) {
    return (SendGroupReactionResult.unauthorizedSenderKey, null);
  }

  // 4. Build reaction payload
  final reactionId = deterministicGroupAddReactionId(
    groupId: groupId,
    messageId: messageId,
    senderPeerId: senderPeerId,
    emoji: emoji,
  );
  final latestTransition = await reactionReplayOutboxRepo
      .getLatestEntryForTarget(
        groupId: groupId,
        messageId: messageId,
        senderPeerId: senderPeerId,
      );
  final currentReaction = await reactionRepo
      .getReactionForSenderIncludingRemoved(
        messageId: messageId,
        senderPeerId: senderPeerId,
      );
  final exactRetry =
      latestTransition != null &&
      latestTransition.action == GroupReactionPayload.actionAdd &&
      latestTransition.emoji == emoji &&
      currentReaction != null &&
      !currentReaction.isRemoved &&
      currentReaction.id == reactionId &&
      currentReaction.emoji == emoji;
  final timestamp = DateTime.now().toUtc().toIso8601String();
  final transitionId = exactRetry
      ? latestTransition.reactionId
      : _requiredTransitionId(
          (transitionIdFactory ?? _defaultGroupReactionTransitionId)(),
        );

  final payload = GroupReactionPayload(
    id: reactionId,
    messageId: messageId,
    emoji: emoji,
    action: GroupReactionPayload.actionAdd,
    senderPeerId: senderPeerId,
    timestamp: timestamp,
    eventId: transitionId,
  );

  // 5. Stage durable custody + relay store BEFORE publishing, so a live publish
  //    failure still leaves a retryable replay-outbox row (INV-R1/INV-R2). The
  //    reaction id is deterministic, so any later retry re-publish stays
  //    idempotent at the receiver (INV-R3).
  if (exactRetry) {
    unawaited(
      _attemptReactionInboxStore(
        bridge: bridge,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        reactionId: transitionId,
        inboxRetryPayload: latestTransition.inboxRetryPayload,
        staged: true,
      ),
    );
  } else {
    await _stageReactionInboxStore(
      bridge: bridge,
      groupRepo: groupRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: groupId,
      payload: payload,
      senderPublicKey: senderDevice.deviceSigningPublicKey,
      senderPrivateKey: senderPrivateKey,
      senderDevice: senderDevice,
      targetAuthorPeerId: message.senderPeerId,
      transitionId: transitionId,
    );
  }

  // 6. Persist locally (optimistic) regardless of the publish outcome.
  final reaction = payload.toMessageReaction();
  await reactionRepo.saveReaction(reaction);

  // 7. Attempt live publish (Go encrypts + signs). A failure downgrades the
  //    result to queuedForRetry but never discards the custody/optimistic
  //    state staged above — the wired layer keeps the emoji and the retry
  //    driver re-drives the durable row.
  var publishOk = false;
  try {
    final result = await callGroupPublishReaction(
      bridge,
      groupId: groupId,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      senderDeviceId: senderDevice.deviceId,
      senderTransportPeerId: senderDevice.transportPeerId,
      senderDevicePublicKey: senderDevice.deviceSigningPublicKey,
      senderKeyPackageId: senderDevice.keyPackageId,
      reactionPayload: payload.toInnerJson(),
    );

    if (result['ok'] == true) {
      publishOk = true;
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_SEND_PUBLISH_FAILED',
        details: {'errorCode': result['errorCode']},
      );
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_ERROR',
      details: {'error': e.toString()},
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REACTION_SEND_QUEUED',
    details: {
      'id': reactionId.substring(0, 8),
      'emoji': emoji,
      'deliveryMode': 'live_publish_replay_queued',
      'deliveryConfirmed': false,
      'localState': 'optimistic',
      'replayStatus': 'pending',
      'publishOk': publishOk,
    },
  );

  return (
    publishOk
        ? SendGroupReactionResult.success
        : SendGroupReactionResult.queuedForRetry,
    reaction,
  );
}

Future<(SendGroupReactionResult, MessageReaction?)>
sendStrictGroupReactionContent({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupReactionReplayOutboxRepository reactionReplayOutboxRepo,
  required String groupId,
  required GroupMessage message,
  required String emoji,
  required String senderPeerId,
  required GroupMemberDeviceIdentity senderDevice,
  required String senderPrivateKey,
  required GroupContentAuthoringContext context,
  GroupContentAuthoringContext? explicitContext,
  required String senderAccountPublicKey,
  GroupMessageRepository? messageRepository,
  List<String>? frozenRecipientPeerIds,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  required DateTime authoredAt,
  required String action,
}) async {
  if (action != GroupReactionPayload.actionAdd &&
      action != GroupReactionPayload.actionRemove) {
    return (SendGroupReactionResult.unauthorizedSenderKey, null);
  }
  final authority = context.authorityVersion;
  if (authority == null ||
      !validGroupContentAuthoringOrder(
        authority: authority,
        contentAt: authoredAt,
        contentEventId: buildGroupReactionTransitionId(
          groupId: groupId,
          messageId: message.id,
          logicalActorPeerId: senderPeerId,
          action: action,
          emoji: emoji,
          timestamp: authoredAt,
        ),
      )) {
    return (SendGroupReactionResult.unauthorizedSenderKey, null);
  }
  final timestamp = fixedGroupContentUtc(authoredAt);
  final transitionId = buildGroupReactionTransitionId(
    groupId: groupId,
    messageId: message.id,
    logicalActorPeerId: senderPeerId,
    action: action,
    emoji: emoji,
    timestamp: authoredAt,
  );
  final reactionId = deterministicGroupReactionStateId(
    groupId: groupId,
    messageId: message.id,
    logicalActorPeerId: senderPeerId,
  );
  final payload = GroupReactionPayload(
    id: reactionId,
    messageId: message.id,
    emoji: emoji,
    action: action,
    senderPeerId: senderPeerId,
    timestamp: timestamp,
    eventId: transitionId,
  );
  final recipients = frozenRecipientPeerIds == null
      ? await loadStrictGroupReactionRecipientPeerIds(
          groupRepo: groupRepo,
          groupId: groupId,
          senderTransportPeerId: senderDevice.transportPeerId,
          inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
        )
      : List<String>.unmodifiable(frozenRecipientPeerIds);
  final replayEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    payloadType: groupOfflineReplayPayloadTypeReaction,
    plaintext: payload.toInnerJson(),
    senderPeerId: senderPeerId,
    senderPublicKey: senderDevice.deviceSigningPublicKey,
    senderPrivateKey: senderPrivateKey,
    messageId: transitionId,
    senderDeviceId: senderDevice.deviceId,
    senderTransportPeerId: senderDevice.transportPeerId,
    senderKeyPackageId: senderDevice.keyPackageId,
    recipientPeerIds: recipients,
    contentAuthorityVersion: context.authorityVersion!,
    contentEventId: transitionId,
    reactionNotificationExtension: GroupReactionNotificationExtensionInput(
      transitionId: transitionId,
      action: action,
      targetMessageId: message.id,
      reactorPeerId: senderPeerId,
      reactorTransportPeerId: senderDevice.transportPeerId,
      notificationRecipientTransportPeerIds: const <String>[],
    ),
  );
  final retryPayload = recipients.isEmpty
      ? null
      : jsonEncode(<String, Object?>{
          'groupId': groupId,
          'message': replayEnvelope,
          'custodyContract': ackOrExpiryInboxCustodyContract,
          'custodyKind': groupContentCustodyKind,
          'recipientPeerIds': recipients,
        });
  final stagedAt = timestamp;
  final staged = GroupReactionReplayOutboxEntry(
    reactionId: transitionId,
    groupId: groupId,
    messageId: message.id,
    senderPeerId: senderPeerId,
    emoji: emoji,
    action: action,
    inboxRetryPayload: retryPayload ?? '',
    deliveryStatus: recipients.isEmpty
        ? GroupReactionReplayOutboxStatus.stored
        : GroupReactionReplayOutboxStatus.pending,
    createdAt: stagedAt,
    updatedAt: stagedAt,
  );
  final reaction = MessageReaction(
    id: payload.id,
    messageId: payload.messageId,
    emoji: payload.emoji,
    senderPeerId: payload.senderPeerId,
    timestamp: timestamp,
    createdAt: timestamp,
    removedAt: action == GroupReactionPayload.actionRemove ? timestamp : null,
  );
  final eventPayload = buildLocalProtectedGroupContentEventPayload(
    replayEnvelope: replayEnvelope,
    payload: Map<String, Object?>.from(
      jsonDecode(payload.toInnerJson()) as Map<String, dynamic>,
    ),
  );
  final sourceEventId = localProtectedGroupReactionSourceEventId(transitionId);
  Future<bool> authorityMatchesAssumingPhase() =>
      _strictReactionAuthorityMatchesAssumingPhase(
        groupRepo: groupRepo,
        messageRepository: messageRepository,
        groupId: groupId,
        message: message,
        senderPeerId: senderPeerId,
        senderAccountPublicKey: senderAccountPublicKey,
        senderDevice: senderDevice,
        expectedRecipients: recipients,
        expectedContext: context,
        explicitContext: explicitContext,
        inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
      );
  Future<bool> currentAuthorityMatches() => runGroupAuthorityPhase(
    groupId: groupId,
    action: authorityMatchesAssumingPhase,
  );
  Future<bool> commitIfAuthorityMatches(Future<bool> Function() mutation) =>
      runGroupAuthorityPhase(
        groupId: groupId,
        action: () async {
          if (!await authorityMatchesAssumingPhase()) return false;
          return mutation();
        },
      );
  final stagedUnderCurrentAuthority = await runGroupAuthorityPhase(
    groupId: groupId,
    action: () async {
      if (!await authorityMatchesAssumingPhase()) {
        return false;
      }
      if (recipients.isEmpty) {
        if (reactionReplayOutboxRepo
            is! GroupReactionStrictLocalTerminalRepository) {
          return false;
        }
        return (reactionReplayOutboxRepo
                as GroupReactionStrictLocalTerminalRepository)
            .stageAndCompleteStrictLocalContent(
              staged,
              reactionRow: reaction.toMap(),
              action: payload.action,
              transitionId: transitionId,
              sourcePeerId: senderPeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: timestamp,
              eventPayload: eventPayload,
            );
      }
      if (reactionReplayOutboxRepo is! GroupReactionStrictPreparedRepository) {
        return false;
      }
      return (reactionReplayOutboxRepo as GroupReactionStrictPreparedRepository)
          .stageStrictContentPrepared(
            staged,
            sourcePeerId: senderPeerId,
            sourceEventId: localPreparedProtectedGroupReactionSourceEventId(
              transitionId,
            ),
            sourceTimestamp: timestamp,
            preparedEventPayload:
                buildLocalProtectedGroupContentPreparedEventPayload(
                  eventPayload: eventPayload,
                  ownerKind: 'group_reaction',
                  ownerId: transitionId,
                  ownerStatus: staged.deliveryStatus,
                  inboxRetryPayload: staged.inboxRetryPayload,
                ),
          );
    },
  );
  if (!stagedUnderCurrentAuthority) {
    return (SendGroupReactionResult.unauthorizedSenderKey, null);
  }
  if (recipients.isEmpty) {
    return (SendGroupReactionResult.success, reaction);
  }
  final completed = await _driveStrictReactionCustody(
    repository: reactionReplayOutboxRepo,
    store: context.inboxStore!,
    expected: staged,
    reaction: reaction,
    transitionId: transitionId,
    sourcePeerId: senderPeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: timestamp,
    eventPayload: eventPayload,
    currentAuthorityMatches: currentAuthorityMatches,
    commitIfAuthorityMatches: commitIfAuthorityMatches,
  );
  if (completed) {
    return (SendGroupReactionResult.success, reaction);
  }
  final exactPendingOwner = await _hasExactPendingStrictReactionOwner(
    repository: reactionReplayOutboxRepo,
    expected: staged,
  );
  return (
    exactPendingOwner
        ? SendGroupReactionResult.queuedForRetry
        : SendGroupReactionResult.unauthorizedSenderKey,
    null,
  );
}

Future<bool> _hasExactPendingStrictReactionOwner({
  required GroupReactionReplayOutboxRepository repository,
  required GroupReactionReplayOutboxEntry expected,
}) async {
  try {
    final current = await repository.getEntry(expected.reactionId);
    if (current == null ||
        current.reactionId != expected.reactionId ||
        current.groupId != expected.groupId ||
        current.messageId != expected.messageId ||
        current.senderPeerId != expected.senderPeerId ||
        current.emoji != expected.emoji ||
        current.action != expected.action ||
        current.createdAt != expected.createdAt ||
        current.deliveryStatus != GroupReactionReplayOutboxStatus.pending ||
        current.lastError != null) {
      return false;
    }
    final initial = GroupContentRetryPayload.decode(expected.inboxRetryPayload);
    final pending = GroupContentRetryPayload.decode(current.inboxRetryPayload);
    return pending.groupId == initial.groupId &&
        pending.message == initial.message &&
        pending.contentEventId == expected.reactionId &&
        pending.logicalSenderPeerId == expected.senderPeerId &&
        _sameExactStrings(
          pending.fullRecipientPeerIds,
          initial.fullRecipientPeerIds,
        ) &&
        pending.pendingRecipientPeerIds.isNotEmpty;
  } catch (_) {
    return false;
  }
}

Future<bool> _strictReactionAuthorityMatchesAssumingPhase({
  required GroupRepository groupRepo,
  required GroupMessageRepository? messageRepository,
  required String groupId,
  required GroupMessage message,
  required String senderPeerId,
  required String senderAccountPublicKey,
  required GroupMemberDeviceIdentity senderDevice,
  required List<String> expectedRecipients,
  required GroupContentAuthoringContext expectedContext,
  required GroupContentAuthoringContext? explicitContext,
  required GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
}) async {
  final group = await groupRepo.getGroup(groupId);
  final sender = await groupRepo.getMember(groupId, senderPeerId);
  final target = messageRepository == null
      ? message
      : await messageRepository.getMessage(message.id);
  final key = await groupRepo.getLatestKey(groupId);
  if (group == null ||
      group.selfRemovedAt != null ||
      group.isDissolved ||
      sender == null ||
      target == null ||
      target.groupId != groupId ||
      target.privateMediaPolicy.isPrivate ||
      target.media.isNotEmpty ||
      target.isForwarded ||
      target.quotedMessageId?.isNotEmpty == true ||
      target.text.trimLeft().startsWith(r'{"__sys":') ||
      (messageRepository != null &&
          (messageRepository is! GroupMessageStrictReactionTargetRepository ||
              !await (messageRepository
                      as GroupMessageStrictReactionTargetRepository)
                  .isStrictReactionTargetEligible(target))) ||
      key?.keyGeneration != expectedContext.authorityVersion?.keyEpoch) {
    return false;
  }
  final resolution = await resolveGroupContentAuthoring(
    resolverOwner: groupRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
    senderPublicKey: senderAccountPublicKey,
    senderMember: sender,
    senderDeviceId: senderDevice.deviceId,
    senderTransportPeerId: senderDevice.transportPeerId,
    explicitContext: explicitContext,
  );
  if (resolution.kind != GroupContentAuthoringResolutionKind.strict ||
      resolution.context == null ||
      !sameGroupContentAuthoringContext(expectedContext, resolution.context!)) {
    return false;
  }
  final currentDevice = sender.findDeviceById(senderDevice.deviceId);
  if (currentDevice == null ||
      currentDevice.transportPeerId != senderDevice.transportPeerId ||
      currentDevice.deviceSigningPublicKey !=
          senderDevice.deviceSigningPublicKey) {
    return false;
  }
  final currentMembers = await groupRepo.getMembers(groupId);
  if (!hasUniqueStrictGroupContentAuthorBinding(
    members: currentMembers,
    senderPeerId: senderPeerId,
    senderDeviceId: senderDevice.deviceId,
    senderTransportPeerId: senderDevice.transportPeerId,
    senderPublicKey: senderDevice.deviceSigningPublicKey,
  )) {
    return false;
  }
  final currentRecipients = await loadStrictGroupReactionRecipientPeerIds(
    groupRepo: groupRepo,
    groupId: groupId,
    senderTransportPeerId: senderDevice.transportPeerId,
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
    members: currentMembers,
  );
  return _sameExactStrings(expectedRecipients, currentRecipients);
}

/// Revalidates a persisted strict reaction before retrying relay custody.
/// Callers must hold the keyed group authority phase.
Future<bool> strictGroupReactionAuthorityMatchesAssumingPhase({
  required GroupRepository groupRepo,
  required GroupMessageRepository messageRepository,
  required String groupId,
  required String messageId,
  required String logicalSenderPeerId,
  required String senderAccountPublicKey,
  required String senderDeviceId,
  required String senderTransportPeerId,
  required String senderDevicePublicKey,
  required List<String> expectedRecipientPeerIds,
  required GroupContentAuthorityVersion expectedAuthority,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
}) async {
  final group = await groupRepo.getGroup(groupId);
  final sender = await groupRepo.getMember(groupId, logicalSenderPeerId);
  final target = await messageRepository.getMessage(messageId);
  final key = await groupRepo.getLatestKey(groupId);
  if (group == null ||
      group.selfRemovedAt != null ||
      group.isDissolved ||
      sender == null ||
      target == null ||
      target.groupId != groupId ||
      key?.keyGeneration != expectedAuthority.keyEpoch ||
      messageRepository is! GroupMessageStrictReactionTargetRepository ||
      !await (messageRepository as GroupMessageStrictReactionTargetRepository)
          .isStrictReactionTargetEligible(target)) {
    return false;
  }
  final resolution = await resolveGroupContentAuthoring(
    resolverOwner: groupRepo,
    groupId: groupId,
    senderPeerId: logicalSenderPeerId,
    senderPublicKey: senderAccountPublicKey,
    senderMember: sender,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
  );
  final device = sender.findDeviceById(senderDeviceId);
  if (resolution.kind != GroupContentAuthoringResolutionKind.strict ||
      resolution.context == null ||
      !sameGroupContentAuthorityVersion(
        expectedAuthority,
        resolution.context!.authorityVersion,
      ) ||
      device == null ||
      device.transportPeerId != senderTransportPeerId ||
      device.deviceSigningPublicKey != senderDevicePublicKey) {
    return false;
  }
  final currentMembers = await groupRepo.getMembers(groupId);
  if (!hasUniqueStrictGroupContentAuthorBinding(
    members: currentMembers,
    senderPeerId: logicalSenderPeerId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderPublicKey: senderDevicePublicKey,
  )) {
    return false;
  }
  final recipients = await loadStrictGroupReactionRecipientPeerIds(
    groupRepo: groupRepo,
    groupId: groupId,
    senderTransportPeerId: senderTransportPeerId,
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
    members: currentMembers,
  );
  return _sameExactStrings(expectedRecipientPeerIds, recipients);
}

bool _sameExactStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Future<List<String>> loadStrictGroupReactionRecipientPeerIds({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderTransportPeerId,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  List<GroupMember>? members,
}) async {
  final inviteStatuses = inviteDeliveryAttemptRepo == null
      ? const <String, GroupInviteDeliveryStatus>{}
      : await inviteDeliveryAttemptRepo.getStatusesForGroupMembers(groupId);
  final result = <String>{};
  final transportClaims = <String, int>{};
  for (final member in members ?? await groupRepo.getMembers(groupId)) {
    if (member.peerId.trim().isEmpty ||
        isPersistedNonJoinedGroupInviteStatus(
          inviteStatuses[member.peerId.trim()],
        )) {
      continue;
    }
    for (final device in member.activeDevicesWithLegacyFallback()) {
      final deviceId = device.deviceId.trim();
      final transport = device.transportPeerId.trim();
      final signingKey = device.deviceSigningPublicKey.trim();
      // Content replay is already group-encrypted, so a physical recipient
      // needs an active transport/signing identity but not key-package/ML-KEM
      // material. Requiring the latter drops otherwise eligible same-account
      // siblings from the frozen custody ACL.
      if (deviceId.isNotEmpty &&
          transport.isNotEmpty &&
          signingKey.isNotEmpty &&
          transport != senderTransportPeerId) {
        transportClaims.update(
          transport,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }
  result.addAll(
    transportClaims.entries
        .where((entry) => entry.value == 1)
        .map((entry) => entry.key),
  );
  return result.toList()..sort();
}

GroupMemberDeviceIdentity? resolveStrictGroupReactionSenderDevice({
  required GroupMember member,
  required String senderPublicKey,
  required GroupContentAuthoringContext context,
}) {
  final linked = context.linkedTransportCredential;
  final validLinked =
      linked != null &&
      linked.state == LinkedTransportCredentialState.active &&
      linked.accountPeerId == member.peerId;
  if (validLinked) {
    final exact = member.findDeviceById(linked.deviceId);
    return exact != null &&
            exact.transportPeerId == linked.transportPeerId &&
            exact.deviceSigningPublicKey == linked.transportPublicKey
        ? exact
        : null;
  }
  final boundDeviceId = context.authoringDeviceId?.trim();
  final boundTransportPeerId = context.authoringTransportPeerId?.trim();
  final boundPublicKey = context.authoringPublicKey?.trim();
  final hasAnyProductionBinding =
      boundDeviceId?.isNotEmpty == true ||
      boundTransportPeerId?.isNotEmpty == true ||
      boundPublicKey?.isNotEmpty == true;
  if (hasAnyProductionBinding) {
    if (boundDeviceId == null ||
        boundDeviceId.isEmpty ||
        boundTransportPeerId == null ||
        boundTransportPeerId.isEmpty ||
        boundPublicKey == null ||
        boundPublicKey.isEmpty) {
      return null;
    }
    final exact = member.findDeviceById(boundDeviceId);
    return exact != null &&
            exact.transportPeerId == boundTransportPeerId &&
            exact.deviceSigningPublicKey == boundPublicKey &&
            boundPublicKey == senderPublicKey
        ? exact
        : null;
  }
  return member.firstActiveDeviceForSigningKey(
    senderPublicKey,
    allowLegacyFallback: true,
  );
}

Future<bool> _legacyReactionAuthorityStillUninitialized({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderPeerId,
  required String senderPublicKey,
  required GroupMessage expectedMessage,
  required GroupMessageRepository messageRepository,
  required GroupContentAuthoringContext? explicitContext,
}) {
  return runGroupAuthorityPhase(
    groupId: groupId,
    action: () async {
      final group = await groupRepo.getGroup(groupId);
      final sender = await groupRepo.getMember(groupId, senderPeerId);
      final message = await messageRepository.getMessage(expectedMessage.id);
      final resolverAbsentLegacy = isResolverAbsentLegacyGroupContentAuthoring(
        owner: groupRepo,
        explicitContext: explicitContext,
      );
      if (group == null ||
          group.selfRemovedAt != null ||
          group.isDissolved ||
          sender == null ||
          (sender.hasInitializedDeviceAuthority && !resolverAbsentLegacy) ||
          message == null ||
          message.groupId != groupId ||
          message.senderPeerId != expectedMessage.senderPeerId ||
          message.timestamp.toUtc() != expectedMessage.timestamp.toUtc()) {
        return false;
      }
      final resolution = await resolveGroupContentAuthoring(
        resolverOwner: groupRepo,
        groupId: groupId,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        senderMember: sender,
        explicitContext: explicitContext,
      );
      return resolution.kind ==
          GroupContentAuthoringResolutionKind.legacyUninitialized;
    },
  );
}

Future<bool> _driveStrictReactionCustody({
  required GroupReactionReplayOutboxRepository repository,
  required AckOrExpiryInboxStore store,
  required GroupReactionReplayOutboxEntry expected,
  required MessageReaction reaction,
  required String transitionId,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
  required Future<bool> Function() currentAuthorityMatches,
  required Future<bool> Function(Future<bool> Function() mutation)
  commitIfAuthorityMatches,
}) async {
  if (repository is! GroupReactionReplayPayloadCasRepository ||
      repository is! GroupReactionStrictContentCompletionRepository) {
    return false;
  }
  final casRepository = repository as GroupReactionReplayPayloadCasRepository;
  final completionRepository =
      repository as GroupReactionStrictContentCompletionRepository;
  final initial = GroupContentRetryPayload.decode(expected.inboxRetryPayload);
  for (final recipient in initial.pendingRecipientPeerIds) {
    if (!await currentAuthorityMatches()) return false;
    final current = await repository.getEntry(expected.reactionId);
    if (current == null) return false;
    final decoded = GroupContentRetryPayload.decode(current.inboxRetryPayload);
    try {
      await storeGroupContentRetryRecipient(
        store: store,
        inboxRetryPayload: current.inboxRetryPayload,
        recipientPeerId: recipient,
      );
    } catch (_) {
      continue;
    }
    if (decoded.pendingRecipientPeerIds.length == 1) {
      return commitIfAuthorityMatches(
        () => completionRepository.completeStrictContentIfExact(
          current,
          reactionRow: reaction.toMap(),
          action: current.action,
          transitionId: transitionId,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
        ),
      );
    }
    final survivors = decoded.pendingRecipientPeerIds
        .where((candidate) => candidate != recipient)
        .toList(growable: false);
    if (!await commitIfAuthorityMatches(
      () => casRepository.replaceInboxRetryPayloadIfExact(
        current,
        decoded.encodeWithPending(survivors),
      ),
    )) {
      return false;
    }
  }
  return false;
}

String deterministicGroupAddReactionId({
  required String groupId,
  required String messageId,
  required String senderPeerId,
  required String emoji,
}) {
  final canonical = jsonEncode({
    'action': GroupReactionPayload.actionAdd,
    'emoji': emoji,
    'groupId': groupId,
    'messageId': messageId,
    'senderPeerId': senderPeerId,
  });
  final digest = sha256.convert(utf8.encode(canonical)).toString();
  return 'group-reaction-add-${digest.substring(0, 32)}';
}

String _defaultGroupReactionTransitionId() =>
    'group-reaction-event-${const Uuid().v4()}';

String _requiredTransitionId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, 'transitionId', 'must not be empty');
  }
  return normalized;
}

/// Wraps inbox store in try/catch so failures don't propagate.
Future<void> _stageReactionInboxStore({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupReactionReplayOutboxRepository reactionReplayOutboxRepo,
  required String groupId,
  required GroupReactionPayload payload,
  required String senderPublicKey,
  required String senderPrivateKey,
  required GroupMemberDeviceIdentity senderDevice,
  required String targetAuthorPeerId,
  required String transitionId,
}) async {
  // Plan 319: stage a rescuable needs-build row BEFORE any throwing build
  // step. A throw below used to abandon custody permanently — no row existed
  // for the retriers to rescue, while the local reaction and the live publish
  // proceeded as if replay were queued.
  final stagedAtIso = DateTime.now().toUtc().toIso8601String();
  final needsBuildEntry = GroupReactionReplayOutboxEntry(
    reactionId: transitionId,
    groupId: groupId,
    messageId: payload.messageId,
    senderPeerId: payload.senderPeerId,
    emoji: payload.emoji,
    action: payload.action,
    inboxRetryPayload: '',
    deliveryStatus: GroupReactionReplayOutboxStatus.needsBuild,
    createdAt: stagedAtIso,
    updatedAt: stagedAtIso,
  );
  var needsBuildStaged = false;
  try {
    needsBuildStaged = await reactionReplayOutboxRepo.saveEntry(
      needsBuildEntry,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_OUTBOX_STAGE_FAILED',
      details: {'error': e.toString(), 'phase': 'needs_build'},
    );
  }
  if (!needsBuildStaged) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_OUTBOX_STAGE_SKIPPED_PARENT_GONE',
      details: {'reactionId': transitionId},
    );
  }

  late final String inboxRetryPayload;
  try {
    final recipients = await resolveGroupReactionRecipientsForRebuild(
      groupRepo: groupRepo,
      groupId: groupId,
      senderTransportPeerId: senderDevice.transportPeerId,
      reactorPeerId: payload.senderPeerId,
      targetAuthorPeerId: targetAuthorPeerId,
    );
    inboxRetryPayload = await buildGroupOfflineReplayInboxRetryPayload(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      payloadType: groupOfflineReplayPayloadTypeReaction,
      plaintext: payload.toInnerJson(),
      senderPeerId: payload.senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      messageId: payload.id,
      senderDeviceId: senderDevice.deviceId,
      senderTransportPeerId: senderDevice.transportPeerId,
      senderKeyPackageId: senderDevice.keyPackageId,
      recipientPeerIds: recipients.replayRecipientTransportPeerIds,
      reactionNotificationExtension: GroupReactionNotificationExtensionInput(
        transitionId: transitionId,
        action: payload.action,
        targetMessageId: payload.messageId,
        reactorPeerId: payload.senderPeerId,
        reactorTransportPeerId: senderDevice.transportPeerId,
        notificationRecipientTransportPeerIds:
            recipients.notificationRecipientTransportPeerIds,
      ),
    );
  } catch (e) {
    // The needs-build row staged above survives: the retrier rebuilds the
    // payload from its identity fields and stores it.
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_OUTBOX_STAGE_FAILED',
      details: {'error': e.toString(), 'phase': 'build'},
    );
    return;
  }

  var staged = false;
  if (needsBuildStaged) {
    try {
      staged = await reactionReplayOutboxRepo.attachBuiltPayload(
        reactionId: transitionId,
        inboxRetryPayload: inboxRetryPayload,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_OUTBOX_STAGE_FAILED',
        details: {'error': e.toString(), 'phase': 'attach'},
      );
    }
  }

  unawaited(
    _attemptReactionInboxStore(
      bridge: bridge,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      reactionId: transitionId,
      inboxRetryPayload: inboxRetryPayload,
      staged: staged,
    ),
  );
}

({
  List<String> replayRecipientTransportPeerIds,
  List<String> notificationRecipientTransportPeerIds,
})
_reactionRecipientsFromMembers({
  required List<GroupMember> members,
  required String senderTransportPeerId,
  required String reactorPeerId,
  required String targetAuthorPeerId,
  required bool allowAuthorFallback,
}) {
  final replayRecipients = <String>{};
  for (final member in members) {
    for (final device in member.activeDevicesWithLegacyFallback()) {
      final transportPeerId = device.transportPeerId.trim();
      if (transportPeerId.isEmpty ||
          transportPeerId == senderTransportPeerId.trim()) {
        continue;
      }
      replayRecipients.add(transportPeerId);
    }
  }
  final notificationRecipients = <String>{};
  if (reactorPeerId != targetAuthorPeerId) {
    for (final member in members) {
      if (member.peerId != targetAuthorPeerId) continue;
      for (final device in member.activeDevicesWithLegacyFallback()) {
        final transportPeerId = device.transportPeerId.trim();
        if (replayRecipients.contains(transportPeerId)) {
          notificationRecipients.add(transportPeerId);
        }
      }
    }
    if (allowAuthorFallback) {
      final authorTransportPeerId = targetAuthorPeerId.trim();
      if (authorTransportPeerId.isNotEmpty &&
          authorTransportPeerId != senderTransportPeerId.trim()) {
        replayRecipients.add(authorTransportPeerId);
        notificationRecipients.add(authorTransportPeerId);
      }
    }
  }
  final sortedReplay = replayRecipients.toList()..sort();
  final sortedNotification = notificationRecipients.toList()..sort();
  return (
    replayRecipientTransportPeerIds: sortedReplay,
    notificationRecipientTransportPeerIds: sortedNotification,
  );
}

Future<
  ({
    List<String> replayRecipientTransportPeerIds,
    List<String> notificationRecipientTransportPeerIds,
  })
>
resolveGroupReactionRecipientsForRebuild({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderTransportPeerId,
  required String reactorPeerId,
  required String targetAuthorPeerId,
}) async {
  final members = await groupRepo.getMembers(groupId);
  var allowAuthorFallback = false;
  if (reactorPeerId != targetAuthorPeerId &&
      !members.any((member) => member.peerId == targetAuthorPeerId)) {
    final removedSnapshotRepo =
        groupRepo is RemovedGroupMemberSnapshotRepository
        ? groupRepo as RemovedGroupMemberSnapshotRepository
        : null;
    final removedAuthor =
        removedSnapshotRepo != null &&
        await removedSnapshotRepo.getRemovedMemberSnapshot(
              groupId,
              targetAuthorPeerId,
            ) !=
            null;
    final authorTransportPeerId = targetAuthorPeerId.trim();
    allowAuthorFallback =
        !removedAuthor &&
        authorTransportPeerId.isNotEmpty &&
        authorTransportPeerId != senderTransportPeerId.trim();
  }
  if (allowAuthorFallback) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_NOMINATION_AUTHOR_FALLBACK',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
  }
  return _reactionRecipientsFromMembers(
    members: members,
    senderTransportPeerId: senderTransportPeerId,
    reactorPeerId: reactorPeerId,
    targetAuthorPeerId: targetAuthorPeerId,
    allowAuthorFallback: allowAuthorFallback,
  );
}

bool _hasNoReactionInboxStoreRecipients(String inboxRetryPayload) {
  try {
    final decoded = jsonDecode(inboxRetryPayload);
    if (decoded is! Map) return false;
    if (!decoded.containsKey('recipientPeerIds')) return true;
    final recipients = decoded['recipientPeerIds'];
    return recipients == null || (recipients is List && recipients.isEmpty);
  } catch (_) {
    return false;
  }
}

Future<void> _attemptReactionInboxStore({
  required Bridge bridge,
  required GroupReactionReplayOutboxRepository reactionReplayOutboxRepo,
  required String reactionId,
  required String inboxRetryPayload,
  required bool staged,
}) async {
  if (_hasNoReactionInboxStoreRecipients(inboxRetryPayload)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_CUSTODY_UNROUTABLE',
      details: {
        'reactionId': reactionId.length > 8
            ? reactionId.substring(0, 8)
            : reactionId,
        'reason': 'empty_recipients',
      },
    );
    if (staged) {
      await reactionReplayOutboxRepo.updateEntryStatus(
        reactionId,
        deliveryStatus: GroupReactionReplayOutboxStatus.failed,
        lastError: 'custody_unroutable_empty_recipients',
      );
    }
    return;
  }
  try {
    await storeGroupOfflineReplayFromRetryPayload(
      bridge: bridge,
      inboxRetryPayload: inboxRetryPayload,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_INBOX_STORE_FAILED',
      details: {'error': e.toString()},
    );
    if (staged) {
      await reactionReplayOutboxRepo.updateEntryStatus(
        reactionId,
        deliveryStatus: GroupReactionReplayOutboxStatus.failed,
        lastError: e.toString(),
      );
    }
    return;
  }

  if (!staged) return;

  try {
    await reactionReplayOutboxRepo.updateEntryStatus(
      reactionId,
      deliveryStatus: GroupReactionReplayOutboxStatus.stored,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_OUTBOX_STORE_MARK_FAILED',
      details: {'error': e.toString()},
    );
  }
}
