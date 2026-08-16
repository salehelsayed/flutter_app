import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/push/application/group_notification_display_policy.dart';

/// Canonical local-state verdict after Android has published a managed group
/// notification generation.
///
/// [unknown] is deliberately distinct from [keep]. Read/open failures and a
/// push that arrived before its inbox row must never cause a blind cancel.
enum BackgroundGroupNotificationPostShowDecision { keep, read, retire, unknown }

sealed class BackgroundManagedGroupNotificationComparand {
  const BackgroundManagedGroupNotificationComparand({required this.groupId});

  final String groupId;
}

final class BackgroundGroupMessageNotificationComparand
    extends BackgroundManagedGroupNotificationComparand {
  const BackgroundGroupMessageNotificationComparand({
    required super.groupId,
    required this.messageId,
    required this.senderPeerId,
    this.senderTransportPeerId,
  });

  final String messageId;
  final String senderPeerId;
  final String? senderTransportPeerId;
}

final class BackgroundGroupReactionNotificationComparand
    extends BackgroundManagedGroupNotificationComparand {
  const BackgroundGroupReactionNotificationComparand({
    required super.groupId,
    required this.reactionId,
    required this.messageId,
    required this.senderPeerId,
    required this.timestamp,
    required this.notificationEventIdentity,
  });

  final String reactionId;
  final String messageId;
  final String senderPeerId;
  final String timestamp;
  final String notificationEventIdentity;
}

/// Authenticated outer scope for a locally authorized group-reaction fallback
/// whose private payload could not be decrypted.
///
/// This deliberately carries neither a reaction-state id nor a timestamp:
/// those facts exist only in the unavailable decrypted payload. The fence may
/// therefore make a terminal decision only when local materialization is
/// unambiguously tied to [notificationEventIdentity].
final class BackgroundProvisionalGroupReactionNotificationComparand
    extends BackgroundManagedGroupNotificationComparand {
  const BackgroundProvisionalGroupReactionNotificationComparand({
    required super.groupId,
    required this.messageId,
    required this.senderPeerId,
    required this.notificationEventIdentity,
  });

  final String messageId;
  final String senderPeerId;
  final String notificationEventIdentity;
}

/// Pure row-level policy used by the production SQLCipher reader and host
/// tests. Callers must convert read/open exceptions to [unknown]. A null row is
/// therefore a successfully observed absence, not a failed query.
BackgroundGroupNotificationPostShowDecision
evaluateBackgroundGroupNotificationPostShowState({
  required BackgroundManagedGroupNotificationComparand comparand,
  required String? localPeerId,
  required Map<String, Object?>? groupRow,
  required Map<String, Object?>? localMemberRow,
  Map<String, Object?>? messageRow,
  Map<String, Object?>? messageDeletionRow,
  Map<String, Object?>? reactionRow,
  Map<String, Object?>? targetMessageRow,
  Map<String, Object?>? targetDeletionRow,
  Map<String, Object?>? readAcknowledgementRow,
}) {
  final groupId = _trimToNull(comparand.groupId);
  final selfPeerId = _trimToNull(localPeerId);
  final storedGroupId = _trimToNull(groupRow?['id']);
  final localMemberGroupId = _trimToNull(localMemberRow?['group_id']);
  final localMemberPeerId = _trimToNull(localMemberRow?['peer_id']);
  final groupPolicy = evaluateGroupNotificationDisplayPolicy(
    GroupNotificationDisplayPolicyInput(
      groupExists: groupId != null && storedGroupId == groupId,
      hasCurrentLocalMembership:
          groupId != null &&
          selfPeerId != null &&
          localMemberGroupId == groupId &&
          localMemberPeerId == selfPeerId,
      groupType: _trimToNull(groupRow?['type']),
      isMuted: (groupRow?['is_muted'] as num?)?.toInt() == 1,
      isArchived: (groupRow?['is_archived'] as num?)?.toInt() == 1,
      isDissolved: (groupRow?['is_dissolved'] as num?)?.toInt() == 1,
      hasDissolvedAt: groupRow?['dissolved_at'] != null,
      hasSelfRemovedAt: groupRow?['self_removed_at'] != null,
    ),
  );
  if (!groupPolicy.shouldDisplay) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }

  return switch (comparand) {
    BackgroundGroupMessageNotificationComparand message => _evaluateMessage(
      message,
      messageRow: messageRow,
      deletionRow: messageDeletionRow,
      readAcknowledgementRow: readAcknowledgementRow,
    ),
    BackgroundGroupReactionNotificationComparand reaction => _evaluateReaction(
      reaction,
      localPeerId: selfPeerId!,
      reactionRow: reactionRow,
      targetMessageRow: targetMessageRow,
      targetDeletionRow: targetDeletionRow,
      readAcknowledgementRow: readAcknowledgementRow,
    ),
    BackgroundProvisionalGroupReactionNotificationComparand reaction =>
      _evaluateProvisionalReaction(
        reaction,
        localPeerId: selfPeerId!,
        reactionRow: reactionRow,
        targetMessageRow: targetMessageRow,
        targetDeletionRow: targetDeletionRow,
        readAcknowledgementRow: readAcknowledgementRow,
      ),
  };
}

BackgroundGroupNotificationPostShowDecision _evaluateMessage(
  BackgroundGroupMessageNotificationComparand comparand, {
  required Map<String, Object?>? messageRow,
  required Map<String, Object?>? deletionRow,
  required Map<String, Object?>? readAcknowledgementRow,
}) {
  if (_isExactReadAcknowledgement(
    readAcknowledgementRow,
    groupId: comparand.groupId,
    contentKind: 'message',
    eventIdentity: comparand.messageId,
  )) {
    return BackgroundGroupNotificationPostShowDecision.read;
  }
  if (_isExactDeletion(
    deletionRow,
    groupId: comparand.groupId,
    messageId: comparand.messageId,
  )) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }
  // Push delivery can precede inbox persistence. Absence without an exact
  // deletion tombstone is not proof that the just-shown card is stale.
  if (messageRow == null) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }
  final messagePolicy = GroupPrivateMediaPolicy.fromDatabase(
    version: messageRow['media_policy_version'],
    lifecycle: messageRow['media_lifecycle'],
    durationSeconds: messageRow['media_duration_seconds'],
    protected: messageRow['media_protected'],
  );
  if (_trimToNull(messageRow['id']) != comparand.messageId ||
      _trimToNull(messageRow['group_id']) != comparand.groupId ||
      _trimToNull(messageRow['sender_peer_id']) != comparand.senderPeerId ||
      (messageRow['is_incoming'] as num?)?.toInt() != 1 ||
      comparand.messageId.startsWith('sys-') ||
      messagePolicy.isUnsupported) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }
  if (messageRow['read_at'] != null) {
    return BackgroundGroupNotificationPostShowDecision.read;
  }
  return BackgroundGroupNotificationPostShowDecision.keep;
}

BackgroundGroupNotificationPostShowDecision _evaluateReaction(
  BackgroundGroupReactionNotificationComparand comparand, {
  required String localPeerId,
  required Map<String, Object?>? reactionRow,
  required Map<String, Object?>? targetMessageRow,
  required Map<String, Object?>? targetDeletionRow,
  required Map<String, Object?>? readAcknowledgementRow,
}) {
  if (_isExactReadAcknowledgement(
    readAcknowledgementRow,
    groupId: comparand.groupId,
    contentKind: 'reaction',
    eventIdentity: comparand.notificationEventIdentity,
  )) {
    return BackgroundGroupNotificationPostShowDecision.read;
  }
  if (_isExactDeletion(
    targetDeletionRow,
    groupId: comparand.groupId,
    messageId: comparand.messageId,
  )) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }
  if (targetMessageRow == null) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }
  final targetPolicy = GroupPrivateMediaPolicy.fromDatabase(
    version: targetMessageRow['media_policy_version'],
    lifecycle: targetMessageRow['media_lifecycle'],
    durationSeconds: targetMessageRow['media_duration_seconds'],
    protected: targetMessageRow['media_protected'],
  );
  if (_trimToNull(targetMessageRow['id']) != comparand.messageId ||
      _trimToNull(targetMessageRow['group_id']) != comparand.groupId ||
      _trimToNull(targetMessageRow['sender_peer_id']) != localPeerId ||
      (targetMessageRow['is_incoming'] as num?)?.toInt() != 0 ||
      comparand.messageId.startsWith('sys-') ||
      targetPolicy.requiresRedaction) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }

  // As with messages, the push can beat inbox mutation. Durable reaction
  // ingestion/reconciliation will revisit the generation once a row exists.
  if (reactionRow == null) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }
  if (_trimToNull(reactionRow['message_id']) != comparand.messageId ||
      _trimToNull(reactionRow['sender_peer_id']) != comparand.senderPeerId) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }

  final incomingAt = DateTime.tryParse(comparand.timestamp)?.toUtc();
  final currentAt = DateTime.tryParse(
    _trimToNull(reactionRow['timestamp']) ?? '',
  )?.toUtc();
  final removedAt = DateTime.tryParse(
    _trimToNull(reactionRow['removed_at']) ?? '',
  )?.toUtc();
  if (incomingAt == null || currentAt == null) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }
  if (reactionRow['removed_at'] != null && removedAt == null) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }
  if (removedAt != null && !removedAt.isBefore(incomingAt)) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }
  if (currentAt.isAfter(incomingAt)) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }
  if (currentAt.isBefore(incomingAt)) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }

  final currentReactionId = _trimToNull(reactionRow['id']);
  if (currentReactionId != comparand.reactionId) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }
  final terminalIdentity = _trimToNull(
    reactionRow['notification_display_terminal_event_id'],
  );
  if (terminalIdentity != null &&
      terminalIdentity != comparand.notificationEventIdentity) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }
  if (reactionRow['notification_acknowledged_at'] != null) {
    return BackgroundGroupNotificationPostShowDecision.read;
  }
  return BackgroundGroupNotificationPostShowDecision.keep;
}

BackgroundGroupNotificationPostShowDecision _evaluateProvisionalReaction(
  BackgroundProvisionalGroupReactionNotificationComparand comparand, {
  required String localPeerId,
  required Map<String, Object?>? reactionRow,
  required Map<String, Object?>? targetMessageRow,
  required Map<String, Object?>? targetDeletionRow,
  required Map<String, Object?>? readAcknowledgementRow,
}) {
  if (_isExactReadAcknowledgement(
    readAcknowledgementRow,
    groupId: comparand.groupId,
    contentKind: 'reaction',
    eventIdentity: comparand.notificationEventIdentity,
  )) {
    return BackgroundGroupNotificationPostShowDecision.read;
  }
  if (_isExactDeletion(
    targetDeletionRow,
    groupId: comparand.groupId,
    messageId: comparand.messageId,
  )) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }
  // The push can arrive before either the target or reaction has materialized.
  // Absence is not evidence that the locally authorized generic card is stale.
  if (targetMessageRow == null) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }

  final targetId = _trimToNull(targetMessageRow['id']);
  final targetGroupId = _trimToNull(targetMessageRow['group_id']);
  final targetSenderPeerId = _trimToNull(targetMessageRow['sender_peer_id']);
  final rawTargetIncoming = targetMessageRow['is_incoming'];
  if (targetId == null ||
      targetGroupId == null ||
      targetSenderPeerId == null ||
      rawTargetIncoming is! num) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }
  final targetIncoming = rawTargetIncoming.toInt();
  if (targetIncoming != 0 && targetIncoming != 1) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }
  final targetPolicy = GroupPrivateMediaPolicy.fromDatabase(
    version: targetMessageRow['media_policy_version'],
    lifecycle: targetMessageRow['media_lifecycle'],
    durationSeconds: targetMessageRow['media_duration_seconds'],
    protected: targetMessageRow['media_protected'],
  );
  if (targetId != comparand.messageId ||
      targetGroupId != comparand.groupId ||
      targetSenderPeerId != localPeerId ||
      targetIncoming != 0 ||
      comparand.messageId.startsWith('sys-') ||
      targetPolicy.requiresRedaction) {
    return BackgroundGroupNotificationPostShowDecision.retire;
  }

  if (reactionRow == null) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }
  final currentReactionId = _trimToNull(reactionRow['id']);
  final currentMessageId = _trimToNull(reactionRow['message_id']);
  final currentSenderPeerId = _trimToNull(reactionRow['sender_peer_id']);
  final currentTimestamp = DateTime.tryParse(
    _trimToNull(reactionRow['timestamp']) ?? '',
  )?.toUtc();
  final terminalIdentity = _trimToNull(
    reactionRow['notification_display_terminal_event_id'],
  );
  if (currentReactionId == null ||
      currentMessageId == null ||
      currentSenderPeerId == null ||
      currentTimestamp == null ||
      terminalIdentity == null) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }
  // A provisional comparand cannot order or identify a different local row;
  // it can only trust an exact terminal marker for the authenticated event.
  if (currentMessageId != comparand.messageId ||
      currentSenderPeerId != comparand.senderPeerId ||
      terminalIdentity != comparand.notificationEventIdentity) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }
  if (reactionRow['notification_acknowledged_at'] != null) {
    return BackgroundGroupNotificationPostShowDecision.read;
  }

  final rawRemovedAt = reactionRow['removed_at'];
  if (rawRemovedAt == null) {
    return BackgroundGroupNotificationPostShowDecision.keep;
  }
  final removedAt = DateTime.tryParse(_trimToNull(rawRemovedAt) ?? '')?.toUtc();
  if (removedAt == null || removedAt.isBefore(currentTimestamp)) {
    return BackgroundGroupNotificationPostShowDecision.unknown;
  }
  return BackgroundGroupNotificationPostShowDecision.retire;
}

bool _isExactDeletion(
  Map<String, Object?>? row, {
  required String groupId,
  required String messageId,
}) =>
    _trimToNull(row?['message_id']) == messageId &&
    _trimToNull(row?['group_id']) == groupId;

bool _isExactReadAcknowledgement(
  Map<String, Object?>? row, {
  required String groupId,
  required String contentKind,
  required String eventIdentity,
}) =>
    _trimToNull(row?['group_id']) == groupId &&
    _trimToNull(row?['content_kind']) == contentKind &&
    _trimToNull(row?['event_identity']) == eventIdentity;

String? _trimToNull(Object? value) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
