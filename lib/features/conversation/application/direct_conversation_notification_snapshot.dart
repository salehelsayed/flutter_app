import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';

/// Rebuilds direct notification history from current canonical unread rows.
/// No history copy is persisted: every producer/reconciler sees read, delete,
/// and private-media lifecycle changes made before projection.
Future<ConversationNotificationSnapshot?>
loadDirectConversationNotificationSnapshot({
  required MessageRepository messageRepository,
  required String contactPeerId,
  MediaAttachmentRepository? mediaAttachmentRepository,
  PendingConversationNotificationOverlayStore? pendingNotificationOverlay,
}) async {
  final messages = await messageRepository.getMessagesForContact(contactPeerId);
  final canonical = await buildDirectConversationNotificationSnapshot(
    messages: messages,
    contactPeerId: contactPeerId,
    loadAttachments: mediaAttachmentRepository == null
        ? null
        : (messageId) => mediaAttachmentRepository.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.direct,
          ),
  );
  return pendingNotificationOverlay == null
      ? canonical
      : pendingNotificationOverlay.project(
          conversationKey: contactPeerId,
          canonicalSnapshot: canonical,
        );
}

/// Pure canonical snapshot builder shared by live and headless producers.
/// Callers supply only lane-qualified attachment rows from their own storage
/// boundary; private/terminal messages are filtered before that callback runs.
Future<ConversationNotificationSnapshot?>
buildDirectConversationNotificationSnapshot({
  required Iterable<ConversationMessage> messages,
  required String contactPeerId,
  Future<List<MediaAttachment>> Function(String messageId)? loadAttachments,
}) async {
  final eligible =
      messages
          .where(
            (message) =>
                message.contactPeerId == contactPeerId &&
                message.isIncoming &&
                message.readAt == null &&
                !message.isDeleted &&
                !message.isHidden &&
                !message.privateMediaState.isTerminal,
          )
          .toList(growable: false)
        ..sort((left, right) {
          final leftAt = left.parsedTimestamp;
          final rightAt = right.parsedTimestamp;
          int timeOrder;
          if (leftAt != null && rightAt != null) {
            timeOrder = leftAt.compareTo(rightAt);
          } else if (leftAt == null && rightAt == null) {
            timeOrder = left.timestamp.compareTo(right.timestamp);
          } else {
            timeOrder = leftAt == null ? -1 : 1;
          }
          return timeOrder != 0 ? timeOrder : left.id.compareTo(right.id);
        });
  if (eligible.isEmpty) return null;

  final selected = eligible
      .skip(eligible.length > 5 ? eligible.length - 5 : 0)
      .toList(growable: false);
  final lines = <String>[];
  final orderedHistory = <ConversationNotificationHistoryEntry>[];
  var fallbackOrder = 0;
  for (final message in selected) {
    final attachments =
        message.privateMediaPolicy.requiresRedaction || loadAttachments == null
        ? const <MediaAttachment>[]
        : await loadAttachments(message.id);
    final line = notificationBodyForMessage(
      message.text,
      attachments,
      privateMediaPolicy: message.privateMediaPolicy,
    );
    lines.add(line);
    final occurredAt = message.parsedTimestamp;
    orderedHistory.add(
      ConversationNotificationHistoryEntry(
        eventId: message.id,
        line: line,
        occurredAtMicros:
            occurredAt?.toUtc().microsecondsSinceEpoch ?? fallbackOrder++,
      ),
    );
  }
  return ConversationNotificationSnapshot(
    historyLines: lines,
    totalUnreadMessageCount: eligible.length,
    canonicalEventIds: eligible.map((message) => message.id),
    orderedHistory: orderedHistory,
  );
}
