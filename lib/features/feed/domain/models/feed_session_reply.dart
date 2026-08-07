/// 134-P5: an outgoing reply the local user sent from the Feed during the
/// CURRENT focus session, tracked screen-side so the focused letter card can
/// "append-stay" the new green bubble immediately and keep a failed send
/// visible with a retry affordance (never-silent send, TC-22 / TC-30).
///
/// These are deliberately ephemeral, screen-level state — they are NOT derived
/// from the pending projection (which only surfaces incoming-unread lines).
class FeedSessionReply {
  /// Persisted message id of the optimistic outgoing message (for retry).
  final String messageId;

  /// The outgoing body text rendered in the appended bubble.
  final String text;

  /// True when the send failed or is stuck pending — drives the tappable
  /// "tap to retry" affordance instead of a silent/absent state.
  final bool failed;

  /// Durable-authority disposition for this optimistic direct reply.
  ///
  /// `true` means its message projection or exact inbox-custody row was
  /// positively observed. `false` means the send positively finished before
  /// either authority was staged. `null` means the attempt has not yet been
  /// classified, so an absent projection/outbox must not be re-minted.
  final bool? hadDurableAuthority;

  const FeedSessionReply({
    required this.messageId,
    required this.text,
    this.failed = false,
    this.hadDurableAuthority,
  });

  FeedSessionReply copyWith({bool? failed, bool? hadDurableAuthority}) =>
      FeedSessionReply(
        messageId: messageId,
        text: text,
        failed: failed ?? this.failed,
        hadDurableAuthority: hadDurableAuthority ?? this.hadDurableAuthority,
      );
}
