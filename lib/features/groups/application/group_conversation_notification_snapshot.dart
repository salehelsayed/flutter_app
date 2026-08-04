import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/push/application/private_media_notification_body.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';

Future<ConversationNotificationSnapshot?>
loadGroupConversationNotificationSnapshot({
  required GroupMessageRepository messageRepository,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepository,
  GroupPrivateMediaAvailability privateMediaAvailability =
      productionGroupPrivateMediaAvailability,
  PendingConversationNotificationOverlayStore? pendingNotificationOverlay,
}) async {
  const pageSize = 200;
  var offset = 0;
  final eligible = <GroupMessage>[];
  while (true) {
    final page = await messageRepository.getMessagesPage(
      groupId,
      limit: pageSize,
      offset: offset,
    );
    for (final message in page) {
      final activePrivate =
          !message.privateMediaPolicy.isPrivate ||
          (message.mediaConsumedAt == null && message.mediaExpiredAt == null);
      if (message.groupId == groupId &&
          message.isIncoming &&
          message.readAt == null &&
          !isGroupRemovalCutoffMessageId(message.id) &&
          activePrivate &&
          privateMediaAvailability.allowsMediaDerivatives(
            message.privateMediaPolicy,
          )) {
        eligible.add(message);
      }
    }
    if (page.length < pageSize) break;
    offset += page.length;
  }
  final canonical = await buildGroupConversationNotificationSnapshot(
    messages: eligible,
    groupId: groupId,
    loadAttachments: mediaAttachmentRepository == null
        ? null
        : (messageId) => mediaAttachmentRepository.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.group,
          ),
    privateMediaAvailability: privateMediaAvailability,
  );
  return pendingNotificationOverlay == null
      ? canonical
      : pendingNotificationOverlay.project(
          conversationKey: 'group:$groupId',
          canonicalSnapshot: canonical,
        );
}

/// Pure canonical snapshot builder shared by live and headless producers.
Future<ConversationNotificationSnapshot?>
buildGroupConversationNotificationSnapshot({
  required Iterable<GroupMessage> messages,
  required String groupId,
  Future<List<MediaAttachment>> Function(String messageId)? loadAttachments,
  GroupPrivateMediaAvailability privateMediaAvailability =
      productionGroupPrivateMediaAvailability,
}) async {
  final eligible = messages
      .where((message) {
        final activePrivate =
            !message.privateMediaPolicy.isPrivate ||
            (message.mediaConsumedAt == null && message.mediaExpiredAt == null);
        return message.groupId == groupId &&
            message.isIncoming &&
            message.readAt == null &&
            !isGroupRemovalCutoffMessageId(message.id) &&
            activePrivate &&
            privateMediaAvailability.allowsMediaDerivatives(
              message.privateMediaPolicy,
            );
      })
      .toList(growable: false);
  if (eligible.isEmpty) return null;
  eligible.sort((left, right) {
    final timeOrder = left.timestamp.compareTo(right.timestamp);
    return timeOrder != 0 ? timeOrder : left.id.compareTo(right.id);
  });
  final selected = eligible
      .skip(eligible.length > 5 ? eligible.length - 5 : 0)
      .toList(growable: false);
  final lines = <String>[];
  final orderedHistory = <ConversationNotificationHistoryEntry>[];
  for (final message in selected) {
    final isPrivate = message.privateMediaPolicy.isPrivate;
    final attachments = isPrivate || loadAttachments == null
        ? const <MediaAttachment>[]
        : await loadAttachments(message.id);
    if (isPrivate) {
      final line = localizedGroupPrivateMediaNotificationBody();
      lines.add(line);
      orderedHistory.add(
        ConversationNotificationHistoryEntry(
          eventId: message.id,
          line: line,
          occurredAtMicros: message.timestamp.toUtc().microsecondsSinceEpoch,
        ),
      );
      continue;
    }
    final body = notificationBodyForMessage(message.text, attachments);
    final sender = message.senderUsername?.trim() ?? '';
    final line = sender.isEmpty ? body : '$sender: $body';
    lines.add(line);
    orderedHistory.add(
      ConversationNotificationHistoryEntry(
        eventId: message.id,
        line: line,
        occurredAtMicros: message.timestamp.toUtc().microsecondsSinceEpoch,
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
