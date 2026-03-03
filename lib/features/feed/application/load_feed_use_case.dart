import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/group_group_messages_into_threads.dart';
import 'package:flutter_app/features/feed/domain/utils/group_messages_into_threads.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Loads the full feed from the database: all contacts + thread-grouped messages.
///
/// Returns ConnectionFeedItems sorted among ThreadFeedItems, with unread
/// threads first, then a divider gap, then read threads.
Future<List<FeedItem>> loadFeed({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  GroupRepository? groupRepo,
  GroupMessageRepository? groupMsgRepo,
}) async {
  emitFlowEvent(layer: 'FL', event: 'FEED_LOAD_START', details: {});

  try {
    final contacts = await contactRepo.getActiveContacts();

    // Build contact username map and blocked-status lookup
    final contactUsernames = <String, String>{
      for (final c in contacts) c.peerId: c.username,
    };
    final contactBlocked = <String, bool>{
      for (final c in contacts) c.peerId: c.isBlocked,
    };

    // Collect all messages across all contacts
    List<ConversationMessage> allMessages = [];
    for (final contact in contacts) {
      final messages =
          await messageRepo.getMessagesForContact(contact.peerId);
      allMessages.addAll(messages);
    }

    // Batch-attach media to messages, resolving relative paths
    if (mediaAttachmentRepo != null && allMessages.isNotEmpty) {
      final ids = allMessages.map((m) => m.id).toList();
      final mediaMap = await mediaAttachmentRepo.getAttachmentsForMessages(ids);
      if (mediaMap.isNotEmpty) {
        // Resolve relative paths to absolute for display
        final resolvedMap = <String, List<MediaAttachment>>{};
        if (mediaFileManager != null) {
          for (final entry in mediaMap.entries) {
            final resolved = <MediaAttachment>[];
            for (final a in entry.value) {
              if (a.localPath != null) {
                final absPath =
                    await mediaFileManager.resolveStoredPath(a.localPath!);
                resolved.add(a.copyWith(localPath: absPath));
              } else {
                resolved.add(a);
              }
            }
            resolvedMap[entry.key] = resolved;
          }
        }

        final effectiveMap = mediaFileManager != null ? resolvedMap : mediaMap;
        allMessages = allMessages
            .map((m) => m.copyWith(media: effectiveMap[m.id] ?? const []))
            .toList();
      }
    }

    // Group into thread items
    final threadItems = groupMessagesIntoThreads(
      allMessages: allMessages,
      contactUsernames: contactUsernames,
      contactBlocked: contactBlocked,
    );

    // Create connection items
    final connectionItems = contacts
        .map((c) => ConnectionFeedItem.fromContact(c))
        .toList();

    // Load group threads if repos provided
    List<GroupThreadFeedItem> groupThreadItems = [];
    if (groupRepo != null && groupMsgRepo != null) {
      final groups = await groupRepo.getActiveGroups();
      if (groups.isNotEmpty) {
        List<GroupMessage> allGroupMessages = [];
        for (final group in groups) {
          final msgs = await groupMsgRepo.getMessagesPage(
            group.id,
            limit: 200,
          );
          allGroupMessages.addAll(msgs);
        }
        groupThreadItems = groupGroupMessagesIntoThreads(
          allGroupMessages: allGroupMessages,
          groups: groups,
        );
      }
    }

    // Merge: connection items sorted by timestamp among thread items
    final List<FeedItem> items = [
      ...connectionItems,
      ...threadItems,
      ...groupThreadItems,
    ];
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
