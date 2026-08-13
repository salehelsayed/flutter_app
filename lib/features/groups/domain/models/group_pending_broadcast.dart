import 'dart:convert';

const groupPendingBroadcastKindMemberRoleUpdated = 'member_role_updated';
const groupPendingBroadcastKindMemberRolePrepared =
    'member_role_updated_prepared';
const groupPendingBroadcastKindExitLeaveNotice = 'member_removed_exit_intent';
const groupPendingBroadcastKindMemberRemoved = 'member_removed';
const groupPendingBroadcastKindLinkedBootstrap = 'linked_group_bootstrap_v1';
const groupPendingBroadcastKindProtectedAuthority = 'group_authority_v1';

bool isProtectedGroupPendingBroadcastKind(String kind) =>
    kind == groupPendingBroadcastKindLinkedBootstrap ||
    kind == groupPendingBroadcastKindProtectedAuthority;

bool isPendingGroupMemberRoleBroadcastKind(String kind) =>
    kind == groupPendingBroadcastKindMemberRoleUpdated ||
    kind == groupPendingBroadcastKindMemberRolePrepared;

bool sameExactGroupPendingBroadcast(
  GroupPendingBroadcast current,
  GroupPendingBroadcast expected,
) {
  if (current.id != expected.id ||
      current.groupId != expected.groupId ||
      current.kind != expected.kind ||
      current.sysText != expected.sysText ||
      current.sourceMessageId != expected.sourceMessageId ||
      current.eventAt.toUtc() != expected.eventAt.toUtc() ||
      current.createdAt.toUtc() != expected.createdAt.toUtc() ||
      current.updatedAt.toUtc() != expected.updatedAt.toUtc() ||
      current.recipientPeerIds.length != expected.recipientPeerIds.length) {
    return false;
  }
  for (var index = 0; index < current.recipientPeerIds.length; index++) {
    if (current.recipientPeerIds[index] != expected.recipientPeerIds[index]) {
      return false;
    }
  }
  return true;
}

/// A group system broadcast (e.g. a `group_metadata_updated` edit) that was
/// persisted locally but failed to leave the device. Retained durably so it can
/// be re-pushed on the next rejoin/foreground instead of being lost or silently
/// reported as sent.
class GroupPendingBroadcast {
  final String id;
  final String groupId;

  /// The transition kind, e.g. `group_metadata_updated`.
  final String kind;

  /// The already-signed system payload (`jsonEncode(signedPayload)`) to re-push
  /// verbatim — re-using it preserves the original signature and `eventAt`.
  final String sysText;

  /// Recipients for the relay inbox / direct-resend leg.
  final List<String> recipientPeerIds;

  /// The original event instant; re-using it (never re-stamping `now`) keeps the
  /// retry from resurrecting stale state past a newer remote update.
  final DateTime eventAt;

  /// The wire message id, used both as the re-push `messageId` and for dedup.
  final String? sourceMessageId;

  final DateTime createdAt;
  final DateTime updatedAt;

  const GroupPendingBroadcast({
    required this.id,
    required this.groupId,
    required this.kind,
    required this.sysText,
    required this.recipientPeerIds,
    required this.eventAt,
    this.sourceMessageId,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'group_id': groupId,
    'kind': kind,
    'sys_text': sysText,
    'recipient_peer_ids': jsonEncode(recipientPeerIds),
    'event_at': eventAt.toUtc().toIso8601String(),
    'source_message_id': sourceMessageId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory GroupPendingBroadcast.fromMap(Map<String, Object?> map) {
    final rawRecipients = map['recipient_peer_ids'] as String?;
    final recipients = rawRecipients == null || rawRecipients.isEmpty
        ? const <String>[]
        : (jsonDecode(rawRecipients) as List<dynamic>).cast<String>();
    return GroupPendingBroadcast(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      kind: map['kind'] as String,
      sysText: map['sys_text'] as String,
      recipientPeerIds: recipients,
      eventAt: DateTime.parse(map['event_at'] as String),
      sourceMessageId: map['source_message_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
