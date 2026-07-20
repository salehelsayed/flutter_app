import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _contactPeerId = 'contact-262-race';
const _oldKey = 'b2xkLXNlbmRlci1rZXk=';
const _newKey = 'bmV3LXNlbmRlci1rZXk=';
const _oldNonce = 'b2xkLW5vbmNl';
const _newNonce = 'bmV3LW5vbmNl';
const _oldHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _newHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test(
    'shared-runtime completion races atomically with PRE-FRAME rollback',
    () async {
      const messageId = 'p262-registration-first';
      const attachmentId = 'p262-registration-first-att';
      final seeded = await _seedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final startupAdapter = _adapter(fixture);
      final conversationAdapter = _adapter(fixture);
      final harness = _controller(fixture, adapter: conversationAdapter);

      expect(
        identical(
          fixture.repo.lifecycleLock,
          harness.controller.lifecycleEngine.lifecycleLock,
        ),
        isTrue,
        reason: 'startup, viewer, and writers must share the repository lock',
      );
      expect(await startupAdapter.loadTarget(messageId), isNotNull);

      final prepared = await harness.controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(
        prepared.isGranted,
        isTrue,
        reason: 'the RED must be past pending-open qualification',
      );
      expect(await _privateState(fixture, messageId), 'opening');

      final rowBeforeCompletion = Map<String, Object?>.from(
        (await fixture.rawAttachmentRow(attachmentId))!,
      );
      final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
      final keyBeforeCompletion = await fixture.secureKeyStore.read(keyName);
      final completed = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );

      await _runRealIncompleteRetry(fixture, completed);

      expect(await _privateState(fixture, messageId), 'opening');
      expect(
        await fixture.rawAttachmentRow(attachmentId),
        rowBeforeCompletion,
        reason:
            'an upload completion registered during opening must defer with '
            'zero attachment-row mutation',
      );
      expect(
        await fixture.secureKeyStore.read(keyName),
        keyBeforeCompletion,
        reason: 'deferred completion must not rotate the live secure key',
      );
      expect(
        await harness.controller.revalidateForLifecycleEvent(prepared.grant!),
        isTrue,
      );

      final settlement = await harness.controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.preFrameDecodeFailure,
      );
      expect(
        settlement.disposition,
        DirectPrivateMediaSettleDisposition.rolledBackAvailable,
      );
      expect(await _privateState(fixture, messageId), 'available');
      _expectCompletedFingerprint(
        (await fixture.rawAttachmentRow(attachmentId))!,
        completed,
      );
      expect(await fixture.secureKeyStore.read(keyName), _newKey);
      expect(
        File(seeded.pendingAbsolute).existsSync(),
        isFalse,
        reason:
            'settlement after transfer release must reclaim the redundant '
            'pending source once the deferred completion commits',
      );
    },
  );

  test(
    'PRE-FRAME rollback winning first permits one direct completion',
    () async {
      const messageId = 'p262-settlement-first';
      const attachmentId = 'p262-settlement-first-att';
      await _seedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final harness = _controller(fixture);
      const identity = DirectPrivateMediaViewerIdentity(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final prepared = await harness.controller.prepareResult(
        identity,
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(
        prepared.isGranted,
        isTrue,
        reason: 'the order sentinel must begin from a real pending lease',
      );
      final settlement = await harness.controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.preFrameDecodeFailure,
      );
      expect(
        settlement.disposition,
        DirectPrivateMediaSettleDisposition.rolledBackAvailable,
      );

      final completed = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      await _runRealIncompleteRetry(fixture, completed);

      expect(await _privateState(fixture, messageId), 'available');
      _expectCompletedFingerprint(
        (await fixture.rawAttachmentRow(attachmentId))!,
        completed,
      );
      expect(
        await fixture.secureKeyStore.read(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        _newKey,
      );

      final reopened = await harness.controller.prepareResult(
        identity,
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(reopened.isGranted, isTrue);
      await harness.controller.settle(
        reopened.grant!,
        DirectPrivateMediaExitReason.preFrameDecodeFailure,
      );
    },
  );

  test(
    'deferred completion is discarded by FIRST-FRAME terminal settlement and late writers cannot reinsert',
    () async {
      const messageId = 'p262-terminal-late-writer';
      const attachmentId = 'p262-terminal-late-writer-att';
      await _seedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      await fixture.db.update(
        'messages',
        <String, Object?>{'wire_envelope': '{"p262":"durable"}'},
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      );
      final harness = _controller(fixture);
      final prepared = await harness.controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(
        prepared.isGranted,
        isTrue,
        reason: 'the RED must be past pending-open qualification',
      );
      expect(await harness.controller.markFirstFrame(prepared.grant!), isTrue);
      final settlement = await harness.controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.close,
      );
      expect(
        settlement.disposition,
        DirectPrivateMediaSettleDisposition.terminalized,
      );
      expect(await _privateState(fixture, messageId), 'consumed');
      expect(await fixture.rawAttachmentRow(attachmentId), isNull);
      final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
      expect(await fixture.secureKeyStore.containsKey(keyName), isFalse);

      await fixture.repo.saveAttachment(
        _completedAttachment(messageId: messageId, attachmentId: attachmentId),
        owner: MediaOwnerLane.direct,
      );

      expect(
        await fixture.rawAttachmentRow(attachmentId),
        isNull,
        reason: 'a late fallback completion cannot resurrect terminal media',
      );
      expect(await fixture.secureKeyStore.containsKey(keyName), isFalse);
      expect(await _privateState(fixture, messageId), 'consumed');
    },
  );

  test(
    'FIRST-FRAME before envelope converts deferred completion to transport-only custody',
    () async {
      const messageId = 'p262-terminal-before-envelope';
      const attachmentId = 'p262-terminal-before-envelope-att';
      final seeded = await _seedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final completed = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final harness = _controller(fixture);
      final prepared = await harness.controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(prepared.isGranted, isTrue);

      // Upload completion loses the attachment lock to the active viewer and
      // is retained only in the shared coordinator.
      await fixture.repo.saveAttachment(
        completed,
        owner: MediaOwnerLane.direct,
      );
      expect(
        (await fixture.rawAttachmentRow(attachmentId))?['download_status'],
        'upload_pending',
      );

      expect(await harness.controller.markFirstFrame(prepared.grant!), isTrue);
      final settlement = await harness.controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.close,
      );
      expect(
        settlement.disposition,
        DirectPrivateMediaSettleDisposition.terminalized,
      );
      expect(await _privateState(fixture, messageId), 'consumed');
      expect(await fixture.rawAttachmentRow(attachmentId), isNotNull);
      expect(File(seeded.pendingAbsolute).existsSync(), isTrue);

      final owned = await fixture.repo.outgoingDirectPrivateMutationCoordinator
          .loadOwnedCompletionFingerprint(
            messageId: messageId,
            attachmentId: attachmentId,
            expectedPendingLocalPath: seeded.pendingRelative,
          );
      expect(
        owned?.matchesHydratedAttachment(completed),
        isTrue,
        reason:
            'terminal cleanup must retain exact transport authority until '
            'the completed upload is durably handed off',
      );

      final handoff = await fixture.messageRepo
          .commitOutgoingDirectPrivateWireEnvelope(
            messageId: messageId,
            completedAttachment: completed,
            expectedPendingLocalPath: seeded.pendingRelative,
            envelope: '{"p262":"terminal-before-envelope"}',
            hasOwnedPendingCompletion: true,
          );
      expect(handoff.authorizesTransport, isTrue);

      expect(
        await harness.controller.lifecycleEngine.cleanupTerminalMessage(
          messageId,
        ),
        isTrue,
      );
      expect(await fixture.rawAttachmentRow(attachmentId), isNull);
      expect(File(seeded.pendingAbsolute).existsSync(), isFalse);
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isFalse,
      );
    },
  );

  test(
    'failed atomic rollback/finalize never reports available and restores the old key',
    () async {
      const messageId = 'p262-atomic-finalize-abort';
      const attachmentId = 'p262-atomic-finalize-abort-att';
      await _seedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final harness = _controller(fixture);
      final prepared = await harness.controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(
        prepared.isGranted,
        isTrue,
        reason: 'the RED must be past pending-open qualification',
      );
      final oldRow = Map<String, Object?>.from(
        (await fixture.rawAttachmentRow(attachmentId))!,
      );
      final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);

      await fixture.db.execute('''
        CREATE TEMP TRIGGER p262_abort_completion
        BEFORE UPDATE ON media_attachments
        WHEN OLD.id = '$attachmentId'
          AND NEW.download_status = 'done'
        BEGIN
          SELECT RAISE(ABORT, 'p262 injected finalize abort');
        END
      ''');

      await _runRealIncompleteRetry(
        fixture,
        _completedAttachment(messageId: messageId, attachmentId: attachmentId),
      );
      expect(await _privateState(fixture, messageId), 'opening');
      expect(await fixture.rawAttachmentRow(attachmentId), oldRow);
      expect(await fixture.secureKeyStore.read(keyName), _oldKey);

      final settlement = await harness.controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.preFrameDecodeFailure,
      );

      expect(
        settlement.disposition,
        isNot(DirectPrivateMediaSettleDisposition.rolledBackAvailable),
        reason:
            'rollback and completion must be one transaction; a failed '
            'finalize cannot expose available with the old pending row',
      );
      expect(await _privateState(fixture, messageId), isNot('available'));
    },
  );

  test(
    'pending deletion is lifecycle-locked and never races a pending-path lease',
    () async {
      const messageId = 'p262-locked-pending-delete';
      const attachmentId = 'p262-locked-pending-delete-att';
      final seeded = await _seedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final harness = _controller(fixture);
      final prepared = await harness.controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(
        prepared.isGranted,
        isTrue,
        reason: 'the deletion RED must begin behind a real pending-path lease',
      );

      final siblingMessageId = '$messageId-sibling';
      final siblingPath = p.join(
        FakeMediaFileManager.testRootPath,
        'pending_uploads',
        siblingMessageId,
        'unrelated.jpg',
      );
      _writeBytes(siblingPath, const <int>[9, 8, 7]);
      final deleteAttempts = <String>[];
      final fileManager = FakeMediaFileManager()
        ..onDeletePendingUploadDir = (candidateMessageId) {
          deleteAttempts.add(candidateMessageId);
          final directory = Directory(
            p.join(
              FakeMediaFileManager.testRootPath,
              'pending_uploads',
              candidateMessageId,
            ),
          );
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        };

      await _runRealIncompleteRetry(
        fixture,
        _completedAttachment(messageId: messageId, attachmentId: attachmentId),
        mediaFileManager: fileManager,
      );

      final deleteAttemptsWhileLeased = List<String>.of(deleteAttempts);
      final pendingFileSurvived = File(seeded.pendingAbsolute).existsSync();
      final siblingFileSurvived = File(siblingPath).existsSync();
      final rowStatusWhileLeased = (await fixture.rawAttachmentRow(
        attachmentId,
      ))?['download_status'];
      final leaseStillValid = await harness.controller
          .revalidateForLifecycleEvent(prepared.grant!);
      await harness.controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.preFrameDecodeFailure,
      );

      expect(
        deleteAttemptsWhileLeased,
        isEmpty,
        reason:
            'the incomplete-retry cleanup caller must not issue a raw '
            'pending-directory delete while the exact lease is active',
      );
      expect(pendingFileSurvived, isTrue);
      expect(siblingFileSurvived, isTrue);
      expect(rowStatusWhileLeased, 'upload_pending');
      expect(leaseStillValid, isTrue);
    },
  );

  test(
    'upload failure projection cannot rewrite an attachment under an opening lease',
    () async {
      const messageId = 'p262-failure-writer-guard';
      const attachmentId = 'p262-failure-writer-guard-att';
      final seeded = await _seedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final harness = _controller(fixture);
      final prepared = await harness.controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(
        prepared.isGranted,
        isTrue,
        reason: 'the raw-writer RED must be past pending-open qualification',
      );
      final rowBefore = Map<String, Object?>.from(
        (await fixture.rawAttachmentRow(attachmentId))!,
      );
      final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
      final keyBefore = await fixture.secureKeyStore.read(keyName);

      await _runRealIncompleteRetry(
        fixture,
        _completedAttachment(messageId: messageId, attachmentId: attachmentId),
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              blobId,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async => const UploadMediaFailed(
              stage: UploadMediaStage.transport,
              disposition: UploadMediaDisposition.terminal,
              errorCode: 'P262_INJECTED_UPLOAD_FAILURE',
            ),
      );

      final rowAfterFailure = await fixture.rawAttachmentRow(attachmentId);
      final keyAfterFailure = await fixture.secureKeyStore.read(keyName);
      final stateAfterFailure = await _privateState(fixture, messageId);
      final pendingFileSurvived = File(seeded.pendingAbsolute).existsSync();
      final leaseStillValid = await harness.controller
          .revalidateForLifecycleEvent(prepared.grant!);
      await harness.controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.preFrameDecodeFailure,
      );

      expect(rowAfterFailure, rowBefore);
      expect(keyAfterFailure, keyBefore);
      expect(stateAfterFailure, 'opening');
      expect(pendingFileSurvived, isTrue);
      expect(
        leaseStillValid,
        isTrue,
        reason:
            'failure projection must report a non-applied active-lease result, '
            'not mutate upload_pending to upload_failed',
      );
    },
  );

  test(
    'real private incomplete retry preserves transfer and durable outbox custody',
    () async {
      const messageId = 'p262-real-retrier-custody';
      const attachmentId = 'p262-real-retrier-custody-att';
      const staleEnvelope = '{"p262":"stale-before-key-rotation"}';
      final seeded = await _seedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        wireEnvelope: staleEnvelope,
      );
      final completed = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final harness = _controller(fixture);

      final initialLockHeld = Completer<void>();
      final releaseInitialLock = Completer<void>();
      final initialLockFuture = fixture.repo.lifecycleLock.synchronized(
        attachmentId,
        () async {
          initialLockHeld.complete();
          await releaseInitialLock.future;
        },
      );
      await initialLockHeld.future;

      final uploadStarted = Completer<void>();
      final uploadProbeComplete = Completer<void>();
      final releaseUpload = Completer<void>();
      var registryClaimedBeforeRead = false;
      var staleEnvelopeClearedBeforeRead = false;
      var lifecycleLockReleasedDuringIo = false;
      final p2pService = _BlockingReuseP2PService();
      final fileManager = FakeMediaFileManager();
      final retryFuture = _runRealIncompleteRetry(
        fixture,
        completed,
        mediaFileManager: fileManager,
        p2pService: p2pService,
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              blobId,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async {
              uploadStarted.complete();
              registryClaimedBeforeRead = directPrivateMediaTransferRegistry
                  .isActive(attachmentId);
              staleEnvelopeClearedBeforeRead =
                  await _wireEnvelope(fixture, messageId) == null;

              final competingLockAcquired = Completer<void>();
              final competingLock = Zone.root.run(
                () => fixture.repo.lifecycleLock.synchronized(
                  attachmentId,
                  () async => competingLockAcquired.complete(),
                ),
              );
              try {
                await competingLockAcquired.future.timeout(
                  const Duration(seconds: 1),
                );
                lifecycleLockReleasedDuringIo = true;
              } on TimeoutException {
                lifecycleLockReleasedDuringIo = false;
              }
              if (!uploadProbeComplete.isCompleted) {
                uploadProbeComplete.complete();
              }
              await releaseUpload.future;
              await competingLock;
              return UploadMediaSucceeded(completed);
            },
      );

      await Future.any<void>(<Future<void>>[
        uploadStarted.future,
        Future<void>.delayed(const Duration(milliseconds: 100)),
      ]);
      final uploadEnteredWhileLifecycleLockHeld = uploadStarted.isCompleted;
      final registryClaimedWhileLifecycleLockHeld =
          directPrivateMediaTransferRegistry.isActive(attachmentId);
      releaseInitialLock.complete();
      await initialLockFuture;
      await uploadStarted.future.timeout(const Duration(seconds: 2));
      await uploadProbeComplete.future.timeout(const Duration(seconds: 2));

      final prepared = await harness.controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      final pendingFileSurvivedBlockedIo = File(
        seeded.pendingAbsolute,
      ).existsSync();
      releaseUpload.complete();

      final reachedDurableEnvelopeBarrier =
          await Future.any<bool>(<Future<bool>>[
            p2pService.sendEntered.future.then((_) => true),
            retryFuture.then((_) => false),
          ]).timeout(const Duration(seconds: 5), onTimeout: () => false);

      Map<String, Object?>? rowWhileDeferred;
      String? envelopeWhileDeferred;
      var registryHeldThroughEnvelope = false;
      var firstFrameMarked = false;
      DirectPrivateMediaSettleResult? terminalSettlement;
      var rowSurvivedTerminalWhileTransferActive = false;
      var fileSurvivedTerminalWhileTransferActive = false;
      if (reachedDurableEnvelopeBarrier) {
        rowWhileDeferred = await fixture.rawAttachmentRow(attachmentId);
        envelopeWhileDeferred = await _wireEnvelope(fixture, messageId);
        registryHeldThroughEnvelope = directPrivateMediaTransferRegistry
            .isActive(attachmentId);
        if (prepared.isGranted) {
          firstFrameMarked = await harness.controller.markFirstFrame(
            prepared.grant!,
          );
          terminalSettlement = await harness.controller.settle(
            prepared.grant!,
            DirectPrivateMediaExitReason.close,
          );
        }
        rowSurvivedTerminalWhileTransferActive =
            await fixture.rawAttachmentRow(attachmentId) != null;
        fileSurvivedTerminalWhileTransferActive = File(
          seeded.pendingAbsolute,
        ).existsSync();
        p2pService.releaseSend.complete();
      } else if (prepared.isGranted) {
        await harness.controller.settle(
          prepared.grant!,
          DirectPrivateMediaExitReason.preFrameDecodeFailure,
        );
      }
      final retryCount = await retryFuture.timeout(const Duration(seconds: 5));

      expect(registryClaimedBeforeRead, isTrue);
      expect(uploadEnteredWhileLifecycleLockHeld, isFalse);
      expect(registryClaimedWhileLifecycleLockHeld, isFalse);
      expect(staleEnvelopeClearedBeforeRead, isTrue);
      expect(lifecycleLockReleasedDuringIo, isTrue);
      expect(prepared.isGranted, isTrue);
      expect(pendingFileSurvivedBlockedIo, isTrue);
      expect(reachedDurableEnvelopeBarrier, isTrue);
      expect(registryHeldThroughEnvelope, isTrue);
      expect(rowWhileDeferred?['local_path'], seeded.pendingRelative);
      expect(rowWhileDeferred?['download_status'], 'upload_pending');
      expect(envelopeWhileDeferred, isNotNull);
      expect(envelopeWhileDeferred, isNot(staleEnvelope));
      expect(firstFrameMarked, isTrue);
      expect(
        terminalSettlement?.disposition,
        DirectPrivateMediaSettleDisposition.terminalized,
      );
      expect(rowSurvivedTerminalWhileTransferActive, isTrue);
      expect(fileSurvivedTerminalWhileTransferActive, isTrue);
      expect(retryCount, 1);
      expect(
        directPrivateMediaTransferRegistry.isActive(attachmentId),
        isFalse,
      );
      expect(await _privateState(fixture, messageId), 'consumed');
      expect(await fixture.rawAttachmentRow(attachmentId), isNull);
      expect(File(seeded.pendingAbsolute).existsSync(), isFalse);
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isFalse,
      );
      expect(await _wireEnvelope(fixture, messageId), isNotNull);
    },
  );

  test(
    'stale-envelope invalidation failure aborts before first read',
    () async {
      const messageId = 'p262-stale-envelope-abort';
      const attachmentId = 'p262-stale-envelope-abort-att';
      const staleEnvelope = '{"p262":"must-not-be-read-through"}';
      final seeded = await _seedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        wireEnvelope: staleEnvelope,
      );
      await fixture.db.execute('''
      CREATE TEMP TRIGGER p262_abort_stale_envelope_clear
      BEFORE UPDATE OF wire_envelope ON messages
      WHEN OLD.id = '$messageId'
        AND OLD.wire_envelope IS NOT NULL
        AND NEW.wire_envelope IS NULL
      BEGIN
        SELECT RAISE(ABORT, 'p262 injected envelope invalidation abort');
      END
    ''');
      var readCount = 0;

      await _runRealIncompleteRetry(
        fixture,
        _completedAttachment(messageId: messageId, attachmentId: attachmentId),
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              blobId,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async {
              readCount++;
              return UploadMediaSucceeded(
                _completedAttachment(
                  messageId: messageId,
                  attachmentId: attachmentId,
                ),
              );
            },
      );

      expect(readCount, 0);
      expect(await _wireEnvelope(fixture, messageId), staleEnvelope);
      expect(
        (await fixture.rawAttachmentRow(attachmentId))?['download_status'],
        'upload_pending',
      );
      expect(File(seeded.pendingAbsolute).existsSync(), isTrue);
      expect(
        directPrivateMediaTransferRegistry.isActive(attachmentId),
        isFalse,
      );
    },
  );

  test(
    'committed private retry removes only its exact redundant pending source',
    () async {
      const messageId = 'p262-private-committed-cleanup';
      const attachmentId = 'p262-private-committed-cleanup-att';
      final seeded = await _seedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final siblingPath = p.join(
        p.dirname(seeded.pendingAbsolute),
        'unrelated-sibling.bin',
      );
      _writeBytes(siblingPath, const <int>[9, 8, 7]);
      final completed = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );

      final retried = await _runRealIncompleteRetry(
        fixture,
        completed,
        mediaFileManager: FakeMediaFileManager(),
      );

      final row = await fixture.rawAttachmentRow(attachmentId);
      expect(retried, 1);
      expect(row?['download_status'], 'done');
      expect(row?['local_path'], completed.localPath);
      expect(File(seeded.pendingAbsolute).existsSync(), isFalse);
      expect(File(siblingPath).existsSync(), isTrue);
      expect(
        directPrivateMediaTransferRegistry.isActive(attachmentId),
        isFalse,
      );
    },
  );

  test(
    'ordinary incomplete retry retains its generic upload cleanup',
    () async {
      const messageId = 'p262-ordinary-control';
      const attachmentId = 'p262-ordinary-control-att';
      await _seedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        isPrivate: false,
      );
      var registryActiveDuringRead = false;
      final deleteAttempts = <String>[];
      final fileManager = FakeMediaFileManager()
        ..onDeletePendingUploadDir = deleteAttempts.add;
      final completed = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );

      final retried = await _runRealIncompleteRetry(
        fixture,
        completed,
        mediaFileManager: fileManager,
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              blobId,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async {
              registryActiveDuringRead = directPrivateMediaTransferRegistry
                  .isActive(attachmentId);
              return UploadMediaSucceeded(completed);
            },
      );

      expect(retried, 1);
      expect(registryActiveDuringRead, isFalse);
      expect(deleteAttempts, <String>[messageId]);
      expect(
        (await fixture.rawAttachmentRow(attachmentId))?['download_status'],
        'done',
      );
    },
  );
}

Future<({String pendingRelative, String pendingAbsolute})> _seedPending(
  MediaRepositoryRealDbFixture fixture, {
  required String messageId,
  required String attachmentId,
  bool isPrivate = true,
  String? wireEnvelope,
}) async {
  await fixture.seedDirectParent(messageId, contactPeerId: _contactPeerId);
  await fixture.db.update(
    'messages',
    <String, Object?>{
      'sender_peer_id': 'self-peer',
      'text': isPrivate ? '' : 'ordinary pending upload',
      'status': 'sending',
      'is_incoming': 0,
      'wire_envelope': wireEnvelope,
      'private_media_policy_version': isPrivate ? 1 : 0,
      'private_media_mode': isPrivate ? 'protected' : 'ordinary',
      'private_media_state': isPrivate ? 'available' : 'none',
      'private_media_received_at_ms': isPrivate ? 1000 : null,
      'private_media_clock_high_water_ms': isPrivate ? 1000 : null,
      'private_media_revealed_at_ms': null,
      'private_media_terminal_at_ms': null,
    },
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
  );
  final pendingRelative = 'pending_uploads/$messageId/$attachmentId.jpg';
  final pendingAbsolute = p.join(
    FakeMediaFileManager.testRootPath,
    pendingRelative,
  );
  _writeBytes(pendingAbsolute, const <int>[1, 2, 3, 4]);
  final pendingAttachment = MediaAttachment(
    id: attachmentId,
    messageId: messageId,
    mime: 'image/jpeg',
    size: 4,
    mediaType: 'image',
    width: 1,
    height: 1,
    localPath: pendingRelative,
    downloadStatus: 'upload_pending',
    createdAt: '2026-07-20T00:00:00.000Z',
    contentHash: _oldHash,
    encryptionKeyBase64: _oldKey,
    encryptionNonce: _oldNonce,
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    ownerLane: MediaOwnerLane.direct,
  );
  if (isPrivate) {
    // This fixture models an already-failed upload with an older complete
    // crypto fingerprint. First durable prep intentionally cannot create it.
    final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
    await fixture.secureKeyStore.write(keyName, _oldKey);
    try {
      await fixture.db.insert(
        'media_attachments',
        pendingAttachment
            .copyWith(encryptionKeyBase64: secureStoreReferenceForKey(keyName))
            .toMap(),
      );
    } catch (_) {
      await fixture.secureKeyStore.delete(keyName);
      rethrow;
    }
  } else {
    await fixture.repo.saveAttachment(
      pendingAttachment,
      owner: MediaOwnerLane.direct,
    );
  }
  return (pendingRelative: pendingRelative, pendingAbsolute: pendingAbsolute);
}

MediaAttachment _completedAttachment({
  required String messageId,
  required String attachmentId,
}) {
  final canonicalRelative = 'media/$_contactPeerId/$attachmentId.jpg';
  _writeBytes(
    p.join(FakeMediaFileManager.testRootPath, canonicalRelative),
    const <int>[1, 2, 3, 4],
  );
  return MediaAttachment(
    id: attachmentId,
    messageId: messageId,
    mime: 'image/jpeg',
    size: 4,
    mediaType: 'image',
    width: 1,
    height: 1,
    localPath: canonicalRelative,
    downloadStatus: 'done',
    createdAt: '2026-07-20T00:00:00.000Z',
    contentHash: _newHash,
    encryptionKeyBase64: _newKey,
    encryptionNonce: _newNonce,
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    ownerLane: MediaOwnerLane.direct,
  );
}

Future<int> _runRealIncompleteRetry(
  MediaRepositoryRealDbFixture fixture,
  MediaAttachment completed, {
  UploadMediaFn? uploadMediaFn,
  FakeMediaFileManager? mediaFileManager,
  FakeP2PService? p2pService,
}) async {
  final identityRepo = FakeIdentityRepository()
    ..seed(
      FakeIdentityRepository.makeIdentity(
        peerId: 'self-peer',
        mlKemPublicKey: 'self-ml-kem-public',
        mlKemSecretKey: 'self-ml-kem-secret',
      ),
    );
  final contactRepo = FakeContactRepository()
    ..seed(<ContactModel>[
      ContactModel(
        peerId: _contactPeerId,
        publicKey: 'contact-public-key',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'P262 Contact',
        signature: 'contact-signature',
        scannedAt: '2026-07-20T00:00:00.000Z',
        mlKemPublicKey: 'contact-ml-kem-public',
      ),
    ]);
  return retryIncompleteUploads(
    mediaAttachmentRepo: fixture.repo,
    messageRepo: fixture.messageRepo,
    bridge: FakeBridge(),
    p2pService:
        p2pService ??
        FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'self-peer',
            circuitAddresses: <String>['/p2p-circuit/p262'],
          ),
          storeInInboxResult: true,
        ),
    identityRepo: identityRepo,
    contactRepo: contactRepo,
    mediaFileManager: mediaFileManager ?? FakeMediaFileManager(),
    uploadMediaFn:
        uploadMediaFn ??
        ({
          required bridge,
          required localFilePath,
          required mime,
          required recipientPeerId,
          mediaFileManager,
          width,
          height,
          durationMs,
          waveform,
          allowedPeers,
          blobId,
          deleteSourceWhenDone = false,
          preparedArtifact,
        }) async => UploadMediaSucceeded(completed),
  );
}

Future<String?> _wireEnvelope(
  MediaRepositoryRealDbFixture fixture,
  String messageId,
) async {
  final rows = await fixture.db.query(
    'messages',
    columns: const <String>['wire_envelope'],
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
  );
  return rows.single['wire_envelope'] as String?;
}

DirectPrivateMediaLifecycle _adapter(MediaRepositoryRealDbFixture fixture) =>
    DirectPrivateMediaLifecycle(
      messageRepository: fixture.messageRepo,
      mediaAttachmentRepository: fixture.repo,
      mediaFileManager: FakeMediaFileManager(),
    );

_ControllerHarness _controller(
  MediaRepositoryRealDbFixture fixture, {
  DirectPrivateMediaLifecycle? adapter,
}) {
  final effectiveAdapter = adapter ?? _adapter(fixture);
  final engine = PrivateMediaLifecycleEngine(
    adapter: effectiveAdapter,
    lifecycleLock: fixture.repo.lifecycleLock,
    nowMs: () => 5000,
  );
  final nativeEvents = StreamController<Object?>.broadcast();
  final coordinator = PrivateMediaProtectionCoordinator(
    invokeMethod: (method, arguments) async => <String, Object?>{
      'ok': true,
      'protectionActive': method == 'enter',
    },
    nativeEvents: nativeEvents.stream,
  );
  final controller = DirectPrivateMediaViewerController(
    loadCurrentRows: (identity) async {
      final parent = await fixture.messageRepo.loadPrivateMediaLifecycleMessage(
        identity.messageId,
      );
      final attachments = await fixture.repo.getAttachmentsForMessage(
        identity.messageId,
        owner: MediaOwnerLane.direct,
      );
      final exact = attachments
          .where((attachment) => attachment.id == identity.attachmentId)
          .toList(growable: false);
      return DirectPrivateMediaCurrentRows(
        parent: parent,
        attachment: exact.length == 1 ? exact.single : null,
      );
    },
    lifecycleEngine: engine,
    protectionCoordinator: coordinator,
  );
  addTearDown(() async {
    await controller.dispose();
    await nativeEvents.close();
  });
  return _ControllerHarness(controller);
}

Future<String> _privateState(
  MediaRepositoryRealDbFixture fixture,
  String messageId,
) async {
  final rows = await fixture.db.query(
    'messages',
    columns: const <String>['private_media_state'],
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
  );
  return rows.single['private_media_state']! as String;
}

void _expectCompletedFingerprint(
  Map<String, Object?> row,
  MediaAttachment expected,
) {
  expect(row['id'], expected.id);
  expect(row['message_id'], expected.messageId);
  expect(row['owner_lane'], MediaOwnerLane.direct.dbValue);
  expect(row['local_path'], expected.localPath);
  expect(row['download_status'], 'done');
  expect(row['mime'], expected.mime);
  expect(row['size'], expected.size);
  expect(row['content_hash'], expected.contentHash);
  expect(row['encryption_nonce'], expected.encryptionNonce);
  expect(row['encryption_scheme'], expected.encryptionScheme);
}

void _writeBytes(String path, List<int> bytes) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes, flush: true);
}

class _ControllerHarness {
  const _ControllerHarness(this.controller);

  final DirectPrivateMediaViewerController controller;
}

class _BlockingReuseP2PService extends FakeP2PService {
  _BlockingReuseP2PService()
    : super(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'self-peer',
          connections: <ConnectionState>[
            ConnectionState(
              peerId: _contactPeerId,
              multiaddrs: <String>['/ip4/127.0.0.1/tcp/4001'],
              direction: 'outbound',
              status: 'connected',
            ),
          ],
        ),
      );

  final Completer<void> sendEntered = Completer<void>();
  final Completer<void> releaseSend = Completer<void>();

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendEntered.complete();
    await releaseSend.future;
    // Keep the attempt on the durable-inbox custody lane. A direct ACK is a
    // delivered terminal and intentionally clears its replay envelope, which
    // would not exercise E8's retained-envelope handoff boundary.
    return const SendMessageResult(sent: true, reply: null);
  }
}
