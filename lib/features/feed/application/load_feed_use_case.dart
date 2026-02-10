import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';

/// Loads the full feed from the database: all contacts + all incoming messages.
///
/// Returns items sorted newest-first.
Future<List<FeedItem>> loadFeed({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
}) async {
  emitFlowEvent(layer: 'FL', event: 'FEED_LOAD_START', details: {});

  try {
    final contacts = await contactRepo.getAllContacts();
    final List<FeedItem> items = [];

    // Add a ConnectionFeedItem for each contact
    for (final contact in contacts) {
      items.add(ConnectionFeedItem.fromContact(contact));
    }

    // Add incoming MessageFeedItems for each contact's messages
    for (final contact in contacts) {
      final messages =
          await messageRepo.getMessagesForContact(contact.peerId);

      for (final message in messages) {
        if (!message.isIncoming) continue;

        final displayTime = formatMessageTime(message.timestamp);
        items.add(MessageFeedItem(
          id: 'message_${message.id}',
          timestamp:
              DateTime.tryParse(message.timestamp) ?? DateTime.now(),
          contactPeerId: message.contactPeerId,
          contactUsername: contact.username,
          messageId: message.id,
          messageText: message.text,
          messageTime: displayTime,
        ));
      }
    }

    // Sort newest-first
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
