import 'dart:io';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/retry_direct_private_committed_pending_cleanup.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

class _FailFirstExactPendingDeleteMediaFileManager extends MediaFileManager {
  _FailFirstExactPendingDeleteMediaFileManager(this.documentsRoot);

  final Directory documentsRoot;
  String? failOncePath;

  @override
  Future<String> trustedMediaRootPath() async =>
      p.join(documentsRoot.path, 'media');

  @override
  Future<String> trustedPendingUploadRootPath() async =>
      p.join(documentsRoot.path, 'pending_uploads');

  @override
  Future<String> resolveStoredPath(String storedPath) async =>
      p.isAbsolute(storedPath)
      ? storedPath
      : p.join(documentsRoot.path, storedPath);

  @override
  Future<void> deleteFile(
    String localPath, {
    String caller = 'MediaFileManager.deleteFile',
    String reason = 'media_file_delete',
    String? storedPath,
    Map<String, Object?> details = const {},
    bool redactTelemetry = false,
  }) async {
    if (localPath == failOncePath) {
      failOncePath = null;
      throw const FileSystemException(
        'injected committed-pending unlink failure',
      );
    }
    await super.deleteFile(
      localPath,
      caller: caller,
      reason: reason,
      storedPath: storedPath,
      details: details,
      redactTelemetry: redactTelemetry,
    );
  }
}

class _CommittedFixtureRows {
  const _CommittedFixtureRows({
    required this.messageId,
    required this.attachmentId,
    required this.pendingRelativePath,
    required this.pendingFile,
    required this.canonicalRelativePath,
    required this.canonicalFile,
    required this.keyName,
  });

  final String messageId;
  final String attachmentId;
  final String pendingRelativePath;
  final File pendingFile;
  final String canonicalRelativePath;
  final File canonicalFile;
  final String keyName;
}

Future<_CommittedFixtureRows> _seedDeliveredCanonicalCompletion({
  required MediaRepositoryRealDbFixture fixture,
  required Directory documentsRoot,
  required String messageId,
  required String attachmentId,
  required String createdAt,
  required String hashCharacter,
}) async {
  const contactPeerId = 'cleanup-contact';
  const mime = 'image/jpeg';
  final bytes = <int>[0xff, 0xd8, 0xff, 0xe0, ...attachmentId.codeUnits];
  final pendingRelativePath =
      MediaFilePathConvention.relativePathForPendingUpload(
        messageId: messageId,
        attachmentId: attachmentId,
        mime: mime,
      );
  final canonicalRelativePath =
      MediaFilePathConvention.relativePathForAttachment(
        contactPeerId: contactPeerId,
        blobId: attachmentId,
        mime: mime,
      );
  final pendingFile = File('${documentsRoot.path}/$pendingRelativePath')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  final canonicalFile = File('${documentsRoot.path}/$canonicalRelativePath')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  final parent = ConversationMessage(
    id: messageId,
    contactPeerId: contactPeerId,
    senderPeerId: 'self-peer',
    text: '',
    timestamp: createdAt,
    status: 'sending',
    isIncoming: false,
    createdAt: createdAt,
    privateMediaPolicy: const PrivateMediaPolicy.protected(),
    privateMediaState: PrivateMediaLifecycleState.available,
  );
  final pending = MediaAttachment(
    id: attachmentId,
    messageId: messageId,
    mime: mime,
    size: bytes.length,
    mediaType: 'image',
    localPath: pendingRelativePath,
    downloadStatus: 'upload_pending',
    createdAt: createdAt,
    ownerLane: MediaOwnerLane.direct,
  );
  await fixture.messageRepo.saveMessage(parent);
  final prepared = await fixture.repo
      .prepareOutgoingDirectPrivatePendingAttachments(<MediaAttachment>[
        pending,
      ]);
  expect(prepared, OutgoingDirectPrivatePendingPreparationOutcome.inserted);

  final committed = pending.copyWith(
    localPath: canonicalRelativePath,
    downloadStatus: 'done',
    contentHash: List<String>.filled(64, hashCharacter).join(),
    encryptionKeyBase64: 'cHJpdmF0ZS1rZXkt$attachmentId',
    encryptionNonce: 'bm9uY2Ut$attachmentId',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  );
  final completion = await fixture.repo.outgoingDirectPrivateMutationCoordinator
      .commitCompletion(
        attachment: committed,
        expectedPendingLocalPath: pendingRelativePath,
      );
  expect(completion.authorizesTransportHandoff, isTrue);
  const envelope = '{"private":"committed"}';
  final handoff = await fixture.messageRepo
      .commitOutgoingDirectPrivateWireEnvelope(
        messageId: messageId,
        completedAttachment: committed,
        expectedPendingLocalPath: pendingRelativePath,
        envelope: envelope,
        hasOwnedPendingCompletion: true,
      );
  expect(handoff.authorizesTransport, isTrue);
  final settlement = await fixture.messageRepo
      .settleOutgoingDirectPrivateTransport(
        messageId: messageId,
        attachmentId: attachmentId,
        expectedEnvelope: envelope,
        status: 'delivered',
        transport: 'direct',
        relayExpiresAt: null,
      );
  expect(settlement, OutgoingDirectPrivateTransportSettlementOutcome.committed);
  expect(
    (await fixture.messageRepo.getMessage(messageId))?.wireEnvelope,
    isNull,
  );

  return _CommittedFixtureRows(
    messageId: messageId,
    attachmentId: attachmentId,
    pendingRelativePath: pendingRelativePath,
    pendingFile: pendingFile,
    canonicalRelativePath: canonicalRelativePath,
    canonicalFile: canonicalFile,
    keyName: mediaAttachmentEncryptionKeyStoreName(attachmentId),
  );
}

void main() {
  setUp(() => flowEventLoggingEnabled = false);
  tearDown(() => flowEventLoggingEnabled = true);

  test(
    'cold/reopen recovery retries exact committed-pending unlink and preserves canonical custody and siblings',
    () async {
      final temp = Directory.systemTemp.createTempSync(
        'committed_pending_recovery_',
      );
      addTearDown(() {
        MediaFileManager.debugResetDocumentsDirCache();
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final documentsRoot = Directory('${temp.path}/documents')
        ..createSync(recursive: true);
      final databasePath = '${temp.path}/identity.sqlite';
      MediaFileManager.cacheDocumentsDir(documentsRoot.path);
      final secureStore = RecordingSecureKeyStore();
      var fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: databasePath,
        secureKeyStore: secureStore,
      );
      var fixtureOpen = true;
      addTearDown(() async {
        if (fixtureOpen) await fixture.dispose();
      });

      final target = await _seedDeliveredCanonicalCompletion(
        fixture: fixture,
        documentsRoot: documentsRoot,
        messageId: 'committed-cleanup-target-message',
        attachmentId: 'committed-cleanup-target-attachment',
        createdAt: '2026-07-20T10:00:00.000Z',
        hashCharacter: 'a',
      );
      final missingKeySibling = await _seedDeliveredCanonicalCompletion(
        fixture: fixture,
        documentsRoot: documentsRoot,
        messageId: 'committed-cleanup-sibling-message',
        attachmentId: 'committed-cleanup-sibling-attachment',
        createdAt: '2026-07-20T09:00:00.000Z',
        hashCharacter: 'b',
      );
      await secureStore.delete(missingKeySibling.keyName);
      final initialCandidates = await fixture.repo
          .loadDirectPrivateCommittedPendingCleanupCandidates(limit: 10);
      expect(initialCandidates, hasLength(1));
      expect(initialCandidates.single.attachmentId, target.attachmentId);
      expect(
        initialCandidates.map((candidate) => candidate.attachmentId),
        isNot(contains(missingKeySibling.attachmentId)),
      );
      final manager = _FailFirstExactPendingDeleteMediaFileManager(
        documentsRoot,
      )..failOncePath = target.pendingFile.path;
      var lifecycle = DirectPrivateMediaLifecycle(
        messageRepository: fixture.messageRepo,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: manager,
      );

      final first = await retryDirectPrivateCommittedPendingCleanup(
        repository: fixture.repo,
        lifecycle: lifecycle,
        limit: 10,
      );
      expect(first.loaded, 1);
      expect(first.cleanedOrAlreadyAbsent, 0);
      expect(first.failed, 1);
      expect(first.refused, 0);
      expect(manager.failOncePath, isNull);
      expect(target.pendingFile.existsSync(), isTrue);
      expect(target.canonicalFile.existsSync(), isTrue);
      expect(missingKeySibling.pendingFile.existsSync(), isTrue);
      expect(missingKeySibling.canonicalFile.existsSync(), isTrue);
      expect(await secureStore.containsKey(target.keyName), isTrue);

      await fixture.dispose();
      fixtureOpen = false;
      fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: databasePath,
        secureKeyStore: secureStore,
      );
      fixtureOpen = true;
      lifecycle = DirectPrivateMediaLifecycle(
        messageRepository: fixture.messageRepo,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: manager,
      );
      final reopenedCandidates = await fixture.repo
          .loadDirectPrivateCommittedPendingCleanupCandidates(limit: 10);
      expect(reopenedCandidates, hasLength(1));
      expect(reopenedCandidates.single.attachmentId, target.attachmentId);
      expect(
        reopenedCandidates.map((candidate) => candidate.attachmentId),
        isNot(contains(missingKeySibling.attachmentId)),
      );
      final second = await retryDirectPrivateCommittedPendingCleanup(
        repository: fixture.repo,
        lifecycle: lifecycle,
        limit: 10,
      );

      expect(second.loaded, 1);
      expect(
        (
          cleaned: second.cleanedOrAlreadyAbsent,
          refused: second.refused,
          failed: second.failed,
        ),
        (cleaned: 1, refused: 0, failed: 0),
      );
      expect(target.pendingFile.existsSync(), isFalse);
      expect(target.canonicalFile.existsSync(), isTrue);
      expect(missingKeySibling.pendingFile.existsSync(), isTrue);
      expect(missingKeySibling.canonicalFile.existsSync(), isTrue);
      expect(await secureStore.containsKey(target.keyName), isTrue);
      expect(await secureStore.containsKey(missingKeySibling.keyName), isFalse);

      final targetRows = await fixture.repo.getAttachmentsForMessage(
        target.messageId,
        owner: MediaOwnerLane.direct,
      );
      final siblingRows = await fixture.repo.getAttachmentsForMessage(
        missingKeySibling.messageId,
        owner: MediaOwnerLane.direct,
      );
      expect(targetRows, hasLength(1));
      expect(targetRows.single.localPath, target.canonicalRelativePath);
      expect(targetRows.single.downloadStatus, 'done');
      expect(targetRows.single.hasEncryptionKeyMaterial, isTrue);
      expect(siblingRows, hasLength(1));
      expect(
        siblingRows.single.localPath,
        missingKeySibling.canonicalRelativePath,
      );
      expect(siblingRows.single.downloadStatus, 'done');
      expect(siblingRows.single.hasEncryptionKeyMaterial, isFalse);
      expect(
        (await fixture.messageRepo.getMessage(target.messageId))?.wireEnvelope,
        isNull,
      );
    },
  );
}
