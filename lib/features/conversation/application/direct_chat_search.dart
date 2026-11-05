import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/utils/text_search.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

/// Ids of the 1:1 messages whose words or caption contain [query], newest
/// first. Deleted, hidden and private-media messages are never searched.
List<String> searchDirectChat(
  Iterable<ConversationMessage> oldestFirst,
  String query,
) => newestFirstSearchHits([
  for (final message in oldestFirst)
    if (!message.isDeleted &&
        !message.isHidden &&
        message.privateMediaMode == PrivateMediaMode.ordinary)
      (id: message.id, text: message.text),
], query);
