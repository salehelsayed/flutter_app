import 'package:flutter_app/features/feed/domain/models/feed_item.dart';

List<FeedItem> applyContactFeedSnapshot({
  required List<FeedItem> currentItems,
  required String contactPeerId,
  ConnectionFeedItem? connectionItem,
  ThreadFeedItem? threadItem,
}) {
  final nextItems = currentItems.where((item) {
    if (item is ConnectionFeedItem) {
      return item.contactPeerId != contactPeerId;
    }
    if (item is ThreadFeedItem) {
      return item.contactPeerId != contactPeerId;
    }
    return true;
  }).toList();

  if (connectionItem != null) nextItems.add(connectionItem);
  if (threadItem != null) nextItems.add(threadItem);

  nextItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return nextItems;
}

List<FeedItem> applyGroupFeedSnapshot({
  required List<FeedItem> currentItems,
  required String groupId,
  GroupThreadFeedItem? threadItem,
}) {
  final nextItems = currentItems.where((item) {
    if (item is GroupThreadFeedItem) {
      return item.groupId != groupId;
    }
    return true;
  }).toList();

  if (threadItem != null) nextItems.add(threadItem);

  nextItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return nextItems;
}
