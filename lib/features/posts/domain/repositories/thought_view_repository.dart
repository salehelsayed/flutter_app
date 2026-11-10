import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/thought_view_receipt.dart';

/// Optional companion to PostRepository. A view means a displayed card, never
/// a delivered envelope or a note shown on the Orbit.
abstract interface class ThoughtViewRepository {
  Future<List<ThoughtViewReceipt>> loadThoughtViews(String postId);

  /// How many friends saw each of [authorPeerId]'s own Thoughts in [postIds],
  /// live or expired, in one read. A Thought nobody saw has no entry.
  Future<Map<String, int>> countOwnThoughtViews({
    required String authorPeerId,
    required List<String> postIds,
  });

  /// Who saw [authorPeerId]'s own Thought [postId], newest first, live or
  /// expired. Empty for anyone else's Thought.
  Future<List<ThoughtViewReceipt>> loadOwnThoughtViews({
    required String authorPeerId,
    required String postId,
  });

  /// Atomically records the first local view and queues its encrypted receipt.
  /// Returns false for a duplicate, retired, or expired incoming thought.
  Future<bool> queueThoughtView({
    required ThoughtViewReceipt receipt,
    required PostFollowOnOutboxEvent event,
    required PostFollowOnOutboxRecipientDelivery recipient,
    required String authorPeerId,
    required String nowIso,
  });

  /// Insert-only receipt, requalified against the live authored thought and its
  /// original recipient snapshot in the same database transaction.
  Future<bool> recordIncomingThoughtView({
    required ThoughtViewReceipt receipt,
    required String localPeerId,
    required String nowIso,
  });
}
