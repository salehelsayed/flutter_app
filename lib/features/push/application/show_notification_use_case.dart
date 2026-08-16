import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/android_recovery_alert_disposition.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/ios_mailbox_alert_silent_replay_context.dart';
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
typedef LoadConversationNotificationSnapshot =
    Future<ConversationNotificationSnapshot?> Function();

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
  required AppVisibilitySuppressionReader appVisibility,
  required String contactPeerId,
  String? routePayload,
  required String senderUsername,
  required String messageText,
  bool suppressNotification = false,
  bool forceSilent = false,
  String suppressionReason = 'recovery_replay',
  String? messageId,
  String? notificationEventIdentity,
  ConsumeRecentRemoteNotificationAnnouncement?
  consumeRecentRemoteNotificationAnnouncement,
  MarkRecentRemoteNotificationAnnouncement?
  markRecentRemoteNotificationAnnouncement,
  NotificationToneTracker? toneTracker,
  ResolveDurableNotificationCoordinator? durableNotificationCoordinatorResolver,
  LoadConversationNotificationSnapshot? loadConversationNotificationSnapshot,
  String notificationEventType = 'new_message',
  Duration backgroundDuplicateGuardDelay = const Duration(seconds: 2),
  DurableLocalNotificationEffectContext? durableEffectContext,
}) async {
  // The Android recovery disposition is consulted at the same decision the
  // iOS mailbox replay context uses: it may alter only the sound flag, and
  // only inside the one installed headless recovery graph. A fixed-only
  // marker reads false and keeps normal exact tone arbitration.
  final forceSilentEffect =
      forceSilent ||
      isIosMailboxAlertSilentReplayContext ||
      await readAmbientAndroidRecoveryGenericAlertAmbiguity();
  final visibilityIdentity = AppVisibilityConversationIdentity.tryParse(
    lane: contactPeerId.trim().startsWith('group:')
        ? AppVisibilityConversationLane.group
        : AppVisibilityConversationLane.direct,
    value: contactPeerId,
  );
  // The tone key and visibility decision share the same canonical identity.
  // Malformed identities remain notification-eligible and retain a bounded
  // trimmed debounce key rather than consulting a legacy tracker.
  final conversationKey =
      visibilityIdentity?.normalizedValue ?? contactPeerId.trim();
  if (suppressNotification) {
    emitFlowEvent(
      layer: 'FL',
      event: durableEffectContext == null
          ? 'NOTIFICATION_SUPPRESSED'
          : 'NOTIFICATION_DEFERRED',
      details: {'reason': suppressionReason},
    );
    return durableEffectContext == null
        ? NotificationPresentationResult.terminalWithoutOutcome
        : NotificationPresentationResult.contendedRetryable;
  }

  final visibility = await appVisibility.evaluate(visibilityIdentity);
  if (visibility.maySuppress && durableEffectContext == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_SUPPRESSED',
      details: const {'reason': 'fresh_visible_conversation'},
    );
    // N04/N05/N11 own the final same-chat/read effect authority. Until that
    // shared boundary exists this is terminal, but it cannot mint an outcome.
    return NotificationPresentationResult.terminalWithoutOutcome;
  }

  if (consumeRecentRemoteNotificationAnnouncement != null) {
    if (!visibility.isForegroundActive &&
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
        event: durableEffectContext == null
            ? 'NOTIFICATION_SUPPRESSED'
            : 'NOTIFICATION_LEGACY_DEDUPE_RECONCILE',
        details: {
          'reason': 'recent_remote_push',
          if (durableEffectContext == null)
            'contactPeerId': contactPeerId.length > 10
                ? contactPeerId.substring(0, 10)
                : contactPeerId,
        },
      );
      if (durableEffectContext == null) {
        return NotificationPresentationResult.terminalWithoutOutcome;
      }
      // The legacy marker is not durable final-effect authority. An anchored
      // attempt continues into the ledger, where an already-terminal sibling
      // replays its receipt and an in-flight sibling remains retryable.
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
          event: durableEffectContext == null
              ? 'NOTIFICATION_SUPPRESSED'
              : 'NOTIFICATION_LEGACY_CLAIM_RECONCILE',
          details: {
            'reason': 'message_event_already_claimed',
            'type': notificationEventType,
            if (durableEffectContext == null)
              'contactPeerId': contactPeerId.length > 10
                  ? contactPeerId.substring(0, 10)
                  : contactPeerId,
          },
        );
        if (durableEffectContext == null) {
          return NotificationPresentationResult.terminalWithoutOutcome;
        }
        // The exact ledger, not the legacy event-claim projection, decides
        // whether this is a terminal replay or an ambiguous in-flight owner.
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
    assert(
      messageClaim != null ||
          claimStorageFailedOpen ||
          durableEffectContext != null,
    );
  }

  DurableNotificationToneReservation? toneReservation;
  DurableNotificationClaimedPublicationResult? claimedPublication;
  DurableNotificationTonePublicationResult? tonePublication;
  DurableLocalNotificationEffectResult? durableEffectResult;

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
  // starts its window only after the native publication callback returns below.
  try {
    bool inMemorySilentDecision() =>
        toneTracker != null && !toneTracker.shouldPlayTone(conversationKey);

    late final bool silent;
    if (forceSilentEffect) {
      silent = true;
    } else if (durableNotificationCoordinator != null) {
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

    final snapshot = await loadConversationNotificationSnapshot?.call();
    final contentKind = switch (notificationEventType) {
      'new_message' ||
      'group_message' => ConversationNotificationContentKind.message,
      'message_reaction' => ConversationNotificationContentKind.reaction,
      _ => null,
    };

    Future<bool> publishAtNativeBoundary(
      NativeMessageNotificationShow showNative,
      AuthorizeDurableLocalNotificationNativeEntry authorize,
    ) async {
      Future<void> publishWithExactToneOwner() async {
        final reservation = toneReservation;
        if (reservation == null) {
          if (!await authorize()) {
            throw const DurableNotificationPublicationNotAuthorizedException();
          }
          await showNative(silent: silent);
          return;
        }
        tonePublication = await reservation.publishAndCommit(() async {
          if (!await authorize()) {
            throw const DurableNotificationPublicationNotAuthorizedException();
          }
          await showNative(silent: false);
        });
        if (!tonePublication!.publishedAudibly) {
          if (!await authorize()) {
            throw const DurableNotificationPublicationNotAuthorizedException();
          }
          await showNative(silent: true);
        }
      }

      try {
        claimedPublication = messageClaim == null
            ? null
            : await messageClaim.publishAndCommit(publishWithExactToneOwner);
        if (claimedPublication == null) {
          await publishWithExactToneOwner();
        } else if (!claimedPublication!.published) {
          return false;
        }
        return true;
      } on DurableNotificationPublicationNotAuthorizedException {
        return false;
      }
    }

    Future<void> publishLegacyAtNativeBoundary(
      NativeMessageNotificationShow showNative,
    ) async {
      final entered = await publishAtNativeBoundary(
        showNative,
        () async => true,
      );
      if (!entered) {
        throw const _NotificationClaimOwnershipLostBeforeShow();
      }
    }

    if (durableEffectContext != null) {
      if (visibilityIdentity == null ||
          contentKind == null ||
          eventIdentity == null ||
          notificationService
              is! MessageNotificationDurableFinalEffectBoundary) {
        await releaseToneReservationAfterDisplayFailure();
        await releaseMessageClaimAfterDisplayFailure();
        return NotificationPresentationResult.contendedRetryable;
      }
      final durableBoundary =
          notificationService as MessageNotificationDurableFinalEffectBoundary;
      durableEffectResult = await durableBoundary
          .showMessageNotificationWithDurableFinalEffect(
            contactPeerId: contactPeerId,
            senderUsername: senderUsername,
            messageText: messageText,
            payload: routePayload,
            silent: silent,
            contentKind: contentKind,
            contentEventIdentity: eventIdentity,
            snapshot: snapshot,
            durableEffectContext: durableEffectContext,
            finalVisibility: appVisibility,
            conversationIdentity: visibilityIdentity,
            publishNative: publishAtNativeBoundary,
          );
    } else if (defaultTargetPlatform == TargetPlatform.android &&
        notificationService is MessageNotificationNativePublicationBoundary) {
      final publicationBoundary =
          notificationService as MessageNotificationNativePublicationBoundary;
      await publicationBoundary.showMessageNotificationAtNativeBoundary(
        contactPeerId: contactPeerId,
        senderUsername: senderUsername,
        messageText: messageText,
        payload: routePayload,
        silent: silent,
        // Direct and group conversations both reuse one stable OS-card id.
        // Typed generation metadata makes exact read/reconciliation CAS safe.
        contentKind: contentKind,
        contentEventIdentity: eventIdentity,
        snapshot: snapshot,
        publishNative: publishLegacyAtNativeBoundary,
      );
    } else {
      Future<void> fallbackNativeShow({required bool silent}) =>
          notificationService.showMessageNotification(
            contactPeerId: contactPeerId,
            senderUsername: senderUsername,
            messageText: messageText,
            payload: routePayload,
            silent: silent,
            contentKind: contentKind,
            contentEventIdentity: eventIdentity,
            snapshot: snapshot,
          );
      await publishLegacyAtNativeBoundary(fallbackNativeShow);
    }

    final durableReceipt = durableEffectResult?.receipt;
    if (durableReceipt != null) {
      final handoffCompleted = await _notifyDurableEffectTerminal(
        context: durableEffectContext!,
        receipt: durableReceipt,
        notificationEventType: notificationEventType,
      );
      if (handoffCompleted &&
          durableEffectContext.terminalObserverCompletesSqlHandoff &&
          notificationService
              is MessageNotificationDurablePostHandoffReconciliation) {
        await (notificationService
                as MessageNotificationDurablePostHandoffReconciliation)
            .notifyDurableEffectHandoffComplete(durableReceipt);
      }
    }

    if (durableEffectResult != null &&
        durableEffectResult.disposition !=
            DurableLocalNotificationEffectDisposition.osPosted) {
      if (durableEffectResult.currentNativeEntryAttempted &&
          !durableEffectResult.currentNativeEntryWasSilentRepair) {
        // Publication ownership is intentionally detached: the ledger retains
        // PUBLISHING and exact marker custody for recovery.
        toneReservation = null;
        messageClaim = null;
      } else {
        await releaseToneReservationAfterDisplayFailure();
        await releaseMessageClaimAfterDisplayFailure();
      }
      return switch (durableEffectResult.disposition) {
        DurableLocalNotificationEffectDisposition.inChat =>
          NotificationPresentationResult.inChat,
        DurableLocalNotificationEffectDisposition.suppressedPolicy =>
          NotificationPresentationResult.suppressedPolicy,
        DurableLocalNotificationEffectDisposition.cancelled =>
          NotificationPresentationResult.terminalWithoutOutcome,
        DurableLocalNotificationEffectDisposition.retryable ||
        DurableLocalNotificationEffectDisposition.ambiguous =>
          NotificationPresentationResult.contendedRetryable,
        DurableLocalNotificationEffectDisposition.osPosted =>
          NotificationPresentationResult.osPosted,
      };
    }
    if (durableEffectResult != null &&
        durableEffectResult.disposition ==
            DurableLocalNotificationEffectDisposition.osPosted &&
        (!durableEffectResult.currentNativeEntryAttempted ||
            durableEffectResult.currentNativeEntryWasSilentRepair)) {
      // A terminal/active-inventory replay or force-silent repair owns no
      // fresh audible/event publication. Release newly prepared legacy owners
      // and skip their commit bookkeeping.
      await releaseToneReservationAfterDisplayFailure();
      await releaseMessageClaimAfterDisplayFailure();
      return NotificationPresentationResult.osPosted;
    }
  } on _NotificationClaimOwnershipLostBeforeShow {
    await releaseToneReservationAfterDisplayFailure();
    await releaseMessageClaimAfterDisplayFailure();
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_DEFERRED',
      details: {
        'reason': 'message_event_claim_ownership_lost_before_show',
        'type': notificationEventType,
      },
    );
    return NotificationPresentationResult.contendedRetryable;
  } on DurableNotificationPublicationAttemptedException catch (
    error,
    stackTrace
  ) {
    // Android may already have accepted the notification even though the
    // method channel failed. A tone owner that never entered its audible native
    // callback remains safely releasable; detach all effect-unknown
    // `publishing` owners fail-closed.
    if (tonePublication?.publishedAudibly == false) {
      await releaseToneReservationAfterDisplayFailure();
    }
    toneReservation = null;
    messageClaim = null;
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_PUBLICATION_OUTCOME_UNKNOWN',
      details: {'type': notificationEventType, 'errorType': error.errorType},
    );
    Error.throwWithStackTrace(error, stackTrace);
  } catch (error, stackTrace) {
    // On Android this path did not enter the native publication callback.
    // Release both provisional owners independently; one storage failure must
    // never prevent the other cleanup attempt. Non-Android keeps its legacy
    // error/release behavior.
    await releaseToneReservationAfterDisplayFailure();
    await releaseMessageClaimAfterDisplayFailure();
    Error.throwWithStackTrace(error, stackTrace);
  }

  final toneCommitted =
      toneReservation == null ||
      !tonePublication!.publishedAudibly ||
      tonePublication!.toneCommitted;
  if (!toneCommitted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_TONE_RESERVATION_COMMIT_FAILED',
      details: {
        'type': notificationEventType,
        if (durableEffectContext == null)
          'contactPeerId': contactPeerId.length > 10
              ? contactPeerId.substring(0, 10)
              : contactPeerId,
      },
    );
  }

  final claimCommitted = claimedPublication?.claimCommitted ?? true;
  if (!claimCommitted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_CLAIM_COMMIT_FAILED',
      details: {
        'type': notificationEventType,
        if (durableEffectContext == null)
          'contactPeerId': contactPeerId.length > 10
              ? contactPeerId.substring(0, 10)
              : contactPeerId,
      },
    );
  }
  // Once the native callback returns, Android has acknowledged the show call.
  // Commit failures and all later bookkeeping failures deliberately retain
  // both owners fail-closed; releasing here could alert twice.

  // 118 Phase 2 (live-wins handshake): record a dedup marker for this exact
  // message so a LATE FCM background isolate firing for the same messageId
  // consumes-and-suppresses instead of showing a second notification. The
  // consume-on-read gate only removes markers — without writing one here the
  // live-first ordering (live shows, then a late FCM finds nothing to consume)
  // would double-alert. Gated on messageId so it never over-suppresses an
  // unrelated bare-payload message.
  if (markRecentRemoteNotificationAnnouncement != null && messageId != null) {
    try {
      await markRecentRemoteNotificationAnnouncement(
        payload: routePayload ?? contactPeerId,
        messageId: messageId,
      );
    } catch (error) {
      // Native publication already returned normally. Dedupe bookkeeping is a
      // separate recoverable residue and cannot erase the truthful OS outcome.
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_REMOTE_ANNOUNCEMENT_MARK_FAILED',
        details: {
          'type': notificationEventType,
          'errorType': error.runtimeType.toString(),
        },
      );
    }
  }
  return NotificationPresentationResult.osPosted;
}

Future<bool> _notifyDurableEffectTerminal({
  required DurableLocalNotificationEffectContext context,
  required DurableLocalNotificationEffectReceipt receipt,
  required String notificationEventType,
}) async {
  final observer = context.onEffectTerminal;
  if (observer == null) return false;
  try {
    await observer(receipt);
    return true;
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_NOTIFICATION_EFFECT_HANDOFF_FAILED',
      details: {
        'type': notificationEventType,
        'errorType': error.runtimeType.toString(),
      },
    );
    return false;
  }
}

final class _NotificationClaimOwnershipLostBeforeShow implements Exception {
  const _NotificationClaimOwnershipLostBeforeShow();
}
