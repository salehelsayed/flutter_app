import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/application/group_feed_media_verification.dart';
import 'package:flutter_app/features/feed/domain/utils/group_group_messages_into_threads.dart';
import 'package:flutter_app/features/feed/domain/utils/group_messages_into_threads.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Loads all feed items derived from active contacts and their messages.
Future<List<FeedItem>> loadContactFeedItems({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
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
    final messages = await messageRepo.getMessagesForContact(contact.peerId);
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
              final absPath = await mediaFileManager.resolveStoredPath(
                a.localPath!,
              );
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

  final threadItems = groupMessagesIntoThreads(
    allMessages: allMessages,
    contactUsernames: contactUsernames,
    contactBlocked: contactBlocked,
  );

  final connectionItems = contacts
      .map((c) => ConnectionFeedItem.fromContact(c))
      .toList();

  return [...connectionItems, ...threadItems];
}

/// Loads all feed items derived from active groups and their messages.
Future<List<GroupThreadFeedItem>> loadGroupFeedItems({
  GroupRepository? groupRepo,
  GroupMessageRepository? groupMsgRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  if (groupRepo == null || groupMsgRepo == null) return [];

  final groups = await groupRepo.getActiveGroups();
  if (groups.isEmpty) return [];

  List<GroupMessage> allGroupMessages = [];
  for (final group in groups) {
    final msgs = await groupMsgRepo.getMessagesPage(group.id, limit: 200);
    allGroupMessages.addAll(msgs);
  }

  // Batch-attach media to group messages, resolving relative paths
  if (mediaAttachmentRepo != null && allGroupMessages.isNotEmpty) {
    final ids = allGroupMessages.map((m) => m.id).toList();
    final mediaMap = await mediaAttachmentRepo.getAttachmentsForMessages(ids);
    if (mediaMap.isNotEmpty) {
      final resolvedMap = <String, List<MediaAttachment>>{};
      for (final entry in mediaMap.entries) {
        resolvedMap[entry.key] = await resolveGroupFeedMediaForDisplay(
          attachments: entry.value,
          mediaFileManager: mediaFileManager,
        );
      }

      allGroupMessages = allGroupMessages
          .map((m) => m.copyWith(media: resolvedMap[m.id] ?? const []))
          .toList();
    }
  }

  return groupGroupMessagesIntoThreads(
    allGroupMessages: allGroupMessages,
    groups: groups,
  );
}

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
    final contactItems = await loadContactFeedItems(
      contactRepo: contactRepo,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    );
    final groupThreadItems = await loadGroupFeedItems(
      groupRepo: groupRepo,
      groupMsgRepo: groupMsgRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    );

    // Merge: connection items sorted by timestamp among thread items
    final List<FeedItem> items = [...contactItems, ...groupThreadItems];
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
