import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_thread_summary_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/application/group_feed_media_verification.dart';
import 'package:flutter_app/features/feed/domain/utils/group_group_messages_into_threads.dart';
import 'package:flutter_app/features/feed/domain/utils/group_messages_into_threads.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_thread_preview_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Extra messages loaded beyond the unread run so the windowed preview also
/// captures the answering outgoing (newest) and a little earlier context for
/// the collapsed card. Tuning-only: counts come from the summary, "has earlier"
/// from `totalMessageCount`, so raising it never changes correctness.
const int _previewWindowContext = CardThreadFeedItem.maxPreview;

/// Newest-first window size for a PENDING contact: the full unread run plus
/// [_previewWindowContext]. Floored at `maxPreview + context` so even a
/// single-unread thread still shows a couple of context lines. Never a fixed K
/// (would truncate the uncapped unread set, 160 A2) and never limit-1.
int _previewWindowLimit(int unreadCount) {
  final base = unreadCount + _previewWindowContext;
  const floor = CardThreadFeedItem.maxPreview + _previewWindowContext;
  return base < floor ? floor : base;
}

/// Loads the feed preview for active contacts (160 db-persistence-1).
///
/// Instead of decrypting every contact's full history (the old N+1), this:
///   1. fetches ONE batched [ConversationThreadSummary] for all active
///      contacts (via the [ConversationThreadSummaryRepository] cast);
///   2. loads a bounded, newest-first, media-resolved window ONLY for PENDING
///      contacts (`summary.unreadCount > 0`) — all-read contacts cost zero
///      message reads;
///   3. sources card counts/state from the summary, and tags each connection
///      letter with `hasConversationHistory` so an all-read contact with prior
///      history does not resurface as a brand-new connection (160 A5).
Future<List<FeedItem>> loadContactFeedItems({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  final contacts = await contactRepo.getActiveContacts();
  if (contacts.isEmpty) return const <FeedItem>[];

  final contactUsernames = <String, String>{
    for (final c in contacts) c.peerId: c.username,
  };
  final contactBlocked = <String, bool>{
    for (final c in contacts) c.peerId: c.isBlocked,
  };

  final summaries = await _loadContactSummaries(
    messageRepo,
    contacts.map((c) => c.peerId),
  );

  final totalMessageCounts = <String, int>{};
  final unreadCounts = <String, int>{};
  final lastOutgoingAtByContact = <String, DateTime?>{};
  final allMessages = <ConversationMessage>[];

  for (final contact in contacts) {
    final summary = summaries[contact.peerId];
    final unread = summary?.unreadCount ?? 0;
    if (unread <= 0) {
      // All-read / empty contact: load nothing. Connection-letter suppression
      // is carried by hasConversationHistory below (160 A5).
      continue;
    }
    final windowed = await loadConversationPage(
      messageRepo: messageRepo,
      contactPeerId: contact.peerId,
      pageSize: _previewWindowLimit(unread),
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    );
    allMessages.addAll(windowed);
    totalMessageCounts[contact.peerId] = summary?.messageCount ?? windowed.length;
    unreadCounts[contact.peerId] = unread;
    lastOutgoingAtByContact[contact.peerId] = summary?.lastOutgoingAt;
  }

  final threadItems = groupMessagesIntoThreads(
    allMessages: allMessages,
    contactUsernames: contactUsernames,
    contactBlocked: contactBlocked,
    totalMessageCounts: totalMessageCounts,
    unreadCounts: unreadCounts,
    lastOutgoingAtByContact: lastOutgoingAtByContact,
  );

  final connectionItems = contacts
      .map(
        (c) => ConnectionFeedItem.fromContact(
          c,
          hasConversationHistory: (summaries[c.peerId]?.messageCount ?? 0) > 0,
        ),
      )
      .toList();

  return [...connectionItems, ...threadItems];
}

/// One batched summary call for all active contacts (via the cast, mirroring
/// `load_orbit_data_use_case.dart`). The fallback stays bounded (per-id counts,
/// never a full message load) so a repo that does not implement the summary
/// interface cannot silently re-introduce the N+1 decrypt.
Future<Map<String, ConversationThreadSummary>> _loadContactSummaries(
  MessageRepository messageRepo,
  Iterable<String> contactPeerIds,
) async {
  final ids = contactPeerIds.toList(growable: false);
  if (ids.isEmpty) return const <String, ConversationThreadSummary>{};

  if (messageRepo is ConversationThreadSummaryRepository) {
    return (messageRepo as ConversationThreadSummaryRepository)
        .getConversationThreadSummaries(ids);
  }

  final summaries = <String, ConversationThreadSummary>{};
  for (final id in ids) {
    summaries[id] = ConversationThreadSummary(
      contactPeerId: id,
      messageCount: await messageRepo.getMessageCountForContact(id),
      unreadCount: await messageRepo.getUnreadCountForContact(id),
      latestMessage: await messageRepo.getLatestMessageForContact(id),
    );
  }
  return summaries;
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

  // 161 db-persistence-5: cast to the batched-preview interface (mirroring the
  // orbit idiom / 160's contact summary cast). When present, ONE batched
  // preview + a bounded NEWEST-first window ONLY for pending groups replaces
  // the per-group `getMessagesPage(limit:200)` decrypt loop.
  final previewRepo = groupMsgRepo is GroupThreadPreviewRepository
      ? groupMsgRepo as GroupThreadPreviewRepository
      : null;

  List<GroupMessage> allGroupMessages = [];
  final totalMessageCounts = <String, int>{};
  final unreadCounts = <String, int>{};
  final lastOutgoingAtByGroup = <String, DateTime?>{};

  if (previewRepo != null) {
    final previews = await previewRepo.getGroupThreadPreviews(
      groups.map((g) => g.id),
    );
    for (final group in groups) {
      final preview = previews[group.id];
      final unread = preview?.unreadCount ?? 0;
      if (unread <= 0) {
        // All-read / answered group: load nothing. The shared pending
        // projection drops a non-pending group card, so no item is needed.
        continue;
      }
      final windowed = await groupMsgRepo.getMessagesPage(
        group.id,
        limit: _previewWindowLimit(unread),
      );
      allGroupMessages.addAll(windowed);
      totalMessageCounts[group.id] = preview?.messageCount ?? windowed.length;
      unreadCounts[group.id] = unread;
      lastOutgoingAtByGroup[group.id] = preview?.lastOutgoingAt;
    }
  } else {
    // Fallback for lightweight impls that do not expose the preview interface:
    // keep the bounded legacy per-group page (no worse than HEAD).
    for (final group in groups) {
      final msgs = await groupMsgRepo.getMessagesPage(group.id, limit: 200);
      allGroupMessages.addAll(msgs);
    }
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
    totalMessageCounts: totalMessageCounts,
    unreadCounts: unreadCounts,
    lastOutgoingAtByGroup: lastOutgoingAtByGroup,
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
