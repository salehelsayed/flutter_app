import 'package:flutter/foundation.dart';

import 'package:flutter_app/features/feed/domain/models/feed_item.dart';

class FeedStore {
  final Map<String, ConnectionFeedItem> _connectionsByContactId = {};
  final Map<String, ThreadFeedItem> _threadsByContactId = {};
  final Map<String, GroupThreadFeedItem> _groupThreadsById = {};
  final ValueNotifier<List<FeedItem>> _itemsNotifier =
      ValueNotifier<List<FeedItem>>(const <FeedItem>[]);

  ValueListenable<List<FeedItem>> get itemsListenable => _itemsNotifier;

  List<FeedItem> get items => _itemsNotifier.value;

  List<FeedItem> _buildItems() {
    final merged = <FeedItem>[
      ..._connectionsByContactId.values,
      ..._threadsByContactId.values,
      ..._groupThreadsById.values,
    ];
    merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return merged;
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
