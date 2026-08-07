// Notification Sound Smoke — Role-Dispatched Harness (Alice sender / Bob receiver)
//
// A single harness that dispatches on the SMOKE_ROLE dart-define:
//   - role == 'alice' -> sender path (drives text, suppression, and media
//     scenarios by sending messages to Bob, coordinated via signal files under
//     /tmp/nsmoke_<runId>_*).
//   - role == 'bob'   -> receiver path (verifies the REAL
//     FlutterNotificationService fires with sound config intact, writing
//     per-scenario verdict files the orchestrator reads).
//
// Scenarios: S1-S3 text, S4 suppression, S5-S13 image/video/voice across
// direct, group discussion, and group announcement lanes.
//
// Launch via orchestrator:
//   dart run integration_test/scripts/run_notification_sound_smoke.dart -d alice,bob

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';

import '_support/direct_inbox_custody_db_bindings.dart';
import '_support/node_readiness.dart';
import '_support/signal_files.dart';
import 'group_multi_device_real_harness.dart';

// ---------------------------------------------------------------------------
// Role dispatch
// ---------------------------------------------------------------------------

const _role = String.fromEnvironment('SMOKE_ROLE', defaultValue: 'alice');

// ---------------------------------------------------------------------------
// Config from dart-defines (shared across roles)
// ---------------------------------------------------------------------------

const _sharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '/tmp',
);
const _runId = String.fromEnvironment('SMOKE_RUN_ID', defaultValue: 'adhoc');
const _dbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: 'notif_sound_smoke.db',
);
const _nonInteractive = bool.fromEnvironment(
  'NOTIFICATION_SOUND_NON_INTERACTIVE',
);

enum _MediaNotificationLane { direct, group, announcement }

class _MediaNotificationScenario {
  const _MediaNotificationScenario({
    required this.id,
    required this.lane,
    required this.mediaType,
    required this.mime,
    required this.hashSeed,
  });

  final String id;
  final _MediaNotificationLane lane;
  final String mediaType;
  final String mime;
  final String hashSeed;

  String get signal => id.toLowerCase();
}

const _mediaNotificationScenarios = <_MediaNotificationScenario>[
  _MediaNotificationScenario(
    id: 'S5',
    lane: _MediaNotificationLane.direct,
    mediaType: 'image',
    mime: 'image/jpeg',
    hashSeed: '1',
  ),
  _MediaNotificationScenario(
    id: 'S6',
    lane: _MediaNotificationLane.direct,
    mediaType: 'video',
    mime: 'video/mp4',
    hashSeed: '2',
  ),
  _MediaNotificationScenario(
    id: 'S7',
    lane: _MediaNotificationLane.direct,
    mediaType: 'audio',
    mime: 'audio/mp4',
    hashSeed: '3',
  ),
  _MediaNotificationScenario(
    id: 'S8',
    lane: _MediaNotificationLane.group,
    mediaType: 'image',
    mime: 'image/jpeg',
    hashSeed: '4',
  ),
  _MediaNotificationScenario(
    id: 'S9',
    lane: _MediaNotificationLane.group,
    mediaType: 'video',
    mime: 'video/mp4',
    hashSeed: '5',
  ),
  _MediaNotificationScenario(
    id: 'S10',
    lane: _MediaNotificationLane.group,
    mediaType: 'audio',
    mime: 'audio/mp4',
    hashSeed: '6',
  ),
  _MediaNotificationScenario(
    id: 'S11',
    lane: _MediaNotificationLane.announcement,
    mediaType: 'image',
    mime: 'image/jpeg',
    hashSeed: '7',
  ),
  _MediaNotificationScenario(
    id: 'S12',
    lane: _MediaNotificationLane.announcement,
    mediaType: 'video',
    mime: 'video/mp4',
    hashSeed: '8',
  ),
  _MediaNotificationScenario(
    id: 'S13',
    lane: _MediaNotificationLane.announcement,
    mediaType: 'audio',
    mime: 'audio/mp4',
    hashSeed: '9',
  ),
];

/// Mirrors the production guarded group-attachment persistence seam.
///
/// [setupGroupMultiDeviceStack] intentionally provides only the repository
/// surface needed by its original group-text scenarios. Media notification
/// scenarios exercise the incoming group-media path, which must use the same
/// parent/tombstone guard wired by `main.dart`.
MediaAttachmentRepositoryImpl _createNotificationGroupMediaRepository(
  GroupMultiDeviceTestStack stack,
) {
  final db = stack.db;
  final repository = MediaAttachmentRepositoryImpl(
    dbSaveMediaAttachmentPreservingLocalState: (row) =>
        dbSaveMediaAttachmentPreservingLocalState(db, row),
    dbLoadMediaForMessage: (messageId, ownerLane) =>
        dbLoadMediaForMessage(db, messageId, ownerLane: ownerLane),
    dbLoadMediaById: (id) => dbLoadMediaById(db, id),
    dbLoadMediaForMessages: (messageIds, ownerLane) =>
        dbLoadMediaForMessages(db, messageIds, ownerLane: ownerLane),
    dbUpdateMediaLocalPath: (id, localPath, downloadStatus) =>
        dbUpdateMediaLocalPath(db, id, localPath, downloadStatus),
    dbUpdateMediaDownloadStatus: (id, downloadStatus) =>
        dbUpdateMediaDownloadStatus(db, id, downloadStatus),
    dbDeleteMediaForMessage: (messageId, ownerLane) =>
        dbDeleteMediaForMessage(db, messageId, ownerLane: ownerLane),
    dbDeleteMediaForContact: (contactPeerId) =>
        dbDeleteMediaForContact(db, contactPeerId),
    dbMarkUploadPendingAttachmentsFailedForMessage: (messageId, ownerLane) =>
        dbMarkUploadPendingAttachmentsFailedForMessage(
          db,
          messageId,
          ownerLane: ownerLane,
        ),
    dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(db),
    dbLoadUploadPendingAttachments:
        ({int limit = 50, required String ownerLane}) =>
            dbLoadUploadPendingAttachments(
              db,
              limit: limit,
              ownerLane: ownerLane,
            ),
    dbSetMediaBookmarked: (id, bookmarked) =>
        dbSetMediaBookmarked(db, id, bookmarked: bookmarked),
    dbUpdateMediaPlaybackPosition: (id, positionMs) =>
        dbUpdateMediaPlaybackPosition(db, id, positionMs),
    dbLoadMediaLibraryPage:
        ({
          required String scopeKind,
          required String scopeId,
          required List<String> mediaTypes,
          required bool bookmarkedOnly,
          required bool incomingOnly,
          required int limit,
          String? afterTimestamp,
          String? afterMessageId,
          String? afterAttachmentId,
        }) => dbLoadMediaLibraryPage(
          db,
          scopeKind: scopeKind,
          scopeId: scopeId,
          mediaTypes: mediaTypes,
          bookmarkedOnly: bookmarkedOnly,
          incomingOnly: incomingOnly,
          limit: limit,
          afterTimestamp: afterTimestamp,
          afterMessageId: afterMessageId,
          afterAttachmentId: afterAttachmentId,
        ),
    dbSaveGroupMediaAttachmentGuarded: (row, {required String groupId}) =>
        dbSaveGroupMediaAttachmentGuarded(db, row, groupId: groupId),
  );
  if (repository.dbSaveGroupMediaAttachmentGuarded == null) {
    throw StateError(
      'Notification media harness requires guarded group-attachment writes',
    );
  }
  print('[NOTIF-HARNESS] Guarded group-media persistence is wired');
  return repository;
}

MediaAttachment _mediaAttachmentForScenario(
  _MediaNotificationScenario scenario, {
  required String messageId,
}) {
  return MediaAttachment(
    id: 'notification-$_runId-${scenario.signal}',
    messageId: messageId,
    mime: scenario.mime,
    size: 4096,
    mediaType: scenario.mediaType,
    width: scenario.mediaType == 'image' || scenario.mediaType == 'video'
        ? 640
        : null,
    height: scenario.mediaType == 'image' || scenario.mediaType == 'video'
        ? 480
        : null,
    durationMs: scenario.mediaType == 'video' || scenario.mediaType == 'audio'
        ? 3200
        : null,
    downloadStatus: 'done',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    waveform: scenario.mediaType == 'audio'
        ? const <double>[0.1, 0.4, 0.2]
        : null,
    contentHash: List<String>.filled(64, scenario.hashSeed).join(),
    encryptionKeyBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    encryptionNonce: 'AAAAAAAAAAAAAAAA',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  );
}

// Canonical signal-file coordinator. Produces byte-identical paths to the old
// inline `_sig(name)` => `'$_sharedDir/nsmoke_${_runId}_$name'`.
final SignalDir _signals = SignalDir(
  dir: _sharedDir,
  prefix: 'nsmoke_',
  runId: '${_runId}_',
  role: 'Notif($_role)',
);

// ---------------------------------------------------------------------------
// Recording NotificationService (Bob only)
//
// Wraps FlutterNotificationService and records every showMessageNotification
// call directly (no dependence on debugPrint capture, which the
// integration-test binding clobbers). We infer NOTIFICATION_SUPPRESSED by
// observing that a call did NOT happen within a scenario window — the
// `maybeShowNotification` gate is the only other code path, so "no call"
// unambiguously means "suppressed".
// ---------------------------------------------------------------------------

class _RecordingNotificationService implements NotificationService {
  _RecordingNotificationService(this._inner);
  final NotificationService _inner;
  final List<_RecordedShow> shown = <_RecordedShow>[];

  @override
  void Function(String payload)? get onNotificationTap =>
      _inner.onNotificationTap;
  @override
  set onNotificationTap(void Function(String payload)? value) =>
      _inner.onNotificationTap = value;

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    ConversationNotificationContentKind? contentKind,
    String? contentEventIdentity,
    ConversationNotificationSnapshot? snapshot,
  }) async {
    final resolvedPayload = payload ?? contactPeerId;
    await _inner.showMessageNotification(
      contactPeerId: contactPeerId,
      senderUsername: senderUsername,
      messageText: messageText,
      payload: resolvedPayload,
      silent: silent,
      contentKind: contentKind,
      contentEventIdentity: contentEventIdentity,
      snapshot: snapshot,
    );
    shown.add(
      _RecordedShow(
        contactPeerId: contactPeerId,
        senderUsername: senderUsername,
        messageText: messageText,
        payload: resolvedPayload,
        silent: silent,
        at: DateTime.now(),
      ),
    );
    print(
      '[BOB-N-REC] showMessageNotification called contactPeerId=$contactPeerId silent=$silent shown.length=${shown.length}',
    );
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) => _inner.showNotification(title: title, body: body, payload: payload);

  @override
  Future<String?> consumeInitialPayload() => _inner.consumeInitialPayload();

  @override
  Future<void> clearDeliveredNotifications() =>
      _inner.clearDeliveredNotifications();

  @override
  void dispose() => _inner.dispose();
}

class _RecordedShow {
  final String contactPeerId;
  final String senderUsername;
  final String messageText;
  final String? payload;
  final bool silent;
  final DateTime at;
  _RecordedShow({
    required this.contactPeerId,
    required this.senderUsername,
    required this.messageText,
    required this.payload,
    required this.at,
    this.silent = false,
  });

  Map<String, dynamic> toJson() => {
    'contactPeerId': contactPeerId,
    'senderUsername': senderUsername,
    'messageText': messageText,
    'payload': payload,
    'silent': silent,
    'at': at.toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// Main — dispatches on SMOKE_ROLE
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  if (_role == 'bob') {
    _runBob();
  } else {
    _runAlice();
  }
}

// ---------------------------------------------------------------------------
// Alice (Sender)
// ---------------------------------------------------------------------------

void _runAlice() {
  testWidgets('Alice(Notif) — S1..S13', (tester) async {
    print('\n${'═' * 60}');
    print('  ALICE (NOTIFICATION SOUND) — SMOKE E2E');
    print('${'═' * 60}\n');

    // ── Stack (reuse the group-capable setup; all repos we need) ──
    late final MessageRepositoryImpl messageRepo;
    final stack = await setupGroupMultiDeviceStack(
      dbName: _dbName,
      username: 'AliceNotif',
      cliPeerFixture: null,
      publishOutgoingOrdinaryMutation:
          ({required messageId, required outcome, required committedMedia}) =>
              messageRepo.publishOutgoingOrdinaryMutation(
                messageId: messageId,
                outcome: outcome,
                committedMedia: committedMedia,
              ),
    );
    await waitForOnline(stack.p2pService, timeout: const Duration(seconds: 60));

    // ── 1:1 message repo (not created by setupGroupMultiDeviceStack) ──
    final custodyDb = DirectInboxCustodyDbBindings(stack.db);
    messageRepo = MessageRepositoryImpl(
      dbInsertMessage: (row) => dbInsertMessage(stack.db, row),
      dbLoadMessagesForContact: (p) => dbLoadMessagesForContact(stack.db, p),
      dbLoadLatestMessageForContact: (p) =>
          dbLoadLatestMessageForContact(stack.db, p),
      dbUpdateMessageStatus: (id, s) => dbUpdateMessageStatus(stack.db, id, s),
      dbLoadMessage: (id) => dbLoadMessage(stack.db, id),
      dbExistsMessageByContent:
          (contactPeerId, senderPeerId, text, timestamp) =>
              dbExistsMessageByContent(
                stack.db,
                contactPeerId,
                senderPeerId,
                text,
                timestamp,
              ),
      dbCountMessagesForContact: (p) => dbCountMessagesForContact(stack.db, p),
      dbMarkConversationAsRead: (p) => dbMarkConversationAsRead(stack.db, p),
      dbCountUnreadForContact: (p) => dbCountUnreadForContact(stack.db, p),
      dbCountTotalUnread: () => dbCountTotalUnread(stack.db),
      dbCountTotalUnreadExcludingArchived: () =>
          dbCountTotalUnreadExcludingArchived(stack.db),
      dbDeleteMessagesForContact: (p) =>
          dbDeleteMessagesForContact(stack.db, p),
      dbDeleteMessage: (id) => dbDeleteMessage(stack.db, id),
      dbLoadMessagesPage: (p, {limit = 50, beforeTimestamp}) =>
          dbLoadMessagesPage(
            stack.db,
            p,
            limit: limit,
            beforeTimestamp: beforeTimestamp,
          ),
      dbLoadFailedOutgoingMessages: () =>
          dbLoadFailedOutgoingMessages(stack.db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
          dbLoadUnackedOutgoingMessages(
            stack.db,
            olderThan: olderThan,
            limit: limit,
          ),
      dbLoadConversationThreadSummaries: (ids) =>
          dbLoadConversationThreadSummaries(stack.db, ids),
      dbRecoverStuckSendingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbRecoverStuckSendingMessages(
                stack.db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbUpdateWireEnvelope: (id, we) => dbUpdateWireEnvelope(stack.db, id, we),
      dbStageOutgoingOrdinaryAttempt:
          ({required expectedRow, required stagedRow, required kind}) =>
              dbStageOutgoingOrdinaryAttempt(
                stack.db,
                expectedRow: expectedRow,
                stagedRow: stagedRow,
                kind: kind,
              ),
      dbStageOutgoingDirectTextInboxCustody: custodyDb.stage,
      dbLoadDirectInboxCustodyOutbox: custodyDb.load,
      dbLoadDirectInboxCustodyOutboxForMessage: custodyDb.loadForMessage,
      dbRecordDirectInboxCustodyFailureIfExact: custodyDb.recordFailureIfExact,
      dbCompleteAcceptedDirectInboxCustodyIfExact:
          custodyDb.completeAcceptedIfExact,
      dbSettleOutgoingOrdinaryTransport:
          ({
            required messageId,
            required expectedContactPeerId,
            required expectedEnvelope,
            required status,
            required transport,
            required relayExpiresAt,
            required mode,
          }) => dbSettleOutgoingOrdinaryTransport(
            stack.db,
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
            status: status,
            transport: transport,
            relayExpiresAt: relayExpiresAt,
            mode: mode,
          ),
      dbSettleOutgoingOrdinaryDeleteTombstone:
          ({
            required messageId,
            required expectedContactPeerId,
            required expectedEnvelope,
            required status,
            required transport,
            required relayExpiresAt,
            required mode,
          }) => dbSettleOutgoingOrdinaryDeleteTombstone(
            stack.db,
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
            status: status,
            transport: transport,
            relayExpiresAt: relayExpiresAt,
            mode: mode,
          ),
      dbInvalidateOutgoingOrdinaryEnvelope:
          ({
            required messageId,
            required expectedContactPeerId,
            required expectedEnvelope,
          }) => dbInvalidateOutgoingOrdinaryEnvelope(
            stack.db,
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
          ),
      dbQuarantineUnsafeLegacyOutgoingEnvelope:
          ({
            required messageId,
            required expectedContactPeerId,
            required expectedEnvelope,
            required isDeleteTombstone,
          }) => dbQuarantineUnsafeLegacyOutgoingEnvelope(
            stack.db,
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
            isDeleteTombstone: isDeleteTombstone,
          ),
      loadOutgoingOrdinaryMedia: (messageId) => stack.mediaAttachmentRepo
          .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct),
      dbLoadStuckSendingOutgoingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbLoadStuckSendingOutgoingMessages(
                stack.db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbLoadSendingOutgoingMessages: () =>
          dbLoadSendingOutgoingMessages(stack.db),
      dbConditionalTransitionStatus:
          (id, {required fromStatus, required toStatus}) =>
              dbConditionalTransitionStatus(
                stack.db,
                id,
                fromStatus: fromStatus,
                toStatus: toStatus,
              ),
    );

    // ── Identity exchange ──
    _signals.writeJson('alice_identity.json', {
      'peerId': stack.identity.peerId,
      'publicKey': stack.identity.publicKey,
      'mlKemPublicKey': stack.identity.mlKemPublicKey,
    });
    _signals.writeSignal('alice_ready', content: 'ok');
    print('[ALICE-N] Ready — waiting for Bob identity...');

    final bobFixture = await _signals.waitForJson(
      'bob_identity.json',
      timeout: const Duration(seconds: 300),
    );
    final bobPeerId = bobFixture['peerId'] as String;
    final bobMlKemPk = bobFixture['mlKemPublicKey'] as String?;

    await stack.contactRepo.addContact(
      ContactModel(
        peerId: bobPeerId,
        publicKey: bobFixture['publicKey'] as String,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'BobNotif',
        signature: 'sig-bob-notif',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: bobMlKemPk,
      ),
    );
    await _signals.waitForSignal(
      'bob_ready',
      timeout: const Duration(seconds: 300),
    );
    final bobContact = await stack.contactRepo.getContact(bobPeerId);
    if (bobContact == null) {
      throw StateError('Alice failed to persist Bob as contact');
    }

    // ════════════════════════════════════════════════════════════════
    //  S1: 1:1 direct chat
    // ════════════════════════════════════════════════════════════════
    print('\n--- S1: 1:1 send ---');
    await _signals.waitForSignal(
      's1_go',
      timeout: const Duration(seconds: 300),
    );
    final s1Result = await sendChatMessage(
      p2pService: stack.p2pService,
      messageRepo: messageRepo,
      targetPeerId: bobPeerId,
      text: 'S1: notification sound 1:1',
      senderPeerId: stack.identity.peerId,
      senderUsername: stack.identity.username,
      bridge: stack.bridge,
      recipientMlKemPublicKey: bobMlKemPk,
    );
    _signals.writeJson('s1_alice_sent', {'outcome': s1Result.$1.name});
    print('[ALICE-N] S1 sent: ${s1Result.$1.name}');
    await _signals.waitForSignal(
      's1_verdict_ack',
      timeout: const Duration(seconds: 300),
    );

    // ════════════════════════════════════════════════════════════════
    //  S2: Group discussion (GroupType.chat)
    // ════════════════════════════════════════════════════════════════
    print('\n--- S2: Group discussion (chat) create+send ---');
    final chatGroupResult = await createGroupWithMembers(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      p2pService: stack.p2pService,
      identity: stack.identity,
      selectedContacts: [bobContact],
      type: GroupType.chat,
      name: 'Notif Sound Discussion',
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
    );
    final chatGroup = await stack.groupRepo.getGroup(chatGroupResult.group.id);
    final chatKeyInfo = await stack.groupRepo.getLatestKey(
      chatGroupResult.group.id,
    );
    final chatMembers = await stack.groupRepo.getMembers(
      chatGroupResult.group.id,
    );
    _signals.writeJson(
      'group_chat_fixture.json',
      buildGroupFixture(
        group: chatGroup!,
        keyInfo: chatKeyInfo!,
        members: chatMembers,
      ),
    );
    _signals.writeSignal('alice_group_chat_ready', content: 'ok');
    await _signals.waitForSignal(
      'bob_group_chat_joined',
      timeout: const Duration(seconds: 300),
    );
    await stack.groupInviteDeliveryAttemptRepo.markJoined(
      groupId: chatGroup.id,
      peerId: bobPeerId,
      username: 'BobNotif',
    );
    // Let GossipSub peer discovery + mesh form on both sides.
    await Future<void>.delayed(const Duration(seconds: 5));

    await _signals.waitForSignal(
      's2_go',
      timeout: const Duration(seconds: 300),
    );
    final s2Result = await sendGroupMessage(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      groupId: chatGroup.id,
      text: 'S2: notification sound discussion',
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      senderUsername: stack.identity.username,
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
    );
    _signals.writeJson('s2_alice_sent', {'outcome': s2Result.$1.name});
    print('[ALICE-N] S2 sent: ${s2Result.$1.name}');
    await _signals.waitForSignal(
      's2_verdict_ack',
      timeout: const Duration(seconds: 300),
    );

    // ════════════════════════════════════════════════════════════════
    //  S3: Group announcement (GroupType.announcement)
    // ════════════════════════════════════════════════════════════════
    print('\n--- S3: Group announcement create+send ---');
    final annGroupResult = await createGroupWithMembers(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      p2pService: stack.p2pService,
      identity: stack.identity,
      selectedContacts: [bobContact],
      type: GroupType.announcement,
      name: 'Notif Sound Announcement',
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
    );
    final annGroup = await stack.groupRepo.getGroup(annGroupResult.group.id);
    final annKeyInfo = await stack.groupRepo.getLatestKey(
      annGroupResult.group.id,
    );
    final annMembers = await stack.groupRepo.getMembers(
      annGroupResult.group.id,
    );
    _signals.writeJson(
      'group_announcement_fixture.json',
      buildGroupFixture(
        group: annGroup!,
        keyInfo: annKeyInfo!,
        members: annMembers,
      ),
    );
    _signals.writeSignal('alice_group_announcement_ready', content: 'ok');
    await _signals.waitForSignal(
      'bob_group_announcement_joined',
      timeout: const Duration(seconds: 300),
    );
    await stack.groupInviteDeliveryAttemptRepo.markJoined(
      groupId: annGroup.id,
      peerId: bobPeerId,
      username: 'BobNotif',
    );
    await Future<void>.delayed(const Duration(seconds: 5));

    await _signals.waitForSignal(
      's3_go',
      timeout: const Duration(seconds: 300),
    );
    final s3Result = await sendGroupMessage(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      groupId: annGroup.id,
      text: 'S3: notification sound announcement',
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      senderUsername: stack.identity.username,
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
    );
    _signals.writeJson('s3_alice_sent', {'outcome': s3Result.$1.name});
    print('[ALICE-N] S3 sent: ${s3Result.$1.name}');
    await _signals.waitForSignal(
      's3_verdict_ack',
      timeout: const Duration(seconds: 300),
    );

    // ════════════════════════════════════════════════════════════════
    //  S4: Suppression control — Bob is now viewing Alice's 1:1 conversation.
    //       Alice re-sends a 1:1 message; Bob should SUPPRESS.
    // ════════════════════════════════════════════════════════════════
    print('\n--- S4: Suppression control (1:1) ---');
    await _signals.waitForSignal(
      'bob_viewing_conversation',
      timeout: const Duration(seconds: 300),
    );
    await _signals.waitForSignal(
      's4_go',
      timeout: const Duration(seconds: 300),
    );
    final s4Result = await sendChatMessage(
      p2pService: stack.p2pService,
      messageRepo: messageRepo,
      targetPeerId: bobPeerId,
      text: 'S4: should be suppressed',
      senderPeerId: stack.identity.peerId,
      senderUsername: stack.identity.username,
      bridge: stack.bridge,
      recipientMlKemPublicKey: bobMlKemPk,
    );
    _signals.writeJson('s4_alice_sent', {'outcome': s4Result.$1.name});
    print('[ALICE-N] S4 sent: ${s4Result.$1.name}');
    await _signals.waitForSignal(
      's4_verdict_ack',
      timeout: const Duration(seconds: 300),
    );

    // S5-S13: attachment-only image/video/voice notifications across direct,
    // discussion, and announcement lanes. These are real encrypted message
    // sends over the existing P2P/relay stack; only synthetic media descriptors
    // are needed because this campaign proves notification projection rather
    // than blob download/rendering.
    for (final scenario in _mediaNotificationScenarios) {
      final signal = scenario.signal;
      await _signals.waitForSignal(
        '${signal}_go',
        timeout: const Duration(seconds: 300),
      );
      final messageId = 'notification-$_runId-$signal-message';
      final attachment = _mediaAttachmentForScenario(
        scenario,
        messageId: messageId,
      );
      late final String outcome;
      switch (scenario.lane) {
        case _MediaNotificationLane.direct:
          final result = await sendChatMessage(
            p2pService: stack.p2pService,
            messageRepo: messageRepo,
            targetPeerId: bobPeerId,
            text: '',
            senderPeerId: stack.identity.peerId,
            senderUsername: stack.identity.username,
            messageId: messageId,
            preassignedMessageIdIsFresh: true,
            bridge: stack.bridge,
            recipientMlKemPublicKey: bobMlKemPk,
            mediaAttachments: <MediaAttachment>[attachment],
            mediaAttachmentRepo: stack.mediaAttachmentRepo,
          );
          outcome = result.$1.name;
        case _MediaNotificationLane.group:
          final result = await sendGroupMessage(
            bridge: stack.bridge,
            groupRepo: stack.groupRepo,
            msgRepo: stack.groupMsgRepo,
            groupId: chatGroup.id,
            text: '',
            senderPeerId: stack.identity.peerId,
            senderPublicKey: stack.identity.publicKey,
            senderPrivateKey: stack.identity.privateKey,
            senderUsername: stack.identity.username,
            messageId: messageId,
            mediaAttachments: <MediaAttachment>[attachment],
            mediaAttachmentRepo: stack.mediaAttachmentRepo,
            inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
          );
          outcome = result.$1.name;
        case _MediaNotificationLane.announcement:
          final result = await sendGroupMessage(
            bridge: stack.bridge,
            groupRepo: stack.groupRepo,
            msgRepo: stack.groupMsgRepo,
            groupId: annGroup.id,
            text: '',
            senderPeerId: stack.identity.peerId,
            senderPublicKey: stack.identity.publicKey,
            senderPrivateKey: stack.identity.privateKey,
            senderUsername: stack.identity.username,
            messageId: messageId,
            mediaAttachments: <MediaAttachment>[attachment],
            mediaAttachmentRepo: stack.mediaAttachmentRepo,
            inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
          );
          outcome = result.$1.name;
      }
      _signals.writeJson('${signal}_alice_sent', <String, Object?>{
        'outcome': outcome,
        'lane': scenario.lane.name,
        'mediaType': scenario.mediaType,
      });
      print(
        '[ALICE-N] ${scenario.id} ${scenario.lane.name}/'
        '${scenario.mediaType} sent: $outcome',
      );
      await _signals.waitForSignal(
        '${signal}_verdict_ack',
        timeout: const Duration(seconds: 300),
      );
    }

    // ── Done ──
    await _signals.waitForSignal(
      'all_done',
      timeout: const Duration(seconds: 300),
    );
    print('\n[ALICE-N] Complete');
    await stack.teardown();
    _signals.writeSignal('alice_done', content: 'ok');
  }, timeout: const Timeout(Duration(minutes: 35)));
}

// ---------------------------------------------------------------------------
// Bob (Receiver)
// ---------------------------------------------------------------------------

void _runBob() {
  testWidgets('Bob(Notif) — S1..S13', (tester) async {
    print('\n${'═' * 60}');
    print('  BOB (NOTIFICATION SOUND) — SMOKE E2E');
    print('${'═' * 60}\n');

    // ── Mount staging screen so the app is in `resumed` + not viewing any
    //    conversation. Tester requires a widget to be pumped for the app to
    //    render.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            key: Key('staging-screen'),
            child: Text('Staging — awaiting messages'),
          ),
        ),
      ),
    );

    // ── Stack setup (uses setupGroupMultiDeviceStack for DB/P2P/bridge/repos).
    //    The stack wires its own GroupMessageListener with FakeNotificationService
    //    — we dispose it below and rewire with the REAL FlutterNotificationService
    //    so we can verify production behaviour.
    final stack = await setupGroupMultiDeviceStack(
      dbName: _dbName,
      username: 'BobNotif',
      cliPeerFixture: null,
    );
    await waitForOnline(stack.p2pService, timeout: const Duration(seconds: 60));

    // Publish identity before initializing the local notification plugin. On a
    // fresh iOS simulator the permission request can block an unattended run;
    // Alice still waits for bob_ready before sending any scenario messages.
    _signals.writeJson('bob_identity.json', {
      'peerId': stack.identity.peerId,
      'publicKey': stack.identity.publicKey,
      'mlKemPublicKey': stack.identity.mlKemPublicKey,
    });

    // Replace the stack's FakeNotificationService-wired group listener with
    // one that targets the REAL FlutterNotificationService.
    stack.groupListener.dispose();
    final groupMediaAttachmentRepo = _createNotificationGroupMediaRepository(
      stack,
    );

    final recording = _RecordingNotificationService(
      FlutterNotificationService(requestApplePermissions: !_nonInteractive),
    );
    await recording.initialize().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Bob(notif): FlutterNotificationService.initialize() timed out',
      ),
    );
    await recording.clearDeliveredNotifications();
    final NotificationService notificationService = recording;

    final chatConversationTracker = ActiveConversationTracker();
    final groupConversationTracker = ActiveConversationTracker();
    AppLifecycleState currentLifecycle = AppLifecycleState.resumed;

    final realGroupListener = GroupMessageListener(
      groupRepo: stack.groupRepo,
      msgRepo: stack.groupMsgRepo,
      bridge: stack.bridge,
      getSelfPeerId: () async => stack.identity.peerId,
      mediaAttachmentRepo: groupMediaAttachmentRepo,
      notificationService: notificationService,
      groupConversationTracker: groupConversationTracker,
      getAppLifecycleState: () => currentLifecycle,
      inviteDeliveryAttemptRepo: stack.groupInviteDeliveryAttemptRepo,
    );
    realGroupListener.start(stack.groupStreamController.stream);

    // ── 1:1 message repo (not created by setupGroupMultiDeviceStack) ──
    final messageRepo = MessageRepositoryImpl(
      dbInsertMessage: (row) => dbInsertMessage(stack.db, row),
      dbLoadMessagesForContact: (p) => dbLoadMessagesForContact(stack.db, p),
      dbLoadLatestMessageForContact: (p) =>
          dbLoadLatestMessageForContact(stack.db, p),
      dbUpdateMessageStatus: (id, s) => dbUpdateMessageStatus(stack.db, id, s),
      dbLoadMessage: (id) => dbLoadMessage(stack.db, id),
      dbExistsMessageByContent:
          (contactPeerId, senderPeerId, text, timestamp) =>
              dbExistsMessageByContent(
                stack.db,
                contactPeerId,
                senderPeerId,
                text,
                timestamp,
              ),
      dbCountMessagesForContact: (p) => dbCountMessagesForContact(stack.db, p),
      dbMarkConversationAsRead: (p) => dbMarkConversationAsRead(stack.db, p),
      dbCountUnreadForContact: (p) => dbCountUnreadForContact(stack.db, p),
      dbCountTotalUnread: () => dbCountTotalUnread(stack.db),
      dbCountTotalUnreadExcludingArchived: () =>
          dbCountTotalUnreadExcludingArchived(stack.db),
      dbDeleteMessagesForContact: (p) =>
          dbDeleteMessagesForContact(stack.db, p),
      dbDeleteMessage: (id) => dbDeleteMessage(stack.db, id),
      dbLoadMessagesPage: (p, {limit = 50, beforeTimestamp}) =>
          dbLoadMessagesPage(
            stack.db,
            p,
            limit: limit,
            beforeTimestamp: beforeTimestamp,
          ),
      dbLoadFailedOutgoingMessages: () =>
          dbLoadFailedOutgoingMessages(stack.db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
          dbLoadUnackedOutgoingMessages(
            stack.db,
            olderThan: olderThan,
            limit: limit,
          ),
      dbLoadConversationThreadSummaries: (ids) =>
          dbLoadConversationThreadSummaries(stack.db, ids),
      dbRecoverStuckSendingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbRecoverStuckSendingMessages(
                stack.db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbUpdateWireEnvelope: (id, we) => dbUpdateWireEnvelope(stack.db, id, we),
      dbLoadStuckSendingOutgoingMessages:
          ({required DateTime olderThan, int limit = 50}) =>
              dbLoadStuckSendingOutgoingMessages(
                stack.db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbLoadSendingOutgoingMessages: () =>
          dbLoadSendingOutgoingMessages(stack.db),
      dbConditionalTransitionStatus:
          (id, {required fromStatus, required toStatus}) =>
              dbConditionalTransitionStatus(
                stack.db,
                id,
                fromStatus: fromStatus,
                toStatus: toStatus,
              ),
    );

    // ── 1:1 chat listener wired to the REAL notification service ──
    final chatListener = ChatMessageListener(
      chatMessageStream: stack.p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: stack.contactRepo,
      bridge: stack.bridge,
      getOwnMlKemSecretKey: () async => stack.identity.mlKemSecretKey,
      mediaAttachmentRepo: stack.mediaAttachmentRepo,
      notificationService: notificationService,
      conversationTracker: chatConversationTracker,
      getAppLifecycleState: () => currentLifecycle,
    );
    chatListener.start();

    // ── Identity exchange ──
    print('[BOB-N] Identity written, waiting for Alice...');

    final aliceFixture = await _signals.waitForJson(
      'alice_identity.json',
      timeout: const Duration(seconds: 300),
    );
    final alicePeerId = aliceFixture['peerId'] as String;

    await stack.contactRepo.addContact(
      ContactModel(
        peerId: alicePeerId,
        publicKey: aliceFixture['publicKey'] as String,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'AliceNotif',
        signature: 'sig-alice-notif',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: aliceFixture['mlKemPublicKey'] as String?,
      ),
    );
    print('[BOB-N] Alice added as contact');

    _signals.writeSignal('bob_ready', content: 'ok');

    // Helpers — verdict is derived from the recording wrapper's call log.
    // "Shown" = showMessageNotification was called; "Suppressed" = the
    // maybeShowNotification gate short-circuited (no call recorded). For
    // an expect-shown scenario we wait up to 30s for the wrapper to grow;
    // for an expect-suppressed scenario we wait a short settling window
    // and then confirm no call was recorded.
    Future<void> waitForShown({
      required int baselineCount,
      Duration timeout = const Duration(seconds: 30),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (recording.shown.length > baselineCount) return;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    Map<String, dynamic> buildVerdict({
      required String scenarioId,
      required String state,
      required int baselineCount,
      required bool expectSuppressed,
      String? expectedContactPeerId,
      String? expectedSenderUsername,
      String? expectedMessageText,
      String? expectedPayload,
      String? expectedPayloadPrefix,
    }) {
      final calls = recording.shown.sublist(baselineCount);
      final call = calls.length == 1 ? calls.single : null;
      final contactMatches =
          expectedContactPeerId == null ||
          call?.contactPeerId == expectedContactPeerId;
      final senderMatches =
          expectedSenderUsername == null ||
          call?.senderUsername == expectedSenderUsername;
      final bodyMatches =
          expectedMessageText == null ||
          call?.messageText == expectedMessageText;
      final payloadMatches =
          (expectedPayload == null || call?.payload == expectedPayload) &&
          (expectedPayloadPrefix == null ||
              (call?.payload?.startsWith(expectedPayloadPrefix) ?? false));
      final programmaticPass = expectSuppressed
          ? calls.isEmpty
          : call != null &&
                contactMatches &&
                senderMatches &&
                bodyMatches &&
                payloadMatches;
      return {
        'scenarioId': scenarioId,
        'state': state,
        'expectSuppressed': expectSuppressed,
        'expectedContactPeerId': expectedContactPeerId,
        'expectedSenderUsername': expectedSenderUsername,
        'expectedMessageText': expectedMessageText,
        'expectedPayload': expectedPayload,
        'expectedPayloadPrefix': expectedPayloadPrefix,
        'notificationShown': calls.isNotEmpty,
        'notificationSuppressed': expectSuppressed && calls.isEmpty,
        'programmaticPass': programmaticPass,
        'shownCount': calls.length,
        'duplicateCount': calls.length > 1 ? calls.length - 1 : 0,
        'contactMatches': contactMatches,
        'senderMatches': senderMatches,
        'bodyMatches': bodyMatches,
        'payloadMatches': payloadMatches,
        'shownCalls': calls.map((s) => s.toJson()).toList(),
      };
    }

    // ════════════════════════════════════════════════════════════════
    //  S1: 1:1 direct chat — foreground, off-conversation → should NOTIFY
    // ════════════════════════════════════════════════════════════════
    print('\n--- S1: 1:1 direct chat ---');
    // Capture baseline BEFORE the signal wait — the notification may fire
    // between Alice writing the signal and Bob observing it, so reading
    // after the wait would double-count.
    final s1Baseline = recording.shown.length;
    await _signals.waitForSignal(
      's1_alice_sent',
      timeout: const Duration(seconds: 300),
    );
    await waitForShown(baselineCount: s1Baseline);
    final s1Verdict = buildVerdict(
      scenarioId: 'S1',
      state: 'foreground_off_conversation',
      baselineCount: s1Baseline,
      expectSuppressed: false,
      expectedContactPeerId: alicePeerId,
      expectedSenderUsername: 'AliceNotif',
      expectedMessageText: 'S1: notification sound 1:1',
      expectedPayload: alicePeerId,
    );
    _signals.writeJson('s1_bob_verdict', s1Verdict);
    print(
      '[BOB-N] S1 verdict: pass=${s1Verdict['programmaticPass']} '
      'shown=${s1Verdict['notificationShown']} '
      'count=${s1Verdict['shownCount']}',
    );
    await _signals.waitForSignal(
      's1_verdict_ack',
      timeout: const Duration(seconds: 300),
    );
    await notificationService.clearDeliveredNotifications();

    // ════════════════════════════════════════════════════════════════
    //  S2: Group discussion (GroupType.chat) → should NOTIFY
    // ════════════════════════════════════════════════════════════════
    print('\n--- S2: Group discussion ---');
    await _signals.waitForSignal(
      'alice_group_chat_ready',
      timeout: const Duration(seconds: 300),
    );
    final chatGroupFixture = await _signals.waitForJson(
      'group_chat_fixture.json',
      timeout: const Duration(seconds: 300),
    );
    final chatGroupId = await importJoinedGroupFixture(
      stack: stack,
      fixture: chatGroupFixture,
    );
    print('[BOB-N] Joined chat group: ${chatGroupId.substring(0, 16)}...');
    // Give GossipSub peer discovery + connection a few seconds.
    await Future<void>.delayed(const Duration(seconds: 5));
    _signals.writeSignal('bob_group_chat_joined', content: 'ok');

    final s2Baseline = recording.shown.length;
    await _signals.waitForSignal(
      's2_alice_sent',
      timeout: const Duration(seconds: 300),
    );
    await waitForShown(baselineCount: s2Baseline);
    final s2Verdict = buildVerdict(
      scenarioId: 'S2',
      state: 'foreground_off_conversation',
      baselineCount: s2Baseline,
      expectSuppressed: false,
      expectedContactPeerId: 'group:$chatGroupId',
      expectedSenderUsername: 'Notif Sound Discussion',
      expectedMessageText: 'AliceNotif: S2: notification sound discussion',
      expectedPayloadPrefix: 'group:$chatGroupId|message:',
    );
    _signals.writeJson('s2_bob_verdict', s2Verdict);
    print(
      '[BOB-N] S2 verdict: pass=${s2Verdict['programmaticPass']} '
      'count=${s2Verdict['shownCount']}',
    );
    await _signals.waitForSignal(
      's2_verdict_ack',
      timeout: const Duration(seconds: 300),
    );
    await notificationService.clearDeliveredNotifications();

    // ════════════════════════════════════════════════════════════════
    //  S3: Group announcement (GroupType.announcement) → should NOTIFY
    // ════════════════════════════════════════════════════════════════
    print('\n--- S3: Group announcement ---');
    await _signals.waitForSignal(
      'alice_group_announcement_ready',
      timeout: const Duration(seconds: 300),
    );
    final annGroupFixture = await _signals.waitForJson(
      'group_announcement_fixture.json',
      timeout: const Duration(seconds: 300),
    );
    final annGroupId = await importJoinedGroupFixture(
      stack: stack,
      fixture: annGroupFixture,
    );
    print(
      '[BOB-N] Joined announcement group: ${annGroupId.substring(0, 16)}...',
    );
    await Future<void>.delayed(const Duration(seconds: 5));
    _signals.writeSignal('bob_group_announcement_joined', content: 'ok');

    final s3Baseline = recording.shown.length;
    await _signals.waitForSignal(
      's3_alice_sent',
      timeout: const Duration(seconds: 300),
    );
    await waitForShown(baselineCount: s3Baseline);
    final s3Verdict = buildVerdict(
      scenarioId: 'S3',
      state: 'foreground_off_conversation',
      baselineCount: s3Baseline,
      expectSuppressed: false,
      expectedContactPeerId: 'group:$annGroupId',
      expectedSenderUsername: 'Notif Sound Announcement',
      expectedMessageText: 'AliceNotif: S3: notification sound announcement',
      expectedPayloadPrefix: 'group:$annGroupId|message:',
    );
    _signals.writeJson('s3_bob_verdict', s3Verdict);
    print(
      '[BOB-N] S3 verdict: pass=${s3Verdict['programmaticPass']} '
      'count=${s3Verdict['shownCount']}',
    );
    await _signals.waitForSignal(
      's3_verdict_ack',
      timeout: const Duration(seconds: 300),
    );
    await notificationService.clearDeliveredNotifications();

    // ════════════════════════════════════════════════════════════════
    //  S4: Suppression control — Bob simulates viewing Alice's 1:1
    //       conversation. Expected: NOTIFICATION_SUPPRESSED, no NOTIFICATION_SHOWN.
    // ════════════════════════════════════════════════════════════════
    print('\n--- S4: Suppression control ---');
    chatConversationTracker.setActive(alicePeerId);
    _signals.writeSignal('bob_viewing_conversation', content: 'ok');

    final s4Baseline = recording.shown.length;
    await _signals.waitForSignal(
      's4_alice_sent',
      timeout: const Duration(seconds: 300),
    );
    // For the suppression case, wait a short settling window so any rogue
    // showMessageNotification call has time to fire — then assert none did.
    await Future<void>.delayed(const Duration(seconds: 6));
    final s4Verdict = buildVerdict(
      scenarioId: 'S4',
      state: 'foreground_viewing_conversation',
      baselineCount: s4Baseline,
      expectSuppressed: true,
      expectedContactPeerId: alicePeerId,
    );
    _signals.writeJson('s4_bob_verdict', s4Verdict);
    print(
      '[BOB-N] S4 verdict: pass=${s4Verdict['programmaticPass']} '
      'suppressed=${s4Verdict['notificationSuppressed']} '
      'count=${s4Verdict['shownCount']}',
    );

    await _signals.waitForSignal(
      's4_verdict_ack',
      timeout: const Duration(seconds: 300),
    );
    await notificationService.clearDeliveredNotifications();

    chatConversationTracker.clear();

    for (final scenario in _mediaNotificationScenarios) {
      final signal = scenario.signal;
      final expectedAttachment = _mediaAttachmentForScenario(
        scenario,
        messageId: 'notification-$_runId-$signal-message',
      );
      final expectedLabel = notificationBodyForMessage('', <MediaAttachment>[
        expectedAttachment,
      ]);
      late final String expectedContactPeerId;
      late final String expectedSenderUsername;
      late final String expectedMessageText;
      String? expectedPayload;
      String? expectedPayloadPrefix;
      switch (scenario.lane) {
        case _MediaNotificationLane.direct:
          expectedContactPeerId = alicePeerId;
          expectedSenderUsername = 'AliceNotif';
          expectedMessageText = expectedLabel;
          expectedPayload = alicePeerId;
        case _MediaNotificationLane.group:
          expectedContactPeerId = 'group:$chatGroupId';
          expectedSenderUsername = 'Notif Sound Discussion';
          expectedMessageText = 'AliceNotif: $expectedLabel';
          expectedPayloadPrefix = 'group:$chatGroupId|message:';
        case _MediaNotificationLane.announcement:
          expectedContactPeerId = 'group:$annGroupId';
          expectedSenderUsername = 'Notif Sound Announcement';
          expectedMessageText = 'AliceNotif: $expectedLabel';
          expectedPayloadPrefix = 'group:$annGroupId|message:';
      }

      final baseline = recording.shown.length;
      await _signals.waitForSignal(
        '${signal}_alice_sent',
        timeout: const Duration(seconds: 300),
      );
      await waitForShown(
        baselineCount: baseline,
        timeout: const Duration(seconds: 60),
      );
      final verdict =
          buildVerdict(
              scenarioId: scenario.id,
              state: 'foreground_off_conversation_media',
              baselineCount: baseline,
              expectSuppressed: false,
              expectedContactPeerId: expectedContactPeerId,
              expectedSenderUsername: expectedSenderUsername,
              expectedMessageText: expectedMessageText,
              expectedPayload: expectedPayload,
              expectedPayloadPrefix: expectedPayloadPrefix,
            )
            ..['lane'] = scenario.lane.name
            ..['mediaType'] = scenario.mediaType
            ..['mime'] = scenario.mime
            ..['expectedMediaLabel'] = expectedLabel;
      _signals.writeJson('${signal}_bob_verdict', verdict);
      print(
        '[BOB-N] ${scenario.id} ${scenario.lane.name}/'
        '${scenario.mediaType} verdict: pass=${verdict['programmaticPass']} '
        'count=${verdict['shownCount']}',
      );
      await _signals.waitForSignal(
        '${signal}_verdict_ack',
        timeout: const Duration(seconds: 300),
      );
      await notificationService.clearDeliveredNotifications();
    }

    // ── Done ──
    await _signals.waitForSignal(
      'all_done',
      timeout: const Duration(seconds: 300),
    );
    print('\n[BOB-N] All scenarios complete');

    chatListener.dispose();
    realGroupListener.dispose();
    notificationService.dispose();
    await stack.teardown();
    _signals.writeSignal('bob_done', content: 'ok');
  }, timeout: const Timeout(Duration(minutes: 35)));
}
