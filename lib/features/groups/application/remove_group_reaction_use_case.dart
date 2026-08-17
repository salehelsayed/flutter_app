import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';

/// Result of removing an emoji reaction from a group message.
enum RemoveGroupReactionResult {
  /// Live publish was accepted and local/replay state was queued.
  ///
  /// This is not a remote delivery confirmation.
  success,

  /// Live publish failed or threw, but the remove was durably staged in the
  /// replay outbox and applied locally. The existing retry driver will
  /// re-drive it — it is NOT a hard drop. (INV-R1)
  queuedForRetry,
  groupNotFound,
  groupDissolved,
  notMember,

  /// The strict-authority machinery refused the remove (resolver refusal or
  /// legacy authority drift) — NOT a membership fact. The wired screen
  /// restores the optimistic state without latching the removed banner
  /// (Plan 377).
  authorityUnavailable,
  publishFailed,
}

/// Deterministic outbox PK for a remove, keyed by (groupId, messageId,
/// senderPeerId) — emoji is intentionally excluded because a remove targets
/// the single reaction a sender holds on a message. Repeated remove re-stages
/// therefore collapse to one durable row instead of minting a fresh uuid each
/// time (OQ-2 / INV-R3). Mirrors `_deterministicAddReactionId`.
String deterministicGroupRemoveReactionId({
  required String groupId,
  required String messageId,
  required String senderPeerId,
}) {
  final canonical = jsonEncode({
    'action': 'remove',
    'groupId': groupId,
    'messageId': messageId,
    'senderPeerId': senderPeerId,
  });
  final digest = sha256.convert(utf8.encode(canonical)).toString();
  return 'group-reaction-remove-${digest.substring(0, 32)}';
}

/// Sends a "remove" reaction via live publish plus replay outbox and deletes locally.
Future<RemoveGroupReactionResult> removeGroupReaction({
  required Bridge bridge,
  required GroupRepository groupRepo,
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
  GroupMessageRepository? msgRepo,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  GroupMessage? targetMessage,
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
      final strictDevice = member == null || resolution.context == null
          ? null
          : resolveStrictGroupReactionSenderDevice(
              member: member,
              senderPublicKey: senderPublicKey,
              context: resolution.context!,
            );
      final strictMembers = strictDevice == null
          ? null
          : await groupRepo.getMembers(groupId);
      final recipients =
          resolution.kind == GroupContentAuthoringResolutionKind.strict &&
              strictDevice != null
          ? await loadStrictGroupReactionRecipientPeerIds(
              groupRepo: groupRepo,
              groupId: groupId,
              senderTransportPeerId: strictDevice.transportPeerId,
              inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
              members: strictMembers,
            )
          : const <String>[];
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
      final exactTarget = msgRepo == null
          ? targetMessage
          : await msgRepo.getMessage(messageId);
      final targetEligible =
          exactTarget != null &&
          msgRepo is GroupMessageStrictReactionTargetRepository &&
          await (msgRepo as GroupMessageStrictReactionTargetRepository)
              .isStrictReactionTargetEligible(exactTarget);
      return (
        group: group,
        member: member,
        resolution: resolution,
        recipients: recipients,
        exactTarget: exactTarget,
        targetEligible: targetEligible,
        authorBindingUnique: authorBindingUnique,
      );
    },
  );
  if (snapshot.group == null) {
    return RemoveGroupReactionResult.groupNotFound;
  }
  if (snapshot.group!.isDissolved) {
    return RemoveGroupReactionResult.groupDissolved;
  }
  if (snapshot.member == null) {
    return RemoveGroupReactionResult.notMember;
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
    return RemoveGroupReactionResult.authorityUnavailable;
  }
  if (snapshot.resolution.kind == GroupContentAuthoringResolutionKind.strict &&
      (!snapshot.targetEligible || !snapshot.authorBindingUnique)) {
    return RemoveGroupReactionResult.notMember;
  }
  return _removeGroupReactionWithAuthorityRecheck(
    bridge: bridge,
    groupRepo: groupRepo,
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
    msgRepo: msgRepo,
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
    targetMessage: snapshot.exactTarget,
    authoredAt: authoredAt,
  );
}

Future<RemoveGroupReactionResult> _removeGroupReactionWithAuthorityRecheck({
  required Bridge bridge,
  required GroupRepository groupRepo,
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
  GroupMessageRepository? msgRepo,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  GroupMessage? targetMessage,
  DateTime? authoredAt,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REACTION_REMOVE_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
    },
  );

  // 1. Validate group exists
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    return RemoveGroupReactionResult.groupNotFound;
  }

  if (group.isDissolved) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_REMOVE_GROUP_DISSOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        if (group.dissolvedAt != null)
          'dissolvedAt': group.dissolvedAt!.toUtc().toIso8601String(),
      },
    );
    return RemoveGroupReactionResult.groupDissolved;
  }

  // 2. Validate sender is a member
  final member = await groupRepo.getMember(groupId, senderPeerId);
  if (member == null) {
    return RemoveGroupReactionResult.notMember;
  }
  final strictContext = groupContentAuthoring;
  final strictSelected =
      authoringKind == GroupContentAuthoringResolutionKind.strict;
  if (strictSelected) {
    if (strictContext == null || msgRepo == null) {
      return RemoveGroupReactionResult.notMember;
    }
    final linked = strictContext.linkedTransportCredential;
    final validLinked =
        linked != null &&
        linked.state == LinkedTransportCredentialState.active &&
        linked.accountPeerId == senderPeerId;
    final signingPrivate = validLinked
        ? linked.transportPrivateKey
        : senderPrivateKey;
    final strictDevice = resolveStrictGroupReactionSenderDevice(
      member: member,
      senderPublicKey: senderPublicKey,
      context: strictContext,
    );
    final target = targetMessage;
    if (!strictContext.directLinkedDeviceSelector.allowsLinkedDeviceAuthoring ||
        !strictContext.multiDeviceSyncEnabled ||
        strictContext.authorityVersion == null ||
        strictContext.inboxStore == null ||
        (strictContext.requireLinkedTransportCredential && !validLinked) ||
        strictDevice == null ||
        target == null ||
        target.groupId != groupId ||
        target.id != messageId ||
        target.privateMediaPolicy.isPrivate ||
        target.media.isNotEmpty ||
        target.isForwarded ||
        target.quotedMessageId?.isNotEmpty == true ||
        target.text.trimLeft().startsWith(r'{"__sys":')) {
      return RemoveGroupReactionResult.notMember;
    }
    final result = await sendStrictGroupReactionContent(
      bridge: bridge,
      groupRepo: groupRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: groupId,
      message: target,
      emoji: emoji,
      senderPeerId: senderPeerId,
      senderDevice: strictDevice,
      senderPrivateKey: signingPrivate,
      context: strictContext,
      explicitContext: explicitGroupContentAuthoring,
      senderAccountPublicKey: senderPublicKey,
      messageRepository: msgRepo,
      frozenRecipientPeerIds: frozenRecipientPeerIds,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
      authoredAt: authoredAt ?? DateTime.now().toUtc(),
      action: GroupReactionPayload.actionRemove,
    );
    return switch (result.$1) {
      SendGroupReactionResult.success => RemoveGroupReactionResult.success,
      SendGroupReactionResult.queuedForRetry =>
        RemoveGroupReactionResult.queuedForRetry,
      _ => RemoveGroupReactionResult.notMember,
    };
  }

  final senderDevice = member.firstActiveDeviceForSigningKey(
    senderPublicKey,
    allowLegacyFallback: true,
  );

  if (authoringKind !=
          GroupContentAuthoringResolutionKind.legacyUninitialized ||
      !await _legacyRemoveAuthorityStillUninitialized(
        groupRepo: groupRepo,
        groupId: groupId,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        expectedMessage: targetMessage,
        messageRepository: msgRepo,
        explicitContext: explicitGroupContentAuthoring,
      )) {
    return RemoveGroupReactionResult.authorityUnavailable;
  }

  // 3. Build remove payload (deterministic id ⇒ idempotent re-stage / OQ-2)
  final reactionId = deterministicGroupRemoveReactionId(
    groupId: groupId,
    messageId: messageId,
    senderPeerId: senderPeerId,
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
      latestTransition.action == GroupReactionPayload.actionRemove &&
      currentReaction?.isRemoved == true;
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
    action: 'remove',
    senderPeerId: senderPeerId,
    timestamp: timestamp,
    eventId: transitionId,
  );

  // 4. Stage durable custody + relay store BEFORE publishing, so a live publish
  //    failure still leaves a retryable replay-outbox row (INV-R1/INV-R2).
  if (exactRetry) {
    unawaited(
      _attemptRemoveReactionInboxStore(
        bridge: bridge,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        reactionId: transitionId,
        inboxRetryPayload: latestTransition.inboxRetryPayload,
        staged: true,
      ),
    );
  } else {
    await _stageRemoveReactionInboxStore(
      bridge: bridge,
      groupRepo: groupRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: groupId,
      payload: payload,
      senderPublicKey: senderDevice?.deviceSigningPublicKey ?? senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      senderDevice: senderDevice,
      transitionId: transitionId,
    );
  }

  // 5. Delete locally (optimistic) regardless of the publish outcome. Tombstone
  //    with the remove's authored timestamp so a stale incoming add can't
  //    resurrect it (INV-T1/INV-T2).
  if (reactionRepo case AtomicGroupReactionRemovalRepository atomicGroup) {
    await atomicGroup.applyGroupRemove(
      groupId: groupId,
      reaction: payload.toMessageReaction(),
    );
  } else {
    await reactionRepo.removeReaction(
      messageId,
      senderPeerId,
      removedAtTimestamp: timestamp,
    );
  }

  // 6. Attempt live publish. A failure downgrades the result to queuedForRetry
  //    but never discards the custody/optimistic delete staged above.
  var publishOk = false;
  try {
    final result = await callGroupPublishReaction(
      bridge,
      groupId: groupId,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      senderDeviceId: senderDevice?.deviceId,
      senderTransportPeerId: senderDevice?.transportPeerId,
      senderDevicePublicKey: senderDevice?.deviceSigningPublicKey,
      senderKeyPackageId: senderDevice?.keyPackageId,
      reactionPayload: payload.toInnerJson(),
    );

    if (result['ok'] == true) {
      publishOk = true;
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_REMOVE_PUBLISH_FAILED',
        details: {'errorCode': result['errorCode']},
      );
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_REMOVE_ERROR',
      details: {'error': e.toString()},
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REACTION_REMOVE_QUEUED',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'emoji': emoji,
      'deliveryMode': 'live_publish_replay_queued',
      'deliveryConfirmed': false,
      'localState': 'optimistic',
      'replayStatus': 'pending',
      'publishOk': publishOk,
    },
  );

  return publishOk
      ? RemoveGroupReactionResult.success
      : RemoveGroupReactionResult.queuedForRetry;
}

Future<bool> _legacyRemoveAuthorityStillUninitialized({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderPeerId,
  required String senderPublicKey,
  required GroupMessage? expectedMessage,
  required GroupMessageRepository? messageRepository,
  required GroupContentAuthoringContext? explicitContext,
}) {
  return runGroupAuthorityPhase(
    groupId: groupId,
    action: () async {
      final group = await groupRepo.getGroup(groupId);
      final sender = await groupRepo.getMember(groupId, senderPeerId);
      final currentMessage =
          messageRepository == null || expectedMessage == null
          ? expectedMessage
          : await messageRepository.getMessage(expectedMessage.id);
      final resolverAbsentLegacy = isResolverAbsentLegacyGroupContentAuthoring(
        owner: groupRepo,
        explicitContext: explicitContext,
      );
      if (group == null ||
          group.selfRemovedAt != null ||
          group.isDissolved ||
          sender == null ||
          (sender.hasInitializedDeviceAuthority && !resolverAbsentLegacy) ||
          (expectedMessage != null &&
              (currentMessage == null ||
                  currentMessage.groupId != groupId ||
                  currentMessage.senderPeerId != expectedMessage.senderPeerId ||
                  currentMessage.timestamp.toUtc() !=
                      expectedMessage.timestamp.toUtc()))) {
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

String _defaultGroupReactionTransitionId() =>
    'group-reaction-event-${const Uuid().v4()}';

String _requiredTransitionId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, 'transitionId', 'must not be empty');
  }
  return normalized;
}

Future<void> _stageRemoveReactionInboxStore({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupReactionReplayOutboxRepository reactionReplayOutboxRepo,
  required String groupId,
  required GroupReactionPayload payload,
  required String senderPublicKey,
  required String senderPrivateKey,
  required GroupMemberDeviceIdentity? senderDevice,
  required String transitionId,
}) async {
  // Plan 319: stage a rescuable needs-build row BEFORE any throwing build
  // step (mirrors the send lane).
  final stagedAtIso = DateTime.now().toUtc().toIso8601String();
  var needsBuildStaged = false;
  try {
    needsBuildStaged = await reactionReplayOutboxRepo.saveEntry(
      GroupReactionReplayOutboxEntry(
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
      ),
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
    final senderTransportPeerId =
        senderDevice?.transportPeerId ?? payload.senderPeerId;
    final replayRecipients = await _resolveReplayRecipients(
      groupRepo: groupRepo,
      groupId: groupId,
      senderTransportPeerId: senderTransportPeerId,
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
      senderDeviceId: senderDevice?.deviceId,
      senderTransportPeerId: senderDevice?.transportPeerId,
      senderKeyPackageId: senderDevice?.keyPackageId,
      recipientPeerIds: replayRecipients,
      reactionNotificationExtension: GroupReactionNotificationExtensionInput(
        transitionId: transitionId,
        action: payload.action,
        targetMessageId: payload.messageId,
        reactorPeerId: payload.senderPeerId,
        reactorTransportPeerId: senderTransportPeerId,
        notificationRecipientTransportPeerIds: const <String>[],
      ),
    );
  } catch (e) {
    // The needs-build row staged above survives for the retrier to rebuild.
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
    _attemptRemoveReactionInboxStore(
      bridge: bridge,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      reactionId: transitionId,
      inboxRetryPayload: inboxRetryPayload,
      staged: staged,
    ),
  );
}

Future<List<String>> _resolveReplayRecipients({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderTransportPeerId,
}) async {
  final recipients = <String>{};
  for (final member in await groupRepo.getMembers(groupId)) {
    for (final device in member.activeDevicesWithLegacyFallback()) {
      final transportPeerId = device.transportPeerId.trim();
      if (transportPeerId.isEmpty ||
          transportPeerId == senderTransportPeerId.trim()) {
        continue;
      }
      recipients.add(transportPeerId);
    }
  }
  return recipients.toList()..sort();
}

/// Plan 319 (GAP 2): the send lane's unroutable pre-check, ported to the
/// remove choke point. Without it an empty-recipient payload reaches the Go
/// bridge, which silently no-ops on the config-loaded arm and returns ok —
/// the row was then falsely marked `stored`. Placed at the choke point so BOTH
/// call sites (stage and exactRetry) are covered.
Future<void> _attemptRemoveReactionInboxStore({
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
        'action': 'remove',
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

/// Mirror of the send lane's predicate (plan 315/319): an empty or absent
/// recipient list means the relay store can never route this custody.
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
