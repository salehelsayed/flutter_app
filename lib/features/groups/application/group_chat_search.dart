import 'package:flutter_app/core/utils/text_search.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';

/// Ids of the group messages whose words or caption contain [query], newest
/// first. Private media and messages removed on this phone are never
/// searched.
List<String> searchGroupChat(
  Iterable<GroupMessage> oldestFirst,
  String query, {
  Set<String> removedIds = const {},
}) => newestFirstSearchHits([
  for (final message in oldestFirst)
    if (message.privateMediaPolicy.isOrdinary &&
        !removedIds.contains(message.id))
      (id: message.id, text: message.text),
], query);
