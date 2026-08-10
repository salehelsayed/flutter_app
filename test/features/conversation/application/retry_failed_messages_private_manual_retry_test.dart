import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _contactPeerId = 'contact-262-manual';
const _oldKey = 'b2xkLW1hbnVhbC1rZXk=';
const _newKey = 'bmV3LW1hbnVhbC1rZXk=';
const _oldNonce = 'b2xkLW1hbnVhbC1ub25jZQ==';
const _newNonce = 'bmV3LW1hbnVhbC1ub25jZQ==';
const _secondRetryKey = 'c2Vjb25kLXJldHJ5LWtleQ==';
const _secondRetryNonce = 'c2Vjb25kLXJldHJ5LW5vbmNl';
const _oldHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _newHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _secondRetryHash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

void main() {
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test(
    'manual private retry owns source through envelope handoff and preserves active opening',
    () async {
      const messageId = 'p262-manual-opening';
      const attachmentId = 'p262-manual-opening-att';
      final seeded = await _seedFailedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        privateMode: 'view_once',
        wireEnvelope: '{"stale":"manual"}',
      );
      final controller = _controller(fixture);
      final completed = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final uploadEntered = Completer<void>();
      final releaseUpload = Completer<void>();
      var claimedBeforeRead = false;
      var envelopeClearedBeforeRead = false;
      var lifecycleLockReleasedDuringIo = false;
      var claimedDuringHandoff = false;
      var rawPendingDirDeletes = 0;
      final p2pService = _p2pService();
      p2pService.onStoreInInbox = (peerId, envelope, {timeoutMs}) async {
        claimedDuringHandoff = directPrivateMediaTransferRegistry.isActive(
          attachmentId,
        );
        return true;
      };
      final manager = FakeMediaFileManager()
        ..onDeletePendingUploadDir = (_) => rawPendingDirDeletes++;

      final retryFuture = _runManualRetry(
        fixture,
        messageId: messageId,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: manager,
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
              claimedBeforeRead = directPrivateMediaTransferRegistry.isActive(
                attachmentId,
              );
              envelopeClearedBeforeRead =
                  await _wireEnvelope(fixture, messageId) == null;
              expect(localFilePath, seeded.pendingAbsolute);
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
              await competingLock;
              uploadEntered.complete();
              await releaseUpload.future;
              return UploadMediaSucceeded(completed);
            },
      );

      await uploadEntered.future.timeout(const Duration(seconds: 2));
      final prepared = await controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(prepared.isGranted, isTrue);
      expect(await _privateState(fixture, messageId), 'opening');
      releaseUpload.complete();
      final retried = await retryFuture.timeout(const Duration(seconds: 5));

      expect(retried, 1);
      expect(claimedBeforeRead, isTrue);
      expect(envelopeClearedBeforeRead, isTrue);
      expect(lifecycleLockReleasedDuringIo, isTrue);
      expect(claimedDuringHandoff, isTrue);
      expect(
        directPrivateMediaTransferRegistry.isActive(attachmentId),
        isFalse,
      );
      expect(rawPendingDirDeletes, 0);
      expect(await _privateState(fixture, messageId), 'opening');
      expect(
        (await fixture.rawAttachmentRow(attachmentId))?['local_path'],
        seeded.pendingRelative,
      );
      expect(
        (await fixture.rawAttachmentRow(attachmentId))?['download_status'],
        'upload_pending',
      );
      expect(await _wireEnvelope(fixture, messageId), isNotNull);
      expect(
        await _wireEnvelope(fixture, messageId),
        isNot('{"stale":"manual"}'),
      );
      expect(
        await controller.revalidateForLifecycleEvent(prepared.grant!),
        isTrue,
      );
      expect(File(seeded.pendingAbsolute).existsSync(), isTrue);

      final settlement = await controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.preFrameDecodeFailure,
      );
      expect(
        settlement.disposition,
        DirectPrivateMediaSettleDisposition.rolledBackAvailable,
      );
      expect(await _privateState(fixture, messageId), 'available');
      expect(
        (await fixture.rawAttachmentRow(attachmentId))?['local_path'],
        completed.localPath,
      );
      expect(
        await fixture.secureKeyStore.read(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        _newKey,
      );
      expect(
        File(seeded.pendingAbsolute).existsSync(),
        isFalse,
        reason:
            'settlement after manual transfer release must reclaim the '
            'redundant pending source',
      );
    },
  );

  test(
    'manual private terminal custody cleans only after durable handoff releases its claim',
    () async {
      const messageId = 'p262-manual-terminal';
      const attachmentId = 'p262-manual-terminal-att';
      await _seedFailedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        privateMode: 'view_once',
      );
      final controller = _controller(fixture);
      final completed = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final uploadEntered = Completer<void>();
      final releaseUpload = Completer<void>();
      var claimedDuringHandoff = false;
      var rawPendingDirDeletes = 0;
      final p2pService = _p2pService();
      p2pService.onStoreInInbox = (peerId, envelope, {timeoutMs}) async {
        claimedDuringHandoff = directPrivateMediaTransferRegistry.isActive(
          attachmentId,
        );
        expect(await fixture.rawAttachmentRow(attachmentId), isNotNull);
        return true;
      };
      final manager = FakeMediaFileManager()
        ..onDeletePendingUploadDir = (_) => rawPendingDirDeletes++;

      final retryFuture = _runManualRetry(
        fixture,
        messageId: messageId,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: manager,
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
              uploadEntered.complete();
              await releaseUpload.future;
              return UploadMediaSucceeded(completed);
            },
      );

      await uploadEntered.future.timeout(const Duration(seconds: 2));
      final prepared = await controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(prepared.isGranted, isTrue);
      expect(await controller.markFirstFrame(prepared.grant!), isTrue);
      final settlement = await controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.close,
      );
      expect(
        settlement.disposition,
        DirectPrivateMediaSettleDisposition.terminalized,
      );
      expect(await _privateState(fixture, messageId), 'consumed');
      expect(await fixture.rawAttachmentRow(attachmentId), isNotNull);
      expect(directPrivateMediaTransferRegistry.isActive(attachmentId), isTrue);
      releaseUpload.complete();
      final retried = await retryFuture.timeout(const Duration(seconds: 5));

      expect(retried, 1);
      expect(claimedDuringHandoff, isTrue);
      expect(
        directPrivateMediaTransferRegistry.isActive(attachmentId),
        isFalse,
      );
      expect(rawPendingDirDeletes, 0);
      expect(await _privateState(fixture, messageId), 'consumed');
      expect(await fixture.rawAttachmentRow(attachmentId), isNull);
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isFalse,
      );
    },
  );

  test(
    'manual private deferred completion survives first-frame terminalization before envelope commit',
    () async {
      const messageId = 'p262-manual-terminal-before-envelope';
      const attachmentId = 'p262-manual-terminal-before-envelope-att';
      final seeded = await _seedFailedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        privateMode: 'view_once',
      );
      final controller = _controller(fixture);
      final completed = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final uploadEntered = Completer<void>();
      final releaseUpload = Completer<void>();
      final bridge = _BlockingMessageEncryptBridge();
      var transportSawTerminalCustody = false;
      final p2pService = _p2pService()
        ..onStoreInInbox = (peerId, envelope, {timeoutMs}) async {
          transportSawTerminalCustody =
              await _privateState(fixture, messageId) == 'consumed' &&
              await fixture.rawAttachmentRow(attachmentId) != null &&
              directPrivateMediaTransferRegistry.isActive(attachmentId);
          return true;
        };

      final retryFuture = _runManualRetry(
        fixture,
        messageId: messageId,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: FakeMediaFileManager(),
        p2pService: p2pService,
        bridge: bridge,
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
              uploadEntered.complete();
              await releaseUpload.future;
              return UploadMediaSucceeded(completed);
            },
      );

      await uploadEntered.future.timeout(const Duration(seconds: 2));
      final prepared = await controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(prepared.isGranted, isTrue);
      expect(await _privateState(fixture, messageId), 'opening');

      releaseUpload.complete();
      await bridge.encryptEntered.future.timeout(const Duration(seconds: 2));
      final coordinator = fixture.repo.outgoingDirectPrivateMutationCoordinator;
      expect(
        await coordinator.loadOwnedCompletionFingerprint(
          messageId: messageId,
          attachmentId: attachmentId,
          expectedPendingLocalPath: seeded.pendingRelative,
        ),
        isNotNull,
        reason: 'upload completion must be deferred before message encryption',
      );
      expect(
        (await fixture.rawAttachmentRow(attachmentId))?['download_status'],
        'upload_pending',
      );
      expect(await _wireEnvelope(fixture, messageId), isNull);

      expect(await controller.markFirstFrame(prepared.grant!), isTrue);
      final settlement = await controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.close,
      );
      expect(
        settlement.disposition,
        DirectPrivateMediaSettleDisposition.terminalized,
      );
      expect(await _privateState(fixture, messageId), 'consumed');
      expect(await fixture.rawAttachmentRow(attachmentId), isNotNull);
      expect(
        await coordinator.loadOwnedCompletionFingerprint(
          messageId: messageId,
          attachmentId: attachmentId,
          expectedPendingLocalPath: seeded.pendingRelative,
        ),
        isNotNull,
        reason:
            'first-frame cleanup must convert the deferred completion to '
            'transport-only terminal custody',
      );

      bridge.releaseEncrypt.complete();
      final retried = await retryFuture.timeout(const Duration(seconds: 5));

      expect(retried, 1);
      expect(transportSawTerminalCustody, isTrue);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(await _privateState(fixture, messageId), 'consumed');
      expect(await _wireEnvelope(fixture, messageId), isNotNull);
      expect(await fixture.rawAttachmentRow(attachmentId), isNull);
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isFalse,
      );
      expect(File(seeded.pendingAbsolute).existsSync(), isFalse);
      expect(
        directPrivateMediaTransferRegistry.isActive(attachmentId),
        isFalse,
      );
    },
  );

  test(
    'manual private retry abandons failed terminal custody before a new same-process upload',
    () async {
      const messageId = 'p262-manual-terminal-handoff-failure';
      const attachmentId = 'p262-manual-terminal-handoff-failure-att';
      final seeded = await _seedFailedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        privateMode: 'view_once',
      );
      final controller = _controller(fixture);
      final firstCompleted = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final secondCompleted = firstCompleted.copyWith(
        contentHash: _secondRetryHash,
        encryptionKeyBase64: _secondRetryKey,
        encryptionNonce: _secondRetryNonce,
      );
      final uploadEntered = Completer<void>();
      final releaseUpload = Completer<void>();
      final failingBridge = _BlockingMessageEncryptBridge(failEncrypt: true);

      final firstRetry = _runManualRetry(
        fixture,
        messageId: messageId,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: FakeMediaFileManager(),
        bridge: failingBridge,
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
              uploadEntered.complete();
              await releaseUpload.future;
              return UploadMediaSucceeded(firstCompleted);
            },
      );

      await uploadEntered.future.timeout(const Duration(seconds: 2));
      final prepared = await controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(prepared.isGranted, isTrue);
      releaseUpload.complete();
      await failingBridge.encryptEntered.future.timeout(
        const Duration(seconds: 2),
      );
      expect(await controller.markFirstFrame(prepared.grant!), isTrue);
      expect(
        (await controller.settle(
          prepared.grant!,
          DirectPrivateMediaExitReason.close,
        )).disposition,
        DirectPrivateMediaSettleDisposition.terminalized,
      );
      failingBridge.releaseEncrypt.complete();

      expect(
        await firstRetry.timeout(const Duration(seconds: 5)),
        0,
        reason: 'the first transport envelope never became durable',
      );
      expect(await _privateState(fixture, messageId), 'consumed');
      expect(await _wireEnvelope(fixture, messageId), isNull);
      expect(await fixture.rawAttachmentRow(attachmentId), isNotNull);
      expect(File(seeded.pendingAbsolute).existsSync(), isTrue);

      final coordinator = fixture.repo.outgoingDirectPrivateMutationCoordinator;
      expect(
        await coordinator.loadOwnedCompletionFingerprint(
          messageId: messageId,
          attachmentId: attachmentId,
          expectedPendingLocalPath: seeded.pendingRelative,
        ),
        isNull,
        reason:
            'a completed attempt with no durable envelope must relinquish its '
            'process-local transport authorization after releasing custody',
      );

      final secondRetry = await _runManualRetry(
        fixture,
        messageId: messageId,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: FakeMediaFileManager(),
        uploadMediaFn: _successfulUpload(secondCompleted),
      ).timeout(const Duration(seconds: 5));

      expect(secondRetry, 1);
      expect(await _wireEnvelope(fixture, messageId), isNotNull);
      expect(await fixture.rawAttachmentRow(attachmentId), isNull);
      expect(File(seeded.pendingAbsolute).existsSync(), isFalse);
      expect(
        directPrivateMediaTransferRegistry.isActive(attachmentId),
        isFalse,
      );
    },
  );

  test(
    'manual private committed completion removes only its exact pending source',
    () async {
      const messageId = 'p262-manual-committed';
      const attachmentId = 'p262-manual-committed-att';
      final seeded = await _seedFailedPending(
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
      var rawPendingDirDeletes = 0;
      final manager = FakeMediaFileManager()
        ..onDeletePendingUploadDir = (_) => rawPendingDirDeletes++;

      final retried = await _runManualRetry(
        fixture,
        messageId: messageId,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: manager,
        uploadMediaFn: _successfulUpload(completed),
      );

      expect(retried, 1);
      expect(rawPendingDirDeletes, 0);
      expect(File(seeded.pendingAbsolute).existsSync(), isFalse);
      expect(File(siblingPath).existsSync(), isTrue);
      expect(
        (await fixture.rawAttachmentRow(attachmentId))?['local_path'],
        completed.localPath,
      );
      expect(
        (await fixture.rawAttachmentRow(attachmentId))?['download_status'],
        'done',
      );
    },
  );

  test(
    'manual private exact envelope refusal aborts before plaintext read',
    () async {
      const messageId = 'p262-manual-envelope-refusal';
      const attachmentId = 'p262-manual-envelope-refusal-att';
      final seeded = await _seedFailedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        wireEnvelope: '{"stale":"manual-refusal"}',
      );
      await fixture.db.execute('''
        CREATE TEMP TRIGGER p262_manual_abort_exact_envelope_clear
        BEFORE UPDATE OF wire_envelope ON messages
        WHEN OLD.id = '$messageId'
          AND OLD.status = 'sending'
          AND NEW.wire_envelope IS NULL
        BEGIN
          SELECT RAISE(ABORT, 'p262 manual exact envelope refusal');
        END
      ''');
      var uploadCalls = 0;

      final retried = await _runManualRetry(
        fixture,
        messageId: messageId,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: FakeMediaFileManager(),
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
              uploadCalls++;
              return UploadMediaSucceeded(
                _completedAttachment(
                  messageId: messageId,
                  attachmentId: attachmentId,
                ),
              );
            },
      );

      expect(retried, 0);
      expect(uploadCalls, 0);
      expect(
        directPrivateMediaTransferRegistry.isActive(attachmentId),
        isFalse,
      );
      expect(File(seeded.pendingAbsolute).existsSync(), isTrue);
      expect(
        (await fixture.rawAttachmentRow(attachmentId))?['download_status'],
        'upload_pending',
      );
    },
  );

  test(
    'manual private re-upload fails closed without repository authority',
    () async {
      const messageId = 'p262-manual-no-authority';
      const attachmentId = 'p262-manual-no-authority-att';
      await _seedFailedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        wireEnvelope: '{"stale":"must-survive-refusal"}',
      );
      final rearm = _RealManualRearm(fixture);
      var uploadCalls = 0;

      final retried = await _runManualRetry(
        fixture,
        messageId: messageId,
        mediaAttachmentRepository: _BaseOnlyMediaRepository(fixture.repo),
        mediaFileManager: FakeMediaFileManager(),
        rearm: rearm,
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
              uploadCalls++;
              return UploadMediaSucceeded(
                _completedAttachment(
                  messageId: messageId,
                  attachmentId: attachmentId,
                ),
              );
            },
      );

      expect(retried, 0);
      expect(uploadCalls, 0);
      expect(rearm.callCount, 0);
      expect(await _wireEnvelope(fixture, messageId), isNotNull);
      expect(
        (await fixture.messageRepo.getMessage(messageId))?.status,
        'failed',
      );
    },
  );

  test(
    'ordinary manual re-upload retains generic persistence and cleanup',
    () async {
      const messageId = 'p262-manual-ordinary';
      const attachmentId = 'p262-manual-ordinary-att';
      await _seedFailedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        isPrivate: false,
      );
      final completed = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      var rawPendingDirDeletes = 0;
      final manager = FakeMediaFileManager()
        ..onDeletePendingUploadDir = (_) => rawPendingDirDeletes++;

      final retried = await _runManualRetry(
        fixture,
        messageId: messageId,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: manager,
        uploadMediaFn: _successfulUpload(completed),
      );

      expect(retried, 1);
      expect(rawPendingDirDeletes, 1);
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
    },
  );

  // 302 (AD-3): the active-lease refusal is keyed on the 'opening'/'viewing'
  // states. A protected sender open no longer produces either, so a manual
  // retry driven while the viewer is open must APPLY rather than return
  // notAppliedActiveLease.
  //
  // The commit is asserted BEFORE settle on purpose: a refused projection
  // commits during settlement, so a post-settle assertion would pass on the
  // old behavior too and prove nothing.
  test(
    'protected manual retry applies under an open lease-free viewer and reopen uses canonical',
    () async {
      const messageId = 'p302-manual-lease-free';
      const attachmentId = 'p302-manual-lease-free-att';
      const identity = DirectPrivateMediaViewerIdentity(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final seeded = await _seedFailedPending(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        privateMode: 'protected',
        wireEnvelope: '{"stale":"manual"}',
      );
      final completed = _completedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final canonicalAbsolute = p.join(
        FakeMediaFileManager.testRootPath,
        completed.localPath!,
      );
      final controller = _controller(fixture);

      final prepared = await controller.prepareResult(
        identity,
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(prepared.isGranted, isTrue);
      expect(prepared.grant!.localPath, seeded.pendingAbsolute);

      final retried = await _runManualRetry(
        fixture,
        messageId: messageId,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: FakeMediaFileManager(),
        uploadMediaFn: _successfulUpload(completed),
      );

      // Asserted WHILE the grant is still open.
      expect(retried, 1);
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
      expect(await _privateState(fixture, messageId), 'available');

      final settlement = await controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.close,
      );
      expect(
        settlement.disposition,
        DirectPrivateMediaSettleDisposition.noLease,
      );
      expect(await _privateState(fixture, messageId), 'available');

      final reopened = await controller.prepareResult(
        identity,
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );
      expect(reopened.isGranted, isTrue);
      expect(reopened.grant!.localPath, canonicalAbsolute);
      final reopenedSettlement = await controller.settle(
        reopened.grant!,
        DirectPrivateMediaExitReason.close,
      );
      expect(
        reopenedSettlement.disposition,
        DirectPrivateMediaSettleDisposition.noLease,
      );
      expect(await _privateState(fixture, messageId), 'available');
    },
  );

  test(
    'TC-354-03b private strict failed retry canonicalizes without reminting',
    () async {
      // The manual failed-retry lane must reach the SAME reopen owner as the
      // incomplete lane. This pins the production wiring that makes that true:
      // a durable private v111 generation permanently excludes the legacy
      // encrypt-and-upload helper for this parent.
      final source = File(
        'lib/features/conversation/application/retry_failed_messages_use_case.dart',
      ).readAsStringSync();

      final reopenEntry = source.indexOf(
        '_reopenStrictPrivateFailedRetryAttachments(',
      );
      expect(
        reopenEntry,
        greaterThan(-1),
        reason: 'the failed-retry lane must own a private strict reopen entry',
      );
      final legacyCall = source.indexOf('await _reuploadAttachments(');
      expect(
        legacyCall,
        greaterThan(reopenEntry),
        reason:
            'the reopen decision must precede the legacy re-upload helper so '
            'a published generation can never reach it',
      );
      // The legacy helper is reachable only when the reopen produced no
      // attachments AND did not own the parent.
      expect(
        source.contains(
          'final reuploadedAttachments =\n        strictPrivate.attachments ??',
        ),
        isTrue,
      );
      expect(
        source.contains(
          'if (strictPrivate.owned && strictPrivate.attachments == null) {',
        ),
        isTrue,
        reason:
            'an owned-but-unfinished reopen must fail closed, never fall back',
      );

      final helperStart = source.indexOf(
        'Future<_StrictPrivateFailedRetry> _reopenStrictPrivateFailedRetryAttachments(',
      );
      expect(helperStart, greaterThan(-1));
      final helperBody = source.substring(helperStart);
      // It reopens through the coordinator, never through prepare/upload.
      expect(helperBody.contains('reopenAndUploadPrivate('), isTrue);
      expect(
        helperBody.contains('prepareAndUploadPrivate('),
        isFalse,
        reason: 'a retry must never mint a fresh private generation',
      );
      // It canonicalizes with the shared no-network promotion and commits
      // through the existing private completion coordinator.
      expect(
        helperBody.contains('canonicalizeStrictPrivateRetryCompletion('),
        isTrue,
      );
      expect(
        helperBody.contains(
          'outgoingDirectPrivateMutationCoordinator\n      .commitCompletion(',
        ),
        isTrue,
      );
      // Every non-success path retains custody rather than re-encrypting.
      expect(
        'RETRY_FAILED_PRIVATE_STRICT_RETAINED'.allMatches(helperBody).length,
        2,
      );
      expect(
        helperBody.contains('RETRY_FAILED_PRIVATE_STRICT_CANONICALIZE_REFUSED'),
        isTrue,
      );
      expect(
        helperBody.contains('RETRY_FAILED_PRIVATE_STRICT_COMPLETION_REFUSED'),
        isTrue,
      );

      // The shared canonicalization itself performs no network or crypto: it
      // copies the exact pending plaintext and preserves the strict identity.
      final shared = File(
        'lib/features/conversation/application/retry_incomplete_uploads_use_case.dart',
      ).readAsStringSync();
      final canonicalStart = shared.indexOf(
        'Future<MediaAttachment?> canonicalizeStrictPrivateRetryCompletion(',
      );
      expect(canonicalStart, greaterThan(-1));
      final canonicalBody = shared.substring(canonicalStart);
      for (final forbidden in <String>[
        'callP2PMediaUpload',
        'runUploadMedia',
        'prepareEncryptedMediaArtifact',
        'callBlobEncrypt',
      ]) {
        expect(
          canonicalBody.contains(forbidden),
          isFalse,
          reason: 'canonicalization must not $forbidden',
        );
      }
      expect(canonicalBody.contains('return strict.copyWith('), isTrue);
      expect(canonicalBody.contains("downloadStatus: 'done',"), isTrue);
    },
  );
}

Future<({String pendingRelative, String pendingAbsolute})> _seedFailedPending(
  MediaRepositoryRealDbFixture fixture, {
  required String messageId,
  required String attachmentId,
  bool isPrivate = true,
  String privateState = 'available',
  String? wireEnvelope,
  // 302: an open viewer only blocks a manual retry where a lease still
  // exists — outgoing view-once. Protected opens lease-free and is covered by
  // the immediate-apply case instead.
  String privateMode = 'protected',
}) async {
  await fixture.seedDirectParent(messageId, contactPeerId: _contactPeerId);
  await fixture.db.update(
    'messages',
    <String, Object?>{
      'sender_peer_id': 'self-peer',
      'text': isPrivate ? '' : 'ordinary manual retry',
      'status': 'failed',
      'is_incoming': 0,
      'wire_envelope': wireEnvelope,
      'private_media_policy_version': isPrivate ? 1 : 0,
      'private_media_mode': isPrivate ? privateMode : 'ordinary',
      'private_media_state': isPrivate ? privateState : 'none',
      'private_media_received_at_ms': isPrivate ? 1000 : null,
      'private_media_clock_high_water_ms': isPrivate ? 1000 : null,
      'private_media_revealed_at_ms': null,
      'private_media_terminal_at_ms': isPrivate && privateState == 'consumed'
          ? 2000
          : null,
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
    uploadRetryCount: kMaxUploadRetries,
    createdAt: '2026-07-20T00:00:00.000Z',
    contentHash: _oldHash,
    encryptionKeyBase64: _oldKey,
    encryptionNonce: _oldNonce,
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    ownerLane: MediaOwnerLane.direct,
  );
  if (isPrivate) {
    // Model a post-failure historical row. This deliberately bypasses the
    // first-durable-prep seam, whose production contract correctly refuses
    // first inserts that already carry completion crypto.
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
    uploadRetryCount: 0,
    createdAt: '2026-07-20T00:00:00.000Z',
    contentHash: _newHash,
    encryptionKeyBase64: _newKey,
    encryptionNonce: _newNonce,
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    ownerLane: MediaOwnerLane.direct,
  );
}

UploadMediaFn _successfulUpload(MediaAttachment completed) =>
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
    }) async => UploadMediaSucceeded(completed);

Future<int> _runManualRetry(
  MediaRepositoryRealDbFixture fixture, {
  required String messageId,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required FakeMediaFileManager mediaFileManager,
  required UploadMediaFn uploadMediaFn,
  _RealManualRearm? rearm,
  FakeP2PService? p2pService,
  FakeBridge? bridge,
}) {
  final identityRepository = FakeIdentityRepository()
    ..seed(
      FakeIdentityRepository.makeIdentity(
        peerId: 'self-peer',
        mlKemPublicKey: 'self-ml-kem-public',
        mlKemSecretKey: 'self-ml-kem-secret',
      ),
    );
  final contactRepository = FakeContactRepository()
    ..seed(<ContactModel>[
      ContactModel(
        peerId: _contactPeerId,
        publicKey: 'contact-public-key',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'P262 Manual Contact',
        signature: 'contact-signature',
        scannedAt: '2026-07-20T00:00:00.000Z',
        mlKemPublicKey: 'contact-ml-kem-public',
      ),
    ]);
  final uploadTracker = MediaUploadInFlightTracker();
  return retryFailedMessage(
    messageId: messageId,
    messageRepo: fixture.messageRepo,
    identityRepo: identityRepository,
    contactRepo: contactRepository,
    p2pService: p2pService ?? _p2pService(),
    bridge: bridge ?? FakeBridge(),
    mediaAttachmentRepo: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
    uploadMediaFn: uploadMediaFn,
    uploadRetryRearmRepo: rearm ?? _RealManualRearm(fixture),
    tryClaimUploadLease: (ids) =>
        uploadTracker.tryClaimAll(ids, source: MediaUploadTriggerSource.manual),
    releaseUploadLease: uploadTracker.release,
  );
}

class _BlockingMessageEncryptBridge extends FakeBridge {
  _BlockingMessageEncryptBridge({this.failEncrypt = false});

  final bool failEncrypt;
  final Completer<void> encryptEntered = Completer<void>();
  final Completer<void> releaseEncrypt = Completer<void>();

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    if (decoded['cmd'] == 'message.encrypt') {
      if (!encryptEntered.isCompleted) encryptEntered.complete();
      await releaseEncrypt.future;
      if (failEncrypt) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'errorCode': 'P262_INJECTED_ENCRYPT_FAILURE',
          'errorMessage': 'injected terminal-custody handoff failure',
        });
      }
    }
    return super.send(message);
  }
}

FakeP2PService _p2pService() => FakeP2PService(
  initialState: const NodeState(
    isStarted: true,
    peerId: 'self-peer',
    circuitAddresses: <String>['/p2p-circuit/p262-manual'],
  ),
  storeInInboxResult: true,
);

DirectPrivateMediaViewerController _controller(
  MediaRepositoryRealDbFixture fixture,
) {
  final adapter = DirectPrivateMediaLifecycle(
    messageRepository: fixture.messageRepo,
    mediaAttachmentRepository: fixture.repo,
    mediaFileManager: FakeMediaFileManager(),
  );
  final engine = PrivateMediaLifecycleEngine(
    adapter: adapter,
    lifecycleLock: fixture.repo.lifecycleLock,
    nowMs: () => 5000,
  );
  final nativeEvents = StreamController<Object?>.broadcast();
  final protectionCoordinator = PrivateMediaProtectionCoordinator(
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
    protectionCoordinator: protectionCoordinator,
  );
  addTearDown(() async {
    await controller.dispose();
    await nativeEvents.close();
  });
  return controller;
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
  expect(
    row['download_status'],
    'done',
    reason: 'the retry must not be refused as notAppliedActiveLease',
  );
  expect(row['mime'], expected.mime);
  expect(row['size'], expected.size);
  expect(row['content_hash'], expected.contentHash);
  expect(row['encryption_nonce'], expected.encryptionNonce);
  expect(row['encryption_scheme'], expected.encryptionScheme);
  expect(row['upload_retry_count'], expected.uploadRetryCount);
}

void _writeBytes(String path, List<int> bytes) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes, flush: true);
}

class _RealManualRearm implements DirectManualUploadRetryRearmRepository {
  _RealManualRearm(this.fixture);

  final MediaRepositoryRealDbFixture fixture;
  int callCount = 0;

  @override
  Future<bool> rearmUploadRetryForManualRetry({
    required String messageId,
    required List<ManualUploadRetryAttachmentExpectation> attachments,
  }) {
    callCount++;
    return dbRearmDirectUploadRetryForManualRetry(
      fixture.db,
      messageId: messageId,
      attachments: attachments,
    );
  }
}

/// Deliberately exposes only the ordinary repository surface. Private retry
/// must not silently fall through when lifecycle/coordinator authority is
/// absent.
class _BaseOnlyMediaRepository implements MediaAttachmentRepository {
  const _BaseOnlyMediaRepository(this.delegate);

  final MediaAttachmentRepository delegate;

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) => delegate.saveAttachment(attachment, owner: owner);

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) => delegate.getAttachmentsForMessage(messageId, owner: owner);

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) => delegate.getAttachmentsForMessages(messageIds, owner: owner);

  @override
  Future<void> updateLocalPath(String id, String localPath) =>
      delegate.updateLocalPath(id, localPath);

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) =>
      delegate.updateDownloadStatus(id, downloadStatus);

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) => delegate.deleteAttachmentsForMessage(messageId, owner: owner);

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) =>
      delegate.deleteAttachmentsForContact(contactPeerId);

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) => delegate.markUploadPendingAttachmentsFailedForMessage(
    messageId,
    owner: owner,
  );

  @override
  Future<List<MediaAttachment>> getPendingDownloads() =>
      delegate.getPendingDownloads();

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) => delegate.getUploadPendingAttachments(owner: owner);
}
