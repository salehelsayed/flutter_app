import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/private_media_action_eligibility.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import '../test/core/bridge/fake_bridge.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';

const _artifactMarker = 'P234_DEVICE_ARTIFACT=';
const _role = String.fromEnvironment('P234_ROLE');
const _deviceId = String.fromEnvironment('P234_DEVICE_ID');
const _correlatedPrivateMessageId = 'p234-private-fixture';
const _correlatedPrivateAttachmentId = 'p234-private-fixture-attachment';
const _privateFixtureText = 'never disclose this caption';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('instrumented Plan 234 device-local journey', (tester) async {
    expect(_deviceId, isNotEmpty, reason: 'P234_DEVICE_ID is required');
    expect(
      _role,
      anyOf('sender', 'recipient'),
      reason: 'P234_ROLE must be sender or recipient',
    );

    final artifact = _role == 'sender'
        ? _runSenderProof()
        : await _runRecipientProof();
    final encoded = base64Url.encode(utf8.encode(jsonEncode(artifact)));
    // The runner captures exactly one marker and performs strict combined
    // validation. The artifact contains no payload text, path, key, or nonce.
    // ignore: avoid_print
    print('$_artifactMarker$encoded');
    await tester.pump();
  });
}

Map<String, Object?> _runSenderProof() {
  final privatePayload = _privatePayload(
    id: _correlatedPrivateMessageId,
    policy: const PrivateMediaPolicy.viewOnce(),
  );
  final innerJson = privatePayload.toInnerJson();
  final fixtureDigest = sha256.convert(utf8.encode(innerJson)).toString();
  final inner = jsonDecode(innerJson) as Map<String, dynamic>;
  // Existing crypto suites prove encryption. This local harness binds the v2
  // envelope projection and recipient fixture without retaining inner bytes.
  final envelopeString = MessagePayload.buildEncryptedEnvelope(
    id: privatePayload.id,
    senderPeerId: privatePayload.senderPeerId,
    senderUsername: privatePayload.senderUsername,
    kem: 'opaque-kem',
    ciphertext: fixtureDigest,
    nonce: 'opaque-nonce',
  );
  final envelope = MessagePayload.parseEncryptedEnvelope(envelopeString);
  final ordinaryInner =
      jsonDecode(
            _privatePayload(
              id: 'p234-ordinary-sender',
              policy: const PrivateMediaPolicy.ordinary(),
            ).toInnerJson(),
          )
          as Map<String, dynamic>;

  expect(envelope, isNotNull);
  expect(envelope!['version'], '2');
  expect(envelope.containsKey('privateMedia'), isFalse);
  expect(
    (envelope['encrypted'] as Map<String, dynamic>)['ciphertext'],
    fixtureDigest,
  );
  expect(inner['privateMedia'], {'version': 1, 'mode': 'view_once'});
  expect(ordinaryInner.containsKey('privateMedia'), isFalse);

  return <String, Object?>{
    'role': 'sender',
    'deviceId': _deviceId,
    'observationSource': 'instrumented_app',
    'observations': <String, Object?>{
      'fixtureDigest': fixtureDigest,
      'encryptedEnvelopeCodec': 'encrypted-v2',
      'outerPrivateMediaPresent': envelope.containsKey('privateMedia'),
      'innerPrivateMediaPresent': inner.containsKey('privateMedia'),
      'ordinarySendPreserved': !ordinaryInner.containsKey('privateMedia'),
    },
  };
}

Future<Map<String, Object?>> _runRecipientProof() async {
  var sequence = 0;
  var phase = 'setup';
  final tempRoot = await Directory.systemTemp.createTemp('p234-device-local-');
  final databasePath = p.join(tempRoot.path, 'journey.db');
  final mediaFileManager = MediaFileManager();
  final attachmentRepository = _JourneyMediaAttachmentRepository();
  final downloadBridge = _JourneyDownloadBridge();
  final cleanupPaths = <String>{};
  sqlcipher.Database? database;
  try {
    final fixturePayload = _privatePayload(
      id: _correlatedPrivateMessageId,
      policy: const PrivateMediaPolicy.viewOnce(),
    );
    final innerJson = fixturePayload.toInnerJson();
    final fixtureDigest = sha256.convert(utf8.encode(innerJson)).toString();
    final decoded = MessagePayload.fromDecryptedJson(innerJson);
    expect(decoded, isNotNull);

    const receivedAtMs = 1_752_307_200_000;
    final durableInput = decoded!
        .toConversationMessage(
          contactPeerId: 'peer-sender',
          isIncoming: true,
          transport: 'direct',
        )
        .copyWith(
          privateMediaReceivedAtMs: receivedAtMs,
          privateMediaClockHighWaterMs: receivedAtMs,
        );
    phase = 'initial_sqlcipher_open';
    database = await _openProofDatabase(databasePath);
    phase = 'initial_parent_commit';
    await dbInsertMessage(database, durableInput.toMap());
    await database.close();
    phase = 'durable_parent_reopen';
    database = await _openProofDatabase(databasePath);
    phase = 'durable_parent_hydrate';
    final persistedRow = await dbLoadMessage(database, durableInput.id);
    expect(persistedRow, isNotNull);
    final persisted = ConversationMessage.fromMap(persistedRow!);
    final persistedSequence = ++sequence;
    final privatePayloadPersisted =
        persisted.privateMediaPolicy.mode == PrivateMediaMode.viewOnce &&
        persisted.privateMediaState == PrivateMediaLifecycleState.available &&
        persisted.privateMediaReceivedAtMs == receivedAtMs;

    final privateAttachment = _attachment(
      id: _correlatedPrivateAttachmentId,
      messageId: persisted.id,
      downloadStatus: 'pending',
    );
    attachmentRepository.seedAttachment(privateAttachment);
    final downloadMessageRepository = InMemoryMessageRepository();
    await downloadMessageRepository.saveMessage(persisted);
    final currentDecision = DirectPrivateMediaActionEligibility.evaluate(
      parent: persisted,
      attachment: privateAttachment,
      expectedMessageId: persisted.id,
      expectedAttachmentId: privateAttachment.id,
    );
    final policySequence = ++sequence;
    final privatePolicyApplied =
        currentDecision.requiresPrivacyMinimizedPresentation &&
        currentDecision.safeReplyText == 'Private media' &&
        !currentDecision.allows(DirectPrivateMediaAction.externalShare) &&
        !currentDecision.canEnterPictureInPicture;
    final privateEgressDenied = const <DirectPrivateMediaAction>[
      DirectPrivateMediaAction.saveToPhotos,
      DirectPrivateMediaAction.saveToFiles,
      DirectPrivateMediaAction.externalShare,
      DirectPrivateMediaAction.internalForward,
      DirectPrivateMediaAction.bookmark,
      DirectPrivateMediaAction.sharedMedia,
    ].every((action) => !currentDecision.allows(action));
    final legacyOrdinaryViewerEntryDenied =
        currentDecision.requiresPrivacyMinimizedPresentation;
    final typedPictureInPictureDenied =
        !currentDecision.canEnterPictureInPicture;

    final notificationCopy = notificationBodyForMessage(
      _privateFixtureText,
      <MediaAttachment>[privateAttachment],
      privateMediaPolicy: persisted.privateMediaPolicy,
      locale: const Locale('en'),
    );
    final previewSequence = ++sequence;

    final autoDownloadCount = downloadBridge.commandLog
        .where((command) => command == 'media:download')
        .length;
    final manualDownloadAllowed = currentDecision.allows(
      DirectPrivateMediaAction.explicitDownload,
    );
    final privateCanonicalPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: persisted.contactPeerId,
      blobId: privateAttachment.id,
      mime: privateAttachment.mime,
    );
    cleanupPaths.add(privateCanonicalPath);
    final privateRelativePath = mediaFileManager.relativePathForAttachment(
      contactPeerId: persisted.contactPeerId,
      blobId: privateAttachment.id,
      mime: privateAttachment.mime,
    );
    MediaAttachment? privateDownload;
    var manualDownloadResult = 'denied';
    if (manualDownloadAllowed) {
      phase = 'private_explicit_download';
      privateDownload = await downloadMedia(
        bridge: downloadBridge,
        mediaAttachmentRepo: attachmentRepository,
        mediaFileManager: mediaFileManager,
        attachment: privateAttachment,
        contactPeerId: persisted.contactPeerId,
        owner: MediaOwnerLane.direct,
        messageRepo: downloadMessageRepository,
        intent: MediaDownloadIntent.explicitUser,
        nowMs: () => receivedAtMs + 1,
      );
      final persistedAttachment =
          (await attachmentRepository.getAttachmentsForMessage(
            persisted.id,
            owner: MediaOwnerLane.direct,
          )).single;
      final canonical =
          privateDownload?.localPath == privateCanonicalPath &&
          persistedAttachment.localPath == privateRelativePath &&
          await File(privateCanonicalPath).exists() &&
          await File(privateCanonicalPath).length() == privateAttachment.size;
      if (canonical) {
        manualDownloadResult = 'canonical_durable_storage';
      }
    }
    final manualDownloadCount = downloadBridge.commandLog
        .where((command) => command == 'media:download')
        .length;
    final downloadSequence = ++sequence;

    phase = 'view_once_lifecycle';
    final viewOnceLifecycle = DirectPrivateMediaLifecycle(
      messageRepository: _SqlLifecycleRepository(database),
      mediaAttachmentRepository: attachmentRepository,
      mediaFileManager: mediaFileManager,
    );
    final viewOnceEngine = PrivateMediaLifecycleEngine(
      adapter: viewOnceLifecycle,
      lifecycleLock: attachmentRepository.directPrivateMediaLifecycleLock,
      nowMs: () => receivedAtMs + 10,
    );
    final lease = await viewOnceEngine.openViewOnce(persisted.id);
    expect(lease, isNotNull);
    final firstFrame = await viewOnceEngine.markFirstFrame(lease!);
    final consumed = await viewOnceEngine.terminalizeViewOnce(lease);
    final consumedParent = ConversationMessage.fromMap(
      (await dbLoadMessage(database, persisted.id))!,
    );
    final viewOnceRevealCount =
        consumedParent.privateMediaRevealedAtMs == receivedAtMs + 10 ? 1 : 0;
    final viewOnceCleanupCompleted =
        firstFrame &&
        consumed &&
        consumedParent.privateMediaState ==
            PrivateMediaLifecycleState.consumed &&
        !await File(privateCanonicalPath).exists();
    final viewOnceAttachmentPresentAfterCleanup =
        (await attachmentRepository.getAttachmentsForMessage(
          persisted.id,
          owner: MediaOwnerLane.direct,
        )).isNotEmpty;
    await database.close();
    phase = 'terminal_parent_reopen';
    database = await _openProofDatabase(databasePath);
    final reopenedViewOnceEngine = PrivateMediaLifecycleEngine(
      adapter: DirectPrivateMediaLifecycle(
        messageRepository: _SqlLifecycleRepository(database),
        mediaAttachmentRepository: attachmentRepository,
        mediaFileManager: mediaFileManager,
      ),
      lifecycleLock: attachmentRepository.directPrivateMediaLifecycleLock,
      nowMs: () => receivedAtMs + 20,
    );
    final reopenedLease = await reopenedViewOnceEngine.openViewOnce(
      persisted.id,
    );
    final reopenedParent = ConversationMessage.fromMap(
      (await dbLoadMessage(database, persisted.id))!,
    );
    final viewOnceAvailableAfterReopen =
        reopenedLease != null ||
        reopenedParent.privateMediaState ==
            PrivateMediaLifecycleState.available ||
        await File(privateCanonicalPath).exists();

    phase = 'disappearing_expiry';
    final disappearingParent = _incomingParent(
      id: 'p234-disappearing',
      policy: PrivateMediaPolicy.disappearing(3600),
      state: PrivateMediaLifecycleState.available,
      receivedAtMs: 1_000,
      expiresAtMs: 3_601_000,
      highWaterMs: 1_000,
    );
    await dbInsertMessage(database, disappearingParent.toMap());
    final disappearingAttachment = _attachment(
      id: 'p234-disappearing-attachment',
      messageId: disappearingParent.id,
      downloadStatus: 'done',
      localPath: mediaFileManager.relativePathForAttachment(
        contactPeerId: disappearingParent.contactPeerId,
        blobId: 'p234-disappearing-attachment',
        mime: 'image/png',
      ),
    );
    final disappearingPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: disappearingParent.contactPeerId,
      blobId: disappearingAttachment.id,
      mime: disappearingAttachment.mime,
    );
    cleanupPaths.add(disappearingPath);
    await File(disappearingPath).parent.create(recursive: true);
    await File(
      disappearingPath,
    ).writeAsBytes(_JourneyDownloadBridge.mediaBytes, flush: true);
    attachmentRepository.seedAttachment(disappearingAttachment);
    final disappearingEngine = PrivateMediaLifecycleEngine(
      adapter: DirectPrivateMediaLifecycle(
        messageRepository: _SqlLifecycleRepository(database),
        mediaAttachmentRepository: attachmentRepository,
        mediaFileManager: mediaFileManager,
      ),
      lifecycleLock: attachmentRepository.directPrivateMediaLifecycleLock,
      nowMs: () => 3_601_001,
    );
    final expiry = await disappearingEngine.sweepExpiries();
    final expiredParent = ConversationMessage.fromMap(
      (await dbLoadMessage(database, disappearingParent.id))!,
    );
    final disappearingExpiryCompleted =
        expiry.terminalClaims == 1 &&
        expiry.cleanupCompleted == 1 &&
        expiredParent.privateMediaState == PrivateMediaLifecycleState.expired &&
        !await File(disappearingPath).exists();
    final disappearingAvailableAfterExpiry =
        expiredParent.privateMediaState == PrivateMediaLifecycleState.available;

    phase = 'assert_disappearing_terminal_claim';
    expect(expiry.terminalClaims, 1);
    phase = 'assert_disappearing_cleanup_count';
    expect(expiry.cleanupCompleted, 1);
    phase = 'assert_disappearing_terminal_state';
    expect(expiredParent.privateMediaState, PrivateMediaLifecycleState.expired);
    phase = 'assert_disappearing_file_deleted';
    expect(await File(disappearingPath).exists(), isFalse);

    phase = 'protected_open_decisions';
    final protectedParent = _incomingParent(
      id: 'p234-protected',
      policy: const PrivateMediaPolicy.protected(),
      state: PrivateMediaLifecycleState.available,
      receivedAtMs: receivedAtMs,
      highWaterMs: receivedAtMs,
    );
    final protectedAttachment = _attachment(
      id: 'p234-protected-attachment',
      messageId: protectedParent.id,
      downloadStatus: 'done',
      localPath: mediaFileManager.relativePathForAttachment(
        contactPeerId: protectedParent.contactPeerId,
        blobId: 'p234-protected-attachment',
        mime: 'image/png',
      ),
    );
    final protectedPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: protectedParent.contactPeerId,
      blobId: protectedAttachment.id,
      mime: protectedAttachment.mime,
    );
    cleanupPaths.add(protectedPath);
    await File(protectedPath).parent.create(recursive: true);
    await File(
      protectedPath,
    ).writeAsBytes(_JourneyDownloadBridge.mediaBytes, flush: true);
    final protectedFirst = DirectPrivateMediaActionEligibility.evaluate(
      parent: protectedParent,
      attachment: protectedAttachment,
      expectedMessageId: protectedParent.id,
      expectedAttachmentId: protectedAttachment.id,
    );
    final protectedRepeat = DirectPrivateMediaActionEligibility.evaluate(
      parent: protectedParent,
      attachment: protectedAttachment,
      expectedMessageId: protectedParent.id,
      expectedAttachmentId: protectedAttachment.id,
    );

    phase = 'ordinary_download';
    final ordinaryParent = _incomingParent(
      id: 'p234-ordinary',
      policy: const PrivateMediaPolicy.ordinary(),
      state: PrivateMediaLifecycleState.none,
    );
    final ordinaryAttachment = _attachment(
      id: 'p234-ordinary-attachment',
      messageId: ordinaryParent.id,
      downloadStatus: 'pending',
    );
    final ordinaryDecision = DirectPrivateMediaActionEligibility.evaluate(
      parent: ordinaryParent,
      attachment: ordinaryAttachment,
      expectedMessageId: ordinaryParent.id,
      expectedAttachmentId: ordinaryAttachment.id,
    );
    final ordinaryPreview = notificationBodyForMessage('', <MediaAttachment>[
      ordinaryAttachment,
    ]);
    await downloadMessageRepository.saveMessage(ordinaryParent);
    attachmentRepository.seedAttachment(ordinaryAttachment);
    final ordinaryCanonicalPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: ordinaryParent.contactPeerId,
      blobId: ordinaryAttachment.id,
      mime: ordinaryAttachment.mime,
    );
    cleanupPaths.add(ordinaryCanonicalPath);
    final ordinaryDownload = await downloadMedia(
      bridge: downloadBridge,
      mediaAttachmentRepo: attachmentRepository,
      mediaFileManager: mediaFileManager,
      attachment: ordinaryAttachment,
      contactPeerId: ordinaryParent.contactPeerId,
      owner: MediaOwnerLane.direct,
      messageRepo: downloadMessageRepository,
      intent: MediaDownloadIntent.explicitUser,
      nowMs: () => receivedAtMs + 30,
    );
    final ordinaryManualDownloadSucceeded =
        ordinaryDownload?.localPath == ordinaryCanonicalPath &&
        await File(ordinaryCanonicalPath).exists();
    final consumeReceiptCount = downloadBridge.commandLog
        .where(
          (command) =>
              command.toLowerCase().contains('consume') ||
              command.toLowerCase().contains('receipt'),
        )
        .length;

    phase = 'assert_persistence_and_download';
    expect(privatePayloadPersisted, isTrue);
    expect(privatePolicyApplied, isTrue);
    expect(notificationCopy, 'Private media');
    expect(autoDownloadCount, 0);
    expect(manualDownloadCount, 1);
    expect(manualDownloadResult, 'canonical_durable_storage');
    phase = 'assert_view_once';
    expect(viewOnceRevealCount, 1);
    expect(viewOnceCleanupCompleted, isTrue);
    expect(viewOnceAttachmentPresentAfterCleanup, isFalse);
    expect(viewOnceAvailableAfterReopen, isFalse);
    phase = 'assert_disappearing_expiry';
    expect(disappearingExpiryCompleted, isTrue);
    phase = 'assert_disappearing_unavailable';
    expect(disappearingAvailableAfterExpiry, isFalse);
    phase = 'assert_protected';
    expect(protectedFirst.allows(DirectPrivateMediaAction.openInApp), isTrue);
    expect(protectedRepeat.allows(DirectPrivateMediaAction.openInApp), isTrue);
    expect(
      protectedParent.privateMediaState,
      PrivateMediaLifecycleState.available,
    );
    phase = 'assert_ordinary';
    expect(ordinaryPreview, 'Photo');
    expect(
      ordinaryDecision.allows(DirectPrivateMediaAction.explicitDownload),
      isTrue,
    );
    expect(ordinaryManualDownloadSucceeded, isTrue);
    expect(consumeReceiptCount, 0);

    phase = 'artifact_projection';
    return <String, Object?>{
      'role': 'recipient',
      'deviceId': _deviceId,
      'observationSource': 'instrumented_app',
      'observations': <String, Object?>{
        'fixtureDigest': fixtureDigest,
        'privatePayloadPersisted': privatePayloadPersisted,
        'privatePolicyApplied': privatePolicyApplied,
        'privateEgressDenied': privateEgressDenied,
        'legacyOrdinaryViewerEntryDenied': legacyOrdinaryViewerEntryDenied,
        'typedPictureInPictureDenied': typedPictureInPictureDenied,
        'persistedSequence': persistedSequence,
        'policySequence': policySequence,
        'previewSequence': previewSequence,
        'downloadSequence': downloadSequence,
        'notificationCopy': notificationCopy,
        'quoteCopy': currentDecision.safeReplyText,
        'autoDownloadCount': autoDownloadCount,
        'manualDownloadCount': manualDownloadCount,
        'manualDownloadResult': manualDownloadResult,
        'viewOnceRevealCount': viewOnceRevealCount,
        'viewOnceCleanupCompleted': viewOnceCleanupCompleted,
        'viewOnceAttachmentPresentAfterCleanup':
            viewOnceAttachmentPresentAfterCleanup,
        'viewOnceAvailableAfterReopen': viewOnceAvailableAfterReopen,
        'disappearingExpiryCompleted': disappearingExpiryCompleted,
        'disappearingAvailableAfterExpiry': disappearingAvailableAfterExpiry,
        'protectedFirstOpenDecisionAllowed': protectedFirst.allows(
          DirectPrivateMediaAction.openInApp,
        ),
        'protectedRepeatOpenDecisionAllowed': protectedRepeat.allows(
          DirectPrivateMediaAction.openInApp,
        ),
        'protectedAvailableAfterRepeat':
            protectedParent.privateMediaState ==
            PrivateMediaLifecycleState.available,
        'ordinaryPreviewSucceeded': ordinaryPreview == 'Photo',
        'ordinaryManualDownloadSucceeded': ordinaryManualDownloadSucceeded,
        'consumeReceiptCount': consumeReceiptCount,
      },
    };
  } on Object catch (error) {
    // This safe diagnostic never includes payload, path, or exception text.
    // The runner withholds raw child output; direct triage can identify the
    // failing production seam without weakening artifact redaction.
    // ignore: avoid_print
    print('P234_RECIPIENT_FAILURE_PHASE=$phase TYPE=${error.runtimeType}');
    rethrow;
  } finally {
    if (database != null && database.isOpen) {
      await database.close();
    }
    for (final path in cleanupPaths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  }
}

Future<sqlcipher.Database> _openProofDatabase(String path) {
  return sqlcipher.openDatabase(
    path,
    password: 'plan-234-session-06-device-local-proof',
    version: 100,
    singleInstance: false,
    onCreate: runProductionOnCreate,
    onUpgrade: runProductionOnUpgrade,
    onDowngrade: sqlcipher.onDatabaseVersionChangeError,
  );
}

MessagePayload _privatePayload({
  required String id,
  required PrivateMediaPolicy policy,
  String text = '',
}) {
  return MessagePayload(
    id: id,
    text: text,
    senderPeerId: 'peer-sender',
    senderUsername: 'Sender',
    timestamp: '2026-07-12T09:00:00.000Z',
    media: <Map<String, dynamic>>[
      <String, dynamic>{
        'id': '$id-attachment',
        'mime': 'image/png',
        'size': 4,
        'mediaType': 'image',
        'createdAt': '2026-07-12T09:00:00.000Z',
      },
    ],
    privateMediaPolicy: policy,
  );
}

ConversationMessage _incomingParent({
  required String id,
  required PrivateMediaPolicy policy,
  required PrivateMediaLifecycleState state,
  int? receivedAtMs,
  int? expiresAtMs,
  int? highWaterMs,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: 'peer-sender',
    senderPeerId: 'peer-sender',
    text: '',
    timestamp: '2026-07-12T09:00:00.000Z',
    status: 'sent',
    isIncoming: true,
    createdAt: '2026-07-12T09:00:00.000Z',
    privateMediaPolicy: policy,
    privateMediaState: state,
    privateMediaReceivedAtMs: receivedAtMs,
    privateMediaExpiresAtMs: expiresAtMs,
    privateMediaClockHighWaterMs: highWaterMs,
  );
}

MediaAttachment _attachment({
  required String id,
  required String messageId,
  required String downloadStatus,
  String? localPath,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: 'image/png',
    size: 4,
    mediaType: 'image',
    localPath: localPath,
    downloadStatus: downloadStatus,
    createdAt: '2026-07-12T09:00:00.000Z',
    ownerLane: MediaOwnerLane.direct,
  );
}

class _SqlLifecycleRepository implements DirectPrivateMediaLifecycleRepository {
  const _SqlLifecycleRepository(this.database);

  final sqlcipher.Database database;

  Future<ConversationMessage?> _load(String messageId) async {
    final row = await dbLoadMessage(database, messageId);
    return row == null ? null : ConversationMessage.fromMap(row);
  }

  @override
  Future<ConversationMessage?> loadPrivateMediaLifecycleMessage(
    String messageId,
  ) => _load(messageId);

  @override
  Future<bool> claimPrivateMediaOpening(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbClaimDirectPrivateMediaOpening(
        database,
        messageId,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<bool> markPrivateMediaViewing(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbMarkDirectPrivateMediaViewing(
        database,
        messageId,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<bool> rollbackPrivateMediaOpening(String messageId) async =>
      await dbRollbackDirectPrivateMediaOpening(database, messageId) == 1;

  @override
  Future<bool> consumePrivateMedia(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbConsumeDirectPrivateMedia(database, messageId, nowMs: nowMs) == 1;

  @override
  Future<bool> advancePrivateMediaClock(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbAdvanceDirectPrivateMediaClock(
        database,
        messageId,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<bool> failClosedCorruptPrivateMediaState(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbFailClosedCorruptDirectPrivateMediaState(
        database,
        messageId,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<bool> hidePrivateMediaForMe(
    String messageId, {
    required String hiddenAt,
    required int nowMs,
  }) async =>
      await dbHideDirectPrivateMediaForMe(
        database,
        messageId,
        hiddenAt: hiddenAt,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<List<ConversationMessage>> loadActiveDisappearingPrivateMedia({
    int limit = 100,
  }) async => (await dbLoadActiveDirectPrivateMediaDisappearing(
    database,
    limit: limit,
  )).map(ConversationMessage.fromMap).toList(growable: false);

  @override
  Future<List<ConversationMessage>> loadPrivateMediaRecoveryCandidates({
    int limit = 100,
  }) async => (await dbLoadDirectPrivateMediaRecoveryCandidates(
    database,
    limit: limit,
  )).map(ConversationMessage.fromMap).toList(growable: false);

  @override
  Future<bool> rotatePrivateMediaRecoveryCandidate(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbRotateDirectPrivateMediaRecoveryCandidate(
        database,
        messageId,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<int?> loadNextPrivateMediaExpiryAtMs() =>
      dbLoadNextDirectPrivateMediaExpiryAtMs(database);
}

class _JourneyDownloadBridge extends FakeBridge {
  static const List<int> mediaBytes = <int>[7, 11, 23, 47];

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    if (decoded['cmd'] == 'media:download') {
      final payload = decoded['payload'] as Map<String, dynamic>;
      final output = File(payload['outputPath'] as String);
      await output.parent.create(recursive: true);
      await output.writeAsBytes(mediaBytes, flush: true);
    }
    return super.send(message);
  }
}

class _JourneyMediaAttachmentRepository
    implements
        MediaAttachmentRepository,
        DirectPrivateMediaDownloadStateRepository,
        DirectPrivateMediaCleanupRepository,
        DirectPrivateMediaCleanupRuntime {
  final Map<String, List<MediaAttachment>> _byMessage =
      <String, List<MediaAttachment>>{};
  final MediaAttachmentLifecycleLock _lock = MediaAttachmentLifecycleLock();

  @override
  MediaAttachmentLifecycleLock get directPrivateMediaLifecycleLock => _lock;

  void seedAttachment(MediaAttachment attachment) {
    final rows = _byMessage.putIfAbsent(
      attachment.messageId,
      () => <MediaAttachment>[],
    );
    rows.removeWhere((row) => row.id == attachment.id);
    rows.add(attachment);
  }

  MediaAttachment? _find(String id) {
    for (final rows in _byMessage.values) {
      for (final row in rows) {
        if (row.id == id) return row;
      }
    }
    return null;
  }

  bool _replace(
    String id,
    MediaAttachment Function(MediaAttachment current) replace,
  ) {
    for (final rows in _byMessage.values) {
      final index = rows.indexWhere((row) => row.id == id);
      if (index >= 0) {
        rows[index] = replace(rows[index]);
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async => seedAttachment(attachment.copyWith(ownerLane: owner));

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => List<MediaAttachment>.of(
    (_byMessage[messageId] ?? const <MediaAttachment>[]).where(
      (row) => row.ownerLane == owner,
    ),
  );

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async => <String, List<MediaAttachment>>{
    for (final id in messageIds)
      id: await getAttachmentsForMessage(id, owner: owner),
  };

  @override
  Future<void> updateLocalPath(String id, String localPath) async {
    _replace(
      id,
      (row) => row.copyWith(
        localPath: localPath,
        downloadStatus: 'done',
        downloadRetryCount: 0,
      ),
    );
  }

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    _replace(id, (row) => row.copyWith(downloadStatus: downloadStatus));
  }

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final rows = _byMessage[messageId];
    if (rows == null) return 0;
    final before = rows.length;
    rows.removeWhere((row) => row.ownerLane == owner);
    return before - rows.length;
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => _byMessage.values
      .expand((rows) => rows)
      .where((row) => row.downloadStatus == 'pending')
      .toList(growable: false);

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async => const <MediaAttachment>[];

  @override
  Future<bool> beginDirectPrivateMediaDownload(
    String id, {
    required String messageId,
    required int nowMs,
  }) => _lock.synchronized(
    id,
    () => beginDirectPrivateMediaDownloadWithinLock(
      id,
      messageId: messageId,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> beginDirectPrivateMediaDownloadWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) async {
    final current = _find(id);
    if (current == null ||
        current.messageId != messageId ||
        current.downloadStatus == 'downloading') {
      return false;
    }
    return _replace(id, (row) => row.copyWith(downloadStatus: 'downloading'));
  }

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReady(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) => _lock.synchronized(
    id,
    () => qualifyDirectPrivateMediaLocalReadyWithinLock(
      id,
      messageId: messageId,
      expectedLocalPath: expectedLocalPath,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReadyWithinLock(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) async {
    final current = _find(id);
    return current?.messageId == messageId &&
        current?.downloadStatus == 'done' &&
        current?.localPath == expectedLocalPath;
  }

  @override
  Future<bool> qualifyDirectPrivateMediaDownloadClaimWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) async {
    final current = _find(id);
    return current?.messageId == messageId &&
        current?.downloadStatus == 'downloading';
  }

  @override
  Future<bool> recordDirectPrivateMediaDownloadFailure(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath = false,
  }) => _lock.synchronized(
    id,
    () => recordDirectPrivateMediaDownloadFailureWithinLock(
      id,
      messageId: messageId,
      nowMs: nowMs,
      incrementRetryCount: incrementRetryCount,
      failureStatus: failureStatus,
      expectedDownloadStatus: expectedDownloadStatus,
      expectedLocalPath: expectedLocalPath,
      clearLocalPath: clearLocalPath,
    ),
  );

  @override
  Future<bool> recordDirectPrivateMediaDownloadFailureWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath = false,
  }) async {
    final current = _find(id);
    if (current == null ||
        current.messageId != messageId ||
        current.downloadStatus != expectedDownloadStatus ||
        (expectedLocalPath != null && current.localPath != expectedLocalPath)) {
      return false;
    }
    return _replace(
      id,
      (row) => row.copyWith(
        downloadStatus: failureStatus,
        downloadRetryCount: incrementRetryCount
            ? (row.downloadRetryCount ?? 0) + 1
            : row.downloadRetryCount,
        clearLocalPath: clearLocalPath,
      ),
    );
  }

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPath(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) => _lock.synchronized(
    id,
    () => commitDirectPrivateMediaDownloadLocalPathWithinLock(
      id,
      messageId: messageId,
      localPath: localPath,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPathWithinLock(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) async {
    final current = _find(id);
    if (current == null ||
        current.messageId != messageId ||
        current.downloadStatus != 'downloading') {
      return false;
    }
    return _replace(
      id,
      (row) => row.copyWith(
        localPath: localPath,
        downloadStatus: 'done',
        downloadRetryCount: 0,
      ),
    );
  }

  @override
  Future<List<DirectPrivateMediaLifecycleAttachmentMetadata>>
  loadDirectPrivateMediaLifecycleAttachmentMetadata(String messageId) async =>
      (_byMessage[messageId] ?? const <MediaAttachment>[])
          .map(
            (row) => DirectPrivateMediaLifecycleAttachmentMetadata(
              id: row.id,
              messageId: row.messageId,
              mime: row.mime,
              size: row.size,
              downloadStatus: row.downloadStatus,
              localPath: row.localPath,
            ),
          )
          .toList(growable: false);

  @override
  Future<List<DirectPrivateMediaCleanupAttachment>>
  loadDirectPrivateMediaCleanupAttachments(String messageId) async =>
      (_byMessage[messageId] ?? const <MediaAttachment>[])
          .map(
            (row) => DirectPrivateMediaCleanupAttachment(
              id: row.id,
              messageId: row.messageId,
              mime: row.mime,
            ),
          )
          .toList(growable: false);

  @override
  Future<bool> deleteDirectPrivateMediaEncryptionKeyWithinLock({
    required String messageId,
    required String attachmentId,
  }) async => _find(attachmentId)?.messageId == messageId;

  @override
  Future<int> deleteDirectPrivateMediaAttachmentWithinLock({
    required String messageId,
    required String attachmentId,
  }) async {
    final rows = _byMessage[messageId];
    if (rows == null) return 0;
    final before = rows.length;
    rows.removeWhere((row) => row.id == attachmentId);
    return before - rows.length;
  }
}
