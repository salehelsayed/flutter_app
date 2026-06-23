import 'package:flutter/foundation.dart';

import 'package:flutter_app/features/feed/application/feed_pending_projection.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';

class FeedStore {
  final Map<String, ConnectionFeedItem> _connectionsByContactId = {};
  final Map<String, ThreadFeedItem> _threadsByContactId = {};
  final Map<String, GroupThreadFeedItem> _groupThreadsById = {};

  /// Cleared watermarks (134 decision 2). The pending projection in
  /// [_buildItems] drops a thread whose newest incoming is not strictly newer
  /// than its watermark, so EVERY publish (from any of the ~12 live listeners)
  /// re-applies the cleared filter — a just-cleared card can never be revived
  /// by a stream re-publish.
  ClearedWatermarks _clearedWatermarks = <(String, String), int>{};

  /// The currently-focused thread id (focus/swipe encoding). While set, that
  /// card is PINNED into the projected list even if it stops being pending —
  /// e.g. once you reply it is "answered" and the projection would drop it, but
  /// the composer must keep appending green bubbles under it until focus
  /// clears. Cleared on defocus / swipe-commit / swipe-dismiss (134-P5/P6).
  String? _pinnedThreadId;

  final ValueNotifier<List<FeedItem>> _itemsNotifier =
      ValueNotifier<List<FeedItem>>(const <FeedItem>[]);

  ValueListenable<List<FeedItem>> get itemsListenable => _itemsNotifier;

  List<FeedItem> get items => _itemsNotifier.value;

  /// Current cleared watermarks (read-only view for diagnostics/tests).
  ClearedWatermarks get clearedWatermarks =>
      Map<(String, String), int>.unmodifiable(_clearedWatermarks);

  /// Replace the whole watermark set (e.g. after loading from
  /// `FeedClearedRepository.getClearedWatermarks()`), then re-project.
  void setClearedWatermarks(ClearedWatermarks watermarks) {
    _clearedWatermarks = Map<(String, String), int>.of(watermarks);
    _publish();
  }

  /// Optimistically hide a thread (swipe-right commit / swipe-left dismiss):
  /// set the in-memory watermark and re-project. The durable write is the
  /// caller's (`FeedClearedRepository.markCleared`).
  void markClearedLocally(String threadKind, String threadId, int clearedAtMs) {
    _clearedWatermarks[(threadKind, threadId)] = clearedAtMs;
    _publish();
  }

  /// Undo a prior [markClearedLocally]: drop the in-memory watermark so the
  /// item re-surfaces in its natural (timestamp-sorted) slot.
  void clearClearedLocally(String threadKind, String threadId) {
    _clearedWatermarks.remove((threadKind, threadId));
    _publish();
  }

  /// Pin (or unpin with null) the focused thread so it stays rendered while the
  /// composer appends replies, even after it becomes "answered" (134 append-
  /// stay). The caller MUST unpin BEFORE marking a card cleared (commit/dismiss)
  /// so a removed card is not re-pinned.
  void setPinnedThread(String? threadId) {
    if (_pinnedThreadId == threadId) return;
    _pinnedThreadId = threadId;
    _publish();
  }

  List<FeedItem> _buildItems() {
    final merged = <FeedItem>[
      ..._connectionsByContactId.values,
      ..._threadsByContactId.values,
      ..._groupThreadsById.values,
    ];
    merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final projected = projectPendingFeed(merged, _clearedWatermarks);

    final pinned = _pinnedThreadId;
    if (pinned == null ||
        projected.any((i) => feedItemMatchesThreadId(i, pinned))) {
      return projected;
    }
    // The focused thread fell out of the pending set (answered) — re-insert it
    // at its sorted slot so the focused card + appended bubbles stay visible.
    // Prefer a real thread item over a same-peer connection card.
    final matches =
        merged.where((i) => feedItemMatchesThreadId(i, pinned)).toList();
    if (matches.isEmpty) return projected;
    final pinnedItem = matches.firstWhere(
      (i) => i is CardThreadFeedItem,
      orElse: () => matches.first,
    );
    final result = List<FeedItem>.of(projected);
    final insertAt = result.indexWhere(
      (i) => i.timestamp.compareTo(pinnedItem.timestamp) < 0,
    );
    if (insertAt < 0) {
      result.add(pinnedItem);
    } else {
      result.insert(insertAt, pinnedItem);
    }
    return result;
  }

  Set<String> get contactMessageIds => _threadsByContactId.values
      .expand((item) => item.messages)
      .map((message) => message.id)
      .toSet();

  bool containsMessageId(String messageId) {
    for (final thread in _threadsByContactId.values) {
      if (thread.messages.any((message) => message.id == messageId)) {
        return true;
      }
    }
    return false;
  }

  Set<String> messageIdsForContact(String contactPeerId) {
    final thread = _threadsByContactId[contactPeerId];
    if (thread == null) return <String>{};
    return thread.messages.map((message) => message.id).toSet();
  }

  bool hasConnection(String contactPeerId) =>
      _connectionsByContactId.containsKey(contactPeerId);

  void replaceAll(Iterable<FeedItem> feedItems) {
    _connectionsByContactId.clear();
    _threadsByContactId.clear();
    _groupThreadsById.clear();
    _ingest(feedItems);
    _publish();
  }

  void replaceContacts(Iterable<FeedItem> contactItems) {
    _connectionsByContactId.clear();
    _threadsByContactId.clear();
    _ingest(contactItems);
    _publish();
  }

  void replaceGroups(Iterable<GroupThreadFeedItem> groupItems) {
    _groupThreadsById
      ..clear()
      ..addEntries(groupItems.map((item) => MapEntry(item.groupId, item)));
    _publish();
  }

  void replaceContactSnapshot({
    required String contactPeerId,
    ConnectionFeedItem? connectionItem,
    ThreadFeedItem? threadItem,
  }) {
    _connectionsByContactId.remove(contactPeerId);
    _threadsByContactId.remove(contactPeerId);

    if (connectionItem != null) {
      _connectionsByContactId[contactPeerId] = connectionItem;
    }
    if (threadItem != null) {
      _threadsByContactId[contactPeerId] = threadItem;
    }
    _publish();
  }

  void replaceGroupSnapshot({
    required String groupId,
    GroupThreadFeedItem? threadItem,
  }) {
    _groupThreadsById.remove(groupId);
    if (threadItem != null) {
      _groupThreadsById[groupId] = threadItem;
    }
    _publish();
  }

  void upsertConnection(ConnectionFeedItem item) {
    _connectionsByContactId[item.contactPeerId] = item;
    _publish();
  }

  void dispose() {
    _itemsNotifier.dispose();
  }

  void _ingest(Iterable<FeedItem> feedItems) {
    for (final item in feedItems) {
      if (item is ConnectionFeedItem) {
        _connectionsByContactId[item.contactPeerId] = item;
      } else if (item is ThreadFeedItem) {
        _threadsByContactId[item.contactPeerId] = item;
      } else if (item is GroupThreadFeedItem) {
        _groupThreadsById[item.groupId] = item;
      }
    }
  }

  void _publish() {
    _itemsNotifier.value = List<FeedItem>.unmodifiable(_buildItems());
  }
}
