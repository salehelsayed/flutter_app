import 'group_message.dart';

/// Batched preview aggregate for a group thread (161 db-persistence-5, the
/// QUERY half). The group sibling of [ConversationThreadSummary] (160 A0):
/// the feed derives a collapsed group card's counts + state + "has earlier"
/// affordance from this summary row rather than decrypting the group's full
/// per-group page on every feed mount.
///
/// Loaded ONE-batched for all active groups via
/// [GroupThreadPreviewRepository.getGroupThreadPreviews]; the windowed message
/// slice itself is loaded separately (and ONLY for pending groups) so an
/// all-read group costs zero message reads. Distinct from the existing
/// [GroupThreadSummary] (orbit-owned, unread-badge only) so the orbit path is
/// left byte-for-byte unchanged.
class GroupThreadPreview {
  final String groupId;

  /// Total non-cutoff messages in the group (excludes
  /// `sys-member_removed_cutoff:` rows). Sources [CardThreadFeedItem.totalMessageCount]
  /// so "View earlier" survives the windowed preview (161 G3).
  final int messageCount;

  final int unreadCount;

  /// Timestamp of the newest OUTGOING message in the group, or null when the
  /// group has no outgoing reply. Lets the feed derive
  /// `hasReply` / `conversationState` / `lastRepliedAt` from the summary rather
  /// than scanning a windowed message slice (where an old reply may be off the
  /// loaded window). Sourced from `MAX(CASE WHEN is_incoming = 0 …)` in
  /// `dbLoadGroupThreadPreviews` (161 G4). `hasSent` derives from it.
  final DateTime? lastOutgoingAt;

  final GroupMessage? latestMessage;

  const GroupThreadPreview({
    required this.groupId,
    this.messageCount = 0,
    this.unreadCount = 0,
    this.lastOutgoingAt,
    this.latestMessage,
  });

  /// True when the group has at least one outgoing message anywhere in its
  /// history (even one OFF the loaded window). Drives the `replied`/`active`
  /// conversation state without re-scanning a partial window.
  bool get hasSent => lastOutgoingAt != null;
}
