import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_call_timeline_source.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Loads all messages for a conversation with a contact.
///
/// Returns messages ordered by timestamp ASC.
Future<List<ConversationMessage>> loadConversation({
  required MessageRepository messageRepo,
  required String contactPeerId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_LOAD_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  final messages = await messageRepo.getMessagesForContact(contactPeerId);

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_LOAD_SUCCESS',
    details: {'count': messages.length},
  );

  return _attachMedia(messages, mediaAttachmentRepo, mediaFileManager);
}

/// Loads a typed chronological timeline of chat messages and, when explicitly
/// enabled, terminal call-history rows.
///
/// [includeCalls] defaults off. Existing chat loaders retain their original
/// return type and ordering, and a missing/failing optional call source never
/// prevents ordinary messages from rendering.
Future<List<ConversationTimelineEntry>> loadConversationTimeline({
  required MessageRepository messageRepo,
  required String contactPeerId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  ConversationCallTimelineSource? callTimelineSource,
  bool includeCalls = false,
}) async {
  final messages = await loadConversation(
    messageRepo: messageRepo,
    contactPeerId: contactPeerId,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
  );
  final messageEntries = messages
      .map(ConversationMessageTimelineEntry.new)
      .toList(growable: false);
  if (!includeCalls || callTimelineSource == null) {
    return List<ConversationTimelineEntry>.unmodifiable(messageEntries);
  }

  List<ConversationCallTimelineEntry> callEntries;
  try {
    callEntries = await callTimelineSource.listCallsForContact(contactPeerId);
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_CALL_TIMELINE_LOAD_SKIPPED',
      details: {'errorType': error.runtimeType.toString()},
    );
    return List<ConversationTimelineEntry>.unmodifiable(messageEntries);
  }

  final sortable = <_SortableTimelineEntry>[
    for (var index = 0; index < messageEntries.length; index++)
      _SortableTimelineEntry(
        entry: messageEntries[index],
        originalMessageIndex: index,
      ),
    for (final call in callEntries)
      if (call.contactPeerId == contactPeerId)
        _SortableTimelineEntry(entry: call),
  ]..sort(_compareTimelineEntries);
  return List<ConversationTimelineEntry>.unmodifiable(
    sortable.map((row) => row.entry),
  );
}

final class _SortableTimelineEntry {
  const _SortableTimelineEntry({
    required this.entry,
    this.originalMessageIndex,
  });

  final ConversationTimelineEntry entry;
  final int? originalMessageIndex;
}

int _compareTimelineEntries(
  _SortableTimelineEntry left,
  _SortableTimelineEntry right,
) {
  final leftTime = DateTime.tryParse(left.entry.timestamp);
  final rightTime = DateTime.tryParse(right.entry.timestamp);
  final byTime = leftTime != null && rightTime != null
      ? leftTime.compareTo(rightTime)
      : left.entry.timestamp.compareTo(right.entry.timestamp);
  if (byTime != 0) return byTime;

  final leftMessageIndex = left.originalMessageIndex;
  final rightMessageIndex = right.originalMessageIndex;
  if (leftMessageIndex != null && rightMessageIndex != null) {
    return leftMessageIndex.compareTo(rightMessageIndex);
  }
  if (leftMessageIndex != null) return -1;
  if (rightMessageIndex != null) return 1;
  return left.entry.stableId.compareTo(right.entry.stableId);
}

/// Loads a single page of messages for a conversation.
///
/// Returns at most [pageSize] messages in chronological order.
/// When [beforeTimestamp] is null, returns the most recent page.
/// When provided, returns messages older than that cursor.
Future<List<ConversationMessage>> loadConversationPage({
  required MessageRepository messageRepo,
  required String contactPeerId,
  int pageSize = 50,
  String? beforeTimestamp,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_LOAD_PAGE_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
      'pageSize': pageSize,
      'hasCursor': beforeTimestamp != null,
    },
  );

  final messages = await messageRepo.getMessagesPage(
    contactPeerId,
    limit: pageSize,
    beforeTimestamp: beforeTimestamp,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_LOAD_PAGE_SUCCESS',
    details: {'count': messages.length},
  );

  return _attachMedia(messages, mediaAttachmentRepo, mediaFileManager);
}

/// Batch-loads media attachments and attaches them to messages.
///
/// When [mediaFileManager] is provided, relative paths stored in the DB
/// are resolved to absolute paths for display.
Future<List<ConversationMessage>> _attachMedia(
  List<ConversationMessage> messages,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
) async {
  if (messages.isEmpty) return messages;

  final projectableMessages = messages
      .where((message) => !message.mustClearTransientMedia)
      .toList(growable: false);
  if (mediaAttachmentRepo == null || projectableMessages.isEmpty) {
    return messages
        .map(
          (message) => message.mustClearTransientMedia
              ? message.copyWith(media: const <MediaAttachment>[])
              : message,
        )
        .toList();
  }

  final ids = projectableMessages.map((message) => message.id).toList();
  final mediaMap = await mediaAttachmentRepo.getAttachmentsForMessages(
    ids,
    owner: MediaOwnerLane.direct,
  );
  if (mediaMap.isEmpty) {
    return messages
        .map(
          (message) => message.mustClearTransientMedia
              ? message.copyWith(media: const <MediaAttachment>[])
              : message,
        )
        .toList();
  }

  // Resolve relative paths to absolute for display
  final resolvedMap = <String, List<MediaAttachment>>{};
  for (final entry in mediaMap.entries) {
    final resolved = <MediaAttachment>[];
    for (final attachment in entry.value) {
      if (attachment.localPath != null && mediaFileManager != null) {
        // 162 (db-persistence-7): resolve via the startup-seeded synchronous
        // twin — pure string work over the cached docs dir, dropping the
        // per-attachment `path_provider` channel hop that serialized this loop.
        final absolutePath = MediaFileManager.resolveStoredPathSync(
          attachment.localPath!,
        );
        resolved.add(attachment.copyWith(localPath: absolutePath));
      } else {
        resolved.add(attachment);
      }
    }
    resolvedMap[entry.key] = resolved;
  }

  return messages
      .map(
        (message) => message.copyWith(
          media: message.mustClearTransientMedia
              ? const <MediaAttachment>[]
              : resolvedMap[message.id] ?? const <MediaAttachment>[],
        ),
      )
      .toList();
}
