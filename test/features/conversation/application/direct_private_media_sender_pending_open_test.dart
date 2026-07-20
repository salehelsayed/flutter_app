import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

const _contactPeerId = 'contact-1';
const _modes = <String>['protected', 'view_once'];

void main() {
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('finalized canonical state grants', () async {
    const messageId = 'sender-canonical-msg';
    const attachmentId = 'sender-canonical-blob';
    const relativePath = 'media/$_contactPeerId/$attachmentId.jpg';
    final absolutePath = p.join(
      FakeMediaFileManager.testRootPath,
      relativePath,
    );

    await _seedOutgoingPrivateParent(
      fixture,
      messageId: messageId,
      mode: 'protected',
    );
    _writeBytes(absolutePath, const <int>[7, 7, 7, 7]);
    await _insertDirectAttachmentFixtureRow(
      fixture,
      messageId: messageId,
      attachmentId: attachmentId,
      localPath: relativePath,
      downloadStatus: 'done',
      size: 4,
      encryptionKeyBase64: 'cHJpdmF0ZS1rZXk=',
      encryptionNonce: 'bm9uY2U=',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );

    final harness = _buildHarness(fixture);
    final result = await harness.controller.prepareResult(
      const DirectPrivateMediaViewerIdentity(
        messageId: messageId,
        attachmentId: attachmentId,
      ),
      const DirectPrivateMediaAlwaysValidContinuityGuard(),
    );

    try {
      expect(
        result.isGranted,
        isTrue,
        reason:
            'synthetic canonical done state remains a preservation sentinel',
      );
      expect(result.grant!.localPath, absolutePath);
    } finally {
      if (result.grant != null && !result.grant!.settled) {
        await harness.controller.settle(
          result.grant!,
          DirectPrivateMediaExitReason.preFrameDecodeFailure,
        );
      }
    }
  });

  for (final mode in _modes) {
    test(
      'outgoing upload_pending adapter target is locally complete ($mode)',
      () async {
        final messageId = 'sender-pending-adapter-$mode';
        final attachmentId = 'sender-pending-adapter-blob-$mode';
        final pendingRelative = 'pending_uploads/$messageId/$attachmentId.jpg';
        final pendingAbsolute = p.join(
          FakeMediaFileManager.testRootPath,
          pendingRelative,
        );
        await _seedPendingTarget(
          fixture,
          messageId: messageId,
          attachmentId: attachmentId,
          mode: mode,
          bytes: const <int>[1, 2, 3, 4],
        );

        final adapter = DirectPrivateMediaLifecycle(
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: FakeMediaFileManager(),
        );
        final target = await adapter.loadTarget(messageId);

        expect(target, isNotNull);
        expect(target!.direction, PrivateMediaDirection.outgoing);
        expect(target.attachments, hasLength(1));
        expect(target.attachments.single.storedLocalPath, pendingRelative);
        expect(target.attachments.single.localPath, pendingAbsolute);
        expect(target.attachments.single.isDownloadComplete, isTrue);
        expect(target.attachments.single.isIntegrityEligible, isTrue);
      },
    );

    test('outgoing pending exact CAS claims and rolls back ($mode)', () async {
      final messageId = 'sender-pending-cas-$mode';
      final attachmentId = 'sender-pending-cas-blob-$mode';
      final pendingRelative = 'pending_uploads/$messageId/$attachmentId.jpg';
      await _seedPendingTarget(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        mode: mode,
        bytes: const <int>[1, 2, 3, 4],
      );

      expect(
        await dbClaimDirectPrivateMediaOpening(
          fixture.db,
          messageId,
          nowMs: 5000,
          isIncoming: false,
          mode: mode,
          attachmentId: attachmentId,
          storedLocalPath: '$pendingRelative.replaced',
        ),
        0,
        reason: 'the pending arm must retain exact stored-path identity',
      );
      expect(await _privateState(fixture, messageId), 'available');
      expect(
        await dbClaimDirectPrivateMediaOpening(
          fixture.db,
          messageId,
          nowMs: 5001,
          isIncoming: false,
          mode: mode,
          attachmentId: attachmentId,
          storedLocalPath: pendingRelative,
        ),
        1,
      );
      expect(await _privateState(fixture, messageId), 'opening');
      expect(
        await dbRollbackDirectPrivateMediaOpening(
          fixture.db,
          messageId,
          isIncoming: false,
          mode: mode,
          attachmentId: attachmentId,
          storedLocalPath: pendingRelative,
        ),
        1,
      );
      expect(await _privateState(fixture, messageId), 'available');
    });

    test(
      'outgoing upload_pending grant rolls back before first frame ($mode)',
      () async {
        final messageId = 'sender-pending-rollback-$mode';
        final attachmentId = 'sender-pending-rollback-blob-$mode';
        final pendingRelative = 'pending_uploads/$messageId/$attachmentId.jpg';
        final pendingAbsolute = p.join(
          FakeMediaFileManager.testRootPath,
          pendingRelative,
        );
        await _seedPendingTarget(
          fixture,
          messageId: messageId,
          attachmentId: attachmentId,
          mode: mode,
          bytes: const <int>[1, 2, 3, 4],
        );
        final harness = _buildHarness(fixture);
        final result = await harness.controller.prepareResult(
          DirectPrivateMediaViewerIdentity(
            messageId: messageId,
            attachmentId: attachmentId,
          ),
          const DirectPrivateMediaAlwaysValidContinuityGuard(),
        );

        var settled = false;
        try {
          expect(
            result.isGranted,
            isTrue,
            reason: 'pending plaintext is sender-local one-more-look authority',
          );
          expect(result.grant!.localPath, pendingAbsolute);
          expect(await _privateState(fixture, messageId), 'opening');
          final settlement = await harness.controller.settle(
            result.grant!,
            DirectPrivateMediaExitReason.preFrameDecodeFailure,
          );
          settled = true;
          expect(
            settlement.disposition,
            DirectPrivateMediaSettleDisposition.rolledBackAvailable,
          );
          expect(settlement.firstFrameRecorded, isFalse);
          expect(await _privateState(fixture, messageId), 'available');
        } finally {
          if (!settled && result.grant != null && !result.grant!.settled) {
            await harness.controller.settle(
              result.grant!,
              DirectPrivateMediaExitReason.preFrameDecodeFailure,
            );
          }
        }
      },
    );

    test(
      'outgoing upload_pending first frame terminalizes the lease ($mode)',
      () async {
        final messageId = 'sender-pending-terminal-$mode';
        final attachmentId = 'sender-pending-terminal-blob-$mode';
        await _seedPendingTarget(
          fixture,
          messageId: messageId,
          attachmentId: attachmentId,
          mode: mode,
          bytes: const <int>[1, 2, 3, 4],
        );
        final harness = _buildHarness(fixture);
        final result = await harness.controller.prepareResult(
          DirectPrivateMediaViewerIdentity(
            messageId: messageId,
            attachmentId: attachmentId,
          ),
          const DirectPrivateMediaAlwaysValidContinuityGuard(),
        );

        var settled = false;
        try {
          expect(result.isGranted, isTrue);
          expect(
            await harness.controller.markFirstFrame(result.grant!),
            isTrue,
          );
          expect(await _privateState(fixture, messageId), 'viewing');
          final settlement = await harness.controller.settle(
            result.grant!,
            DirectPrivateMediaExitReason.close,
          );
          settled = true;
          expect(
            settlement.disposition,
            DirectPrivateMediaSettleDisposition.terminalized,
          );
          expect(settlement.firstFrameRecorded, isTrue);
          expect(await _privateState(fixture, messageId), 'consumed');
        } finally {
          if (!settled && result.grant != null && !result.grant!.settled) {
            await harness.controller.settle(
              result.grant!,
              DirectPrivateMediaExitReason.close,
            );
          }
        }
      },
    );
  }

  test('post-rollback retry requalifies the pending shape', () async {
    for (final mode in _modes) {
      final messageId = 'sender-pending-retry-$mode';
      final attachmentId = 'sender-pending-retry-blob-$mode';
      final pendingRelative = 'pending_uploads/$messageId/$attachmentId.jpg';
      final pendingAbsolute = p.join(
        FakeMediaFileManager.testRootPath,
        pendingRelative,
      );
      final canonicalAbsolute = p.join(
        FakeMediaFileManager.testRootPath,
        'media/$_contactPeerId/$attachmentId.jpg',
      );
      final canonicalFile = File(canonicalAbsolute);
      if (canonicalFile.existsSync()) canonicalFile.deleteSync();
      await _seedPendingTarget(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        mode: mode,
        bytes: const <int>[1, 2, 3, 4],
      );
      final harness = _buildHarness(fixture);
      final identity = DirectPrivateMediaViewerIdentity(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final prepared = await harness.controller.prepareResult(
        identity,
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );

      expect(prepared.isGranted, isTrue, reason: mode);
      final settlement = await harness.controller.settle(
        prepared.grant!,
        DirectPrivateMediaExitReason.preFrameDecodeFailure,
      );
      expect(
        settlement.disposition,
        DirectPrivateMediaSettleDisposition.rolledBackAvailable,
        reason: mode,
      );
      expect(await _privateState(fixture, messageId), 'available');
      expect(
        (await fixture.rawAttachmentRow(attachmentId))!['download_status'],
        'upload_pending',
        reason:
            'retry must requalify the pending row, not a canonical done row',
      );
      expect(File(pendingAbsolute).existsSync(), isTrue);
      expect(canonicalFile.existsSync(), isFalse);
      expect(
        await harness.controller.canRetryAfterOpenFailure(
          identity,
          DirectPrivateMediaOpenFailureReason.preFrameFailure,
          settleResult: settlement,
        ),
        isTrue,
        reason: '$mode exact rolled-back pending authority remains retryable',
      );

      File(pendingAbsolute).deleteSync();
      expect(
        await harness.controller.canRetryAfterOpenFailure(
          identity,
          DirectPrivateMediaOpenFailureReason.preFrameFailure,
          settleResult: settlement,
        ),
        isFalse,
        reason: '$mode missing sender-local bytes cannot retry',
      );

      _writeBytes(pendingAbsolute, const <int>[1, 2, 3, 4]);
      final wrongRelative = 'pending_uploads/$messageId/sibling.jpg';
      _writeBytes(
        p.join(FakeMediaFileManager.testRootPath, wrongRelative),
        const <int>[1, 2, 3, 4],
      );
      await fixture.db.update(
        'media_attachments',
        <String, Object?>{'local_path': wrongRelative},
        where: 'id = ? AND message_id = ?',
        whereArgs: <Object?>[attachmentId, messageId],
      );
      expect(
        await harness.controller.canRetryAfterOpenFailure(
          identity,
          DirectPrivateMediaOpenFailureReason.preFrameFailure,
          settleResult: settlement,
        ),
        isFalse,
        reason: '$mode wrong pending identity cannot retry',
      );

      await fixture.db.update(
        'media_attachments',
        <String, Object?>{'local_path': pendingRelative},
        where: 'id = ? AND message_id = ?',
        whereArgs: <Object?>[attachmentId, messageId],
      );
      await fixture.db.update(
        'messages',
        <String, Object?>{'private_media_state': 'consumed'},
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      );
      expect(
        await harness.controller.canRetryAfterOpenFailure(
          identity,
          DirectPrivateMediaOpenFailureReason.preFrameFailure,
          settleResult: settlement,
        ),
        isFalse,
        reason: '$mode terminal lifecycle state cannot retry',
      );
    }
  });

  test(
    'exact otherwise-authorized missing pending leaf is senderLocalBytesMissing',
    () async {
      const messageId = 'sender-pending-missing-leaf';
      const attachmentId = 'sender-pending-missing-leaf-blob';
      const pendingRelative = 'pending_uploads/$messageId/$attachmentId.jpg';
      final pendingAbsolute = p.join(
        FakeMediaFileManager.testRootPath,
        pendingRelative,
      );
      final parent = Directory(p.dirname(pendingAbsolute));
      parent.createSync(recursive: true);
      final leaf = File(pendingAbsolute);
      if (leaf.existsSync()) leaf.deleteSync();
      await _seedOutgoingPrivateParent(
        fixture,
        messageId: messageId,
        mode: 'protected',
      );
      await _saveDirectAttachment(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        localPath: pendingRelative,
        downloadStatus: 'upload_pending',
        size: 4,
      );
      final harness = _buildHarness(fixture);
      const identity = DirectPrivateMediaViewerIdentity(
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final result = await harness.controller.prepareResult(
        identity,
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );

      expect(result.isGranted, isFalse);
      expect(result.failureReason?.name, 'senderLocalBytesMissing');
      expect(
        await harness.controller.canRetryAfterPrepareFailure(
          identity,
          result.failureReason!,
          settleResult: result.settleResult,
        ),
        isFalse,
      );
      expect(await _privateState(fixture, messageId), 'available');
      expect(harness.nativeCalls, isEmpty);
    },
  );

  test(
    'missing pending root or ancestor stays generic, unlike the exact leaf',
    () async {
      final missingRoot = _newScenarioManager('missing_root');
      expect(
        FileSystemEntity.typeSync(missingRoot.pendingRoot, followLinks: false),
        FileSystemEntityType.notFound,
      );
      await _expectPendingRefusal(
        fixture,
        manager: missingRoot,
        messageId: 'sender-pending-missing-root',
        attachmentId: 'sender-pending-missing-root-blob',
        storedPath:
            'pending_uploads/sender-pending-missing-root/sender-pending-missing-root-blob.jpg',
        reason: 'missing independently trusted root',
      );

      final missingAncestor = _newScenarioManager('missing_ancestor');
      Directory(missingAncestor.pendingRoot).createSync(recursive: true);
      expect(
        FileSystemEntity.typeSync(
          p.join(
            missingAncestor.pendingRoot,
            'sender-pending-missing-ancestor',
          ),
          followLinks: false,
        ),
        FileSystemEntityType.notFound,
      );
      await _expectPendingRefusal(
        fixture,
        manager: missingAncestor,
        messageId: 'sender-pending-missing-ancestor',
        attachmentId: 'sender-pending-missing-ancestor-blob',
        storedPath:
            'pending_uploads/sender-pending-missing-ancestor/sender-pending-missing-ancestor-blob.jpg',
        reason: 'missing exact message ancestor',
      );
    },
  );

  test(
    'pending-path authority rejects wrong IDs, convention, extension, and containment',
    () async {
      final cases =
          <
            ({
              String name,
              String messageId,
              String attachmentId,
              String contactPeerId,
              String storedPath,
              bool absoluteStoredPath,
            })
          >[
            (
              name: 'wrong message id in stored convention',
              messageId: 'sender-pending-wrong-message',
              attachmentId: 'sender-pending-wrong-message-blob',
              contactPeerId: _contactPeerId,
              storedPath:
                  'pending_uploads/other-message/sender-pending-wrong-message-blob.jpg',
              absoluteStoredPath: false,
            ),
            (
              name: 'wrong attachment id and sibling pending file',
              messageId: 'sender-pending-wrong-attachment',
              attachmentId: 'sender-pending-wrong-attachment-blob',
              contactPeerId: _contactPeerId,
              storedPath:
                  'pending_uploads/sender-pending-wrong-attachment/sibling.jpg',
              absoluteStoredPath: false,
            ),
            (
              name: 'wrong extension',
              messageId: 'sender-pending-wrong-extension',
              attachmentId: 'sender-pending-wrong-extension-blob',
              contactPeerId: _contactPeerId,
              storedPath:
                  'pending_uploads/sender-pending-wrong-extension/sender-pending-wrong-extension-blob.png',
              absoluteStoredPath: false,
            ),
            (
              name: 'extra nested path component',
              messageId: 'sender-pending-nested-path',
              attachmentId: 'sender-pending-nested-path-blob',
              contactPeerId: _contactPeerId,
              storedPath:
                  'pending_uploads/sender-pending-nested-path/nested/sender-pending-nested-path-blob.jpg',
              absoluteStoredPath: false,
            ),
            (
              name: 'absolute stored pending path',
              messageId: 'sender-pending-absolute-row',
              attachmentId: 'sender-pending-absolute-row-blob',
              contactPeerId: _contactPeerId,
              storedPath:
                  'pending_uploads/sender-pending-absolute-row/sender-pending-absolute-row-blob.jpg',
              absoluteStoredPath: true,
            ),
            (
              name: 'outside trusted pending root',
              messageId: 'sender-pending-outside-root',
              attachmentId: 'sender-pending-outside-root-blob',
              contactPeerId: _contactPeerId,
              storedPath: '../outside/sender-pending-outside-root-blob.jpg',
              absoluteStoredPath: false,
            ),
            (
              name: 'unsafe message id',
              messageId: 'unsafe/message',
              attachmentId: 'sender-pending-unsafe-message-blob',
              contactPeerId: _contactPeerId,
              storedPath:
                  'pending_uploads/unsafe/message/sender-pending-unsafe-message-blob.jpg',
              absoluteStoredPath: false,
            ),
            (
              name: 'unsafe attachment id',
              messageId: 'sender-pending-unsafe-attachment',
              attachmentId: 'unsafe/blob',
              contactPeerId: _contactPeerId,
              storedPath:
                  'pending_uploads/sender-pending-unsafe-attachment/unsafe/blob.jpg',
              absoluteStoredPath: false,
            ),
            (
              name: 'unsafe contact id',
              messageId: 'sender-pending-unsafe-contact',
              attachmentId: 'sender-pending-unsafe-contact-blob',
              contactPeerId: 'unsafe/contact',
              storedPath:
                  'pending_uploads/sender-pending-unsafe-contact/sender-pending-unsafe-contact-blob.jpg',
              absoluteStoredPath: false,
            ),
          ];

      for (var index = 0; index < cases.length; index += 1) {
        final candidate = cases[index];
        final manager = _newScenarioManager('identity_$index');
        final storedPath = candidate.absoluteStoredPath
            ? p.join(
                manager.pendingRoot,
                candidate.storedPath.substring('pending_uploads/'.length),
              )
            : candidate.storedPath;
        final candidateAbsolute = candidate.absoluteStoredPath
            ? storedPath
            : candidate.storedPath.startsWith('pending_uploads/')
            ? p.join(
                manager.pendingRoot,
                candidate.storedPath.substring('pending_uploads/'.length),
              )
            : p.normalize(p.join(manager.pendingRoot, candidate.storedPath));
        _writeBytes(candidateAbsolute, const <int>[1, 2, 3, 4]);
        await _expectPendingRefusal(
          fixture,
          manager: manager,
          messageId: candidate.messageId,
          attachmentId: candidate.attachmentId,
          contactPeerId: candidate.contactPeerId,
          storedPath: storedPath,
          reason: candidate.name,
        );
      }
    },
  );

  test(
    'pending-path authority rejects symlink, type, and size violations',
    () async {
      final symlinkRoot = _newScenarioManager('symlink_root');
      final realPendingRoot = p.join(symlinkRoot.baseRoot, 'real_pending');
      _writeBytes(
        p.join(realPendingRoot, 'sender-symlink-root', 'blob-symlink-root.jpg'),
        const <int>[1, 2, 3, 4],
      );
      Link(symlinkRoot.pendingRoot).createSync(realPendingRoot);
      await _expectPendingRefusal(
        fixture,
        manager: symlinkRoot,
        messageId: 'sender-symlink-root',
        attachmentId: 'blob-symlink-root',
        storedPath: 'pending_uploads/sender-symlink-root/blob-symlink-root.jpg',
        reason: 'trusted pending root is a symlink',
      );

      final symlinkAncestor = _newScenarioManager('symlink_ancestor');
      Directory(symlinkAncestor.pendingRoot).createSync(recursive: true);
      final realMessageDir = p.join(symlinkAncestor.baseRoot, 'real_message');
      _writeBytes(
        p.join(realMessageDir, 'blob-symlink-ancestor.jpg'),
        const <int>[1, 2, 3, 4],
      );
      Link(
        p.join(symlinkAncestor.pendingRoot, 'sender-symlink-ancestor'),
      ).createSync(realMessageDir);
      await _expectPendingRefusal(
        fixture,
        manager: symlinkAncestor,
        messageId: 'sender-symlink-ancestor',
        attachmentId: 'blob-symlink-ancestor',
        storedPath:
            'pending_uploads/sender-symlink-ancestor/blob-symlink-ancestor.jpg',
        reason: 'message ancestor is a symlink',
      );

      final symlinkLeaf = _newScenarioManager('symlink_leaf');
      final realLeaf = p.join(symlinkLeaf.baseRoot, 'real_leaf.jpg');
      _writeBytes(realLeaf, const <int>[1, 2, 3, 4]);
      final linkedLeaf = p.join(
        symlinkLeaf.pendingRoot,
        'sender-symlink-leaf',
        'blob-symlink-leaf.jpg',
      );
      Directory(p.dirname(linkedLeaf)).createSync(recursive: true);
      Link(linkedLeaf).createSync(realLeaf);
      await _expectPendingRefusal(
        fixture,
        manager: symlinkLeaf,
        messageId: 'sender-symlink-leaf',
        attachmentId: 'blob-symlink-leaf',
        storedPath: 'pending_uploads/sender-symlink-leaf/blob-symlink-leaf.jpg',
        reason: 'exact leaf is a symlink',
      );

      final ancestorFile = _newScenarioManager('ancestor_file');
      Directory(ancestorFile.pendingRoot).createSync(recursive: true);
      _writeBytes(
        p.join(ancestorFile.pendingRoot, 'sender-ancestor-file'),
        const <int>[1, 2, 3, 4],
      );
      await _expectPendingRefusal(
        fixture,
        manager: ancestorFile,
        messageId: 'sender-ancestor-file',
        attachmentId: 'blob-ancestor-file',
        storedPath:
            'pending_uploads/sender-ancestor-file/blob-ancestor-file.jpg',
        reason: 'message ancestor is not a directory',
      );

      final leafDirectory = _newScenarioManager('leaf_directory');
      Directory(
        p.join(
          leafDirectory.pendingRoot,
          'sender-leaf-directory',
          'blob-leaf-directory.jpg',
        ),
      ).createSync(recursive: true);
      await _expectPendingRefusal(
        fixture,
        manager: leafDirectory,
        messageId: 'sender-leaf-directory',
        attachmentId: 'blob-leaf-directory',
        storedPath:
            'pending_uploads/sender-leaf-directory/blob-leaf-directory.jpg',
        reason: 'exact leaf is a directory rather than a regular file',
      );

      final wrongSize = _newScenarioManager('wrong_size');
      _writeBytes(
        p.join(
          wrongSize.pendingRoot,
          'sender-pending-size-mismatch',
          'sender-pending-size-mismatch-blob.jpg',
        ),
        const <int>[1, 2, 3],
      );
      await _expectPendingRefusal(
        fixture,
        manager: wrongSize,
        messageId: 'sender-pending-size-mismatch',
        attachmentId: 'sender-pending-size-mismatch-blob',
        storedPath:
            'pending_uploads/sender-pending-size-mismatch/sender-pending-size-mismatch-blob.jpg',
        reason: 'recorded size differs from the exact regular file',
      );
    },
  );

  test(
    'bare pending row plus canonical bytes stays pending without a key',
    () async {
      for (final mode in _modes) {
        final messageId = 'sender-bare-pending-$mode';
        final attachmentId = 'sender-bare-pending-blob-$mode';
        final pendingRelative = 'pending_uploads/$messageId/$attachmentId.jpg';
        final pendingAbsolute = p.join(
          FakeMediaFileManager.testRootPath,
          pendingRelative,
        );
        final canonicalAbsolute = p.join(
          FakeMediaFileManager.testRootPath,
          'media/$_contactPeerId/$attachmentId.jpg',
        );
        await _seedPendingTarget(
          fixture,
          messageId: messageId,
          attachmentId: attachmentId,
          mode: mode,
          bytes: const <int>[1, 2, 3, 4],
        );
        _writeBytes(canonicalAbsolute, const <int>[9, 9, 9, 9]);
        final before = (await fixture.rawAttachmentRow(attachmentId))!;
        final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
        expect(await fixture.secureKeyStore.read(keyName), isNull);
        final harness = _buildHarness(fixture);
        final prepared = await harness.controller.prepareResult(
          DirectPrivateMediaViewerIdentity(
            messageId: messageId,
            attachmentId: attachmentId,
          ),
          const DirectPrivateMediaAlwaysValidContinuityGuard(),
        );

        expect(prepared.isGranted, isTrue, reason: mode);
        expect(prepared.grant!.localPath, pendingAbsolute, reason: mode);
        await harness.controller.settle(
          prepared.grant!,
          DirectPrivateMediaExitReason.preFrameDecodeFailure,
        );
        expect(
          await fixture.rawAttachmentRow(attachmentId),
          before,
          reason: mode,
        );
        expect(
          await fixture.secureKeyStore.read(keyName),
          isNull,
          reason: mode,
        );
        expect(
          fixture.secureKeyStore.writtenKeys.where((key) => key == keyName),
          isEmpty,
          reason:
              '$mode canonical bytes alone cannot fabricate upload metadata',
        );
      }
    },
  );

  test(
    'legacy dangling-path repair rejects missing, wrong-size, symlink, and non-file canonical candidates',
    () async {
      for (final kind in <String>[
        'missing',
        'wrong-size',
        'symlink',
        'non-file',
      ]) {
        final manager = _newScenarioManager('legacy_$kind');
        final messageId = 'sender-legacy-negative-$kind';
        final attachmentId = 'sender-legacy-negative-blob-$kind';
        final paths = await _seedLegacyDanglingDone(
          fixture,
          manager: manager,
          messageId: messageId,
          attachmentId: attachmentId,
          mode: 'protected',
        );
        switch (kind) {
          case 'missing':
            expect(
              FileSystemEntity.typeSync(
                paths.canonicalAbsolute,
                followLinks: false,
              ),
              FileSystemEntityType.notFound,
            );
          case 'wrong-size':
            _writeBytes(paths.canonicalAbsolute, const <int>[8, 8, 8]);
          case 'symlink':
            final realLeaf = p.join(manager.baseRoot, 'real-canonical.jpg');
            _writeBytes(realLeaf, const <int>[8, 8, 8, 8]);
            Directory(
              p.dirname(paths.canonicalAbsolute),
            ).createSync(recursive: true);
            Link(paths.canonicalAbsolute).createSync(realLeaf);
          case 'non-file':
            Directory(paths.canonicalAbsolute).createSync(recursive: true);
        }
        final before = (await fixture.rawAttachmentRow(attachmentId))!;
        final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
        final beforeKey = await fixture.secureKeyStore.read(keyName);
        final harness = _buildHarness(fixture, manager: manager);
        final result = await harness.controller.prepareResult(
          DirectPrivateMediaViewerIdentity(
            messageId: messageId,
            attachmentId: attachmentId,
          ),
          const DirectPrivateMediaAlwaysValidContinuityGuard(),
        );

        expect(result.isGranted, isFalse, reason: kind);
        expect(
          result.failureReason,
          DirectPrivateMediaPrepareFailureReason.localAuthorityMissing,
          reason: kind,
        );
        expect(
          await fixture.rawAttachmentRow(attachmentId),
          before,
          reason: kind,
        );
        expect(
          await fixture.secureKeyStore.read(keyName),
          beforeKey,
          reason: kind,
        );
        expect(
          await _privateState(fixture, messageId),
          'available',
          reason: kind,
        );
        expect(harness.nativeCalls, isEmpty, reason: kind);
      }
    },
  );

  test(
    'legacy dangling-path repair path CAS preserves a competing row',
    () async {
      const messageId = 'sender-legacy-competing-cas';
      const attachmentId = 'sender-legacy-competing-cas-blob';
      final manager = _newScenarioManager('legacy_competing_cas');
      final paths = await _seedLegacyDanglingDone(
        fixture,
        manager: manager,
        messageId: messageId,
        attachmentId: attachmentId,
        mode: 'protected',
      );
      _writeBytes(paths.canonicalAbsolute, const <int>[8, 8, 8, 8]);
      final before = (await fixture.rawAttachmentRow(attachmentId))!;
      const competingPath =
          'media/$_contactPeerId/competing-sender-legacy-competing-cas-blob.jpg';
      expect(
        await fixture.db.update(
          'media_attachments',
          <String, Object?>{'local_path': competingPath},
          where: 'id = ? AND message_id = ? AND local_path = ?',
          whereArgs: <Object?>[attachmentId, messageId, paths.danglingAbsolute],
        ),
        1,
      );

      expect(
        await dbRepairOutgoingDirectPrivateMediaDoneLocalPathIfEligible(
          fixture.db,
          messageId: messageId,
          attachmentId: attachmentId,
          expectedStoredLocalPath: paths.danglingAbsolute,
          canonicalLocalPath: paths.canonicalRelative,
          expectedContactPeerId: _contactPeerId,
          expectedMime: 'image/jpeg',
          expectedSize: 4,
        ),
        0,
        reason: 'the path-only repair CAS must not overwrite a competing row',
      );
      final afterCas = (await fixture.rawAttachmentRow(attachmentId))!;
      expect(afterCas['local_path'], competingPath);
      expect(_withoutLocalPath(afterCas), _withoutLocalPath(before));
      final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
      final beforeKey = await fixture.secureKeyStore.read(keyName);
      final harness = _buildHarness(fixture, manager: manager);
      final result = await harness.controller.prepareResult(
        const DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        const DirectPrivateMediaAlwaysValidContinuityGuard(),
      );

      expect(result.isGranted, isFalse);
      expect(
        result.failureReason,
        DirectPrivateMediaPrepareFailureReason.localAuthorityMissing,
      );
      expect(
        (await fixture.rawAttachmentRow(attachmentId))!['local_path'],
        competingPath,
      );
      expect(await fixture.secureKeyStore.read(keyName), beforeKey);
      expect(await _privateState(fixture, messageId), 'available');
      expect(harness.nativeCalls, isEmpty);
    },
  );

  for (final mode in _modes) {
    test(
      'legacy done row with dangling absolute pending path is repaired at open qualification ($mode)',
      () async {
        final messageId = 'sender-legacy-dangling-$mode';
        final attachmentId = 'sender-legacy-dangling-blob-$mode';
        final pendingRelative = 'pending_uploads/$messageId/$attachmentId.jpg';
        final danglingAbsolute = p.join(
          FakeMediaFileManager.testRootPath,
          pendingRelative,
        );
        final danglingFile = File(danglingAbsolute);
        if (danglingFile.existsSync()) danglingFile.deleteSync();
        final canonicalRelative = 'media/$_contactPeerId/$attachmentId.jpg';
        final canonicalAbsolute = p.join(
          FakeMediaFileManager.testRootPath,
          canonicalRelative,
        );
        _writeBytes(canonicalAbsolute, const <int>[8, 8, 8, 8]);
        await _seedOutgoingPrivateParent(
          fixture,
          messageId: messageId,
          mode: mode,
        );
        await _insertDirectAttachmentFixtureRow(
          fixture,
          messageId: messageId,
          attachmentId: attachmentId,
          localPath: danglingAbsolute,
          downloadStatus: 'done',
          size: 4,
          encryptionKeyBase64: 'bGVnYWN5LXByaXZhdGUta2V5',
          encryptionNonce: 'bGVnYWN5LW5vbmNl',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          isBookmarked: true,
          lastPlaybackPositionMs: 7,
          uploadRetryCount: 2,
          downloadRetryCount: 1,
        );
        final before = (await fixture.rawAttachmentRow(attachmentId))!;
        final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
        final beforeKey = await fixture.secureKeyStore.read(keyName);
        final harness = _buildHarness(fixture);
        final identity = DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        );
        final result = await harness.controller.prepareResult(
          identity,
          const DirectPrivateMediaAlwaysValidContinuityGuard(),
        );

        var settled = false;
        try {
          final after = (await fixture.rawAttachmentRow(attachmentId))!;
          expect(after['local_path'], canonicalRelative);
          expect(_withoutLocalPath(after), _withoutLocalPath(before));
          expect(await fixture.secureKeyStore.read(keyName), beforeKey);
          expect(result.isGranted, isTrue);
          expect(result.grant!.localPath, canonicalAbsolute);
          final settlement = await harness.controller.settle(
            result.grant!,
            DirectPrivateMediaExitReason.preFrameDecodeFailure,
          );
          settled = true;
          expect(
            settlement.disposition,
            DirectPrivateMediaSettleDisposition.rolledBackAvailable,
          );

          final replay = await harness.controller.prepareResult(
            identity,
            const DirectPrivateMediaAlwaysValidContinuityGuard(),
          );
          try {
            expect(replay.isGranted, isTrue);
            expect(
              (await fixture.rawAttachmentRow(attachmentId))!['local_path'],
              canonicalRelative,
            );
          } finally {
            if (replay.grant != null && !replay.grant!.settled) {
              await harness.controller.settle(
                replay.grant!,
                DirectPrivateMediaExitReason.preFrameDecodeFailure,
              );
            }
          }
        } finally {
          if (!settled && result.grant != null && !result.grant!.settled) {
            await harness.controller.settle(
              result.grant!,
              DirectPrivateMediaExitReason.preFrameDecodeFailure,
            );
          }
        }
      },
    );
  }
}

Future<void> _seedOutgoingPrivateParent(
  MediaRepositoryRealDbFixture fixture, {
  required String messageId,
  required String mode,
  String contactPeerId = _contactPeerId,
}) async {
  await fixture.seedDirectParent(messageId, contactPeerId: contactPeerId);
  await fixture.db.update(
    'messages',
    <String, Object?>{
      'is_incoming': 0,
      'sender_peer_id': 'self-peer',
      'status': 'sent',
      'private_media_policy_version': 1,
      'private_media_mode': mode,
      'private_media_state': 'available',
      'private_media_received_at_ms': 1000,
      'private_media_clock_high_water_ms': 1000,
    },
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
  );
}

Future<void> _expectPendingRefusal(
  MediaRepositoryRealDbFixture fixture, {
  required _ScenarioMediaFileManager manager,
  required String messageId,
  required String attachmentId,
  required String storedPath,
  required String reason,
  String contactPeerId = _contactPeerId,
  int recordedSize = 4,
}) async {
  await _seedOutgoingPrivateParent(
    fixture,
    messageId: messageId,
    mode: 'protected',
    contactPeerId: contactPeerId,
  );
  await _insertDirectAttachmentFixtureRow(
    fixture,
    messageId: messageId,
    attachmentId: attachmentId,
    localPath: storedPath,
    downloadStatus: 'upload_pending',
    size: recordedSize,
  );
  final before = (await fixture.rawAttachmentRow(attachmentId))!;
  final harness = _buildHarness(fixture, manager: manager);
  final result = await harness.controller.prepareResult(
    DirectPrivateMediaViewerIdentity(
      messageId: messageId,
      attachmentId: attachmentId,
    ),
    const DirectPrivateMediaAlwaysValidContinuityGuard(),
  );

  expect(result.isGranted, isFalse, reason: reason);
  expect(
    result.failureReason,
    DirectPrivateMediaPrepareFailureReason.localAuthorityMissing,
    reason: reason,
  );
  expect(await fixture.rawAttachmentRow(attachmentId), before, reason: reason);
  expect(await _privateState(fixture, messageId), 'available', reason: reason);
  expect(harness.nativeCalls, isEmpty, reason: reason);
}

Future<
  ({
    String danglingAbsolute,
    String canonicalRelative,
    String canonicalAbsolute,
  })
>
_seedLegacyDanglingDone(
  MediaRepositoryRealDbFixture fixture, {
  required _ScenarioMediaFileManager manager,
  required String messageId,
  required String attachmentId,
  required String mode,
}) async {
  final danglingAbsolute = p.join(
    manager.pendingRoot,
    messageId,
    '$attachmentId.jpg',
  );
  final canonicalRelative = 'media/$_contactPeerId/$attachmentId.jpg';
  final canonicalAbsolute = p.join(
    manager.mediaRoot,
    _contactPeerId,
    '$attachmentId.jpg',
  );
  await _seedOutgoingPrivateParent(fixture, messageId: messageId, mode: mode);
  await _insertDirectAttachmentFixtureRow(
    fixture,
    messageId: messageId,
    attachmentId: attachmentId,
    localPath: danglingAbsolute,
    downloadStatus: 'done',
    size: 4,
    encryptionKeyBase64: 'bGVnYWN5LXByaXZhdGUta2V5',
    encryptionNonce: 'bGVnYWN5LW5vbmNl',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    contentHash:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    isBookmarked: true,
    lastPlaybackPositionMs: 7,
    uploadRetryCount: 2,
    downloadRetryCount: 1,
  );
  return (
    danglingAbsolute: danglingAbsolute,
    canonicalRelative: canonicalRelative,
    canonicalAbsolute: canonicalAbsolute,
  );
}

Future<void> _seedPendingTarget(
  MediaRepositoryRealDbFixture fixture, {
  required String messageId,
  required String attachmentId,
  required String mode,
  required List<int> bytes,
}) async {
  await _seedOutgoingPrivateParent(fixture, messageId: messageId, mode: mode);
  final pendingRelative = 'pending_uploads/$messageId/$attachmentId.jpg';
  _writeBytes(
    p.join(FakeMediaFileManager.testRootPath, pendingRelative),
    bytes,
  );
  await _saveDirectAttachment(
    fixture,
    messageId: messageId,
    attachmentId: attachmentId,
    localPath: pendingRelative,
    downloadStatus: 'upload_pending',
    size: bytes.length,
  );
}

Future<void> _saveDirectAttachment(
  MediaRepositoryRealDbFixture fixture, {
  required String messageId,
  required String attachmentId,
  required String localPath,
  required String downloadStatus,
  required int size,
  String? encryptionKeyBase64,
  String? encryptionNonce,
  String? encryptionScheme,
  String? contentHash,
  bool isBookmarked = false,
  int lastPlaybackPositionMs = 0,
  int? uploadRetryCount,
  int? downloadRetryCount,
}) => fixture.repo.saveAttachment(
  MediaAttachment(
    id: attachmentId,
    messageId: messageId,
    mime: 'image/jpeg',
    size: size,
    mediaType: 'image',
    width: 1,
    height: 1,
    localPath: localPath,
    downloadStatus: downloadStatus,
    createdAt: '2026-07-18T00:00:00.000Z',
    uploadRetryCount: uploadRetryCount,
    downloadRetryCount: downloadRetryCount,
    contentHash: contentHash,
    encryptionKeyBase64: encryptionKeyBase64,
    encryptionNonce: encryptionNonce,
    encryptionScheme: encryptionScheme,
    ownerLane: MediaOwnerLane.direct,
    isBookmarked: isBookmarked,
    lastPlaybackPositionMs: lastPlaybackPositionMs,
  ),
  owner: MediaOwnerLane.direct,
);

/// Seeds a deliberately pre-existing direct attachment without exercising the
/// production first-private-insert guard. These rows model legacy or malformed
/// database state that the open path must reject or repair.
Future<void> _insertDirectAttachmentFixtureRow(
  MediaRepositoryRealDbFixture fixture, {
  required String messageId,
  required String attachmentId,
  required String localPath,
  required String downloadStatus,
  required int size,
  String? encryptionKeyBase64,
  String? encryptionNonce,
  String? encryptionScheme,
  String? contentHash,
  bool isBookmarked = false,
  int lastPlaybackPositionMs = 0,
  int? uploadRetryCount,
  int? downloadRetryCount,
}) async {
  final attachment = MediaAttachment(
    id: attachmentId,
    messageId: messageId,
    mime: 'image/jpeg',
    size: size,
    mediaType: 'image',
    width: 1,
    height: 1,
    localPath: localPath,
    downloadStatus: downloadStatus,
    createdAt: '2026-07-18T00:00:00.000Z',
    uploadRetryCount: uploadRetryCount,
    downloadRetryCount: downloadRetryCount,
    contentHash: contentHash,
    encryptionKeyBase64: encryptionKeyBase64,
    encryptionNonce: encryptionNonce,
    encryptionScheme: encryptionScheme,
    ownerLane: MediaOwnerLane.direct,
    isBookmarked: isBookmarked,
    lastPlaybackPositionMs: lastPlaybackPositionMs,
  );
  final row = Map<String, Object?>.from(attachment.toMap());
  final rawKey = attachment.encryptionKeyBase64;
  if (rawKey != null && rawKey.isNotEmpty && !isSecureStoreReference(rawKey)) {
    final keyName = mediaAttachmentEncryptionKeyStoreName(attachment.id);
    await fixture.secureKeyStore.write(keyName, rawKey);
    row['encryption_key_base64'] = secureStoreReferenceForKey(keyName);
  }
  await dbInsertMediaAttachment(fixture.db, row);
}

_ControllerHarness _buildHarness(
  MediaRepositoryRealDbFixture fixture, {
  FakeMediaFileManager? manager,
}) {
  final effectiveManager = manager ?? FakeMediaFileManager();
  final adapter = DirectPrivateMediaLifecycle(
    messageRepository: fixture.messageRepo,
    mediaAttachmentRepository: fixture.repo,
    mediaFileManager: effectiveManager,
  );
  final engine = PrivateMediaLifecycleEngine(
    adapter: adapter,
    lifecycleLock: fixture.repo.lifecycleLock,
    nowMs: () => 5000,
  );
  final nativeEvents = StreamController<Object?>.broadcast();
  final nativeCalls = <String>[];
  final coordinator = PrivateMediaProtectionCoordinator(
    invokeMethod: (method, arguments) async {
      nativeCalls.add(method);
      return <String, Object?>{
        'ok': true,
        'protectionActive': method == 'enter',
      };
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
      MediaAttachment? exact;
      for (final attachment in attachments) {
        if (attachment.id != identity.attachmentId) continue;
        if (exact != null) {
          exact = null;
          break;
        }
        exact = attachment;
      }
      return DirectPrivateMediaCurrentRows(parent: parent, attachment: exact);
    },
    lifecycleEngine: engine,
    protectionCoordinator: coordinator,
  );
  addTearDown(() async {
    await controller.dispose();
    await nativeEvents.close();
  });
  return _ControllerHarness(
    adapter: adapter,
    controller: controller,
    nativeCalls: nativeCalls,
  );
}

_ScenarioMediaFileManager _newScenarioManager(String label) {
  final base = Directory.systemTemp.createTempSync('p262_$label');
  addTearDown(() async {
    if (base.existsSync()) await base.delete(recursive: true);
  });
  return _ScenarioMediaFileManager(base.path);
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

void _writeBytes(String path, List<int> bytes) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes, flush: true);
}

Map<String, Object?> _withoutLocalPath(Map<String, Object?> row) {
  final copy = Map<String, Object?>.from(row);
  copy.remove('local_path');
  return copy;
}

class _ControllerHarness {
  const _ControllerHarness({
    required this.adapter,
    required this.controller,
    required this.nativeCalls,
  });

  final DirectPrivateMediaLifecycle adapter;
  final DirectPrivateMediaViewerController controller;
  final List<String> nativeCalls;
}

class _ScenarioMediaFileManager extends FakeMediaFileManager {
  _ScenarioMediaFileManager(this.baseRoot)
    : pendingRoot = p.join(baseRoot, 'pending_uploads'),
      mediaRoot = p.join(baseRoot, 'media');

  final String baseRoot;
  final String pendingRoot;
  final String mediaRoot;

  @override
  Future<String> trustedPendingUploadRootPath() async => pendingRoot;

  @override
  Future<String> trustedMediaRootPath() async => mediaRoot;
}
