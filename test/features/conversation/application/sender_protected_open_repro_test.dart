import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

/// Repro for the field report: sender (user-a) of a protected-view photo taps
/// "Open private media" and gets "Couldn't open this photo" while the
/// recipient (user-b) opens the same photo fine.
///
/// Seeds the EXACT durable state the send pipeline leaves on the sender after
/// a fully successful upload+send (canonical relative local_path,
/// download_status 'done', protected/available outgoing parent) and drives the
/// real DirectPrivateMediaViewerController.prepareResult.
void main() {
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('sender one-more-look open succeeds on the happy post-send state', () async {
    const messageId = 'sender-open-msg';
    const attachmentId = 'sender-open-blob';
    const contactPeerId = 'contact-1';
    const relativePath = 'media/$contactPeerId/$attachmentId.jpg';

    // Outgoing protected parent exactly as persisted post-send.
    await fixture.seedDirectParent(messageId, contactPeerId: contactPeerId);
    await fixture.db.update(
      'messages',
      {
        'is_incoming': 0,
        'sender_peer_id': 'self-peer',
        'status': 'delivered',
        'private_media_policy_version': 1,
        'private_media_mode': 'protected',
        'private_media_state': 'available',
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );

    // Real durable file at the canonical owned path.
    final absolutePath = p.join(
      FakeMediaFileManager.testRootPath,
      relativePath,
    );
    File(absolutePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(4, 7));

    // Attachment row exactly as _finalizeUploadedAttachmentFromPlan saves it.
    await fixture.repo.saveAttachment(
      MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 4,
        mediaType: 'image',
        localPath: relativePath,
        downloadStatus: 'done',
        createdAt: '2026-07-18T00:00:00.000Z',
        contentHash: 'hash',
        encryptionKeyBase64: 'cHJpdmF0ZS1rZXk=',
        encryptionNonce: 'bm9uY2U=',
        encryptionScheme: 'blob_aes_256_gcm_v1',
      ),
      owner: MediaOwnerLane.direct,
    );

    final manager = FakeMediaFileManager();
    final adapter = DirectPrivateMediaLifecycle(
      messageRepository: fixture.messageRepo,
      mediaAttachmentRepository: fixture.repo,
      mediaFileManager: manager,
    );
    final engine = PrivateMediaLifecycleEngine(
      adapter: adapter,
      lifecycleLock: fixture.repo.lifecycleLock,
      nowMs: () => 5000,
    );

    // Probe the adapter view first for diagnostics.
    final target = await adapter.loadTarget(messageId);
    // ignore: avoid_print
    print('target: $target');
    if (target != null) {
      for (final a in target.attachments) {
        // ignore: avoid_print
        print(
          'attachment id=${a.id} stored=${a.storedLocalPath} '
          'local=${a.localPath} done=${a.isDownloadComplete} '
          'integrity=${a.isIntegrityEligible} size=${a.size}',
        );
      }
      // ignore: avoid_print
      print(
        'direction=${target.direction} mode=${target.mode} '
        'state=${target.state} hidden=${target.hidden}',
      );
    }

    final nativeEvents = StreamController<Object?>.broadcast();
    addTearDown(nativeEvents.close);
    final coordinator = PrivateMediaProtectionCoordinator(
      invokeMethod: (method, arguments) async => <String, Object?>{
        'ok': true,
        'protectionActive': method == 'enter',
      },
      nativeEvents: nativeEvents.stream,
    );

    final controller = DirectPrivateMediaViewerController(
      loadCurrentRows: (identity) async {
        final parent = await fixture.messageRepo
            .loadPrivateMediaLifecycleMessage(identity.messageId);
        final attachments = await fixture.repo.getAttachmentsForMessage(
          identity.messageId,
          owner: MediaOwnerLane.direct,
        );
        MediaAttachment? exact;
        for (final attachment in attachments) {
          if (attachment.id == identity.attachmentId) {
            if (exact != null) {
              exact = null;
              break;
            }
            exact = attachment;
          }
        }
        return DirectPrivateMediaCurrentRows(
          parent: parent,
          attachment: exact,
        );
      },
      lifecycleEngine: engine,
      protectionCoordinator: coordinator,
    );
    addTearDown(controller.dispose);

    final result = await controller.prepareResult(
      const DirectPrivateMediaViewerIdentity(
        messageId: messageId,
        attachmentId: attachmentId,
      ),
      const DirectPrivateMediaAlwaysValidContinuityGuard(),
    );

    // ignore: avoid_print
    print(
      'prepare granted=${result.isGranted} '
      'failure=${result.failureReason} settle=${result.settleResult}',
    );

    expect(
      result.isGranted,
      isTrue,
      reason:
          'sender one-more-look prepare failed: ${result.failureReason} '
          '(settle: ${result.settleResult?.disposition})',
    );

    // Settle so controller.dispose() does not wait forever on the grant.
    await controller.settle(
      result.grant!,
      DirectPrivateMediaExitReason.close,
    );
  });

  test('sender open during/after failed relay upload (LAN already delivered)',
      () async {
    const messageId = 'sender-pending-msg';
    const attachmentId = 'sender-pending-blob';
    const contactPeerId = 'contact-1';
    const pendingRelative = 'pending_uploads/$messageId/$attachmentId.jpg';

    await fixture.seedDirectParent(messageId, contactPeerId: contactPeerId);
    await fixture.db.update(
      'messages',
      {
        'is_incoming': 0,
        'sender_peer_id': 'self-peer',
        'status': 'sent',
        'private_media_policy_version': 1,
        'private_media_mode': 'protected',
        'private_media_state': 'available',
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );

    // Durable-prep state: pending-upload copy exists, row is upload_pending.
    final absolutePending = p.join(
      FakeMediaFileManager.testRootPath,
      pendingRelative,
    );
    File(absolutePending)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(4, 7));
    await fixture.repo.saveAttachment(
      MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 4,
        mediaType: 'image',
        localPath: pendingRelative,
        downloadStatus: 'upload_pending',
        createdAt: '2026-07-18T00:00:00.000Z',
      ),
      owner: MediaOwnerLane.direct,
    );

    final manager = FakeMediaFileManager();
    final adapter = DirectPrivateMediaLifecycle(
      messageRepository: fixture.messageRepo,
      mediaAttachmentRepository: fixture.repo,
      mediaFileManager: manager,
    );
    final engine = PrivateMediaLifecycleEngine(
      adapter: adapter,
      lifecycleLock: fixture.repo.lifecycleLock,
      nowMs: () => 5000,
    );
    final nativeEvents = StreamController<Object?>.broadcast();
    addTearDown(nativeEvents.close);
    final coordinator = PrivateMediaProtectionCoordinator(
      invokeMethod: (method, arguments) async => <String, Object?>{
        'ok': true,
        'protectionActive': method == 'enter',
      },
      nativeEvents: nativeEvents.stream,
    );
    final controller = DirectPrivateMediaViewerController(
      loadCurrentRows: (identity) async {
        final parent = await fixture.messageRepo
            .loadPrivateMediaLifecycleMessage(identity.messageId);
        final attachments = await fixture.repo.getAttachmentsForMessage(
          identity.messageId,
          owner: MediaOwnerLane.direct,
        );
        MediaAttachment? exact;
        for (final attachment in attachments) {
          if (attachment.id == identity.attachmentId) {
            exact = attachment;
          }
        }
        return DirectPrivateMediaCurrentRows(
          parent: parent,
          attachment: exact,
        );
      },
      lifecycleEngine: engine,
      protectionCoordinator: coordinator,
    );
    addTearDown(controller.dispose);

    final result = await controller.prepareResult(
      const DirectPrivateMediaViewerIdentity(
        messageId: messageId,
        attachmentId: attachmentId,
      ),
      const DirectPrivateMediaAlwaysValidContinuityGuard(),
    );

    final canRetry = result.failureReason == null
        ? false
        : await controller.canRetryAfterPrepareFailure(
            const DirectPrivateMediaViewerIdentity(
              messageId: messageId,
              attachmentId: attachmentId,
            ),
            result.failureReason!,
            settleResult: result.settleResult,
          );

    // ignore: avoid_print
    print(
      'pending-state prepare granted=${result.isGranted} '
      'failure=${result.failureReason} canRetry=$canRetry',
    );

    expect(result.isGranted, isFalse);
  });
}
