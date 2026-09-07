import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/group_invite_android_notification_identity.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/core/notifications/recent_background_notification_gate.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/group_reaction_notification_copy.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/fake_app_visibility.dart';

/// One entry of a `getNotificationChannels` platform reply. Every key the
/// plugin's mapper dereferences is supplied: it calls `Color(a['ledColor'])`
/// and `Importance.values.firstWhere(...)` unguarded, so a partial fixture
/// throws inside the plugin instead of exercising the code under test.
Map<String, Object?> _blockedChannelReply(String id, int importance) =>
    <String, Object?>{
      'id': id,
      'name': id,
      'description': null,
      'groupId': null,
      'showBadge': true,
      'importance': importance,
      'playSound': true,
      'soundSource': null,
      'enableLights': false,
      'enableVibration': true,
      'vibrationPattern': null,
      'ledColor': 0,
      'audioAttributesUsage': 5,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const cryptoChannel = MethodChannel('com.mknoon/background_push_crypto');
  final List<MethodCall> log = <MethodCall>[];

  test('TC-393-14 direct post-show completion cannot be skipped', () async {
    final source = await File(
      'lib/features/push/application/background_message_handler.dart',
    ).readAsString();
    final owner = source.indexOf(
      '_validateBackgroundDirectNotificationAfterShow({',
    );
    final nextOwner = source.indexOf('void _emitPlan393G30Diagnostic', owner);
    final body = source.substring(owner, nextOwner);

    expect(
      body,
      contains(
        'decision = await '
        'validateBackgroundDirectNotificationAfterShowInDatabase(',
      ),
      reason: 'the independent handle must outlive every validator query',
    );
    expect(
      body,
      isNot(
        contains(
          'return validateBackgroundDirectNotificationAfterShowInDatabase(',
        ),
      ),
      reason: 'returning the Future lets finally close the handle too early',
    );
    expect(
      body,
      contains('return effectiveDisposition;'),
      reason:
          'every completed validator must return its logged closed-domain '
          'keep/read/retire disposition',
    );
  });

  test(
    'persists only the exact token-registration transport installation',
    () async {
      final store = FakeSecureKeyStore();

      await persistBackgroundPushRegistrationTransportPeerId(
        secureKeyStore: store,
        transportPeerId: '  transport-this-install  ',
      );
      expect(
        await store.read('push_registration_transport_peer_id'),
        'transport-this-install',
      );

      await persistBackgroundPushRegistrationTransportPeerId(
        secureKeyStore: store,
        transportPeerId: ' ',
      );
      expect(await store.read('push_registration_transport_peer_id'), isNull);
    },
  );

  test(
    'FlutterFire direct post-show unknown is read-only and defers to staged ingestion',
    () async {
      final path =
          '${Directory.systemTemp.path}/background-direct-readonly-${DateTime.now().microsecondsSinceEpoch}.db';
      final writable = await databaseFactoryFfi.openDatabase(path);
      await writable.execute('''
        CREATE TABLE contacts (
          peer_id TEXT PRIMARY KEY,
          is_blocked INTEGER NOT NULL DEFAULT 0,
          is_archived INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await writable.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          contact_peer_id TEXT,
          is_incoming INTEGER,
          read_at TEXT,
          deleted_at TEXT,
          hidden_at TEXT,
          private_media_state TEXT
        )
      ''');
      await writable.insert('contacts', const <String, Object?>{
        'peer_id': 'peer-readonly',
        'is_blocked': 0,
        'is_archived': 0,
      });
      await writable.insert('messages', const <String, Object?>{
        'id': 'message-read',
        'contact_peer_id': 'peer-readonly',
        'is_incoming': 1,
        'read_at': '2026-08-16T01:00:00.000Z',
        'deleted_at': null,
        'hidden_at': null,
        'private_media_state': 'none',
      });
      await writable.close();
      final readOnly = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      addTearDown(() async {
        await readOnly.close();
        await databaseFactoryFfi.deleteDatabase(path);
      });

      expect(
        await validateBackgroundDirectNotificationAfterShowInDatabase(
          readOnly,
          peerId: 'peer-readonly',
          metadata: const ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity: 'not-materialized-yet',
            generation: 'generation-readonly',
          ),
        ),
        BackgroundDirectNotificationPostShowDecision.unknown,
      );
      expect(
        await validateBackgroundDirectNotificationAfterShowInDatabase(
          readOnly,
          peerId: 'peer-readonly',
          metadata: const ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity: 'message-read',
            generation: 'generation-readonly',
          ),
        ),
        BackgroundDirectNotificationPostShowDecision.read,
      );
    },
  );

  test(
    'background direct final facts enforce exact READY comparands and private terminals',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
        CREATE TABLE contacts (
          peer_id TEXT PRIMARY KEY,
          is_blocked INTEGER NOT NULL DEFAULT 0,
          is_archived INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          contact_peer_id TEXT,
          sender_peer_id TEXT,
          timestamp TEXT,
          is_incoming INTEGER,
          read_at TEXT,
          deleted_at TEXT,
          hidden_at TEXT,
          private_media_state TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE message_reactions (
          id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          sender_peer_id TEXT NOT NULL,
          timestamp TEXT,
          removed_at TEXT,
          UNIQUE(message_id, sender_peer_id)
        )
      ''');
      await db.execute('''
        CREATE TABLE direct_notification_reaction_terminal_events (
          peer_id TEXT NOT NULL,
          message_id TEXT NOT NULL,
          actor_peer_id TEXT NOT NULL,
          reaction_id TEXT NOT NULL,
          terminal_event_id TEXT NOT NULL,
          notification_acknowledged_at TEXT,
          updated_at TEXT NOT NULL,
          PRIMARY KEY(peer_id, message_id, actor_peer_id)
        )
      ''');
      await db.insert('contacts', const <String, Object?>{
        'peer_id': 'peer-final-facts',
      });
      await db.insert('messages', const <String, Object?>{
        'id': 'message-final-facts',
        'contact_peer_id': 'peer-final-facts',
        'sender_peer_id': 'peer-final-facts',
        'timestamp': '2026-08-16T12:00:00.000Z',
        'is_incoming': 1,
        'read_at': null,
        'deleted_at': null,
        'hidden_at': null,
        'private_media_state': 'available',
      });
      await db.insert('messages', const <String, Object?>{
        'id': 'reaction-target-final-facts',
        'contact_peer_id': 'peer-final-facts',
        'sender_peer_id': 'peer-self-final-facts',
        'timestamp': '2026-08-16T11:59:00.000Z',
        'is_incoming': 0,
        'read_at': null,
        'deleted_at': null,
        'hidden_at': null,
        'private_media_state': 'available',
      });
      await db.insert('message_reactions', const <String, Object?>{
        'id': 'reaction-final-facts',
        'message_id': 'reaction-target-final-facts',
        'sender_peer_id': 'peer-final-facts',
        'timestamp': '2026-08-16T12:00:01.000Z',
        'removed_at': null,
      });
      await db.insert(
        'direct_notification_reaction_terminal_events',
        const <String, Object?>{
          'peer_id': 'peer-final-facts',
          'message_id': 'reaction-target-final-facts',
          'actor_peer_id': 'peer-final-facts',
          'reaction_id': 'reaction-final-facts',
          'terminal_event_id': 'reaction-event-final-facts',
          'notification_acknowledged_at': null,
          'updated_at': '2026-08-16T12:00:00.000Z',
        },
      );

      const messageMetadata = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: 'message-final-facts',
        generation: 'generation-message-final-facts',
      );
      const reactionMetadata = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.reaction,
        eventIdentity: 'reaction-event-final-facts',
        generation: 'generation-reaction-final-facts',
      );
      const messageEntry = DirectNotificationDisplayOutboxEntry.message(
        eventId: 'message-final-facts',
        peerId: 'peer-final-facts',
        messageId: 'message-final-facts',
        actorPeerId: 'peer-final-facts',
        eventTimestamp: '2026-08-16T12:00:00.000Z',
        readiness: DirectNotificationDisplayOutboxReadiness.ready,
        revision: 2,
        createdAt: '2026-08-16T12:00:00.000Z',
        updatedAt: '2026-08-16T12:00:00.000Z',
      );
      const reactionEntry = DirectNotificationDisplayOutboxEntry.reaction(
        eventId: 'reaction-event-final-facts',
        peerId: 'peer-final-facts',
        messageId: 'reaction-target-final-facts',
        actorPeerId: 'peer-final-facts',
        eventTimestamp: '2026-08-16T12:00:01.000Z',
        reactionId: 'reaction-final-facts',
        reactionAction: 'add',
        reactionTombstone: false,
        readiness: DirectNotificationDisplayOutboxReadiness.ready,
        revision: 3,
        createdAt: '2026-08-16T12:00:01.000Z',
        updatedAt: '2026-08-16T12:00:01.000Z',
      );
      Future<BackgroundDirectNotificationPostShowDecision> validateMessage() =>
          validateBackgroundDirectNotificationAfterShowInDatabase(
            db,
            peerId: 'peer-final-facts',
            metadata: messageMetadata,
            expectedEntry: messageEntry,
          );
      Future<BackgroundDirectNotificationPostShowDecision> validateReaction() =>
          validateBackgroundDirectNotificationAfterShowInDatabase(
            db,
            peerId: 'peer-final-facts',
            metadata: reactionMetadata,
            expectedEntry: reactionEntry,
          );

      expect(
        await validateMessage(),
        BackgroundDirectNotificationPostShowDecision.keep,
      );
      expect(
        await validateReaction(),
        BackgroundDirectNotificationPostShowDecision.keep,
      );

      await db.update(
        'messages',
        const <String, Object?>{'sender_peer_id': 'peer-mutated'},
        where: 'id = ?',
        whereArgs: const <Object?>['message-final-facts'],
      );
      expect(
        await validateMessage(),
        BackgroundDirectNotificationPostShowDecision.unknown,
        reason: 'message sender mutation cannot borrow exact READY authority',
      );
      await db.update(
        'messages',
        const <String, Object?>{
          'sender_peer_id': 'peer-final-facts',
          'timestamp': '2026-08-16T12:00:02.000Z',
        },
        where: 'id = ?',
        whereArgs: const <Object?>['message-final-facts'],
      );
      expect(
        await validateMessage(),
        BackgroundDirectNotificationPostShowDecision.unknown,
        reason:
            'message timestamp mutation cannot borrow exact READY authority',
      );
      await db.update(
        'messages',
        const <String, Object?>{'timestamp': '2026-08-16T12:00:00.000Z'},
        where: 'id = ?',
        whereArgs: const <Object?>['message-final-facts'],
      );
      await db.update(
        'direct_notification_reaction_terminal_events',
        const <String, Object?>{'actor_peer_id': 'peer-mutated'},
        where: 'terminal_event_id = ?',
        whereArgs: const <Object?>['reaction-event-final-facts'],
      );
      expect(
        await validateReaction(),
        BackgroundDirectNotificationPostShowDecision.unknown,
        reason: 'mutable terminal cannot substitute another READY actor',
      );
      await db.update(
        'direct_notification_reaction_terminal_events',
        const <String, Object?>{'actor_peer_id': 'peer-final-facts'},
        where: 'terminal_event_id = ?',
        whereArgs: const <Object?>['reaction-event-final-facts'],
      );
      await db.update(
        'message_reactions',
        const <String, Object?>{'timestamp': '2026-08-16T12:00:03.000Z'},
        where: 'id = ?',
        whereArgs: const <Object?>['reaction-final-facts'],
      );
      expect(
        await validateReaction(),
        BackgroundDirectNotificationPostShowDecision.retire,
        reason: 'a newer reaction timestamp cancels the staged generation',
      );
      await db.update(
        'message_reactions',
        const <String, Object?>{'timestamp': '2026-08-16T12:00:01.000Z'},
        where: 'id = ?',
        whereArgs: const <Object?>['reaction-final-facts'],
      );

      for (final state in const <String>[
        'consumed',
        'expired',
        'unsupported',
      ]) {
        await db.update(
          'messages',
          <String, Object?>{'private_media_state': state},
          where: 'id = ?',
          whereArgs: const <Object?>['message-final-facts'],
        );
        expect(
          await validateMessage(),
          BackgroundDirectNotificationPostShowDecision.retire,
          reason: 'message private-media $state is terminal',
        );
        await db.update(
          'messages',
          <String, Object?>{'private_media_state': state},
          where: 'id = ?',
          whereArgs: const <Object?>['reaction-target-final-facts'],
        );
        expect(
          await validateReaction(),
          BackgroundDirectNotificationPostShowDecision.retire,
          reason: 'reaction target private-media $state is terminal',
        );
      }

      await db.update(
        'messages',
        const <String, Object?>{
          'private_media_state': 'available',
          'hidden_at': '2026-08-16T12:01:00.000Z',
        },
        where: 'id IN (?, ?)',
        whereArgs: const <Object?>[
          'message-final-facts',
          'reaction-target-final-facts',
        ],
      );
      expect(
        await validateMessage(),
        BackgroundDirectNotificationPostShowDecision.retire,
      );
      expect(
        await validateReaction(),
        BackgroundDirectNotificationPostShowDecision.retire,
      );
      await db.delete(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: const <Object?>['peer-final-facts'],
      );
      expect(
        await validateMessage(),
        BackgroundDirectNotificationPostShowDecision.unknown,
        reason: 'missing contact is unknown, never suppression authority',
      );
      expect(
        await validateReaction(),
        BackgroundDirectNotificationPostShowDecision.unknown,
        reason: 'missing contact is unknown, never suppression authority',
      );
    },
  );

  test(
    'final background authority accepts retry-only revision advances and rejects canonical drift',
    () {
      const expected = DirectNotificationDisplayOutboxEntry.message(
        eventId: 'message-retry-race',
        peerId: 'peer-retry-race',
        messageId: 'message-retry-race',
        actorPeerId: 'peer-retry-race',
        eventTimestamp: '2026-08-21T13:58:27.011136Z',
        readiness: DirectNotificationDisplayOutboxReadiness.ready,
        revision: 2,
        createdAt: '2026-08-21T13:58:28.774121Z',
        updatedAt: '2026-08-21T13:58:28.774121Z',
      );
      final retryOnly = expected.copyWith(
        revision: 3,
        retryCount: 1,
        lastErrorCode: DirectNotificationDisplayOutboxErrorCode.claimPending,
        lastAttemptAt: '2026-08-21T13:58:31.720000Z',
        nextAttemptAt: '2026-08-21T13:59:36.720000Z',
        updatedAt: '2026-08-21T13:58:31.720000Z',
      );

      expect(
        backgroundDirectDisplayAuthorityRemainsCurrentForFinalRead(
          expected: expected,
          current: retryOnly,
        ),
        isTrue,
      );
      expect(
        backgroundDirectDisplayAuthorityRemainsCurrentForFinalRead(
          expected: expected,
          current: retryOnly.copyWith(messageId: 'different-message'),
        ),
        isFalse,
        reason: 'immutable identity changes are never retry bookkeeping',
      );
      expect(
        backgroundDirectDisplayAuthorityRemainsCurrentForFinalRead(
          expected: expected,
          current: retryOnly.copyWith(revision: 4),
        ),
        isFalse,
        reason: 'a non-retry revision advance preserves the final-read fence',
      );
      expect(
        backgroundDirectDisplayAuthorityRemainsCurrentForFinalRead(
          expected: expected,
          current: expected.copyWith(
            revision: 3,
            lastErrorCode:
                DirectNotificationDisplayOutboxErrorCode.stateUnavailable,
            lastAttemptAt: DirectNotificationDisplayOutboxErrorCode
                .canonicalRetirementAttemptMarker,
          ),
        ),
        isFalse,
        reason: 'canonical retirement cannot authorize an alert',
      );
    },
  );

  setUp(() async {
    flowEventLoggingEnabled = false;
    log.clear();
    debugResetBackgroundDirectNotificationPostShowValidator();

    final backgroundGate = RecentBackgroundNotificationGate(
      filePath:
          '${Directory.systemTemp.path}/background-handler-gate-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    debugSetRecentBackgroundNotificationGate(backgroundGate);
    addTearDown(backgroundGate.clear);

    final remoteGate = RecentRemoteNotificationGate(
      filePath:
          '${Directory.systemTemp.path}/background-handler-remote-gate-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    debugSetRecentRemoteNotificationGate(remoteGate);
    addTearDown(remoteGate.clear);

    final reactionCoordinatorDirectory = Directory.systemTemp.createTempSync(
      'background-reaction-coordinator-',
    );
    final reactionCoordinator = DurableNotificationToneLease(
      directory: reactionCoordinatorDirectory,
    );
    debugSetBackgroundReactionNotificationCoordinatorResolver(
      () async => reactionCoordinator,
    );
    addTearDown(() async {
      if (reactionCoordinatorDirectory.existsSync()) {
        reactionCoordinatorDirectory.deleteSync(recursive: true);
      }
    });

    final messageCoordinatorDirectory = Directory.systemTemp.createTempSync(
      'background-message-coordinator-',
    );
    final messageCoordinator = DurableNotificationToneLease(
      directory: messageCoordinatorDirectory,
      pendingClaimWait: Duration.zero,
    );
    debugSetBackgroundMessageNotificationCoordinatorResolver(
      () async => messageCoordinator,
    );
    addTearDown(() async {
      if (messageCoordinatorDirectory.existsSync()) {
        messageCoordinatorDirectory.deleteSync(recursive: true);
      }
    });

    final notificationIdDirectory = Directory.systemTemp.createTempSync(
      'background-notification-id-registry-',
    );
    final notificationIdRegistry = DurableConversationNotificationIdRegistry(
      directory: notificationIdDirectory,
    );
    await LocalNotificationLedgerStore(
      directory: notificationIdDirectory,
    ).initializeOrRebind(currentOpaqueBinding: 'v1:${'b' * 64}');
    debugSetBackgroundConversationNotificationIdRegistryResolver(
      () async => notificationIdRegistry,
    );
    addTearDown(() async {
      if (notificationIdDirectory.existsSync()) {
        notificationIdDirectory.deleteSync(recursive: true);
      }
    });

    debugSetBackgroundAccountMigrationNetworkGate(({
      String? peerId,
      required String operation,
    }) async {
      return true;
    });
    debugSetBackgroundGroupNotificationPostShowValidator(
      (_) async => BackgroundGroupNotificationPostShowDecision.keep,
    );
    debugSetBackgroundDurableLocalNotificationEffectResolver(({
      required routeTarget,
      required fallback,
      required metadata,
    }) async {
      final resolved = fallback.resolvedEventIdentity;
      if (resolved == null) return null;
      final identity = AppVisibilityConversationIdentity.tryParse(
        lane: routeTarget.kind == NotificationRouteTargetKind.group
            ? AppVisibilityConversationLane.group
            : AppVisibilityConversationLane.direct,
        value: routeTarget.kind == NotificationRouteTargetKind.group
            ? 'group:${routeTarget.groupId}'
            : routeTarget.peerId ?? '',
      );
      final outcomeProducer = switch ((routeTarget.kind, metadata.kind)) {
        (
          NotificationRouteTargetKind.conversation,
          ConversationNotificationContentKind.message,
        ) =>
          NotificationCompletedOutcomeProducerKind.directMessage,
        (
          NotificationRouteTargetKind.conversation,
          ConversationNotificationContentKind.reaction,
        ) =>
          NotificationCompletedOutcomeProducerKind.directReaction,
        (
          NotificationRouteTargetKind.group,
          ConversationNotificationContentKind.message,
        ) =>
          NotificationCompletedOutcomeProducerKind.groupMessage,
        (
          NotificationRouteTargetKind.group,
          ConversationNotificationContentKind.reaction,
        ) =>
          NotificationCompletedOutcomeProducerKind.groupReaction,
        _ => null,
      };
      final ledgerProducer = switch (outcomeProducer) {
        NotificationCompletedOutcomeProducerKind.directMessage =>
          LocalNotificationProducerKind.directMessage,
        NotificationCompletedOutcomeProducerKind.directReaction =>
          LocalNotificationProducerKind.directReaction,
        NotificationCompletedOutcomeProducerKind.groupMessage =>
          LocalNotificationProducerKind.groupMessage,
        NotificationCompletedOutcomeProducerKind.groupReaction =>
          LocalNotificationProducerKind.groupReaction,
        null => null,
      };
      final correlation = outcomeProducer == null
          ? null
          : tryComputeNotificationCompletedOutcomeCorrelation(
              physicalPeerId: 'test-physical-peer',
              producerKind: outcomeProducer,
              eventKey: resolved.canonicalEventId,
            );
      if (identity == null || ledgerProducer == null || correlation == null) {
        return null;
      }
      return DurableLocalNotificationEffectContext(
        currentOpaqueBinding: 'v1:${'b' * 64}',
        eventCorrelation: correlation,
        conversationDigest: identity.digest,
        producerKind: ledgerProducer,
        sourceCustody: LocalNotificationSourceCustody.sqlReady,
        presentationOwner:
            LocalNotificationPresentationOwner.androidPushService,
        readFinalCanonicalDisposition: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );
    });
    debugSetBackgroundAppVisibilityResolver(() async => FixedAppVisibility());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cryptoChannel, null);
    debugDefaultTargetPlatformOverride = null;
    debugSetFlowEventSink(null);
    debugResetRecentBackgroundNotificationGate();
    debugResetRecentRemoteNotificationGate();
    debugResetBackgroundPushNotificationResolver();
    debugResetBackgroundPushNotificationDisplayEligibilityResolver();
    debugResetBackgroundDirectMessageLocalStateResolver();
    debugResetBackgroundGroupMessageLocalStateResolver();
    debugResetBackgroundNotificationLocaleResolver();
    debugResetBackgroundDirectReactionLocalStateResolver();
    debugResetBackgroundGroupReactionLocalStateResolver();
    debugResetBackgroundGroupNotificationPostShowValidator();
    debugResetBackgroundDirectNotificationPostShowValidator();
    debugResetBackgroundDurableLocalNotificationEffectResolver();
    debugResetBackgroundAppVisibilityResolver();
    debugResetBackgroundMessageNotificationCoordinatorResolver();
    debugResetBackgroundConversationNotificationIdRegistryResolver();
    debugResetBackgroundReactionNotificationCoordinatorResolver();
    debugResetBackgroundAccountMigrationNetworkGate();
    debugResetBackgroundPushEnvelopeStager();
    debugResetBackgroundPendingConversationNotificationOverlayResolver();
    debugResetBackgroundNotificationsInitialization();
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearLocaleTestValue();
  });

  group('firebaseMessagingBackgroundHandler', () {
    test(
      'TC-395-05 group invite fallback keeps a non-conversation exact route identity',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundPushNotificationResolver(
          (message) async => buildBackgroundPushFallbackNotification(message),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        for (final inviteId in const ['invite-a', 'invite-b']) {
          await firebaseMessagingBackgroundHandler(
            RemoteMessage(
              messageId: 'provider-$inviteId',
              data: <String, dynamic>{
                'type': 'group_invite',
                'groupId': 'group-395',
                'message_id': inviteId,
              },
            ),
          );
        }

        const firstKey = 'group_invite:group-395|message:invite-a';
        const secondKey = 'group_invite:group-395|message:invite-b';
        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(2));
        final first = shows.first.arguments as Map;
        final second = shows.last.arguments as Map;
        expect(first['payload'], firstKey);
        expect(second['payload'], secondKey);
        expect(first['id'], groupInviteAndroidNotificationId);
        expect(second['id'], groupInviteAndroidNotificationId);
        expect(
          (first['platformSpecifics'] as Map)['tag'],
          groupInviteAndroidNotificationTag(
            groupId: 'group-395',
            inviteId: 'invite-a',
          ),
        );
        expect(
          (second['platformSpecifics'] as Map)['tag'],
          groupInviteAndroidNotificationTag(
            groupId: 'group-395',
            inviteId: 'invite-b',
          ),
        );
        expect(
          (first['platformSpecifics'] as Map)['tag'],
          isNot((second['platformSpecifics'] as Map)['tag']),
        );
      },
    );

    test(
      'TC-395-06 repeated group invite delivery updates one native identity without history suppression',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundPushNotificationResolver(
          (message) async => buildBackgroundPushFallbackNotification(message),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        for (final providerId in const ['provider-first', 'provider-replay']) {
          await firebaseMessagingBackgroundHandler(
            RemoteMessage(
              messageId: providerId,
              data: const <String, dynamic>{
                'type': 'group_invite',
                'groupId': 'group-395',
                'message_id': 'invite-multi-use',
              },
            ),
          );
        }

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(2));
        final first = shows.first.arguments as Map;
        final second = shows.last.arguments as Map;
        expect(first['id'], groupInviteAndroidNotificationId);
        expect(second['id'], groupInviteAndroidNotificationId);
        expect(
          (first['platformSpecifics'] as Map)['tag'],
          (second['platformSpecifics'] as Map)['tag'],
        );
        expect(first['payload'], second['payload']);
      },
    );

    test(
      'TC-393-04 nondurable final barrier prevents canonical or visible race',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundDurableLocalNotificationEffectResolver(
          ({
            required routeTarget,
            required fallback,
            required metadata,
          }) async => null,
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        Future<void> runDenied({
          required String suffix,
          required AppVisibilitySuppressionReader visibility,
          required BackgroundGroupNotificationPostShowDecision decision,
        }) async {
          final groupId = 'group-final-$suffix';
          final messageId = 'message-final-$suffix';
          final ownerDirectory = Directory.systemTemp.createTempSync(
            'tc393-final-owner-$suffix-',
          );
          final coordinator = DurableNotificationToneLease(
            directory: ownerDirectory,
            pendingClaimWait: Duration.zero,
            pendingToneReservationWait: Duration.zero,
          );
          addTearDown(() {
            if (ownerDirectory.existsSync()) {
              ownerDirectory.deleteSync(recursive: true);
            }
          });
          debugSetBackgroundMessageNotificationCoordinatorResolver(
            () async => coordinator,
          );
          debugSetBackgroundAppVisibilityResolver(() async => visibility);
          debugSetBackgroundGroupNotificationPostShowValidator(
            (_) async => decision,
          );
          debugSetBackgroundPushNotificationResolver(
            (_) async => BackgroundPushNotificationFallback(
              title: 'Team',
              body: 'Alice: final barrier',
              payload: 'group:$groupId|message:$messageId',
              groupComparand: BackgroundGroupMessageNotificationComparand(
                groupId: groupId,
                messageId: messageId,
                senderPeerId: 'peer-alice',
              ),
              resolvedEventIdentity:
                  ResolvedPushEventIdentity.authenticatedInner(
                    kind: ConversationNotificationContentKind.message,
                    canonicalEventId: messageId,
                  ),
            ),
          );
          await useIsolatedBackgroundNotificationRegistry('final-$suffix');
          final showsBefore = log.where((call) => call.method == 'show').length;

          await firebaseMessagingBackgroundHandler(
            RemoteMessage(
              messageId: 'provider-final-$suffix',
              data: <String, dynamic>{
                'type': 'group_message',
                'groupId': groupId,
                'message_id': messageId,
              },
            ),
          );

          expect(
            log.where((call) => call.method == 'show').length,
            showsBefore,
            reason: suffix,
          );
          final reacquired = await coordinator.acquireMessageEventClaim(
            type: 'group_message',
            eventIdentity: messageId,
          );
          expect(reacquired.claim, isNotNull, reason: '$suffix event owner');
          expect(
            await coordinator.reserveTone('group:$groupId'),
            isNotNull,
            reason: '$suffix tone owner',
          );
          await reacquired.claim?.release();
        }

        await runDenied(
          suffix: 'canonical-read',
          visibility: FixedAppVisibility(),
          decision: BackgroundGroupNotificationPostShowDecision.read,
        );
        await runDenied(
          suffix: 'exact-visible',
          visibility: FixedAppVisibility(
            isForegroundActive: true,
            maySuppress: true,
          ),
          decision: BackgroundGroupNotificationPostShowDecision.keep,
        );

        // An ordinary canonical-read phase timeout is unknown authority, not
        // proof that the event is read or the exact conversation is visible.
        // It must therefore keep the alert while the aggregate still has
        // headroom; exhausting the aggregate remains fail-closed elsewhere.
        const timeoutGroupId = 'group-final-timeout';
        const timeoutMessageId = 'message-final-timeout';
        final timeoutOwnerDirectory = Directory.systemTemp.createTempSync(
          'tc393-final-owner-timeout-',
        );
        final timeoutCoordinator = DurableNotificationToneLease(
          directory: timeoutOwnerDirectory,
          pendingClaimWait: Duration.zero,
          pendingToneReservationWait: Duration.zero,
        );
        addTearDown(() {
          debugResetBackgroundStorageDeadlineDurations();
          if (timeoutOwnerDirectory.existsSync()) {
            timeoutOwnerDirectory.deleteSync(recursive: true);
          }
        });
        debugSetBackgroundStorageDeadlineDurations(
          aggregate: const Duration(seconds: 2),
          phase: const Duration(milliseconds: 250),
          displayEligibilityReserve: const Duration(milliseconds: 250),
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => timeoutCoordinator,
        );
        debugSetBackgroundAppVisibilityResolver(
          () async => FixedAppVisibility(),
        );
        final timeoutValidatorEntered = Completer<void>();
        final timeoutValidator =
            Completer<BackgroundGroupNotificationPostShowDecision>();
        var timeoutValidationCalls = 0;
        debugSetBackgroundGroupNotificationPostShowValidator((_) {
          timeoutValidationCalls += 1;
          if (!timeoutValidatorEntered.isCompleted) {
            timeoutValidatorEntered.complete();
          }
          return timeoutValidator.future;
        });
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Team',
            body: 'Alice: timeout is unknown',
            payload: 'group:group-final-timeout|message:message-final-timeout',
            groupComparand: BackgroundGroupMessageNotificationComparand(
              groupId: timeoutGroupId,
              messageId: timeoutMessageId,
              senderPeerId: 'peer-alice',
            ),
            resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
              kind: ConversationNotificationContentKind.message,
              canonicalEventId: timeoutMessageId,
            ),
          ),
        );
        await useIsolatedBackgroundNotificationRegistry('final-timeout');
        final timeoutShowsBefore = log
            .where((call) => call.method == 'show')
            .length;
        final timeoutHandler = firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-final-timeout',
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': timeoutGroupId,
              'message_id': timeoutMessageId,
            },
          ),
        );
        try {
          await timeoutValidatorEntered.future.timeout(
            const Duration(seconds: 1),
          );
          expect(
            log.where((call) => call.method == 'show').length,
            timeoutShowsBefore,
            reason: 'native entry must wait for the final barrier',
          );
          await timeoutHandler.timeout(const Duration(seconds: 3));
        } finally {
          if (!timeoutValidator.isCompleted) {
            timeoutValidator.complete(
              BackgroundGroupNotificationPostShowDecision.keep,
            );
          }
        }
        expect(timeoutValidationCalls, 2);
        expect(
          log.where((call) => call.method == 'show').length,
          timeoutShowsBefore + 1,
          reason:
              'ordinary timeout must fail toward one notification before the '
              'aggregate hard stop',
        );
      },
    );

    test(
      'TC-394-04 nondurable direct final barrier rolls back exact message and reaction owners',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundDurableLocalNotificationEffectResolver(
          ({
            required routeTarget,
            required fallback,
            required metadata,
          }) async => null,
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        final scenarios =
            <
              ({
                _DirectFinalBarrierLeg leg,
                ConversationNotificationContentKind kind,
                String suffix,
                String peerId,
                String rawEventIdentity,
                String eventIdentity,
                String claimType,
                String payload,
                String toneKey,
                Map<String, dynamic> data,
              })
            >[
              (
                leg: _DirectFinalBarrierLeg.canonicalRead,
                kind: ConversationNotificationContentKind.message,
                suffix: 'message-canonical-read',
                peerId: 'peer-final-message-read',
                rawEventIdentity: 'message-final-canonical-read',
                eventIdentity: 'message-final-canonical-read',
                claimType: 'new_message',
                payload: 'peer-final-message-read',
                toneKey: 'peer-final-message-read',
                data: <String, dynamic>{
                  'type': 'new_message',
                  'sender_id': 'peer-final-message-read',
                  'message_id': 'message-final-canonical-read',
                },
              ),
              (
                leg: _DirectFinalBarrierLeg.exactVisible,
                kind: ConversationNotificationContentKind.reaction,
                suffix: 'reaction-exact-visible',
                peerId: 'peer-final-reaction-visible',
                rawEventIdentity: 'reaction-final-exact-visible',
                eventIdentity: boundedReactionEventIdentity(
                  'reaction-final-exact-visible',
                ),
                claimType: 'message_reaction',
                payload:
                    'peer-final-reaction-visible|message:'
                    'target-final-reaction-visible',
                toneKey:
                    'peer-final-reaction-visible|message:'
                    'target-final-reaction-visible',
                data: <String, dynamic>{
                  'type': 'message_reaction',
                  'sender_id': 'peer-final-reaction-visible',
                  'target_message_id': 'target-final-reaction-visible',
                  'action': 'add',
                  'event_id': 'reaction-final-exact-visible',
                  'reaction_id': 'reaction-final-exact-visible',
                },
              ),
              (
                leg: _DirectFinalBarrierLeg.visibilityUnknown,
                kind: ConversationNotificationContentKind.message,
                suffix: 'message-visibility-unknown',
                peerId: 'peer-final-visibility-unknown',
                rawEventIdentity: 'message-final-visibility-unknown',
                eventIdentity: 'message-final-visibility-unknown',
                claimType: 'new_message',
                payload: 'peer-final-visibility-unknown',
                toneKey: 'peer-final-visibility-unknown',
                data: <String, dynamic>{
                  'type': 'new_message',
                  'sender_id': 'peer-final-visibility-unknown',
                  'message_id': 'message-final-visibility-unknown',
                },
              ),
            ];

        Future<void> expectPublishingOwners({
          required Directory ownerDirectory,
          required String claimType,
          required String eventIdentity,
          required String toneKey,
          required String reason,
        }) async {
          final eventClaim = File(
            '${ownerDirectory.path}/'
            '${DurableNotificationToneLease.eventClaimsDirectoryName}/'
            '${DurableNotificationToneLease.messageEventClaimFileName(type: claimType, eventIdentity: eventIdentity)}',
          );
          expect(eventClaim.existsSync(), isTrue, reason: '$reason event');
          expect(
            jsonDecode(await eventClaim.readAsString()),
            containsPair('state', 'publishing'),
            reason: '$reason exact event owner',
          );

          final toneDirectory = Directory(
            '${ownerDirectory.path}/'
            '${DurableNotificationToneLease.toneLeasesDirectoryName}',
          );
          expect(toneDirectory.existsSync(), isTrue, reason: '$reason tone');
          final pendingToneOwners = toneDirectory
              .listSync()
              .whereType<File>()
              .where(
                (file) => file.path.endsWith(
                  DurableNotificationToneLease.tonePendingReservationFileSuffix,
                ),
              )
              .toList();
          expect(
            pendingToneOwners,
            hasLength(1),
            reason: '$reason sole tone sidecar',
          );
          final expectedPendingToneOwner = File(
            '${toneDirectory.path}/.'
            '${sha256.convert(utf8.encode(toneKey.trim()))}'
            '${DurableNotificationToneLease.tonePendingReservationFileSuffix}',
          );
          expect(
            pendingToneOwners.single.path,
            expectedPendingToneOwner.path,
            reason: '$reason exact tone-key owner',
          );
          expect(
            jsonDecode(await pendingToneOwners.single.readAsString()),
            containsPair('state', 'publishing'),
            reason: '$reason exact tone owner',
          );
        }

        for (final scenario in scenarios) {
          // The lease snapshots its platform, so pin Android before creating
          // any per-leg owner fixture.
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          final ownerDirectory = Directory.systemTemp.createTempSync(
            'tc394-direct-final-${scenario.suffix}-',
          );
          addTearDown(() {
            if (ownerDirectory.existsSync()) {
              ownerDirectory.deleteSync(recursive: true);
            }
          });
          final coordinator = DurableNotificationToneLease(
            directory: ownerDirectory,
            pendingClaimWait: Duration.zero,
            pendingToneReservationWait: Duration.zero,
            platform: TargetPlatform.android,
          );
          expect(
            coordinator.platform,
            TargetPlatform.android,
            reason: '${scenario.suffix} must exercise Android publishing',
          );
          if (scenario.kind == ConversationNotificationContentKind.reaction) {
            debugSetBackgroundReactionNotificationCoordinatorResolver(
              () async => coordinator,
            );
          } else {
            debugSetBackgroundMessageNotificationCoordinatorResolver(
              () async => coordinator,
            );
          }
          await useIsolatedBackgroundNotificationRegistry(
            'tc394-${scenario.suffix}',
          );

          final fixedVisibility = FixedAppVisibility();
          final controlledVisibility = switch (scenario.leg) {
            _DirectFinalBarrierLeg.canonicalRead => null,
            _DirectFinalBarrierLeg.exactVisible =>
              _ControlledBackgroundVisibility(
                evaluation: const AppVisibilityEvaluation(
                  isForegroundActive: true,
                  maySuppress: true,
                ),
              ),
            _DirectFinalBarrierLeg.visibilityUnknown =>
              _ControlledBackgroundVisibility(
                failure: StateError('visibility unavailable'),
              ),
          };
          debugSetBackgroundAppVisibilityResolver(
            () async => controlledVisibility ?? fixedVisibility,
          );

          final validatorEntered = Completer<void>();
          final canonicalRead =
              scenario.leg == _DirectFinalBarrierLeg.canonicalRead
              ? Completer<BackgroundDirectNotificationPostShowDecision>()
              : null;
          final validatedPeers = <String>[];
          final validatedMetadata = <ConversationNotificationContentMetadata>[];
          Future<BackgroundDirectNotificationPostShowDecision> validate({
            required String peerId,
            required ConversationNotificationContentMetadata metadata,
          }) {
            validatedPeers.add(peerId);
            validatedMetadata.add(metadata);
            if (!validatorEntered.isCompleted) validatorEntered.complete();
            return canonicalRead?.future ??
                Future<BackgroundDirectNotificationPostShowDecision>.value(
                  BackgroundDirectNotificationPostShowDecision.keep,
                );
          }

          debugSetBackgroundDirectNotificationPostShowValidator(validate);
          debugSetBackgroundPushNotificationResolver(
            (_) async => BackgroundPushNotificationFallback(
              title:
                  scenario.kind == ConversationNotificationContentKind.reaction
                  ? 'Reaction'
                  : 'Alice',
              body:
                  scenario.kind == ConversationNotificationContentKind.reaction
                  ? 'Alice reacted to your message'
                  : 'final barrier message',
              payload: scenario.payload,
              resolvedEventIdentity:
                  ResolvedPushEventIdentity.authenticatedInner(
                    kind: scenario.kind,
                    canonicalEventId: scenario.rawEventIdentity,
                  ),
            ),
          );
          final events = <Map<String, dynamic>>[];
          debugSetFlowEventSink(events.add);
          final showsBefore = log.where((call) => call.method == 'show').length;
          final handling = firebaseMessagingBackgroundHandler(
            RemoteMessage(
              messageId: 'provider-${scenario.suffix}',
              data: scenario.data,
            ),
          );

          try {
            if (scenario.leg == _DirectFinalBarrierLeg.canonicalRead) {
              await validatorEntered.future.timeout(const Duration(seconds: 1));
            } else {
              await controlledVisibility!.entered.future.timeout(
                const Duration(seconds: 1),
              );
            }
            await validatorEntered.future.timeout(const Duration(seconds: 1));
            expect(
              validatedPeers,
              <String>[scenario.peerId],
              reason: '${scenario.suffix} exact validator peer at boundary',
            );
            expect(
              validatedMetadata.single.kind,
              scenario.kind,
              reason: '${scenario.suffix} exact validator content kind',
            );
            expect(
              validatedMetadata.single.eventIdentity,
              scenario.eventIdentity,
              reason: '${scenario.suffix} exact validator event identity',
            );
            if (controlledVisibility == null) {
              expect(
                fixedVisibility.evaluations,
                0,
                reason: 'canonical read must deny before visibility',
              );
            } else {
              expect(controlledVisibility.identities, hasLength(1));
              final identity = controlledVisibility.identities.single;
              expect(identity?.lane, AppVisibilityConversationLane.direct);
              expect(identity?.normalizedValue, scenario.peerId);
            }
            expect(
              log.where((call) => call.method == 'show').length,
              showsBefore,
              reason: '${scenario.suffix} must hold before native show',
            );
            await expectPublishingOwners(
              ownerDirectory: ownerDirectory,
              claimType: scenario.claimType,
              eventIdentity: scenario.eventIdentity,
              toneKey: scenario.toneKey,
              reason: scenario.suffix,
            );
          } finally {
            if (canonicalRead != null && !canonicalRead.isCompleted) {
              canonicalRead.complete(
                BackgroundDirectNotificationPostShowDecision.read,
              );
            }
            controlledVisibility?.release();
            await handling.timeout(const Duration(seconds: 3));
          }

          final showsAfter = log.where((call) => call.method == 'show').length;
          final ownershipSuppressions = events.where((event) {
            if (event['event'] != 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED') {
              return false;
            }
            final details = event['details'];
            return details is Map &&
                details['reason'] == 'event_claim_ownership_lost_before_show';
          }).toList();
          if (scenario.leg == _DirectFinalBarrierLeg.visibilityUnknown) {
            expect(
              showsAfter,
              showsBefore + 1,
              reason: 'unknown visibility must fail toward one notification',
            );
            expect(ownershipSuppressions, isEmpty);
            expect(
              validatedPeers,
              everyElement(scenario.peerId),
              reason: 'both pre/post-show reads retain the exact peer',
            );
            expect(validatedPeers, hasLength(2));
          } else {
            expect(showsAfter, showsBefore, reason: scenario.suffix);
            expect(
              ownershipSuppressions,
              hasLength(1),
              reason: '${scenario.suffix} exact suppression disposition',
            );
            expect(validatedPeers, hasLength(1));

            final reacquiredEvent = await coordinator.acquireMessageEventClaim(
              type: scenario.claimType,
              eventIdentity: scenario.eventIdentity,
            );
            expect(
              reacquiredEvent.disposition,
              DurableNotificationClaimDisposition.acquired,
              reason: '${scenario.suffix} event owner must roll back',
            );
            final reacquiredTone = await coordinator.reserveTone(
              scenario.toneKey,
            );
            expect(
              reacquiredTone,
              isNotNull,
              reason: '${scenario.suffix} tone owner must roll back',
            );
            expect(await reacquiredEvent.claim!.release(), isTrue);
            expect(await reacquiredTone!.release(), isTrue);
          }

          if (ownerDirectory.existsSync()) {
            ownerDirectory.deleteSync(recursive: true);
          }
        }
      },
    );

    test(
      'TC-372-07b authenticated background effect authorizes before native entry',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'hello',
            payload: 'peer-authorized',
            resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
              kind: ConversationNotificationContentKind.message,
              canonicalEventId: 'message-authorized',
            ),
          ),
        );

        final sqlPath =
            '${Directory.systemTemp.path}/background-effect-authority-${DateTime.now().microsecondsSinceEpoch}.db';
        final db = await databaseFactoryFfi.openDatabase(sqlPath);
        addTearDown(() async {
          await db.close();
          await databaseFactoryFfi.deleteDatabase(sqlPath);
        });
        await db.execute('''
          CREATE TABLE direct_notification_display_outbox (
            event_id TEXT NOT NULL,
            event_kind TEXT NOT NULL,
            peer_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            actor_peer_id TEXT NOT NULL,
            event_timestamp TEXT NOT NULL,
            reaction_id TEXT,
            reaction_action TEXT,
            reaction_tombstone INTEGER,
            readiness TEXT NOT NULL,
            revision INTEGER NOT NULL,
            retry_count INTEGER NOT NULL,
            last_error_code TEXT,
            last_attempt_at TEXT,
            next_attempt_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(peer_id, event_kind, event_id)
          )
        ''');
        const sqlEntry = DirectNotificationDisplayOutboxEntry.message(
          eventId: 'message-authorized',
          peerId: 'peer-authorized',
          messageId: 'message-authorized',
          actorPeerId: 'peer-authorized',
          eventTimestamp: '2026-08-16T12:00:00.000Z',
          readiness: DirectNotificationDisplayOutboxReadiness.ready,
          revision: 2,
          createdAt: '2026-08-16T12:00:00.000Z',
          updatedAt: '2026-08-16T12:00:00.000Z',
        );
        await db.insert('direct_notification_display_outbox', sqlEntry.toMap());

        final registryDirectory = Directory.systemTemp.createTempSync(
          'background-effect-authority-registry-',
        );
        addTearDown(() {
          if (registryDirectory.existsSync()) {
            registryDirectory.deleteSync(recursive: true);
          }
        });
        final registry = DurableConversationNotificationIdRegistry(
          directory: registryDirectory,
        );
        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async => registry,
        );
        const binding =
            'v1:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
        await LocalNotificationLedgerStore(
          directory: registryDirectory,
        ).initializeOrRebind(currentOpaqueBinding: binding);

        final order = <String>[];
        debugSetBackgroundDurableLocalNotificationEffectResolver(
          ({required routeTarget, required fallback, required metadata}) =>
              resolveBackgroundDurableLocalNotificationEffectInDatabase(
                db,
                routeTarget: routeTarget,
                fallback: fallback,
                metadata: metadata,
                currentOpaqueBinding: binding,
                physicalPeerId: 'physical-authorized',
                readFinalCanonicalDisposition: () async {
                  order.add('canonical');
                  final current = await db.query(
                    'direct_notification_display_outbox',
                    where: 'event_id = ?',
                    whereArgs: const <Object?>['message-authorized'],
                  );
                  expect(current.single['revision'], 2);
                  return DurableLocalNotificationCanonicalDisposition.eligible;
                },
              ),
        );
        debugSetBackgroundAppVisibilityResolver(
          () async => _OrderedBackgroundVisibility(order),
        );
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              if (call.method == 'show') order.add('native');
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-authorized',
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-authorized',
              'message_id': 'message-authorized',
            },
          ),
        );

        expect(order, <String>['canonical', 'visibility', 'native']);
        expect(log.where((call) => call.method == 'show'), hasLength(1));
        final shownEvent = events.singleWhere(
          (event) => event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
        );
        final shownBytes = jsonEncode(shownEvent);
        expect(shownBytes, isNot(contains('provider-authorized')));
        expect(shownBytes, isNot(contains('peer-authorized')));
        expect(shownBytes, isNot(contains('message-authorized')));
        expect((shownEvent['details'] as Map)['durable'], isTrue);
        expect(
          await db.query('direct_notification_display_outbox'),
          hasLength(1),
          reason: 'the read-only background owner retains SQL custody',
        );
        final correlation = tryComputeNotificationCompletedOutcomeCorrelation(
          physicalPeerId: 'physical-authorized',
          producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
          eventKey: 'message-authorized',
        )!;
        final envelope = await LocalNotificationLedgerStore(
          directory: registryDirectory,
        ).read(currentOpaqueBinding: binding);
        final record = envelope!.records[correlation]!;
        expect(
          record.presentationOwner,
          LocalNotificationPresentationOwner.androidPushService,
        );
        expect(record.effectPhase, LocalNotificationEffectPhase.effectTerminal);
        expect(record.settledAtUtc, isNull);
      },
    );

    test(
      'locked dual delivery keeps background authority across a live claim-pending retry',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});

        const groupId = 'group-dual-delivery';
        const messageId = 'message-dual-delivery';
        const expected = GroupNotificationDisplayOutboxEntry.message(
          eventId: messageId,
          groupId: groupId,
          messageId: messageId,
          actorPeerId: 'peer-alice',
          eventTimestamp: '2026-08-21T13:58:27.011136Z',
          readiness: GroupNotificationDisplayOutboxReadiness.ready,
          revision: 2,
          createdAt: '2026-08-21T13:58:28.774121Z',
          updatedAt: '2026-08-21T13:58:28.774121Z',
        );
        final db = await openEmptyBackgroundDisplayOutboxDatabase(
          tag: 'dual-delivery',
          group: true,
        );
        await db.execute('''
          CREATE TABLE group_messages (
            id TEXT PRIMARY KEY,
            logical_delivery_id TEXT
          )
        ''');
        await db.insert('group_messages', const <String, Object?>{
          'id': messageId,
          'logical_delivery_id': messageId,
        });
        await db.insert('group_notification_display_outbox', expected.toMap());

        final finalReadEntered = Completer<void>();
        final retryRecorded = Completer<void>();
        debugSetBackgroundDurableLocalNotificationEffectResolver(
          ({
            required routeTarget,
            required fallback,
            required metadata,
          }) => resolveBackgroundDurableLocalNotificationEffectInDatabase(
            db,
            routeTarget: routeTarget,
            fallback: fallback,
            metadata: metadata,
            currentOpaqueBinding: 'v1:${'b' * 64}',
            physicalPeerId: 'physical-dual-delivery',
            readFinalCanonicalDisposition: () async {
              if (!finalReadEntered.isCompleted) {
                finalReadEntered.complete();
              }
              await retryRecorded.future;
              final row = await dbLoadGroupNotificationDisplayOutboxEntry(
                db,
                messageId,
              );
              final current = GroupNotificationDisplayOutboxEntry.fromMap(row!);
              return backgroundGroupDisplayAuthorityRemainsCurrentForFinalRead(
                    expected: expected,
                    current: current,
                  )
                  ? DurableLocalNotificationCanonicalDisposition.eligible
                  : DurableLocalNotificationCanonicalDisposition
                        .retryableUnknown;
            },
          ),
        );
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Team',
            body: 'Alice: Photo',
            payload: 'group:$groupId|message:$messageId',
            groupComparand: BackgroundGroupMessageNotificationComparand(
              groupId: groupId,
              messageId: messageId,
              senderPeerId: 'peer-alice',
            ),
            resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
              kind: ConversationNotificationContentKind.message,
              canonicalEventId: messageId,
            ),
          ),
        );

        final ownerDirectory = Directory.systemTemp.createTempSync(
          'background-dual-delivery-owner-',
        );
        final coordinator = DurableNotificationToneLease(
          directory: ownerDirectory,
          pendingClaimWait: Duration.zero,
          pendingToneReservationWait: Duration.zero,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        addTearDown(() {
          if (ownerDirectory.existsSync()) {
            ownerDirectory.deleteSync(recursive: true);
          }
        });

        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        final handling = firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-dual-delivery',
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': groupId,
              'message_id': messageId,
            },
          ),
        );
        await finalReadEntered.future.timeout(const Duration(seconds: 2));
        final advanced =
            await dbRecordGroupNotificationDisplayOutboxRetryIfExact(
              db,
              eventId: messageId,
              expectedRevision: expected.revision,
              lastErrorCode:
                  GroupNotificationDisplayOutboxErrorCode.claimPending,
              lastAttemptAt: '2026-08-21T13:58:31.720000Z',
              nextAttemptAt: '2026-08-21T13:59:36.720000Z',
              updatedAt: '2026-08-21T13:58:31.720000Z',
            );
        expect(advanced, isTrue);
        retryRecorded.complete();
        await handling;

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          events.where(
            (event) => event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
          ),
          hasLength(1),
        );
        expect(
          events.where((event) => event['event'] == 'NOTIFICATION_DEFERRED'),
          isEmpty,
        );
        final duplicate = await coordinator.acquireMessageEventClaim(
          type: 'group_message',
          eventIdentity: messageId,
        );
        expect(
          duplicate.disposition,
          DurableNotificationClaimDisposition.committedOrUnavailable,
        );
      },
    );

    // ---------------------------------------------------------------------
    // Plan 383 (G17) — a killed app must still ALERT for an authenticated
    // typed event whose durable display-outbox authority has not been staged
    // yet. The durable seam stays intact; only its silent exits fall through
    // into the existing non-durable typed presentation lane.
    // ---------------------------------------------------------------------
    test('authenticated durable-authority deferral presents the non-durable '
        'fallback card (direct message)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      debugSetBackgroundPushNotificationDisplayEligibilityResolver(
        (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
      );
      debugSetBackgroundPushEnvelopeStager((_) async {});
      debugSetBackgroundPushNotificationResolver(
        (_) async => const BackgroundPushNotificationFallback(
          title: 'Alice',
          body: 'hello',
          payload: 'peer-fallback-direct',
          resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
            kind: ConversationNotificationContentKind.message,
            canonicalEventId: 'message-fallback-direct',
          ),
        ),
      );
      final db = await openEmptyBackgroundDisplayOutboxDatabase(
        tag: 'direct-message',
        direct: true,
      );
      useRealEmptyOutboxDurableEffectResolver(db);
      final registry = await useIsolatedBackgroundNotificationRegistry(
        'direct-message',
      );
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'initialize') return true;
            return null;
          });

      await firebaseMessagingBackgroundHandler(
        const RemoteMessage(
          messageId: 'provider-fallback-direct',
          data: <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-fallback-direct',
            'message_id': 'message-fallback-direct',
          },
        ),
      );

      final shows = log.where((call) => call.method == 'show').toList();
      expect(shows, hasLength(1));
      final showArguments = shows.single.arguments as Map;
      expect(showArguments['title'], 'Alice');
      expect(showArguments['body'], 'hello');
      final platformSpecifics = showArguments['platformSpecifics'] as Map;
      expect(
        platformSpecifics['playSound'],
        isTrue,
        reason: 'the fallback card must alert, never post silently',
      );
      expect(
        platformSpecifics['autoCancel'],
        isFalse,
        reason: 'managed content metadata owns retirement, not autoCancel',
      );

      final deferred = events.singleWhere(
        (event) => event['event'] == 'PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED',
      );
      expect(
        deferred['details'],
        containsPair('reason', 'exact_sql_authority_unavailable'),
      );
      expect(
        deferred['details'],
        containsPair('presentation', 'nondurable_fallback'),
      );
      final shown = events.singleWhere(
        (event) => event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
      );
      expect(
        (shown['details'] as Map).containsKey('durable'),
        isFalse,
        reason: 'a fallback presentation must never claim durable authority',
      );

      final notificationId = await registry.lookup('peer-fallback-direct');
      expect(notificationId, isNotNull);
      final metadata = await registry.lookupContentMetadata(
        conversationKey: 'peer-fallback-direct',
        notificationId: notificationId!,
      );
      expect(
        metadata?.kind,
        ConversationNotificationContentKind.message,
        reason: 'the shown card stays managed typed content',
      );
      expect(metadata?.eventIdentity, 'message-fallback-direct');
      expect(metadata?.generation, isNotEmpty);

      expect(
        await readBackgroundFallbackLedgerRecords(registry),
        isEmpty,
        reason: 'no durable authority means no ledger record',
      );
      expect(
        await db.query('direct_notification_display_outbox'),
        isEmpty,
        reason: 'the background isolate must never stage custody rows',
      );
    });

    test('authenticated durable-authority deferral presents the non-durable '
        'fallback card (direct reaction)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      debugSetBackgroundPushNotificationDisplayEligibilityResolver(
        (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
      );
      debugSetBackgroundPushEnvelopeStager((_) async {});
      debugSetBackgroundPushNotificationResolver(
        (_) async => const BackgroundPushNotificationFallback(
          title: 'Reaction',
          body: 'Alice reacted 👍 to your message',
          payload: 'peer-fallback-reaction|message:target-fallback-reaction',
          resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
            kind: ConversationNotificationContentKind.reaction,
            canonicalEventId: 'reaction-fallback-direct',
          ),
        ),
      );
      final db = await openEmptyBackgroundDisplayOutboxDatabase(
        tag: 'direct-reaction',
        direct: true,
      );
      useRealEmptyOutboxDurableEffectResolver(db);
      final registry = await useIsolatedBackgroundNotificationRegistry(
        'direct-reaction',
      );
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'initialize') return true;
            return null;
          });

      await firebaseMessagingBackgroundHandler(
        const RemoteMessage(
          messageId: 'provider-fallback-direct-reaction',
          data: <String, dynamic>{
            'type': 'message_reaction',
            'sender_id': 'peer-fallback-reaction',
            'target_message_id': 'target-fallback-reaction',
            'action': 'add',
            'event_id': 'reaction-fallback-direct',
            'reaction_id': 'reaction-fallback-direct',
          },
        ),
      );

      final shows = log.where((call) => call.method == 'show').toList();
      expect(shows, hasLength(1));
      final showArguments = shows.single.arguments as Map;
      expect(
        showArguments['title'],
        'Reaction',
        reason: 'the resolved reaction preview copy owns the fallback card',
      );
      expect(showArguments['body'], 'Alice reacted 👍 to your message');

      final deferred = events.singleWhere(
        (event) => event['event'] == 'PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED',
      );
      expect(
        deferred['details'],
        containsPair('presentation', 'nondurable_fallback'),
      );
      final notificationId = await registry.lookup('peer-fallback-reaction');
      expect(notificationId, isNotNull);
      final metadata = await registry.lookupContentMetadata(
        conversationKey: 'peer-fallback-reaction',
        notificationId: notificationId!,
      );
      expect(metadata?.kind, ConversationNotificationContentKind.reaction);
      expect(
        metadata?.eventIdentity,
        boundedReactionEventIdentity('reaction-fallback-direct'),
      );
      expect(await readBackgroundFallbackLedgerRecords(registry), isEmpty);
    });

    test('authenticated durable-authority deferral presents the non-durable '
        'fallback card (group reaction)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      debugSetBackgroundPushNotificationDisplayEligibilityResolver(
        (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
      );
      debugSetBackgroundPushEnvelopeStager((_) async {});
      debugSetBackgroundPushNotificationResolver(
        (_) async => BackgroundPushNotificationFallback(
          title: 'Team Chat',
          body: 'Alice reacted 👍 to your message',
          payload: 'group:group-fallback-reaction|message:target-fallback',
          groupComparand: BackgroundGroupReactionNotificationComparand(
            groupId: 'group-fallback-reaction',
            reactionId: 'reaction-state-fallback',
            messageId: 'target-fallback',
            senderPeerId: 'peer-alice',
            timestamp: '2026-08-18T09:00:00.000Z',
            // The comparand alias MUST equal the bounded identity the
            // handler mints, or the post-show switch retires the card it
            // just published.
            notificationEventIdentity: boundedReactionEventIdentity(
              'group-reaction-fallback',
            ),
          ),
          resolvedEventIdentity:
              const ResolvedPushEventIdentity.authenticatedInner(
                kind: ConversationNotificationContentKind.reaction,
                canonicalEventId: 'group-reaction-fallback',
              ),
        ),
      );
      final db = await openEmptyBackgroundDisplayOutboxDatabase(
        tag: 'group-reaction',
        group: true,
      );
      useRealEmptyOutboxDurableEffectResolver(db);
      final registry = await useIsolatedBackgroundNotificationRegistry(
        'group-reaction',
      );
      var postShowValidations = 0;
      debugSetBackgroundGroupNotificationPostShowValidator((_) async {
        postShowValidations++;
        return BackgroundGroupNotificationPostShowDecision.keep;
      });
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'initialize') return true;
            return null;
          });

      await firebaseMessagingBackgroundHandler(
        const RemoteMessage(
          messageId: 'provider-fallback-group-reaction',
          data: <String, dynamic>{
            'type': 'group_reaction',
            'groupId': 'group-fallback-reaction',
            'event_id': 'group-reaction-fallback',
            'reaction_id': 'group-reaction-fallback',
            'reactor_peer_id': 'peer-alice',
            'target_message_id': 'target-fallback',
            'action': 'add',
          },
        ),
      );

      final shows = log.where((call) => call.method == 'show').toList();
      expect(shows, hasLength(1));
      expect(
        (shows.single.arguments as Map)['body'],
        'Alice reacted 👍 to your message',
      );
      final deferred = events.singleWhere(
        (event) => event['event'] == 'PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED',
      );
      expect(
        deferred['details'],
        containsPair('reason', 'exact_sql_authority_unavailable'),
      );
      expect(
        deferred['details'],
        containsPair('presentation', 'nondurable_fallback'),
      );
      expect(
        postShowValidations,
        2,
        reason:
            'a matching comparand alias must reach both the final native-entry '
            'barrier and the post-show race fence',
      );
      expect(
        events.where(
          (event) =>
              event['event'] == 'PUSH_BACKGROUND_GROUP_POST_SHOW_RETIRED',
        ),
        isEmpty,
        reason: 'the freshly shown group card must not flash-retire',
      );
      expect(
        log
            .where((call) => call.method == 'show' || call.method == 'cancel')
            .map((call) => call.method),
        <String>['show'],
        reason:
            'a keep decision updates in place and must never retire the prior '
            'card before the replacement is accepted',
      );
      final notificationId = await registry.lookup(
        'group:group-fallback-reaction',
      );
      expect(notificationId, isNotNull);
      final metadata = await registry.lookupContentMetadata(
        conversationKey: 'group:group-fallback-reaction',
        notificationId: notificationId!,
      );
      expect(
        metadata?.eventIdentity,
        boundedReactionEventIdentity('group-reaction-fallback'),
      );
      expect(await readBackgroundFallbackLedgerRecords(registry), isEmpty);
      expect(
        await db.query('group_notification_display_outbox'),
        isEmpty,
        reason: 'the background isolate must never stage custody rows',
      );
    });

    test(
      'authority read failure still presents the non-durable fallback card',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'hello',
            payload: 'peer-fallback-read-failed',
            resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
              kind: ConversationNotificationContentKind.message,
              canonicalEventId: 'message-fallback-read-failed',
            ),
          ),
        );
        debugSetBackgroundDurableLocalNotificationEffectResolver(({
          required routeTarget,
          required fallback,
          required metadata,
        }) async {
          throw StateError('authority read failed');
        });
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-fallback-read-failed',
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-fallback-read-failed',
              'message_id': 'message-fallback-read-failed',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        final deferred = events.singleWhere(
          (event) =>
              event['event'] == 'PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED',
        );
        expect(
          deferred['details'],
          containsPair('reason', 'authority_read_failed'),
        );
        expect(deferred['details'], containsPair('errorType', 'StateError'));
        expect(
          deferred['details'],
          containsPair('presentation', 'nondurable_fallback'),
        );
        final shown = events.singleWhere(
          (event) => event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
        );
        expect((shown['details'] as Map).containsKey('durable'), isFalse);
      },
    );

    test(
      'invalid durable generation still presents the non-durable fallback card',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'hello',
            payload: 'peer-fallback-generation',
            resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
              kind: ConversationNotificationContentKind.message,
              canonicalEventId: 'message-fallback-generation',
            ),
          ),
        );
        debugSetBackgroundDurableLocalNotificationEffectResolver(({
          required routeTarget,
          required fallback,
          required metadata,
        }) async {
          // A correlation that fails the lowercase-digest contract yields a
          // null content generation, so no durable card can be minted.
          return DurableLocalNotificationEffectContext(
            currentOpaqueBinding: backgroundFallbackLaneBinding,
            eventCorrelation: 'NOT-A-LOWERCASE-DIGEST',
            conversationDigest: 'a' * 64,
            producerKind: LocalNotificationProducerKind.directMessage,
            sourceCustody: LocalNotificationSourceCustody.sqlReady,
            presentationOwner:
                LocalNotificationPresentationOwner.androidPushService,
            readFinalCanonicalDisposition: () async =>
                DurableLocalNotificationCanonicalDisposition.eligible,
          );
        });
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-fallback-generation',
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-fallback-generation',
              'message_id': 'message-fallback-generation',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        final deferred = events.singleWhere(
          (event) =>
              event['event'] == 'PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED',
        );
        expect(
          deferred['details'],
          containsPair('reason', 'generation_invalid'),
        );
        expect(
          deferred['details'],
          containsPair('presentation', 'nondurable_fallback'),
        );
        final shown = events.singleWhere(
          (event) => event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
        );
        expect((shown['details'] as Map).containsKey('durable'), isFalse);
      },
    );

    // Coverage add beyond the plan's Test Contract (the plan dropped TC-383-03
    // as over-engineering). An independent adversarial pass showed that with no
    // UNMUTED group-MESSAGE row a two-axis conditional
    // (`kind == group && contentKind == message`) survives every other row —
    // and group text is the highest-volume killed-app typed event. The seam is
    // kind-agnostic, so this is cheap insurance, not new behavior.
    test('authenticated durable-authority deferral presents the non-durable '
        'fallback card (group message)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      debugSetBackgroundPushNotificationDisplayEligibilityResolver(
        (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
      );
      debugSetBackgroundPushEnvelopeStager((_) async {});
      debugSetBackgroundPushNotificationResolver(
        (_) async => const BackgroundPushNotificationFallback(
          title: 'Team Chat',
          body: 'Alice: hello',
          payload:
              'group:group-fallback-message|message:message-fallback-group',
          groupComparand: BackgroundGroupMessageNotificationComparand(
            groupId: 'group-fallback-message',
            messageId: 'message-fallback-group',
            senderPeerId: 'peer-alice',
          ),
          resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
            kind: ConversationNotificationContentKind.message,
            canonicalEventId: 'message-fallback-group',
          ),
        ),
      );
      final db = await openEmptyBackgroundDisplayOutboxDatabase(
        tag: 'group-message',
        group: true,
      );
      useRealEmptyOutboxDurableEffectResolver(db);
      final registry = await useIsolatedBackgroundNotificationRegistry(
        'group-message',
      );
      var postShowValidations = 0;
      debugSetBackgroundGroupNotificationPostShowValidator((_) async {
        postShowValidations++;
        return BackgroundGroupNotificationPostShowDecision.keep;
      });
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'initialize') return true;
            return null;
          });

      await firebaseMessagingBackgroundHandler(
        const RemoteMessage(
          messageId: 'provider-fallback-group-message',
          data: <String, dynamic>{
            'type': 'group_message',
            'groupId': 'group-fallback-message',
            'message_id': 'message-fallback-group',
          },
        ),
      );

      final shows = log.where((call) => call.method == 'show').toList();
      expect(shows, hasLength(1));
      final showArguments = shows.single.arguments as Map;
      expect(showArguments['body'], 'Alice: hello');
      expect(
        (showArguments['platformSpecifics'] as Map)['playSound'],
        isTrue,
        reason: 'group text at a killed app must alert, not post silently',
      );
      final deferred = events.singleWhere(
        (event) => event['event'] == 'PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED',
      );
      expect(
        deferred['details'],
        containsPair('reason', 'exact_sql_authority_unavailable'),
      );
      expect(
        deferred['details'],
        containsPair('presentation', 'nondurable_fallback'),
      );
      expect(
        postShowValidations,
        2,
        reason:
            'the message comparand must match both the final native-entry '
            'barrier and the post-show race fence',
      );
      expect(
        events.where(
          (event) =>
              event['event'] == 'PUSH_BACKGROUND_GROUP_POST_SHOW_RETIRED',
        ),
        isEmpty,
      );
      final notificationId = await registry.lookup(
        'group:group-fallback-message',
      );
      expect(notificationId, isNotNull);
      final metadata = await registry.lookupContentMetadata(
        conversationKey: 'group:group-fallback-message',
        notificationId: notificationId!,
      );
      expect(metadata?.kind, ConversationNotificationContentKind.message);
      expect(metadata?.eventIdentity, 'message-fallback-group');
      expect(await readBackgroundFallbackLedgerRecords(registry), isEmpty);
      expect(
        await db.query('group_notification_display_outbox'),
        isEmpty,
        reason: 'the background isolate must never stage custody rows',
      );
    });

    test(
      'muted group killed-app events stay silent through the fallback lane',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (message) => resolveBackgroundPushFallbackDisplayEligibility(
            message,
            groupMessageDisplayEligibilityResolver: (_) async =>
                groupMemberMessageDisplayEligibility({
                  'type': 'chat',
                  'is_muted': 1,
                }),
          ),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundPushNotificationResolver((message) async {
          final isReaction = message.data['type'] == 'group_reaction';
          return BackgroundPushNotificationFallback(
            title: 'Team Chat',
            body: isReaction ? 'Alice reacted 👍' : 'Alice: hello',
            payload: isReaction
                ? 'group:group-fallback-muted|message:target-muted'
                : 'group:group-fallback-muted|message:message-fallback-muted',
            resolvedEventIdentity: isReaction
                ? const ResolvedPushEventIdentity.authenticatedInner(
                    kind: ConversationNotificationContentKind.reaction,
                    canonicalEventId: 'group-reaction-fallback-muted',
                  )
                : const ResolvedPushEventIdentity.authenticatedInner(
                    kind: ConversationNotificationContentKind.message,
                    canonicalEventId: 'message-fallback-muted',
                  ),
          );
        });
        final db = await openEmptyBackgroundDisplayOutboxDatabase(
          tag: 'group-muted',
          group: true,
        );
        useRealEmptyOutboxDurableEffectResolver(db);
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-fallback-muted-message',
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-fallback-muted',
              'message_id': 'message-fallback-muted',
            },
          ),
        );
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-fallback-muted-reaction',
            data: <String, dynamic>{
              'type': 'group_reaction',
              'groupId': 'group-fallback-muted',
              'event_id': 'group-reaction-fallback-muted',
              'reaction_id': 'group-reaction-fallback-muted',
              'reactor_peer_id': 'peer-alice',
              'target_message_id': 'target-muted',
              'action': 'add',
            },
          ),
        );

        expect(
          log.where((call) => call.method == 'show'),
          isEmpty,
          reason: 'a muted group is silent on every background path',
        );
        expect(
          events.where(
            (event) =>
                event['event'] == 'PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED',
          ),
          isEmpty,
          reason: 'muted events are stopped upstream of the durable seam',
        );
      },
    );

    test(
      'redelivery after a fallback presentation does not re-alert',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'hello',
            payload: 'peer-fallback-redelivery',
            resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
              kind: ConversationNotificationContentKind.message,
              canonicalEventId: 'message-fallback-redelivery',
            ),
          ),
        );
        final db = await openEmptyBackgroundDisplayOutboxDatabase(
          tag: 'redelivery',
          direct: true,
        );
        useRealEmptyOutboxDurableEffectResolver(db);
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        const message = RemoteMessage(
          messageId: 'provider-fallback-redelivery',
          data: <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-fallback-redelivery',
            'message_id': 'message-fallback-redelivery',
          },
        );
        await firebaseMessagingBackgroundHandler(message);
        await firebaseMessagingBackgroundHandler(message);

        expect(
          log.where((call) => call.method == 'show'),
          hasLength(1),
          reason: 'one audible presentation maximum per delivered event',
        );
        final suppression = events.lastWhere(
          (event) =>
              event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
        );
        expect(
          suppression['details'],
          containsPair('reason', 'recent_duplicate_background_push'),
        );
      },
    );

    test(
      'authenticated durable-authority deferral presents non-durably, defers '
      'the durable effect, and commits the claim',
      () async {
        // Plan 372 pinned this seam as SILENT. Plan 383 (G17) changes the
        // intended behavior: the durable effect is still deferred, but the
        // event must reach the user through the non-durable lane, and the
        // event claim must COMMIT so no other producer re-alerts it.
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'hello',
            payload: 'peer-deferred',
            resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
              kind: ConversationNotificationContentKind.message,
              canonicalEventId: 'message-deferred',
            ),
          ),
        );
        var authorityReads = 0;
        debugSetBackgroundDurableLocalNotificationEffectResolver(({
          required routeTarget,
          required fallback,
          required metadata,
        }) async {
          authorityReads++;
          return null;
        });
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        const message = RemoteMessage(
          messageId: 'provider-deferred',
          data: <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-deferred',
            'message_id': 'message-deferred',
          },
        );
        await firebaseMessagingBackgroundHandler(message);

        expect(authorityReads, 1);
        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          events.singleWhere(
            (event) =>
                event['event'] == 'PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED',
          )['details'],
          containsPair('presentation', 'nondurable_fallback'),
        );

        // Retire the recent-shown gate (its own dedupe authority) so the next
        // delivery must be stopped by the COMMITTED event claim alone. A
        // fall-through that still released its provisional owners would
        // re-claim here and alert a second time.
        final freshGate = RecentBackgroundNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/background-fallback-claim-gate-'
              '${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentBackgroundNotificationGate(freshGate);
        addTearDown(freshGate.clear);

        await firebaseMessagingBackgroundHandler(message);

        expect(
          log.where((call) => call.method == 'show'),
          hasLength(1),
          reason: 'the committed claim is the exact background dedupe owner',
        );
        expect(
          events.lastWhere(
            (event) =>
                event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
          )['details'],
          containsPair('reason', 'message_event_already_claimed'),
        );
      },
    );

    test(
      'authenticated background read terminalizes the durable ledger as READ',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'hello',
            payload: 'peer-background-read',
            resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
              kind: ConversationNotificationContentKind.message,
              canonicalEventId: 'message-background-read',
            ),
          ),
        );
        final registryDirectory = Directory.systemTemp.createTempSync(
          'background-read-terminal-registry-',
        );
        addTearDown(() {
          if (registryDirectory.existsSync()) {
            registryDirectory.deleteSync(recursive: true);
          }
        });
        const binding =
            'v1:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
        final registry = DurableConversationNotificationIdRegistry(
          directory: registryDirectory,
        );
        expect(
          await LocalNotificationLedgerStore(
            directory: registryDirectory,
          ).initializeOrRebind(currentOpaqueBinding: binding),
          isNotNull,
        );
        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async => registry,
        );
        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.direct,
          value: 'peer-background-read',
        )!;
        final correlation = tryComputeNotificationCompletedOutcomeCorrelation(
          physicalPeerId: 'physical-background-read',
          producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
          eventKey: 'message-background-read',
        )!;
        debugSetBackgroundDurableLocalNotificationEffectResolver(
          ({
            required routeTarget,
            required fallback,
            required metadata,
          }) async => DurableLocalNotificationEffectContext(
            currentOpaqueBinding: binding,
            eventCorrelation: correlation,
            conversationDigest: identity.digest,
            producerKind: LocalNotificationProducerKind.directMessage,
            sourceCustody: LocalNotificationSourceCustody.sqlReady,
            presentationOwner:
                LocalNotificationPresentationOwner.androidPushService,
            readFinalCanonicalDisposition: () async =>
                DurableLocalNotificationCanonicalDisposition.read,
          ),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-background-read',
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-background-read',
              'message_id': 'message-background-read',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), isEmpty);
        final envelope = await LocalNotificationLedgerStore(
          directory: registryDirectory,
        ).read(currentOpaqueBinding: binding);
        final record = envelope!.records[correlation]!;
        expect(record.readState, LocalNotificationReadState.read);
        expect(
          record.presentationState,
          LocalNotificationPresentationState.cancelled,
        );
        expect(record.effectPhase, LocalNotificationEffectPhase.effectTerminal);
      },
    );

    test(
      'durable terminal replay releases fresh provisional owners without a second native entry',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'hello',
            payload: 'peer-terminal-replay',
            resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
              kind: ConversationNotificationContentKind.message,
              canonicalEventId: 'message-terminal-replay',
            ),
          ),
        );

        final registryDirectory = Directory.systemTemp.createTempSync(
          'background-terminal-replay-registry-',
        );
        addTearDown(() {
          if (registryDirectory.existsSync()) {
            registryDirectory.deleteSync(recursive: true);
          }
        });
        final registry = DurableConversationNotificationIdRegistry(
          directory: registryDirectory,
        );
        await LocalNotificationLedgerStore(
          directory: registryDirectory,
        ).initializeOrRebind(currentOpaqueBinding: 'v1:${'b' * 64}');
        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async => registry,
        );

        final firstToneDirectory = Directory.systemTemp.createTempSync(
          'background-terminal-replay-first-tone-',
        );
        addTearDown(() {
          if (firstToneDirectory.existsSync()) {
            firstToneDirectory.deleteSync(recursive: true);
          }
        });
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => DurableNotificationToneLease(
            directory: firstToneDirectory,
            pendingClaimWait: Duration.zero,
          ),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        const message = RemoteMessage(
          messageId: 'provider-terminal-replay',
          data: <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-terminal-replay',
            'message_id': 'message-terminal-replay',
          },
        );

        await firebaseMessagingBackgroundHandler(message);
        expect(log.where((call) => call.method == 'show'), hasLength(1));

        // Model a fresh headless isolate: the file ledger survives while the
        // legacy event/tone projections start empty and are provisionally
        // acquired again before the durable terminal is replayed.
        final replayToneDirectory = Directory.systemTemp.createTempSync(
          'background-terminal-replay-second-tone-',
        );
        addTearDown(() {
          if (replayToneDirectory.existsSync()) {
            replayToneDirectory.deleteSync(recursive: true);
          }
        });
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => DurableNotificationToneLease(
            directory: replayToneDirectory,
            pendingClaimWait: Duration.zero,
          ),
        );
        debugResetRecentBackgroundNotificationGate();
        debugResetRecentRemoteNotificationGate();

        await firebaseMessagingBackgroundHandler(message);

        expect(
          log.where((call) => call.method == 'show'),
          hasLength(1),
          reason: 'EFFECT_TERMINAL replay must not re-enter native show',
        );
      },
    );

    test(
      'post-show policy flip retires only the generation just shown',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        var nativeShowCompleted = false;
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Team',
            body: 'Alice: hello',
            payload: 'group:group-fence|message:message-fence',
            groupComparand: BackgroundGroupMessageNotificationComparand(
              groupId: 'group-fence',
              messageId: 'message-fence',
              senderPeerId: 'peer-alice',
            ),
          ),
        );
        debugSetBackgroundGroupNotificationPostShowValidator((_) async {
          expect(nativeShowCompleted, isTrue);
          return BackgroundGroupNotificationPostShowDecision.retire;
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              if (call.method == 'show') nativeShowCompleted = true;
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-fence',
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-fence',
              'message_id': 'message-fence',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          log
              .where((call) => call.method == 'show' || call.method == 'cancel')
              .map((call) => call.method),
          <String>['show', 'cancel'],
        );
      },
    );

    test(
      'newer generation published during the fence survives stale retirement',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Team',
            body: 'Alice: hello',
            payload: 'group:group-fence-race|message:message-fence-race',
            groupComparand: BackgroundGroupMessageNotificationComparand(
              groupId: 'group-fence-race',
              messageId: 'message-fence-race',
              senderPeerId: 'peer-alice',
            ),
          ),
        );
        final directory = Directory.systemTemp.createTempSync(
          'background-post-show-race-',
        );
        final registry = DurableConversationNotificationIdRegistry(
          directory: directory,
        );
        final concurrentPublisherRegistry =
            DurableConversationNotificationIdRegistry(directory: directory);
        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async => registry,
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        debugSetBackgroundGroupNotificationPostShowValidator((_) async {
          final notificationId = await registry.lookup(
            'group:group-fence-race',
          );
          await concurrentPublisherRegistry.replaceContent(
            conversationKey: 'group:group-fence-race',
            notificationId: notificationId!,
            metadata: const ConversationNotificationContentMetadata(
              kind: ConversationNotificationContentKind.message,
              eventIdentity: 'newer-message',
              generation: 'newer-generation',
            ),
            replace: () async {},
          );
          return BackgroundGroupNotificationPostShowDecision.retire;
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-fence-race',
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-fence-race',
              'message_id': 'message-fence-race',
            },
          ),
        );

        final notificationId = await registry.lookup('group:group-fence-race');
        expect(
          await registry.lookupContentMetadata(
            conversationKey: 'group:group-fence-race',
            notificationId: notificationId!,
          ),
          const ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity: 'newer-message',
            generation: 'newer-generation',
          ),
        );
        expect(
          log
              .where((call) => call.method == 'show' || call.method == 'cancel')
              .map((call) => call.method),
          <String>['show'],
        );
        expect(
          events.singleWhere(
            (event) =>
                event['event'] == 'PUSH_BACKGROUND_GROUP_POST_SHOW_RETIRED',
          )['details'],
          containsPair('result', 'newer_generation_survived'),
        );
      },
    );

    test(
      'post-show read error keeps the card and commits the exact claim',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Team',
            body: 'Alice: hello',
            payload: 'group:group-fence-error|message:message-fence-error',
            groupComparand: BackgroundGroupMessageNotificationComparand(
              groupId: 'group-fence-error',
              messageId: 'message-fence-error',
              senderPeerId: 'peer-alice',
            ),
          ),
        );
        debugSetBackgroundGroupNotificationPostShowValidator(
          (_) => throw StateError('post-show database unavailable'),
        );
        final gate = RecentBackgroundNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/post-show-claim-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentBackgroundNotificationGate(gate);
        addTearDown(gate.clear);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        const first = RemoteMessage(
          messageId: 'provider-fence-error-a',
          data: <String, dynamic>{
            'type': 'group_message',
            'groupId': 'group-fence-error',
            'message_id': 'message-fence-error',
          },
        );
        const duplicateTransport = RemoteMessage(
          messageId: 'provider-fence-error-b',
          data: <String, dynamic>{
            'type': 'group_message',
            'groupId': 'group-fence-error',
            'message_id': 'message-fence-error',
          },
        );

        await firebaseMessagingBackgroundHandler(first);
        await gate.clear();
        await firebaseMessagingBackgroundHandler(duplicateTransport);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          log
              .where((call) => call.method == 'show' || call.method == 'cancel')
              .map((call) => call.method),
          <String>['show'],
        );
      },
    );

    test(
      'post-show cancellation error keeps metadata and commits exact owners',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Team',
            body: 'Alice: hello',
            payload: 'group:group-fence-cancel|message:message-fence-cancel',
            groupComparand: BackgroundGroupMessageNotificationComparand(
              groupId: 'group-fence-cancel',
              messageId: 'message-fence-cancel',
              senderPeerId: 'peer-alice',
            ),
          ),
        );
        final registryDirectory = Directory.systemTemp.createTempSync(
          'background-post-show-cancel-registry-',
        );
        final registry = DurableConversationNotificationIdRegistry(
          directory: registryDirectory,
        );
        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async => registry,
        );
        final ownerDirectory = Directory.systemTemp.createTempSync(
          'background-post-show-cancel-owners-',
        );
        final coordinator = DurableNotificationToneLease(
          directory: ownerDirectory,
          pendingClaimWait: Duration.zero,
          pendingToneReservationWait: Duration.zero,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        final claimFile = File(
          '${ownerDirectory.path}/'
          '${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'group_message', eventIdentity: 'message-fence-cancel')}',
        );
        var fenceObservedCommittedOwners = false;
        debugSetBackgroundGroupNotificationPostShowValidator((_) async {
          expect(
            jsonDecode(claimFile.readAsStringSync()),
            containsPair('state', 'committed'),
          );
          expect(
            await coordinator.reserveTone('group:group-fence-cancel'),
            isNull,
          );
          fenceObservedCommittedOwners = true;
          return BackgroundGroupNotificationPostShowDecision.retire;
        });
        addTearDown(() {
          if (registryDirectory.existsSync()) {
            registryDirectory.deleteSync(recursive: true);
          }
          if (ownerDirectory.existsSync()) {
            ownerDirectory.deleteSync(recursive: true);
          }
        });
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        var cancelAttempts = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              if (call.method == 'cancel' && ++cancelAttempts == 1) {
                throw PlatformException(code: 'synthetic_cancel_failure');
              }
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-fence-cancel',
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-fence-cancel',
              'message_id': 'message-fence-cancel',
            },
          ),
        );

        final notificationId = await registry.lookup(
          'group:group-fence-cancel',
        );
        expect(notificationId, isNotNull);
        expect(
          await registry.lookupContentMetadata(
            conversationKey: 'group:group-fence-cancel',
            notificationId: notificationId!,
          ),
          isNotNull,
        );
        expect(fenceObservedCommittedOwners, isTrue);
        expect(
          jsonDecode(claimFile.readAsStringSync()),
          containsPair('state', 'committed'),
        );
        expect(
          await coordinator.reserveTone('group:group-fence-cancel'),
          isNull,
          reason: 'the successful show must retain its committed tone window',
        );
        expect(
          log
              .where((call) => call.method == 'show' || call.method == 'cancel')
              .map((call) => call.method),
          <String>['show', 'cancel'],
        );
        final eventNames = events.map((event) => event['event']);
        expect(eventNames, contains('PUSH_BACKGROUND_GROUP_POST_SHOW_UNKNOWN'));
        expect(
          eventNames,
          isNot(contains('PUSH_BACKGROUND_NOTIFICATION_ERROR')),
        );
        expect(
          eventNames,
          isNot(contains('PUSH_BACKGROUND_MESSAGE_TONE_RELEASE_FAILED')),
        );
        expect(
          eventNames,
          isNot(contains('PUSH_BACKGROUND_MESSAGE_CLAIM_RELEASE_FAILED')),
        );
      },
    );

    test(
      'headless group message and reaction record durable shared-card ownership',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushNotificationResolver((message) async {
          final isReaction = message.data['type'] == 'group_reaction';
          return BackgroundPushNotificationFallback(
            title: 'Team Chat',
            body: isReaction ? 'Alice reacted to your message' : 'Alice: hello',
            payload: isReaction
                ? 'group:group-content-kind|message:target-message'
                : 'group:group-content-kind|message:group-message-kind',
          );
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        final directory = Directory.systemTemp.createTempSync(
          'background-content-kind-',
        );
        final registry = DurableConversationNotificationIdRegistry(
          directory: directory,
        );
        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async =>
              DurableConversationNotificationIdRegistry(directory: directory),
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-content-kind',
              'message_id': 'group-message-kind',
              'preview_unavailable': '1',
            },
          ),
        );

        final id = await registry.lookup('group:group-content-kind');
        expect(id, isNotNull);
        expect(
          await registry.lookupContentKind(
            conversationKey: 'group:group-content-kind',
            notificationId: id!,
          ),
          ConversationNotificationContentKind.message,
        );
        final firstMetadata = await registry.lookupContentMetadata(
          conversationKey: 'group:group-content-kind',
          notificationId: id,
        );
        expect(firstMetadata?.eventIdentity, 'group-message-kind');
        expect(firstMetadata?.generation, isNotEmpty);

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_reaction',
              'groupId': 'group-content-kind',
              'event_id': 'group-reaction-kind',
              'reaction_id': 'group-reaction-kind',
              'reactor_peer_id': 'peer-alice',
              'target_message_id': 'target-message',
              'action': 'add',
            },
          ),
        );

        expect(
          await registry.lookupContentKind(
            conversationKey: 'group:group-content-kind',
            notificationId: id,
          ),
          ConversationNotificationContentKind.reaction,
        );
        final reactionMetadata = await registry.lookupContentMetadata(
          conversationKey: 'group:group-content-kind',
          notificationId: id,
        );
        expect(
          reactionMetadata?.eventIdentity,
          boundedReactionEventIdentity('group-reaction-kind'),
        );
        expect(reactionMetadata?.generation, isNot(firstMetadata?.generation));

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-content-kind',
              'message_id': 'group-message-before-legacy-reaction',
              'preview_unavailable': '1',
            },
          ),
        );
        expect(
          await registry.lookupContentKind(
            conversationKey: 'group:group-content-kind',
            notificationId: id,
          ),
          ConversationNotificationContentKind.message,
        );

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'payloadType': 'group_reaction',
              'groupId': 'group-content-kind',
              'event_id': 'legacy-group-reaction-kind',
              'reaction_id': 'legacy-group-reaction-kind',
              'reactor_peer_id': 'peer-alice',
              'target_message_id': 'legacy-target-message',
              'action': 'add',
            },
          ),
        );
        expect(
          await registry.lookupContentKind(
            conversationKey: 'group:group-content-kind',
            notificationId: id,
          ),
          ConversationNotificationContentKind.reaction,
          reason: 'legacy group reaction routing must remain reaction-owned',
        );

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'payload': 'group:group-content-kind|message:legacy-message',
            },
          ),
        );
        expect(
          await registry.lookupContentKind(
            conversationKey: 'group:group-content-kind',
            notificationId: id,
          ),
          ConversationNotificationContentKind.message,
          reason: 'payload-only legacy group routes must replace stale markers',
        );
      },
    );

    test(
      'group reaction background handler uses headless group crypto and stable group card',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptGroup');
              return '''{"ok":true,"plaintext":"{\\"id\\":\\"reaction-state-1\\",\\"messageId\\":\\"message-1\\",\\"emoji\\":\\"👍\\",\\"action\\":\\"add\\",\\"senderPeerId\\":\\"peer-alice\\",\\"timestamp\\":\\"2026-07-12T09:00:00.000Z\\",\\"eventId\\":\\"transition-1\\"}"}''';
            });
        debugSetBackgroundGroupReactionLocalStateResolver((_) async {
          return BackgroundGroupReactionLocalState(
            snapshot: ConversationNotificationSnapshot(
              historyLines: const <String>[
                'oldest unread',
                'older unread',
                'middle unread',
                'newer unread',
                'newest unread',
              ],
              totalUnreadMessageCount: 17,
            ),
            previewContext: GroupReactionNotificationContext(
              groupId: 'group-team',
              groupName: 'Team Chat',
              actorPeerId: 'peer-alice',
              actorUsername: 'Alice',
              targetMessageId: 'message-1',
            ),
            groupKey: 'group-key',
            keyEpoch: 7,
            nominationVerified: true,
          );
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-group-reaction-id',
            data: {
              'type': 'group_reaction',
              'groupId': 'group-team',
              'reactor_peer_id': 'peer-alice',
              'event_id': 'transition-1',
              'target_message_id': 'message-1',
              'action': 'add',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );

        final showCall = log.singleWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(
          showArgs['id'],
          deterministicConversationNotificationId('group:group-team'),
        );
        expect(showArgs['title'], 'Team Chat');
        expect(showArgs['body'], 'Alice reacted to your message');
        final payload = decodeConversationNotificationPayload(
          showArgs['payload'] as String?,
        );
        expect(payload?.routePayload, 'group:group-team|message:message-1');
        expect(
          payload?.metadata.kind,
          ConversationNotificationContentKind.reaction,
        );
        final specifics = showArgs['platformSpecifics'] as Map;
        expect(specifics['autoCancel'], isFalse);
        expect(specifics['number'], 17);
        expect(
          (specifics['styleInformation'] as Map)['lines'],
          const <String>[
            'older unread',
            'middle unread',
            'newer unread',
            'newest unread',
            'Alice reacted to your message',
          ],
          reason:
              'the authenticated background group path must show its current reaction in expanded style',
        );
      },
    );

    test(
      'group reaction decrypt failure is shown generically then fenced by authenticated outer scope',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        var nativeShowCompleted = false;
        final fencedComparands =
            <BackgroundManagedGroupNotificationComparand>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              if (call.method == 'show') nativeShowCompleted = true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptGroup');
              return <String, Object?>{
                'ok': false,
                'errorCode': 'decrypt_failed',
              };
            });
        debugSetBackgroundGroupReactionLocalStateResolver((_) async {
          return const BackgroundGroupReactionLocalState(
            previewContext: GroupReactionNotificationContext(
              groupId: 'group-team-fallback',
              groupName: 'Team Chat',
              actorPeerId: 'peer-alice',
              actorUsername: 'Alice',
              targetMessageId: 'message-fallback',
            ),
            groupKey: 'group-key',
            keyEpoch: 7,
            nominationVerified: true,
          );
        });
        debugSetBackgroundGroupNotificationPostShowValidator((comparand) async {
          expect(nativeShowCompleted, isTrue);
          fencedComparands.add(comparand);
          return BackgroundGroupNotificationPostShowDecision.retire;
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-group-reaction-fallback',
            data: <String, dynamic>{
              'type': 'group_reaction',
              'groupId': 'group-team-fallback',
              'reactor_peer_id': 'peer-alice',
              'event_id': 'transition-fallback',
              'target_message_id': 'message-fallback',
              'action': 'add',
              'keyEpoch': '7',
              'ciphertext': 'transiently-unavailable',
              'nonce': 'nonce',
            },
          ),
        );

        final showCall = log.singleWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(showArgs['title'], 'Team Chat');
        expect(showArgs['body'], 'Alice reacted to your message');
        final comparand =
            fencedComparands.single
                as BackgroundProvisionalGroupReactionNotificationComparand;
        expect(comparand.groupId, 'group-team-fallback');
        expect(comparand.messageId, 'message-fallback');
        expect(comparand.senderPeerId, 'peer-alice');
        expect(
          comparand.notificationEventIdentity,
          boundedReactionEventIdentity('transition-fallback'),
        );
        expect(log.where((call) => call.method == 'cancel'), hasLength(1));
      },
    );

    test(
      'group reaction parity mismatch is suppressed before event claim and display',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptGroup');
              return '''{"ok":true,"plaintext":"{\\"id\\":\\"reaction-state-1\\",\\"messageId\\":\\"attacker-target\\",\\"emoji\\":\\"👍\\",\\"action\\":\\"add\\",\\"senderPeerId\\":\\"peer-alice\\",\\"timestamp\\":\\"2026-07-12T09:00:00.000Z\\",\\"eventId\\":\\"transition-parity\\"}"}''';
            });
        debugSetBackgroundGroupReactionLocalStateResolver((_) async {
          return const BackgroundGroupReactionLocalState(
            previewContext: GroupReactionNotificationContext(
              groupId: 'group-team',
              groupName: 'Team Chat',
              actorPeerId: 'peer-alice',
              actorUsername: 'Alice',
              targetMessageId: 'message-1',
            ),
            groupKey: 'group-key',
            keyEpoch: 7,
            nominationVerified: true,
          );
        });
        final directory = Directory.systemTemp.createTempSync(
          'background-parity-claim-',
        );
        final coordinator = DurableNotificationToneLease(directory: directory);
        debugSetBackgroundReactionNotificationCoordinatorResolver(
          () async => coordinator,
        );
        final fencedComparands =
            <BackgroundManagedGroupNotificationComparand>[];
        debugSetBackgroundGroupNotificationPostShowValidator((comparand) async {
          fencedComparands.add(comparand);
          return BackgroundGroupNotificationPostShowDecision.keep;
        });
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: {
              'type': 'group_reaction',
              'groupId': 'group-team',
              'reactor_peer_id': 'peer-alice',
              'event_id': 'transition-parity',
              'target_message_id': 'message-1',
              'action': 'add',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), isEmpty);
        expect(fencedComparands, isEmpty);
        expect(
          await coordinator.claimEvent(
            boundedReactionEventIdentity('transition-parity'),
          ),
          isTrue,
          reason: 'invalid plaintext must not poison the durable event claim',
        );
      },
    );

    test(
      'reaction background handler uses headless crypto and trusted actor copy',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptMessage');
              return '''{"ok":true,"plaintext":"{\\"id\\":\\"reaction-1\\",\\"messageId\\":\\"message-1\\",\\"emoji\\":\\"👍\\",\\"action\\":\\"add\\",\\"senderPeerId\\":\\"peer-alice\\",\\"timestamp\\":\\"2026-07-12T09:00:00.000Z\\"}"}''';
            });
        debugSetBackgroundDirectReactionLocalStateResolver((_) async {
          return const BackgroundDirectReactionLocalState(
            previewContext: DirectReactionNotificationContext(
              actorPeerId: 'peer-alice',
              actorUsername: 'Alice',
              targetMessageId: 'message-1',
            ),
            mlKemSecretKey: 'recipient-secret',
          );
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-id',
            data: {
              'type': 'message_reaction',
              'sender_id': 'peer-alice',
              'event_id': 'reaction-1',
              'target_message_id': 'message-1',
              'action': 'add',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );

        final showCall = log.singleWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(showArgs['title'], 'Alice');
        expect(showArgs['body'], 'Reacted 👍 to your message');
        final payload = decodeConversationNotificationPayload(
          showArgs['payload'] as String?,
        );
        expect(payload?.routePayload, 'peer-alice');
        expect(
          payload?.metadata.kind,
          ConversationNotificationContentKind.reaction,
        );
      },
    );

    test(
      'direct reaction outer versus authenticated-inner mismatch never claims or shows',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushEnvelopeStager((_) async {});
        debugSetBackgroundDirectReactionLocalStateResolver(
          (message) async => _eligibleDirectReactionState(message),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptMessage');
              return '''{"ok":true,"plaintext":"{\\"id\\":\\"reaction-authenticated-inner\\",\\"messageId\\":\\"message-1\\",\\"emoji\\":\\"👍\\",\\"action\\":\\"add\\",\\"senderPeerId\\":\\"peer-alice\\",\\"timestamp\\":\\"2026-08-03T10:00:00.000Z\\"}"}''';
            });
        final directory = Directory.systemTemp.createTempSync(
          'background-direct-reaction-parity-',
        );
        final coordinator = DurableNotificationToneLease(directory: directory);
        debugSetBackgroundReactionNotificationCoordinatorResolver(
          () async => coordinator,
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'message_reaction',
              'sender_id': 'peer-alice',
              'event_id': 'reaction-outer',
              'target_message_id': 'message-1',
              'action': 'add',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'direct-parity-nonce',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), isEmpty);
        expect(
          await coordinator.claimEvent(
            boundedReactionEventIdentity('reaction-outer'),
          ),
          isTrue,
          reason: 'invalid authenticated plaintext must not poison the claim',
        );
      },
    );

    test(
      'missing outer direct reaction id decrypts, promotes staged identity, and shows',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final staged = <StagedPushEnvelope>[];
        debugSetBackgroundPushEnvelopeStager((entry) async {
          staged.add(entry);
        });
        var localStateReads = 0;
        debugSetBackgroundDirectReactionLocalStateResolver((message) async {
          localStateReads++;
          return _eligibleDirectReactionState(message);
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptMessage');
              return '''{"ok":true,"plaintext":"{\\"id\\":\\"reaction-inner-only\\",\\"messageId\\":\\"message-1\\",\\"emoji\\":\\"👍\\",\\"action\\":\\"add\\",\\"senderPeerId\\":\\"peer-alice\\",\\"timestamp\\":\\"2026-08-03T10:01:00.000Z\\"}"}''';
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'message_reaction',
              'sender_id': 'peer-alice',
              'target_message_id': 'message-1',
              'action': 'add',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'direct-missing-id-nonce',
            },
          ),
        );

        expect(localStateReads, 2, reason: 'eligibility and final authority');
        expect(staged, hasLength(2));
        expect(staged.first.identityResolutionPending, isTrue);
        expect(staged.first.eventId, isNull);
        expect(staged.last.identityResolutionPending, isFalse);
        expect(staged.last.eventId, 'reaction-inner-only');
        final show = log.singleWhere((call) => call.method == 'show');
        final payload = decodeConversationNotificationPayload(
          (show.arguments as Map)['payload'] as String?,
        );
        expect(
          payload?.metadata.eventIdentity,
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: 'test-physical-peer',
            producerKind:
                NotificationCompletedOutcomeProducerKind.directReaction,
            eventKey: 'reaction-inner-only',
          ),
        );
      },
    );

    test(
      'missing outer group reaction id passes local policy and shows authenticated transition',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        var localStateReads = 0;
        debugSetBackgroundGroupReactionLocalStateResolver((message) async {
          localStateReads++;
          return _eligibleGroupReactionState(message);
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptGroup');
              return '''{"ok":true,"plaintext":"{\\"id\\":\\"group-reaction-state\\",\\"messageId\\":\\"message-1\\",\\"emoji\\":\\"👍\\",\\"action\\":\\"add\\",\\"senderPeerId\\":\\"peer-alice\\",\\"timestamp\\":\\"2026-08-03T10:02:00.000Z\\",\\"eventId\\":\\"group-inner-transition\\"}"}''';
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_reaction',
              'groupId': 'group-team',
              'reactor_peer_id': 'peer-alice',
              'target_message_id': 'message-1',
              'action': 'add',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'group-missing-id-nonce',
            },
          ),
        );

        expect(localStateReads, 2, reason: 'eligibility and final authority');
        final show = log.singleWhere((call) => call.method == 'show');
        final payload = decodeConversationNotificationPayload(
          (show.arguments as Map)['payload'] as String?,
        );
        expect(
          payload?.metadata.eventIdentity,
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: 'test-physical-peer',
            producerKind:
                NotificationCompletedOutcomeProducerKind.groupReaction,
            eventKey: 'group-inner-transition',
          ),
        );
      },
    );

    test(
      'reaction allocation failure releases exact claim and tone for audible retry',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'Reacted 👍 to your message',
            payload: 'peer-allocation-retry',
          ),
        );
        final claimDirectory = Directory.systemTemp.createTempSync(
          'background-reaction-allocation-claim-',
        );
        final coordinator = DurableNotificationToneLease(
          directory: claimDirectory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundReactionNotificationCoordinatorResolver(
          () async => coordinator,
        );
        final registryDirectory = Directory.systemTemp.createTempSync(
          'background-reaction-allocation-registry-',
        );
        final registry = DurableConversationNotificationIdRegistry(
          directory: registryDirectory,
        );
        var allocationAttempts = 0;
        debugSetBackgroundConversationNotificationIdRegistryResolver(() async {
          allocationAttempts++;
          if (allocationAttempts == 1) {
            throw const NotificationIdAllocationException(
              operation: 'synthetic_allocation_failure',
              errorType: 'StateError',
            );
          }
          return registry;
        });
        addTearDown(() {
          if (claimDirectory.existsSync()) {
            claimDirectory.deleteSync(recursive: true);
          }
          if (registryDirectory.existsSync()) {
            registryDirectory.deleteSync(recursive: true);
          }
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        const message = RemoteMessage(
          data: {
            'type': 'message_reaction',
            'sender_id': 'peer-allocation-retry',
            'event_id': 'reaction-allocation-retry',
            'target_message_id': 'target-allocation-retry',
            'action': 'add',
          },
        );

        await firebaseMessagingBackgroundHandler(message);
        expect(log.where((call) => call.method == 'show'), isEmpty);
        await firebaseMessagingBackgroundHandler(message);

        final show = log.singleWhere((call) => call.method == 'show');
        final specifics = (show.arguments as Map)['platformSpecifics'] as Map;
        expect(specifics['playSound'], isTrue);
        final claimFile = File(
          '${claimDirectory.path}/'
          '${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'message_reaction', eventIdentity: boundedReactionEventIdentity('reaction-allocation-retry'))}',
        );
        expect(claimFile.readAsStringSync(), contains('"state":"committed"'));
      },
    );

    test(
      'reaction native-attempt error preserves fail-closed exact ownership',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'Reacted ❤️ to your message',
            payload: 'peer-show-retry',
          ),
        );
        final claimDirectory = Directory.systemTemp.createTempSync(
          'background-reaction-show-claim-',
        );
        final coordinator = DurableNotificationToneLease(
          directory: claimDirectory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundReactionNotificationCoordinatorResolver(
          () async => coordinator,
        );
        addTearDown(() {
          if (claimDirectory.existsSync()) {
            claimDirectory.deleteSync(recursive: true);
          }
        });
        var showAttempts = 0;
        final successfulShows = <Map>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              if (call.method == 'initialize') return true;
              if (call.method == 'show') {
                showAttempts++;
                if (showAttempts == 1) {
                  throw PlatformException(code: 'synthetic_show_failure');
                }
                successfulShows.add(call.arguments as Map);
              }
              return null;
            });
        const message = RemoteMessage(
          data: {
            'type': 'message_reaction',
            'sender_id': 'peer-show-retry',
            'event_id': 'reaction-show-retry',
            'target_message_id': 'target-show-retry',
            'action': 'add',
          },
        );
        final claimFile = File(
          '${claimDirectory.path}/'
          '${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'message_reaction', eventIdentity: boundedReactionEventIdentity('reaction-show-retry'))}',
        );

        await firebaseMessagingBackgroundHandler(message);
        expect(claimFile.existsSync(), isTrue);
        expect(
          claimFile.readAsStringSync(),
          contains('"state":"publishing"'),
          reason:
              'a plugin error after the native call was attempted cannot prove '
              'that no notification was shown',
        );
        await firebaseMessagingBackgroundHandler(message);

        expect(showAttempts, 1);
        expect(successfulShows, isEmpty);
      },
    );

    test(
      'post-show reaction commit failures retain both replacement owners',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Announcements',
            body: 'Alice reacted 👍 to your announcement',
            payload: 'group:announcement-commit|message:target-commit',
          ),
        );
        final directory = Directory.systemTemp.createTempSync(
          'background-reaction-commit-failure-',
        );
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
          pendingToneReservationWait: Duration.zero,
        );
        debugSetBackgroundReactionNotificationCoordinatorResolver(
          () async => coordinator,
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        final claimFile = File(
          '${directory.path}/'
          '${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'message_reaction', eventIdentity: boundedReactionEventIdentity('announcement-reaction-commit'))}',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              if (call.method == 'show') {
                await _replaceBackgroundPendingToken(
                  claimFile,
                  'replacement-reaction-claim',
                );
                final toneDirectory = Directory(
                  '${directory.path}/'
                  '${DurableNotificationToneLease.toneLeasesDirectoryName}',
                );
                final pendingTone = toneDirectory
                    .listSync()
                    .whereType<File>()
                    .singleWhere(
                      (file) => file.path.endsWith(
                        DurableNotificationToneLease
                            .tonePendingReservationFileSuffix,
                      ),
                    );
                await _replaceBackgroundPendingToken(
                  pendingTone,
                  'replacement-reaction-tone',
                );
              }
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: {
              'type': 'group_reaction',
              'groupId': 'announcement-commit',
              'reactor_peer_id': 'peer-announcement-admin',
              'event_id': 'announcement-reaction-commit',
              'target_message_id': 'target-commit',
              'action': 'add',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          claimFile.readAsStringSync(),
          contains('replacement-reaction-claim'),
        );
        final names = events.map((event) => event['event']);
        expect(
          names,
          containsAll(<String>[
            'PUSH_BACKGROUND_MESSAGE_TONE_COMMIT_FAILED',
            'PUSH_BACKGROUND_MESSAGE_CLAIM_COMMIT_FAILED',
          ]),
        );
        expect(
          names,
          isNot(contains('PUSH_BACKGROUND_MESSAGE_TONE_RELEASE_FAILED')),
        );
        expect(
          names,
          isNot(contains('PUSH_BACKGROUND_MESSAGE_CLAIM_RELEASE_FAILED')),
        );
      },
    );

    test(
      'reaction becoming ineligible between policy and preview stays silent',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        var localStateReads = 0;
        debugSetBackgroundDirectReactionLocalStateResolver((_) async {
          localStateReads++;
          if (localStateReads > 1) return null;
          return const BackgroundDirectReactionLocalState(
            previewContext: DirectReactionNotificationContext(
              actorPeerId: 'peer-alice',
              actorUsername: 'Alice',
              targetMessageId: 'message-1',
            ),
            mlKemSecretKey: 'recipient-secret',
          );
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-race-id',
            data: {
              'type': 'message_reaction',
              'sender_id': 'peer-alice',
              'event_id': 'reaction-race-1',
              'target_message_id': 'message-1',
              'action': 'add',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );

        expect(localStateReads, 2);
        expect(log.where((call) => call.method == 'show'), isEmpty);
      },
    );

    test(
      'real default direct handler decrypts text/media/private previews with trusted names, locales, and prior keys',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushEnvelopeStager((_) async {});
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        final cases = <Map<String, Object?>>[
          <String, Object?>{
            'id': 'direct-text-en',
            'locale': const Locale('en'),
            'text': 'Hello from encrypted text',
            'expected': 'Hello from encrypted text',
          },
          <String, Object?>{
            'id': 'direct-image-de',
            'locale': const Locale('de'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'image', 'mime': 'image/jpeg'},
            ],
            'expected': 'Foto',
          },
          <String, Object?>{
            'id': 'direct-video-ar',
            'locale': const Locale('ar'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'video', 'mime': 'video/mp4'},
            ],
            'expected': 'فيديو',
          },
          <String, Object?>{
            'id': 'direct-voice-de',
            'locale': const Locale('de'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'audio', 'mime': 'audio/aac'},
            ],
            'expected': 'Sprachnachricht',
          },
          <String, Object?>{
            'id': 'direct-private-ar',
            'locale': const Locale('ar'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'image', 'mime': 'image/jpeg'},
            ],
            'privateMedia': <String, Object?>{
              'version': 1,
              'mode': 'protected',
            },
            'expected': 'وسائط خاصة',
          },
        ];
        final byId = <String, Map<String, Object?>>{
          for (final testCase in cases) testCase['id']! as String: testCase,
        };
        final cryptoKeys = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptMessage');
              final arguments = Map<String, dynamic>.from(
                jsonDecode(call.arguments as String) as Map,
              );
              final secretKey = arguments['secretKey']! as String;
              cryptoKeys.add(secretKey);
              if (secretKey == 'current-key') {
                return jsonEncode(<String, Object?>{
                  'ok': false,
                  'errorCode': 'decrypt_failed',
                });
              }
              final id = (arguments['ciphertext']! as String).substring(
                'cipher-'.length,
              );
              final testCase = byId[id]!;
              return jsonEncode(<String, Object?>{
                'ok': true,
                'plaintext': jsonEncode(<String, Object?>{
                  'id': id,
                  'text': testCase['text'],
                  'senderPeerId': 'peer-alice',
                  'senderUsername': 'ATTACKER DECRYPTED NAME',
                  'timestamp': '2026-07-12T09:00:00.000Z',
                  if (testCase['media'] != null) 'media': testCase['media'],
                  if (testCase['privateMedia'] != null)
                    'privateMedia': testCase['privateMedia'],
                }),
              });
            });
        debugSetBackgroundDirectMessageLocalStateResolver((message) async {
          return BackgroundDirectMessageLocalState(
            previewContext: DirectMessageNotificationContext(
              senderPeerId: 'peer-alice',
              senderUsername: 'Alice from contacts DB',
              expectedMessageId: message.data['message_id'] as String?,
            ),
            mlKemSecretKeys: const <String>['current-key', 'prior-key'],
          );
        });

        for (final testCase in cases) {
          log.clear();
          cryptoKeys.clear();
          final id = testCase['id']! as String;
          debugSetBackgroundNotificationLocaleResolver(
            () => testCase['locale']! as Locale,
          );
          await firebaseMessagingBackgroundHandler(
            RemoteMessage(
              messageId: 'provider-$id',
              data: <String, dynamic>{
                'type': 'new_message',
                'sender_id': 'peer-alice',
                'message_id': id,
                'kem': 'kem-$id',
                'ciphertext': 'cipher-$id',
                'nonce': 'nonce-$id',
                'title': 'ATTACKER OUTER NAME',
              },
            ),
          );

          final show = log.singleWhere((call) => call.method == 'show');
          final arguments = show.arguments as Map;
          expect(arguments['title'], 'Alice from contacts DB', reason: id);
          expect(arguments['body'], testCase['expected'], reason: id);
          final payload = decodeConversationNotificationPayload(
            arguments['payload'] as String?,
          );
          expect(payload?.routePayload, 'peer-alice', reason: id);
          expect(
            payload?.metadata.kind,
            ConversationNotificationContentKind.message,
            reason: id,
          );
          expect(cryptoKeys, const <String>['current-key', 'prior-key']);
          expect(
            '${arguments['title']}|${arguments['body']}',
            isNot(contains('ATTACKER')),
          );
        }
      },
    );

    test(
      'real default group and announcement handler localizes every modality and trusts only DB names',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        final modalities = <Map<String, Object?>>[
          <String, Object?>{
            'name': 'text',
            'locale': const Locale('en'),
            'text': 'Encrypted hello',
            'expected': 'Encrypted hello',
          },
          <String, Object?>{
            'name': 'image',
            'locale': const Locale('de'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'image'},
            ],
            'expected': 'Foto',
          },
          <String, Object?>{
            'name': 'video',
            'locale': const Locale('ar'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'video'},
            ],
            'expected': 'فيديو',
          },
          <String, Object?>{
            'name': 'voice',
            'locale': const Locale('de'),
            'text': '',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'audio'},
            ],
            'expected': 'Sprachnachricht',
          },
          <String, Object?>{
            'name': 'private',
            'locale': const Locale('ar'),
            'text': 'SECRET private caption',
            'media': <Map<String, Object?>>[
              <String, Object?>{'mediaType': 'image'},
            ],
            'private': true,
            'expected': 'وسائط خاصة جديدة',
          },
        ];
        final cases = <Map<String, Object?>>[
          for (final kind in const <String>['group', 'announcement'])
            for (final modality in modalities)
              <String, Object?>{
                ...modality,
                'kind': kind,
                'id': '$kind-${modality['name']}',
              },
        ];
        final byId = <String, Map<String, Object?>>{
          for (final testCase in cases) testCase['id']! as String: testCase,
        };
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (MethodCall call) async {
              expect(call.method, 'decryptGroup');
              final arguments = Map<String, dynamic>.from(
                jsonDecode(call.arguments as String) as Map,
              );
              expect(arguments['groupKey'], 'group-key');
              final id = (arguments['ciphertext']! as String).substring(
                'cipher-'.length,
              );
              final testCase = byId[id]!;
              return jsonEncode(<String, Object?>{
                'ok': true,
                'plaintext': jsonEncode(<String, Object?>{
                  'groupId': testCase['kind'] == 'group'
                      ? 'group-team'
                      : 'group-announcements',
                  'messageId': id,
                  'senderId': 'peer-admin',
                  'groupName': 'ATTACKER DECRYPTED GROUP',
                  'senderUsername': 'ATTACKER DECRYPTED ACTOR',
                  'text': testCase['text'],
                  if (testCase['media'] != null) 'media': testCase['media'],
                  if (testCase['private'] == true) ...<String, Object?>{
                    'mediaPolicyVersion': 1,
                    'mediaLifecycle': 'viewOnce',
                    'mediaDurationSeconds': null,
                    'mediaProtected': true,
                  },
                }),
              });
            });
        debugSetBackgroundGroupMessageLocalStateResolver((message) async {
          final groupId = message.data['groupId']! as String;
          return BackgroundGroupMessageLocalState(
            previewContext: GroupMessageNotificationContext(
              groupId: groupId,
              groupName: groupId == 'group-team'
                  ? 'Team from groups DB'
                  : 'Announcements from groups DB',
              localPeerId: 'peer-local',
              senderPeerId: 'peer-admin',
              senderTransportPeerId: 'transport-admin-phone',
              senderUsername: 'Admin from members DB',
              expectedMessageId: message.data['message_id'] as String?,
            ),
            groupKey: 'group-key',
            keyEpoch: 7,
          );
        });

        for (final testCase in cases) {
          log.clear();
          final id = testCase['id']! as String;
          final groupId = testCase['kind'] == 'group'
              ? 'group-team'
              : 'group-announcements';
          debugSetBackgroundNotificationLocaleResolver(
            () => testCase['locale']! as Locale,
          );
          await firebaseMessagingBackgroundHandler(
            RemoteMessage(
              messageId: 'provider-$id',
              data: <String, dynamic>{
                'type': 'group_message',
                'groupId': groupId,
                'sender_id': 'peer-admin',
                'sender_transport_peer_id': 'transport-admin-phone',
                'message_id': id,
                'keyEpoch': '7',
                'ciphertext': 'cipher-$id',
                'nonce': 'nonce-$id',
                'title': 'ATTACKER OUTER GROUP',
              },
            ),
          );

          final show = log.singleWhere((call) => call.method == 'show');
          final arguments = show.arguments as Map;
          expect(
            arguments['title'],
            testCase['private'] == true
                ? 'Mknoon'
                : testCase['kind'] == 'group'
                ? 'Team from groups DB'
                : 'Announcements from groups DB',
            reason: id,
          );
          final expectedBody = testCase['private'] == true
              ? testCase['expected']
              : 'Admin from members DB: ${testCase['expected']}';
          expect(arguments['body'], expectedBody, reason: id);
          expect(
            '${arguments['title']}|${arguments['body']}',
            isNot(contains('ATTACKER')),
            reason: id,
          );
        }
      },
    );

    test(
      'group provider without authenticated transport stays silent',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (_) async {
              return jsonEncode(<String, Object?>{
                'ok': true,
                'plaintext': jsonEncode(<String, Object?>{
                  'groupId': 'group-team',
                  'messageId': 'group-no-provider-actor',
                  'senderId': 'peer-alice',
                  'senderUsername': 'UNTRUSTED DECRYPTED ALICE',
                  'groupName': 'UNTRUSTED DECRYPTED GROUP',
                  'text': '',
                  'media': <Map<String, Object?>>[
                    <String, Object?>{'mediaType': 'audio'},
                  ],
                }),
              });
            });
        debugSetBackgroundGroupMessageLocalStateResolver((_) async => null);
        debugSetBackgroundNotificationLocaleResolver(() => const Locale('de'));

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'message_id': 'group-no-provider-actor',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), isEmpty);
      },
    );

    test(
      'direct outage and flagged group preview unavailability stay generic while invalid/parity failures stay silent',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundNotificationLocaleResolver(() => const Locale('de'));
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        var directKeys = const <String>[];
        debugSetBackgroundDirectMessageLocalStateResolver((message) async {
          return BackgroundDirectMessageLocalState(
            previewContext: DirectMessageNotificationContext(
              senderPeerId: 'peer-alice',
              senderUsername: 'Trusted Alice',
              expectedMessageId: message.data['message_id'] as String?,
            ),
            mlKemSecretKeys: directKeys,
          );
        });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'no-key',
              'kem': 'SECRET-kem',
              'ciphertext': 'SECRET-ciphertext',
              'nonce': 'SECRET-nonce',
            },
          ),
        );
        var shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(1));
        var arguments = shows.single.arguments as Map;
        expect(arguments['title'], 'Trusted Alice');
        expect(arguments['body'], 'Nachricht');
        expect(
          '${arguments['title']}|${arguments['body']}',
          isNot(contains('SECRET')),
        );

        log.clear();
        debugSetBackgroundGroupMessageLocalStateResolver((message) async {
          return BackgroundGroupMessageLocalState(
            previewContext: GroupMessageNotificationContext(
              groupId: 'group-team',
              groupName: 'Trusted Team',
              localPeerId: 'peer-local',
              senderPeerId: 'peer-admin',
              senderTransportPeerId: 'transport-admin-phone',
              senderUsername: 'Trusted Admin',
              expectedMessageId: message.data['message_id'] as String?,
            ),
            groupKey: 'group-key',
            keyEpoch: 7,
          );
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (_) async {
              return jsonEncode(<String, Object?>{
                'ok': false,
                'errorCode': 'plugin_unavailable',
              });
            });
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'sender_transport_peer_id': 'transport-admin-phone',
              'message_id': 'group-plugin-outage',
              'keyEpoch': '7',
              'ciphertext': 'SECRET-group-ciphertext',
              'nonce': 'SECRET-group-nonce',
            },
          ),
        );
        shows = log.where((call) => call.method == 'show').toList();
        expect(shows, isEmpty, reason: 'ordinary invalid cipher fails closed');

        log.clear();
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'sender_transport_peer_id': 'transport-admin-phone',
              'message_id': 'group-preview-unavailable',
              'preview_unavailable': '1',
            },
          ),
        );
        shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(1));
        arguments = shows.single.arguments as Map;
        expect(arguments['title'], 'Trusted Team');
        expect(arguments['body'], 'Trusted Admin: Nachricht');

        log.clear();
        directKeys = const <String>['current-key'];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (_) async {
              return jsonEncode(<String, Object?>{
                'ok': true,
                'plaintext': jsonEncode(<String, Object?>{
                  'id': 'attacker-message-id',
                  'text': 'ATTACKER CONTENT',
                  'senderPeerId': 'peer-alice',
                  'senderUsername': 'ATTACKER NAME',
                  'timestamp': '2026-07-12T09:00:00.000Z',
                }),
              });
            });
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'expected-message-id',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );
        shows = log.where((call) => call.method == 'show').toList();
        expect(shows, isEmpty);

        log.clear();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cryptoChannel, (_) async {
              return jsonEncode(<String, Object?>{
                'ok': true,
                'plaintext': jsonEncode(<String, Object?>{
                  'groupId': 'group-attacker',
                  'messageId': 'group-expected-message-id',
                  'senderId': 'peer-attacker',
                  'senderUsername': 'ATTACKER NAME',
                  'text': 'ATTACKER CONTENT',
                }),
              });
            });
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'sender_transport_peer_id': 'transport-admin-phone',
              'message_id': 'group-expected-message-id',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
        );
        shows = log.where((call) => call.method == 'show').toList();
        expect(shows, isEmpty);
      },
    );

    test(
      'ordinary message becoming locally ineligible between policy and preview stays silent',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        var directReads = 0;
        debugSetBackgroundDirectMessageLocalStateResolver((message) async {
          directReads++;
          return directReads == 1
              ? BackgroundDirectMessageLocalState(
                  previewContext: DirectMessageNotificationContext(
                    senderPeerId: 'peer-alice',
                    senderUsername: 'Trusted Alice',
                    expectedMessageId: message.data['message_id'] as String?,
                  ),
                  mlKemSecretKeys: const <String>[],
                )
              : null;
        });
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'direct-state-race',
            },
          ),
        );
        expect(directReads, 2);
        expect(log.where((call) => call.method == 'show'), isEmpty);

        log.clear();
        var groupReads = 0;
        debugSetBackgroundGroupMessageLocalStateResolver((message) async {
          groupReads++;
          return groupReads == 1
              ? BackgroundGroupMessageLocalState(
                  previewContext: GroupMessageNotificationContext(
                    groupId: 'group-team',
                    groupName: 'Trusted Team',
                    localPeerId: 'peer-local',
                    senderPeerId: null,
                    senderUsername: null,
                    expectedMessageId: message.data['message_id'] as String?,
                  ),
                  groupKey: null,
                  keyEpoch: null,
                )
              : null;
        });
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'message_id': 'group-state-race',
            },
          ),
        );
        expect(groupReads, 2);
        expect(log.where((call) => call.method == 'show'), isEmpty);
      },
    );

    test(
      'committed live and NSE claims suppress exact direct and group background events',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final directory = Directory.systemTemp.createTempSync(
          'background-existing-message-claims-',
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        final liveClaim = await coordinator.claimMessageEvent(
          type: 'new_message',
          eventIdentity: 'direct-live-claimed',
        );
        expect(liveClaim, isNotNull);
        expect(await liveClaim!.commit(), isTrue);
        final claimDirectory = Directory(
          '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}',
        );
        await claimDirectory.create(recursive: true);
        final nseClaim = File(
          '${claimDirectory.path}/${DurableNotificationToneLease.messageEventClaimFileName(type: 'group_message', eventIdentity: 'group-nse-claimed')}',
        );
        await nseClaim.writeAsString('', flush: true);

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'direct-live-claimed',
            },
          ),
        );
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'message_id': 'group-nse-claimed',
              'preview_unavailable': '1',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), isEmpty);
      },
    );

    test(
      'direct and group background shows fence exact identities before show and commit after',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final directory = Directory.systemTemp.createTempSync(
          'background-exact-message-claims-',
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/background-exact-claims-remote-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);
        final pendingStatesAtShow = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              if (call.method == 'show') {
                final payload = (call.arguments as Map)['payload'] as String?;
                final routePayload =
                    decodeConversationNotificationPayload(
                      payload,
                    )?.routePayload ??
                    payload;
                final typedIdentity = routePayload == 'peer-alice'
                    ? (type: 'new_message', id: 'direct/exact id')
                    : (type: 'group_message', id: 'group/exact id');
                final file = File(
                  '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/${DurableNotificationToneLease.messageEventClaimFileName(type: typedIdentity.type, eventIdentity: typedIdentity.id)}',
                );
                pendingStatesAtShow.add(await file.readAsString());
              }
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'direct/exact id',
            },
          ),
        );
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'message_id': 'group/exact id',
              'preview_unavailable': '1',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), hasLength(2));
        expect(pendingStatesAtShow, hasLength(2));
        expect(
          pendingStatesAtShow,
          everyElement(
            allOf(contains('"state":"publishing"'), contains('token')),
          ),
        );
        for (final identity in const <({String type, String id})>[
          (type: 'new_message', id: 'direct/exact id'),
          (type: 'group_message', id: 'group/exact id'),
        ]) {
          final file = File(
            '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/${DurableNotificationToneLease.messageEventClaimFileName(type: identity.type, eventIdentity: identity.id)}',
          );
          expect(await file.readAsString(), contains('"state":"committed"'));
        }
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'peer-alice',
            messageId: 'direct/exact id',
          ),
          isFalse,
          reason: 'exact Android events use the durable claim, not legacy gate',
        );
      },
    );

    test(
      'native-attempt error keeps exact event fail-closed on redelivery',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final directory = Directory.systemTemp.createTempSync(
          'background-message-claim-redelivery-',
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        var showAttempts = 0;
        final playSound = <bool>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              if (call.method == 'show') {
                showAttempts++;
                final specifics =
                    (call.arguments as Map)['platformSpecifics'] as Map;
                playSound.add(specifics['playSound'] as bool);
                if (showAttempts == 1) {
                  throw PlatformException(code: 'show_failed');
                }
              }
              return null;
            });
        const message = RemoteMessage(
          data: <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-alice',
            'message_id': 'redelivery-after-show-error',
          },
        );
        final claimFile = File(
          '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'redelivery-after-show-error')}',
        );

        await firebaseMessagingBackgroundHandler(message);
        expect(claimFile.existsSync(), isTrue);
        expect(
          claimFile.readAsStringSync(),
          contains('"state":"publishing"'),
          reason:
              'the native call was attempted before its acknowledgement failed',
        );
        await firebaseMessagingBackgroundHandler(message);

        expect(showAttempts, 1);
        expect(playSound, const <bool>[true]);
        expect(
          await claimFile.readAsString(),
          contains('"state":"publishing"'),
        );
      },
    );

    test(
      'forced id collisions keep direct, group, and announcement cards distinct',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );
        final directory = Directory.systemTemp.createTempSync(
          'background-colliding-notification-ids-',
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final fallbacks = <String, int>{
          'peer-id-collision': 801,
          'group:discussion-id-collision': 802,
          'group:announcement-id-collision': 803,
        };
        final registry = DurableConversationNotificationIdRegistry(
          directory: directory,
          candidateGenerator: (key, probe) =>
              probe == 0 ? 800 : fallbacks[key]! + probe - 1,
        );
        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async => registry,
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        for (final message in const <RemoteMessage>[
          RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-id-collision',
              'message_id': 'direct-id-collision-message',
            },
          ),
          RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'discussion-id-collision',
              'message_id': 'group-id-collision-message',
              'preview_unavailable': '1',
            },
          ),
          RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'announcement-id-collision',
              'message_id': 'announcement-id-collision-message',
              'preview_unavailable': '1',
            },
          ),
        ]) {
          await firebaseMessagingBackgroundHandler(message);
        }

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(3));
        final ids = shows
            .map((call) => (call.arguments as Map)['id'] as int)
            .toList();
        expect(ids.toSet(), hasLength(3));
        expect(ids.first, 800);
      },
    );

    test(
      'id allocation failure releases exact claim and tone for audible redelivery',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        final coordinatorDirectory = Directory.systemTemp.createTempSync(
          'background-id-allocation-release-',
        );
        final registryDirectory = Directory.systemTemp.createTempSync(
          'background-id-allocation-retry-',
        );
        addTearDown(() {
          if (coordinatorDirectory.existsSync()) {
            coordinatorDirectory.deleteSync(recursive: true);
          }
          if (registryDirectory.existsSync()) {
            registryDirectory.deleteSync(recursive: true);
          }
        });
        final coordinator = DurableNotificationToneLease(
          directory: coordinatorDirectory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async => throw StateError('registry unavailable'),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });
        const message = RemoteMessage(
          data: <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-id-allocation-retry',
            'message_id': 'id-allocation-retry-message',
          },
        );
        final claimFile = File(
          '${coordinatorDirectory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'id-allocation-retry-message')}',
        );

        await firebaseMessagingBackgroundHandler(message);
        expect(log.where((call) => call.method == 'show'), isEmpty);
        expect(claimFile.existsSync(), isFalse);

        debugSetBackgroundConversationNotificationIdRegistryResolver(
          () async => DurableConversationNotificationIdRegistry(
            directory: registryDirectory,
          ),
        );
        await firebaseMessagingBackgroundHandler(message);

        final show = log.singleWhere((call) => call.method == 'show');
        final details = (show.arguments as Map)['platformSpecifics'] as Map;
        expect(details['playSound'], isTrue);
        expect(await claimFile.readAsString(), contains('"state":"committed"'));
      },
    );

    test(
      'claim storage failure and no-id legacy messages fail open through RecentRemote compatibility',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/background-claim-fail-open-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => throw StateError('claim storage unavailable'),
        );
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'fcm-storage-fail-open',
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-storage-fail',
              'message_id': 'storage-fail-open',
            },
          ),
        );
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'peer-storage-fail',
            messageId: 'storage-fail-open',
          ),
          isTrue,
        );

        final legacyDirectory = Directory.systemTemp.createTempSync(
          'background-legacy-message-claim-',
        );
        addTearDown(() {
          if (legacyDirectory.existsSync()) {
            legacyDirectory.deleteSync(recursive: true);
          }
        });
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => DurableNotificationToneLease(
            directory: legacyDirectory,
            pendingClaimWait: Duration.zero,
          ),
        );
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'fcm-legacy-no-id',
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-legacy-no-id',
            },
          ),
        );
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'peer-legacy-no-id',
            messageId: null,
          ),
          isTrue,
        );
        expect(log.where((call) => call.method == 'show'), hasLength(2));
      },
    );

    test(
      'tone reservation storage failure keeps an exactly claimed message audible',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final directory = Directory.systemTemp.createTempSync(
          'background-tone-reservation-failure-',
        );
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final coordinator = _ThrowingToneReservationCoordinator(directory);
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-tone-storage-fail',
              'message_id': 'tone-storage-fail-open',
            },
          ),
        );

        final show = log.singleWhere((call) => call.method == 'show');
        final specifics = (show.arguments as Map)['platformSpecifics'] as Map;
        expect(specifics['playSound'], isTrue);
        final claimFile = File(
          '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'tone-storage-fail-open')}',
        );
        expect(await claimFile.readAsString(), contains('"state":"committed"'));
      },
    );

    test('ordinary local-state policies fail closed for unsafe rows', () {
      const directData = <String, dynamic>{
        'type': 'new_message',
        'sender_id': 'peer-alice',
        'message_id': 'direct-policy',
      };
      const identity = <String, Object?>{'peer_id': 'peer-local'};
      const contact = <String, Object?>{
        'peer_id': 'peer-alice',
        'username': 'Trusted Alice',
        'is_blocked': 0,
        'is_archived': 0,
      };
      final direct = directMessageLocalStateFromRows(
        data: directData,
        identityRow: identity,
        contactRow: contact,
        currentMlKemSecretKey: 'current',
        priorMlKemSecretKeys: const <String>['prior', 'current', ' '],
      );
      expect(direct?.mlKemSecretKeys, const <String>['current', 'prior']);
      expect(direct?.previewContext.senderUsername, 'Trusted Alice');
      for (final unsafe
          in <({Map<String, dynamic> data, Map<String, Object?>? row})>[
            (
              data: directData,
              row: <String, Object?>{...contact, 'is_blocked': 1},
            ),
            (
              data: directData,
              row: <String, Object?>{...contact, 'is_archived': 1},
            ),
            (
              data: <String, dynamic>{...directData, 'sender_id': 'peer-local'},
              row: <String, Object?>{...contact, 'peer_id': 'peer-local'},
            ),
            (data: directData, row: null),
          ]) {
        expect(
          directMessageLocalStateFromRows(
            data: unsafe.data,
            identityRow: identity,
            contactRow: unsafe.row,
            currentMlKemSecretKey: 'current',
            priorMlKemSecretKeys: const <String>[],
          ),
          isNull,
        );
      }

      const groupData = <String, dynamic>{
        'type': 'group_message',
        'groupId': 'group-team',
        'sender_id': 'peer-admin',
        'sender_transport_peer_id': 'transport-admin-phone',
        'message_id': 'group-policy',
        'keyEpoch': '7',
      };
      const group = <String, Object?>{
        'id': 'group-team',
        'name': 'Trusted Team',
        'type': 'chat',
        'is_muted': 0,
        'is_archived': 0,
        'is_dissolved': 0,
        'dissolved_at': null,
      };
      const localMember = <String, Object?>{
        'group_id': 'group-team',
        'peer_id': 'peer-local',
        'role': 'reader',
        'devices_json':
            '[{"deviceId":"local-phone","transportPeerId":"transport-local-phone","deviceSigningPublicKey":"local-device-key","status":"active"}]',
      };
      const actorMember = <String, Object?>{
        'group_id': 'group-team',
        'peer_id': 'peer-admin',
        'username': 'Trusted Admin',
        'role': 'admin',
        'devices_json':
            '[{"deviceId":"admin-phone","transportPeerId":"transport-admin-phone","deviceSigningPublicKey":"admin-device-key","status":"active"}]',
      };
      const groupKey = <String, Object?>{
        'group_id': 'group-team',
        'key_generation': 7,
        'encrypted_key': 'group-key',
      };
      BackgroundGroupMessageLocalState? resolveGroup({
        Map<String, dynamic> data = groupData,
        Map<String, Object?>? groupRow = group,
        Map<String, Object?>? localRow = localMember,
        Map<String, Object?>? actorRow = actorMember,
        List<Map<String, Object?>>? members,
        Map<String, Object?>? readAcknowledgementRow,
        Map<String, Object?>? canonicalMessageRow,
      }) => groupMessageLocalStateFromRows(
        data: data,
        identityRow: identity,
        groupRow: groupRow,
        localMemberRow: localRow,
        memberRows: members ?? <Map<String, Object?>>[?localRow, ?actorRow],
        groupKeyRow: groupKey,
        readAcknowledgementRow: readAcknowledgementRow,
        canonicalMessageRow: canonicalMessageRow,
      );

      expect(resolveGroup()?.previewContext.senderUsername, 'Trusted Admin');
      expect(resolveGroup()?.previewContext.senderPeerId, 'peer-admin');
      expect(
        resolveGroup()?.previewContext.senderTransportPeerId,
        'transport-admin-phone',
        reason: 'modern account and transport identities are distinct',
      );
      expect(resolveGroup(groupRow: {...group, 'is_muted': 1}), isNull);
      expect(resolveGroup(groupRow: {...group, 'is_archived': 1}), isNull);
      expect(resolveGroup(groupRow: {...group, 'is_dissolved': 1}), isNull);
      expect(
        resolveGroup(
          groupRow: {...group, 'self_removed_at': '2026-08-02T00:00:00Z'},
        ),
        isNull,
      );
      expect(resolveGroup(localRow: null), isNull);
      expect(
        resolveGroup(
          readAcknowledgementRow: const <String, Object?>{
            'group_id': 'group-team',
            'content_kind': 'message',
            'event_identity': 'group-policy',
            'generation': 'read-generation',
            'acknowledged_at': '2026-08-03T01:00:01.000Z',
          },
        ),
        isNull,
        reason: 'an exact push-before-inbox message read suppresses pre-show',
      );
      expect(
        resolveGroup(
          readAcknowledgementRow: const <String, Object?>{
            'group_id': 'group-team',
            'content_kind': 'message',
            'event_identity': 'different-message',
          },
        ),
        isNotNull,
        reason: 'a distinct message remains eligible after the read',
      );
      expect(
        resolveGroup(
          canonicalMessageRow: const <String, Object?>{
            'id': 'group-policy',
            'group_id': 'group-team',
            'sender_peer_id': 'peer-admin',
            'is_incoming': 1,
            'read_at': '2026-08-03T01:00:01.000Z',
          },
        ),
        isNull,
        reason:
            'a read canonical message cannot alert after a crash before its first display',
      );
      expect(
        resolveGroup(
          canonicalMessageRow: const <String, Object?>{
            'id': 'different-message',
            'group_id': 'group-team',
            'sender_peer_id': 'peer-admin',
            'is_incoming': 1,
            'read_at': '2026-08-03T01:00:01.000Z',
          },
        ),
        isNotNull,
        reason: 'a distinct read message cannot suppress this push',
      );
      expect(
        resolveGroup(
          data: <String, dynamic>{
            ...groupData,
            'sender_id': 'peer-local',
            'sender_transport_peer_id': 'transport-local-phone',
          },
          actorRow: localMember,
        ),
        isNull,
      );
      expect(
        resolveGroup(actorRow: {...actorMember, 'role': 'reader'}),
        isNull,
      );
      expect(
        resolveGroup(actorRow: {...actorMember, 'role': 'unknown'}),
        isNull,
      );
      expect(resolveGroup(groupRow: {...group, 'type': 'qa'}), isNull);
      expect(
        resolveGroup(groupRow: {...group, 'type': 'announcement'}),
        isNotNull,
        reason: 'locally resolved admins may publish announcements',
      );
      expect(
        resolveGroup(
          groupRow: {...group, 'type': 'announcement'},
          actorRow: {...actorMember, 'role': 'writer'},
        ),
        isNull,
        reason: 'announcement messages require a locally known admin actor',
      );

      expect(
        resolveGroup(
          data: <String, dynamic>{
            ...groupData,
            'sender_transport_peer_id': 'transport-unknown',
          },
        ),
        isNull,
      );
      expect(
        resolveGroup(
          actorRow: <String, Object?>{
            ...actorMember,
            'devices_json':
                '[{"deviceId":"admin-phone","transportPeerId":"transport-admin-phone","deviceSigningPublicKey":"admin-device-key","status":"revoked"}]',
          },
        ),
        isNull,
      );
      expect(
        resolveGroup(
          members: <Map<String, Object?>>[
            localMember,
            actorMember,
            <String, Object?>{
              ...actorMember,
              'peer_id': 'peer-impostor',
              'devices_json':
                  '[{"deviceId":"impostor-phone","transportPeerId":"transport-admin-phone","deviceSigningPublicKey":"impostor-device-key","status":"active"}]',
            },
          ],
        ),
        isNull,
        reason: 'ambiguous active transport bindings fail closed',
      );
      expect(
        resolveGroup(
          data: <String, dynamic>{
            ...groupData,
            'sender_transport_peer_id': 'peer-legacy',
            'sender_id': 'peer-legacy',
          },
          actorRow: const <String, Object?>{
            'group_id': 'group-team',
            'peer_id': 'peer-legacy',
            'username': 'Legacy Writer',
            'role': 'writer',
            'public_key': 'legacy-signing-key',
            'devices_json': '[]',
          },
        )?.previewContext.senderPeerId,
        'peer-legacy',
      );
      expect(
        resolveGroup(
          data: <String, dynamic>{
            ...groupData,
            'sender_transport_peer_id': 'peer-legacy',
            'sender_id': 'peer-legacy',
          },
          actorRow: const <String, Object?>{
            'group_id': 'group-team',
            'peer_id': 'peer-legacy',
            'username': 'Malformed Legacy',
            'role': 'writer',
            'public_key': 'legacy-signing-key',
            'devices_json': '{malformed',
          },
        ),
        isNull,
        reason: 'malformed rosters are not legacy-empty',
      );
      expect(
        resolveGroup(
          data: <String, dynamic>{...groupData, 'sender_id': 'peer-other'},
        ),
        isNull,
        reason: 'an outer account hint cannot override the local binding',
      );
      expect(
        resolveGroup(
          data: <String, dynamic>{
            ...groupData,
            'sender_transport_peer_id': null,
          },
        ),
        isNull,
        reason: 'missing authenticated transport identity suppresses',
      );
    });

    test(
      'group reaction local state is ineligible when the group is archived',
      () {
        // Plan 309 TC-01: the archived guard exists on the push message path but
        // not on the reaction resolver — an archived group must not banner.
        const data = <String, dynamic>{
          'type': 'group_reaction',
          'groupId': 'group-team',
          'reactor_peer_id': 'peer-alice',
          'event_id': 'transition-arch-1',
          'target_message_id': 'message-1',
          'action': 'add',
          'keyEpoch': '7',
        };
        const identity = <String, Object?>{'peer_id': 'peer-bob'};
        const group = <String, Object?>{
          'id': 'group-team',
          'name': 'Team Chat',
          'type': 'chat',
          'is_muted': 0,
          'is_dissolved': 0,
          'dissolved_at': null,
        };
        final localMember = <String, Object?>{
          'group_id': 'group-team',
          'peer_id': 'peer-bob',
          'devices_json': jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'deviceId': 'bob-phone',
              'transportPeerId': 'transport-bob-phone',
              'deviceSigningPublicKey': 'bob-device-key',
              'status': 'active',
            },
          ]),
        };
        final actorMember = <String, Object?>{
          'peer_id': 'peer-alice',
          'username': 'Alice',
          'devices_json': jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'deviceId': 'alice-phone',
              'transportPeerId': 'transport-alice-phone',
              'deviceSigningPublicKey': 'alice-device-key',
              'status': 'active',
            },
          ]),
        };
        const outgoingTarget = <String, Object?>{
          'id': 'message-1',
          'group_id': 'group-team',
          'sender_peer_id': 'peer-bob',
          'is_incoming': 0,
        };
        const groupKey = <String, Object?>{
          'group_id': 'group-team',
          'key_generation': 7,
          'encrypted_key': 'group-key',
        };
        const nomination = VerifiedGroupReactionNotificationNomination(
          reactorTransportPeerId: 'transport-alice-phone',
          senderPublicKey: 'alice-device-key',
          transitionId: 'reaction-arch-1',
        );

        expect(
          groupReactionLocalStateFromRows(
            data: data,
            identityRow: identity,
            groupRow: {...group, 'is_archived': 1},
            localMemberRow: localMember,
            actorMemberRow: actorMember,
            targetMessageRow: outgoingTarget,
            groupKeyRow: groupKey,
            latestGroupKeyRow: groupKey,
            currentReactionRow: null,
            localInstallationTransportPeerId: 'transport-bob-phone',
            verifiedNomination: nomination,
          ),
          isNull,
        );
      },
    );

    test(
      'direct reaction local state is ineligible when the contact is archived',
      () {
        // Plan 309 TC-03: same guard on the 1:1 reaction resolver.
        const data = <String, dynamic>{
          'type': 'message_reaction',
          'sender_id': 'peer-alice',
          'event_id': 'reaction-arch-1',
          'target_message_id': 'message-1',
          'action': 'add',
        };
        const identity = <String, Object?>{'peer_id': 'peer-bob'};
        const contact = <String, Object?>{
          'peer_id': 'peer-alice',
          'username': 'Alice',
          'is_blocked': 0,
        };
        const outgoingTarget = <String, Object?>{
          'id': 'message-1',
          'contact_peer_id': 'peer-alice',
          'sender_peer_id': 'peer-bob',
          'is_incoming': 0,
          'deleted_at': null,
        };

        expect(
          directReactionLocalStateFromRows(
            data: data,
            identityRow: identity,
            contactRow: {...contact, 'is_archived': 1},
            targetMessageRow: outgoingTarget,
            mlKemSecretKey: 'secret',
          ),
          isNull,
        );
      },
    );

    test('reaction local-state policy requires known author and identity', () {
      const data = <String, dynamic>{
        'type': 'message_reaction',
        'sender_id': 'peer-alice',
        'event_id': 'reaction-1',
        'target_message_id': 'message-1',
        'action': 'add',
      };
      const identity = <String, Object?>{'peer_id': 'peer-bob'};
      const contact = <String, Object?>{
        'peer_id': 'peer-alice',
        'username': 'Alice',
        'is_blocked': 0,
      };
      const outgoingTarget = <String, Object?>{
        'id': 'message-1',
        'contact_peer_id': 'peer-alice',
        'sender_peer_id': 'peer-bob',
        'is_incoming': 0,
        'deleted_at': null,
      };

      final eligible = directReactionLocalStateFromRows(
        data: data,
        identityRow: identity,
        contactRow: contact,
        targetMessageRow: outgoingTarget,
        mlKemSecretKey: 'secret',
      );
      expect(eligible?.previewContext.actorUsername, 'Alice');

      expect(
        directReactionLocalStateFromRows(
          data: data,
          identityRow: null,
          contactRow: contact,
          targetMessageRow: outgoingTarget,
          mlKemSecretKey: 'secret',
        ),
        isNull,
      );
      expect(
        directReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          contactRow: {...contact, 'is_blocked': 1},
          targetMessageRow: outgoingTarget,
          mlKemSecretKey: 'secret',
        ),
        isNull,
      );
      expect(
        directReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          contactRow: contact,
          targetMessageRow: {...outgoingTarget, 'is_incoming': 1},
          mlKemSecretKey: 'secret',
        ),
        isNull,
      );
    });

    test(
      'group reaction background state hydrates the SQL secure-key reference',
      () async {
        final store = FakeSecureKeyStore();
        final keyName = groupKeyMaterialStoreName('group-team', 7);
        await store.write(keyName, 'hydrated-group-key');

        final hydrated = await hydrateBackgroundGroupKeyRow(
          groupKeyRow: <String, Object?>{
            'group_id': 'group-team',
            'key_generation': 7,
            'encrypted_key': secureStoreReferenceForKey(keyName),
          },
          secureStore: store,
        );

        expect(hydrated?['encrypted_key'], 'hydrated-group-key');

        await store.delete(keyName);
        expect(
          await hydrateBackgroundGroupKeyRow(
            groupKeyRow: <String, Object?>{
              'group_id': 'group-team',
              'key_generation': 7,
              'encrypted_key': secureStoreReferenceForKey(keyName),
            },
            secureStore: store,
          ),
          isNull,
          reason: 'missing secure material must suppress the notification',
        );
      },
    );

    test('group reaction local-state policy requires current local author', () {
      const data = <String, dynamic>{
        'type': 'group_reaction',
        'groupId': 'group-team',
        'reactor_peer_id': 'peer-alice',
        'event_id': 'transition-1',
        'target_message_id': 'message-1',
        'action': 'add',
        'keyEpoch': '7',
      };
      const identity = <String, Object?>{'peer_id': 'peer-bob'};
      const group = <String, Object?>{
        'id': 'group-team',
        'name': 'Team Chat',
        'type': 'chat',
        'is_muted': 0,
        'is_dissolved': 0,
        'dissolved_at': null,
      };
      final localMember = <String, Object?>{
        'group_id': 'group-team',
        'peer_id': 'peer-bob',
        'devices_json': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'deviceId': 'bob-phone',
            'transportPeerId': 'transport-bob-phone',
            'deviceSigningPublicKey': 'bob-device-key',
            'status': 'active',
          },
        ]),
      };
      final actorMember = <String, Object?>{
        'peer_id': 'peer-alice',
        'username': 'Alice',
        'devices_json': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'deviceId': 'alice-phone',
            'transportPeerId': 'transport-alice-phone',
            'deviceSigningPublicKey': 'alice-device-key',
            'status': 'active',
          },
        ]),
      };
      const outgoingTarget = <String, Object?>{
        'id': 'message-1',
        'group_id': 'group-team',
        'sender_peer_id': 'peer-bob',
        'is_incoming': 0,
      };
      const groupKey = <String, Object?>{
        'group_id': 'group-team',
        'key_generation': 7,
        'encrypted_key': 'group-key',
      };
      const nomination = VerifiedGroupReactionNotificationNomination(
        reactorTransportPeerId: 'transport-alice-phone',
        senderPublicKey: 'alice-device-key',
        transitionId: 'reaction-1',
      );

      final eligible = groupReactionLocalStateFromRows(
        data: data,
        identityRow: identity,
        groupRow: group,
        localMemberRow: localMember,
        actorMemberRow: actorMember,
        targetMessageRow: outgoingTarget,
        groupKeyRow: groupKey,
        latestGroupKeyRow: groupKey,
        currentReactionRow: null,
        localInstallationTransportPeerId: 'transport-bob-phone',
        verifiedNomination: nomination,
        targetAttachmentRows: const <Map<String, Object?>>[
          <String, Object?>{'owner_lane': 'direct', 'media_type': 'image'},
          <String, Object?>{'owner_lane': 'unresolved', 'media_type': 'audio'},
          <String, Object?>{'owner_lane': 'group', 'media_type': 'video'},
        ],
      );
      expect(eligible?.previewContext.groupName, 'Team Chat');
      expect(eligible?.previewContext.actorUsername, 'Alice');
      expect(
        eligible?.previewContext.targetKind,
        GroupReactionTargetKind.video,
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: <String, Object?>{
            'id': 'reaction-existing',
            'message_id': 'message-1',
            'sender_peer_id': 'peer-alice',
            'timestamp': '2026-08-03T01:00:00.000Z',
            'removed_at': null,
            'notification_acknowledged_at': '2026-08-03T01:00:01.000Z',
            'notification_display_terminal_event_id':
                boundedReactionEventIdentity('transition-1'),
          },
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
        reason: 'an acknowledged canonical reaction cannot alert again',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: <String, dynamic>{...data, 'event_id': 'transition-2'},
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: const <String, Object?>{
            'id': 'reaction-existing',
            'message_id': 'message-1',
            'sender_peer_id': 'peer-alice',
            'timestamp': '2026-08-03T01:00:00.000Z',
            'removed_at': null,
            'notification_acknowledged_at': '2026-08-03T01:00:01.000Z',
            'notification_display_terminal_event_id':
                'group-reaction-kind-transition-1',
          },
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNotNull,
        reason:
            'reading transition 1 cannot suppress distinct transition 2 before inbox mutation',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: const <String, Object?>{
            'id': 'reaction-existing',
            'message_id': 'message-1',
            'sender_peer_id': 'peer-alice',
            'timestamp': '2026-08-03T01:00:00.000Z',
            'removed_at': null,
            'notification_acknowledged_at': '2026-08-03T01:00:01.000Z',
            'notification_display_terminal_event_id': null,
          },
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNotNull,
        reason:
            'an unbound acknowledgement must reach decrypted exact-state comparison',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          readAcknowledgementRow: <String, Object?>{
            'group_id': 'group-team',
            'content_kind': 'reaction',
            'event_identity': boundedReactionEventIdentity('transition-1'),
            'generation': 'read-generation',
            'acknowledged_at': '2026-08-03T01:00:01.000Z',
          },
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
        reason: 'the exact durable read boundary wins the push/read race',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          readAcknowledgementRow: const <String, Object?>{
            'group_id': 'group-team',
            'content_kind': 'reaction',
            'event_identity': 'different-bounded-event',
          },
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNotNull,
        reason: 'a different event acknowledgement cannot suppress this push',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: const <String, Object?>{
            ...outgoingTarget,
            'media_policy_version': 1,
            'media_lifecycle': 'view_once',
            'media_duration_seconds': null,
            'media_protected': 1,
          },
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
        reason: 'private target media never becomes notification copy',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: {...group, 'is_muted': 1},
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
      );
      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: {...group, 'type': 'qa'},
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
        reason: 'QA storage does not widen the notification projection',
      );
      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: {...group, 'self_removed_at': '2026-08-02T00:00:00.000Z'},
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
        reason: 'a durable self-removal marker suppresses the notification',
      );
      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: {...outgoingTarget, 'is_incoming': 1},
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
      );
      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: {
            ...outgoingTarget,
            'sender_peer_id': 'peer-bystander',
          },
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: {...groupKey, 'key_generation': 8},
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
        reason: 'a retained historical key cannot authorize a reaction card',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-revoked-phone',
          verifiedNomination: nomination,
        ),
        isNull,
        reason: 'account membership alone cannot authorize another install',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: <String, Object?>{
            ...localMember,
            'devices_json': jsonEncode(<Map<String, Object?>>[
              <String, Object?>{
                'deviceId': 'bob-phone',
                'transportPeerId': 'transport-bob-phone',
                'deviceSigningPublicKey': 'bob-device-key',
                'status': 'revoked',
                'revokedAt': '2026-07-12T09:02:00.000Z',
              },
            ]),
          },
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: nomination,
        ),
        isNull,
        reason: 'a revoked local installation must fail closed',
      );

      expect(
        groupReactionLocalStateFromRows(
          data: data,
          identityRow: identity,
          groupRow: group,
          localMemberRow: localMember,
          actorMemberRow: actorMember,
          targetMessageRow: outgoingTarget,
          groupKeyRow: groupKey,
          latestGroupKeyRow: groupKey,
          currentReactionRow: null,
          localInstallationTransportPeerId: 'transport-bob-phone',
          verifiedNomination: null,
        ),
        isNull,
        reason: 'the current install must be signed-nominated',
      );
    });

    test('completes without error for valid RemoteMessage', () async {
      const message = RemoteMessage(
        messageId: 'msg-123',
        data: {'type': 'inbox', 'peerId': '12D3KooW...'},
      );

      // Should not throw
      await firebaseMessagingBackgroundHandler(message);
    });

    test(
      'shows a fallback notification for routable data-only pushes',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'msg-fallback-1',
          data: {'type': 'new_message', 'sender_id': '12D3KooWTestPeer'},
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(
          log.map((call) => call.method).toList(),
          containsAll(<String>[
            'initialize',
            'createNotificationChannel',
            'show',
          ]),
        );

        final channelCall = log.firstWhere(
          (call) => call.method == 'createNotificationChannel',
        );
        final channelArgs = channelCall.arguments as Map;
        expect(channelArgs['id'], mknoonMessagesChannelId);

        final showCall = log.firstWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(showArgs['title'], 'Mknoon');
        expect(showArgs['body'], 'Message');
        expect(showArgs['payload'], '12D3KooWTestPeer');
        final platformSpecifics = showArgs['platformSpecifics'] as Map;
        expect(platformSpecifics['channelId'], mknoonMessagesChannelId);
        expect(platformSpecifics['channelName'], mknoonMessagesChannelName);
        expect(
          platformSpecifics['channelDescription'],
          mknoonMessagesChannelDescription,
        );
        expect(platformSpecifics['playSound'], isTrue);
      },
    );

    test(
      'suppresses background fallback when account migration runtime gate blocks',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        final gateCalls = <String>[];
        debugSetBackgroundAccountMigrationNetworkGate(({
          String? peerId,
          required String operation,
        }) async {
          gateCalls.add(operation);
          return false;
        });

        const message = RemoteMessage(
          messageId: 'msg-migration-blocked-1',
          data: {'type': 'new_message', 'sender_id': '12D3KooWTestPeer'},
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(gateCalls, <String>['push_background_notification_display']);
        expect(log.where((call) => call.method == 'show'), isEmpty);
      },
    );

    test(
      'uses injected preview resolver before showing notification',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        debugSetBackgroundPushNotificationResolver((message) async {
          return const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'Hello secret',
            payload: 'peer-alice',
          );
        });
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );

        const message = RemoteMessage(
          messageId: 'msg-decrypt-1',
          data: {
            'type': 'new_message',
            'sender_id': 'peer-alice',
            'message_id': 'msg-decrypt-1',
            'kem': 'kem',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        final showCall = log.firstWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(showArgs['title'], 'Alice');
        expect(showArgs['body'], 'Hello secret');
        final payload = decodeConversationNotificationPayload(
          showArgs['payload'] as String?,
        );
        expect(payload?.routePayload, 'peer-alice');
        expect(
          payload?.metadata.kind,
          ConversationNotificationContentKind.message,
        );
      },
    );

    test('suppresses a repeated background fallback for the same push', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final gate = RecentBackgroundNotificationGate(
        filePath:
            '${Directory.systemTemp.path}/background-fallback-dedupe-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      debugSetRecentBackgroundNotificationGate(gate);
      addTearDown(gate.clear);
      debugSetBackgroundDirectMessageLocalStateResolver(
        (message) async => _authorizedDirectMessageState(message),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'initialize') {
              return true;
            }
            return null;
          });

      final message = RemoteMessage(
        messageId: 'msg-fallback-dedupe-1',
        sentTime: DateTime.utc(2026, 4, 4, 12),
        data: {'type': 'new_message', 'sender_id': '12D3KooWTestPeer'},
      );

      await firebaseMessagingBackgroundHandler(message);
      await firebaseMessagingBackgroundHandler(message);

      expect(log.where((call) => call.method == 'show'), hasLength(1));
    });

    test('handles RemoteMessage with null messageId', () async {
      const message = RemoteMessage(data: {'type': 'inbox'});

      await firebaseMessagingBackgroundHandler(message);
    });

    test('handles RemoteMessage with empty data map', () async {
      const message = RemoteMessage(messageId: 'msg-456');

      await firebaseMessagingBackgroundHandler(message);
    });

    test(
      'records a recent remote notification target even when FCM already carries a visible notification',
      () async {
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/background-handler-visible-push-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        const message = RemoteMessage(
          notification: RemoteNotification(title: 'Alice', body: 'Hey!'),
          data: {'type': 'new_message', 'sender_id': '12D3KooWVisiblePeer'},
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: '12D3KooWVisiblePeer',
          ),
          isTrue,
        );
      },
    );

    test(
      'visible Android group invite stays provider-owned without creating invite-id history',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final coordinatorDirectory = Directory.systemTemp.createTempSync(
          'visible-group-invite-no-history-',
        );
        addTearDown(() {
          if (coordinatorDirectory.existsSync()) {
            coordinatorDirectory.deleteSync(recursive: true);
          }
        });
        final coordinator = DurableNotificationToneLease(
          directory: coordinatorDirectory,
          pendingClaimWait: Duration.zero,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async => coordinator,
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            messageId: 'provider-visible-group-invite',
            notification: RemoteNotification(
              title: 'Book Club',
              body: 'Invited by Alice',
            ),
            data: <String, dynamic>{
              'type': 'group_invite',
              'groupId': 'group-visible',
              'message_id': 'invite-multi-use',
            },
          ),
        );

        expect(log.where((call) => call.method == 'show'), isEmpty);
        final laterDelivery = await coordinator.claimMessageEvent(
          type: 'group_invite',
          eventIdentity: 'invite-multi-use',
        );
        expect(laterDelivery, isNotNull);
        expect(await laterDelivery!.release(), isTrue);
      },
    );

    test(
      'GIRD-006 does not mark remote announcement when group fallback display fails',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/gird006-background-display-failure-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              if (call.method == 'show') {
                throw PlatformException(
                  code: 'display_failed',
                  message: 'blocked by OS notification state',
                );
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-gird006-display-fail',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-display-fail',
            'preview_unavailable': '1',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-gird006|message:msg-gird006-display-fail',
            messageId: 'msg-gird006-display-fail',
          ),
          isFalse,
          reason:
              'A failed local fallback must not suppress the later listener notification.',
        );
      },
    );

    test(
      'suppresses group background fallback when display eligibility denies it',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async =>
              const PushFallbackNotificationDisplayEligibility.suppressed(
                'group_missing',
              ),
        );
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/background-group-display-denied-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-session03-denied',
          data: {
            'type': 'group_message',
            'groupId': 'group-session03',
            'message_id': 'msg-session03-denied',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), isEmpty);
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-session03|message:msg-session03-denied',
            messageId: 'msg-session03-denied',
          ),
          isFalse,
        );
        final suppressionEvent = events.lastWhere(
          (event) =>
              event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
        );
        expect(
          suppressionEvent['details'],
          containsPair('reason', 'group_missing'),
        );
        expect(
          suppressionEvent['details'],
          containsPair(
            'payload',
            'group:group-session03|message:msg-session03-denied',
          ),
        );
      },
    );

    test('suppresses a muted group member end-to-end through the real fallback '
        'resolver and helper (reason "muted", no .show)', () async {
      // 04-P0 / SI-1 — Tier A regression lock (G-NM-1). Instead of stubbing
      // the outer eligibility seam with a hardcoded suppressed(...), this
      // drives the REAL resolveBackgroundPushFallbackDisplayEligibility with
      // the REAL groupMemberMessageDisplayEligibility helper (is_muted=1), so
      // the helper -> fallback-routing -> handler-suppression wiring AND the
      // literal 'muted' reason are locked end-to-end. A regression that
      // inverts the helper's mute check, or stops the fallback resolver from
      // routing a group_message to the group resolver, fails here while the
      // existing stubbed suppression tests would still pass. The encrypted-DB
      // glue (dbLoadGroup -> groupMemberMessageDisplayEligibility) is the
      // separate device Tier-B proof — the host VM cannot open the SQLCipher
      // identity.db.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      debugSetBackgroundPushNotificationDisplayEligibilityResolver(
        (message) => resolveBackgroundPushFallbackDisplayEligibility(
          message,
          groupMessageDisplayEligibilityResolver: (_) async =>
              groupMemberMessageDisplayEligibility({
                'type': 'chat',
                'is_muted': 1,
              }),
        ),
      );
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      final gate = RecentRemoteNotificationGate(
        filePath:
            '${Directory.systemTemp.path}/background-group-muted-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      debugSetRecentRemoteNotificationGate(gate);
      addTearDown(gate.clear);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'initialize') {
              return true;
            }
            return null;
          });

      const message = RemoteMessage(
        messageId: 'fcm-session03-muted',
        data: {
          'type': 'group_message',
          'groupId': 'group-session03-muted',
          'message_id': 'msg-session03-muted',
        },
      );

      await firebaseMessagingBackgroundHandler(message);

      expect(log.where((call) => call.method == 'show'), isEmpty);
      final suppressionEvent = events.lastWhere(
        (event) => event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
      );
      expect(suppressionEvent['details'], containsPair('reason', 'muted'));
    });

    test(
      'exact Android group claim replaces the recent-remote compatibility mark',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/gird006-background-display-success-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-gird006-display-success',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-display-success',
            'preview_unavailable': '1',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-gird006|message:msg-gird006-display-success',
            messageId: 'msg-gird006-display-success',
          ),
          isFalse,
          reason:
              'the committed durable claim is the exact Android dedupe authority',
        );
      },
    );

    test(
      'GIRD-006 coalesces duplicate group background fallback by logical message id',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(message),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-gird006-transport-a',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-duplicate',
            'preview_unavailable': '1',
          },
        );
        const duplicateTransportMessage = RemoteMessage(
          messageId: 'fcm-gird006-transport-b',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-duplicate',
            'preview_unavailable': '1',
          },
        );

        await firebaseMessagingBackgroundHandler(message);
        await firebaseMessagingBackgroundHandler(duplicateTransportMessage);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
      },
    );

    test(
      'registry duplicate defense preserves the Android card when claim storage is unavailable',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        debugSetBackgroundDurableLocalNotificationEffectResolver(
          ({
            required routeTarget,
            required fallback,
            required metadata,
          }) async => null,
        );
        debugSetBackgroundMessageNotificationCoordinatorResolver(
          () async =>
              throw const FileSystemException('claim storage unavailable'),
        );
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );

        Map<String, Object?>? activeNotification;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              if (call.method == 'getActiveNotifications') {
                return activeNotification == null
                    ? <Map<String, Object?>>[]
                    : <Map<String, Object?>>[activeNotification!];
              }
              if (call.method == 'show') {
                final arguments = call.arguments as Map;
                final platformSpecifics = arguments['platformSpecifics'] as Map;
                activeNotification = <String, Object?>{
                  'id': arguments['id'] as int,
                  'channelId': platformSpecifics['channelId'] as String,
                };
              }
              return null;
            });

        const first = RemoteMessage(
          messageId: 'transport-duplicate-a',
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWPeerDuplicate',
            'message_id': 'semantic-message-duplicate',
            'timestamp': '1000',
          },
        );
        const secondTransport = RemoteMessage(
          messageId: 'transport-duplicate-b',
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWPeerDuplicate',
            'message_id': 'semantic-message-duplicate',
            // Deliberately changes the recent-gate key so the durable content
            // registry is the final duplicate defense under test.
            'timestamp': '2000',
          },
        );

        await firebaseMessagingBackgroundHandler(first);
        await firebaseMessagingBackgroundHandler(secondTransport);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(log.where((call) => call.method == 'cancel'), isEmpty);
        expect(
          events.where(
            (entry) =>
                entry['event'] == 'NOTIFICATION_DUPLICATE_CARD_PRESERVED',
          ),
          hasLength(1),
        );
        expect(
          events.where(
            (entry) => entry['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'shows iOS local fallback for chat pushes when Flutter surfaces only the data payload',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        IOSFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWVisiblePeer',
            'title': 'Alice',
            'body': 'Hey!',
            'message_id': 'msg-visible-chat-1',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        final showCall = log.firstWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(showArgs['title'], 'Mknoon');
        expect(showArgs['body'], 'Message');
        final platformSpecifics = showArgs['platformSpecifics'] as Map;
        expect(platformSpecifics['presentSound'], isTrue);
        expect(platformSpecifics['presentAlert'], isTrue);
        expect(platformSpecifics['presentBadge'], isTrue);
      },
    );

    test(
      'rapid direct messages update one primary-channel card without a second alert',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final overlayDirectory = Directory.systemTemp.createTempSync(
          'background-direct-overlay-',
        );
        final overlay = PendingConversationNotificationOverlayStore(
          directory: overlayDirectory,
          resolveBinding: () async => 'v1:test-account',
          secureStore: FakeSecureKeyStore(),
        );
        debugSetBackgroundPendingConversationNotificationOverlayResolver(
          () async => overlay,
        );
        addTearDown(() {
          if (overlayDirectory.existsSync()) {
            overlayDirectory.deleteSync(recursive: true);
          }
        });
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(
            message,
            snapshot: ConversationNotificationSnapshot(
              historyLines: const <String>['older direct', 'newest direct'],
              totalUnreadMessageCount: 7,
              canonicalEventIds: const <String>['older-a', 'older-b'],
              orderedHistory: const <ConversationNotificationHistoryEntry>[
                ConversationNotificationHistoryEntry(
                  eventId: 'older-a',
                  line: 'older direct',
                  occurredAtMicros: 1,
                ),
                ConversationNotificationHistoryEntry(
                  eventId: 'older-b',
                  line: 'newest direct',
                  occurredAtMicros: 2,
                ),
              ],
            ),
          ),
        );

        Map<String, Object?>? activeNotification;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              if (call.method == 'getActiveNotifications') {
                return activeNotification == null
                    ? <Map<String, Object?>>[]
                    : <Map<String, Object?>>[activeNotification!];
              }
              if (call.method == 'show') {
                final arguments = call.arguments as Map;
                final platformSpecifics = arguments['platformSpecifics'] as Map;
                activeNotification = <String, Object?>{
                  'id': arguments['id'] as int,
                  'channelId': platformSpecifics['channelId'] as String,
                };
              }
              return null;
            });

        // A suspended burst of two distinct messages from the SAME sender.
        const first = RemoteMessage(
          messageId: 'm-burst-a',
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWPeerBurst',
            'message_id': 'direct-burst-a',
          },
        );
        const second = RemoteMessage(
          messageId: 'm-burst-b',
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWPeerBurst',
            'message_id': 'direct-burst-b',
          },
        );

        await firebaseMessagingBackgroundHandler(first);
        await firebaseMessagingBackgroundHandler(second);

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(2));

        final id0 = (shows[0].arguments as Map)['id'];
        final id1 = (shows[1].arguments as Map)['id'];
        // Direct background notifications coalesce per conversation.
        expect(
          id0,
          deterministicConversationNotificationId('12D3KooWPeerBurst'),
        );
        expect(id1, id0);

        final ps0 = (shows[0].arguments as Map)['platformSpecifics'] as Map;
        final ps1 = (shows[1].arguments as Map)['platformSpecifics'] as Map;
        expect(ps0['channelId'], mknoonMessagesChannelId);
        expect(ps0['playSound'], isTrue);
        expect(ps1['channelId'], mknoonMessagesChannelId);
        expect(ps1['playSound'], isFalse);
        expect(ps1['silent'], isTrue);
        expect(ps1['onlyAlertOnce'], isTrue);
        expect(ps0['number'], 8);
        expect(ps1['number'], 9);
        expect(ps1['style'], AndroidNotificationStyle.inbox.index);
        expect((ps1['styleInformation'] as Map)['lines'], const <String>[
          'older direct',
          'newest direct',
          'Message',
          'Message',
        ]);
      },
    );

    // The same burst with the user-facing "Messages" channel switched off.
    // The second post is the one that matters: it is the tone-debounced
    // silent update, and `mknoon_messages_silent` is still open, so before the
    // withdrawal it delivered a card the user had just turned off. The
    // background isolate is asserted separately from the foreground service
    // because it publishes through its own plugin instance.
    test('a blocked messages channel withdraws the silent channel from the '
        'background burst update', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      final overlayDirectory = Directory.systemTemp.createTempSync(
        'background-direct-overlay-blocked-',
      );
      final overlay = PendingConversationNotificationOverlayStore(
        directory: overlayDirectory,
        resolveBinding: () async => 'v1:test-account',
        secureStore: FakeSecureKeyStore(),
      );
      debugSetBackgroundPendingConversationNotificationOverlayResolver(
        () async => overlay,
      );
      addTearDown(() {
        if (overlayDirectory.existsSync()) {
          overlayDirectory.deleteSync(recursive: true);
        }
      });
      debugSetBackgroundDirectMessageLocalStateResolver(
        (message) async => _authorizedDirectMessageState(message),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'initialize') {
              return true;
            }
            if (call.method == 'getNotificationChannels') {
              return <Map<String, Object?>>[
                // 0 = IMPORTANCE_NONE: blocked by the user in Settings.
                _blockedChannelReply(mknoonMessagesChannelId, 0),
                _blockedChannelReply(
                  mknoonMessagesSilentChannelId,
                  Importance.low.value,
                ),
              ];
            }
            return null;
          });

      const first = RemoteMessage(
        messageId: 'm-blocked-a',
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWPeerBlocked',
          'message_id': 'direct-blocked-a',
        },
      );
      const second = RemoteMessage(
        messageId: 'm-blocked-b',
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWPeerBlocked',
          'message_id': 'direct-blocked-b',
        },
      );

      await firebaseMessagingBackgroundHandler(first);
      await firebaseMessagingBackgroundHandler(second);

      final shows = log.where((call) => call.method == 'show').toList();
      expect(shows, hasLength(2));
      final ps0 = (shows[0].arguments as Map)['platformSpecifics'] as Map;
      final ps1 = (shows[1].arguments as Map)['platformSpecifics'] as Map;
      // Both publications stay on the blocked channel, where the OS refuses
      // them. The post attempts remain real, which is what the Android
      // device matrix measures.
      expect(ps0['channelId'], mknoonMessagesChannelId);
      expect(ps1['channelId'], mknoonMessagesChannelId);
      expect(
        events
            .where(
              (event) =>
                  event['event'] == 'NOTIFICATION_SILENT_CHANNEL_WITHHELD',
            )
            .length,
        1,
        reason: 'only the silent update had a second route to withdraw',
      );
    });

    test(
      'background group burst reuses one conversation card while the latest tap stays message-anchored',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final overlayDirectory = Directory.systemTemp.createTempSync(
          'background-group-overlay-',
        );
        final overlay = PendingConversationNotificationOverlayStore(
          directory: overlayDirectory,
          resolveBinding: () async => 'v1:test-account',
          secureStore: FakeSecureKeyStore(),
        );
        debugSetBackgroundPendingConversationNotificationOverlayResolver(
          () async => overlay,
        );
        addTearDown(() {
          if (overlayDirectory.existsSync()) {
            overlayDirectory.deleteSync(recursive: true);
          }
        });
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundGroupMessageLocalStateResolver(
          (message) async => _authorizedGroupMessageState(
            message,
            snapshot: ConversationNotificationSnapshot(
              historyLines: const <String>['Alice: older', 'Bob: newest'],
              totalUnreadMessageCount: 9,
              canonicalEventIds: const <String>['group-old-a', 'group-old-b'],
              orderedHistory: const <ConversationNotificationHistoryEntry>[
                ConversationNotificationHistoryEntry(
                  eventId: 'group-old-a',
                  line: 'Alice: older',
                  occurredAtMicros: 1,
                ),
                ConversationNotificationHistoryEntry(
                  eventId: 'group-old-b',
                  line: 'Bob: newest',
                  occurredAtMicros: 2,
                ),
              ],
            ),
          ),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const first = RemoteMessage(
          messageId: 'fcm-burst-a',
          data: {
            'type': 'group_message',
            'groupId': 'group-burst',
            'message_id': 'gmsg-a',
            'preview_unavailable': '1',
          },
        );
        const second = RemoteMessage(
          messageId: 'fcm-burst-b',
          data: {
            'type': 'group_message',
            'groupId': 'group-burst',
            'message_id': 'gmsg-b',
            'preview_unavailable': '1',
          },
        );

        await firebaseMessagingBackgroundHandler(first);
        await firebaseMessagingBackgroundHandler(second);

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(2));

        final id0 = (shows[0].arguments as Map)['id'];
        final id1 = (shows[1].arguments as Map)['id'];
        expect(
          id0,
          deterministicConversationNotificationId('group:group-burst'),
        );
        expect(id1, id0);
        final firstPayload = decodeConversationNotificationPayload(
          (shows[0].arguments as Map)['payload'] as String?,
        );
        final secondPayload = decodeConversationNotificationPayload(
          (shows[1].arguments as Map)['payload'] as String?,
        );
        expect(firstPayload?.routePayload, 'group:group-burst|message:gmsg-a');
        expect(secondPayload?.routePayload, 'group:group-burst|message:gmsg-b');
        expect(
          secondPayload?.metadata.generation,
          isNot(firstPayload?.metadata.generation),
        );
        final secondPlatformSpecifics =
            (shows[1].arguments as Map)['platformSpecifics'] as Map;
        final firstPlatformSpecifics =
            (shows[0].arguments as Map)['platformSpecifics'] as Map;
        expect(firstPlatformSpecifics['playSound'], isTrue);
        expect(secondPlatformSpecifics['playSound'], isFalse);
        expect(firstPlatformSpecifics['autoCancel'], isFalse);
        expect(secondPlatformSpecifics['autoCancel'], isFalse);
        expect(
          secondPlatformSpecifics['channelId'],
          mknoonMessagesSilentChannelId,
        );
        expect(
          secondPlatformSpecifics['category'],
          AndroidNotificationCategory.message.name,
        );
        expect(firstPlatformSpecifics['number'], 10);
        expect(secondPlatformSpecifics['number'], 11);
        expect(
          (secondPlatformSpecifics['styleInformation'] as Map)['lines'],
          const <String>['Alice: older', 'Bob: newest', 'Message', 'Message'],
        );
      },
    );

    test(
      'canonical materialization retires pending push before the next plugin replacement',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final overlayDirectory = Directory.systemTemp.createTempSync(
          'background-materialized-overlay-',
        );
        final overlay = PendingConversationNotificationOverlayStore(
          directory: overlayDirectory,
          resolveBinding: () async => 'v1:test-account',
          secureStore: FakeSecureKeyStore(),
        );
        debugSetBackgroundPendingConversationNotificationOverlayResolver(
          () async => overlay,
        );
        addTearDown(() {
          if (overlayDirectory.existsSync()) {
            overlayDirectory.deleteSync(recursive: true);
          }
        });
        debugSetBackgroundDirectMessageLocalStateResolver((message) async {
          final id = message.data['message_id']?.toString();
          return _authorizedDirectMessageState(
            message,
            snapshot: id == 'direct-materialization-b'
                ? ConversationNotificationSnapshot(
                    historyLines: const <String>['canonical A'],
                    totalUnreadMessageCount: 1,
                    canonicalEventIds: const <String>[
                      'direct-materialization-a',
                    ],
                    orderedHistory:
                        const <ConversationNotificationHistoryEntry>[
                          ConversationNotificationHistoryEntry(
                            eventId: 'direct-materialization-a',
                            line: 'canonical A',
                            occurredAtMicros: 1,
                          ),
                        ],
                  )
                : null,
          );
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-materialization',
              'message_id': 'direct-materialization-a',
            },
          ),
        );
        await firebaseMessagingBackgroundHandler(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-materialization',
              'message_id': 'direct-materialization-b',
            },
          ),
        );

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(2));
        final first =
            (shows.first.arguments as Map)['platformSpecifics'] as Map;
        final second =
            (shows.last.arguments as Map)['platformSpecifics'] as Map;
        expect(first['number'], 1);
        expect((first['styleInformation'] as Map)['lines'], <String>[
          'Message',
        ]);
        expect(second['number'], 2, reason: 'canonical A + pending B only');
        expect((second['styleInformation'] as Map)['lines'], <String>[
          'canonical A',
          'Message',
        ]);
      },
    );

    test(
      'background reaction reads pending history without incrementing it',
      () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        final overlayDirectory = Directory.systemTemp.createTempSync(
          'background-reaction-overlay-',
        );
        final overlay = PendingConversationNotificationOverlayStore(
          directory: overlayDirectory,
          resolveBinding: () async => 'v1:test-account',
          secureStore: FakeSecureKeyStore(),
        );
        await overlay.project(
          conversationKey: 'group:group-reaction-overlay',
          canonicalSnapshot: null,
          currentMessage: const PendingConversationNotificationMessage(
            eventId: 'pending-message',
            line: 'Alice: pending message',
            occurredAtMicros: 1,
          ),
        );
        debugSetBackgroundPendingConversationNotificationOverlayResolver(
          () async => overlay,
        );
        addTearDown(() {
          if (overlayDirectory.existsSync()) {
            overlayDirectory.deleteSync(recursive: true);
          }
        });
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        debugSetBackgroundPushNotificationResolver(
          (_) async => const BackgroundPushNotificationFallback(
            title: 'Project group',
            body: 'Alice reacted to your message',
            payload:
                'group:group-reaction-overlay|message:reaction-target-message',
          ),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        const reaction = RemoteMessage(
          data: <String, dynamic>{
            'type': 'group_reaction',
            'groupId': 'group-reaction-overlay',
            'group_id': 'group-reaction-overlay',
            'event_id': 'reaction-overlay-event',
            'target_message_id': 'reaction-target-message',
            'reactor_peer_id': 'peer-reactor',
            'action': 'add',
            'payload':
                'group:group-reaction-overlay|message:reaction-target-message',
          },
        );
        await firebaseMessagingBackgroundHandler(reaction);
        await firebaseMessagingBackgroundHandler(reaction);

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(1), reason: events.toString());
        final show = shows.single;
        final specifics = (show.arguments as Map)['platformSpecifics'] as Map;
        expect(specifics['number'], 1);
        expect((specifics['styleInformation'] as Map)['lines'], <String>[
          'Alice: pending message',
          'Alice reacted to your message',
        ]);
        expect(specifics['playSound'], isTrue);
        await firebaseMessagingBackgroundHandler(
          RemoteMessage(
            data: <String, dynamic>{
              ...reaction.data,
              'event_id': 'reaction-overlay-next',
            },
          ),
        );
        final updates = log.where((call) => call.method == 'show').toList();
        expect(updates, hasLength(2));
        final update = updates.last.arguments as Map;
        final updateSpecifics = update['platformSpecifics'] as Map;
        expect(update['id'], (show.arguments as Map)['id']);
        expect(updateSpecifics['playSound'], isFalse);
        expect(updateSpecifics['onlyAlertOnce'], isTrue);
        expect(updateSpecifics['number'], 1);
        expect(
          (updateSpecifics['styleInformation'] as Map)['lines'],
          const <String>[
            'Alice: pending message',
            'Alice reacted to your message',
          ],
        );
        final projected = await overlay.project(
          conversationKey: 'group:group-reaction-overlay',
          canonicalSnapshot: null,
        );
        expect(projected?.totalUnreadMessageCount, 1);
        expect(
          projected?.historyLines,
          const <String>['Alice: pending message'],
          reason:
              'the reaction line is presentation-only, never pending ordinary history',
        );
      },
    );

    test(
      'different direct conversations remain independently audible',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundDirectMessageLocalStateResolver(
          (message) async => _authorizedDirectMessageState(message),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') return true;
              return null;
            });

        for (final message in const <RemoteMessage>[
          RemoteMessage(
            data: {
              'type': 'new_message',
              'sender_id': 'peer-conversation-a',
              'message_id': 'different-conversation-a',
            },
          ),
          RemoteMessage(
            data: {
              'type': 'new_message',
              'sender_id': 'peer-conversation-b',
              'message_id': 'different-conversation-b',
            },
          ),
        ]) {
          await firebaseMessagingBackgroundHandler(message);
        }

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(2));
        expect(
          shows.map(
            (call) =>
                ((call.arguments as Map)['platformSpecifics']
                    as Map)['playSound'],
          ),
          everyElement(isTrue),
        );
        expect(
          shows.map((call) => (call.arguments as Map)['id']).toSet(),
          hasLength(2),
        );
      },
    );
  });

  group('canonical background group display policy row mapping', () {
    const groupId = 'group-policy';
    const localPeerId = 'peer-local';
    const group = <String, Object?>{
      'id': groupId,
      'type': 'chat',
      'is_muted': 0,
      'is_archived': 0,
      'is_dissolved': 0,
      'dissolved_at': null,
      'self_removed_at': null,
    };
    const member = <String, Object?>{
      'group_id': groupId,
      'peer_id': localPeerId,
    };

    test('maps the exact group and current member to allow', () {
      final eligibility = groupNotificationDisplayEligibilityFromRows(
        expectedGroupId: groupId,
        localPeerId: localPeerId,
        groupRow: group,
        localMemberRow: member,
      );
      expect(eligibility.shouldDisplay, isTrue);
      expect(eligibility.reason, 'current_member');
    });

    for (final scenario
        in <
          ({
            Map<String, Object?>? groupRow,
            Map<String, Object?>? memberRow,
            String reason,
          })
        >[
          (groupRow: null, memberRow: member, reason: 'group_missing'),
          (groupRow: group, memberRow: null, reason: 'local_member_missing'),
          (
            groupRow: group,
            memberRow: {...member, 'group_id': 'other-group'},
            reason: 'local_member_missing',
          ),
          (
            groupRow: {...group, 'type': 'qa'},
            memberRow: member,
            reason: 'unsupported_group_type',
          ),
          (
            groupRow: {...group, 'is_muted': 1},
            memberRow: member,
            reason: 'muted',
          ),
          (
            groupRow: {...group, 'is_archived': 1},
            memberRow: member,
            reason: 'archived',
          ),
          (
            groupRow: {...group, 'is_dissolved': 1},
            memberRow: member,
            reason: 'dissolved',
          ),
          (
            groupRow: {...group, 'dissolved_at': '2026-08-02T00:00:00Z'},
            memberRow: member,
            reason: 'dissolved',
          ),
          (
            groupRow: {...group, 'self_removed_at': '2026-08-02T00:00:00Z'},
            memberRow: member,
            reason: 'self_removed',
          ),
        ]) {
      test('suppresses row state with reason ${scenario.reason}', () {
        final eligibility = groupNotificationDisplayEligibilityFromRows(
          expectedGroupId: groupId,
          localPeerId: localPeerId,
          groupRow: scenario.groupRow,
          localMemberRow: scenario.memberRow,
        );
        expect(eligibility.shouldDisplay, isFalse);
        expect(eligibility.reason, scenario.reason);
      });
    }

    test('suppresses a muted group member with reason "muted"', () {
      final eligibility = groupMemberMessageDisplayEligibility({
        'type': 'chat',
        'is_muted': 1,
      });
      expect(eligibility.shouldDisplay, isFalse);
      expect(eligibility.reason, 'muted');
    });

    test('allows an un-muted group member', () {
      final eligibility = groupMemberMessageDisplayEligibility({
        'type': 'chat',
        'is_muted': 0,
      });
      expect(eligibility.shouldDisplay, isTrue);
      expect(eligibility.reason, 'current_member');
    });

    test('fails closed when the group type is absent', () {
      expect(
        groupMemberMessageDisplayEligibility(<String, Object?>{}).shouldDisplay,
        isFalse,
      );
      expect(
        groupMemberMessageDisplayEligibility({'is_muted': null}).shouldDisplay,
        isFalse,
      );
    });
  });
}

BackgroundDirectMessageLocalState _authorizedDirectMessageState(
  RemoteMessage message, {
  ConversationNotificationSnapshot? snapshot,
}) {
  final sender =
      message.data['sender_id']?.toString() ??
      message.data['senderId']?.toString() ??
      message.data['senderPeerId']?.toString() ??
      message.data['from']?.toString() ??
      'peer-test';
  final messageId =
      message.data['message_id']?.toString() ??
      message.data['messageId']?.toString();
  return BackgroundDirectMessageLocalState(
    previewContext: DirectMessageNotificationContext(
      senderPeerId: sender,
      senderUsername: null,
      expectedMessageId: messageId,
    ),
    mlKemSecretKeys: const <String>[],
    snapshot: snapshot,
  );
}

BackgroundGroupMessageLocalState _authorizedGroupMessageState(
  RemoteMessage message, {
  ConversationNotificationSnapshot? snapshot,
}) {
  final groupId =
      message.data['groupId']?.toString() ??
      message.data['group_id']?.toString() ??
      'group-test';
  final messageId =
      message.data['message_id']?.toString() ??
      message.data['messageId']?.toString();
  return BackgroundGroupMessageLocalState(
    previewContext: GroupMessageNotificationContext(
      groupId: groupId,
      groupName: null,
      localPeerId: 'peer-local',
      senderPeerId: null,
      senderUsername: null,
      expectedMessageId: messageId,
    ),
    groupKey: null,
    keyEpoch: null,
    snapshot: snapshot,
  );
}

BackgroundDirectReactionLocalState? _eligibleDirectReactionState(
  RemoteMessage message,
) => directReactionLocalStateFromRows(
  data: message.data,
  identityRow: const <String, Object?>{'peer_id': 'peer-local'},
  contactRow: const <String, Object?>{
    'peer_id': 'peer-alice',
    'username': 'Alice',
    'is_blocked': 0,
    'is_archived': 0,
  },
  targetMessageRow: const <String, Object?>{
    'id': 'message-1',
    'contact_peer_id': 'peer-alice',
    'sender_peer_id': 'peer-local',
    'is_incoming': 0,
    'deleted_at': null,
  },
  mlKemSecretKey: 'recipient-secret',
);

BackgroundGroupReactionLocalState? _eligibleGroupReactionState(
  RemoteMessage message,
) => groupReactionLocalStateFromRows(
  data: message.data,
  identityRow: const <String, Object?>{'peer_id': 'peer-local'},
  groupRow: const <String, Object?>{
    'id': 'group-team',
    'name': 'Team Chat',
    'type': 'chat',
    'is_muted': 0,
    'is_archived': 0,
    'is_dissolved': 0,
    'dissolved_at': null,
    'self_removed_at': null,
  },
  localMemberRow: <String, Object?>{
    'group_id': 'group-team',
    'peer_id': 'peer-local',
    'devices_json': jsonEncode(<Map<String, Object?>>[
      <String, Object?>{
        'deviceId': 'local-phone',
        'transportPeerId': 'transport-local-phone',
        'deviceSigningPublicKey': 'local-device-key',
        'status': 'active',
      },
    ]),
  },
  actorMemberRow: <String, Object?>{
    'group_id': 'group-team',
    'peer_id': 'peer-alice',
    'username': 'Alice',
    'devices_json': jsonEncode(<Map<String, Object?>>[
      <String, Object?>{
        'deviceId': 'alice-phone',
        'transportPeerId': 'transport-alice-phone',
        'deviceSigningPublicKey': 'alice-device-key',
        'status': 'active',
      },
    ]),
  },
  targetMessageRow: const <String, Object?>{
    'id': 'message-1',
    'group_id': 'group-team',
    'sender_peer_id': 'peer-local',
    'is_incoming': 0,
  },
  groupKeyRow: const <String, Object?>{
    'group_id': 'group-team',
    'key_generation': 7,
    'encrypted_key': 'group-key',
  },
  latestGroupKeyRow: const <String, Object?>{
    'group_id': 'group-team',
    'key_generation': 7,
    'encrypted_key': 'group-key',
  },
  currentReactionRow: null,
  localInstallationTransportPeerId: 'transport-local-phone',
  verifiedNomination: const VerifiedGroupReactionNotificationNomination(
    reactorTransportPeerId: 'transport-alice-phone',
    senderPublicKey: 'alice-device-key',
    transitionId: 'group-inner-transition',
  ),
);

class _ThrowingToneReservationCoordinator extends DurableNotificationToneLease {
  _ThrowingToneReservationCoordinator(Directory directory)
    : super(directory: directory, pendingClaimWait: Duration.zero);

  @override
  Future<DurableNotificationToneReservation?> reserveTone(
    String conversationKey,
  ) async {
    throw const FileSystemException('tone storage unavailable');
  }
}

enum _DirectFinalBarrierLeg { canonicalRead, exactVisible, visibilityUnknown }

final class _ControlledBackgroundVisibility
    extends AppVisibilitySuppressionReader {
  _ControlledBackgroundVisibility({this.evaluation, this.failure})
    : assert(evaluation != null || failure != null);

  final AppVisibilityEvaluation? evaluation;
  final Object? failure;
  final Completer<void> entered = Completer<void>();
  final Completer<void> _released = Completer<void>();
  final List<AppVisibilityConversationIdentity?> identities =
      <AppVisibilityConversationIdentity?>[];

  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async {
    identities.add(identity);
    if (!entered.isCompleted) entered.complete();
    await _released.future;
    final capturedFailure = failure;
    if (capturedFailure != null) throw capturedFailure;
    return evaluation!;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

final class _OrderedBackgroundVisibility
    extends AppVisibilitySuppressionReader {
  _OrderedBackgroundVisibility(this.order);

  final List<String> order;

  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async {
    order.add('visibility');
    return const AppVisibilityEvaluation(
      isForegroundActive: false,
      maySuppress: false,
      lifecycle: AppVisibilityLifecycle.background,
      revision: 9,
      lifecycleGeneration: 12,
    );
  }
}

Future<void> _replaceBackgroundPendingToken(File file, String token) async {
  final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  decoded['token'] = token;
  await file.writeAsString(jsonEncode(decoded), flush: true);
}

/// Plan 383 (G17) — killed-app typed-event fallback lane.
///
/// The production state a genuinely new authenticated event meets at a killed
/// app is: the display-outbox table EXISTS (v106/v107 migrations ran) and holds
/// NO row for this event, because only the foreground runtime stages those
/// rows. These helpers reproduce that exact state with the real in-db resolver
/// instead of a hand-written null-returning stub.
const String backgroundFallbackLaneBinding =
    'v1:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

Future<Database> openEmptyBackgroundDisplayOutboxDatabase({
  required String tag,
  bool direct = false,
  bool group = false,
}) async {
  final path =
      '${Directory.systemTemp.path}/background-fallback-$tag-'
      '${DateTime.now().microsecondsSinceEpoch}.db';
  final db = await databaseFactoryFfi.openDatabase(path);
  addTearDown(() async {
    await db.close();
    await databaseFactoryFfi.deleteDatabase(path);
  });
  if (direct) {
    await db.execute('''
      CREATE TABLE direct_notification_display_outbox (
        event_id TEXT NOT NULL,
        event_kind TEXT NOT NULL,
        peer_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        actor_peer_id TEXT NOT NULL,
        event_timestamp TEXT NOT NULL,
        reaction_id TEXT,
        reaction_action TEXT,
        reaction_tombstone INTEGER,
        readiness TEXT NOT NULL,
        revision INTEGER NOT NULL,
        retry_count INTEGER NOT NULL,
        last_error_code TEXT,
        last_attempt_at TEXT,
        next_attempt_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(peer_id, event_kind, event_id)
      )
    ''');
  }
  if (group) {
    await db.execute('''
      CREATE TABLE group_notification_display_outbox (
        event_id TEXT PRIMARY KEY,
        event_kind TEXT NOT NULL,
        group_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        actor_peer_id TEXT NOT NULL,
        event_timestamp TEXT NOT NULL,
        reaction_id TEXT,
        reaction_action TEXT,
        reaction_tombstone INTEGER,
        readiness TEXT NOT NULL DEFAULT 'not_ready',
        revision INTEGER NOT NULL DEFAULT 1,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error_code TEXT,
        last_attempt_at TEXT,
        next_attempt_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }
  return db;
}

void useRealEmptyOutboxDurableEffectResolver(Database db) {
  debugSetBackgroundDurableLocalNotificationEffectResolver(
    ({required routeTarget, required fallback, required metadata}) =>
        resolveBackgroundDurableLocalNotificationEffectInDatabase(
          db,
          routeTarget: routeTarget,
          fallback: fallback,
          metadata: metadata,
          currentOpaqueBinding: backgroundFallbackLaneBinding,
          physicalPeerId: 'physical-fallback-lane',
          readFinalCanonicalDisposition: () async =>
              DurableLocalNotificationCanonicalDisposition.eligible,
        ),
  );
}

/// Installs a private ledger/registry pair so a test can prove that the
/// non-durable lane wrote NO ledger record while still reading the exact
/// content metadata the registry retained for the shown card.
Future<DurableConversationNotificationIdRegistry>
useIsolatedBackgroundNotificationRegistry(String tag) async {
  final directory = Directory.systemTemp.createTempSync(
    'background-fallback-$tag-registry-',
  );
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  final registry = DurableConversationNotificationIdRegistry(
    directory: directory,
  );
  await LocalNotificationLedgerStore(
    directory: directory,
  ).initializeOrRebind(currentOpaqueBinding: backgroundFallbackLaneBinding);
  debugSetBackgroundConversationNotificationIdRegistryResolver(
    () async => registry,
  );
  return registry;
}

Future<Map<String, LocalNotificationRecordV1>>
readBackgroundFallbackLedgerRecords(
  DurableConversationNotificationIdRegistry registry,
) async {
  final envelope = await LocalNotificationLedgerStore(
    directory: registry.directory,
  ).read(currentOpaqueBinding: backgroundFallbackLaneBinding);
  return envelope?.records ?? const <String, LocalNotificationRecordV1>{};
}
