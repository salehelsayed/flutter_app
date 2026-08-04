import 'dart:async';
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
import 'package:flutter_app/core/notifications/notification_service.dart';
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
import 'package:flutter_app/core/database/helpers/direct_notification_reaction_terminal_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_read_acknowledgement_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_invites_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
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
import 'package:flutter_app/features/conversation/application/direct_conversation_notification_snapshot.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/background_storage_liveness_journal.dart';
import 'package:flutter_app/features/push/application/group_notification_display_policy.dart';
import 'package:flutter_app/features/push/application/group_reaction_notification_copy.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/application/group_conversation_notification_snapshot.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final FlutterLocalNotificationsPlugin _backgroundNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
bool _backgroundNotificationsInitialized = false;
const String _backgroundDbEncryptionKey = 'db_encryption_key';
const String _backgroundMlKemSecretKey = 'identity_ml_kem_secret_key';
const String _backgroundPushTransportPeerId =
    'push_registration_transport_peer_id';
const Duration _productionBackgroundStorageAggregateDeadline = Duration(
  seconds: 8,
);
const Duration _productionBackgroundStoragePhaseDeadline = Duration(seconds: 2);
Duration _backgroundStorageAggregateDeadline =
    _productionBackgroundStorageAggregateDeadline;
Duration _backgroundStoragePhaseDeadline =
    _productionBackgroundStoragePhaseDeadline;
BackgroundStorageLivenessJournal _backgroundStorageLivenessJournal =
    BackgroundStorageLivenessJournal.mobileDefault();
typedef BackgroundStorageMonotonicClock = Duration Function();
BackgroundStorageMonotonicClock Function()
_backgroundStorageMonotonicClockFactory = _newBackgroundStorageStopwatchClock;

BackgroundStorageMonotonicClock _newBackgroundStorageStopwatchClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}

final class BackgroundStorageDeadlineExceeded implements Exception {
  const BackgroundStorageDeadlineExceeded({
    required this.phase,
    required this.elapsed,
  });

  final String phase;
  final Duration elapsed;

  @override
  String toString() =>
      'BackgroundStorageDeadlineExceeded($phase, ${elapsed.inMilliseconds}ms)';
}

final class _BackgroundStorageDeadline {
  _BackgroundStorageDeadline({
    required this.aggregate,
    required this.phase,
    required this.enabled,
    required BackgroundStorageMonotonicClock elapsed,
  }) : _elapsed = elapsed,
       _startedAt = elapsed();

  final Duration aggregate;
  final Duration phase;
  final bool enabled;
  final BackgroundStorageMonotonicClock _elapsed;
  final Duration _startedAt;

  Duration get elapsed {
    final value = _elapsed() - _startedAt;
    return value.isNegative ? Duration.zero : value;
  }

  Future<T> run<T>(String phaseName, Future<T> Function() action) {
    if (!enabled) return action();
    final remaining = aggregate - elapsed;
    if (remaining <= Duration.zero) {
      throw BackgroundStorageDeadlineExceeded(
        phase: phaseName,
        elapsed: elapsed,
      );
    }
    final bound = remaining < phase ? remaining : phase;
    return action().timeout(
      bound,
      onTimeout: () => throw BackgroundStorageDeadlineExceeded(
        phase: phaseName,
        elapsed: elapsed,
      ),
    );
  }
}

@visibleForTesting
void debugSetBackgroundStorageDeadlineDurations({
  required Duration aggregate,
  required Duration phase,
}) {
  if (aggregate <= Duration.zero || phase <= Duration.zero) {
    throw ArgumentError('background storage deadlines must be positive');
  }
  _backgroundStorageAggregateDeadline = aggregate;
  _backgroundStoragePhaseDeadline = phase;
}

@visibleForTesting
void debugResetBackgroundStorageDeadlineDurations() {
  _backgroundStorageAggregateDeadline =
      _productionBackgroundStorageAggregateDeadline;
  _backgroundStoragePhaseDeadline = _productionBackgroundStoragePhaseDeadline;
}

@visibleForTesting
void debugSetBackgroundStorageLivenessJournal(
  BackgroundStorageLivenessJournal journal,
) {
  _backgroundStorageLivenessJournal = journal;
}

@visibleForTesting
void debugResetBackgroundStorageLivenessJournal() {
  _backgroundStorageLivenessJournal =
      BackgroundStorageLivenessJournal.mobileDefault();
}

@visibleForTesting
void debugSetBackgroundStorageMonotonicClockFactory(
  BackgroundStorageMonotonicClock Function() factory,
) {
  _backgroundStorageMonotonicClockFactory = factory;
}

@visibleForTesting
void debugResetBackgroundStorageMonotonicClockFactory() {
  _backgroundStorageMonotonicClockFactory = _newBackgroundStorageStopwatchClock;
}

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
typedef BackgroundPendingConversationNotificationOverlayResolver =
    Future<PendingConversationNotificationOverlayStore> Function();
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

enum BackgroundDirectNotificationPostShowDecision { keep, retire, unknown }

class BackgroundDirectReactionLocalState {
  const BackgroundDirectReactionLocalState({
    required this.previewContext,
    required this.mlKemSecretKey,
    this.snapshot,
  });

  final DirectReactionNotificationContext previewContext;
  final String? mlKemSecretKey;
  final ConversationNotificationSnapshot? snapshot;
}

class BackgroundDirectMessageLocalState {
  const BackgroundDirectMessageLocalState({
    required this.previewContext,
    required this.mlKemSecretKeys,
    this.snapshot,
  });

  final DirectMessageNotificationContext previewContext;

  /// Current key first, followed by prior identity keys newest-first.
  final List<String> mlKemSecretKeys;
  final ConversationNotificationSnapshot? snapshot;
}

class BackgroundGroupMessageLocalState {
  const BackgroundGroupMessageLocalState({
    required this.previewContext,
    required this.groupKey,
    required this.keyEpoch,
    this.snapshot,
  });

  final GroupMessageNotificationContext previewContext;
  final String? groupKey;
  final int? keyEpoch;
  final ConversationNotificationSnapshot? snapshot;
}

class BackgroundGroupReactionLocalState {
  const BackgroundGroupReactionLocalState({
    required this.previewContext,
    required this.groupKey,
    required this.keyEpoch,
    required this.nominationVerified,
    this.snapshot,
  });

  final GroupReactionNotificationContext previewContext;
  final String groupKey;
  final int keyEpoch;
  final bool nominationVerified;
  final ConversationNotificationSnapshot? snapshot;
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
BackgroundPendingConversationNotificationOverlayResolver
_backgroundPendingConversationNotificationOverlayResolver =
    PendingConversationNotificationOverlayStore.openDefault;
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

@visibleForTesting
void debugSetBackgroundPendingConversationNotificationOverlayResolver(
  BackgroundPendingConversationNotificationOverlayResolver resolver,
) {
  _backgroundPendingConversationNotificationOverlayResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundPendingConversationNotificationOverlayResolver() {
  _backgroundPendingConversationNotificationOverlayResolver =
      PendingConversationNotificationOverlayStore.openDefault;
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
  final storageDeadline = _BackgroundStorageDeadline(
    aggregate: _backgroundStorageAggregateDeadline,
    phase: _backgroundStoragePhaseDeadline,
    enabled: defaultTargetPlatform == TargetPlatform.android,
    elapsed: _backgroundStorageMonotonicClockFactory(),
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
    try {
      await storageDeadline.run(
        'recent_remote_mark',
        () => recentRemoteNotificationGate.markAnnouncement(
          payload: payload,
          messageId: messageId,
        ),
      );
    } on BackgroundStorageDeadlineExceeded catch (error) {
      await _recordBackgroundStorageDeferred(
        message,
        error,
        outcome: 'post_show_unknown',
      );
    }
  }

  if (!shouldShowBackgroundPushFallbackNotification(message)) {
    if (message.notification != null) {
      await markVisibleRemoteAnnouncement();
    }
    return;
  }

  try {
    await storageDeadline.run(
      'direct_stage',
      () => _stagePushEnvelopeIfPresent(message),
    );
  } on BackgroundStorageDeadlineExceeded catch (error) {
    // Direct staging is nonce-keyed and idempotent. Its detached write may
    // finish later, but it cannot display or retire a notification.
    await _recordBackgroundStorageDeferred(
      message,
      error,
      outcome: 'custody_write_pending',
    );
    return;
  }

  late final PushFallbackNotificationDisplayEligibility displayEligibility;
  try {
    displayEligibility = await storageDeadline.run(
      'display_eligibility',
      () => _backgroundPushNotificationDisplayEligibilityResolver(message),
    );
  } on BackgroundStorageDeadlineExceeded catch (error) {
    await _recordBackgroundStorageDeferred(
      message,
      error,
      outcome: 'storage_deferred',
    );
    return;
  }
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
  DurableNotificationTonePublicationResult? tonePublication;
  try {
    await _initializeBackgroundNotifications();
    late BackgroundPushNotificationFallback fallback;
    try {
      fallback = await storageDeadline.run(
        'preview_resolution',
        () => _backgroundPushNotificationResolver(message),
      );
    } on BackgroundStorageDeadlineExceeded catch (error) {
      await _recordBackgroundStorageDeferred(
        message,
        error,
        outcome: 'storage_deferred',
      );
      return;
    }
    try {
      await storageDeadline.run(
        'resolved_stage',
        () => _stageResolvedPushEnvelopeIfNeeded(message, fallback),
      );
    } on BackgroundStorageDeadlineExceeded catch (error) {
      await _recordBackgroundStorageDeferred(
        message,
        error,
        outcome: 'custody_write_pending',
      );
      return;
    }
    final dedupeKey = backgroundPushFallbackDedupeKey(message);
    var wasRecentlyShown = false;
    if (dedupeKey != null) {
      try {
        wasRecentlyShown = await storageDeadline.run(
          'recent_background_read',
          () => recentBackgroundNotificationGate.wasRecentlyShown(dedupeKey),
        );
      } on BackgroundStorageDeadlineExceeded catch (error) {
        await _recordBackgroundStorageDeferred(
          message,
          error,
          outcome: 'storage_deferred',
        );
        return;
      }
    }
    if (wasRecentlyShown) {
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
    final resolvedEventIdentity = fallback.resolvedEventIdentity;
    final reactionEventId = isReaction
        ? _trimToNull(message.data['event_id']) ??
              _trimToNull(message.data['reaction_id']) ??
              (resolvedEventIdentity?.kind ==
                      ConversationNotificationContentKind.reaction
                  ? resolvedEventIdentity?.canonicalEventId
                  : null)
        : null;
    if (isReaction && reactionEventId == null) return;
    final notificationEventIdentity = isOrdinaryMessage
        ? remoteNotificationMessageIdFromData(message.data) ??
              (resolvedEventIdentity?.kind ==
                      ConversationNotificationContentKind.message
                  ? resolvedEventIdentity?.canonicalEventId
                  : null)
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

    // The overlay is encrypted enrichment, not notification ownership. Run it
    // before creating a provisional event claim so a stalled secure-store
    // operation cannot age that claim into a reclaimable duplicate window.
    if (isOrdinaryMessage || isReaction) {
      try {
        final projected = await storageDeadline.run('pending_overlay', () async {
          final overlay =
              await _backgroundPendingConversationNotificationOverlayResolver();
          return overlay.project(
            conversationKey: conversationKey,
            canonicalSnapshot: fallback.snapshot,
            currentMessage:
                isOrdinaryMessage && notificationEventIdentity != null
                ? PendingConversationNotificationMessage(
                    eventId: notificationEventIdentity,
                    line: fallback.body,
                    occurredAtMicros:
                        message.sentTime?.toUtc().microsecondsSinceEpoch ?? 0,
                  )
                : null,
          );
        });
        fallback = fallback.withSnapshot(projected);
      } on BackgroundStorageDeadlineExceeded catch (error) {
        await _recordBackgroundStorageDeferred(
          message,
          error,
          outcome: 'storage_deferred',
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_NOTIFICATION_OVERLAY_ERROR',
          details: {
            'type': pushType,
            'errorType': error.runtimeType.toString(),
          },
        );
      } catch (error) {
        // The encrypted overlay is an enrichment. Canonical notification
        // delivery remains available if secure storage is temporarily down.
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_NOTIFICATION_OVERLAY_ERROR',
          details: {
            'type': pushType,
            'errorType': error.runtimeType.toString(),
          },
        );
      }
    }

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

    final directContentKind =
        routeTarget?.kind == NotificationRouteTargetKind.conversation &&
            notificationEventIdentity != null
        ? isReaction
              ? ConversationNotificationContentKind.reaction
              : isOrdinaryMessage
              ? ConversationNotificationContentKind.message
              : null
        : null;
    final contentKind = groupContentKind ?? directContentKind;
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
    Future<void> show({required bool publicationSilent}) =>
        _backgroundNotificationsPlugin.show(
          notificationId,
          fallback.title,
          fallback.body,
          mknoonConversationNotificationDetails(
            conversationKey: conversationKey,
            silent: publicationSilent,
            autoCancel: contentMetadata == null,
            snapshot: fallback.snapshot,
          ),
          payload: nativePayload,
        );
    Future<void> publishPrepared({required bool publicationSilent}) async {
      if (contentMetadata == null) {
        await show(publicationSilent: publicationSilent);
        return;
      }
      await notificationIdRegistry.replaceContent(
        conversationKey: conversationKey,
        notificationId: notificationId,
        metadata: contentMetadata,
        retireCurrent: () =>
            _backgroundNotificationsPlugin.cancel(notificationId),
        replace: () => show(publicationSilent: publicationSilent),
      );
    }

    DurableNotificationClaimedPublicationResult? claimedPublication;
    Future<void> publishAtNativeBoundary() async {
      Future<void> publishWithExactToneOwner() async {
        final reservation = notificationToneReservation;
        if (reservation == null) {
          await show(publicationSilent: silent);
          return;
        }
        tonePublication = await reservation.publishAndCommit(
          () => show(publicationSilent: false),
        );
        if (!tonePublication!.publishedAudibly) {
          await show(publicationSilent: true);
        }
      }

      claimedPublication = notificationEventClaim == null
          ? null
          : await notificationEventClaim.publishAndCommit(
              publishWithExactToneOwner,
            );
      if (claimedPublication == null) {
        await publishWithExactToneOwner();
      } else if (!claimedPublication!.published) {
        throw const _BackgroundNotificationClaimOwnershipLost();
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Registry allocation, retirement, and metadata preparation happen
      // before Android durable owners enter `publishing`. Only the actual
      // platform show call is ambiguous if its method-channel result fails.
      if (contentMetadata == null) {
        await publishAtNativeBoundary();
      } else {
        await notificationIdRegistry.replaceContent(
          conversationKey: conversationKey,
          notificationId: notificationId,
          metadata: contentMetadata,
          retireCurrent: () =>
              _backgroundNotificationsPlugin.cancel(notificationId),
          replace: publishAtNativeBoundary,
        );
      }
    } else {
      // Preserve the existing Apple/desktop ordering. Their coordination
      // files are shared with the NSE and do not use Android's `publishing`
      // recovery protocol.
      Future<void> publishWithLegacyToneOwner() async {
        final reservation = notificationToneReservation;
        if (reservation == null) {
          await publishPrepared(publicationSilent: silent);
          return;
        }
        tonePublication = await reservation.publishAndCommit(
          () => publishPrepared(publicationSilent: false),
        );
        if (!tonePublication!.publishedAudibly) {
          await publishPrepared(publicationSilent: true);
        }
      }

      claimedPublication = notificationEventClaim == null
          ? null
          : await notificationEventClaim.publishAndCommit(
              publishWithLegacyToneOwner,
            );
      if (claimedPublication == null) {
        await publishWithLegacyToneOwner();
      } else if (!claimedPublication!.published) {
        throw const _BackgroundNotificationClaimOwnershipLost();
      }
    }
    // The native callback returned successfully. Detach both owners before any
    // subsequent validation/bookkeeping so no later failure can reach the
    // outer catch and release them for a duplicate audible retry.
    final shownToneReservation = notificationToneReservation;
    notificationToneReservation = null;
    final shownMessageClaim = notificationEventClaim;
    notificationEventClaim = null;
    if (shownToneReservation != null) {
      // The native callback completed, so a later bookkeeping failure must
      // never release the audible right and permit a second immediate tone.
      if (tonePublication!.publishedAudibly &&
          !tonePublication!.toneCommitted) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_MESSAGE_TONE_COMMIT_FAILED',
          details: {'type': pushType},
        );
      }
    }
    if (shownMessageClaim != null) {
      notificationClaimCommitted = claimedPublication!.claimCommitted;
      // The native callback completed, so this producer must never release its
      // claim, even if a later compatibility-gate write fails.
      if (!notificationClaimCommitted) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_MESSAGE_CLAIM_COMMIT_FAILED',
          details: {'type': pushType},
        );
      }
    }
    var postShowStorageExpired = false;
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
            ? await storageDeadline.run(
                'group_post_show_validation',
                () => _backgroundGroupNotificationPostShowValidator(
                  groupComparand,
                ),
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
        // The native callback already returned. A read or cancellation failure
        // is unknown, not a publication failure: keep the card. Its tone and
        // event owners are committed or retained fail-closed, so the same push
        // cannot re-alert. Durable reconciliation retries the canonical
        // projection from the foreground runtime.
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_GROUP_POST_SHOW_UNKNOWN',
          details: {
            'type': pushType,
            'errorType': error.runtimeType.toString(),
          },
        );
        if (error is BackgroundStorageDeadlineExceeded) {
          postShowStorageExpired = true;
          await _recordBackgroundStorageDeferred(
            message,
            error,
            outcome: 'post_show_unknown',
          );
        }
      }
    }
    if (!postShowStorageExpired &&
        contentMetadata != null &&
        directContentKind != null &&
        routeTarget?.kind == NotificationRouteTargetKind.conversation) {
      final peerId = _trimToNull(routeTarget?.peerId);
      if (peerId != null) {
        try {
          final decision = await storageDeadline.run(
            'direct_post_show_validation',
            () => _validateBackgroundDirectNotificationAfterShow(
              peerId: peerId,
              metadata: contentMetadata,
            ),
          );
          if (decision == BackgroundDirectNotificationPostShowDecision.retire) {
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
              event: 'PUSH_BACKGROUND_DIRECT_POST_SHOW_RETIRED',
              details: {
                'type': pushType,
                'result': retired
                    ? 'retired_exact_generation'
                    : 'newer_generation_survived',
              },
            );
          }
        } catch (error) {
          // The native callback returned and its claim is committed or retained
          // fail-closed. Keep the exact managed generation. FlutterFire remains
          // read-only; the staged encrypted envelope transfers retry ownership
          // to foreground ingestion, whose canonical commit enqueues v107
          // reconciliation.
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_BACKGROUND_DIRECT_POST_SHOW_UNKNOWN',
            details: {
              'type': pushType,
              'errorType': error.runtimeType.toString(),
            },
          );
          if (error is BackgroundStorageDeadlineExceeded) {
            postShowStorageExpired = true;
            await _recordBackgroundStorageDeferred(
              message,
              error,
              outcome: 'post_show_unknown',
            );
          }
        }
      }
    }
    if (!postShowStorageExpired && dedupeKey != null) {
      try {
        await storageDeadline.run(
          'recent_background_mark',
          () => recentBackgroundNotificationGate.markShown(dedupeKey),
        );
      } on BackgroundStorageDeadlineExceeded catch (error) {
        postShowStorageExpired = true;
        await _recordBackgroundStorageDeferred(
          message,
          error,
          outcome: 'post_show_unknown',
        );
      }
    }
    // Exact committed message claims are the Android live/background dedupe
    // authority. Keep the recent-remote gate only for iOS NSE compatibility,
    // legacy/no-id pushes, or the documented durable-storage fail-open path.
    if (!postShowStorageExpired &&
        (!isOrdinaryMessage ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            notificationEventIdentity == null ||
            !notificationClaimCommitted)) {
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
    if (e is DurableNotificationPublicationAttemptedException) {
      // Android may already have accepted the card. Preserve the exact event
      // and any audible tone `publishing` residue fail-closed. If tone
      // coordination failed before its callback and the silent fallback was
      // ambiguous, its still-pending audible owner is safe to release.
      final unattemptedToneReservation =
          tonePublication?.publishedAudibly == false
          ? notificationToneReservation
          : null;
      notificationToneReservation = null;
      notificationEventClaim = null;
      if (unattemptedToneReservation != null) {
        try {
          await unattemptedToneReservation.release();
        } catch (releaseError) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_BACKGROUND_MESSAGE_TONE_RELEASE_FAILED',
            details: {
              'kind': 'pre_native_audible_owner',
              'errorType': releaseError.runtimeType.toString(),
            },
          );
        }
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_BACKGROUND_NOTIFICATION_PUBLICATION_OUTCOME_UNKNOWN',
        details: {
          'type': _trimToNull(message.data['type']),
          'errorType': e.errorType,
        },
      );
      return;
    }
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
    if (e is _BackgroundNotificationClaimOwnershipLost) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
        details: {
          'messageId': message.messageId,
          'reason': 'event_claim_ownership_lost_before_show',
        },
      );
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_BACKGROUND_NOTIFICATION_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}

final class _BackgroundNotificationClaimOwnershipLost implements Exception {
  const _BackgroundNotificationClaimOwnershipLost();
}

Future<void> _recordBackgroundStorageDeferred(
  RemoteMessage message,
  BackgroundStorageDeadlineExceeded error, {
  required String outcome,
}) async {
  final rawKind = _trimToNull(message.data['type']);
  final kind = switch (rawKind) {
    'new_message' => BackgroundStorageMessageKind.directMessage,
    'group_message' => BackgroundStorageMessageKind.groupMessage,
    'message_reaction' => BackgroundStorageMessageKind.directReaction,
    'group_reaction' => BackgroundStorageMessageKind.groupReaction,
    _ => BackgroundStorageMessageKind.unknown,
  };
  final phase = switch (error.phase) {
    'direct_stage' ||
    'resolved_stage' => BackgroundStorageLivenessPhase.directStaging,
    'display_eligibility' => BackgroundStorageLivenessPhase.displayEligibility,
    'recent_background_read' ||
    'recent_background_mark' ||
    'recent_remote_mark' => BackgroundStorageLivenessPhase.recentGate,
    'group_post_show_validation' || 'direct_post_show_validation' =>
      BackgroundStorageLivenessPhase.postShowValidation,
    'pending_overlay' => BackgroundStorageLivenessPhase.pendingOverlay,
    _ => BackgroundStorageLivenessPhase.localState,
  };
  final terminalOutcome = switch (outcome) {
    'post_show_unknown' => BackgroundStorageTerminalOutcome.shownStateUnknown,
    'notification_suppressed' =>
      BackgroundStorageTerminalOutcome.notificationSuppressed,
    _ => BackgroundStorageTerminalOutcome.storageDeferred,
  };
  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_BACKGROUND_STORAGE_DEFERRED',
    details: <String, Object?>{
      'kind': kind.wireName,
      'phase': phase.wireName,
      'outcome': terminalOutcome.wireName,
      'elapsedBucket': bucketBackgroundStorageElapsed(error.elapsed).wireName,
      'buildMode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'engineRole': 'flutterfire_background',
    },
  );
  await _backgroundStorageLivenessJournal.recordTerminal(
    kind: kind,
    phase: phase,
    outcome: terminalOutcome,
    elapsed: error.elapsed,
  );
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

Future<BackgroundDirectNotificationPostShowDecision>
_validateBackgroundDirectNotificationAfterShow({
  required String peerId,
  required ConversationNotificationContentMetadata metadata,
}) async {
  final eventIdentity = _trimToNull(metadata.eventIdentity);
  if (eventIdentity == null) {
    return BackgroundDirectNotificationPostShowDecision.unknown;
  }
  Database? db;
  try {
    final key = await FlutterSecureKeyStore().read(_backgroundDbEncryptionKey);
    if (_trimToNull(key) == null) {
      return BackgroundDirectNotificationPostShowDecision.unknown;
    }
    final dbPath = await getDatabasesPath();
    db = await openBackgroundIdentityDbReadTolerant(
      path: '$dbPath/identity.db',
      key: key!,
    );
    return validateBackgroundDirectNotificationAfterShowInDatabase(
      db,
      peerId: peerId,
      metadata: metadata,
    );
  } finally {
    await db?.close();
  }
}

/// Read-only FlutterFire H0 seam. Unknown canonical materialization remains
/// owned by the already-staged encrypted envelope; foreground ingestion will
/// commit canonical state and enqueue v107 reconciliation under its write
/// lease. This method must never mutate [db].
@visibleForTesting
Future<BackgroundDirectNotificationPostShowDecision>
validateBackgroundDirectNotificationAfterShowInDatabase(
  Database db, {
  required String peerId,
  required ConversationNotificationContentMetadata metadata,
}) async {
  final eventIdentity = _trimToNull(metadata.eventIdentity);
  if (eventIdentity == null) {
    return BackgroundDirectNotificationPostShowDecision.unknown;
  }
  final contact = await dbLoadContact(db, peerId);
  final contactEligible =
      _trimToNull(contact?['peer_id']) == peerId &&
      (contact?['is_blocked'] as num?)?.toInt() != 1 &&
      (contact?['is_archived'] as num?)?.toInt() != 1;
  if (!contactEligible) {
    return BackgroundDirectNotificationPostShowDecision.retire;
  }

  final acknowledgement =
      await dbLoadExactDirectNotificationReadAcknowledgement(
        db,
        peerId: peerId,
        contentKind: metadata.kind.name,
        eventIdentity: eventIdentity,
        generation: metadata.generation,
      );
  if (acknowledgement != null) {
    return BackgroundDirectNotificationPostShowDecision.retire;
  }

  switch (metadata.kind) {
    case ConversationNotificationContentKind.message:
      final message = await dbLoadMessage(db, eventIdentity);
      if (message == null) {
        return BackgroundDirectNotificationPostShowDecision.unknown;
      }
      final canonical =
          _trimToNull(message['contact_peer_id']) == peerId &&
          (message['is_incoming'] as num?)?.toInt() == 1 &&
          message['read_at'] == null &&
          message['deleted_at'] == null &&
          message['hidden_at'] == null;
      return canonical
          ? BackgroundDirectNotificationPostShowDecision.keep
          : BackgroundDirectNotificationPostShowDecision.retire;
    case ConversationNotificationContentKind.reaction:
      final terminal =
          await dbLoadDirectNotificationReactionTerminalEventByIdentity(
            db,
            peerId: peerId,
            terminalEventId: eventIdentity,
          );
      if (terminal == null) {
        return BackgroundDirectNotificationPostShowDecision.unknown;
      }
      if (terminal['notification_acknowledged_at'] != null) {
        return BackgroundDirectNotificationPostShowDecision.retire;
      }
      final messageId = terminal['message_id'] as String;
      final actorPeerId = terminal['actor_peer_id'] as String;
      final target = await dbLoadMessage(db, messageId);
      final reaction = await dbLoadActiveOrTombstonedReactionForSender(
        db,
        messageId,
        actorPeerId,
      );
      final canonical =
          _trimToNull(target?['contact_peer_id']) == peerId &&
          (target?['is_incoming'] as num?)?.toInt() == 0 &&
          target?['deleted_at'] == null &&
          _trimToNull(reaction?['id']) ==
              _trimToNull(terminal['reaction_id']) &&
          reaction?['removed_at'] == null;
      return canonical
          ? BackgroundDirectNotificationPostShowDecision.keep
          : BackgroundDirectNotificationPostShowDecision.retire;
  }
}

Future<void> _stageResolvedPushEnvelopeIfNeeded(
  RemoteMessage message,
  BackgroundPushNotificationFallback fallback,
) async {
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      fallback.resolvedEventIdentity?.origin !=
          ResolvedPushEventIdentityOrigin.authenticatedInner) {
    return;
  }
  final entry = _stagedPushEnvelopeFromRemoteMessage(
    message,
    resolvedIdentity: fallback.resolvedEventIdentity,
  );
  if (entry == null || entry.identityResolutionPending) return;
  try {
    // File staging is keyed by nonce, so this atomically promotes the earlier
    // pending custody record instead of creating a second logical envelope.
    await _backgroundPushEnvelopeStager(entry);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_ENVELOPE_PROMOTION_ERROR',
      details: {'messageId': message.messageId, 'error': e.toString()},
    );
  }
}

StagedPushEnvelope? _stagedPushEnvelopeFromRemoteMessage(
  RemoteMessage message, {
  ResolvedPushEventIdentity? resolvedIdentity,
}) {
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
        _trimToNull(data['event_id']) ??
        _trimToNull(data['reaction_id']) ??
        (resolvedIdentity?.kind == ConversationNotificationContentKind.reaction
            ? resolvedIdentity?.canonicalEventId
            : null);
    final action = _trimToNull(data['action']) ?? resolvedIdentity?.action;
    final targetMessageId =
        _trimToNull(data['target_message_id']) ??
        resolvedIdentity?.targetMessageId;
    if (action != 'add' || targetMessageId == null) {
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
      identityResolutionPending: eventId == null,
      receivedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }
  return StagedPushEnvelope(
    kind: 'chat',
    kem: kem,
    ciphertext: ciphertext,
    nonce: nonce,
    senderPeerId: senderPeerId,
    messageId:
        remoteNotificationMessageIdFromData(data) ??
        (resolvedIdentity?.kind == ConversationNotificationContentKind.message
            ? resolvedIdentity?.canonicalEventId
            : null),
    identityResolutionPending:
        remoteNotificationMessageIdFromData(data) == null &&
        resolvedIdentity?.canonicalEventId == null,
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

Future<ConversationNotificationSnapshot?>
_loadBackgroundDirectConversationSnapshot(Database db, String peerId) async {
  try {
    final rows = await dbLoadMessagesForContact(db, peerId);
    return buildDirectConversationNotificationSnapshot(
      messages: rows.map(
        (row) => ConversationMessage.fromMap(Map<String, dynamic>.from(row)),
      ),
      contactPeerId: peerId,
      loadAttachments: (messageId) async =>
          (await dbLoadMediaForMessage(
                db,
                messageId,
                ownerLane: MediaOwnerLane.direct.dbValue,
              ))
              .map(
                (row) =>
                    MediaAttachment.fromMap(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false),
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_NOTIFICATION_SNAPSHOT_ERROR',
      details: {'kind': 'direct', 'errorType': error.runtimeType.toString()},
    );
    return null;
  }
}

Future<ConversationNotificationSnapshot?>
_loadBackgroundGroupConversationSnapshot(Database db, String groupId) async {
  try {
    final rows = await dbLoadAllGroupMessages(db, groupId);
    return buildGroupConversationNotificationSnapshot(
      messages: rows.map(
        (row) => GroupMessage.fromMap(Map<String, dynamic>.from(row)),
      ),
      groupId: groupId,
      loadAttachments: (messageId) async =>
          (await dbLoadMediaForMessage(
                db,
                messageId,
                ownerLane: MediaOwnerLane.group.dbValue,
              ))
              .map(
                (row) =>
                    MediaAttachment.fromMap(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false),
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_NOTIFICATION_SNAPSHOT_ERROR',
      details: {'kind': 'group', 'errorType': error.runtimeType.toString()},
    );
    return null;
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
    return (await resolveBackgroundPushNotification(
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
    )).withSnapshot(localState.snapshot);
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
    return (await resolveBackgroundPushNotification(
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
    )).withSnapshot(localState.snapshot);
  }
  if (type == 'group_reaction') {
    final localState = await _backgroundGroupReactionLocalStateResolver(
      message,
    );
    if (localState == null || !localState.nominationVerified) {
      throw StateError('group reaction local state became ineligible');
    }
    return (await resolveBackgroundPushNotification(
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
    )).withSnapshot(localState.snapshot);
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
  return (await resolveBackgroundPushNotification(
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
  )).withSnapshot(localState.snapshot);
}

@visibleForTesting
BackgroundDirectMessageLocalState? directMessageLocalStateFromRows({
  required Map<String, dynamic> data,
  required Map<String, Object?>? identityRow,
  required Map<String, Object?>? contactRow,
  required String? currentMlKemSecretKey,
  required List<String> priorMlKemSecretKeys,
  ConversationNotificationSnapshot? snapshot,
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
    snapshot: snapshot,
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
      snapshot: await _loadBackgroundDirectConversationSnapshot(
        db,
        senderPeerId,
      ),
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
  ConversationNotificationSnapshot? snapshot,
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
    snapshot: snapshot,
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
      snapshot: await _loadBackgroundGroupConversationSnapshot(db, groupId),
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
  ConversationNotificationSnapshot? snapshot,
}) {
  final action = _trimToNull(data['action']);
  final senderPeerId =
      _trimToNull(data['sender_id']) ?? _trimToNull(data['from']);
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
    snapshot: snapshot,
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
      snapshot: await _loadBackgroundDirectConversationSnapshot(
        db,
        senderPeerId,
      ),
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
  ConversationNotificationSnapshot? snapshot,
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
      expectedTransitionId: verifiedNomination.transitionId,
    ),
    groupKey: groupKey,
    keyEpoch: keyEpoch,
    nominationVerified: true,
    snapshot: snapshot,
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
      eventId == null
          ? Future<Map<String, Object?>?>.value(null)
          : dbLoadExactGroupNotificationReadAcknowledgement(
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
      snapshot: await _loadBackgroundGroupConversationSnapshot(db, groupId),
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
/// passphrase for legacy DBs. Always readOnly + singleInstance:false: the
/// FlutterFire engine can share the Android app process with the foreground or
/// recovery engine, but it never owns the canonical writable-runtime lease.
/// Extracted as a testable seam so SC-B can prove the raw-read path against a
/// manufactured raw fixture without standing up the full FCM push machinery.
@visibleForTesting
Future<Database> openBackgroundIdentityDbReadTolerant({
  required String path,
  required String key,
}) => openEncryptedDatabaseReadOnlyTolerant(path: path, storedKey: key);

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
