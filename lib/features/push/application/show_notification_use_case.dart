import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

typedef ConsumeRecentRemoteNotificationAnnouncement =
    Future<bool> Function({required String payload, String? messageId});

/// Returns the notification body text for a message.
///
/// If [text] is non-empty it is returned as-is (caption-first rule).
/// If [text] is empty the body is derived from the first attachment's
/// [MediaAttachment.mediaType]: image -> "Photo", video -> "Video",
/// audio -> "Voice message", file -> "File", mixed/unknown -> "Media".
/// Falls back to "Message" when text is empty and there are no attachments.
String notificationBodyForMessage(String text, List<MediaAttachment> media) {
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) return trimmed;
  if (media.isEmpty) return 'Message';

  final firstType = media.first.mediaType;
  final allSameType = media.every((a) => a.mediaType == firstType);
  if (!allSameType) return 'Media';

  return switch (firstType) {
    'image' => 'Photo',
    'video' => 'Video',
    'audio' => 'Voice message',
    'file' => 'File',
    _ => 'Media',
  };
}

/// Shows a local notification for an incoming message unless the user
/// is currently viewing that conversation in the foreground.
///
/// Suppression logic:
///   - App resumed AND viewing sender's conversation -> suppress
///   - Otherwise -> show notification
Future<void> maybeShowNotification({
  required NotificationService notificationService,
  required ActiveConversationTracker conversationTracker,
  required AppLifecycleState Function() getAppLifecycleState,
  required String contactPeerId,
  String? routePayload,
  required String senderUsername,
  required String messageText,
  bool suppressNotification = false,
  String? messageId,
  ConsumeRecentRemoteNotificationAnnouncement?
  consumeRecentRemoteNotificationAnnouncement,
  Duration backgroundDuplicateGuardDelay = const Duration(seconds: 2),
}) async {
  if (suppressNotification) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_SUPPRESSED',
      details: {
        'reason': 'recovery_replay',
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
      },
    );
    return;
  }

  final lifecycleState = getAppLifecycleState();
  final isViewingConversation = conversationTracker.isViewing(contactPeerId);

  if (lifecycleState == AppLifecycleState.resumed && isViewingConversation) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_SUPPRESSED',
      details: {
        'reason': 'viewing_conversation',
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
      },
    );
    return;
  }

  if (lifecycleState != AppLifecycleState.resumed &&
      consumeRecentRemoteNotificationAnnouncement != null) {
    if (backgroundDuplicateGuardDelay > Duration.zero) {
      await Future<void>.delayed(backgroundDuplicateGuardDelay);
    }

    final shouldSuppress = await consumeRecentRemoteNotificationAnnouncement(
      payload: contactPeerId,
      messageId: messageId,
    );
    if (shouldSuppress) {
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_SUPPRESSED',
        details: {
          'reason': 'recent_remote_push',
          'contactPeerId': contactPeerId.length > 10
              ? contactPeerId.substring(0, 10)
              : contactPeerId,
        },
      );
      return;
    }
  }

  await notificationService.showMessageNotification(
    contactPeerId: contactPeerId,
    senderUsername: senderUsername,
    messageText: messageText,
    payload: routePayload,
  );
}
