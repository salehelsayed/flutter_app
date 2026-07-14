import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/build_received_media_forward.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../domain/repositories/fake_media_attachment_repository.dart';

class _UnresolvedOwnerRepository extends FakeMediaAttachmentRepository {
  _UnresolvedOwnerRepository(this.row);

  final MediaAttachment row;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => [row];
}

class _ExactRowAwaitHookRepository extends FakeMediaAttachmentRepository {
  Future<void> Function(int callCount)? onExactRowAwait;
  int exactRowReadCount = 0;

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    final row = await super.getAttachmentById(id);
    exactRowReadCount++;
    await onExactRowAwait?.call(exactRowReadCount);
    return row;
  }
}

class _RootedMediaFileManager extends MediaFileManager {
  _RootedMediaFileManager(this.documentsDirectory);

  final Directory documentsDirectory;

  @override
  Future<String> trustedMediaRootPath() async =>
      p.join(documentsDirectory.path, 'media');

  String get snapshotRootPath => p.join(
    documentsDirectory.path,
    MediaFileManager.groupForwardSnapshotRootDirectoryName,
  );

  @override
  Future<String> groupForwardSnapshotRootPath() async => snapshotRootPath;

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    final portable = storedPath.replaceAll('\\', '/');
    if (portable.startsWith('media/')) {
      return p.join(documentsDirectory.path, portable);
    }
    final mediaIndex = portable.indexOf('/media/');
    if (mediaIndex >= 0) {
      return p.join(
        documentsDirectory.path,
        portable.substring(mediaIndex + 1),
      );
    }
    return storedPath;
  }
}

const _validJpegBytes = <int>[
  0xff,
  0xd8,
  0xff,
  0xe0,
  0x00,
  0x10,
  0x4a,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
  0x01,
  0x00,
];
const _validMp4Bytes = <int>[
  0x00,
  0x00,
  0x00,
  0x18,
  0x66,
  0x74,
  0x79,
  0x70,
  0x69,
  0x73,
  0x6f,
  0x6d,
  0x00,
  0x00,
  0x02,
  0x00,
];

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('received_forward_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  ConversationMessage parent({
    bool incoming = true,
    bool deleted = false,
    bool hidden = false,
    PrivateMediaPolicy privateMediaPolicy = const PrivateMediaPolicy.ordinary(),
    PrivateMediaLifecycleState privateMediaState =
        PrivateMediaLifecycleState.none,
  }) => ConversationMessage(
    id: 'message-1',
    contactPeerId: 'contact-1',
    senderPeerId: incoming ? 'contact-1' : 'self',
    text: 'source caption',
    timestamp: '2026-07-10T10:00:00.000Z',
    status: 'delivered',
    isIncoming: incoming,
    createdAt: '2026-07-10T10:00:00.000Z',
    dedupKey: 'source-secret-key',
    deletedAt: deleted ? '2026-07-10T10:01:00.000Z' : null,
    hiddenAt: hidden ? '2026-07-10T10:01:00.000Z' : null,
    privateMediaPolicy: privateMediaPolicy,
    privateMediaState: privateMediaState,
  );

  MediaAttachment attachment({
    required String id,
    required String path,
    String mime = 'image/jpeg',
    String status = 'done',
    MediaOwnerLane? owner = MediaOwnerLane.direct,
  }) => MediaAttachment(
    id: id,
    messageId: 'message-1',
    mime: mime,
    size: 10,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: path,
    downloadStatus: status,
    createdAt: '2026-07-10T10:00:01.000Z',
    ownerLane: owner,
  );

  Future<CanonicalGroupMediaPlaintextValidationResult> validateTestFile({
    required MediaAttachment attachment,
    required String ownerScopeId,
  }) async {
    final path = attachment.localPath;
    if (path == null || !File(path).existsSync()) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'missing_file',
      );
    }
    return CanonicalGroupMediaPlaintextValidationResult.valid(path);
  }

  MediaAttachment strongAttachment({
    required String id,
    required String localPath,
    required String mime,
    required int size,
  }) => MediaAttachment(
    id: id,
    messageId: 'message-1',
    mime: mime,
    size: size,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: localPath,
    downloadStatus: 'done',
    createdAt: '2026-07-10T10:00:01.000Z',
    contentHash: List.filled(64, 'a').join(),
    encryptionKeyBase64: 'relay-key',
    encryptionNonce: 'relay-nonce',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    ownerLane: MediaOwnerLane.direct,
  );

  String canonicalPath({required String attachmentId, required String mime}) =>
      p.join(
        tempDir.path,
        'media',
        'contact-1',
        '$attachmentId${mime == 'video/mp4' ? '.mp4' : '.jpg'}',
      );

  test(
    'builds direct owned drafts with a fresh operation token per explicit action',
    () async {
      final image = File('${tempDir.path}/one.jpg')..writeAsBytesSync([1]);
      final video = File('${tempDir.path}/two.mp4')..writeAsBytesSync([2]);
      final audio = File('${tempDir.path}/three.m4a')..writeAsBytesSync([3]);
      final repo = FakeMediaAttachmentRepository()
        ..seed([
          attachment(id: 'image', path: image.path),
          attachment(id: 'video', path: video.path, mime: 'video/mp4'),
          attachment(id: 'audio', path: audio.path, mime: 'audio/mp4'),
          attachment(
            id: 'group-collision',
            path: image.path,
            owner: MediaOwnerLane.group,
          ),
        ]);
      final tokens = ['operation-a', 'operation-b'].iterator;
      final builder = BuildReceivedMediaForward(
        loadParentMessage: (_) async => parent(),
        mediaAttachmentRepository: repo,
        operationTokenFactory: () {
          tokens.moveNext();
          return tokens.current;
        },
        validateCanonicalPlaintext: validateTestFile,
      );

      final first = await builder.build(parent: parent());
      final second = await builder.build(
        parent: parent(),
        currentAttachmentId: 'video',
      );

      expect(first.denial, isNull);
      expect(first.draft!.shareIntent.filePaths, [image.path, video.path]);
      expect(first.draft!.shareIntent.text, 'source caption');
      expect(
        first.draft!.shareIntent.forwardProvenance!.operationDedupKey,
        'operation-a',
      );
      expect(second.draft!.shareIntent.filePaths, [video.path]);
      expect(
        second.draft!.shareIntent.forwardProvenance!.operationDedupKey,
        'operation-b',
      );
      expect(
        first.draft!.shareIntent.forwardProvenance!.operationDedupKey,
        isNot(anyOf('message-1', 'contact-1', 'source-secret-key')),
      );
      expect(
        repo.getAttachmentsForMessageCallCount,
        greaterThanOrEqualTo(2),
        reason: 'each exact source is reloaded before a draft is released',
      );
    },
  );

  test(
    'ineligible or unresolved source media fails closed before the picker',
    () async {
      final present = File('${tempDir.path}/present.jpg')
        ..writeAsBytesSync([1]);
      var tokenMintCount = 0;

      Future<ReceivedMediaForwardBuildResult> run({
        bool incoming = true,
        bool deleted = false,
        String status = 'done',
        MediaOwnerLane? owner = MediaOwnerLane.direct,
        String? path,
      }) {
        final row = attachment(
          id: 'candidate',
          path: path ?? present.path,
          status: status,
          owner: owner,
        );
        final repo = owner == null
            ? _UnresolvedOwnerRepository(row)
            : (FakeMediaAttachmentRepository()..seed([row]));
        final currentParent = parent(incoming: incoming, deleted: deleted);
        return BuildReceivedMediaForward(
          loadParentMessage: (_) async => currentParent,
          mediaAttachmentRepository: repo,
          operationTokenFactory: () {
            tokenMintCount++;
            return 'must-not-mint';
          },
          validateCanonicalPlaintext: validateTestFile,
        ).build(parent: currentParent);
      }

      expect(
        (await run(deleted: true)).denial,
        DirectMediaForwardDenial.parentDeleted,
      );
      expect(
        (await run(incoming: false)).denial,
        DirectMediaForwardDenial.parentNotIncoming,
      );
      expect(
        (await run(status: 'pending')).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(
        (await run(status: 'downloading')).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(
        (await run(status: 'evicted')).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(
        (await run(status: 'integrity_failed')).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(
        (await run(owner: null)).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(
        (await run(path: '${tempDir.path}/missing.jpg')).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(tokenMintCount, 0);
    },
  );

  test(
    'accepts exact stale-iOS JPEG and MP4 sources and returns current canonical paths',
    () async {
      final manager = _RootedMediaFileManager(tempDir);
      for (final mediaCase in <({String id, String mime, List<int> bytes})>[
        (id: 'stale-jpeg', mime: 'image/jpeg', bytes: _validJpegBytes),
        (id: 'stale-mp4', mime: 'video/mp4', bytes: _validMp4Bytes),
      ]) {
        final canonical = File(
          canonicalPath(attachmentId: mediaCase.id, mime: mediaCase.mime),
        );
        canonical.parent.createSync(recursive: true);
        canonical.writeAsBytesSync(mediaCase.bytes);
        final relative = p.join(
          'media',
          'contact-1',
          '${mediaCase.id}${mediaCase.mime == 'video/mp4' ? '.mp4' : '.jpg'}',
        );
        final staleIosPath =
            '/var/mobile/Containers/Data/Application/STALE/Documents/$relative';
        final repo = FakeMediaAttachmentRepository()
          ..seed([
            strongAttachment(
              id: mediaCase.id,
              localPath: staleIosPath,
              mime: mediaCase.mime,
              size: mediaCase.bytes.length,
            ),
          ]);

        final result = await BuildReceivedMediaForward(
          loadParentMessage: (_) async => parent(),
          mediaAttachmentRepository: repo,
          mediaFileManager: manager,
          operationTokenFactory: () => 'operation-${mediaCase.id}',
        ).build(parent: parent(), currentAttachmentId: mediaCase.id);

        expect(result.denial, isNull, reason: mediaCase.id);
        expect(result.draft!.shareIntent.filePaths, [canonical.path]);
        expect(
          result.draft!.shareIntent.directForwardSourceAuthority!.attachmentIds,
          [mediaCase.id],
        );
      }
    },
  );

  test(
    'denies noncanonical, traversal, symlink, non-file, size, and signature sources before token mint',
    () async {
      final manager = _RootedMediaFileManager(tempDir);
      var tokenMintCount = 0;

      Future<void> expectDenied({
        required String label,
        required String id,
        required String storedPath,
        List<int> bytes = _validJpegBytes,
        int? declaredSize,
        bool makeSymlink = false,
        bool makeDirectory = false,
      }) async {
        final canonical = File(
          canonicalPath(attachmentId: id, mime: 'image/jpeg'),
        );
        canonical.parent.createSync(recursive: true);
        if (makeSymlink) {
          final outside = File(p.join(tempDir.path, 'outside-$id.jpg'))
            ..writeAsBytesSync(bytes);
          Link(canonical.path).createSync(outside.path);
        } else if (makeDirectory) {
          Directory(canonical.path).createSync();
        } else {
          canonical.writeAsBytesSync(bytes);
        }
        final repo = FakeMediaAttachmentRepository()
          ..seed([
            strongAttachment(
              id: id,
              localPath: storedPath,
              mime: 'image/jpeg',
              size: declaredSize ?? bytes.length,
            ),
          ]);
        final result = await BuildReceivedMediaForward(
          loadParentMessage: (_) async => parent(),
          mediaAttachmentRepository: repo,
          mediaFileManager: manager,
          operationTokenFactory: () {
            tokenMintCount++;
            return 'must-not-mint';
          },
        ).build(parent: parent(), currentAttachmentId: id);

        expect(result.draft, isNull, reason: label);
        expect(result.denial, isNotNull, reason: label);
      }

      await expectDenied(
        label: 'noncanonical relative path',
        id: 'bad-relative',
        storedPath: 'media/contact-1/not-bad-relative.jpg',
      );
      final outsideAbsolute = File(p.join(tempDir.path, 'absolute.jpg'))
        ..writeAsBytesSync(_validJpegBytes);
      await expectDenied(
        label: 'arbitrary absolute path',
        id: 'bad-absolute',
        storedPath: outsideAbsolute.path,
      );
      await expectDenied(
        label: 'parent traversal path',
        id: 'bad-traversal',
        storedPath: 'media/contact-1/../contact-1/bad-traversal.jpg',
      );
      await expectDenied(
        label: 'canonical symlink',
        id: 'bad-symlink',
        storedPath: 'media/contact-1/bad-symlink.jpg',
        makeSymlink: true,
      );
      await expectDenied(
        label: 'canonical directory',
        id: 'bad-directory',
        storedPath: 'media/contact-1/bad-directory.jpg',
        makeDirectory: true,
      );
      await expectDenied(
        label: 'size mismatch',
        id: 'bad-size',
        storedPath: 'media/contact-1/bad-size.jpg',
        declaredSize: _validJpegBytes.length + 1,
      );
      await expectDenied(
        label: 'MIME signature mismatch',
        id: 'bad-signature',
        storedPath: 'media/contact-1/bad-signature.jpg',
        bytes: _validMp4Bytes,
      );
      expect(tokenMintCount, 0);
    },
  );

  test(
    'paused parent, row, and file drift fails closed before a draft or token',
    () async {
      for (final scenario in <String>[
        'deleted',
        'hidden',
        'private',
        'terminal',
        'path',
        'file',
      ]) {
        final id = 'drift-$scenario';
        final canonical = File(
          canonicalPath(attachmentId: id, mime: 'image/jpeg'),
        );
        canonical.parent.createSync(recursive: true);
        canonical.writeAsBytesSync(_validJpegBytes);
        final row = strongAttachment(
          id: id,
          localPath: 'media/contact-1/$id.jpg',
          mime: 'image/jpeg',
          size: _validJpegBytes.length,
        );
        final repo = FakeMediaAttachmentRepository()..seed([row]);
        var currentParent = parent();
        var tokenMintCount = 0;
        final builder = BuildReceivedMediaForward(
          loadParentMessage: (_) async => currentParent,
          mediaAttachmentRepository: repo,
          mediaFileManager: _RootedMediaFileManager(tempDir),
          operationTokenFactory: () {
            tokenMintCount++;
            return 'must-not-mint';
          },
          beforeFinalSourceRecheck: () async {
            switch (scenario) {
              case 'deleted':
                currentParent = currentParent.copyWith(
                  deletedAt: '2026-07-10T10:02:00.000Z',
                );
              case 'hidden':
                currentParent = currentParent.copyWith(
                  hiddenAt: '2026-07-10T10:02:00.000Z',
                );
              case 'private':
                currentParent = currentParent.copyWith(
                  privateMediaPolicy: const PrivateMediaPolicy.protected(),
                  privateMediaState: PrivateMediaLifecycleState.available,
                );
              case 'terminal':
                currentParent = currentParent.copyWith(
                  privateMediaPolicy: const PrivateMediaPolicy.viewOnce(),
                  privateMediaState: PrivateMediaLifecycleState.consumed,
                );
              case 'path':
                await repo.saveAttachment(
                  row.copyWith(
                    localPath: 'media/contact-1/drifted-elsewhere.jpg',
                  ),
                  owner: MediaOwnerLane.direct,
                );
              case 'file':
                canonical.deleteSync();
            }
          },
        );

        final result = await builder.build(
          parent: parent(),
          currentAttachmentId: id,
        );
        expect(result.draft, isNull, reason: scenario);
        expect(result.denial, isNotNull, reason: scenario);
        expect(tokenMintCount, 0, reason: scenario);
      }
    },
  );

  test(
    'dispatch capture owns immutable bytes until its lease is disposed',
    () async {
      final id = 'immutable-capture';
      final canonical = File(
        canonicalPath(attachmentId: id, mime: 'image/jpeg'),
      );
      canonical.parent.createSync(recursive: true);
      canonical.writeAsBytesSync(_validJpegBytes);
      final repo = FakeMediaAttachmentRepository()
        ..seed([
          strongAttachment(
            id: id,
            localPath: 'media/contact-1/$id.jpg',
            mime: 'image/jpeg',
            size: _validJpegBytes.length,
          ),
        ]);
      final builder = BuildReceivedMediaForward(
        loadParentMessage: (_) async => parent(),
        mediaAttachmentRepository: repo,
        mediaFileManager: _RootedMediaFileManager(tempDir),
        operationTokenFactory: () => 'immutable-operation',
      );
      final draft = await builder.build(
        parent: parent(),
        currentAttachmentId: id,
      );
      final capture = await builder.captureForDispatch(
        draft.draft!.shareIntent,
      );
      final lease = capture.lease!;
      final snapshot = File(lease.shareIntent.filePaths.single);

      expect(snapshot.path, isNot(canonical.path));
      expect(snapshot.readAsBytesSync(), _validJpegBytes);
      canonical.deleteSync();
      expect(snapshot.readAsBytesSync(), _validJpegBytes);

      await lease.dispose();
      expect(snapshot.existsSync(), isFalse);
    },
  );

  test(
    'dispatch fails closed when an exact security row mutates during snapshot copy',
    () async {
      const id = 'copy-row-drift';
      final canonical = File(
        canonicalPath(attachmentId: id, mime: 'image/jpeg'),
      );
      canonical.parent.createSync(recursive: true);
      canonical.writeAsBytesSync(_validJpegBytes);
      final row = strongAttachment(
        id: id,
        localPath: 'media/contact-1/$id.jpg',
        mime: 'image/jpeg',
        size: _validJpegBytes.length,
      );
      final repo = FakeMediaAttachmentRepository()..seed([row]);
      final builder = BuildReceivedMediaForward(
        loadParentMessage: (_) async => parent(),
        mediaAttachmentRepository: repo,
        mediaFileManager: _RootedMediaFileManager(tempDir),
        operationTokenFactory: () => 'copy-row-drift-operation',
        copySnapshot:
            ({required String sourcePath, required String snapshotPath}) async {
              await File(sourcePath).copy(snapshotPath);
              await repo.saveAttachment(
                row.copyWith(contentHash: List.filled(64, 'b').join()),
                owner: MediaOwnerLane.direct,
              );
            },
      );
      final draft = await builder.build(
        parent: parent(),
        currentAttachmentId: id,
      );

      final capture = await builder.captureForDispatch(
        draft.draft!.shareIntent,
      );

      expect(capture.lease, isNull);
      expect(
        capture.denial,
        DirectMediaForwardDenial.currentAttachmentNotEligible,
      );
    },
  );

  test(
    'dispatch final row reload detects security drift during canonical validation',
    () async {
      const id = 'final-validator-row-drift';
      final canonical = File(
        canonicalPath(attachmentId: id, mime: 'image/jpeg'),
      );
      canonical.parent.createSync(recursive: true);
      canonical.writeAsBytesSync(_validJpegBytes);
      final row = strongAttachment(
        id: id,
        localPath: 'media/contact-1/$id.jpg',
        mime: 'image/jpeg',
        size: _validJpegBytes.length,
      );
      final repo = FakeMediaAttachmentRepository()..seed([row]);
      final manager = _RootedMediaFileManager(tempDir);
      var validationCalls = 0;
      final builder = BuildReceivedMediaForward(
        loadParentMessage: (_) async => parent(),
        mediaAttachmentRepository: repo,
        mediaFileManager: manager,
        operationTokenFactory: () => 'validator-row-drift-operation',
        validateCanonicalPlaintext:
            ({
              required MediaAttachment attachment,
              required String ownerScopeId,
            }) async {
              validationCalls++;
              final validation =
                  await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
                    attachment: attachment,
                    ownerScopeId: ownerScopeId,
                    mediaFileManager: manager,
                  );
              if (validationCalls == 5) {
                await repo.saveAttachment(
                  row.copyWith(encryptionNonce: 'drifted-relay-nonce'),
                  owner: MediaOwnerLane.direct,
                );
              }
              return validation;
            },
      );
      final draft = await builder.build(
        parent: parent(),
        currentAttachmentId: id,
      );

      final capture = await builder.captureForDispatch(
        draft.draft!.shareIntent,
      );

      expect(validationCalls, 5);
      expect(capture.lease, isNull);
      expect(
        capture.denial,
        DirectMediaForwardDenial.currentAttachmentNotEligible,
      );
    },
  );

  test(
    'dispatch final parent authority denies delete hidden private and terminal drift during exact-row await',
    () async {
      for (final scenario in <String>[
        'deleted',
        'hidden',
        'private',
        'terminal',
      ]) {
        final id = 'final-parent-$scenario';
        final canonical = File(
          canonicalPath(attachmentId: id, mime: 'image/jpeg'),
        );
        canonical.parent.createSync(recursive: true);
        canonical.writeAsBytesSync(_validJpegBytes);
        final row = strongAttachment(
          id: id,
          localPath: 'media/contact-1/$id.jpg',
          mime: 'image/jpeg',
          size: _validJpegBytes.length,
        );
        var currentParent = parent();
        var mutationCount = 0;
        final repo = _ExactRowAwaitHookRepository()..seed([row]);
        repo.onExactRowAwait = (callCount) async {
          // Build consumes reads 1-2; capture preflight consumes 3-4. Read 5
          // occurs only after the immutable snapshot has been copied.
          if (callCount != 5) return;
          currentParent = switch (scenario) {
            'deleted' => currentParent.copyWith(
              deletedAt: '2026-07-14T12:00:00.000Z',
            ),
            'hidden' => currentParent.copyWith(
              hiddenAt: '2026-07-14T12:00:00.000Z',
            ),
            'private' => currentParent.copyWith(
              privateMediaPolicy: const PrivateMediaPolicy.protected(),
              privateMediaState: PrivateMediaLifecycleState.available,
            ),
            _ => currentParent.copyWith(
              privateMediaPolicy: const PrivateMediaPolicy.viewOnce(),
              privateMediaState: PrivateMediaLifecycleState.consumed,
            ),
          };
          mutationCount++;
          await Future<void>.delayed(Duration.zero);
        };
        final manager = _RootedMediaFileManager(tempDir);
        final builder = BuildReceivedMediaForward(
          loadParentMessage: (_) async => currentParent,
          mediaAttachmentRepository: repo,
          mediaFileManager: manager,
          operationTokenFactory: () => 'final-parent-$scenario-operation',
        );
        final draft = await builder.build(
          parent: currentParent,
          currentAttachmentId: id,
        );

        final capture = await builder.captureForDispatch(
          draft.draft!.shareIntent,
        );

        expect(mutationCount, 1, reason: scenario);
        expect(capture.lease, isNull, reason: scenario);
        expect(capture.denial, isNotNull, reason: scenario);
        final snapshotRoot = Directory(manager.snapshotRootPath);
        expect(
          snapshotRoot.existsSync() ? snapshotRoot.listSync() : const [],
          isEmpty,
          reason: '$scenario snapshot lease must be disposed',
        );
      }
    },
  );

  test(
    'lifecycle-lock queued row mutation cannot interleave before draft qualification returns',
    () async {
      const id = 'queued-lock-row-drift';
      final canonical = File(
        canonicalPath(attachmentId: id, mime: 'image/jpeg'),
      );
      canonical.parent.createSync(recursive: true);
      canonical.writeAsBytesSync(_validJpegBytes);
      final row = strongAttachment(
        id: id,
        localPath: 'media/contact-1/$id.jpg',
        mime: 'image/jpeg',
        size: _validJpegBytes.length,
      );
      final repo = FakeMediaAttachmentRepository()..seed([row]);
      final manager = _RootedMediaFileManager(tempDir);
      final lifecycleLock = MediaAttachmentLifecycleLock();
      final mutationEntered = Completer<void>();
      late Future<void> queuedMutation;
      var queued = false;
      var interleavedDuringValidation = false;
      var tokenMintedBeforeMutation = false;
      final builder = BuildReceivedMediaForward(
        loadParentMessage: (_) async => parent(),
        mediaAttachmentRepository: repo,
        mediaFileManager: manager,
        lifecycleLock: lifecycleLock,
        operationTokenFactory: () {
          tokenMintedBeforeMutation = !mutationEntered.isCompleted;
          return 'queued-lock-row-operation';
        },
        validateCanonicalPlaintext:
            ({
              required MediaAttachment attachment,
              required String ownerScopeId,
            }) async {
              if (!queued) {
                queued = true;
                Zone.root.run(() {
                  queuedMutation = lifecycleLock.synchronized(id, () async {
                    mutationEntered.complete();
                    await repo.saveAttachment(
                      row.copyWith(encryptionNonce: 'queued-relay-nonce'),
                      owner: MediaOwnerLane.direct,
                    );
                  });
                });
                await Future<void>.delayed(Duration.zero);
                interleavedDuringValidation = mutationEntered.isCompleted;
              }
              return GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
                attachment: attachment,
                ownerScopeId: ownerScopeId,
                mediaFileManager: manager,
              );
            },
      );

      final result = await builder.build(
        parent: parent(),
        currentAttachmentId: id,
      );
      await queuedMutation;

      expect(result.denial, isNull);
      expect(result.draft, isNotNull);
      expect(interleavedDuringValidation, isFalse);
      expect(tokenMintedBeforeMutation, isTrue);
      expect(mutationEntered.isCompleted, isTrue);
      expect(
        (await repo.getAttachmentById(id))!.encryptionNonce,
        'queued-relay-nonce',
      );
    },
  );
}
