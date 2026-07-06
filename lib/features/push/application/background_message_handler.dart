import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/recent_background_notification_gate.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/remote_notification_identity.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_invites_db_helpers.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';
import 'package:flutter_app/features/push/application/resolve_group_notification_route_target_use_case.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final FlutterLocalNotificationsPlugin _backgroundNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
bool _backgroundNotificationsInitialized = false;
const String _backgroundDbEncryptionKey = 'db_encryption_key';

typedef BackgroundPushNotificationResolver =
    Future<BackgroundPushNotificationFallback> Function(RemoteMessage message);
typedef BackgroundPushNotificationDisplayEligibilityResolver =
    Future<PushFallbackNotificationDisplayEligibility> Function(
      RemoteMessage message,
    );

BackgroundPushNotificationResolver _backgroundPushNotificationResolver =
    resolveBackgroundPushNotification;
BackgroundPushNotificationDisplayEligibilityResolver
_backgroundPushNotificationDisplayEligibilityResolver =
    resolveBackgroundPushNotificationDisplayEligibilityFromLocalState;
AccountMigrationNetworkGate _backgroundAccountMigrationNetworkGate =
    _defaultBackgroundAccountMigrationNetworkGate;

@visibleForTesting
void debugSetBackgroundPushNotificationResolver(
  BackgroundPushNotificationResolver resolver,
) {
  _backgroundPushNotificationResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundPushNotificationResolver() {
  _backgroundPushNotificationResolver = resolveBackgroundPushNotification;
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

  try {
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
    final notificationId =
        (fallback.payload ?? message.messageId ?? fallback.title).hashCode;

    await _backgroundNotificationsPlugin.show(
      notificationId,
      fallback.title,
      fallback.body,
      mknoonMessagesNotificationDetails,
      payload: fallback.payload,
    );
    if (dedupeKey != null) {
      await recentBackgroundNotificationGate.markShown(dedupeKey);
    }
    await markVisibleRemoteAnnouncement();

    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
      details: {
        'messageId': message.messageId,
        'payload': fallback.payload ?? '',
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_NOTIFICATION_ERROR',
      details: {'error': e.toString()},
    );
  }
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

  return resolveBackgroundPushFallbackDisplayEligibility(
    message,
    groupMessageDisplayEligibilityResolver:
        _resolveGroupMessageNotificationDisplayEligibilityFromEncryptedDb,
  );
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
  return gate.allowsAccountNetworkSideEffects(peerId: peerId, operation: operation);
}

/// 04-P0 / SI-1: a confirmed group member's background-FCM display eligibility,
/// honoring mute. Pure decision over the loaded `groups` row so the is_muted
/// read is unit-testable without standing up a SQLCipher identity.db fixture.
/// Fails open (notifies) when the column is absent/null, matching the live path.
GroupMessageNotificationDisplayEligibility groupMemberMessageDisplayEligibility(
  Map<String, Object?> groupRow,
) {
  if ((groupRow['is_muted'] as int? ?? 0) == 1) {
    return const GroupMessageNotificationDisplayEligibility.suppressed('muted');
  }
  return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
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
  try {
    return await openDatabase(
      path,
      password: "x'$key'", // RAW_KEY
      readOnly: true,
      singleInstance: false,
    );
  } catch (_) {
    return await openDatabase(
      path,
      password: key, // LEGACY_PASSPHRASE_FALLBACK
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
