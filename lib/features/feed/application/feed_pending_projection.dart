import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';

/// Thread-kind discriminators for the cleared-watermark map keys (134
/// decision 2). Pinned across P4/P5/P6.
const String feedThreadKindContact = 'contact';
const String feedThreadKindGroup = 'group';
const String feedThreadKindConnection = 'connection';

/// `(threadKind, threadId)` → `cleared_at_ms`. `threadId` is the
/// peerId / groupId / contactPeerId.
typedef ClearedWatermarks = Map<(String, String), int>;

/// The cleared-watermark key for a feed item, or null for items not part of the
/// pending model (e.g. legacy [MessageFeedItem]).
(String, String)? feedThreadKey(FeedItem item) {
  if (item is ConnectionFeedItem) {
    return (feedThreadKindConnection, item.contactPeerId);
  }
  if (item is CardThreadFeedItem) {
    return (
      item.isGroup ? feedThreadKindGroup : feedThreadKindContact,
      item.displayId,
    );
  }
  return null;
}

/// Whether [item] is the feed card addressed by [threadId] (the focus/swipe
/// encoding: `group:<groupId>` for groups, bare peerId for 1:1 threads and
/// system/connection cards). Used to pin the focused card so it survives the
/// "answered-since" drop while the composer appends replies.
bool feedItemMatchesThreadId(FeedItem item, String threadId) {
  if (threadId.startsWith('group:')) {
    return item is GroupThreadFeedItem &&
        item.groupId == threadId.substring('group:'.length);
  }
  if (item is ThreadFeedItem) return item.contactPeerId == threadId;
  if (item is ConnectionFeedItem) return item.contactPeerId == threadId;
  return false;
}

/// INV-1 (exact): a thread is pending iff it has an incoming-unread message
/// whose `timestamp.millisecondsSinceEpoch` is strictly greater than its
/// cleared watermark AND there is no outgoing message after the newest
/// incoming ("not answered since"). Connection letters use presence — any
/// cleared row hides them. Comparison is always via [ThreadMessage.timestamp]
/// (a real `DateTime`), never a raw model `timestamp`.
bool isPendingFeedItem(FeedItem item, ClearedWatermarks watermarks) {
  if (item is ConnectionFeedItem) {
    return !watermarks.containsKey(
      (feedThreadKindConnection, item.contactPeerId),
    );
  }
  if (item is CardThreadFeedItem) {
    final unread = item.unreadMessages; // incoming && unread && !deleted
    if (unread.isEmpty) return false;

    final newestIncoming = unread
        .map((m) => m.timestamp)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    final answeredSince = item.messages.any(
      (m) => !m.isIncoming && !m.isDeleted && m.timestamp.isAfter(newestIncoming),
    );
    if (answeredSince) return false;

    final watermark = watermarks[(
      item.isGroup ? feedThreadKindGroup : feedThreadKindContact,
      item.displayId,
    )];
    if (watermark == null) return true;
    return unread.any(
      (m) => m.timestamp.millisecondsSinceEpoch > watermark,
    );
  }
  // MessageFeedItem and any other type are not part of the pending inbox.
  return false;
}

/// Filters [items] to only the pending threads (INV-1), preserving input
/// order. Emits `FL/FEED_PENDING_PROJECTED{kept}` once and
/// `FL/FEED_RESURFACE{threadId}` for each watermarked thread kept because a
/// fresher incoming arrived (the re-surface discriminator).
List<FeedItem> projectPendingFeed(
  List<FeedItem> items,
  ClearedWatermarks watermarks,
) {
  // A contact that already has a 1:1 thread is NOT a "new connection", so its
  // system "tap to say hi" letter is superseded by the thread letter — never
  // render both for the same peer (regardless of the thread's pending state).
  final threadedContactPeerIds = <String>{
    for (final item in items)
      if (item is ThreadFeedItem) item.contactPeerId,
  };

  final kept = <FeedItem>[];
  for (final item in items) {
    if (item is ConnectionFeedItem &&
        threadedContactPeerIds.contains(item.contactPeerId)) {
      continue;
    }
    if (!isPendingFeedItem(item, watermarks)) continue;
    kept.add(item);
    if (item is CardThreadFeedItem) {
      final key = (
        item.isGroup ? feedThreadKindGroup : feedThreadKindContact,
        item.displayId,
      );
      if (watermarks.containsKey(key)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_RESURFACE',
          details: {'threadId': item.displayId},
        );
      }
    }
  }
  emitFlowEvent(
    layer: 'FL',
    event: 'FEED_PENDING_PROJECTED',
    details: {'kept': kept.length},
  );
  return kept;
}
