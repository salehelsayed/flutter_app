import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

typedef ConsumeRecentRemoteNotificationAnnouncement =
    Future<bool> Function({required String payload, String? messageId});

/// 118 Phase 2: writes a dedup marker after a LIVE (foreground/resumed) message
/// is shown, so a late FCM background isolate that fires for the same messageId
/// consumes-and-suppresses instead of double-alerting (live-wins handshake).
typedef MarkRecentRemoteNotificationAnnouncement =
    Future<void> Function({required String payload, String? messageId});

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
    'image' => media.every((a) => a.isAnimated) ? 'GIF' : 'Photo',
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
///   - Same message was already announced by a recent remote push -> suppress
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
  String suppressionReason = 'recovery_replay',
  String? messageId,
  ConsumeRecentRemoteNotificationAnnouncement?
  consumeRecentRemoteNotificationAnnouncement,
  MarkRecentRemoteNotificationAnnouncement?
  markRecentRemoteNotificationAnnouncement,
  NotificationToneTracker? toneTracker,
  Duration backgroundDuplicateGuardDelay = const Duration(seconds: 2),
}) async {
  // 118 Phase 4: the per-conversation tone window and the viewing-suppression
  // gate must use the SAME conversation identity. Normalize once.
  final conversationKey = ActiveConversationTracker.normalizeActiveKey(
    contactPeerId,
  );
  if (suppressNotification) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_SUPPRESSED',
      details: {
        'reason': suppressionReason,
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
      },
    );
    return;
  }

  final lifecycleState = getAppLifecycleState();
  final isViewingConversation =
      conversationTracker.isViewing(contactPeerId) ||
      (routePayload != null && conversationTracker.isViewing(routePayload));

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

  if (consumeRecentRemoteNotificationAnnouncement != null) {
    if (lifecycleState != AppLifecycleState.resumed &&
        backgroundDuplicateGuardDelay > Duration.zero) {
      await Future<void>.delayed(backgroundDuplicateGuardDelay);
    }

    final remoteAnnouncementPayload = routePayload ?? contactPeerId;
    final shouldSuppress = await consumeRecentRemoteNotificationAnnouncement(
      payload: remoteAnnouncementPayload,
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

  // 118 Phase 4: consult the tone tracker ONLY after every suppression gate has
  // passed — a muted/deduped/viewed message never touches shouldPlayTone (so it
  // never consumes the conversation's tone window). The first message after a
  // quiet window sounds; the rest update silently. Keyed on the normalized
  // conversation, never on the per-message routePayload.
  final silent =
      toneTracker != null && !toneTracker.shouldPlayTone(conversationKey);

  await notificationService.showMessageNotification(
    contactPeerId: contactPeerId,
    senderUsername: senderUsername,
    messageText: messageText,
    payload: routePayload,
    silent: silent,
  );

  // 118 Phase 2 (live-wins handshake): record a dedup marker for this exact
  // message so a LATE FCM background isolate firing for the same messageId
  // consumes-and-suppresses instead of showing a second notification. The
  // consume-on-read gate only removes markers — without writing one here the
  // live-first ordering (live shows, then a late FCM finds nothing to consume)
  // would double-alert. Gated on messageId so it never over-suppresses an
  // unrelated bare-payload message.
  if (markRecentRemoteNotificationAnnouncement != null && messageId != null) {
    await markRecentRemoteNotificationAnnouncement(
      payload: routePayload ?? contactPeerId,
      messageId: messageId,
    );
  }
}
