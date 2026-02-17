import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/group_messages_into_threads.dart';

/// Loads the full feed from the database: all contacts + thread-grouped messages.
///
/// Returns ConnectionFeedItems sorted among ThreadFeedItems, with unread
/// threads first, then a divider gap, then read threads.
Future<List<FeedItem>> loadFeed({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
}) async {
  emitFlowEvent(layer: 'FL', event: 'FEED_LOAD_START', details: {});

  try {
    final contacts = (await contactRepo.getActiveContacts())
        .where((c) => !c.isBlocked)
        .toList();

    // Build contact username map
    final contactUsernames = <String, String>{
      for (final c in contacts) c.peerId: c.username,
    };

    // Collect all messages across all contacts
    final List<ConversationMessage> allMessages = [];
    for (final contact in contacts) {
      final messages =
          await messageRepo.getMessagesForContact(contact.peerId);
      allMessages.addAll(messages);
    }

    // Group into thread items
    final threadItems = groupMessagesIntoThreads(
      allMessages: allMessages,
      contactUsernames: contactUsernames,
    );

    // Create connection items
    final connectionItems = contacts
        .map((c) => ConnectionFeedItem.fromContact(c))
        .toList();

    // Merge: connection items sorted by timestamp among thread items
    final List<FeedItem> items = [...connectionItems, ...threadItems];
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_LOAD_SUCCESS',
      details: {'itemCount': items.length},
    );

    return items;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_LOAD_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
