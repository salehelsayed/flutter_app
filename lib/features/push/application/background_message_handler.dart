import 'dart:convert';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:background_push_crypto/background_push_crypto.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/recent_background_notification_gate.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/remote_notification_identity.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/notifications/recent_remote_gate_ios_wiring.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_message_local_deletions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_read_acknowledgement_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_invites_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/ml_kem_secret_ring.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/group_notification_display_policy.dart';
import 'package:flutter_app/features/push/application/group_reaction_notification_copy.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final FlutterLocalNotificationsPlugin _backgroundNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
bool _backgroundNotificationsInitialized = false;
const String _backgroundDbEncryptionKey = 'db_encryption_key';
const String _backgroundMlKemSecretKey = 'identity_ml_kem_secret_key';
const String _backgroundPushTransportPeerId =
    'push_registration_transport_peer_id';

@visibleForTesting
void debugResetBackgroundNotificationsInitialization() {
  _backgroundNotificationsInitialized = false;
}

typedef BackgroundPushNotificationResolver =
    Future<BackgroundPushNotificationFallback> Function(RemoteMessage message);
typedef BackgroundPushNotificationDisplayEligibilityResolver =
    Future<PushFallbackNotificationDisplayEligibility> Function(
      RemoteMessage message,
    );
typedef BackgroundPushEnvelopeStager =
    Future<void> Function(StagedPushEnvelope entry);
typedef BackgroundDirectReactionLocalStateResolver =
    Future<BackgroundDirectReactionLocalState?> Function(RemoteMessage message);
typedef BackgroundDirectMessageLocalStateResolver =
    Future<BackgroundDirectMessageLocalState?> Function(RemoteMessage message);
typedef BackgroundGroupMessageLocalStateResolver =
    Future<BackgroundGroupMessageLocalState?> Function(RemoteMessage message);
typedef BackgroundNotificationLocaleResolver = Locale? Function();
typedef BackgroundMessageNotificationCoordinatorResolver =
    Future<DurableNotificationToneLease> Function();
typedef BackgroundConversationNotificationIdRegistryResolver =
    Future<DurableConversationNotificationIdRegistry> Function();
typedef BackgroundReactionNotificationCoordinatorResolver =
    Future<DurableNotificationToneLease> Function();
typedef BackgroundGroupReactionLocalStateResolver =
    Future<BackgroundGroupReactionLocalState?> Function(RemoteMessage message);
typedef BackgroundGroupNotificationPostShowValidator =
    Future<BackgroundGroupNotificationPostShowDecision> Function(
      BackgroundManagedGroupNotificationComparand comparand,
    );

class BackgroundDirectReactionLocalState {
  const BackgroundDirectReactionLocalState({
    required this.previewContext,
    required this.mlKemSecretKey,
  });

  final DirectReactionNotificationContext previewContext;
  final String? mlKemSecretKey;
}

class BackgroundDirectMessageLocalState {
  const BackgroundDirectMessageLocalState({
    required this.previewContext,
    required this.mlKemSecretKeys,
  });

  final DirectMessageNotificationContext previewContext;

  /// Current key first, followed by prior identity keys newest-first.
  final List<String> mlKemSecretKeys;
}

class BackgroundGroupMessageLocalState {
  const BackgroundGroupMessageLocalState({
    required this.previewContext,
    required this.groupKey,
    required this.keyEpoch,
  });

  final GroupMessageNotificationContext previewContext;
  final String? groupKey;
  final int? keyEpoch;
}

class BackgroundGroupReactionLocalState {
  const BackgroundGroupReactionLocalState({
    required this.previewContext,
    required this.groupKey,
    required this.keyEpoch,
    required this.nominationVerified,
  });

  final GroupReactionNotificationContext previewContext;
  final String groupKey;
  final int keyEpoch;
  final bool nominationVerified;
}

/// Persists the exact transport installation whose FCM token is about to be
/// registered. The Android headless engine has no live P2P node state, so this
/// small recipient-owned binding is required to match the signed nomination to
/// the current active local group-device roster.
Future<void> persistBackgroundPushRegistrationTransportPeerId({
  required SecureKeyStore secureKeyStore,
  required String? transportPeerId,
}) async {
  final normalized = _trimToNull(transportPeerId);
  if (normalized == null) {
    await secureKeyStore.delete(_backgroundPushTransportPeerId);
    return;
  }
  await secureKeyStore.write(_backgroundPushTransportPeerId, normalized);
}

BackgroundPushNotificationResolver _backgroundPushNotificationResolver =
    _resolveBackgroundPushNotificationFromLocalState;
BackgroundPushNotificationDisplayEligibilityResolver
_backgroundPushNotificationDisplayEligibilityResolver =
    resolveBackgroundPushNotificationDisplayEligibilityFromLocalState;
AccountMigrationNetworkGate _backgroundAccountMigrationNetworkGate =
    _defaultBackgroundAccountMigrationNetworkGate;
BackgroundPushEnvelopeStager _backgroundPushEnvelopeStager =
    _defaultBackgroundPushEnvelopeStager;
BackgroundDirectReactionLocalStateResolver
_backgroundDirectReactionLocalStateResolver =
    _resolveDirectReactionLocalStateFromEncryptedDb;
BackgroundDirectMessageLocalStateResolver
_backgroundDirectMessageLocalStateResolver =
    _resolveDirectMessageLocalStateFromEncryptedDb;
BackgroundGroupMessageLocalStateResolver
_backgroundGroupMessageLocalStateResolver =
    _resolveGroupMessageLocalStateFromEncryptedDb;
BackgroundNotificationLocaleResolver _backgroundNotificationLocaleResolver =
    _defaultBackgroundNotificationLocale;
BackgroundMessageNotificationCoordinatorResolver
_backgroundMessageNotificationCoordinatorResolver =
    DurableNotificationToneLease.openMobileDefault;
BackgroundConversationNotificationIdRegistryResolver
_backgroundConversationNotificationIdRegistryResolver =
    DurableConversationNotificationIdRegistry.openMobileDefault;
BackgroundReactionNotificationCoordinatorResolver
_backgroundReactionNotificationCoordinatorResolver =
    DurableNotificationToneLease.openDefault;
BackgroundGroupReactionLocalStateResolver
_backgroundGroupReactionLocalStateResolver =
    _resolveGroupReactionLocalStateFromEncryptedDb;
BackgroundGroupNotificationPostShowValidator
_backgroundGroupNotificationPostShowValidator =
    _validateBackgroundGroupNotificationAfterShowFromEncryptedDb;

@visibleForTesting
void debugSetBackgroundPushNotificationResolver(
  BackgroundPushNotificationResolver resolver,
) {
  _backgroundPushNotificationResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundPushNotificationResolver() {
  _backgroundPushNotificationResolver =
      _resolveBackgroundPushNotificationFromLocalState;
}

@visibleForTesting
void debugSetBackgroundDirectReactionLocalStateResolver(
  BackgroundDirectReactionLocalStateResolver resolver,
) {
  _backgroundDirectReactionLocalStateResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundDirectReactionLocalStateResolver() {
  _backgroundDirectReactionLocalStateResolver =
      _resolveDirectReactionLocalStateFromEncryptedDb;
}

@visibleForTesting
void debugSetBackgroundDirectMessageLocalStateResolver(
  BackgroundDirectMessageLocalStateResolver resolver,
) {
  _backgroundDirectMessageLocalStateResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundDirectMessageLocalStateResolver() {
  _backgroundDirectMessageLocalStateResolver =
      _resolveDirectMessageLocalStateFromEncryptedDb;
}

@visibleForTesting
void debugSetBackgroundGroupMessageLocalStateResolver(
  BackgroundGroupMessageLocalStateResolver resolver,
) {
  _backgroundGroupMessageLocalStateResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundGroupMessageLocalStateResolver() {
  _backgroundGroupMessageLocalStateResolver =
      _resolveGroupMessageLocalStateFromEncryptedDb;
}

@visibleForTesting
void debugSetBackgroundNotificationLocaleResolver(
  BackgroundNotificationLocaleResolver resolver,
) {
  _backgroundNotificationLocaleResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundNotificationLocaleResolver() {
  _backgroundNotificationLocaleResolver = _defaultBackgroundNotificationLocale;
}

@visibleForTesting
void debugSetBackgroundMessageNotificationCoordinatorResolver(
  BackgroundMessageNotificationCoordinatorResolver resolver,
) {
  _backgroundMessageNotificationCoordinatorResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundMessageNotificationCoordinatorResolver() {
  _backgroundMessageNotificationCoordinatorResolver =
      DurableNotificationToneLease.openMobileDefault;
}

@visibleForTesting
void debugSetBackgroundConversationNotificationIdRegistryResolver(
  BackgroundConversationNotificationIdRegistryResolver resolver,
) {
  _backgroundConversationNotificationIdRegistryResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundConversationNotificationIdRegistryResolver() {
  _backgroundConversationNotificationIdRegistryResolver =
      DurableConversationNotificationIdRegistry.openMobileDefault;
}

Locale? _defaultBackgroundNotificationLocale() {
  final locales = PlatformDispatcher.instance.locales;
  return locales.isEmpty ? null : locales.first;
}

@visibleForTesting
void debugSetBackgroundReactionNotificationCoordinatorResolver(
  BackgroundReactionNotificationCoordinatorResolver resolver,
) {
  _backgroundReactionNotificationCoordinatorResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundReactionNotificationCoordinatorResolver() {
  _backgroundReactionNotificationCoordinatorResolver =
      DurableNotificationToneLease.openDefault;
}

@visibleForTesting
void debugSetBackgroundGroupReactionLocalStateResolver(
  BackgroundGroupReactionLocalStateResolver resolver,
) {
  _backgroundGroupReactionLocalStateResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundGroupReactionLocalStateResolver() {
  _backgroundGroupReactionLocalStateResolver =
      _resolveGroupReactionLocalStateFromEncryptedDb;
}

@visibleForTesting
void debugSetBackgroundGroupNotificationPostShowValidator(
  BackgroundGroupNotificationPostShowValidator validator,
) {
  _backgroundGroupNotificationPostShowValidator = validator;
}

@visibleForTesting
void debugResetBackgroundGroupNotificationPostShowValidator() {
  _backgroundGroupNotificationPostShowValidator =
      _validateBackgroundGroupNotificationAfterShowFromEncryptedDb;
}

@visibleForTesting
void debugSetBackgroundPushNotificationDisplayEligibilityResolver(
  BackgroundPushNotificationDisplayEligibilityResolver resolver,
) {
  _backgroundPushNotificationDisplayEligibilityResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundPushNotificationDisplayEligibilityResolver() {
  _backgroundPushNotificationDisplayEligibilityResolver =
      resolveBackgroundPushNotificationDisplayEligibilityFromLocalState;
}

@visibleForTesting
void debugSetBackgroundAccountMigrationNetworkGate(
  AccountMigrationNetworkGate gate,
) {
  _backgroundAccountMigrationNetworkGate = gate;
}

@visibleForTesting
void debugResetBackgroundAccountMigrationNetworkGate() {
  _backgroundAccountMigrationNetworkGate =
      _defaultBackgroundAccountMigrationNetworkGate;
}

@visibleForTesting
void debugSetBackgroundPushEnvelopeStager(BackgroundPushEnvelopeStager stager) {
  _backgroundPushEnvelopeStager = stager;
}

@visibleForTesting
void debugResetBackgroundPushEnvelopeStager() {
  _backgroundPushEnvelopeStager = _defaultBackgroundPushEnvelopeStager;
}

Future<void> _initializeBackgroundNotifications() async {
  if (_backgroundNotificationsInitialized) return;

  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    ),
  );

  await _backgroundNotificationsPlugin.initialize(settings);
  await ensureMknoonNotificationChannel(_backgroundNotificationsPlugin);
  _backgroundNotificationsInitialized = true;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    // A background FlutterEngine has its own module globals. Reinstall the iOS
    // App Group-backed gate here so its marks and the NSE sidecar live in the
    // same shared container as the foreground process.
    configureRecentRemoteNotificationGateForIos();
  }

  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_BACKGROUND_FIREBASE_INIT_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_BACKGROUND_MESSAGE_RECEIVED',
    details: {
      'messageId': message.messageId,
      'dataKeys': message.data.keys.toList(),
      'note':
          'local notification shown if routable; inbox drain on next resume',
    },
  );

  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(
    message.data,
  );
  Future<void> markVisibleRemoteAnnouncement() async {
    final target = routeTarget;
    if (target == null) {
      return;
    }
    final payload = target.toPayload();
    final messageId = routeTargetSupportsMessageAwareRemoteDedupe(target.kind)
        ? remoteNotificationMessageIdFromData(message.data)
        : null;
    await recentRemoteNotificationGate.markAnnouncement(
      payload: payload,
      messageId: messageId,
    );
  }

  if (!shouldShowBackgroundPushFallbackNotification(message)) {
    if (message.notification != null) {
      await markVisibleRemoteAnnouncement();
    }
    return;
  }

  final displayEligibility =
      await _backgroundPushNotificationDisplayEligibilityResolver(message);
  if (!displayEligibility.shouldDisplay) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
      details: {
        'messageId': message.messageId,
        'reason': displayEligibility.reason,
        'payload': routeTarget?.toPayload() ?? '',
      },
    );
    return;
  }

  DurableNotificationEventClaim? notificationEventClaim;
  DurableNotificationToneReservation? notificationToneReservation;
  try {
    await _stagePushEnvelopeIfPresent(message);
    await _initializeBackgroundNotifications();
    final fallback = await _backgroundPushNotificationResolver(message);
    final dedupeKey = backgroundPushFallbackDedupeKey(message);
    if (dedupeKey != null &&
        await recentBackgroundNotificationGate.wasRecentlyShown(dedupeKey)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
        details: {
          'messageId': message.messageId,
          'reason': 'recent_duplicate_background_push',
          'payload': fallback.payload ?? '',
        },
      );
      return;
    }
    final pushType = _trimToNull(message.data['type']);
    final groupContentKind =
        routeTarget?.kind == NotificationRouteTargetKind.group
        ? groupNotificationContentKindFromRemoteData(message.data)
        : null;
    final isOrdinaryMessage =
        pushType == 'new_message' ||
        groupContentKind == ConversationNotificationContentKind.message;
    final isReaction =
        pushType == 'message_reaction' ||
        groupContentKind == ConversationNotificationContentKind.reaction;
    final reactionEventId = isReaction
        ? _trimToNull(message.data['event_id']) ??
              _trimToNull(message.data['reaction_id'])
        : null;
    if (isReaction && reactionEventId == null) return;
    final notificationEventIdentity = isOrdinaryMessage
        ? remoteNotificationMessageIdFromData(message.data)
        : reactionEventId == null
        ? null
        : boundedReactionEventIdentity(reactionEventId);
    // Swift's NSE deliberately uses `message_reaction` for direct, group, and
    // announcement reactions. Keep the exact filename contract cross-platform.
    final notificationClaimType = isReaction
        ? 'message_reaction'
        : groupContentKind == ConversationNotificationContentKind.message
        ? 'group_message'
        : pushType;
    // The OS card/thread is conversation-scoped, while the tap payload remains
    // message-anchored. In particular, `group:<id>|message:<id>` must update the
    // existing group card rather than minting one card per message.
    final conversationKey =
        _remoteNotificationConversationKey(routeTarget) ??
        fallback.payload ??
        message.messageId ??
        fallback.title;

    var claimStorageFailedOpen = false;
    var notificationClaimCommitted = false;
    DurableNotificationToneLease? notificationCoordinator;
    if (isOrdinaryMessage || isReaction) {
      try {
        notificationCoordinator = isReaction
            ? await _backgroundReactionNotificationCoordinatorResolver()
            : await _backgroundMessageNotificationCoordinatorResolver();
      } catch (e) {
        claimStorageFailedOpen = true;
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_MESSAGE_CLAIM_STORAGE_UNAVAILABLE',
          details: {'type': pushType, 'errorType': e.runtimeType.toString()},
        );
      }
      if (notificationCoordinator != null &&
          notificationEventIdentity != null &&
          notificationClaimType != null) {
        try {
          notificationEventClaim = await notificationCoordinator
              .claimMessageEvent(
                type: notificationClaimType,
                eventIdentity: notificationEventIdentity,
              );
        } catch (e) {
          notificationCoordinator = null;
          claimStorageFailedOpen = true;
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_BACKGROUND_MESSAGE_CLAIM_STORAGE_UNAVAILABLE',
            details: {'type': pushType, 'errorType': e.runtimeType.toString()},
          );
        }
        if (notificationEventClaim == null && !claimStorageFailedOpen) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
            details: {
              'messageId': message.messageId,
              'reason': isReaction
                  ? 'reaction_event_already_claimed'
                  : 'message_event_already_claimed',
              'type': pushType,
              'payload': fallback.payload ?? '',
            },
          );
          return;
        }
      }
    }

    var silent = false;
    if (notificationCoordinator != null) {
      try {
        final toneKey = isReaction
            ? groupContentKind == ConversationNotificationContentKind.reaction
                  ? _groupReactionConversationKey(message.data) ??
                        notificationEventIdentity!
                  : fallback.payload ?? notificationEventIdentity!
            : conversationKey;
        notificationToneReservation = await notificationCoordinator.reserveTone(
          toneKey,
        );
        silent = notificationToneReservation == null;
      } catch (e) {
        // Tone storage has the same fail-open contract as claim storage: show
        // the authorized notification audibly rather than dropping it.
        silent = false;
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_MESSAGE_TONE_STORAGE_UNAVAILABLE',
          details: {'type': pushType, 'errorType': e.runtimeType.toString()},
        );
      }
    }
    late final DurableConversationNotificationIdRegistry notificationIdRegistry;
    late final int notificationId;
    try {
      notificationIdRegistry =
          await _backgroundConversationNotificationIdRegistryResolver();
      notificationId = await notificationIdRegistry.resolve(
        conversationKey,
        activeNotificationIds: () async =>
            (await _backgroundNotificationsPlugin.getActiveNotifications()).map(
              (notification) => notification.id,
            ),
      );
    } catch (error) {
      final allocationError = error is NotificationIdAllocationException
          ? error
          : NotificationIdAllocationException(
              operation: 'registry_open',
              errorType: error.runtimeType.toString(),
            );
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_BACKGROUND_NOTIFICATION_ID_ALLOCATION_UNAVAILABLE',
        details: {
          'operation': allocationError.operation,
          'errorType': allocationError.errorType,
        },
      );
      throw allocationError;
    }

    final contentKind = groupContentKind;
    final contentMetadata = contentKind == null
        ? null
        : ConversationNotificationContentMetadata(
            kind: contentKind,
            eventIdentity: notificationEventIdentity,
            generation: createConversationNotificationGeneration(),
          );
    final nativePayload = contentMetadata == null
        ? fallback.payload
        : encodeConversationNotificationPayload(
            routePayload: fallback.payload ?? conversationKey,
            conversationKey: conversationKey,
            metadata: contentMetadata,
          );
    Future<void> show() => _backgroundNotificationsPlugin.show(
      notificationId,
      fallback.title,
      fallback.body,
      mknoonConversationNotificationDetails(
        conversationKey: conversationKey,
        silent: silent,
        autoCancel: contentMetadata == null,
      ),
      payload: nativePayload,
    );
    if (contentMetadata == null) {
      await show();
    } else {
      await notificationIdRegistry.replaceContent(
        conversationKey: conversationKey,
        notificationId: notificationId,
        metadata: contentMetadata,
        retireCurrent: () =>
            _backgroundNotificationsPlugin.cancel(notificationId),
        replace: show,
      );
    }
    // Native display has succeeded. Detach both owners before any subsequent
    // validation/bookkeeping so no post-show failure can reach the outer catch
    // and release them for a duplicate audible retry.
    final shownToneReservation = notificationToneReservation;
    notificationToneReservation = null;
    final shownMessageClaim = notificationEventClaim;
    notificationEventClaim = null;
    // Commit durable ownership immediately after native publication. The
    // canonical fence may need to open SQLCipher or call back into the plugin;
    // neither operation may enlarge the show-to-commit crash window.
    if (shownToneReservation != null) {
      var toneCommitted = false;
      try {
        toneCommitted = await shownToneReservation.commit();
      } catch (_) {
        toneCommitted = false;
      }
      // The OS show succeeded, so a later bookkeeping failure must never
      // release the audible right and permit a second immediate tone.
      if (!toneCommitted) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_MESSAGE_TONE_COMMIT_FAILED',
          details: {'type': pushType},
        );
      }
    }
    if (shownMessageClaim != null) {
      try {
        notificationClaimCommitted = await shownMessageClaim.commit();
      } catch (_) {
        notificationClaimCommitted = false;
      }
      // The OS show succeeded, so this producer must never release its claim,
      // even if a later compatibility-gate write fails.
      if (!notificationClaimCommitted) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_MESSAGE_CLAIM_COMMIT_FAILED',
          details: {'type': pushType},
        );
      }
    }
    final groupComparand = fallback.groupComparand;
    if (contentMetadata != null && groupComparand != null) {
      try {
        final metadataMatches = switch (groupComparand) {
          BackgroundGroupMessageNotificationComparand messageComparand =>
            contentMetadata.kind ==
                    ConversationNotificationContentKind.message &&
                contentMetadata.eventIdentity == messageComparand.messageId,
          BackgroundGroupReactionNotificationComparand reactionComparand =>
            contentMetadata.kind ==
                    ConversationNotificationContentKind.reaction &&
                contentMetadata.eventIdentity ==
                    reactionComparand.notificationEventIdentity,
          BackgroundProvisionalGroupReactionNotificationComparand
          reactionComparand =>
            contentMetadata.kind ==
                    ConversationNotificationContentKind.reaction &&
                contentMetadata.eventIdentity ==
                    reactionComparand.notificationEventIdentity,
        };
        final decision = metadataMatches
            ? await _backgroundGroupNotificationPostShowValidator(
                groupComparand,
              )
            : BackgroundGroupNotificationPostShowDecision.retire;
        if (decision == BackgroundGroupNotificationPostShowDecision.retire) {
          final retired = await notificationIdRegistry
              .cancelContentIfGeneration(
                conversationKey: conversationKey,
                notificationId: notificationId,
                generation: contentMetadata.generation!,
                cancel: () =>
                    _backgroundNotificationsPlugin.cancel(notificationId),
              );
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_BACKGROUND_GROUP_POST_SHOW_RETIRED',
            details: {
              'type': pushType,
              'result': retired
                  ? 'retired_exact_generation'
                  : 'newer_generation_survived',
            },
          );
        }
      } catch (error) {
        // The native show already succeeded. A read or cancellation failure is
        // unknown, not a display failure: keep the card. Its tone and event
        // owners were already committed immediately after native publication,
        // so the same push cannot re-alert. Durable reconciliation retries the
        // canonical projection from the foreground runtime.
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_GROUP_POST_SHOW_UNKNOWN',
          details: {
            'type': pushType,
            'errorType': error.runtimeType.toString(),
          },
        );
      }
    }
    if (dedupeKey != null) {
      await recentBackgroundNotificationGate.markShown(dedupeKey);
    }
    // Exact committed message claims are the Android live/background dedupe
    // authority. Keep the recent-remote gate only for iOS NSE compatibility,
    // legacy/no-id pushes, or the documented durable-storage fail-open path.
    if (!isOrdinaryMessage ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        notificationEventIdentity == null ||
        !notificationClaimCommitted) {
      await markVisibleRemoteAnnouncement();
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
      details: {
        'messageId': message.messageId,
        'payload': fallback.payload ?? '',
      },
    );
  } catch (e) {
    final failedToneReservation = notificationToneReservation;
    notificationToneReservation = null;
    if (failedToneReservation != null) {
      try {
        final released = await failedToneReservation.release();
        if (!released) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_BACKGROUND_MESSAGE_TONE_RELEASE_FAILED',
            details: {'kind': 'ordinary_message'},
          );
        }
      } catch (releaseError) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_MESSAGE_TONE_RELEASE_FAILED',
          details: {
            'kind': 'ordinary_message',
            'errorType': releaseError.runtimeType.toString(),
          },
        );
      }
    }
    final failedMessageClaim = notificationEventClaim;
    notificationEventClaim = null;
    if (failedMessageClaim != null) {
      try {
        final released = await failedMessageClaim.release();
        if (!released) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_BACKGROUND_MESSAGE_CLAIM_RELEASE_FAILED',
            details: {'type': failedMessageClaim.type},
          );
        }
      } catch (releaseError) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_MESSAGE_CLAIM_RELEASE_FAILED',
          details: {
            'type': failedMessageClaim.type,
            'errorType': releaseError.runtimeType.toString(),
          },
        );
      }
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_NOTIFICATION_ERROR',
      details: {'error': e.toString()},
    );
  }
}

Future<void> _stagePushEnvelopeIfPresent(RemoteMessage message) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return;
  }
  final entry = _stagedPushEnvelopeFromRemoteMessage(message);
  if (entry == null) {
    return;
  }
  try {
    await _backgroundPushEnvelopeStager(entry);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_ENVELOPE_STAGE_ERROR',
      details: {'messageId': message.messageId, 'error': e.toString()},
    );
  }
}

StagedPushEnvelope? _stagedPushEnvelopeFromRemoteMessage(
  RemoteMessage message,
) {
  final data = message.data;
  final type = _trimToNull(data['type']);
  if (type != 'new_message' && type != 'message_reaction') {
    return null;
  }
  final senderPeerId =
      _trimToNull(data['sender_id']) ?? _trimToNull(data['from']);
  final kem = _trimToNull(data['kem']) ?? _trimToNull(data['k']);
  final ciphertext = _trimToNull(data['ciphertext']) ?? _trimToNull(data['c']);
  final nonce = _trimToNull(data['nonce']) ?? _trimToNull(data['n']);
  if (senderPeerId == null ||
      kem == null ||
      ciphertext == null ||
      nonce == null) {
    return null;
  }
  if (type == 'message_reaction') {
    final eventId =
        _trimToNull(data['event_id']) ?? _trimToNull(data['reaction_id']);
    final action = _trimToNull(data['action']);
    final targetMessageId = _trimToNull(data['target_message_id']);
    if (eventId == null || action != 'add' || targetMessageId == null) {
      return null;
    }
    return StagedPushEnvelope(
      kind: 'reaction',
      kem: kem,
      ciphertext: ciphertext,
      nonce: nonce,
      senderPeerId: senderPeerId,
      messageId: eventId,
      eventId: eventId,
      action: action,
      targetMessageId: targetMessageId,
      receivedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }
  return StagedPushEnvelope(
    kind: 'chat',
    kem: kem,
    ciphertext: ciphertext,
    nonce: nonce,
    senderPeerId: senderPeerId,
    messageId: remoteNotificationMessageIdFromData(data),
    receivedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
  );
}

String? _trimToNull(Object? value) {
  final trimmed = value?.toString().trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

bool _isExactGroupNotificationReadAcknowledgement(
  Map<String, Object?>? row, {
  required String groupId,
  required String contentKind,
  required String eventIdentity,
}) =>
    _trimToNull(row?['group_id']) == groupId &&
    _trimToNull(row?['content_kind']) == contentKind &&
    _trimToNull(row?['event_identity']) == eventIdentity;

String? _groupReactionConversationKey(Map<String, dynamic> data) {
  final groupId = _trimToNull(data['groupId']) ?? _trimToNull(data['group_id']);
  return groupId == null ? null : 'group:$groupId';
}

String? _remoteNotificationConversationKey(
  NotificationRouteTarget? routeTarget,
) {
  if (routeTarget == null) return null;
  switch (routeTarget.kind) {
    case NotificationRouteTargetKind.conversation:
      return _trimToNull(routeTarget.peerId);
    case NotificationRouteTargetKind.group:
      final groupId = _trimToNull(routeTarget.groupId);
      return groupId == null ? null : 'group:$groupId';
    case NotificationRouteTargetKind.contactRequest:
    case NotificationRouteTargetKind.intros:
    case NotificationRouteTargetKind.post:
    case NotificationRouteTargetKind.postComment:
      return _trimToNull(routeTarget.toPayload());
  }
}

Future<void> _defaultBackgroundPushEnvelopeStager(
  StagedPushEnvelope entry,
) async {
  final store = await FilePushEnvelopeStagingStore.openDefault();
  await store.stage(entry);
}

Future<PushFallbackNotificationDisplayEligibility>
resolveBackgroundPushNotificationDisplayEligibilityFromLocalState(
  RemoteMessage message,
) async {
  final accountNetworkAllowed =
      await _allowsBackgroundAccountNotificationDisplay();
  if (!accountNetworkAllowed.shouldDisplay) {
    return accountNetworkAllowed;
  }

  if (_trimToNull(message.data['type']) == 'new_message') {
    final localState = await _backgroundDirectMessageLocalStateResolver(
      message,
    );
    if (localState == null) {
      return const PushFallbackNotificationDisplayEligibility.suppressed(
        'direct_message_local_state_ineligible',
      );
    }
    return const PushFallbackNotificationDisplayEligibility.allow();
  }

  if (_trimToNull(message.data['type']) == 'group_message') {
    final localState = await _backgroundGroupMessageLocalStateResolver(message);
    if (localState == null) {
      return const PushFallbackNotificationDisplayEligibility.suppressed(
        'group_message_local_state_ineligible',
      );
    }
    return const PushFallbackNotificationDisplayEligibility.allow();
  }

  if (_trimToNull(message.data['type']) == 'message_reaction') {
    final localState = await _backgroundDirectReactionLocalStateResolver(
      message,
    );
    if (localState == null) {
      return const PushFallbackNotificationDisplayEligibility.suppressed(
        'reaction_local_state_ineligible',
      );
    }
    return const PushFallbackNotificationDisplayEligibility.allow();
  }

  if (_trimToNull(message.data['type']) == 'group_reaction') {
    final localState = await _backgroundGroupReactionLocalStateResolver(
      message,
    );
    if (localState == null) {
      return const PushFallbackNotificationDisplayEligibility.suppressed(
        'group_reaction_local_state_ineligible',
      );
    }
    return const PushFallbackNotificationDisplayEligibility.allow();
  }

  return resolveBackgroundPushFallbackDisplayEligibility(
    message,
    groupMessageDisplayEligibilityResolver:
        _resolveGroupMessageNotificationDisplayEligibilityFromEncryptedDb,
  );
}

Future<BackgroundPushNotificationFallback>
_resolveBackgroundPushNotificationFromLocalState(RemoteMessage message) async {
  final type = _trimToNull(message.data['type']);
  if (type == 'new_message') {
    final localState = await _backgroundDirectMessageLocalStateResolver(
      message,
    );
    if (localState == null) {
      // Eligibility and preview resolution are deliberately separate reads.
      // Blocking, archiving, or contact deletion between them must suppress.
      throw StateError('direct message local state became ineligible');
    }
    final secretKeys = localState.mlKemSecretKeys;
    return resolveBackgroundPushNotification(
      message,
      directMessageContext: localState.previewContext,
      locale: _backgroundNotificationLocaleResolver(),
      decryptOneToOne: secretKeys.isEmpty
          ? null
          : ({required kem, required ciphertext, required nonce}) async {
              for (var index = 0; index < secretKeys.length; index++) {
                try {
                  final result = await const BackgroundPushCrypto()
                      .decryptMessage(
                        secretKey: secretKeys[index],
                        kem: kem,
                        ciphertext: ciphertext,
                        nonce: nonce,
                      );
                  final plaintext = result['plaintext'];
                  if (result['ok'] == true && plaintext is String) {
                    emitFlowEvent(
                      layer: 'FL',
                      event: 'PUSH_BACKGROUND_MESSAGE_CRYPTO_PLUGIN_OK',
                      details: {'kind': 'chat', 'keyIndex': index},
                    );
                    return plaintext;
                  }
                  emitFlowEvent(
                    layer: 'FL',
                    event: 'PUSH_BACKGROUND_MESSAGE_CRYPTO_PLUGIN_REJECTED',
                    details: {
                      'kind': 'chat',
                      'keyIndex': index,
                      'errorCode': result['errorCode']?.toString() ?? 'unknown',
                    },
                  );
                } catch (e) {
                  emitFlowEvent(
                    layer: 'FL',
                    event: 'PUSH_BACKGROUND_MESSAGE_CRYPTO_PLUGIN_REJECTED',
                    details: {
                      'kind': 'chat',
                      'keyIndex': index,
                      'errorType': e.runtimeType.toString(),
                    },
                  );
                }
              }
              throw StateError('background direct message decrypt rejected');
            },
    );
  }
  if (type == 'group_message') {
    final localState = await _backgroundGroupMessageLocalStateResolver(message);
    if (localState == null) {
      // Membership, mute, archive, dissolution, and actor authorization can
      // change after the pre-display read. This second read is final authority.
      throw StateError('group message local state became ineligible');
    }
    final groupKey = _trimToNull(localState.groupKey);
    final selectedEpoch = localState.keyEpoch;
    return resolveBackgroundPushNotification(
      message,
      groupMessageContext: localState.previewContext,
      locale: _backgroundNotificationLocaleResolver(),
      decryptGroup: groupKey == null || selectedEpoch == null
          ? null
          : ({
              required groupId,
              required keyEpoch,
              required ciphertext,
              required nonce,
            }) async {
              if (groupId != localState.previewContext.groupId ||
                  keyEpoch != selectedEpoch) {
                throw const OrdinaryMessageNotificationIntegrityException(
                  'group_key_context_changed',
                );
              }
              final result = await const BackgroundPushCrypto().decryptGroup(
                groupKey: groupKey,
                ciphertext: ciphertext,
                nonce: nonce,
              );
              final plaintext = result['plaintext'];
              if (result['ok'] != true || plaintext is! String) {
                emitFlowEvent(
                  layer: 'FL',
                  event: 'PUSH_BACKGROUND_MESSAGE_CRYPTO_PLUGIN_REJECTED',
                  details: {
                    'kind': 'group',
                    'errorCode': result['errorCode']?.toString() ?? 'unknown',
                  },
                );
                throw StateError('background group message decrypt rejected');
              }
              emitFlowEvent(
                layer: 'FL',
                event: 'PUSH_BACKGROUND_MESSAGE_CRYPTO_PLUGIN_OK',
                details: {'kind': 'group'},
              );
              return plaintext;
            },
    );
  }
  if (type == 'group_reaction') {
    final localState = await _backgroundGroupReactionLocalStateResolver(
      message,
    );
    if (localState == null || !localState.nominationVerified) {
      throw StateError('group reaction local state became ineligible');
    }
    return resolveBackgroundPushNotification(
      message,
      groupReactionContext: localState.previewContext,
      locale: _backgroundNotificationLocaleResolver(),
      decryptGroup:
          ({
            required groupId,
            required keyEpoch,
            required ciphertext,
            required nonce,
          }) async {
            if (keyEpoch != localState.keyEpoch) {
              throw const GroupReactionNotificationIntegrityException(
                'group_reaction_key_epoch_changed',
              );
            }
            final result = await const BackgroundPushCrypto().decryptGroup(
              groupKey: localState.groupKey,
              ciphertext: ciphertext,
              nonce: nonce,
            );
            final plaintext = result['plaintext'];
            if (result['ok'] != true || plaintext is! String) {
              emitFlowEvent(
                layer: 'FL',
                event: 'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_REJECTED',
                details: {
                  'kind': 'group_reaction',
                  'errorCode': result['errorCode']?.toString() ?? 'unknown',
                  'errorMessage':
                      result['errorMessage']?.toString() ?? 'unknown',
                },
              );
              throw StateError('background group reaction decrypt rejected');
            }
            emitFlowEvent(
              layer: 'FL',
              event: 'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
              details: {'kind': 'group_reaction'},
            );
            return plaintext;
          },
    );
  }
  if (type != 'message_reaction') {
    return resolveBackgroundPushNotification(message);
  }

  final localState = await _backgroundDirectReactionLocalStateResolver(message);
  if (localState == null) {
    // Eligibility and preview resolution are deliberately separate async
    // phases. A contact can be blocked/deleted, or the authored target can be
    // removed, between them. Never turn that state change into a generic
    // reaction card: the second read is the final fail-closed authority.
    throw StateError('reaction local state became ineligible');
  }

  final secretKey = _trimToNull(localState.mlKemSecretKey);
  return resolveBackgroundPushNotification(
    message,
    directReactionContext: localState.previewContext,
    decryptOneToOne: secretKey == null
        ? null
        : ({required kem, required ciphertext, required nonce}) async {
            final result = await const BackgroundPushCrypto().decryptMessage(
              secretKey: secretKey,
              kem: kem,
              ciphertext: ciphertext,
              nonce: nonce,
            );
            final plaintext = result['plaintext'];
            if (result['ok'] != true || plaintext is! String) {
              throw StateError('background reaction decrypt rejected');
            }
            emitFlowEvent(
              layer: 'FL',
              event: 'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
              details: {'kind': 'reaction'},
            );
            return plaintext;
          },
  );
}

@visibleForTesting
BackgroundDirectMessageLocalState? directMessageLocalStateFromRows({
  required Map<String, dynamic> data,
  required Map<String, Object?>? identityRow,
  required Map<String, Object?>? contactRow,
  required String? currentMlKemSecretKey,
  required List<String> priorMlKemSecretKeys,
}) {
  if (_trimToNull(data['type']) != 'new_message') return null;
  final senderPeerId =
      _trimToNull(data['sender_id']) ??
      _trimToNull(data['senderId']) ??
      _trimToNull(data['senderPeerId']) ??
      _trimToNull(data['from']);
  final localPeerId = _trimToNull(identityRow?['peer_id']);
  final contactPeerId = _trimToNull(contactRow?['peer_id']);
  final blocked = (contactRow?['is_blocked'] as num?)?.toInt() == 1;
  final archived = (contactRow?['is_archived'] as num?)?.toInt() == 1;
  if (senderPeerId == null ||
      localPeerId == null ||
      senderPeerId == localPeerId ||
      contactPeerId != senderPeerId ||
      blocked ||
      archived) {
    return null;
  }

  final keys = <String>[];
  for (final raw in <String?>[currentMlKemSecretKey, ...priorMlKemSecretKeys]) {
    final key = _trimToNull(raw);
    if (key != null && !keys.contains(key)) keys.add(key);
  }
  return BackgroundDirectMessageLocalState(
    previewContext: DirectMessageNotificationContext(
      senderPeerId: senderPeerId,
      senderUsername: _trimToNull(contactRow?['username']),
      expectedMessageId: remoteNotificationMessageIdFromData(data),
    ),
    mlKemSecretKeys: List<String>.unmodifiable(keys),
  );
}

Future<BackgroundDirectMessageLocalState?>
_resolveDirectMessageLocalStateFromEncryptedDb(RemoteMessage message) async {
  final senderPeerId =
      _trimToNull(message.data['sender_id']) ??
      _trimToNull(message.data['senderId']) ??
      _trimToNull(message.data['senderPeerId']) ??
      _trimToNull(message.data['from']);
  if (senderPeerId == null) return null;

  Database? db;
  try {
    final secureStore = FlutterSecureKeyStore();
    final dbKey = await secureStore.read(_backgroundDbEncryptionKey);
    if (_trimToNull(dbKey) == null) return null;
    final dbPath = await getDatabasesPath();
    db = await openBackgroundIdentityDbReadTolerant(
      path: '$dbPath/identity.db',
      key: dbKey!,
    );
    final rows = await Future.wait<Map<String, Object?>?>([
      dbLoadIdentityRow(db),
      dbLoadContact(db, senderPeerId),
    ]);

    String? currentKey;
    List<String> priorKeys = const [];
    try {
      currentKey = await secureStore.read(_backgroundMlKemSecretKey);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_BACKGROUND_MESSAGE_KEY_LOAD_ERROR',
        details: {
          'kind': 'chat',
          'source': 'current',
          'errorType': e.runtimeType.toString(),
        },
      );
    }
    try {
      priorKeys = await loadMlKemSecretKeyRing(secureStore);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_BACKGROUND_MESSAGE_KEY_LOAD_ERROR',
        details: {
          'kind': 'chat',
          'source': 'prior_ring',
          'errorType': e.runtimeType.toString(),
        },
      );
    }
    return directMessageLocalStateFromRows(
      data: message.data,
      identityRow: rows[0],
      contactRow: rows[1],
      currentMlKemSecretKey: currentKey,
      priorMlKemSecretKeys: priorKeys,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_MESSAGE_LOCAL_STATE_ERROR',
      details: {'kind': 'chat', 'errorType': e.runtimeType.toString()},
    );
    return null;
  } finally {
    await db?.close();
  }
}

class _ResolvedGroupMessageSender {
  const _ResolvedGroupMessageSender({
    required this.peerId,
    required this.username,
    required this.role,
  });

  final String peerId;
  final String? username;
  final String role;
}

_ResolvedGroupMessageSender? _resolveUniqueGroupMessageSenderForTransport({
  required List<Map<String, Object?>> memberRows,
  required String groupId,
  required String senderTransportPeerId,
}) {
  final matches = <_ResolvedGroupMessageSender>[];
  for (final memberRow in memberRows) {
    if (_trimToNull(memberRow['group_id']) != groupId) continue;
    final peerId = _trimToNull(memberRow['peer_id']);
    final role = _trimToNull(memberRow['role']);
    if (peerId == null || role == null) continue;

    final rawDevices = memberRow['devices_json'];
    var hasAuthoritativeDeviceRoster = false;
    var devices = const <GroupMemberDeviceIdentity>[];
    if (rawDevices != null && rawDevices.toString().trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawDevices.toString());
        if (decoded is! List) {
          // A malformed/non-list roster is neither an active binding nor an
          // empty legacy row. Never let parse failure resurrect peerId equality.
          continue;
        }
        hasAuthoritativeDeviceRoster = decoded.isNotEmpty;
        devices = GroupMemberDeviceIdentity.listFromJson(decoded);
      } catch (_) {
        continue;
      }
    }

    for (final device in devices) {
      if (device.isActive && device.transportPeerId == senderTransportPeerId) {
        matches.add(
          _ResolvedGroupMessageSender(
            peerId: peerId,
            username: _trimToNull(memberRow['username']),
            role: role,
          ),
        );
      }
    }
    if (hasAuthoritativeDeviceRoster) continue;

    // Legacy single-device rows are accepted only when the stored roster is
    // genuinely empty. Account/transport equality plus a signing key is the
    // old binding; sparse rows and malformed JSON remain fail-closed.
    if (peerId == senderTransportPeerId &&
        _trimToNull(memberRow['public_key']) != null) {
      matches.add(
        _ResolvedGroupMessageSender(
          peerId: peerId,
          username: _trimToNull(memberRow['username']),
          role: role,
        ),
      );
    }
  }
  return matches.length == 1 ? matches.single : null;
}

@visibleForTesting
BackgroundGroupMessageLocalState? groupMessageLocalStateFromRows({
  required Map<String, dynamic> data,
  required Map<String, Object?>? identityRow,
  required Map<String, Object?>? groupRow,
  required Map<String, Object?>? localMemberRow,
  required List<Map<String, Object?>> memberRows,
  required Map<String, Object?>? groupKeyRow,
  Map<String, Object?>? readAcknowledgementRow,
  Map<String, Object?>? canonicalMessageRow,
}) {
  if (_trimToNull(data['type']) != 'group_message') return null;
  final groupId = _trimToNull(data['groupId']) ?? _trimToNull(data['group_id']);
  final outerSenderAccount =
      _trimToNull(data['sender_id']) ??
      _trimToNull(data['senderId']) ??
      _trimToNull(data['senderPeerId']) ??
      _trimToNull(data['from']);
  final senderTransportPeerId = _trimToNull(data['sender_transport_peer_id']);
  final requestedEpoch = int.tryParse(
    data['keyEpoch']?.toString() ?? data['key_epoch']?.toString() ?? '',
  );
  final localPeerId = _trimToNull(identityRow?['peer_id']);
  final storedGroupId = _trimToNull(groupRow?['id']);
  final groupName = _trimToNull(groupRow?['name']);
  final groupType = _trimToNull(groupRow?['type']);
  final messageId = remoteNotificationMessageIdFromData(data);
  final groupDisplayEligibility = groupNotificationDisplayEligibilityFromRows(
    expectedGroupId: groupId,
    localPeerId: localPeerId,
    groupRow: groupRow,
    localMemberRow: localMemberRow,
  );
  if (groupId == null ||
      localPeerId == null ||
      senderTransportPeerId == null ||
      storedGroupId != groupId ||
      !groupDisplayEligibility.shouldDisplay) {
    return null;
  }
  if (messageId != null &&
      _isExactGroupNotificationReadAcknowledgement(
        readAcknowledgementRow,
        groupId: groupId,
        contentKind: 'message',
        eventIdentity: messageId,
      )) {
    return null;
  }

  final resolvedSender = _resolveUniqueGroupMessageSenderForTransport(
    memberRows: memberRows,
    groupId: groupId,
    senderTransportPeerId: senderTransportPeerId,
  );
  final authorizedSenderRole =
      resolvedSender != null &&
      (groupType == 'announcement'
          ? resolvedSender.role == MemberRole.admin.toValue()
          : resolvedSender.role == MemberRole.admin.toValue() ||
                resolvedSender.role == MemberRole.writer.toValue());
  if (resolvedSender == null ||
      resolvedSender.peerId == localPeerId ||
      (outerSenderAccount != null &&
          outerSenderAccount != resolvedSender.peerId) ||
      !authorizedSenderRole) {
    return null;
  }
  final canonicalIncoming = canonicalMessageRow?['is_incoming'];
  if (messageId != null &&
      _trimToNull(canonicalMessageRow?['id']) == messageId &&
      _trimToNull(canonicalMessageRow?['group_id']) == groupId &&
      _trimToNull(canonicalMessageRow?['sender_peer_id']) ==
          resolvedSender.peerId &&
      canonicalIncoming is num &&
      canonicalIncoming.toInt() == 1 &&
      canonicalMessageRow?['read_at'] != null) {
    return null;
  }

  String? groupKey;
  int? keyEpoch;
  if (groupKeyRow != null) {
    final keyGroupId = _trimToNull(groupKeyRow['group_id']);
    final storedEpoch = (groupKeyRow['key_generation'] as num?)?.toInt();
    final storedKey = _trimToNull(groupKeyRow['encrypted_key']);
    if (requestedEpoch == null ||
        requestedEpoch < 0 ||
        keyGroupId != groupId ||
        storedEpoch != requestedEpoch ||
        storedKey == null ||
        isSecureStoreReference(storedKey)) {
      return null;
    }
    groupKey = storedKey;
    keyEpoch = storedEpoch;
  }

  return BackgroundGroupMessageLocalState(
    previewContext: GroupMessageNotificationContext(
      groupId: groupId,
      groupName: groupName,
      localPeerId: localPeerId,
      senderPeerId: resolvedSender.peerId,
      senderTransportPeerId: senderTransportPeerId,
      senderUsername: resolvedSender.username,
      expectedMessageId: remoteNotificationMessageIdFromData(data),
    ),
    groupKey: groupKey,
    keyEpoch: keyEpoch,
  );
}

Future<BackgroundGroupMessageLocalState?>
_resolveGroupMessageLocalStateFromEncryptedDb(RemoteMessage message) async {
  final data = message.data;
  final groupId = _trimToNull(data['groupId']) ?? _trimToNull(data['group_id']);
  final senderTransportPeerId = _trimToNull(data['sender_transport_peer_id']);
  final requestedEpoch = int.tryParse(
    data['keyEpoch']?.toString() ?? data['key_epoch']?.toString() ?? '',
  );
  if (groupId == null || senderTransportPeerId == null) return null;

  Database? db;
  try {
    final secureStore = FlutterSecureKeyStore();
    final dbKey = await secureStore.read(_backgroundDbEncryptionKey);
    if (_trimToNull(dbKey) == null) return null;
    final dbPath = await getDatabasesPath();
    db = await openBackgroundIdentityDbReadTolerant(
      path: '$dbPath/identity.db',
      key: dbKey!,
    );
    final identityRow = await dbLoadIdentityRow(db);
    final localPeerId = _trimToNull(identityRow?['peer_id']);
    if (localPeerId == null) return null;
    final groupRowFuture = dbLoadGroup(db, groupId);
    final localMemberRowFuture = dbLoadGroupMember(db, groupId, localPeerId);
    final memberRowsFuture = dbLoadAllGroupMembers(db, groupId);
    final groupKeyRowFuture = requestedEpoch == null || requestedEpoch < 0
        ? Future<Map<String, Object?>?>.value(null)
        : dbLoadGroupKeyByGeneration(db, groupId, requestedEpoch);
    final messageId = remoteNotificationMessageIdFromData(data);
    final readAcknowledgementRowFuture = messageId == null
        ? Future<Map<String, Object?>?>.value(null)
        : dbLoadExactGroupNotificationReadAcknowledgement(
            db,
            groupId: groupId,
            contentKind: 'message',
            eventIdentity: messageId,
          );
    final canonicalMessageRowFuture = messageId == null
        ? Future<Map<String, Object?>?>.value(null)
        : dbLoadGroupMessage(db, messageId);
    final groupRow = await groupRowFuture;
    final localMemberRow = await localMemberRowFuture;
    final memberRows = await memberRowsFuture;
    final groupKeyRow = await groupKeyRowFuture;
    final readAcknowledgementRow = await readAcknowledgementRowFuture;
    final canonicalMessageRow = await canonicalMessageRowFuture;
    Map<String, Object?>? hydratedGroupKeyRow;
    try {
      hydratedGroupKeyRow = await hydrateBackgroundGroupKeyRow(
        groupKeyRow: groupKeyRow,
        secureStore: secureStore,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_BACKGROUND_MESSAGE_KEY_LOAD_ERROR',
        details: {'kind': 'group', 'errorType': e.runtimeType.toString()},
      );
    }
    return groupMessageLocalStateFromRows(
      data: data,
      identityRow: identityRow,
      groupRow: groupRow,
      localMemberRow: localMemberRow,
      memberRows: memberRows,
      groupKeyRow: hydratedGroupKeyRow,
      readAcknowledgementRow: readAcknowledgementRow,
      canonicalMessageRow: canonicalMessageRow,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_MESSAGE_LOCAL_STATE_ERROR',
      details: {'kind': 'group', 'errorType': e.runtimeType.toString()},
    );
    return null;
  } finally {
    await db?.close();
  }
}

@visibleForTesting
BackgroundDirectReactionLocalState? directReactionLocalStateFromRows({
  required Map<String, dynamic> data,
  required Map<String, Object?>? identityRow,
  required Map<String, Object?>? contactRow,
  required Map<String, Object?>? targetMessageRow,
  required String? mlKemSecretKey,
}) {
  final action = _trimToNull(data['action']);
  final senderPeerId =
      _trimToNull(data['sender_id']) ?? _trimToNull(data['from']);
  final eventId =
      _trimToNull(data['event_id']) ?? _trimToNull(data['reaction_id']);
  final targetMessageId =
      _trimToNull(data['target_message_id']) ??
      _trimToNull(data['targetMessageId']);
  final localPeerId = _trimToNull(identityRow?['peer_id']);
  final contactPeerId = _trimToNull(contactRow?['peer_id']);
  final targetId = _trimToNull(targetMessageRow?['id']);
  final targetContactPeerId = _trimToNull(targetMessageRow?['contact_peer_id']);
  final targetSenderPeerId = _trimToNull(targetMessageRow?['sender_peer_id']);
  final actorUsername = _trimToNull(contactRow?['username']);
  final blocked = (contactRow?['is_blocked'] as num?)?.toInt() == 1;
  final contactArchived = (contactRow?['is_archived'] as num?)?.toInt() == 1;
  final incoming = (targetMessageRow?['is_incoming'] as num?)?.toInt() != 0;
  final deleted = targetMessageRow?['deleted_at'] != null;

  if (action != 'add' ||
      eventId == null ||
      senderPeerId == null ||
      targetMessageId == null ||
      localPeerId == null ||
      contactPeerId != senderPeerId ||
      actorUsername == null ||
      blocked ||
      contactArchived ||
      targetId != targetMessageId ||
      targetContactPeerId != senderPeerId ||
      targetSenderPeerId != localPeerId ||
      incoming ||
      deleted) {
    return null;
  }

  return BackgroundDirectReactionLocalState(
    previewContext: DirectReactionNotificationContext(
      actorPeerId: senderPeerId,
      actorUsername: actorUsername,
      targetMessageId: targetMessageId,
    ),
    mlKemSecretKey: _trimToNull(mlKemSecretKey),
  );
}

Future<BackgroundDirectReactionLocalState?>
_resolveDirectReactionLocalStateFromEncryptedDb(RemoteMessage message) async {
  final data = message.data;
  final senderPeerId =
      _trimToNull(data['sender_id']) ?? _trimToNull(data['from']);
  final targetMessageId =
      _trimToNull(data['target_message_id']) ??
      _trimToNull(data['targetMessageId']);
  if (senderPeerId == null || targetMessageId == null) {
    return null;
  }

  Database? db;
  try {
    final secureStore = FlutterSecureKeyStore();
    final dbKey = await secureStore.read(_backgroundDbEncryptionKey);
    if (dbKey == null || dbKey.trim().isEmpty) {
      return null;
    }
    final dbPath = await getDatabasesPath();
    db = await openBackgroundIdentityDbReadTolerant(
      path: '$dbPath/identity.db',
      key: dbKey,
    );
    final rows = await Future.wait<Map<String, Object?>?>([
      dbLoadIdentityRow(db),
      dbLoadContact(db, senderPeerId),
      dbLoadMessage(db, targetMessageId),
    ]);
    return directReactionLocalStateFromRows(
      data: data,
      identityRow: rows[0],
      contactRow: rows[1],
      targetMessageRow: rows[2],
      mlKemSecretKey: await secureStore.read(_backgroundMlKemSecretKey),
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_REACTION_LOCAL_STATE_ERROR',
      details: {'error': e.toString()},
    );
    return null;
  } finally {
    await db?.close();
  }
}

@visibleForTesting
Future<Map<String, Object?>?> hydrateBackgroundGroupKeyRow({
  required Map<String, Object?>? groupKeyRow,
  required SecureKeyStore secureStore,
}) async {
  if (groupKeyRow == null) return null;
  final storedKey = _trimToNull(groupKeyRow['encrypted_key']);
  if (storedKey == null) return null;
  if (!isSecureStoreReference(storedKey)) {
    return groupKeyRow;
  }

  final hydratedKey = _trimToNull(
    await secureStore.read(secureStoreKeyFromReference(storedKey)),
  );
  if (hydratedKey == null) return null;
  return <String, Object?>{...groupKeyRow, 'encrypted_key': hydratedKey};
}

@visibleForTesting
BackgroundGroupReactionLocalState? groupReactionLocalStateFromRows({
  required Map<String, dynamic> data,
  required Map<String, Object?>? identityRow,
  required Map<String, Object?>? groupRow,
  required Map<String, Object?>? localMemberRow,
  required Map<String, Object?>? actorMemberRow,
  required Map<String, Object?>? targetMessageRow,
  required Map<String, Object?>? groupKeyRow,
  required Map<String, Object?>? latestGroupKeyRow,
  required Map<String, Object?>? currentReactionRow,
  Map<String, Object?>? readAcknowledgementRow,
  required String? localInstallationTransportPeerId,
  required VerifiedGroupReactionNotificationNomination? verifiedNomination,
  Iterable<Map<String, Object?>> targetAttachmentRows =
      const <Map<String, Object?>>[],
}) {
  final action = _trimToNull(data['action']);
  final eventId =
      _trimToNull(data['event_id']) ?? _trimToNull(data['reaction_id']);
  final groupId = _trimToNull(data['groupId']) ?? _trimToNull(data['group_id']);
  final actorPeerId =
      _trimToNull(data['reactor_peer_id']) ??
      _trimToNull(data['sender_id']) ??
      _trimToNull(data['from']);
  final targetMessageId =
      _trimToNull(data['target_message_id']) ??
      _trimToNull(data['targetMessageId']);
  final keyEpoch = int.tryParse(data['keyEpoch']?.toString() ?? '');
  final localPeerId = _trimToNull(identityRow?['peer_id']);
  final storedGroupId = _trimToNull(groupRow?['id']);
  final groupName = _trimToNull(groupRow?['name']);
  final groupPolicyInput = _groupNotificationDisplayPolicyInputFromRows(
    expectedGroupId: groupId,
    localPeerId: localPeerId,
    groupRow: groupRow,
    localMemberRow: localMemberRow,
  );
  final storedActor = _trimToNull(actorMemberRow?['peer_id']);
  final actorUsername = _trimToNull(actorMemberRow?['username']);
  final targetId = _trimToNull(targetMessageRow?['id']);
  final targetGroupId = _trimToNull(targetMessageRow?['group_id']);
  final targetSenderPeerId = _trimToNull(targetMessageRow?['sender_peer_id']);
  final targetIncoming =
      (targetMessageRow?['is_incoming'] as num?)?.toInt() != 0;
  final targetPolicy = GroupPrivateMediaPolicy.fromDatabase(
    version: targetMessageRow?['media_policy_version'],
    lifecycle: targetMessageRow?['media_lifecycle'],
    durationSeconds: targetMessageRow?['media_duration_seconds'],
    protected: targetMessageRow?['media_protected'],
  );
  final reactionDisplayEligibility =
      evaluateGroupReactionNotificationDisplayPolicy(
        GroupReactionNotificationDisplayPolicyInput(
          group: groupPolicyInput,
          hasCurrentLocalAuthoredTarget:
              targetId == targetMessageId &&
              targetGroupId == groupId &&
              targetSenderPeerId == localPeerId &&
              !targetIncoming,
          targetRequiresRedaction: targetPolicy.requiresRedaction,
        ),
      );
  final targetKind = groupReactionTargetKindForGroupOwnedMediaTypes(
    targetAttachmentRows
        .where(
          (row) =>
              _trimToNull(row['owner_lane']) == MediaOwnerLane.group.dbValue,
        )
        .map((row) => _trimToNull(row['media_type']) ?? 'unknown'),
  );
  final keyGroupId = _trimToNull(groupKeyRow?['group_id']);
  final storedKeyEpoch = (groupKeyRow?['key_generation'] as num?)?.toInt();
  final groupKey = _trimToNull(groupKeyRow?['encrypted_key']);
  final latestKeyGroupId = _trimToNull(latestGroupKeyRow?['group_id']);
  final latestKeyEpoch = (latestGroupKeyRow?['key_generation'] as num?)
      ?.toInt();
  final localTransportPeerId = _trimToNull(localInstallationTransportPeerId);
  final localDevice = _activeGroupMemberDeviceForTransport(
    localMemberRow,
    localTransportPeerId,
  );
  final actorDevice = _activeGroupMemberDeviceForTransport(
    actorMemberRow,
    verifiedNomination?.reactorTransportPeerId,
  );
  final currentReactionMessageId = _trimToNull(
    currentReactionRow?['message_id'],
  );
  final currentReactionSenderPeerId = _trimToNull(
    currentReactionRow?['sender_peer_id'],
  );
  final currentReactionTimestamp = _trimToNull(
    currentReactionRow?['timestamp'],
  );
  final currentReactionRemovedAt = _trimToNull(
    currentReactionRow?['removed_at'],
  );
  final currentReactionAcknowledged =
      currentReactionRow?['notification_acknowledged_at'] != null;
  final currentReactionTerminalEventIdentity = _trimToNull(
    currentReactionRow?['notification_display_terminal_event_id'],
  );
  final exactCanonicalReactionAcknowledged =
      eventId != null &&
      currentReactionAcknowledged &&
      currentReactionTerminalEventIdentity ==
          boundedReactionEventIdentity(eventId);
  final exactReadAcknowledgement = eventId == null || groupId == null
      ? false
      : _isExactGroupNotificationReadAcknowledgement(
          readAcknowledgementRow,
          groupId: groupId,
          contentKind: 'reaction',
          eventIdentity: boundedReactionEventIdentity(eventId),
        );

  if (action != 'add' ||
      eventId == null ||
      groupId == null ||
      actorPeerId == null ||
      targetMessageId == null ||
      keyEpoch == null ||
      localPeerId == null ||
      actorPeerId == localPeerId ||
      storedGroupId != groupId ||
      groupName == null ||
      !reactionDisplayEligibility.shouldDisplay ||
      localTransportPeerId == null ||
      localDevice == null ||
      storedActor != actorPeerId ||
      actorUsername == null ||
      verifiedNomination == null ||
      actorDevice == null ||
      actorDevice.deviceSigningPublicKey !=
          verifiedNomination.senderPublicKey ||
      keyGroupId != groupId ||
      latestKeyGroupId != groupId ||
      !isCurrentGroupReactionKeyEpoch(
        requestedEpoch: keyEpoch,
        selectedEpoch: storedKeyEpoch,
        latestEpoch: latestKeyEpoch,
      ) ||
      groupKey == null ||
      isSecureStoreReference(groupKey) ||
      exactCanonicalReactionAcknowledged ||
      exactReadAcknowledgement) {
    return null;
  }
  if (currentReactionRow != null &&
      (currentReactionMessageId != targetMessageId ||
          currentReactionSenderPeerId != actorPeerId ||
          currentReactionTimestamp == null)) {
    return null;
  }

  return BackgroundGroupReactionLocalState(
    previewContext: GroupReactionNotificationContext(
      groupId: groupId,
      groupName: groupName,
      actorPeerId: actorPeerId,
      actorUsername: actorUsername,
      targetMessageId: targetMessageId,
      targetKind: targetKind,
      currentReactionId: _trimToNull(currentReactionRow?['id']),
      currentReactionTimestamp: currentReactionTimestamp,
      currentReactionRemovedAt: currentReactionRemovedAt,
      currentReactionAcknowledged: currentReactionAcknowledged,
    ),
    groupKey: groupKey,
    keyEpoch: keyEpoch,
    nominationVerified: true,
  );
}

GroupMemberDeviceIdentity? _activeGroupMemberDeviceForTransport(
  Map<String, Object?>? memberRow,
  String? transportPeerId,
) {
  if (memberRow == null || transportPeerId == null) return null;
  final devices = GroupMemberDeviceIdentity.listFromJsonString(
    memberRow['devices_json'] as String?,
  );
  for (final device in devices) {
    if (device.isActive && device.transportPeerId == transportPeerId) {
      return device;
    }
  }
  if (devices.isNotEmpty) return null;

  // Legacy single-device rows bind account and transport ids together. Require
  // a signing key so a sparse account-only row cannot masquerade as an active
  // installation.
  final peerId = _trimToNull(memberRow['peer_id']);
  final publicKey = _trimToNull(memberRow['public_key']);
  if (peerId != transportPeerId || publicKey == null) return null;
  return GroupMemberDeviceIdentity(
    deviceId: peerId!,
    transportPeerId: peerId,
    deviceSigningPublicKey: publicKey,
  );
}

Future<BackgroundGroupReactionLocalState?>
_resolveGroupReactionLocalStateFromEncryptedDb(RemoteMessage message) async {
  final data = message.data;
  final groupId = _trimToNull(data['groupId']) ?? _trimToNull(data['group_id']);
  final actorPeerId =
      _trimToNull(data['reactor_peer_id']) ??
      _trimToNull(data['sender_id']) ??
      _trimToNull(data['from']);
  final targetMessageId =
      _trimToNull(data['target_message_id']) ??
      _trimToNull(data['targetMessageId']);
  final eventId =
      _trimToNull(data['event_id']) ?? _trimToNull(data['reaction_id']);
  final keyEpoch = int.tryParse(data['keyEpoch']?.toString() ?? '');
  if (groupId == null ||
      actorPeerId == null ||
      targetMessageId == null ||
      eventId == null ||
      keyEpoch == null) {
    return null;
  }

  Database? db;
  try {
    final secureStore = FlutterSecureKeyStore();
    final dbKey = await secureStore.read(_backgroundDbEncryptionKey);
    if (dbKey == null || dbKey.trim().isEmpty) return null;
    final localTransportPeerId = await secureStore.read(
      _backgroundPushTransportPeerId,
    );
    final verifiedNomination = await verifyGroupReactionNotificationNomination(
      data: data,
      localTransportPeerId: localTransportPeerId,
      verifySignature:
          ({
            required publicKey,
            required signedPayload,
            required signature,
          }) async {
            final result = await const BackgroundPushCrypto().verifyPayload(
              publicKey: publicKey,
              data: signedPayload,
              signature: signature,
            );
            return result['ok'] == true && result['valid'] == true;
          },
    );
    if (verifiedNomination == null) return null;
    final dbPath = await getDatabasesPath();
    db = await openBackgroundIdentityDbReadTolerant(
      path: '$dbPath/identity.db',
      key: dbKey,
    );
    final identityRow = await dbLoadIdentityRow(db);
    final localPeerId = _trimToNull(identityRow?['peer_id']);
    if (localPeerId == null) return null;
    final rows = await Future.wait<Map<String, Object?>?>([
      dbLoadGroup(db, groupId),
      dbLoadGroupMember(db, groupId, localPeerId),
      dbLoadGroupMember(db, groupId, actorPeerId),
      dbLoadGroupMessage(db, targetMessageId),
      dbLoadGroupKeyByGeneration(db, groupId, keyEpoch),
      dbLoadLatestGroupKey(db, groupId),
      dbLoadActiveOrTombstonedReactionForSender(
        db,
        targetMessageId,
        actorPeerId,
      ),
      dbLoadExactGroupNotificationReadAcknowledgement(
        db,
        groupId: groupId,
        contentKind: 'reaction',
        eventIdentity: boundedReactionEventIdentity(eventId),
      ),
    ]);
    final targetAttachmentRows = await dbLoadMediaForMessage(
      db,
      targetMessageId,
      ownerLane: MediaOwnerLane.group.dbValue,
    );
    final hydratedGroupKeyRow = await hydrateBackgroundGroupKeyRow(
      groupKeyRow: rows[4],
      secureStore: secureStore,
    );
    return groupReactionLocalStateFromRows(
      data: data,
      identityRow: identityRow,
      groupRow: rows[0],
      localMemberRow: rows[1],
      actorMemberRow: rows[2],
      targetMessageRow: rows[3],
      groupKeyRow: hydratedGroupKeyRow,
      latestGroupKeyRow: rows[5],
      currentReactionRow: rows[6],
      readAcknowledgementRow: rows[7],
      localInstallationTransportPeerId: localTransportPeerId,
      verifiedNomination: verifiedNomination,
      targetAttachmentRows: targetAttachmentRows,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_GROUP_REACTION_LOCAL_STATE_ERROR',
      details: {'error': e.toString()},
    );
    return null;
  } finally {
    await db?.close();
  }
}

Future<BackgroundGroupNotificationPostShowDecision>
_validateBackgroundGroupNotificationAfterShowFromEncryptedDb(
  BackgroundManagedGroupNotificationComparand comparand,
) async {
  Database? db;
  try {
    final key = await FlutterSecureKeyStore().read(_backgroundDbEncryptionKey);
    if (_trimToNull(key) == null) {
      return BackgroundGroupNotificationPostShowDecision.unknown;
    }
    final dbPath = await getDatabasesPath();
    db = await openBackgroundIdentityDbReadTolerant(
      path: '$dbPath/identity.db',
      key: key!,
    );
    final identityRow = await dbLoadIdentityRow(db);
    final localPeerId = _trimToNull(identityRow?['peer_id']);
    final commonRows = await Future.wait<Map<String, Object?>?>([
      dbLoadGroup(db, comparand.groupId),
      localPeerId == null
          ? Future<Map<String, Object?>?>.value(null)
          : dbLoadGroupMember(db, comparand.groupId, localPeerId),
    ]);

    switch (comparand) {
      case BackgroundGroupMessageNotificationComparand message:
        final rows = await Future.wait<Map<String, Object?>?>([
          dbLoadGroupMessage(db, message.messageId),
          dbLoadGroupMessageLocalDeletion(db, message.messageId),
          dbLoadExactGroupNotificationReadAcknowledgement(
            db,
            groupId: message.groupId,
            contentKind: 'message',
            eventIdentity: message.messageId,
          ),
        ]);
        return evaluateBackgroundGroupNotificationPostShowState(
          comparand: message,
          localPeerId: localPeerId,
          groupRow: commonRows[0],
          localMemberRow: commonRows[1],
          messageRow: rows[0],
          messageDeletionRow: rows[1],
          readAcknowledgementRow: rows[2],
        );
      case BackgroundGroupReactionNotificationComparand reaction:
        final rows = await Future.wait<Map<String, Object?>?>([
          dbLoadActiveOrTombstonedReactionForSender(
            db,
            reaction.messageId,
            reaction.senderPeerId,
          ),
          dbLoadGroupMessage(db, reaction.messageId),
          dbLoadGroupMessageLocalDeletion(db, reaction.messageId),
          dbLoadExactGroupNotificationReadAcknowledgement(
            db,
            groupId: reaction.groupId,
            contentKind: 'reaction',
            eventIdentity: reaction.notificationEventIdentity,
          ),
        ]);
        return evaluateBackgroundGroupNotificationPostShowState(
          comparand: reaction,
          localPeerId: localPeerId,
          groupRow: commonRows[0],
          localMemberRow: commonRows[1],
          reactionRow: rows[0],
          targetMessageRow: rows[1],
          targetDeletionRow: rows[2],
          readAcknowledgementRow: rows[3],
        );
      case BackgroundProvisionalGroupReactionNotificationComparand reaction:
        final rows = await Future.wait<Map<String, Object?>?>([
          dbLoadActiveOrTombstonedReactionForSender(
            db,
            reaction.messageId,
            reaction.senderPeerId,
          ),
          dbLoadGroupMessage(db, reaction.messageId),
          dbLoadGroupMessageLocalDeletion(db, reaction.messageId),
          dbLoadExactGroupNotificationReadAcknowledgement(
            db,
            groupId: reaction.groupId,
            contentKind: 'reaction',
            eventIdentity: reaction.notificationEventIdentity,
          ),
        ]);
        return evaluateBackgroundGroupNotificationPostShowState(
          comparand: reaction,
          localPeerId: localPeerId,
          groupRow: commonRows[0],
          localMemberRow: commonRows[1],
          reactionRow: rows[0],
          targetMessageRow: rows[1],
          targetDeletionRow: rows[2],
          readAcknowledgementRow: rows[3],
        );
    }
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_GROUP_POST_SHOW_READ_ERROR',
      details: {'errorType': error.runtimeType.toString()},
    );
    return BackgroundGroupNotificationPostShowDecision.unknown;
  } finally {
    await db?.close();
  }
}

Future<PushFallbackNotificationDisplayEligibility>
_allowsBackgroundAccountNotificationDisplay() async {
  try {
    final allowed = await _backgroundAccountMigrationNetworkGate(
      operation: 'push_background_notification_display',
    );
    if (allowed) {
      return const PushFallbackNotificationDisplayEligibility.allow();
    }
    return const PushFallbackNotificationDisplayEligibility.suppressed(
      'account_migration_network_blocked',
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_ACCOUNT_MIGRATION_GATE_ERROR',
      details: {'error': e.toString()},
    );
    return const PushFallbackNotificationDisplayEligibility.suppressed(
      'account_migration_network_gate_error',
    );
  }
}

Future<bool> _defaultBackgroundAccountMigrationNetworkGate({
  String? peerId,
  required String operation,
}) {
  final gate = AccountMigrationRuntimeNetworkGate(
    authorityRepository: SecureKeyStoreAccountMigrationAuthorityRepository(
      secureKeyStore: FlutterSecureKeyStore(),
    ),
  );
  // Notification display has no relay side effects, so it follows the
  // display policy (which stays allowed during a Move Account export pause)
  // rather than the network-side-effect policy.
  if (operation == 'push_background_notification_display') {
    return gate.allowsAccountNotificationDisplay(peerId: peerId);
  }
  return gate.allowsAccountNetworkSideEffects(
    peerId: peerId,
    operation: operation,
  );
}

/// Maps encrypted-DB rows into the same fail-closed policy used by live and
/// foreground group notification producers.
@visibleForTesting
GroupMessageNotificationDisplayEligibility
groupNotificationDisplayEligibilityFromRows({
  required String? expectedGroupId,
  required String? localPeerId,
  required Map<String, Object?>? groupRow,
  required Map<String, Object?>? localMemberRow,
}) {
  return evaluateGroupNotificationDisplayPolicy(
    _groupNotificationDisplayPolicyInputFromRows(
      expectedGroupId: expectedGroupId,
      localPeerId: localPeerId,
      groupRow: groupRow,
      localMemberRow: localMemberRow,
    ),
  );
}

GroupNotificationDisplayPolicyInput
_groupNotificationDisplayPolicyInputFromRows({
  required String? expectedGroupId,
  required String? localPeerId,
  required Map<String, Object?>? groupRow,
  required Map<String, Object?>? localMemberRow,
}) {
  final normalizedGroupId = _trimToNull(expectedGroupId);
  final normalizedLocalPeerId = _trimToNull(localPeerId);
  final storedGroupId = _trimToNull(groupRow?['id']);
  final storedMemberGroupId = _trimToNull(localMemberRow?['group_id']);
  final storedMemberPeerId = _trimToNull(localMemberRow?['peer_id']);
  final groupExists =
      normalizedGroupId != null && storedGroupId == normalizedGroupId;
  final hasCurrentMembership =
      groupExists &&
      normalizedLocalPeerId != null &&
      storedMemberGroupId == normalizedGroupId &&
      storedMemberPeerId == normalizedLocalPeerId;

  return GroupNotificationDisplayPolicyInput(
    groupExists: groupExists,
    hasCurrentLocalMembership: hasCurrentMembership,
    groupType: _trimToNull(groupRow?['type']),
    isMuted: (groupRow?['is_muted'] as num?)?.toInt() == 1,
    isArchived: (groupRow?['is_archived'] as num?)?.toInt() == 1,
    isDissolved: (groupRow?['is_dissolved'] as num?)?.toInt() == 1,
    hasDissolvedAt: groupRow?['dissolved_at'] != null,
    hasSelfRemovedAt: groupRow?['self_removed_at'] != null,
  );
}

/// Compatibility seam for callers that have already proved current local
/// membership. Missing/unknown group fields still fail closed.
GroupMessageNotificationDisplayEligibility groupMemberMessageDisplayEligibility(
  Map<String, Object?> groupRow,
) {
  return evaluateGroupNotificationDisplayPolicy(
    GroupNotificationDisplayPolicyInput(
      groupExists: true,
      hasCurrentLocalMembership: true,
      groupType: _trimToNull(groupRow['type']),
      isMuted: (groupRow['is_muted'] as num?)?.toInt() == 1,
      isArchived: (groupRow['is_archived'] as num?)?.toInt() == 1,
      isDissolved: (groupRow['is_dissolved'] as num?)?.toInt() == 1,
      hasDissolvedAt: groupRow['dissolved_at'] != null,
      hasSelfRemovedAt: groupRow['self_removed_at'] != null,
    ),
  );
}

/// 218 Phase A — read-tolerant identity.db open for the background isolate's
/// group-eligibility read (the 5th identity.db open site). Tries the raw-key
/// literal first (post-Phase-B raw DBs, PBKDF2 skipped), falls back to
/// passphrase for legacy DBs. Always readOnly + singleInstance:false (this runs
/// in a separate Android background process). Extracted as a testable seam so
/// SC-B can prove the raw-read path against a manufactured raw fixture without
/// standing up the full FCM push machinery.
@visibleForTesting
Future<Database> openBackgroundIdentityDbReadTolerant({
  required String path,
  required String key,
}) async {
  final record = parseCipherKeyRecord(key);
  if (!isValid256BitHexKey(record.hex)) {
    throw StateError('background db_encryption_key is not a 64-hex key');
  }
  try {
    return await openDatabase(
      path,
      password: "x'${record.hex}'", // RAW_KEY
      readOnly: true,
      singleInstance: false,
    );
  } catch (_) {
    if (record.mode == CipherKeyMode.raw) rethrow;
    return await openDatabase(
      path,
      password: record.hex, // LEGACY_PASSPHRASE_FALLBACK
      readOnly: true,
      singleInstance: false,
    );
  }
}

Future<GroupMessageNotificationDisplayEligibility>
_resolveGroupMessageNotificationDisplayEligibilityFromEncryptedDb(
  String groupId,
) async {
  Database? db;
  try {
    final key = await FlutterSecureKeyStore().read(_backgroundDbEncryptionKey);
    if (key == null || key.trim().isEmpty) {
      return const GroupMessageNotificationDisplayEligibility.suppressed(
        'background_local_state_unavailable',
      );
    }

    final dbPath = await getDatabasesPath();
    db = await openBackgroundIdentityDbReadTolerant(
      path: '$dbPath/identity.db',
      key: key,
    );

    final identityRow = await dbLoadIdentityRow(db);
    final localPeerId = identityRow?['peer_id']?.toString().trim();
    if (localPeerId == null || localPeerId.isEmpty) {
      return const GroupMessageNotificationDisplayEligibility.suppressed(
        'unknown_local_identity',
      );
    }

    final groupRow = await dbLoadGroup(db, groupId);
    if (groupRow != null) {
      final memberRow = await dbLoadGroupMember(db, groupId, localPeerId);
      if (memberRow != null) {
        // 04-P0 / SI-1: honor mute on the Android background path too. The
        // `groups` row carries is_muted (dbLoadGroup selects all columns), so
        // no app-group projection is needed here.
        return groupMemberMessageDisplayEligibility(groupRow);
      }
    }

    final pendingInviteRow = await dbLoadPendingGroupInvite(db, groupId);
    if (pendingInviteRow != null) {
      return const GroupMessageNotificationDisplayEligibility.suppressed(
        'pending_invite',
      );
    }

    if (groupRow != null) {
      return const GroupMessageNotificationDisplayEligibility.suppressed(
        'local_member_missing',
      );
    }

    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'group_missing',
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_DISPLAY_ELIGIBILITY_ERROR',
      details: {'error': e.toString()},
    );
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'background_local_state_unavailable',
    );
  } finally {
    await db?.close();
  }
}
