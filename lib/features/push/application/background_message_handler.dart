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
import 'package:flutter_app/core/database/helpers/direct_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
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
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
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
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';
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
// Plan 393 TC-393-06 measured a 175 ms profile-AOT downstream native-entry
// tail. `max(existing 2 s phase, measured tail + 500 ms)` therefore freezes at
// 2 s. The retained, APK-bound receipt lives under
// build/plan393/g21-profile-aot-measurement.
const Duration _productionBackgroundStorageDisplayEligibilityReserve = Duration(
  seconds: 2,
);
const bool _backgroundStorageG21MeasurementBuild = bool.fromEnvironment(
  'MKNOON_NOTIFICATION_G21_MEASUREMENT',
);
const bool _compiledPlan393G30Diagnostics = bool.fromEnvironment(
  'E2E_TEST_MODE',
);
bool _plan393G30DiagnosticsEnabled = _compiledPlan393G30Diagnostics;
Duration _backgroundStorageAggregateDeadline =
    _productionBackgroundStorageAggregateDeadline;
Duration _backgroundStoragePhaseDeadline =
    _productionBackgroundStoragePhaseDeadline;
Duration _backgroundStorageDisplayEligibilityReserve =
    _productionBackgroundStorageDisplayEligibilityReserve;
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
    required this.phaseElapsed,
    required this.budget,
  });

  final String phase;

  /// Time since the whole wake's deadline was constructed.
  final Duration elapsed;

  /// Time spent inside the phase that tripped, measured from that phase's own
  /// start stamp. This is what tells a comfortable phase from a near miss;
  /// [elapsed] cannot, because it also carries every earlier phase.
  final Duration phaseElapsed;

  /// The bound actually applied to the tripping phase — `min(remaining, phase)`
  /// — NOT the configured phase constant. Zero on the aggregate-exhausted
  /// branch, where no bound was ever installed.
  final Duration budget;

  @override
  String toString() =>
      'BackgroundStorageDeadlineExceeded($phase, ${elapsed.inMilliseconds}ms, '
      'phase ${phaseElapsed.inMilliseconds}ms of ${budget.inMilliseconds}ms)';
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

  /// The clock reading when the phase currently in flight began. One deadline
  /// instance serves every phase of one wake, and all of them are sequentially
  /// awaited (no `Future.wait`, `unawaited`, `.then(`, `scheduleMicrotask` or
  /// `Timer(` in the background handler), so a single mutable stamp cannot be
  /// corrupted by overlap.
  Duration? _phaseStartedAt;

  Duration get elapsed {
    final value = _elapsed() - _startedAt;
    return value.isNegative ? Duration.zero : value;
  }

  Duration get remaining {
    final value = aggregate - elapsed;
    return value.isNegative ? Duration.zero : value;
  }

  Duration get _phaseElapsed {
    final startedAt = _phaseStartedAt;
    if (startedAt == null) return Duration.zero;
    final value = _elapsed() - startedAt;
    return value.isNegative ? Duration.zero : value;
  }

  Future<T> run<T>(String phaseName, Future<T> Function() action) {
    if (!enabled) return action();
    // Stamped BEFORE the remaining check on purpose. `run` is not `async`, so
    // the aggregate-exhausted branch below throws synchronously; stamping
    // after it would make that branch report the PREVIOUS phase's offset.
    _phaseStartedAt = _elapsed();
    final remaining = aggregate - elapsed;
    if (remaining <= Duration.zero) {
      throw BackgroundStorageDeadlineExceeded(
        phase: phaseName,
        elapsed: elapsed,
        phaseElapsed: _phaseElapsed,
        // No bound was installed: the phase never started.
        budget: Duration.zero,
      );
    }
    final bound = remaining < phase ? remaining : phase;
    return action().timeout(
      bound,
      onTimeout: () => throw BackgroundStorageDeadlineExceeded(
        phase: phaseName,
        elapsed: elapsed,
        phaseElapsed: _phaseElapsed,
        budget: bound,
      ),
    );
  }

  /// Measurement-only escape hatch for G21. The aggregate remains the hard
  /// stop; only the ordinary per-phase ceiling is omitted so a successful
  /// eligibility read and its downstream native-entry tail can be observed.
  Future<T> runWithRawAggregateRemainder<T>(
    String phaseName,
    Future<T> Function() action,
  ) {
    if (!enabled) return action();
    _phaseStartedAt = _elapsed();
    final bound = remaining;
    if (bound <= Duration.zero) {
      throw BackgroundStorageDeadlineExceeded(
        phase: phaseName,
        elapsed: elapsed,
        phaseElapsed: _phaseElapsed,
        budget: Duration.zero,
      );
    }
    return action().timeout(
      bound,
      onTimeout: () => throw BackgroundStorageDeadlineExceeded(
        phase: phaseName,
        elapsed: elapsed,
        phaseElapsed: _phaseElapsed,
        budget: bound,
      ),
    );
  }

  /// Gives the policy-complete eligibility read the aggregate remainder after
  /// preserving a fixed, evidence-backed tail for native entry. No sibling
  /// phase calls this method, and [aggregate] remains the hard stop.
  Future<T> runWithAggregateReserve<T>(
    String phaseName, {
    required Duration reserve,
    required Future<T> Function() action,
  }) {
    if (!enabled) return action();
    _phaseStartedAt = _elapsed();
    final aggregateRemaining = remaining;
    final bound = aggregateRemaining - reserve;
    if (bound <= Duration.zero) {
      throw BackgroundStorageDeadlineExceeded(
        phase: phaseName,
        elapsed: elapsed,
        phaseElapsed: _phaseElapsed,
        budget: Duration.zero,
      );
    }
    return action().timeout(
      bound,
      onTimeout: () => throw BackgroundStorageDeadlineExceeded(
        phase: phaseName,
        elapsed: elapsed,
        phaseElapsed: _phaseElapsed,
        budget: bound,
      ),
    );
  }
}

@visibleForTesting
void debugSetBackgroundStorageDeadlineDurations({
  required Duration aggregate,
  required Duration phase,
  Duration? displayEligibilityReserve,
}) {
  if (aggregate <= Duration.zero ||
      phase <= Duration.zero ||
      (displayEligibilityReserve != null &&
          displayEligibilityReserve <= Duration.zero)) {
    throw ArgumentError('background storage deadlines must be positive');
  }
  _backgroundStorageAggregateDeadline = aggregate;
  _backgroundStoragePhaseDeadline = phase;
  _backgroundStorageDisplayEligibilityReserve =
      displayEligibilityReserve ?? phase;
}

@visibleForTesting
void debugResetBackgroundStorageDeadlineDurations() {
  _backgroundStorageAggregateDeadline =
      _productionBackgroundStorageAggregateDeadline;
  _backgroundStoragePhaseDeadline = _productionBackgroundStoragePhaseDeadline;
  _backgroundStorageDisplayEligibilityReserve =
      _productionBackgroundStorageDisplayEligibilityReserve;
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
void debugSetPlan393G30DiagnosticsEnabled(bool enabled) {
  _plan393G30DiagnosticsEnabled = enabled;
}

@visibleForTesting
void debugResetPlan393G30DiagnosticsEnabled() {
  _plan393G30DiagnosticsEnabled = _compiledPlan393G30Diagnostics;
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
typedef BackgroundDurableLocalNotificationEffectResolver =
    Future<DurableLocalNotificationEffectContext?> Function({
      required NotificationRouteTarget routeTarget,
      required BackgroundPushNotificationFallback fallback,
      required ConversationNotificationContentMetadata metadata,
    });
typedef BackgroundAppVisibilityResolver =
    Future<AppVisibilitySuppressionReader> Function();

enum BackgroundDirectNotificationPostShowDecision {
  keep,
  read,
  retire,
  unknown,
}

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
BackgroundDurableLocalNotificationEffectResolver
_backgroundDurableLocalNotificationEffectResolver =
    _resolveBackgroundDurableLocalNotificationEffect;
BackgroundAppVisibilityResolver _backgroundAppVisibilityResolver = () async =>
    AppVisibilityAuthority(
      platformBridge: MethodChannelAppVisibilityPlatformBridge(),
    );

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
void debugSetBackgroundDurableLocalNotificationEffectResolver(
  BackgroundDurableLocalNotificationEffectResolver resolver,
) {
  _backgroundDurableLocalNotificationEffectResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundDurableLocalNotificationEffectResolver() {
  _backgroundDurableLocalNotificationEffectResolver =
      _resolveBackgroundDurableLocalNotificationEffect;
}

@visibleForTesting
void debugSetBackgroundAppVisibilityResolver(
  BackgroundAppVisibilityResolver resolver,
) {
  _backgroundAppVisibilityResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundAppVisibilityResolver() {
  _backgroundAppVisibilityResolver = () async => AppVisibilityAuthority(
    platformBridge: MethodChannelAppVisibilityPlatformBridge(),
  );
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
  Duration? g21EligibilityStartElapsed;
  Duration? g21RemainingAtEligibilityStart;
  Duration? g21EligibilityCompletedElapsed;
  Duration? g21NativeEntryCompletedElapsed;
  final g21MeasurementApplies =
      _backgroundStorageG21MeasurementBuild &&
      _trimToNull(message.data['type']) == 'new_message';

  Future<void> recordG21Measurement(
    BackgroundStorageG21TerminalOutcome outcome,
  ) async {
    if (!g21MeasurementApplies) return;
    final start = g21EligibilityStartElapsed;
    final remaining = g21RemainingAtEligibilityStart;
    final completed = g21EligibilityCompletedElapsed;
    if (start == null || remaining == null || completed == null) return;
    final nativeCompleted = g21NativeEntryCompletedElapsed;
    if (outcome == BackgroundStorageG21TerminalOutcome.shown &&
        nativeCompleted == null) {
      return;
    }
    await _backgroundStorageLivenessJournal.recordG21Measurement(
      kind: BackgroundStorageMessageKind.directMessage,
      aggregateElapsedAtEligibilityStart: start,
      remainingAtEligibilityStart: remaining,
      eligibilityElapsed: completed - start,
      nativeEntryTail: nativeCompleted == null
          ? Duration.zero
          : nativeCompleted - completed,
      terminalOutcome: outcome,
    );
  }

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
    if (g21MeasurementApplies) {
      g21EligibilityStartElapsed = storageDeadline.elapsed;
      g21RemainingAtEligibilityStart = storageDeadline.remaining;
      displayEligibility = await storageDeadline.runWithRawAggregateRemainder(
        'display_eligibility',
        () => _backgroundPushNotificationDisplayEligibilityResolver(message),
      );
      g21EligibilityCompletedElapsed = storageDeadline.elapsed;
    } else {
      displayEligibility = await storageDeadline.runWithAggregateReserve(
        'display_eligibility',
        reserve: _backgroundStorageDisplayEligibilityReserve,
        action: () =>
            _backgroundPushNotificationDisplayEligibilityResolver(message),
      );
    }
  } on BackgroundStorageDeadlineExceeded catch (error) {
    await _recordBackgroundStorageDeferred(
      message,
      error,
      outcome: 'storage_deferred',
    );
    return;
  }
  if (!displayEligibility.shouldDisplay) {
    await recordG21Measurement(
      BackgroundStorageG21TerminalOutcome.policySuppressed,
    );
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
  Future<void> releaseProvisionalNotificationOwners({
    required String reason,
  }) async {
    final tone = notificationToneReservation;
    final claim = notificationEventClaim;
    notificationToneReservation = null;
    notificationEventClaim = null;
    if (tone != null) {
      try {
        await tone.release();
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_MESSAGE_TONE_RELEASE_FAILED',
          details: <String, Object?>{
            'kind': reason,
            'errorType': error.runtimeType.toString(),
          },
        );
      }
    }
    if (claim != null) {
      try {
        await claim.release();
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_MESSAGE_CLAIM_RELEASE_FAILED',
          details: <String, Object?>{
            'type': claim.type,
            'reason': reason,
            'errorType': error.runtimeType.toString(),
          },
        );
      }
    }
  }

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
    var contentMetadata = contentKind == null
        ? null
        : ConversationNotificationContentMetadata(
            kind: contentKind,
            eventIdentity: notificationEventIdentity,
            generation: createConversationNotificationGeneration(),
          );
    var nativePayload = contentMetadata == null
        ? fallback.payload
        : encodeConversationNotificationPayload(
            routePayload: fallback.payload ?? conversationKey,
            conversationKey: conversationKey,
            metadata: contentMetadata,
          );
    DurableLocalNotificationEffectContext? durableEffectContext;
    AppVisibilitySuppressionReader? durableFinalVisibility;
    final groupComparand = fallback.groupComparand;
    final requiresDurableEffect =
        defaultTargetPlatform == TargetPlatform.android &&
        resolvedEventIdentity != null &&
        contentMetadata != null &&
        routeTarget != null &&
        (routeTarget.kind == NotificationRouteTargetKind.conversation ||
            routeTarget.kind == NotificationRouteTargetKind.group);
    if (requiresDurableEffect) {
      // 383/G17: deferring the DURABLE effect must never defer the ALERT. A
      // killed app has no staged display-outbox row for a genuinely new event
      // (only the foreground runtime writes those), and the retry vehicle is
      // not live, so every non-deadline exit here falls through to the
      // existing non-durable typed lane with `durableEffectContext` left null
      // and the pre-durable `contentMetadata`/`nativePayload` intact. The
      // provisional owners are NOT released: the show path commits them at
      // the final barrier and the outer catch releases them on failure.
      try {
        final resolvedEffectContext = await storageDeadline.run(
          'durable_effect_authority',
          () => _backgroundDurableLocalNotificationEffectResolver(
            routeTarget: routeTarget,
            fallback: fallback,
            metadata: contentMetadata!,
          ),
        );
        if (resolvedEffectContext == null) {
          // The authenticated envelope remains staged/provider-owned. A card
          // ID, bounded reaction alias or provider message ID is not enough to
          // mint SQL_READY ledger authority.
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED',
            details: const <String, Object?>{
              'reason': 'exact_sql_authority_unavailable',
              'presentation': 'nondurable_fallback',
            },
          );
        } else {
          final generation = durableLocalNotificationContentGeneration(
            resolvedEffectContext.eventCorrelation,
          );
          if (generation == null) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED',
              details: const <String, Object?>{
                'reason': 'generation_invalid',
                'presentation': 'nondurable_fallback',
              },
            );
          } else {
            final durableMetadata = ConversationNotificationContentMetadata(
              kind: contentKind!,
              eventIdentity: resolvedEffectContext.eventCorrelation,
              generation: generation,
            );
            final finalVisibility = await _backgroundAppVisibilityResolver();
            // Commit the durable upgrade only once every authority fact is in
            // hand, so a partial failure cannot leave a half-durable card.
            durableEffectContext = resolvedEffectContext;
            contentMetadata = durableMetadata;
            nativePayload = encodeConversationNotificationPayload(
              routePayload: fallback.payload ?? conversationKey,
              conversationKey: conversationKey,
              metadata: durableMetadata,
            );
            durableFinalVisibility = finalVisibility;
          }
        }
      } on BackgroundStorageDeadlineExceeded catch (error) {
        // Storage-deadline exhaustion signals storage liveness trouble, not a
        // missing row. Presentation stays deferred to the recovery worker.
        await _recordBackgroundStorageDeferred(
          message,
          error,
          outcome: 'storage_deferred',
        );
        await releaseProvisionalNotificationOwners(
          reason: 'durable_effect_storage_deferred',
        );
        return;
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED',
          details: <String, Object?>{
            'reason': 'authority_read_failed',
            'errorType': error.runtimeType.toString(),
            'presentation': 'nondurable_fallback',
          },
        );
      }
    }
    // Mirrors the live path's `publishedSilently` capture
    // (`flutter_notification_service.dart:406-415`). Stays null when no native
    // show happened at all, so a SHOWN event that never posted cannot report
    // itself as an audible alert.
    bool? publishedSilently;
    Future<void> show({required bool publicationSilent}) async {
      final effectiveSilent = await resolveMknoonMessagePublicationSilence(
        silent: publicationSilent,
        plugin: _backgroundNotificationsPlugin,
      );
      final preservePrimaryAndroidChannel =
          await shouldPreserveMknoonPrimaryChannelForSilentUpdate(
            silent: effectiveSilent,
            notificationId: notificationId,
            plugin: _backgroundNotificationsPlugin,
          );
      publishedSilently = effectiveSilent;
      await _backgroundNotificationsPlugin.show(
        notificationId,
        fallback.title,
        fallback.body,
        mknoonConversationNotificationDetails(
          conversationKey: conversationKey,
          silent: effectiveSilent,
          preservePrimaryAndroidChannel: preservePrimaryAndroidChannel,
          autoCancel: contentMetadata == null,
          snapshot: fallback.snapshot,
        ),
        payload: nativePayload,
      );
      g21NativeEntryCompletedElapsed ??= storageDeadline.elapsed;
    }

    Future<void> publishPrepared({required bool publicationSilent}) async {
      if (contentMetadata == null) {
        await show(publicationSilent: publicationSilent);
        return;
      }
      await notificationIdRegistry.replaceContent(
        conversationKey: conversationKey,
        notificationId: notificationId,
        metadata: contentMetadata,
        replace: () => show(publicationSilent: publicationSilent),
      );
    }

    DurableNotificationClaimedPublicationResult? claimedPublication;
    Future<bool> authorizeNondurableNativeEntry() async {
      final metadata = contentMetadata;
      final target = routeTarget;
      if (metadata == null || target == null) return true;

      if (target.kind == NotificationRouteTargetKind.group) {
        final comparand = groupComparand;
        if (comparand != null) {
          final metadataMatches = switch (comparand) {
            BackgroundGroupMessageNotificationComparand messageComparand =>
              metadata.kind == ConversationNotificationContentKind.message &&
                  metadata.eventIdentity == messageComparand.messageId,
            BackgroundGroupReactionNotificationComparand reactionComparand =>
              metadata.kind == ConversationNotificationContentKind.reaction &&
                  metadata.eventIdentity ==
                      reactionComparand.notificationEventIdentity,
            BackgroundProvisionalGroupReactionNotificationComparand
            reactionComparand =>
              metadata.kind == ConversationNotificationContentKind.reaction &&
                  metadata.eventIdentity ==
                      reactionComparand.notificationEventIdentity,
          };
          if (!metadataMatches) return false;
          final remainingBeforeValidation = storageDeadline.remaining;
          try {
            final decision = await storageDeadline.run(
              'group_post_show_validation',
              () => _backgroundGroupNotificationPostShowValidator(comparand),
            );
            if (decision == BackgroundGroupNotificationPostShowDecision.read ||
                decision ==
                    BackgroundGroupNotificationPostShowDecision.retire) {
              return false;
            }
          } on BackgroundStorageDeadlineExceeded catch (error) {
            await _recordBackgroundStorageDeferred(
              message,
              error,
              outcome: 'storage_deferred',
            );
            // An ordinary sibling-phase timeout leaves canonical state
            // unknown, which must fail toward notification. Only a phase
            // bounded by the aggregate remainder may enforce the hard stop.
            if (remainingBeforeValidation <= storageDeadline.phase) rethrow;
          } catch (_) {
            // Unknown canonical facts fail toward notification.
          }
        }
      } else if (target.kind == NotificationRouteTargetKind.conversation) {
        final peerId = _trimToNull(target.peerId);
        if (peerId != null) {
          final remainingBeforeValidation = storageDeadline.remaining;
          try {
            final decision = await storageDeadline.run(
              'direct_post_show_validation',
              () => _validateBackgroundDirectNotificationAfterShow(
                peerId: peerId,
                metadata: metadata,
              ),
            );
            if (decision == BackgroundDirectNotificationPostShowDecision.read ||
                decision ==
                    BackgroundDirectNotificationPostShowDecision.retire) {
              return false;
            }
          } on BackgroundStorageDeadlineExceeded catch (error) {
            await _recordBackgroundStorageDeferred(
              message,
              error,
              outcome: 'storage_deferred',
            );
            // Preserve the aggregate hard stop without converting an
            // ordinary canonical-read timeout into false suppression.
            if (remainingBeforeValidation <= storageDeadline.phase) rethrow;
          } catch (_) {
            // Unknown canonical facts fail toward notification.
          }
        }
      }

      try {
        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: target.kind == NotificationRouteTargetKind.group
              ? AppVisibilityConversationLane.group
              : AppVisibilityConversationLane.direct,
          value: conversationKey,
        );
        final visibility = await _backgroundAppVisibilityResolver();
        return !(await visibility.evaluate(identity)).maySuppress;
      } catch (_) {
        // A stale/missing native visibility snapshot cannot erase an alert.
        return true;
      }
    }

    Future<bool> publishAtDurableFinalBarrier(
      AuthorizeDurableLocalNotificationNativeEntry authorize,
    ) async {
      Future<void> publishWithExactToneOwner() async {
        final reservation = notificationToneReservation;
        if (reservation == null) {
          if (!await authorize()) {
            throw const DurableNotificationPublicationNotAuthorizedException();
          }
          await show(publicationSilent: silent);
          return;
        }
        tonePublication = await reservation.publishAndCommit(() async {
          if (!await authorize()) {
            throw const DurableNotificationPublicationNotAuthorizedException();
          }
          await show(publicationSilent: false);
        });
        if (!tonePublication!.publishedAudibly) {
          if (!await authorize()) {
            throw const DurableNotificationPublicationNotAuthorizedException();
          }
          await show(publicationSilent: true);
        }
      }

      try {
        final currentEventClaim = notificationEventClaim;
        claimedPublication = currentEventClaim == null
            ? null
            : await currentEventClaim.publishAndCommit(
                publishWithExactToneOwner,
              );
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

    Future<void> publishAtNativeBoundary() async {
      final entered = await publishAtDurableFinalBarrier(
        durableEffectContext == null
            ? authorizeNondurableNativeEntry
            : () async => true,
      );
      if (!entered) throw const _BackgroundNotificationClaimOwnershipLost();
    }

    DurableLocalNotificationEffectResult? durableEffectResult;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Registry allocation, retirement, and metadata preparation happen
      // before Android durable owners enter `publishing`. Only the actual
      // platform show call is ambiguous if its method-channel result fails.
      final effectContext = durableEffectContext;
      if (effectContext != null) {
        final conversationIdentity = AppVisibilityConversationIdentity.tryParse(
          lane: routeTarget!.kind == NotificationRouteTargetKind.group
              ? AppVisibilityConversationLane.group
              : AppVisibilityConversationLane.direct,
          value: conversationKey,
        );
        final visibility = durableFinalVisibility;
        if (conversationIdentity == null ||
            visibility == null ||
            contentMetadata == null) {
          await releaseProvisionalNotificationOwners(
            reason: 'durable_effect_final_authority_invalid',
          );
          return;
        }
        durableEffectResult = await notificationIdRegistry.runFinalEffect(
          context: effectContext,
          appVisibility: visibility,
          conversationIdentity: conversationIdentity,
          conversationKey: conversationKey,
          notificationId: notificationId,
          metadata: contentMetadata,
          retireCurrent: () =>
              _backgroundNotificationsPlugin.cancel(notificationId),
          publishNative: publishAtNativeBoundary,
          publishNativeAtFinalBarrier: publishAtDurableFinalBarrier,
          // A recovered PUBLISHING attempt may outlive the provisional tone
          // and event leases. Never route repair through their audible path.
          publishNativeSilently: () => show(publicationSilent: true),
          activeNotificationIds: () async =>
              (await _backgroundNotificationsPlugin.getActiveNotifications())
                  .map((notification) => notification.id),
        );
      } else if (contentMetadata == null) {
        await publishAtNativeBoundary();
      } else {
        final replacement = await notificationIdRegistry.replaceContent(
          conversationKey: conversationKey,
          notificationId: notificationId,
          metadata: contentMetadata,
          replace: publishAtNativeBoundary,
        );
        if (replacement ==
            ConversationNotificationContentReplacementResult.alreadyCurrent) {
          await releaseProvisionalNotificationOwners(
            reason: 'content_event_already_current',
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'NOTIFICATION_DUPLICATE_CARD_PRESERVED',
            details: const {'reason': 'same_content_event'},
          );
          return;
        }
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

      final currentEventClaim = notificationEventClaim;
      claimedPublication = currentEventClaim == null
          ? null
          : await currentEventClaim.publishAndCommit(
              publishWithLegacyToneOwner,
            );
      if (claimedPublication == null) {
        await publishWithLegacyToneOwner();
      } else if (!claimedPublication!.published) {
        throw const _BackgroundNotificationClaimOwnershipLost();
      }
    }

    final durableReceipt = durableEffectResult?.receipt;
    if (durableReceipt != null) {
      try {
        await durableEffectContext?.onEffectTerminal?.call(durableReceipt);
      } catch (error) {
        // The registry lock is already released and EFFECT_TERMINAL is the
        // truthful authority. Main-runtime reconciliation owns SQL replay;
        // never release the audible/event owners because its callback failed.
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_BACKGROUND_EFFECT_HANDOFF_DEFERRED',
          details: <String, Object?>{'errorType': error.runtimeType.toString()},
        );
      }
    }
    if (durableEffectResult != null &&
        durableEffectResult.disposition !=
            DurableLocalNotificationEffectDisposition.osPosted) {
      if (durableEffectResult.currentNativeEntryAttempted &&
          !durableEffectResult.currentNativeEntryWasSilentRepair) {
        // The platform callback may have been accepted. The ledger retains
        // PUBLISHING and both legacy owners stay fail-closed for recovery.
        notificationToneReservation = null;
        notificationEventClaim = null;
      } else {
        await notificationToneReservation?.release();
        await notificationEventClaim?.release();
        notificationToneReservation = null;
        notificationEventClaim = null;
      }
      return;
    }
    if (durableEffectResult != null &&
        durableEffectResult.disposition ==
            DurableLocalNotificationEffectDisposition.osPosted &&
        (!durableEffectResult.currentNativeEntryAttempted ||
            durableEffectResult.currentNativeEntryWasSilentRepair)) {
      // A terminal/active-inventory replay or force-silent repair owns no
      // fresh audible/event publication. Release provisional legacy owners;
      // their publication results are intentionally absent.
      await notificationToneReservation?.release();
      await notificationEventClaim?.release();
      notificationToneReservation = null;
      notificationEventClaim = null;
      return;
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
    if (durableEffectContext == null &&
        contentMetadata != null &&
        groupComparand != null) {
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
        if (decision == BackgroundGroupNotificationPostShowDecision.retire ||
            decision == BackgroundGroupNotificationPostShowDecision.read) {
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
    if (durableEffectContext == null &&
        !postShowStorageExpired &&
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
              metadata: contentMetadata!,
            ),
          );
          if (decision == BackgroundDirectNotificationPostShowDecision.retire ||
              decision == BackgroundDirectNotificationPostShowDecision.read) {
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

    await recordG21Measurement(BackgroundStorageG21TerminalOutcome.shown);

    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
      details: durableEffectContext == null
          ? <String, Object?>{
              'messageId': message.messageId,
              'payload': fallback.payload ?? '',
              // Whether the background isolate's own post ALERTED. The live
              // path has always reported this; without it the background path
              // — which wins the dual-path race whenever the app is merely
              // backgrounded — is unprovable, and a dumpsys read cannot stand
              // in for it (the losing path's silent same-ID reconcile lands
              // ~2.6 s later, device-measured 2026-08-19).
              'silent': ?publishedSilently,
            }
          : <String, Object?>{
              'durable': true,
              'producer': durableEffectContext.producerKind.wireName,
              'disposition':
                  durableEffectResult?.disposition.name ?? 'legacy_fallback',
              'silent': ?publishedSilently,
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
  // The mapping above collapses several phases onto `local_state`. Carry the
  // raw identifier as well, validated against a closed domain so the journal's
  // no-caller-strings rule survives the widening.
  final phaseName = BackgroundStorageDeadlinePhaseName.fromWireName(
    error.phase,
  );
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
      'phaseName': phaseName.wireName,
      'outcome': terminalOutcome.wireName,
      'elapsedBucket': bucketBackgroundStorageElapsed(error.elapsed).wireName,
      'elapsedMs': error.elapsed.inMilliseconds.toString(),
      'phaseElapsedMs': error.phaseElapsed.inMilliseconds.toString(),
      'budgetMs': error.budget.inMilliseconds.toString(),
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
    phaseName: phaseName,
    outcome: terminalOutcome,
    elapsed: error.elapsed,
    phaseElapsed: error.phaseElapsed,
    budget: error.budget,
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
  var phase = 'secure_key';
  var handleState = 'not_requested';
  BackgroundDirectNotificationPostShowDecision? decision;
  Object? failure;
  StackTrace? failureStack;
  String? failurePhase;
  String? failureHandleState;
  try {
    final key = await FlutterSecureKeyStore().read(_backgroundDbEncryptionKey);
    if (_trimToNull(key) == null) {
      decision = BackgroundDirectNotificationPostShowDecision.unknown;
    } else {
      phase = 'open';
      handleState = 'requested_read_only_non_singleton';
      final dbPath = await getDatabasesPath();
      db = await openBackgroundIdentityDbReadTolerant(
        path: '$dbPath/identity.db',
        key: key!,
      );
      handleState = 'acquired_read_only_non_singleton';
      phase = 'query';
      // TC-393-14 / G30: this await is the ownership boundary. Returning the
      // Future from inside a try/finally runs the close before the validator's
      // later SQL reads complete, which produced the observed database_closed
      // between contact lookup and read-ack lookup on Android.
      decision = await validateBackgroundDirectNotificationAfterShowInDatabase(
        db,
        peerId: peerId,
        metadata: metadata,
      );
    }
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
    failurePhase = phase;
    failureHandleState = handleState;
  } finally {
    if (db != null) {
      phase = 'close';
      handleState = 'close_attempted';
      try {
        await db.close();
        handleState = 'close_completed';
      } catch (error, stackTrace) {
        if (failure == null) {
          failure = error;
          failureStack = stackTrace;
          failurePhase = phase;
          failureHandleState = handleState;
        }
      }
    }
  }
  final capturedFailure = failure;
  if (capturedFailure != null) {
    _emitPlan393G30Diagnostic(
      phase: failurePhase ?? phase,
      sqfliteCode: _sanitizedPlan393SqfliteCode(capturedFailure),
      independentHandleState: failureHandleState ?? handleState,
      validatorDisposition: 'not_completed',
      outcome: 'failure',
    );
    Error.throwWithStackTrace(
      capturedFailure,
      failureStack ?? StackTrace.current,
    );
  }
  final capturedDecision =
      decision ?? BackgroundDirectNotificationPostShowDecision.unknown;
  final effectiveDisposition =
      capturedDecision == BackgroundDirectNotificationPostShowDecision.unknown
      ? BackgroundDirectNotificationPostShowDecision.keep
      : capturedDecision;
  _emitPlan393G30Diagnostic(
    phase: 'complete',
    sqfliteCode: 'none',
    independentHandleState: handleState,
    validatorDisposition: effectiveDisposition.name,
    outcome: 'completed',
  );
  return effectiveDisposition;
}

void _emitPlan393G30Diagnostic({
  required String phase,
  required String sqfliteCode,
  required String independentHandleState,
  required String validatorDisposition,
  required String outcome,
}) {
  if (!_plan393G30DiagnosticsEnabled) return;
  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_BACKGROUND_DIRECT_VALIDATOR_DIAGNOSTIC',
    details: <String, Object?>{
      'phase': phase,
      'sqfliteCode': sqfliteCode,
      'independentHandleState': independentHandleState,
      'validatorDisposition': validatorDisposition,
      'outcome': outcome,
    },
  );
}

String _sanitizedPlan393SqfliteCode(Object error) {
  final normalized = error.toString().toLowerCase();
  if (normalized.contains('database_closed') ||
      normalized.contains('database closed')) {
    return 'database_closed';
  }
  if (normalized.contains('database_locked') ||
      normalized.contains('database locked')) {
    return 'database_locked';
  }
  if (normalized.contains('timeout')) return 'timeout';
  if (error is DatabaseException) return 'sqflite_other';
  return 'non_sqflite';
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
  String? canonicalEventIdentity,
  String? acknowledgementEventIdentity,
  String? acknowledgementGeneration,
  DirectNotificationDisplayOutboxEntry? expectedEntry,
}) async {
  final eventIdentity = _trimToNull(
    canonicalEventIdentity ?? metadata.eventIdentity,
  );
  final acknowledgementIdentity = _trimToNull(
    acknowledgementEventIdentity ?? metadata.eventIdentity,
  );
  final acknowledgementContentGeneration = _trimToNull(
    acknowledgementGeneration ?? metadata.generation,
  );
  if (eventIdentity == null) {
    return BackgroundDirectNotificationPostShowDecision.unknown;
  }
  final contact = await dbLoadContact(db, peerId);
  if (contact == null || _trimToNull(contact['peer_id']) != peerId) {
    return BackgroundDirectNotificationPostShowDecision.unknown;
  }
  if ((contact['is_blocked'] as num?)?.toInt() == 1 ||
      (contact['is_archived'] as num?)?.toInt() == 1) {
    return BackgroundDirectNotificationPostShowDecision.retire;
  }

  final acknowledgement =
      acknowledgementIdentity == null ||
          acknowledgementContentGeneration == null
      ? null
      : await dbLoadExactDirectNotificationReadAcknowledgement(
          db,
          peerId: peerId,
          contentKind: metadata.kind.name,
          eventIdentity: acknowledgementIdentity,
          generation: acknowledgementContentGeneration,
        );
  if (acknowledgement != null && expectedEntry == null) {
    return BackgroundDirectNotificationPostShowDecision.read;
  }

  switch (metadata.kind) {
    case ConversationNotificationContentKind.message:
      final message = await dbLoadMessage(db, eventIdentity);
      if (message == null) {
        return BackgroundDirectNotificationPostShowDecision.unknown;
      }
      if (expectedEntry != null &&
          (expectedEntry.eventKind !=
                  DirectNotificationDisplayOutboxKind.message ||
              expectedEntry.eventId != eventIdentity ||
              expectedEntry.peerId != peerId ||
              expectedEntry.messageId != eventIdentity ||
              _trimToNull(message['contact_peer_id']) != expectedEntry.peerId ||
              _trimToNull(message['sender_peer_id']) !=
                  expectedEntry.actorPeerId ||
              _trimToNull(message['timestamp']) !=
                  expectedEntry.eventTimestamp ||
              (message['is_incoming'] as num?)?.toInt() != 1)) {
        return BackgroundDirectNotificationPostShowDecision.unknown;
      }
      final canonicalIdentity =
          _trimToNull(message['contact_peer_id']) == peerId &&
          (message['is_incoming'] as num?)?.toInt() == 1;
      if (!canonicalIdentity ||
          message['deleted_at'] != null ||
          message['hidden_at'] != null ||
          _isBackgroundDirectPrivateMediaTerminal(
            message['private_media_state'],
          )) {
        return BackgroundDirectNotificationPostShowDecision.retire;
      }
      if (acknowledgement != null || message['read_at'] != null) {
        return BackgroundDirectNotificationPostShowDecision.read;
      }
      return BackgroundDirectNotificationPostShowDecision.keep;
    case ConversationNotificationContentKind.reaction:
      if (expectedEntry != null &&
          (expectedEntry.eventKind !=
                  DirectNotificationDisplayOutboxKind.reaction ||
              expectedEntry.eventId != eventIdentity ||
              expectedEntry.peerId != peerId)) {
        return BackgroundDirectNotificationPostShowDecision.unknown;
      }
      final terminal =
          await dbLoadDirectNotificationReactionTerminalEventByIdentity(
            db,
            peerId: peerId,
            terminalEventId: eventIdentity,
          );
      if (terminal == null) {
        return BackgroundDirectNotificationPostShowDecision.unknown;
      }
      if (expectedEntry != null &&
          (_trimToNull(terminal['peer_id']) != expectedEntry.peerId ||
              _trimToNull(terminal['message_id']) != expectedEntry.messageId ||
              _trimToNull(terminal['actor_peer_id']) !=
                  expectedEntry.actorPeerId ||
              _trimToNull(terminal['reaction_id']) !=
                  expectedEntry.reactionId ||
              _trimToNull(terminal['terminal_event_id']) !=
                  expectedEntry.eventId)) {
        return BackgroundDirectNotificationPostShowDecision.unknown;
      }
      if (terminal['notification_acknowledged_at'] != null &&
          expectedEntry == null) {
        return BackgroundDirectNotificationPostShowDecision.read;
      }
      final messageId = terminal['message_id'] as String;
      final actorPeerId = terminal['actor_peer_id'] as String;
      final target = await dbLoadMessage(db, messageId);
      final reaction = await dbLoadActiveOrTombstonedReactionForSender(
        db,
        messageId,
        actorPeerId,
      );
      if (expectedEntry != null && (target == null || reaction == null)) {
        return BackgroundDirectNotificationPostShowDecision.unknown;
      }
      final canonicalIdentity =
          _trimToNull(target?['contact_peer_id']) == peerId &&
          (target?['is_incoming'] as num?)?.toInt() == 0;
      if (expectedEntry != null && !canonicalIdentity) {
        return BackgroundDirectNotificationPostShowDecision.unknown;
      }
      final cancelled =
          !canonicalIdentity ||
          target?['deleted_at'] != null ||
          target?['hidden_at'] != null ||
          _isBackgroundDirectPrivateMediaTerminal(
            target?['private_media_state'],
          ) ||
          _trimToNull(reaction?['id']) !=
              _trimToNull(terminal['reaction_id']) ||
          reaction?['removed_at'] != null ||
          (expectedEntry != null &&
              _trimToNull(reaction?['timestamp']) !=
                  expectedEntry.eventTimestamp);
      if (cancelled) {
        return BackgroundDirectNotificationPostShowDecision.retire;
      }
      if (acknowledgement != null ||
          terminal['notification_acknowledged_at'] != null) {
        return BackgroundDirectNotificationPostShowDecision.read;
      }
      return BackgroundDirectNotificationPostShowDecision.keep;
  }
}

bool _isBackgroundDirectPrivateMediaTerminal(Object? value) {
  final state = _trimToNull(value);
  return state == 'consumed' || state == 'expired' || state == 'unsupported';
}

/// Resolves an authenticated Android background effect only when the exact
/// v106/v107 READY row already owns the same raw producer event. This is a
/// read-only qualification seam: SQL custody stays in place until the main
/// runtime replays the EFFECT_TERMINAL handoff.
@visibleForTesting
Future<DurableLocalNotificationEffectContext?>
resolveBackgroundDurableLocalNotificationEffectInDatabase(
  DatabaseExecutor db, {
  required NotificationRouteTarget routeTarget,
  required BackgroundPushNotificationFallback fallback,
  required ConversationNotificationContentMetadata metadata,
  required String currentOpaqueBinding,
  required String physicalPeerId,
  required ReadDurableLocalNotificationCanonicalDisposition
  readFinalCanonicalDisposition,
}) async {
  final authority = await _resolveBackgroundSqlEffectAuthority(
    db,
    routeTarget: routeTarget,
    fallback: fallback,
    metadata: metadata,
    currentOpaqueBinding: currentOpaqueBinding,
    physicalPeerId: physicalPeerId,
  );
  return authority?.context(readFinalCanonicalDisposition);
}

Future<DurableLocalNotificationEffectContext?>
_resolveBackgroundDurableLocalNotificationEffect({
  required NotificationRouteTarget routeTarget,
  required BackgroundPushNotificationFallback fallback,
  required ConversationNotificationContentMetadata metadata,
}) async {
  final secureStore = FlutterSecureKeyStore();
  final values = await Future.wait<String?>([
    secureStore.read(canonicalRuntimeAccountBindingStorageKey),
    secureStore.read(_backgroundPushTransportPeerId),
    secureStore.read(_backgroundDbEncryptionKey),
  ]);
  final binding = _trimToNull(values[0]);
  final physicalPeerId = _trimToNull(values[1]);
  final dbKey = _trimToNull(values[2]);
  if (!isCanonicalRuntimeOpaqueBinding(binding) ||
      physicalPeerId == null ||
      dbKey == null) {
    return null;
  }

  Database? db;
  try {
    final dbPath = await getDatabasesPath();
    db = await openBackgroundIdentityDbReadTolerant(
      path: '$dbPath/identity.db',
      key: dbKey,
    );
    final authority = await _resolveBackgroundSqlEffectAuthority(
      db,
      routeTarget: routeTarget,
      fallback: fallback,
      metadata: metadata,
      currentOpaqueBinding: binding!,
      physicalPeerId: physicalPeerId,
    );
    if (authority == null) return null;
    return authority.context(
      () => _readFinalBackgroundCanonicalDisposition(authority),
    );
  } finally {
    await db?.close();
  }
}

final class _BackgroundSqlEffectAuthority {
  const _BackgroundSqlEffectAuthority({
    required this.currentOpaqueBinding,
    required this.eventCorrelation,
    required this.conversationDigest,
    required this.producerKind,
    required this.routeTarget,
    required this.fallback,
    required this.metadata,
    this.directEntry,
    this.groupEntry,
  });

  final String currentOpaqueBinding;
  final String eventCorrelation;
  final String conversationDigest;
  final LocalNotificationProducerKind producerKind;
  final NotificationRouteTarget routeTarget;
  final BackgroundPushNotificationFallback fallback;
  final ConversationNotificationContentMetadata metadata;
  final DirectNotificationDisplayOutboxEntry? directEntry;
  final GroupNotificationDisplayOutboxEntry? groupEntry;

  DurableLocalNotificationEffectContext context(
    ReadDurableLocalNotificationCanonicalDisposition readFinal,
  ) => DurableLocalNotificationEffectContext(
    currentOpaqueBinding: currentOpaqueBinding,
    eventCorrelation: eventCorrelation,
    conversationDigest: conversationDigest,
    producerKind: producerKind,
    sourceCustody: LocalNotificationSourceCustody.sqlReady,
    presentationOwner: LocalNotificationPresentationOwner.androidPushService,
    readFinalCanonicalDisposition: readFinal,
  );
}

Future<_BackgroundSqlEffectAuthority?> _resolveBackgroundSqlEffectAuthority(
  DatabaseExecutor db, {
  required NotificationRouteTarget routeTarget,
  required BackgroundPushNotificationFallback fallback,
  required ConversationNotificationContentMetadata metadata,
  required String currentOpaqueBinding,
  required String physicalPeerId,
}) async {
  final resolved = fallback.resolvedEventIdentity;
  final rawEventIdentity = _trimToNull(resolved?.canonicalEventId);
  if (resolved == null ||
      rawEventIdentity == null ||
      resolved.kind != metadata.kind ||
      !isCanonicalRuntimeOpaqueBinding(currentOpaqueBinding)) {
    return null;
  }

  late final NotificationCompletedOutcomeProducerKind outcomeProducer;
  late final LocalNotificationProducerKind ledgerProducer;
  late final String conversationValue;
  late final String eventKey;
  DirectNotificationDisplayOutboxEntry? directEntry;
  GroupNotificationDisplayOutboxEntry? groupEntry;

  switch (routeTarget.kind) {
    case NotificationRouteTargetKind.conversation:
      final peerId = _trimToNull(routeTarget.peerId);
      if (peerId == null) return null;
      final eventKind = metadata.kind.name;
      final custodyEventId =
          metadata.kind == ConversationNotificationContentKind.reaction
          ? boundedReactionEventIdentity(rawEventIdentity)
          : rawEventIdentity;
      final row = await dbLoadDirectNotificationDisplayOutboxEntry(
        db,
        peerId: peerId,
        eventKind: eventKind,
        eventId: custodyEventId,
      );
      if (row == null) return null;
      directEntry = DirectNotificationDisplayOutboxEntry.fromMap(row);
      if (!directEntry.isReady ||
          directEntry.peerId != peerId ||
          directEntry.eventKind != eventKind ||
          directEntry.eventId != custodyEventId ||
          (metadata.kind == ConversationNotificationContentKind.message &&
              directEntry.messageId != rawEventIdentity) ||
          (metadata.kind == ConversationNotificationContentKind.reaction &&
              directEntry.reactionId != rawEventIdentity)) {
        return null;
      }
      outcomeProducer =
          metadata.kind == ConversationNotificationContentKind.message
          ? NotificationCompletedOutcomeProducerKind.directMessage
          : NotificationCompletedOutcomeProducerKind.directReaction;
      ledgerProducer =
          metadata.kind == ConversationNotificationContentKind.message
          ? LocalNotificationProducerKind.directMessage
          : LocalNotificationProducerKind.directReaction;
      eventKey =
          trySelectNotificationCompletedOutcomeEventKey(
            producerKind: outcomeProducer,
            authenticatedEnvelope: <String, Object?>{
              if (metadata.kind == ConversationNotificationContentKind.message)
                'messageId': directEntry.messageId,
              if (metadata.kind == ConversationNotificationContentKind.reaction)
                'reactionId': directEntry.reactionId,
            },
          ) ??
          '';
      conversationValue = peerId;
    case NotificationRouteTargetKind.group:
      final groupId = _trimToNull(routeTarget.groupId);
      if (groupId == null) return null;
      final row = await dbLoadGroupNotificationDisplayOutboxEntry(
        db,
        rawEventIdentity,
      );
      if (row == null) return null;
      groupEntry = GroupNotificationDisplayOutboxEntry.fromMap(row);
      if (!groupEntry.isReady ||
          groupEntry.groupId != groupId ||
          groupEntry.eventKind != metadata.kind.name ||
          groupEntry.eventId != rawEventIdentity ||
          (metadata.kind == ConversationNotificationContentKind.message &&
              groupEntry.messageId != rawEventIdentity)) {
        return null;
      }
      outcomeProducer =
          metadata.kind == ConversationNotificationContentKind.message
          ? NotificationCompletedOutcomeProducerKind.groupMessage
          : NotificationCompletedOutcomeProducerKind.groupReaction;
      ledgerProducer =
          metadata.kind == ConversationNotificationContentKind.message
          ? LocalNotificationProducerKind.groupMessage
          : LocalNotificationProducerKind.groupReaction;
      String? logicalDeliveryId;
      if (metadata.kind == ConversationNotificationContentKind.message) {
        final message = await dbLoadGroupMessage(db, groupEntry.messageId);
        logicalDeliveryId = _trimToNull(message?['logical_delivery_id']);
      }
      eventKey =
          trySelectNotificationCompletedOutcomeEventKey(
            producerKind: outcomeProducer,
            authenticatedEnvelope: <String, Object?>{
              if (metadata.kind == ConversationNotificationContentKind.message)
                'messageId': groupEntry.messageId,
              if (metadata.kind ==
                      ConversationNotificationContentKind.message &&
                  logicalDeliveryId != null)
                'logicalDeliveryId': logicalDeliveryId,
              if (metadata.kind == ConversationNotificationContentKind.reaction)
                'notificationTransitionId': groupEntry.eventId,
            },
          ) ??
          '';
      conversationValue = 'group:$groupId';
    case NotificationRouteTargetKind.contactRequest ||
        NotificationRouteTargetKind.intros ||
        NotificationRouteTargetKind.post ||
        NotificationRouteTargetKind.postComment:
      return null;
  }

  final identity = AppVisibilityConversationIdentity.tryParse(
    lane: routeTarget.kind == NotificationRouteTargetKind.group
        ? AppVisibilityConversationLane.group
        : AppVisibilityConversationLane.direct,
    value: conversationValue,
  );
  final correlation = eventKey.isEmpty
      ? null
      : tryComputeNotificationCompletedOutcomeCorrelation(
          physicalPeerId: physicalPeerId,
          producerKind: outcomeProducer,
          eventKey: eventKey,
        );
  if (identity == null || correlation == null) return null;
  return _BackgroundSqlEffectAuthority(
    currentOpaqueBinding: currentOpaqueBinding,
    eventCorrelation: correlation,
    conversationDigest: identity.digest,
    producerKind: ledgerProducer,
    routeTarget: routeTarget,
    fallback: fallback,
    metadata: metadata,
    directEntry: directEntry,
    groupEntry: groupEntry,
  );
}

Future<DurableLocalNotificationCanonicalDisposition>
_readFinalBackgroundCanonicalDisposition(
  _BackgroundSqlEffectAuthority authority,
) async {
  Database? db;
  try {
    final group = authority.groupEntry;
    final groupComparand = authority.fallback.groupComparand;
    final groupDecision = group == null || groupComparand == null
        ? null
        : await _backgroundGroupNotificationPostShowValidator(groupComparand);
    final key = await FlutterSecureKeyStore().read(_backgroundDbEncryptionKey);
    if (_trimToNull(key) == null) {
      return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
    }
    final dbPath = await getDatabasesPath();
    db = await openBackgroundIdentityDbReadTolerant(
      path: '$dbPath/identity.db',
      key: key!,
    );
    final direct = authority.directEntry;
    if (direct != null) {
      final decision =
          await validateBackgroundDirectNotificationAfterShowInDatabase(
            db,
            peerId: direct.peerId,
            metadata: authority.metadata,
            canonicalEventIdentity:
                direct.eventKind == DirectNotificationDisplayOutboxKind.message
                ? direct.messageId
                : direct.eventId,
            acknowledgementEventIdentity: authority.eventCorrelation,
            acknowledgementGeneration:
                durableLocalNotificationContentGeneration(
                  authority.eventCorrelation,
                ),
            expectedEntry: direct,
          );
      // The exact READY custody reload is deliberately last. It is the SQL
      // linearization point for the canonical facts above; a concurrent
      // delete/read/retry revision cannot be hidden by an earlier read.
      final row = await dbLoadDirectNotificationDisplayOutboxEntry(
        db,
        peerId: direct.peerId,
        eventKind: direct.eventKind,
        eventId: direct.eventId,
      );
      if (row == null) {
        return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
      }
      final current = DirectNotificationDisplayOutboxEntry.fromMap(row);
      final sameIdentity = _sameDirectDisplayAuthorityIdentity(direct, current);
      if (sameIdentity && current.hasCanonicalRetirementProof) {
        return DurableLocalNotificationCanonicalDisposition.cancelled;
      }
      if (!sameIdentity ||
          !backgroundDirectDisplayAuthorityRemainsCurrentForFinalRead(
            expected: direct,
            current: current,
          )) {
        return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
      }
      return switch (decision) {
        BackgroundDirectNotificationPostShowDecision.keep =>
          DurableLocalNotificationCanonicalDisposition.eligible,
        BackgroundDirectNotificationPostShowDecision.read =>
          DurableLocalNotificationCanonicalDisposition.read,
        BackgroundDirectNotificationPostShowDecision.retire =>
          DurableLocalNotificationCanonicalDisposition.cancelled,
        BackgroundDirectNotificationPostShowDecision.unknown =>
          DurableLocalNotificationCanonicalDisposition.retryableUnknown,
      };
    }

    if (group == null || groupDecision == null) {
      return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
    }
    final row = await dbLoadGroupNotificationDisplayOutboxEntry(
      db,
      group.eventId,
    );
    if (row == null) {
      return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
    }
    final current = GroupNotificationDisplayOutboxEntry.fromMap(row);
    final sameIdentity = _sameGroupDisplayAuthorityIdentity(group, current);
    final retirementCorrelation =
        groupNotificationDisplayDurableCorrelationFromMarker(
          current.lastAttemptAt,
        );
    if (sameIdentity &&
        current.isReady &&
        isGroupNotificationDisplayCanonicalRetiredMarker(
          current.lastAttemptAt,
        ) &&
        retirementCorrelation == authority.eventCorrelation) {
      return DurableLocalNotificationCanonicalDisposition.cancelled;
    }
    if (!sameIdentity ||
        !backgroundGroupDisplayAuthorityRemainsCurrentForFinalRead(
          expected: group,
          current: current,
        )) {
      return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
    }
    return switch (groupDecision) {
      BackgroundGroupNotificationPostShowDecision.keep =>
        DurableLocalNotificationCanonicalDisposition.eligible,
      BackgroundGroupNotificationPostShowDecision.read =>
        DurableLocalNotificationCanonicalDisposition.read,
      BackgroundGroupNotificationPostShowDecision.retire =>
        DurableLocalNotificationCanonicalDisposition.cancelled,
      BackgroundGroupNotificationPostShowDecision.unknown =>
        DurableLocalNotificationCanonicalDisposition.retryableUnknown,
    };
  } catch (_) {
    return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
  } finally {
    await db?.close();
  }
}

/// The final SQL authority remains exact when the only concurrent writer was
/// the losing live projection recording a retry. Revision and retry-count
/// deltas must match, so canonical retirement or identity mutation cannot be
/// mistaken for harmless retry bookkeeping.
@visibleForTesting
bool backgroundDirectDisplayAuthorityRemainsCurrentForFinalRead({
  required DirectNotificationDisplayOutboxEntry expected,
  required DirectNotificationDisplayOutboxEntry current,
}) =>
    _sameDirectDisplayAuthorityIdentity(expected, current) &&
    (expected.revision == current.revision ||
        _isNotificationDisplayRetryOnlyRevisionAdvance(
          expectedRevision: expected.revision,
          currentRevision: current.revision,
          expectedRetryCount: expected.retryCount,
          currentRetryCount: current.retryCount,
          currentLastErrorCode: current.lastErrorCode,
          currentNextAttemptAt: current.nextAttemptAt,
        ));

bool _sameDirectDisplayAuthorityIdentity(
  DirectNotificationDisplayOutboxEntry expected,
  DirectNotificationDisplayOutboxEntry current,
) =>
    expected.eventId == current.eventId &&
    expected.eventKind == current.eventKind &&
    expected.peerId == current.peerId &&
    expected.messageId == current.messageId &&
    expected.actorPeerId == current.actorPeerId &&
    expected.eventTimestamp == current.eventTimestamp &&
    expected.reactionId == current.reactionId &&
    expected.reactionAction == current.reactionAction &&
    expected.reactionTombstone == current.reactionTombstone &&
    expected.readiness == current.readiness;

/// Group counterpart of
/// [backgroundDirectDisplayAuthorityRemainsCurrentForFinalRead].
@visibleForTesting
bool backgroundGroupDisplayAuthorityRemainsCurrentForFinalRead({
  required GroupNotificationDisplayOutboxEntry expected,
  required GroupNotificationDisplayOutboxEntry current,
}) =>
    _sameGroupDisplayAuthorityIdentity(expected, current) &&
    (expected.revision == current.revision ||
        _isNotificationDisplayRetryOnlyRevisionAdvance(
          expectedRevision: expected.revision,
          currentRevision: current.revision,
          expectedRetryCount: expected.retryCount,
          currentRetryCount: current.retryCount,
          currentLastErrorCode: current.lastErrorCode,
          currentNextAttemptAt: current.nextAttemptAt,
        ));

bool _sameGroupDisplayAuthorityIdentity(
  GroupNotificationDisplayOutboxEntry expected,
  GroupNotificationDisplayOutboxEntry current,
) =>
    expected.eventId == current.eventId &&
    expected.eventKind == current.eventKind &&
    expected.groupId == current.groupId &&
    expected.messageId == current.messageId &&
    expected.actorPeerId == current.actorPeerId &&
    expected.eventTimestamp == current.eventTimestamp &&
    expected.reactionId == current.reactionId &&
    expected.reactionAction == current.reactionAction &&
    expected.reactionTombstone == current.reactionTombstone &&
    expected.readiness == current.readiness;

bool _isNotificationDisplayRetryOnlyRevisionAdvance({
  required int expectedRevision,
  required int currentRevision,
  required int expectedRetryCount,
  required int currentRetryCount,
  required String? currentLastErrorCode,
  required String? currentNextAttemptAt,
}) {
  final revisionAdvance = currentRevision - expectedRevision;
  final retryAdvance = currentRetryCount - expectedRetryCount;
  if (revisionAdvance <= 0 || revisionAdvance != retryAdvance) return false;
  if (_trimToNull(currentNextAttemptAt) == null) return false;
  return switch (currentLastErrorCode) {
    'display_failed' || 'claim_pending' || 'state_unavailable' => true,
    _ => false,
  };
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
