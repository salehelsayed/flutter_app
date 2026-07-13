import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'scripts/reaction_notification_proof_support.dart';

const _requestFileName = 'tc256_reaction_preflight_request.json';
const _postForegroundMarkerName = 'tc256_post_foreground';
const _clearNotificationsMarkerName = 'tc256_clear_notifications';
const _recentGateBackupName = 'tc256_recent_gate_backup.json';
const _cleanupIndexFileName = 'tc256_cleanup_index.json';
const _recentGateFileName = 'mknoon_recent_background_notifications.json';
const _recentRemoteGateFileName = 'mknoon_recent_remote_notifications.json';
const _cleanupCommandSchema = 'mknoon.tc256-cleanup-command.v1';
const _fcmRefreshCommandName = 'tc256_fcm_refresh_command.json';
const _identityMlKemSecretKeyName = 'identity_ml_kem_secret_key';
const _dbEncryptionKeyName = 'db_encryption_key';
const _ordinaryOnly = bool.fromEnvironment('MKNOON_TC256_ORDINARY_ONLY');
const _actorPeerId = backgroundCryptoPreflightActorPeerId;
const _actorTransportPeerId = backgroundCryptoPreflightActorTransportPeerId;
const _nonAdminActorPeerId = backgroundCryptoPreflightNonAdminActorPeerId;
const _nonAdminTransportPeerId =
    backgroundCryptoPreflightNonAdminTransportPeerId;
const _actorUsername = backgroundCryptoPreflightDirectTrustedTitle;
const _maliciousOuterName = backgroundCryptoPreflightMaliciousOuterName;
const _maliciousDecryptedName = backgroundCryptoPreflightMaliciousDecryptedName;
const _maliciousDecryptedGroupName =
    backgroundCryptoPreflightMaliciousDecryptedGroupName;
const _groupKeyGeneration = 7;

const _groupSpecs =
    <({String context, String id, String name, String type, String actorRole})>[
      (
        context: 'group',
        id: backgroundCryptoPreflightGroupId,
        name: backgroundCryptoPreflightGroupTrustedTitle,
        type: 'chat',
        actorRole: 'writer',
      ),
      (
        context: 'announcement',
        id: backgroundCryptoPreflightAnnouncementId,
        name: backgroundCryptoPreflightAnnouncementTrustedTitle,
        type: 'announcement',
        actorRole: 'admin',
      ),
    ];

void _marker(String event, [Map<String, Object?> details = const {}]) {
  // Values written here are deliberately redacted. The FCM token, encrypted
  // envelopes, and key material live only in short-lived app-private stores.
  // ignore: avoid_print
  print(
    'MKNOON_256_CRYPTO_PREFLIGHT ${jsonEncode({'event': event, ...details})}',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var setupPhase = BackgroundCryptoSetupPhase.appInit;
  void checkpoint(BackgroundCryptoSetupPhase phase) {
    setupPhase = phase;
    _marker('setup_phase', {'phase': phase.wireName});
  }

  checkpoint(BackgroundCryptoSetupPhase.appInit);
  runApp(const _PreflightApp('Preparing TC-07...'));

  Database? db;
  try {
    final support = await getApplicationSupportDirectory();
    final clearNotifications = File(
      '${support.path}${Platform.pathSeparator}$_clearNotificationsMarkerName',
    );
    final cleanupCommand = await _readCleanupCommand(support);
    final startupIntent = backgroundCryptoFixtureStartupIntent(
      hasValidatedCleanupCommand: cleanupCommand != null,
      hasClearNotificationsMarker: await clearNotifications.exists(),
    );
    if (startupIntent ==
        BackgroundCryptoFixtureStartupIntent.clearNotifications) {
      var clearPhase = BackgroundCryptoNotificationClearPhase.knownIdLoad;
      void clearCheckpoint(BackgroundCryptoNotificationClearPhase phase) {
        clearPhase = phase;
        _marker('notification_clear_phase', {'phase': phase.wireName});
      }

      try {
        _marker('notification_clear_command_ack', {
          'schema': 'mknoon.tc256-notification-clear.v1',
        });
        await clearNotifications.delete();
        clearCheckpoint(BackgroundCryptoNotificationClearPhase.knownIdLoad);
        final knownNotificationIds = await _validatedFixtureNotificationIds(
          support,
        );
        final cleared = await _clearSyntheticNotifications(
          knownFixtureIds: knownNotificationIds,
          checkpoint: clearCheckpoint,
        );
        clearCheckpoint(BackgroundCryptoNotificationClearPhase.toneCleanup);
        await _deleteSyntheticToneLeases(support);
        clearPhase = BackgroundCryptoNotificationClearPhase.markerWrite;
        _marker('notification_clear_phase', {
          'phase': clearPhase.wireName,
          'completed': true,
          ...cleared,
        });
        runApp(const _PreflightApp('TC-07 notification cards cleared'));
      } on Object {
        _marker('notification_clear_error', {
          'phase': clearPhase.wireName,
          'reason': backgroundCryptoNotificationClearReasonForPhase(
            clearPhase,
          ).wireName,
        });
        runApp(const _PreflightApp('TC-07 notification clear failed'));
      }
      return;
    }

    checkpoint(BackgroundCryptoSetupPhase.secureStorage);
    final secureStore = FlutterSecureKeyStore();
    db = await _openCurrentIdentityDatabaseWithoutMigration(
      secureStore,
      checkpoint: checkpoint,
    );
    if (cleanupCommand != null && cleanupCommand.mode != 'post-proof') {
      _marker('cleanup_started', {
        'commandId': cleanupCommand.id,
        'commandSha256': cleanupCommand.rawSha256,
        'mode': cleanupCommand.mode,
        'mainReexecuted': true,
      });
      final cleanup = await _performReservedCleanup(
        db: db,
        secureStore: secureStore,
        support: support,
        command: cleanupCommand,
      );
      _marker('cleanup_complete', cleanup);
      await db.close();
      db = null;
      runApp(const _PreflightApp('TC-07 reserved cleanup complete'));
      return;
    }

    checkpoint(BackgroundCryptoSetupPhase.firebaseInit);
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    checkpoint(BackgroundCryptoSetupPhase.identityLoad);
    final identityRepository = IdentityRepositoryImpl(
      dbLoadIdentityRow: () => dbLoadIdentityRow(db!),
      dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db!, row),
      secureKeyStore: secureStore,
    );
    final identity = await identityRepository.loadIdentity();
    if (identity == null) {
      throw const _SetupFailure(BackgroundCryptoSetupReason.missingIdentity);
    }
    checkpoint(BackgroundCryptoSetupPhase.mlKemPublic);
    if (identity.mlKemPublicKey == null || identity.mlKemPublicKey!.isEmpty) {
      throw const _SetupFailure(BackgroundCryptoSetupReason.missingMlKemPublic);
    }
    checkpoint(BackgroundCryptoSetupPhase.mlKemSecret);
    final backgroundMlKemSecret = await secureStore.read(
      _identityMlKemSecretKeyName,
    );
    if (backgroundMlKemSecret == null || backgroundMlKemSecret.isEmpty) {
      throw const _SetupFailure(BackgroundCryptoSetupReason.missingMlKemSecret);
    }

    if (cleanupCommand != null) {
      _marker('cleanup_started', {
        'commandId': cleanupCommand.id,
        'commandSha256': cleanupCommand.rawSha256,
        'mode': cleanupCommand.mode,
        'mainReexecuted': true,
      });
      final cleanup = await _performReservedCleanup(
        db: db,
        secureStore: secureStore,
        support: support,
        command: cleanupCommand,
      );
      _marker('cleanup_complete', cleanup);

      final bridge = GoBridgeClient();
      await bridge.initialize();
      final started = await callP2PNodeStart(
        bridge,
        privateKeyHex: base64ToHex(identity.privateKey),
        relayAddresses: const [],
        autoRegister: false,
        namespace: 'tc256-background-crypto-preflight',
      );
      if (started['ok'] != true) {
        throw StateError('post-foreground Go node start failed');
      }
      _marker('post_foreground_node_started');
      await db.close();
      db = null;
      runApp(const _PreflightApp('TC-07 cleanup complete'));
      return;
    }

    BackgroundCryptoFcmRefreshCommand? fcmRefreshCommand;
    try {
      fcmRefreshCommand = await _readFcmRefreshCommand(support);
    } on FormatException {
      throw const _SetupFailure(BackgroundCryptoSetupReason.schemaGuard);
    }

    // Repair only residue owned by this reserved fixture, then snapshot the
    // production dedupe gate so the test can restore it byte-for-byte.
    checkpoint(BackgroundCryptoSetupPhase.fixtureSeed);
    final knownNotificationIds = await _validatedFixtureNotificationIds(
      support,
    );
    await _deleteSyntheticNotificationClaims(support, db: db);
    await _deleteSyntheticState(db, secureStore);
    await _deleteSyntheticStagedEnvelopes();
    await _deleteSyntheticNotificationIdOwners(support);
    await _restoreRecentGateBaseline(support);
    await _deleteSyntheticRecentGateEntries(support);
    await _captureRecentGateBaseline(support);
    await _clearSyntheticNotifications(knownFixtureIds: knownNotificationIds);

    final now = DateTime.now().toUtc();
    final suffix = now.microsecondsSinceEpoch;
    final eventId = _ordinaryOnly ? null : 'tc256-reaction-$suffix';
    final targetMessageId = _ordinaryOnly ? null : 'tc256-target-$suffix';
    await dbUpsertContact(
      db,
      ContactModel(
        peerId: _actorPeerId,
        publicKey: 'tc256-preflight-public-key',
        rendezvous: '/dns/mknoun.xyz/tcp/4001/wss',
        username: _actorUsername,
        signature: 'tc256-preflight-signature',
        scannedAt: now.toIso8601String(),
      ).toMap(),
    );
    if (targetMessageId != null) {
      await dbInsertMessage(
        db,
        ConversationMessage(
          id: targetMessageId,
          contactPeerId: _actorPeerId,
          senderPeerId: identity.peerId,
          text: 'TC-07 locally authored target',
          timestamp: now.toIso8601String(),
          status: 'sent',
          isIncoming: false,
          createdAt: now.toIso8601String(),
          readAt: now.toIso8601String(),
        ).toMap(),
      );
    }

    final groupKeys = <String, String>{};
    for (var index = 0; index < _groupSpecs.length; index++) {
      final spec = _groupSpecs[index];
      final key = base64Encode(
        List<int>.generate(32, (offset) => (offset + 37 * (index + 1)) % 256),
      );
      groupKeys[spec.context] = key;
      final secureKeyName = groupKeyMaterialStoreName(
        spec.id,
        _groupKeyGeneration,
      );
      await secureStore.write(secureKeyName, key);
      await dbInsertGroup(db, <String, Object?>{
        'id': spec.id,
        'name': spec.name,
        'type': spec.type,
        'topic_name': '/mknoon/tc256/${spec.id}/$suffix',
        'description': 'Reserved Android notification preflight fixture',
        'created_at': now.toIso8601String(),
        'created_by': _actorPeerId,
        'my_role': 'member',
      });
      await dbInsertGroupMember(db, <String, Object?>{
        'group_id': spec.id,
        'peer_id': identity.peerId,
        'username': identity.username,
        'role': 'reader',
        'devices_json': GroupMemberDeviceIdentity.listToJsonString(
          const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'tc256-preflight-local-device',
              transportPeerId: backgroundCryptoPreflightLocalTransportPeerId,
              deviceSigningPublicKey: 'tc256-preflight-local-signing-key',
            ),
          ],
        ),
        'joined_at': now.toIso8601String(),
      });
      await dbInsertGroupMember(db, <String, Object?>{
        'group_id': spec.id,
        'peer_id': _actorPeerId,
        'username': _actorUsername,
        'role': spec.actorRole,
        'devices_json': GroupMemberDeviceIdentity.listToJsonString(
          const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'tc256-preflight-actor-device',
              transportPeerId: _actorTransportPeerId,
              deviceSigningPublicKey: 'tc256-preflight-actor-signing-key',
            ),
          ],
        ),
        'joined_at': now.toIso8601String(),
      });
      if (spec.context == 'announcement') {
        await dbInsertGroupMember(db, <String, Object?>{
          'group_id': spec.id,
          'peer_id': _nonAdminActorPeerId,
          'username': 'TC256 Writer',
          'role': 'writer',
          'devices_json': GroupMemberDeviceIdentity.listToJsonString(
            const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'tc256-preflight-writer-device',
                transportPeerId: _nonAdminTransportPeerId,
                deviceSigningPublicKey: 'tc256-preflight-writer-signing-key',
              ),
            ],
          ),
          'joined_at': now.toIso8601String(),
        });
      }
      await dbInsertGroupKey(db, <String, Object?>{
        'group_id': spec.id,
        'key_generation': _groupKeyGeneration,
        'encrypted_key': secureStoreReferenceForKey(secureKeyName),
        'created_at': now.toIso8601String(),
      });
    }

    final bridge = GoBridgeClient();
    await bridge.initialize();
    Map<String, dynamic>? reactionEncrypted;
    if (!_ordinaryOnly) {
      final reactionInner = ReactionPayload(
        id: eventId!,
        messageId: targetMessageId!,
        emoji: '👍',
        action: 'add',
        senderPeerId: _actorPeerId,
        timestamp: now.toIso8601String(),
      ).toInnerJson();
      reactionEncrypted = await callEncryptMessage(
        bridge: bridge,
        recipientMlKemPublicKey: identity.mlKemPublicKey!,
        plaintext: reactionInner,
      );
      _requireEncryptionSuccess(reactionEncrypted, 'reaction');
    }

    final ordinaryCases = <Map<String, Object?>>[];
    for (
      var index = 0;
      index < backgroundCryptoPreflightOrdinaryRows.length;
      index++
    ) {
      final row = backgroundCryptoPreflightOrdinaryRows[index];
      final messageId = 'tc256-${row.id}-$suffix-$index';
      final text = row.modality == 'text'
          ? 'TC256 encrypted ${row.context} text'
          : '';
      final mediaType = switch (row.modality) {
        'image' => 'image',
        'video' => 'video',
        'voice' => 'audio',
        _ => null,
      };
      final media = mediaType == null
          ? null
          : <Map<String, Object?>>[
              <String, Object?>{
                'id': 'tc256-media-$messageId',
                'mediaType': mediaType,
                'mime': switch (mediaType) {
                  'image' => 'image/jpeg',
                  'video' => 'video/mp4',
                  _ => 'audio/aac',
                },
              },
            ];
      final previewBody = switch (row.modality) {
        'text' => text,
        'image' => localizedNotificationPhoto(1),
        'video' => localizedNotificationVideo(1),
        'voice' => localizedNotificationVoiceMessage(),
        _ => throw StateError('unsupported modality ${row.modality}'),
      };
      final expectedBody = row.context == 'direct'
          ? previewBody
          : '$_actorUsername: $previewBody';

      late final String expectedTitle;
      late final String conversationKey;
      late final String expectedPayload;
      late final Map<String, String> data;
      if (row.context == 'direct') {
        final plaintextPayload = <String, Object?>{
          'id': messageId,
          'text': text,
          'senderPeerId': _actorPeerId,
          'senderUsername': _maliciousDecryptedName,
          'timestamp': now.add(Duration(seconds: index)).toIso8601String(),
        };
        if (media != null) plaintextPayload['media'] = media;
        final plaintext = jsonEncode(plaintextPayload);
        final encrypted = await callEncryptMessage(
          bridge: bridge,
          recipientMlKemPublicKey: identity.mlKemPublicKey!,
          plaintext: plaintext,
        );
        _requireEncryptionSuccess(encrypted, row.id);
        expectedTitle = _actorUsername;
        conversationKey = _actorPeerId;
        expectedPayload = _actorPeerId;
        data = <String, String>{
          'type': row.remoteType,
          'sender_id': _actorPeerId,
          'message_id': messageId,
          'kem': encrypted['kem']! as String,
          'ciphertext': encrypted['ciphertext']! as String,
          'nonce': encrypted['nonce']! as String,
          'title': _maliciousOuterName,
          'body': _maliciousOuterName,
        };
      } else {
        final spec = _groupSpecs.singleWhere(
          (candidate) => candidate.context == row.context,
        );
        final plaintextPayload = <String, Object?>{
          'groupId': spec.id,
          'messageId': messageId,
          'senderId': _actorPeerId,
          'senderUsername': _maliciousDecryptedName,
          'groupName': _maliciousDecryptedGroupName,
          'text': text,
        };
        if (media != null) plaintextPayload['media'] = media;
        final plaintext = jsonEncode(plaintextPayload);
        final encrypted = await callGroupEncrypt(
          bridge,
          groupKeys[row.context]!,
          plaintext,
        );
        _requireEncryptionSuccess(encrypted, row.id, requiresKem: false);
        expectedTitle = spec.name;
        conversationKey = 'group:${spec.id}';
        expectedPayload = '$conversationKey|message:$messageId';
        data = <String, String>{
          'type': row.remoteType,
          'groupId': spec.id,
          'message_id': messageId,
          'sender_transport_peer_id': _actorTransportPeerId,
          'keyEpoch': '$_groupKeyGeneration',
          'ciphertext': encrypted['ciphertext']! as String,
          'nonce': encrypted['nonce']! as String,
          'title': _maliciousOuterName,
          'body': _maliciousOuterName,
          // Intentionally no sender_id: the active device transport maps to
          // the trusted local account/member role/name before decryption.
        };
      }
      ordinaryCases.add(<String, Object?>{
        ...row.toJson(),
        'conversationKey': conversationKey,
        'messageId': messageId,
        'expectedTitle': expectedTitle,
        'expectedBody': expectedBody,
        'expectedPayload': expectedPayload,
        'expectedCategory': 'msg',
        if (row.context != 'direct') ...<String, Object?>{
          'trustedActorAccountPeerId': _actorPeerId,
          'trustedActorTransportPeerId': _actorTransportPeerId,
          'trustedActorRole': _groupSpecs
              .singleWhere((spec) => spec.context == row.context)
              .actorRole,
          'trustedActorName': _actorUsername,
        },
        'forbiddenDisplayValues': const <String>[
          _maliciousOuterName,
          _maliciousDecryptedName,
          _maliciousDecryptedGroupName,
        ],
        'data': data,
      });
    }

    final negativeCases = <Map<String, Object?>>[];
    for (
      var index = 0;
      index < backgroundCryptoPreflightNegativeRows.length;
      index++
    ) {
      final row = backgroundCryptoPreflightNegativeRows[index];
      final spec = _groupSpecs.singleWhere(
        (candidate) => candidate.context == row.context,
      );
      final messageId =
          'tc256-${row.context}-negative-${row.rejectionReason}-$suffix-$index';
      final senderAccount = row.rejectionReason == 'non_admin_announcement'
          ? _nonAdminActorPeerId
          : _actorPeerId;
      final plaintext = jsonEncode(<String, Object?>{
        'groupId': spec.id,
        'messageId': messageId,
        'senderId': senderAccount,
        'senderUsername': _maliciousDecryptedName,
        'groupName': _maliciousDecryptedGroupName,
        'text': 'TC256 rejected authorization fixture',
      });
      final encrypted = await callGroupEncrypt(
        bridge,
        groupKeys[row.context]!,
        plaintext,
      );
      _requireEncryptionSuccess(encrypted, row.id, requiresKem: false);
      final data = <String, String>{
        'type': 'group_message',
        'groupId': spec.id,
        'message_id': messageId,
        if (row.rejectionReason == 'unknown_transport')
          'sender_transport_peer_id':
              backgroundCryptoPreflightUnknownTransportPeerId,
        if (row.rejectionReason == 'non_admin_announcement')
          'sender_transport_peer_id': _nonAdminTransportPeerId,
        'keyEpoch': '$_groupKeyGeneration',
        'ciphertext': encrypted['ciphertext']! as String,
        'nonce': encrypted['nonce']! as String,
        'title': _maliciousOuterName,
        'body': _maliciousOuterName,
        // Every negative also omits sender_id so only the authenticated
        // transport-to-local-member mapping is under test.
      };
      negativeCases.add(<String, Object?>{
        ...row.toJson(),
        'remoteType': 'group_message',
        'conversationKey': 'group:${spec.id}',
        'messageId': messageId,
        'expectedSuppressionReason': 'group_message_local_state_ineligible',
        'data': data,
      });
    }

    await _writeCleanupIndex(
      support,
      reactionEventId: eventId,
      reactionTargetMessageId: targetMessageId,
      ordinaryMessageIds: ordinaryCases
          .map((entry) => entry['messageId']! as String)
          .toList(growable: false),
      negativeMessageIds: negativeCases
          .map((entry) => entry['messageId']! as String)
          .toList(growable: false),
    );

    checkpoint(BackgroundCryptoSetupPhase.fcmToken);
    late final String token;
    late final Map<String, Object?> tokenMetadata;
    if (fcmRefreshCommand case final refresh?) {
      final commandAge = DateTime.now().toUtc().difference(refresh.issuedAt);
      if (commandAge.isNegative || commandAge > refresh.maxAge) {
        throw const _SetupFailure(BackgroundCryptoSetupReason.schemaGuard);
      }
      final messaging = FirebaseMessaging.instance;
      final previousToken = await messaging.getToken();
      if (previousToken == null || previousToken.trim().isEmpty) {
        throw const _SetupFailure(BackgroundCryptoSetupReason.missingFcmToken);
      }
      if (!backgroundCryptoFcmRefreshSubjectMatches(
        currentToken: previousToken,
        subjectTokenSha256: refresh.subjectTokenSha256,
      )) {
        throw const _SetupFailure(BackgroundCryptoSetupReason.schemaGuard);
      }
      final commandFile = File(
        '${support.path}${Platform.pathSeparator}$_fcmRefreshCommandName',
      );
      await commandFile.delete();
      if (await commandFile.exists()) {
        throw const _SetupFailure(BackgroundCryptoSetupReason.schemaGuard);
      }
      final observation = await acquireBackgroundCryptoFreshFcmToken(
        previousToken: previousToken,
        expectedSubjectTokenSha256: refresh.subjectTokenSha256,
        tokenRefreshes: messaging.onTokenRefresh,
        invalidateToken: messaging.deleteToken,
        pollToken: messaging.getToken,
        now: () => DateTime.now().toUtc(),
      );
      token = observation.token;
      tokenMetadata = <String, Object?>{
        'schema': backgroundCryptoFcmTokenObservationSchema,
        'source': 'forced_reregistration',
        'observedAt': observation.observedAt.toIso8601String(),
        'generationId': refresh.commandId,
        'tokenSha256': observation.tokenSha256,
        'priorTokenSha256': observation.priorTokenSha256,
        'refreshSignal': observation.source,
      };
    } else {
      final current = await FirebaseMessaging.instance.getToken();
      if (current == null || current.trim().isEmpty) {
        throw const _SetupFailure(BackgroundCryptoSetupReason.missingFcmToken);
      }
      token = current.trim();
      tokenMetadata = <String, Object?>{
        'schema': backgroundCryptoFcmTokenObservationSchema,
        'source': 'sdk_current',
        'observedAt': DateTime.now().toUtc().toIso8601String(),
        'generationId': null,
        'tokenSha256': sha256.convert(utf8.encode(token)).toString(),
        'priorTokenSha256': null,
        'refreshSignal': 'initial_get_token',
      };
    }
    checkpoint(BackgroundCryptoSetupPhase.bundleValidation);
    final request = File(
      '${support.path}${Platform.pathSeparator}$_requestFileName',
    );
    await request.writeAsString(
      jsonEncode(<String, Object?>{
        'schema': backgroundCryptoPreflightBundleSchema,
        'token': token,
        'tokenMetadata': tokenMetadata,
        if (!_ordinaryOnly)
          'reaction': <String, Object?>{
            'data': <String, String>{
              'type': 'message_reaction',
              'sender_id': _actorPeerId,
              'event_id': eventId!,
              'target_message_id': targetMessageId!,
              'action': 'add',
              'capability_version': 'direct_reaction_v1',
              'kem': reactionEncrypted!['kem']! as String,
              'ciphertext': reactionEncrypted['ciphertext']! as String,
              'nonce': reactionEncrypted['nonce']! as String,
            },
          },
        'ordinaryCases': ordinaryCases,
        'negativeCases': negativeCases,
      }),
      flush: true,
    );
    _marker('ready', {
      'schema': backgroundCryptoPreflightBundleSchema,
      'ordinaryCaseCount': ordinaryCases.length,
      'negativeCaseCount': negativeCases.length,
      'reactionRows': _ordinaryOnly ? 0 : 1,
    });
    await db.close();
    db = null;
    runApp(const _PreflightApp('TC-07 ready for killed-process FCM'));
  } catch (error) {
    await db?.close();
    final reason = error is _SetupFailure
        ? error.reason
        : BackgroundCryptoSetupReason.operationFailed;
    _marker('setup_error', {
      'phase': setupPhase.wireName,
      'reason': backgroundCryptoTerminalSetupReason(
        phase: setupPhase,
        reason: reason,
      ).wireName,
    });
    runApp(const _PreflightApp('TC-07 setup failed'));
  }
}

class _SetupFailure implements Exception {
  const _SetupFailure(this.reason);

  final BackgroundCryptoSetupReason reason;
}

class _CleanupCommand {
  const _CleanupCommand({
    required this.id,
    required this.mode,
    required this.rawSha256,
  });

  final String id;
  final String mode;
  final String rawSha256;
}

Future<BackgroundCryptoFcmRefreshCommand?> _readFcmRefreshCommand(
  Directory support,
) async {
  final command = File(
    '${support.path}${Platform.pathSeparator}$_fcmRefreshCommandName',
  );
  if (!await command.exists()) return null;
  return parseBackgroundCryptoFcmRefreshCommand(
    await command.readAsBytes(),
    now: DateTime.now().toUtc(),
  );
}

Future<_CleanupCommand?> _readCleanupCommand(Directory support) async {
  final command = File(
    '${support.path}${Platform.pathSeparator}$_postForegroundMarkerName',
  );
  if (!await command.exists()) return null;
  try {
    final rawBytes = await command.readAsBytes();
    final rawSha256 = sha256.convert(rawBytes).toString();
    final decoded = jsonDecode(utf8.decode(rawBytes, allowMalformed: false));
    if (decoded is! Map || decoded['schema'] != _cleanupCommandSchema) {
      throw const FormatException('invalid cleanup command schema');
    }
    final id = decoded['commandId'];
    final mode = decoded['mode'];
    if (id is! String ||
        !RegExp(r'^[a-z0-9-]{12,96}$').hasMatch(id) ||
        mode is! String ||
        !backgroundCryptoCleanupCommandModes.contains(mode)) {
      throw const FormatException('invalid cleanup command fields');
    }
    return _CleanupCommand(id: id, mode: mode, rawSha256: rawSha256);
  } on FormatException catch (error) {
    throw StateError('cannot execute reserved cleanup: $error');
  }
}

Future<Map<String, Object?>> _performReservedCleanup({
  required Database db,
  required FlutterSecureKeyStore secureStore,
  required Directory support,
  required _CleanupCommand command,
}) async {
  final knownNotificationIds = await _validatedFixtureNotificationIds(support);
  await _restoreRecentGateBaseline(support);
  final boundedReactionClaimNames = await _deleteSyntheticNotificationClaims(
    support,
    db: db,
  );
  await _deleteSyntheticState(db, secureStore);
  await _deleteSyntheticStagedEnvelopes();
  await _clearSyntheticNotifications(knownFixtureIds: knownNotificationIds);
  await _deleteSyntheticNotificationIdOwners(support);
  await _deleteSyntheticRecentGateEntries(support);

  final privateBundle = File(
    '${support.path}${Platform.pathSeparator}$_requestFileName',
  );
  if (await privateBundle.exists()) await privateBundle.delete();
  final cleanupIndex = File(
    '${support.path}${Platform.pathSeparator}$_cleanupIndexFileName',
  );
  if (await cleanupIndex.exists()) await cleanupIndex.delete();
  final commandFile = File(
    '${support.path}${Platform.pathSeparator}$_postForegroundMarkerName',
  );
  if (await commandFile.exists()) await commandFile.delete();
  final fcmRefreshCommandFile = File(
    '${support.path}${Platform.pathSeparator}$_fcmRefreshCommandName',
  );
  if (await fcmRefreshCommandFile.exists()) {
    await fcmRefreshCommandFile.delete();
  }
  final clearNotificationsMarker = File(
    '${support.path}${Platform.pathSeparator}$_clearNotificationsMarkerName',
  );
  if (await clearNotificationsMarker.exists()) {
    await clearNotificationsMarker.delete();
  }

  final verification = await _verifyReservedCleanup(
    db: db,
    secureStore: secureStore,
    support: support,
    boundedReactionClaimNames: boundedReactionClaimNames,
    knownNotificationIds: knownNotificationIds,
  );
  final residue = verification.values.whereType<int>().fold<int>(
    0,
    (total, value) => total + value,
  );
  if (await privateBundle.exists() ||
      await cleanupIndex.exists() ||
      await commandFile.exists() ||
      await fcmRefreshCommandFile.exists() ||
      await clearNotificationsMarker.exists()) {
    throw StateError('reserved cleanup private artifact survived');
  }
  if (residue != 0) {
    throw StateError('reserved cleanup verification found residue');
  }
  return <String, Object?>{
    'commandId': command.id,
    'commandSha256': command.rawSha256,
    'mode': command.mode,
    'mainReexecuted': true,
    'reservedOnly': true,
    'privateBundleDeleted': true,
    'cleanupIndexDeleted': true,
    'fcmRefreshCommandDeleted': true,
    'clearNotificationsMarkerDeleted': true,
    'boundedReactionClaimsVerified': true,
    'dedupeGatesRestored': 2,
    'dedupeGatesScrubbed': 2,
    ...verification,
  };
}

Future<Map<String, int>> _verifyReservedCleanup({
  required Database db,
  required FlutterSecureKeyStore secureStore,
  required Directory support,
  required Set<String> boundedReactionClaimNames,
  required Set<int> knownNotificationIds,
}) async {
  final dbRows = await _countReservedDatabaseRows(db);
  var groupKeyRefs = 0;
  for (final spec in _groupSpecs) {
    final value = await secureStore.read(
      groupKeyMaterialStoreName(spec.id, _groupKeyGeneration),
    );
    if (value != null) groupKeyRefs++;
  }
  final notificationCounts = await _countSyntheticNotifications(
    knownFixtureIds: knownNotificationIds,
  );
  return <String, int>{
    'fixtureDbRowsRemaining': dbRows,
    'fixtureGroupKeyRefsRemaining': groupKeyRefs,
    'fixtureClaimsRemaining': await _countSyntheticNotificationClaims(
      support,
      exactClaimNames: boundedReactionClaimNames,
    ),
    'fixtureToneSidecarsRemaining': await _countSyntheticToneLeases(support),
    'fixtureStagedEnvelopesRemaining': await _countSyntheticStagedEnvelopes(),
    'fixtureGateEntriesRemaining': await _countSyntheticRecentGateEntries(
      support,
    ),
    ...notificationCounts,
    'fixtureNotificationIdOwnersRemaining':
        await _countSyntheticNotificationIdOwners(support),
  };
}

Future<int> _countReservedDatabaseRows(Database db) async {
  Future<int> count(String table, String where, List<Object?> args) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $table WHERE $where',
      args,
    );
    return (rows.single['count'] as num).toInt();
  }

  var total = await count('contacts', 'peer_id = ?', <Object?>[_actorPeerId]);
  total += await count('messages', 'contact_peer_id = ?', <Object?>[
    _actorPeerId,
  ]);
  total += await count(
    'message_reactions',
    'id LIKE ? OR message_id LIKE ? OR sender_peer_id = ?',
    <Object?>['tc256-reaction-%', 'tc256-target-%', _actorPeerId],
  );
  for (final spec in _groupSpecs) {
    total += await count('groups', 'id = ?', <Object?>[spec.id]);
    total += await count('group_members', 'group_id = ?', <Object?>[spec.id]);
    total += await count('group_keys', 'group_id = ?', <Object?>[spec.id]);
    total += await count('group_messages', 'group_id = ?', <Object?>[spec.id]);
    total += await count(
      'group_message_local_deletions',
      'group_id = ?',
      <Object?>[spec.id],
    );
  }
  return total;
}

void _requireEncryptionSuccess(
  Map<String, dynamic> encrypted,
  String id, {
  bool requiresKem = true,
}) {
  final fields = <String>['ciphertext', 'nonce', if (requiresKem) 'kem'];
  if (encrypted['ok'] != true ||
      fields.any((field) {
        final value = encrypted[field];
        return value is! String || value.trim().isEmpty;
      })) {
    throw StateError('failed to build encrypted fixture for $id');
  }
}

Future<void> _deleteSyntheticState(
  Database db,
  FlutterSecureKeyStore secureStore,
) async {
  await dbDeleteReactionsForContact(db, _actorPeerId);
  await db.rawDelete(
    'DELETE FROM message_reactions '
    'WHERE id LIKE ? OR message_id LIKE ? OR sender_peer_id = ?',
    <Object?>['tc256-reaction-%', 'tc256-target-%', _actorPeerId],
  );
  await dbDeleteMessagesForContact(db, _actorPeerId);
  await dbDeleteContact(db, _actorPeerId);
  for (final spec in _groupSpecs) {
    await dbDeleteGroupMessagesForGroup(db, spec.id);
    await db.delete(
      'group_message_local_deletions',
      where: 'group_id = ?',
      whereArgs: <Object?>[spec.id],
    );
    await dbDeleteAllGroupKeys(db, spec.id);
    await dbDeleteAllGroupMembers(db, spec.id);
    await dbDeleteGroup(db, spec.id);
    await secureStore.delete(
      groupKeyMaterialStoreName(spec.id, _groupKeyGeneration),
    );
  }
}

Future<Database> _openCurrentIdentityDatabaseWithoutMigration(
  FlutterSecureKeyStore secureStore, {
  required void Function(BackgroundCryptoSetupPhase phase) checkpoint,
}) async {
  checkpoint(BackgroundCryptoSetupPhase.dbKey);
  final storedKey = await secureStore.read(_dbEncryptionKeyName);
  if (storedKey == null || storedKey.trim().isEmpty) {
    throw const _SetupFailure(BackgroundCryptoSetupReason.schemaGuard);
  }
  final record = parseCipherKeyRecord(storedKey);
  if (!isValid256BitHexKey(record.hex)) {
    throw const _SetupFailure(BackgroundCryptoSetupReason.schemaGuard);
  }
  checkpoint(BackgroundCryptoSetupPhase.dbOpen);
  final databasePath = '${await getDatabasesPath()}/identity.db';
  if (!await databaseExists(databasePath)) {
    throw const _SetupFailure(BackgroundCryptoSetupReason.schemaGuard);
  }

  Future<Database> openWithPassword(String password) async {
    final candidate = await openDatabase(
      databasePath,
      password: password,
      singleInstance: false,
      onConfigure: (database) async {
        // Match production: Android execSQL rejects this value-returning
        // PRAGMA, so it must run through rawQuery before the first DB read.
        await database.rawQuery('PRAGMA busy_timeout = 5000');
      },
    );
    try {
      // Force SQLCipher key validation inside this attempt so a legacy
      // passphrase database can fall back after a lazy raw-key open.
      await candidate.rawQuery('SELECT count(*) FROM sqlite_master');
      return candidate;
    } catch (_) {
      await candidate.close();
      rethrow;
    }
  }

  Database opened;
  try {
    opened = await openWithPassword("x'${record.hex}'");
  } catch (_) {
    if (record.mode == CipherKeyMode.raw) rethrow;
    opened = await openWithPassword(record.hex);
  }
  try {
    checkpoint(BackgroundCryptoSetupPhase.dbSchema);
    final rows = await opened.rawQuery('PRAGMA user_version');
    final version = (rows.single.values.single as num).toInt();
    if (version != currentIdentityDatabaseVersion) {
      throw const _SetupFailure(BackgroundCryptoSetupReason.schemaGuard);
    }
    return opened;
  } catch (_) {
    await opened.close();
    rethrow;
  }
}

ActiveNotificationCard _activeNotificationCard(Object notification) {
  final active = notification as dynamic;
  return ActiveNotificationCard(
    id: active.id as int?,
    title: active.title as String? ?? '',
    body: active.body as String? ?? '',
    routePayload: active.payload as String?,
  );
}

Map<String, int> _notificationOwnershipReasonCounts(
  Iterable<ActiveNotificationCard> cards, {
  required Set<int> knownFixtureIds,
  required String suffix,
}) {
  var owned = 0;
  final counts = <BackgroundCryptoFixtureNotificationOwnershipReason, int>{
    for (final reason
        in BackgroundCryptoFixtureNotificationOwnershipReason.values)
      reason: 0,
  };
  for (final card in cards) {
    final ownership = backgroundCryptoFixtureNotificationOwnership(
      card,
      knownFixtureIds: knownFixtureIds,
    );
    if (!ownership.isOwned) continue;
    owned++;
    for (final reason in ownership.reasons) {
      counts[reason] = counts[reason]! + 1;
    }
  }
  return <String, int>{
    'fixtureNotificationCards$suffix': owned,
    for (final entry in counts.entries)
      'fixtureNotification${switch (entry.key) {
        BackgroundCryptoFixtureNotificationOwnershipReason.route => 'Route',
        BackgroundCryptoFixtureNotificationOwnershipReason.copy => 'Copy',
        BackgroundCryptoFixtureNotificationOwnershipReason.knownId => 'KnownId',
      }}OwnedCards$suffix': entry
          .value,
  };
}

Future<Map<String, int>> _clearSyntheticNotifications({
  required Set<int> knownFixtureIds,
  void Function(BackgroundCryptoNotificationClearPhase phase)? checkpoint,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  checkpoint?.call(BackgroundCryptoNotificationClearPhase.activeQuery);
  final active = await plugin.getActiveNotifications();
  checkpoint?.call(BackgroundCryptoNotificationClearPhase.classify);
  final cards = active.map(_activeNotificationCard).toList(growable: false);
  final counts = _notificationOwnershipReasonCounts(
    cards,
    knownFixtureIds: knownFixtureIds,
    suffix: 'Cleared',
  );
  checkpoint?.call(BackgroundCryptoNotificationClearPhase.cancel);
  for (final notification in active) {
    final card = _activeNotificationCard(notification);
    final id = card.id;
    if (id != null &&
        backgroundCryptoFixtureNotificationOwnership(
          card,
          knownFixtureIds: knownFixtureIds,
        ).isOwned) {
      await plugin.cancel(id);
    }
  }
  return counts;
}

Future<Map<String, int>> _countSyntheticNotifications({
  required Set<int> knownFixtureIds,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  final active = await plugin.getActiveNotifications();
  return _notificationOwnershipReasonCounts(
    active.map(_activeNotificationCard),
    knownFixtureIds: knownFixtureIds,
    suffix: 'Remaining',
  );
}

Set<String> _syntheticConversationOwnerHashes() => <String>{
  for (final conversationKey in <String>{
    _actorPeerId,
    for (final spec in _groupSpecs) 'group:${spec.id}',
  })
    sha256.convert(utf8.encode(conversationKey)).toString(),
};

Future<Set<int>> _validatedFixtureNotificationIds(Directory support) async {
  final cleanupIndex = File(
    '${support.path}${Platform.pathSeparator}$_cleanupIndexFileName',
  );
  if (!await cleanupIndex.exists()) return const <int>{};
  try {
    final decoded = jsonDecode(await cleanupIndex.readAsString());
    final validation = validateBackgroundCryptoCleanupIndex(
      decoded,
      boundedClaimName: _boundedReactionClaimName,
      requireReaction: _ordinaryOnly ? false : null,
    );
    if (!validation.isValid) {
      throw const FormatException('invalid cleanup index');
    }
  } on FormatException catch (error) {
    throw StateError('cannot validate notification cleanup index: $error');
  }

  final root = Directory(
    '${support.path}${Platform.pathSeparator}'
    '${DurableConversationNotificationIdRegistry.directoryName}',
  );
  if (!await root.exists()) return const <int>{};
  final owners = _syntheticConversationOwnerHashes();
  final ids = <int>{};
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    final suffix = DurableConversationNotificationIdRegistry.ownerFileSuffix;
    if (!name.endsWith(suffix)) continue;
    final id = int.tryParse(name.substring(0, name.length - suffix.length));
    if (id == null || id < 0 || id > 0x7fffffff) continue;
    try {
      if (owners.contains((await entity.readAsString()).trim())) ids.add(id);
    } on FileSystemException catch (error) {
      throw StateError(
        'cannot classify validated notification ID: ${error.runtimeType}',
      );
    }
  }
  return Set<int>.unmodifiable(ids);
}

Future<void> _deleteSyntheticNotificationIdOwners(Directory support) async {
  final root = Directory(
    '${support.path}${Platform.pathSeparator}'
    '${DurableConversationNotificationIdRegistry.directoryName}',
  );
  if (!await root.exists()) return;
  final owners = _syntheticConversationOwnerHashes();
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! File ||
        !entity.path.endsWith(
          DurableConversationNotificationIdRegistry.ownerFileSuffix,
        )) {
      continue;
    }
    try {
      if (owners.contains((await entity.readAsString()).trim())) {
        await entity.delete();
      }
    } on FileSystemException catch (error) {
      throw StateError(
        'cannot classify notification ID owner: ${error.runtimeType}',
      );
    }
  }
}

Future<int> _countSyntheticNotificationIdOwners(Directory support) async {
  final root = Directory(
    '${support.path}${Platform.pathSeparator}'
    '${DurableConversationNotificationIdRegistry.directoryName}',
  );
  if (!await root.exists()) return 0;
  final owners = _syntheticConversationOwnerHashes();
  var count = 0;
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! File ||
        !entity.path.endsWith(
          DurableConversationNotificationIdRegistry.ownerFileSuffix,
        )) {
      continue;
    }
    try {
      if (owners.contains((await entity.readAsString()).trim())) count++;
    } on FileSystemException catch (error) {
      throw StateError(
        'cannot verify notification ID owner: ${error.runtimeType}',
      );
    }
  }
  return count;
}

Future<void> _deleteSyntheticToneLeases(Directory support) async {
  final claimsRoot = Directory(
    '${support.path}${Platform.pathSeparator}ReactionNotificationClaims',
  );
  for (final conversationKey in <String>{
    _actorPeerId,
    for (final spec in _groupSpecs) 'group:${spec.id}',
  }) {
    final identity = sha256.convert(utf8.encode(conversationKey)).toString();
    final toneName = '$identity.lease';
    final tone = File(
      '${claimsRoot.path}${Platform.pathSeparator}'
      '${DurableNotificationToneLease.toneLeasesDirectoryName}'
      '${Platform.pathSeparator}$toneName',
    );
    if (await tone.exists()) await tone.delete();
    final pending = File(
      '${tone.parent.path}${Platform.pathSeparator}'
      '.$identity${DurableNotificationToneLease.tonePendingReservationFileSuffix}',
    );
    if (await pending.exists()) await pending.delete();
  }
}

Future<int> _countSyntheticToneLeases(Directory support) async {
  final claimsRoot = Directory(
    '${support.path}${Platform.pathSeparator}ReactionNotificationClaims',
  );
  var count = 0;
  for (final conversationKey in <String>{
    _actorPeerId,
    for (final spec in _groupSpecs) 'group:${spec.id}',
  }) {
    final identity = sha256.convert(utf8.encode(conversationKey)).toString();
    final tone = File(
      '${claimsRoot.path}${Platform.pathSeparator}'
      '${DurableNotificationToneLease.toneLeasesDirectoryName}'
      '${Platform.pathSeparator}$identity.lease',
    );
    final pending = File(
      '${tone.parent.path}${Platform.pathSeparator}'
      '.$identity${DurableNotificationToneLease.tonePendingReservationFileSuffix}',
    );
    if (await tone.exists()) count++;
    if (await pending.exists()) count++;
  }
  return count;
}

Future<void> _writeCleanupIndex(
  Directory support, {
  required String? reactionEventId,
  required String? reactionTargetMessageId,
  required List<String> ordinaryMessageIds,
  required List<String> negativeMessageIds,
}) async {
  if ((reactionEventId == null) != (reactionTargetMessageId == null)) {
    throw StateError('reaction cleanup IDs must both be present or absent');
  }
  final target = File(
    '${support.path}${Platform.pathSeparator}$_cleanupIndexFileName',
  );
  final temporary = File('${target.path}.tmp');
  try {
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'schema': 'mknoon.tc256-cleanup-index.v2',
        'reactionEventIds': <String>[?reactionEventId],
        'reactionTargetMessageIds': <String>[?reactionTargetMessageId],
        'boundedReactionClaimNames': <String>[
          if (reactionEventId != null)
            _boundedReactionClaimName(reactionEventId),
        ],
        'ordinaryMessageIds': ordinaryMessageIds,
        'negativeMessageIds': negativeMessageIds,
      }),
      flush: true,
    );
    await temporary.rename(target.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<Map<String, dynamic>?> _readPrivateBundle(Directory support) async {
  final request = File(
    '${support.path}${Platform.pathSeparator}$_requestFileName',
  );
  try {
    if (!await request.exists()) return null;
    final decoded = jsonDecode(await request.readAsString());
    final bundle = decoded is Map<String, dynamic>
        ? decoded
        : decoded is Map
        ? decoded.cast<String, dynamic>()
        : null;
    if (bundle == null) {
      throw const FormatException('private bundle root is not an object');
    }
    final errors = validateBackgroundCryptoPreflightBundle(
      bundle,
      requireReaction: _ordinaryOnly ? false : null,
    );
    if (errors.isNotEmpty) {
      throw FormatException(
        'private bundle failed ${errors.length} reserved cleanup checks',
      );
    }
    return bundle;
  } on FileSystemException catch (error) {
    throw StateError(
      'cannot read private cleanup bundle: ${error.runtimeType}',
    );
  } on FormatException catch (error) {
    throw StateError('cannot classify private cleanup bundle: $error');
  }
}

Future<({Set<String> eventIds, Set<String> boundedClaimNames})>
_reservedReactionClaims(Directory support, Database db) async {
  final eventIds = <String>{};
  final boundedClaimNames = <String>{};
  final bundle = await _readPrivateBundle(support);
  if (!_ordinaryOnly) {
    final reaction = bundle?['reaction'];
    final reactionData = reaction is Map ? reaction['data'] : null;
    if (reactionData is Map) {
      final eventId = reactionData['event_id']?.toString().trim();
      if (eventId != null && eventId.startsWith('tc256-reaction-')) {
        eventIds.add(eventId);
      }
    }
  }

  final cleanupIndex = File(
    '${support.path}${Platform.pathSeparator}$_cleanupIndexFileName',
  );
  if (await cleanupIndex.exists()) {
    try {
      final decoded = jsonDecode(await cleanupIndex.readAsString());
      final validation = validateBackgroundCryptoCleanupIndex(
        decoded,
        boundedClaimName: _boundedReactionClaimName,
        requireReaction: _ordinaryOnly ? false : null,
      );
      if (!validation.isValid) {
        throw FormatException(
          'reserved cleanup index failed ${validation.errors.length} checks',
        );
      }
      eventIds.addAll(validation.eventIds);
      boundedClaimNames.addAll(validation.boundedClaimNames);
    } on FormatException catch (error) {
      throw StateError('cannot read reserved cleanup index: $error');
    }
  }

  final targetRows = await db.query(
    'messages',
    columns: const <String>['id'],
    where: 'contact_peer_id = ? AND id LIKE ?',
    whereArgs: <Object?>[_actorPeerId, 'tc256-target-%'],
  );
  for (final row in targetRows) {
    final targetId = row['id']?.toString() ?? '';
    const targetPrefix = 'tc256-target-';
    if (targetId.startsWith(targetPrefix) &&
        targetId.length > targetPrefix.length) {
      final eventId =
          'tc256-reaction-${targetId.substring(targetPrefix.length)}';
      if (!backgroundCryptoReactionTargetHaveParity(
        eventId: eventId,
        targetMessageId: targetId,
      )) {
        throw StateError('reserved DB reaction/target parity failed');
      }
      eventIds.add(eventId);
    }
  }

  final staging = await resolvePushEnvelopeStagingDirectory();
  if (await staging.exists()) {
    await for (final entity in staging.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final envelope = await _readStagedEnvelope(entity);
      final eventId = envelope.eventId?.trim();
      if (_isSyntheticStagedEnvelope(envelope) && eventId != null) {
        if (!backgroundCryptoReactionTargetHaveParity(
          eventId: eventId,
          targetMessageId: envelope.targetMessageId,
        )) {
          throw StateError('staged reaction/target parity failed');
        }
        eventIds.add(eventId);
      }
    }
  }
  return (
    eventIds: Set<String>.unmodifiable(eventIds),
    boundedClaimNames: Set<String>.unmodifiable(boundedClaimNames),
  );
}

String _boundedReactionClaimName(String eventId) =>
    DurableNotificationToneLease.messageEventClaimFileName(
      type: 'message_reaction',
      eventIdentity: boundedReactionEventIdentity(eventId),
    );

Future<Set<String>> _deleteSyntheticNotificationClaims(
  Directory support, {
  required Database db,
}) async {
  final bundle = await _readPrivateBundle(support);
  final exactClaimNames = <String>{};
  final boundedClaimNames = <String>{};
  void addReservedRawClaim(String type, String identity) {
    final name = DurableNotificationToneLease.messageEventClaimFileName(
      type: type,
      eventIdentity: identity,
    );
    if (!isBackgroundCryptoFixtureClaimFileName(name)) {
      throw StateError('private bundle claim identity left reserved namespace');
    }
    exactClaimNames.add(name);
  }

  if (!_ordinaryOnly) {
    final reaction = bundle?['reaction'];
    final reactionData = reaction is Map ? reaction['data'] : null;
    if (reactionData is Map) {
      final eventId = reactionData['event_id']?.toString().trim();
      if (eventId != null) {
        addReservedRawClaim('message_reaction', eventId);
      }
    }
  }
  final reservedReactionClaims = await _reservedReactionClaims(support, db);
  boundedClaimNames.addAll(reservedReactionClaims.boundedClaimNames);
  exactClaimNames.addAll(reservedReactionClaims.boundedClaimNames);
  for (final eventId in reservedReactionClaims.eventIds) {
    addReservedRawClaim('message_reaction', eventId);
    final bounded = _boundedReactionClaimName(eventId);
    boundedClaimNames.add(bounded);
    exactClaimNames.add(bounded);
  }
  for (final caseKey in const <String>['ordinaryCases', 'negativeCases']) {
    final cases = bundle?[caseKey];
    if (cases is List) {
      for (final value in cases.whereType<Map>()) {
        final type = value['remoteType']?.toString().trim();
        final messageId = value['messageId']?.toString().trim();
        if (type != null && messageId != null) {
          addReservedRawClaim(type, messageId);
        }
      }
    }
  }

  final claimsRoot = Directory(
    '${support.path}${Platform.pathSeparator}ReactionNotificationClaims',
  );
  for (final claimName in exactClaimNames) {
    final file = File(
      '${claimsRoot.path}${Platform.pathSeparator}'
      '${DurableNotificationToneLease.eventClaimsDirectoryName}'
      '${Platform.pathSeparator}$claimName',
    );
    if (await file.exists()) await file.delete();
    if (await file.exists()) {
      throw StateError('reserved notification claim survived cleanup');
    }
  }

  final eventDirectory = Directory(
    '${claimsRoot.path}${Platform.pathSeparator}'
    '${DurableNotificationToneLease.eventClaimsDirectoryName}',
  );
  if (await eventDirectory.exists()) {
    await for (final entity in eventDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (isBackgroundCryptoFixtureClaimFileName(name)) {
        await entity.delete();
      }
    }
  }

  await _deleteSyntheticToneLeases(support);
  return Set<String>.unmodifiable(boundedClaimNames);
}

Future<int> _countSyntheticNotificationClaims(
  Directory support, {
  Set<String> exactClaimNames = const <String>{},
}) async {
  final eventDirectory = Directory(
    '${support.path}${Platform.pathSeparator}ReactionNotificationClaims'
    '${Platform.pathSeparator}'
    '${DurableNotificationToneLease.eventClaimsDirectoryName}',
  );
  if (!await eventDirectory.exists()) return 0;
  final remaining = <String>{};
  await for (final entity in eventDirectory.list(followLinks: false)) {
    if (entity is File) {
      final name = entity.uri.pathSegments.last;
      if (isBackgroundCryptoFixtureClaimFileName(name) ||
          exactClaimNames.contains(name)) {
        remaining.add(name);
      }
    }
  }
  return remaining.length;
}

Future<void> _deleteSyntheticStagedEnvelopes() async {
  final directory = await resolvePushEnvelopeStagingDirectory();
  if (!await directory.exists()) return;
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final envelope = await _readStagedEnvelope(entity);
    if (_isSyntheticStagedEnvelope(envelope)) {
      await entity.delete();
    }
  }
}

Future<int> _countSyntheticStagedEnvelopes() async {
  final directory = await resolvePushEnvelopeStagingDirectory();
  if (!await directory.exists()) return 0;
  var count = 0;
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final envelope = await _readStagedEnvelope(entity);
    if (_isSyntheticStagedEnvelope(envelope)) count++;
  }
  return count;
}

Future<StagedPushEnvelope> _readStagedEnvelope(File file) async {
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('staged envelope root is not an object');
    }
    return StagedPushEnvelope.fromJson(decoded);
  } on FileSystemException catch (error) {
    throw StateError('cannot classify staged envelope: ${error.runtimeType}');
  } on FormatException catch (error) {
    throw StateError('cannot classify staged envelope: ${error.runtimeType}');
  }
}

bool _isSyntheticStagedEnvelope(StagedPushEnvelope envelope) =>
    isBackgroundCryptoFixtureEnvelope(
      senderPeerId: envelope.senderPeerId,
      messageId: envelope.messageId,
      eventId: envelope.eventId,
      targetMessageId: envelope.targetMessageId,
    );

Future<void> _captureRecentGateBaseline(Directory support) async {
  final backup = File(
    '${support.path}${Platform.pathSeparator}$_recentGateBackupName',
  );
  final files = <String, List<int>?>{};
  for (final fileName in const <String>[
    _recentGateFileName,
    _recentRemoteGateFileName,
  ]) {
    final gate = File('${support.path}${Platform.pathSeparator}$fileName');
    final existed = await gate.exists();
    files[fileName] = existed ? await gate.readAsBytes() : null;
  }
  final temp = File('${backup.path}.tmp');
  await temp.writeAsString(
    jsonEncode(encodeBackgroundCryptoFileBaselines(files)),
    flush: true,
  );
  await temp.rename(backup.path);
}

Future<void> _restoreRecentGateBaseline(Directory support) async {
  final backup = File(
    '${support.path}${Platform.pathSeparator}$_recentGateBackupName',
  );
  if (!await backup.exists()) return;
  try {
    final decoded = jsonDecode(await backup.readAsString());
    if (decoded is! Map) {
      throw const FormatException('invalid recent-gate backup metadata');
    }
    final records = <({File file, bool existed, List<int>? contents})>[];
    final files = decoded['files'];
    if (files is Map) {
      final decodedFiles = decodeBackgroundCryptoFileBaselines(
        decoded,
        expectedFileNames: const <String>{
          _recentGateFileName,
          _recentRemoteGateFileName,
        },
      );
      for (final fileName in const <String>[
        _recentGateFileName,
        _recentRemoteGateFileName,
      ]) {
        final contents = decodedFiles[fileName];
        records.add((
          file: File('${support.path}${Platform.pathSeparator}$fileName'),
          existed: contents != null,
          contents: contents,
        ));
      }
    } else {
      // Backward-compatible repair for a partially completed v1 harness run.
      final existed = decoded['existed'];
      final encoded = decoded['contentsBase64'];
      if (existed is! bool || (existed && encoded is! String)) {
        throw const FormatException('invalid legacy recent-gate backup');
      }
      records.add((
        file: File(
          '${support.path}${Platform.pathSeparator}$_recentGateFileName',
        ),
        existed: existed,
        contents: existed ? base64Decode(encoded! as String) : null,
      ));
    }
    for (final record in records) {
      if (record.existed) {
        await record.file.writeAsBytes(record.contents!, flush: true);
      } else if (await record.file.exists()) {
        await record.file.delete();
      }
    }
    await backup.delete();
  } on FormatException catch (error) {
    throw StateError('cannot restore recent notification gate: $error');
  }
}

Future<void> _deleteSyntheticRecentGateEntries(Directory support) async {
  for (final fileName in const <String>[
    _recentGateFileName,
    _recentRemoteGateFileName,
  ]) {
    final file = File('${support.path}${Platform.pathSeparator}$fileName');
    if (!await file.exists()) continue;
    final entries = await _readRecentGateEntries(file);
    final cleaned = removeBackgroundCryptoFixtureGateEntries(entries);
    if (cleaned.length == entries.length) continue;
    if (cleaned.isEmpty) {
      await file.delete();
      continue;
    }
    final temporary = File('${file.path}.tc256-cleanup.tmp');
    try {
      await temporary.writeAsString(jsonEncode(cleaned), flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

Future<int> _countSyntheticRecentGateEntries(Directory support) async {
  var count = 0;
  for (final fileName in const <String>[
    _recentGateFileName,
    _recentRemoteGateFileName,
  ]) {
    final file = File('${support.path}${Platform.pathSeparator}$fileName');
    if (!await file.exists()) continue;
    final entries = await _readRecentGateEntries(file);
    count += entries.keys.where(isBackgroundCryptoFixtureGateKey).length;
  }
  return count;
}

Future<Map<String, Object?>> _readRecentGateEntries(File file) async {
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('recent gate is not a JSON object');
    }
    return decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  } on FormatException catch (error) {
    throw StateError('cannot scrub reserved recent-gate entries: $error');
  }
}

class _PreflightApp extends StatelessWidget {
  const _PreflightApp(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(body: Center(child: Text(status))),
    );
  }
}
