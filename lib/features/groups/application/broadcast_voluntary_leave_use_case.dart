import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

enum VoluntaryLeaveBroadcastSkipReason { lastAdmin, memberNotFound }

class PreparedVoluntaryLeaveNotice {
  const PreparedVoluntaryLeaveNotice({
    required this.pendingBroadcast,
    required this.timelineMessage,
    required this.identity,
    required this.senderBinding,
    required this.remainingMembers,
  });

  final GroupPendingBroadcast pendingBroadcast;
  final GroupMessage timelineMessage;
  final IdentityModel identity;
  final GroupSenderDeviceBinding senderBinding;
  final List<GroupMember> remainingMembers;

  List<String> get recipientPeerIds => pendingBroadcast.recipientPeerIds;
}

class VoluntaryLeaveNoticePreparationResult {
  const VoluntaryLeaveNoticePreparationResult.prepared(this.prepared)
    : skipReason = null;

  const VoluntaryLeaveNoticePreparationResult.skipped(this.skipReason)
    : prepared = null;

  final PreparedVoluntaryLeaveNotice? prepared;
  final VoluntaryLeaveBroadcastSkipReason? skipReason;

  bool get didPrepare => prepared != null;
}

/// Typed handoff from the reusable preparation policy to the durable exit
/// runner. A roster projection can make self the sole admin after the runner's
/// first guard but before notice preparation reloads members; callers must not
/// collapse that recoverable outcome into a generic failure.
class VoluntaryLeaveLastAdminPreparationRefused implements Exception {
  const VoluntaryLeaveLastAdminPreparationRefused();
}

PreparedVoluntaryLeaveNotice requirePreparedVoluntaryLeaveNotice(
  VoluntaryLeaveNoticePreparationResult result,
) {
  final prepared = result.prepared;
  if (prepared != null) return prepared;
  if (result.skipReason == VoluntaryLeaveBroadcastSkipReason.lastAdmin) {
    throw const VoluntaryLeaveLastAdminPreparationRefused();
  }
  throw StateError(
    'Group exit notice preparation refused: '
    '${result.skipReason?.name ?? 'unknown'}',
  );
}

enum VoluntaryLeaveNoticeAttemptClassification {
  delivered,
  degraded,
  retryable,
}

class VoluntaryLeaveNoticeAttemptResult {
  const VoluntaryLeaveNoticeAttemptResult({
    required this.classification,
    required this.livePublishResult,
    required this.offlineDeliveredPeerIds,
    required this.offlineFailedPeerIds,
    this.retryableCause,
  });

  final VoluntaryLeaveNoticeAttemptClassification classification;
  final Map<String, dynamic>? livePublishResult;
  final List<String> offlineDeliveredPeerIds;
  final List<String> offlineFailedPeerIds;
  final Object? retryableCause;

  bool get canAdvance =>
      classification != VoluntaryLeaveNoticeAttemptClassification.retryable;
}

class VoluntaryLeaveRotationResult {
  const VoluntaryLeaveRotationResult({
    required this.rotatedKey,
    required this.rotationDeferred,
  });

  final GroupKeyInfo? rotatedKey;
  final bool rotationDeferred;
}

class VoluntaryLeaveBroadcastResult {
  final bool didBroadcast;
  final List<String> remainingPeerIds;
  final GroupKeyInfo? rotatedKey;
  final VoluntaryLeaveBroadcastSkipReason? skipReason;
  final Map<String, dynamic>? livePublishResult;

  /// True when the member left but could NOT rotate the group key because the
  /// leaver lacks the `rotateKeys` permission and/or is not the group creator.
  /// The departure still broadcasts and completes (best-effort rotation); the
  /// group owes a re-key, which a remaining admin performs on receiving the
  /// `member_removed` — mirroring admin-removal's remover-driven rotation.
  final bool rotationDeferred;

  const VoluntaryLeaveBroadcastResult({
    required this.didBroadcast,
    required this.remainingPeerIds,
    this.rotatedKey,
    this.skipReason,
    this.livePublishResult,
    this.rotationDeferred = false,
  });

  static const skipped = VoluntaryLeaveBroadcastResult(
    didBroadcast: false,
    remainingPeerIds: <String>[],
  );

  static const skippedLastAdmin = VoluntaryLeaveBroadcastResult(
    didBroadcast: false,
    remainingPeerIds: <String>[],
    skipReason: VoluntaryLeaveBroadcastSkipReason.lastAdmin,
  );

  static const skippedMemberNotFound = VoluntaryLeaveBroadcastResult(
    didBroadcast: false,
    remainingPeerIds: <String>[],
    skipReason: VoluntaryLeaveBroadcastSkipReason.memberNotFound,
  );
}

/// Prepares one stable, signed voluntary-leave notice without publishing,
/// persisting its timeline row, rotating a key, or clearing durable work.
Future<VoluntaryLeaveNoticePreparationResult> prepareVoluntaryLeaveNotice({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupModel group,
  required IdentityRepository identityRepo,
  required String expectedSelfPeerId,
  required String sourceEventId,
  required DateTime eventAt,
}) async {
  if (sourceEventId.trim().isEmpty) {
    throw ArgumentError.value(sourceEventId, 'sourceEventId');
  }
  final stableEventAt = eventAt.toUtc();
  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    throw StateError('No identity found');
  }
  if (expectedSelfPeerId.trim().isEmpty ||
      identity.peerId != expectedSelfPeerId) {
    throw StateError('Voluntary leave identity changed before preparation');
  }

  final members = await groupRepo.getMembers(group.id);
  final selfMembers = members
      .where((member) => member.peerId == identity.peerId)
      .toList(growable: false);
  if (selfMembers.isEmpty) {
    return const VoluntaryLeaveNoticePreparationResult.skipped(
      VoluntaryLeaveBroadcastSkipReason.memberNotFound,
    );
  }
  if (selfMembers.length != 1) {
    throw StateError('Voluntary leave self membership is ambiguous');
  }
  final selfMember = selfMembers.single;
  final adminCount = members
      .where((member) => member.role == MemberRole.admin)
      .length;
  if (selfMember.role == MemberRole.admin && adminCount <= 1) {
    return const VoluntaryLeaveNoticePreparationResult.skipped(
      VoluntaryLeaveBroadcastSkipReason.lastAdmin,
    );
  }
  final senderBinding = resolveGroupSenderDeviceBindingFromMember(
    member: selfMember,
    senderPublicKey: identity.publicKey,
  );
  final remainingMembers = normalizeGroupConfigMembers(
    members.where((member) => member.peerId != identity.peerId).toList(),
  );
  final recipientPeerIds = remainingMembers
      .map((member) => member.peerId)
      .toList(growable: false);
  final preTransitionStateHash = await buildGroupTransitionStateHash(
    groupRepo,
    group.id,
  );
  final sysPayload = await signGroupSystemTransitionPayload(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: group.id,
    transitionType: 'member_removed',
    sourceEventId: sourceEventId,
    eventAt: stableEventAt,
    actorPeerId: identity.peerId,
    actorUsername: identity.username,
    actorSigningPublicKey: identity.publicKey,
    actorPrivateKey: identity.privateKey,
    actorDeviceId: senderBinding.deviceId,
    actorTransportPeerId: senderBinding.transportPeerId,
    actorKeyPackageId: senderBinding.keyPackageId,
    preTransitionStateHash: preTransitionStateHash,
    systemPayload: {
      '__sys': 'member_removed',
      'member': {'peerId': identity.peerId, 'username': identity.username},
      'removedAt': stableEventAt.toIso8601String(),
      'groupConfig': buildGroupConfigPayload(group, remainingMembers),
    },
  );
  final timelineMessage = buildMemberRemovedTimelineMessage(
    groupId: group.id,
    removedPeerId: identity.peerId,
    removedUsername: identity.username,
    senderId: identity.peerId,
    senderUsername: identity.username,
    eventAt: stableEventAt,
  );
  final pendingBroadcast = GroupPendingBroadcast(
    id: 'pending_group_broadcast:${group.id}:$sourceEventId',
    groupId: group.id,
    kind: groupPendingBroadcastKindExitLeaveNotice,
    sysText: jsonEncode(sysPayload),
    recipientPeerIds: recipientPeerIds,
    eventAt: stableEventAt,
    sourceMessageId: sourceEventId,
    createdAt: stableEventAt,
    updatedAt: stableEventAt,
  );
  return VoluntaryLeaveNoticePreparationResult.prepared(
    PreparedVoluntaryLeaveNotice(
      pendingBroadcast: pendingBroadcast,
      timelineMessage: timelineMessage,
      identity: identity,
      senderBinding: senderBinding,
      remainingMembers: List<GroupMember>.unmodifiable(remainingMembers),
    ),
  );
}

/// Attempts the already-signed notice without mutating or clearing its durable
/// row. Transport failures are classified as degradation after every salvage
/// recipient gets an attempt; missing local key/state remains retryable.
Future<VoluntaryLeaveNoticeAttemptResult> attemptPreparedVoluntaryLeaveNotice({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required PreparedVoluntaryLeaveNotice prepared,
  required String expectedSelfPeerId,
}) async {
  final pending = prepared.pendingBroadcast;
  final sourceEventId = pending.sourceMessageId;
  if (prepared.identity.peerId != expectedSelfPeerId ||
      pending.kind != groupPendingBroadcastKindExitLeaveNotice ||
      sourceEventId == null ||
      sourceEventId.trim().isEmpty ||
      pending.groupId != prepared.timelineMessage.groupId ||
      !pending.eventAt.toUtc().isAtSameMomentAs(
        prepared.timelineMessage.timestamp.toUtc(),
      ) ||
      prepared.timelineMessage.senderPeerId != expectedSelfPeerId ||
      !hasExactSignedVoluntaryLeaveNoticeAuthority(
        pendingBroadcast: pending,
        expectedGroupId: pending.groupId,
        expectedSelfPeerId: expectedSelfPeerId,
        expectedSourceEventId: sourceEventId,
        expectedEventAt: pending.eventAt,
        requireExactActorCredentials: true,
        expectedActorUsername: prepared.identity.username,
        expectedActorSigningPublicKey: prepared.identity.publicKey,
        expectedActorDeviceId: prepared.senderBinding.deviceId,
        expectedActorTransportPeerId: prepared.senderBinding.transportPeerId,
        expectedActorKeyPackageId: prepared.senderBinding.keyPackageId,
      )) {
    return VoluntaryLeaveNoticeAttemptResult(
      classification: VoluntaryLeaveNoticeAttemptClassification.retryable,
      livePublishResult: null,
      offlineDeliveredPeerIds: const [],
      offlineFailedPeerIds: const [],
      retryableCause: StateError(
        'Prepared voluntary leave notice context is inconsistent',
      ),
    );
  }

  final cryptographicAuthorityFailure =
      await _preparedVoluntaryLeaveCryptographicAuthorityFailure(
        bridge: bridge,
        prepared: prepared,
        sourceEventId: sourceEventId,
      );
  if (cryptographicAuthorityFailure != null) {
    return VoluntaryLeaveNoticeAttemptResult(
      classification: VoluntaryLeaveNoticeAttemptClassification.retryable,
      livePublishResult: null,
      offlineDeliveredPeerIds: const [],
      offlineFailedPeerIds: const [],
      retryableCause: cryptographicAuthorityFailure,
    );
  }

  Map<String, dynamic>? livePublishResult;
  var liveDelivered = false;
  try {
    livePublishResult = await callGroupPublish(
      bridge,
      groupId: pending.groupId,
      text: pending.sysText,
      senderPeerId: prepared.identity.peerId,
      senderPublicKey: prepared.identity.publicKey,
      senderPrivateKey: prepared.identity.privateKey,
      senderUsername: prepared.identity.username,
      senderDeviceId: prepared.senderBinding.deviceId,
      senderTransportPeerId: prepared.senderBinding.transportPeerId,
      senderDevicePublicKey: prepared.senderBinding.devicePublicKey,
      senderKeyPackageId: prepared.senderBinding.keyPackageId,
      messageId: sourceEventId,
    );
    liveDelivered = livePublishResult['ok'] == true;
  } catch (_) {
    // Live topic delivery is best-effort once the signed notice is prepared.
  }

  final recipients = pending.recipientPeerIds;
  if (recipients.isEmpty) {
    return VoluntaryLeaveNoticeAttemptResult(
      classification: liveDelivered
          ? VoluntaryLeaveNoticeAttemptClassification.delivered
          : VoluntaryLeaveNoticeAttemptClassification.degraded,
      livePublishResult: livePublishResult,
      offlineDeliveredPeerIds: const [],
      offlineFailedPeerIds: const [],
    );
  }

  final GroupKeyInfo replayKey;
  try {
    final loadedKey = await groupRepo.getLatestKey(pending.groupId);
    if (loadedKey == null) {
      throw StateError('No group key available for voluntary leave replay');
    }
    replayKey = loadedKey;
  } catch (error) {
    return VoluntaryLeaveNoticeAttemptResult(
      classification: VoluntaryLeaveNoticeAttemptClassification.retryable,
      livePublishResult: livePublishResult,
      offlineDeliveredPeerIds: const [],
      offlineFailedPeerIds: const [],
      retryableCause: error,
    );
  }

  final inboxPlaintext = _voluntaryLeaveInboxPlaintext(prepared);
  try {
    final aggregateEnvelope = await buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: pending.groupId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: inboxPlaintext,
      senderPeerId: prepared.identity.peerId,
      senderPublicKey: prepared.identity.publicKey,
      senderPrivateKey: prepared.identity.privateKey,
      keyInfo: replayKey,
      senderDeviceId: prepared.senderBinding.deviceId,
      senderTransportPeerId: prepared.senderBinding.transportPeerId,
      senderKeyPackageId: prepared.senderBinding.keyPackageId,
      messageId: prepared.timelineMessage.id,
      recipientPeerIds: recipients,
    );
    await callGroupInboxStore(
      bridge,
      pending.groupId,
      aggregateEnvelope,
      recipientPeerIds: recipients,
      preserveRecipientPeerIds: true,
    );
    return VoluntaryLeaveNoticeAttemptResult(
      classification: liveDelivered
          ? VoluntaryLeaveNoticeAttemptClassification.delivered
          : VoluntaryLeaveNoticeAttemptClassification.degraded,
      livePublishResult: livePublishResult,
      offlineDeliveredPeerIds: List<String>.unmodifiable(recipients),
      offlineFailedPeerIds: const [],
    );
  } catch (_) {
    // Preserve the aggregate wire on the normal path, but salvage recipients
    // independently after aggregate preparation or storage degrades.
  }

  final deliveredPeerIds = <String>[];
  final failedPeerIds = <String>[];
  for (final recipientPeerId in recipients) {
    try {
      final recipientEnvelope = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: pending.groupId,
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: inboxPlaintext,
        senderPeerId: prepared.identity.peerId,
        senderPublicKey: prepared.identity.publicKey,
        senderPrivateKey: prepared.identity.privateKey,
        keyInfo: replayKey,
        senderDeviceId: prepared.senderBinding.deviceId,
        senderTransportPeerId: prepared.senderBinding.transportPeerId,
        senderKeyPackageId: prepared.senderBinding.keyPackageId,
        messageId: prepared.timelineMessage.id,
        recipientPeerIds: [recipientPeerId],
      );
      await callGroupInboxStore(
        bridge,
        pending.groupId,
        recipientEnvelope,
        recipientPeerIds: [recipientPeerId],
        preserveRecipientPeerIds: true,
      );
      deliveredPeerIds.add(recipientPeerId);
    } catch (_) {
      failedPeerIds.add(recipientPeerId);
    }
  }
  return VoluntaryLeaveNoticeAttemptResult(
    classification: VoluntaryLeaveNoticeAttemptClassification.degraded,
    livePublishResult: livePublishResult,
    offlineDeliveredPeerIds: List<String>.unmodifiable(deliveredPeerIds),
    offlineFailedPeerIds: List<String>.unmodifiable(failedPeerIds),
  );
}

Future<Object?> _preparedVoluntaryLeaveCryptographicAuthorityFailure({
  required Bridge bridge,
  required PreparedVoluntaryLeaveNotice prepared,
  required String sourceEventId,
}) async {
  try {
    final pending = prepared.pendingBroadcast;
    final payload = _stringKeyedMap(jsonDecode(pending.sysText));
    if (payload == null) {
      return StateError('Prepared voluntary leave notice payload is malformed');
    }
    final auditCheck = await verifyGroupTransitionAudit(
      bridge: bridge,
      containerPayload: payload,
      groupId: pending.groupId,
      transitionType: 'member_removed',
      sourceEventId: sourceEventId,
      eventAt: pending.eventAt,
      actorPeerId: prepared.identity.peerId,
      actorUsername: prepared.identity.username,
      actorSigningPublicKey: prepared.identity.publicKey,
      actorDeviceId: prepared.senderBinding.deviceId,
      actorTransportPeerId: prepared.senderBinding.transportPeerId,
      expectedTransitionSubject: buildGroupSystemTransitionSubject(payload),
    );
    if (!auditCheck.isValid) {
      return StateError(
        'Prepared voluntary leave notice signature is invalid or unavailable',
      );
    }

    // The stored audit proves which public key signed preparation; prove that
    // the private key loaded after restart still belongs to that public key
    // before any group publish or inbox write can report a false success.
    final keyPairChallenge = jsonEncode({
      'purpose': 'prepared_voluntary_leave_key_pair',
      'groupId': pending.groupId,
      'sourceEventId': sourceEventId,
      'eventAt': pending.eventAt.toUtc().toIso8601String(),
      'auditHash': auditCheck.verification!.auditHash,
    });
    final proof = await callSignPayload(
      bridge: bridge,
      dataToSign: keyPairChallenge,
      privateKey: prepared.identity.privateKey,
    );
    final proofSignature = proof['signature'];
    if (proof['ok'] != true ||
        proofSignature is! String ||
        proofSignature.isEmpty ||
        !await callVerifyPayload(
          bridge: bridge,
          publicKey: prepared.identity.publicKey,
          data: keyPairChallenge,
          signature: proofSignature,
        )) {
      return StateError(
        'Prepared voluntary leave identity key pair is invalid or unavailable',
      );
    }
    return null;
  } catch (error) {
    return error;
  }
}

/// Performs only the existing best-effort rotation. It reloads identity and
/// membership so a durable runner can resume here without re-preparing or
/// re-signing the leave notice after process recreation.
Future<VoluntaryLeaveRotationResult> rotateVoluntaryLeaveGroupKeyBestEffort({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required IdentityRepository identityRepo,
  required String expectedSelfPeerId,
  Future<bool> Function(String peerId, String message)? sendP2PMessage,
  Future<bool> Function(String peerId, String message)? storeP2PMessageInInbox,
}) async {
  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    throw StateError('No identity found');
  }
  if (expectedSelfPeerId.trim().isEmpty ||
      identity.peerId != expectedSelfPeerId) {
    throw StateError('Voluntary leave identity changed before key rotation');
  }
  final members = await groupRepo.getMembers(groupId);
  final hasRemainingMembers = members.any(
    (member) => member.peerId != identity.peerId,
  );
  if (!hasRemainingMembers) {
    return const VoluntaryLeaveRotationResult(
      rotatedKey: null,
      rotationDeferred: false,
    );
  }

  final rotationOutcome = await rotateAndDistributeGroupKey(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    selfPeerId: identity.peerId,
    senderPublicKey: identity.publicKey,
    senderPrivateKey: identity.privateKey,
    senderUsername: identity.username,
    sendP2PMessage: sendP2PMessage,
    storeP2PMessageInInbox: storeP2PMessageInInbox,
  );
  final rotatedKey = rotationOutcome.key;
  final rotationDeferred = rotatedKey == null;
  if (rotationDeferred) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_VOLUNTARY_LEAVE_ROTATION_DEFERRED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
  }
  return VoluntaryLeaveRotationResult(
    rotatedKey: rotatedKey,
    rotationDeferred: rotationDeferred,
  );
}

/// Broadcasts the local member's voluntary leave and rotates future group
/// traffic away from the departing member before local cleanup deletes state.
Future<VoluntaryLeaveBroadcastResult> broadcastVoluntaryLeaveAndRotateKey({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupModel group,
  required IdentityRepository identityRepo,
  GroupMessageRepository? msgRepo,
  Future<bool> Function(String peerId, String message)? sendP2PMessage,
  Future<bool> Function(String peerId, String message)? storeP2PMessageInInbox,
  void Function(String messageId)? onTimelineMessageSaved,
}) async {
  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    throw StateError('No identity found');
  }
  final leftAt = DateTime.now().toUtc();
  final sourceEventId =
      'member_removed:${group.id}:${identity.peerId}:${leftAt.microsecondsSinceEpoch}';
  final preparation = await prepareVoluntaryLeaveNotice(
    bridge: bridge,
    groupRepo: groupRepo,
    group: group,
    identityRepo: identityRepo,
    expectedSelfPeerId: identity.peerId,
    sourceEventId: sourceEventId,
    eventAt: leftAt,
  );
  if (!preparation.didPrepare) {
    return switch (preparation.skipReason) {
      VoluntaryLeaveBroadcastSkipReason.lastAdmin =>
        VoluntaryLeaveBroadcastResult.skippedLastAdmin,
      VoluntaryLeaveBroadcastSkipReason.memberNotFound =>
        VoluntaryLeaveBroadcastResult.skippedMemberNotFound,
      null => VoluntaryLeaveBroadcastResult.skipped,
    };
  }
  final prepared = preparation.prepared!;
  if (prepared.identity.peerId != identity.peerId) {
    throw StateError('Identity changed while preparing voluntary leave');
  }
  if (msgRepo != null) {
    await msgRepo.saveMessage(prepared.timelineMessage);
    onTimelineMessageSaved?.call(prepared.timelineMessage.id);
  }
  final attempt = await attemptPreparedVoluntaryLeaveNotice(
    bridge: bridge,
    groupRepo: groupRepo,
    prepared: prepared,
    expectedSelfPeerId: identity.peerId,
  );
  if (!attempt.canAdvance) {
    throw StateError(
      'Voluntary leave notice remains retryable: ${attempt.retryableCause}',
    );
  }
  final rotation = await rotateVoluntaryLeaveGroupKeyBestEffort(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: group.id,
    identityRepo: identityRepo,
    expectedSelfPeerId: identity.peerId,
    sendP2PMessage: sendP2PMessage,
    storeP2PMessageInInbox: storeP2PMessageInInbox,
  );
  return VoluntaryLeaveBroadcastResult(
    didBroadcast: true,
    remainingPeerIds: prepared.recipientPeerIds,
    rotatedKey: rotation.rotatedKey,
    skipReason: null,
    livePublishResult: attempt.livePublishResult,
    rotationDeferred: rotation.rotationDeferred,
  );
}

String _voluntaryLeaveInboxPlaintext(PreparedVoluntaryLeaveNotice prepared) {
  final pending = prepared.pendingBroadcast;
  final binding = prepared.senderBinding;
  return jsonEncode({
    'groupId': pending.groupId,
    'senderId': prepared.identity.peerId,
    'senderUsername': prepared.identity.username,
    if (binding.deviceId != null) 'senderDeviceId': binding.deviceId,
    if (binding.transportPeerId != null)
      'transportPeerId': binding.transportPeerId,
    'text': pending.sysText,
    'timestamp': pending.eventAt.toUtc().toIso8601String(),
    'messageId': pending.sourceMessageId,
  });
}

/// Verifies the immutable actor, subject, event, group and recipient authority
/// carried by a durable signed voluntary-leave notice. This is intentionally a
/// structural preflight; receiver-side signature verification remains the
/// authoritative cryptographic boundary.
bool hasExactSignedVoluntaryLeaveNoticeAuthority({
  required GroupPendingBroadcast pendingBroadcast,
  required String expectedGroupId,
  required String expectedSelfPeerId,
  required String expectedSourceEventId,
  required DateTime expectedEventAt,
  bool requireExactActorCredentials = false,
  String? expectedActorUsername,
  String? expectedActorSigningPublicKey,
  String? expectedActorDeviceId,
  String? expectedActorTransportPeerId,
  String? expectedActorKeyPackageId,
}) {
  try {
    final eventAt = expectedEventAt.toUtc().toIso8601String();
    if (pendingBroadcast.groupId != expectedGroupId ||
        pendingBroadcast.kind != groupPendingBroadcastKindExitLeaveNotice ||
        pendingBroadcast.sourceMessageId != expectedSourceEventId ||
        !pendingBroadcast.eventAt.toUtc().isAtSameMomentAs(
          expectedEventAt.toUtc(),
        )) {
      return false;
    }

    final systemPayload = _stringKeyedMap(jsonDecode(pendingBroadcast.sysText));
    final subjectMember = _stringKeyedMap(systemPayload?['member']);
    final audit = _stringKeyedMap(
      systemPayload?[signedGroupTransitionAuditField],
    );
    if (systemPayload == null ||
        systemPayload['__sys'] != 'member_removed' ||
        subjectMember?['peerId'] != expectedSelfPeerId ||
        systemPayload['removedAt'] != eventAt ||
        audit == null ||
        audit['transitionType'] != 'member_removed' ||
        audit['groupId'] != expectedGroupId ||
        audit['sourceEventId'] != expectedSourceEventId ||
        audit['eventAt'] != eventAt) {
      return false;
    }

    final signedPayloadText = audit['signedPayload'];
    if (signedPayloadText is! String || signedPayloadText.isEmpty) {
      return false;
    }
    final signedPayload = _stringKeyedMap(jsonDecode(signedPayloadText));
    final actor = _stringKeyedMap(signedPayload?['actor']);
    final transitionSubject = _stringKeyedMap(
      signedPayload?['transitionSubject'],
    );
    final signedSubjectMember = _stringKeyedMap(transitionSubject?['member']);
    if (signedPayload == null ||
        signedPayload['transitionType'] != 'member_removed' ||
        signedPayload['groupId'] != expectedGroupId ||
        signedPayload['sourceEventId'] != expectedSourceEventId ||
        signedPayload['eventAt'] != eventAt ||
        actor == null ||
        actor['peerId'] != expectedSelfPeerId ||
        signedSubjectMember?['peerId'] != expectedSelfPeerId ||
        transitionSubject?['removedAt'] != eventAt) {
      return false;
    }
    if (requireExactActorCredentials &&
        (actor['username'] != expectedActorUsername ||
            actor['signingPublicKey'] != expectedActorSigningPublicKey ||
            actor['deviceId'] != expectedActorDeviceId ||
            actor['transportPeerId'] != expectedActorTransportPeerId ||
            actor['keyPackageId'] != expectedActorKeyPackageId)) {
      return false;
    }

    final groupConfig = _stringKeyedMap(systemPayload['groupConfig']);
    final rawMembers = groupConfig?['members'];
    if (rawMembers is! List) return false;
    final signedRecipientPeerIds = <String>[];
    for (final rawMember in rawMembers) {
      final member = _stringKeyedMap(rawMember);
      final peerId = member?['peerId'];
      if (peerId is! String || peerId.trim().isEmpty) return false;
      signedRecipientPeerIds.add(peerId);
    }
    return _samePeerIds(
      pendingBroadcast.recipientPeerIds,
      signedRecipientPeerIds,
    );
  } catch (_) {
    return false;
  }
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is! Map) return null;
  try {
    return value.map((key, entry) => MapEntry(key as String, entry));
  } catch (_) {
    return null;
  }
}

bool _samePeerIds(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
