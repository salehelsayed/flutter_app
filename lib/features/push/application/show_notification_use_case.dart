import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';
import 'package:flutter_app/features/push/application/private_media_notification_body.dart';

typedef ConsumeRecentRemoteNotificationAnnouncement =
    Future<bool> Function({required String payload, String? messageId});

/// 118 Phase 2: writes a dedup marker after a LIVE (foreground/resumed) message
/// is shown, so a late FCM background isolate that fires for the same messageId
/// consumes-and-suppresses instead of double-alerting (live-wins handshake).
typedef MarkRecentRemoteNotificationAnnouncement =
    Future<void> Function({required String payload, String? messageId});
typedef ResolveDurableNotificationCoordinator =
    Future<DurableNotificationToneLease?> Function();

/// Returns the notification body text for a message.
///
/// If [text] is non-empty it is returned as-is (caption-first rule).
/// If [text] is empty the body is derived from the first attachment's
/// [MediaAttachment.mediaType]: image -> "Photo", video -> "Video",
/// audio -> "Voice message", file -> "File", mixed/unknown -> "Media".
/// Falls back to "Message" when text is empty and there are no attachments.
String notificationBodyForMessage(
  String text,
  List<MediaAttachment> media, {
  PrivateMediaPolicy privateMediaPolicy = const PrivateMediaPolicy.ordinary(),
  Locale? locale,
}) {
  if (privateMediaPolicy.requiresRedaction) {
    return localizedPrivateMediaNotificationBody(locale: locale);
  }
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) return trimmed;
  if (media.isEmpty) return localizedNotificationMessage(locale: locale);

  final firstType = media.first.mediaType;
  final allSameType = media.every((a) => a.mediaType == firstType);
  if (!allSameType) return localizedNotificationMedia(locale: locale);

  return switch (firstType) {
    'image' =>
      media.every((a) => a.isAnimated)
          ? localizedNotificationGif(locale: locale)
          : localizedNotificationPhoto(1, locale: locale),
    'video' => localizedNotificationVideo(1, locale: locale),
    'audio' => localizedNotificationVoiceMessage(locale: locale),
    'file' => localizedNotificationFile(1, locale: locale),
    _ => localizedNotificationMedia(locale: locale),
  };
}

/// Shows a local notification for an incoming message unless the user
/// is currently viewing that conversation in the foreground.
///
/// Suppression logic:
///   - App resumed AND viewing sender's conversation -> suppress
///   - Same message was already announced by a recent remote push -> suppress
///   - Otherwise -> show notification
Future<NotificationPresentationResult> maybeShowNotification({
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
  String? notificationEventIdentity,
  ConsumeRecentRemoteNotificationAnnouncement?
  consumeRecentRemoteNotificationAnnouncement,
  MarkRecentRemoteNotificationAnnouncement?
  markRecentRemoteNotificationAnnouncement,
  NotificationToneTracker? toneTracker,
  ResolveDurableNotificationCoordinator? durableNotificationCoordinatorResolver,
  String notificationEventType = 'new_message',
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
    return NotificationPresentationResult.terminalSuppressed;
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
    return NotificationPresentationResult.terminalSuppressed;
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
      return NotificationPresentationResult.terminalSuppressed;
    }
  }

  DurableNotificationToneLease? durableNotificationCoordinator;
  try {
    durableNotificationCoordinator =
        await durableNotificationCoordinatorResolver?.call();
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_CLAIM_STORAGE_UNAVAILABLE',
      details: {'type': notificationEventType, 'error': error.toString()},
    );
  }
  DurableNotificationEventClaim? messageClaim;
  var claimStorageFailedOpen = false;
  final eventIdentity = notificationEventIdentity ?? messageId;
  if (durableNotificationCoordinator != null && eventIdentity != null) {
    try {
      final acquisition = await durableNotificationCoordinator
          .acquireMessageEventClaim(
            type: notificationEventType,
            eventIdentity: eventIdentity,
          );
      messageClaim = acquisition.claim;
      if (acquisition.disposition ==
          DurableNotificationClaimDisposition.pending) {
        emitFlowEvent(
          layer: 'FL',
          event: 'NOTIFICATION_DEFERRED',
          details: {
            'reason': 'message_event_claim_pending',
            'type': notificationEventType,
          },
        );
        return NotificationPresentationResult.contendedRetryable;
      }
      if (acquisition.disposition ==
          DurableNotificationClaimDisposition.committedOrUnavailable) {
        emitFlowEvent(
          layer: 'FL',
          event: 'NOTIFICATION_SUPPRESSED',
          details: {
            'reason': 'message_event_already_claimed',
            'type': notificationEventType,
            'contactPeerId': contactPeerId.length > 10
                ? contactPeerId.substring(0, 10)
                : contactPeerId,
          },
        );
        return NotificationPresentationResult.terminalSuppressed;
      }
    } catch (error) {
      // Storage/locking failure is the sole fail-open case. There is no durable
      // ownership result to honor, so retain the in-memory tone fallback.
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_CLAIM_STORAGE_UNAVAILABLE',
        details: {'type': notificationEventType, 'error': error.toString()},
      );
      durableNotificationCoordinator = null;
      claimStorageFailedOpen = true;
    }
    assert(messageClaim != null || claimStorageFailedOpen);
  }

  DurableNotificationToneReservation? toneReservation;

  Future<void> releaseToneReservationAfterDisplayFailure() async {
    final reservation = toneReservation;
    if (reservation == null) return;
    try {
      final released = await reservation.release();
      if (released) return;
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_TONE_RESERVATION_RELEASE_FAILED',
        details: {'type': notificationEventType},
      );
    } catch (releaseError) {
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_TONE_RESERVATION_RELEASE_FAILED',
        details: {
          'type': notificationEventType,
          'error': releaseError.toString(),
        },
      );
    }
  }

  Future<void> releaseMessageClaimAfterDisplayFailure() async {
    final claim = messageClaim;
    if (claim == null) return;
    try {
      final released = await claim.release();
      if (released) return;
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_CLAIM_RELEASE_FAILED',
        details: {'type': notificationEventType},
      );
    } catch (releaseError) {
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_CLAIM_RELEASE_FAILED',
        details: {
          'type': notificationEventType,
          'error': releaseError.toString(),
        },
      );
    }
  }

  // 118 Phase 4: consult the tone tracker ONLY after every suppression gate has
  // passed. The durable path reserves a token-owned audible right here, but
  // starts its window only after the OS show succeeds below.
  try {
    bool inMemorySilentDecision() =>
        toneTracker != null && !toneTracker.shouldPlayTone(conversationKey);

    late final bool silent;
    if (durableNotificationCoordinator != null) {
      try {
        toneReservation = await durableNotificationCoordinator.reserveTone(
          conversationKey,
        );
        silent = toneReservation == null;
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'NOTIFICATION_TONE_STORAGE_UNAVAILABLE',
          details: {'type': notificationEventType, 'error': error.toString()},
        );
        silent = inMemorySilentDecision();
      }
    } else {
      silent = inMemorySilentDecision();
    }

    await notificationService.showMessageNotification(
      contactPeerId: contactPeerId,
      senderUsername: senderUsername,
      messageText: messageText,
      payload: routePayload,
      silent: silent,
      contentKind: !conversationKey.startsWith('group:')
          ? null
          : switch (notificationEventType) {
              'group_message' => ConversationNotificationContentKind.message,
              'message_reaction' =>
                ConversationNotificationContentKind.reaction,
              _ => null,
            },
      contentEventIdentity: eventIdentity,
    );
  } catch (error, stackTrace) {
    // No OS card was published. Release both provisional owners independently;
    // one storage failure must never prevent the other cleanup attempt.
    await releaseToneReservationAfterDisplayFailure();
    await releaseMessageClaimAfterDisplayFailure();
    Error.throwWithStackTrace(error, stackTrace);
  }

  var toneCommitted = true;
  if (toneReservation != null) {
    try {
      toneCommitted = await toneReservation.commit();
    } catch (_) {
      toneCommitted = false;
    }
  }
  if (!toneCommitted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_TONE_RESERVATION_COMMIT_FAILED',
      details: {
        'type': notificationEventType,
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
      },
    );
  }

  var claimCommitted = true;
  if (messageClaim != null) {
    try {
      claimCommitted = await messageClaim.commit();
    } catch (_) {
      claimCommitted = false;
    }
  }
  if (!claimCommitted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_CLAIM_COMMIT_FAILED',
      details: {
        'type': notificationEventType,
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
      },
    );
  }

  // Once showMessageNotification returns, the OS-visible side effect has
  // happened. Commit failures and all later bookkeeping failures deliberately
  // retain both owners fail-closed; releasing here could alert twice.

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
  return NotificationPresentationResult.shown;
}
