import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/nth_exact_media_read_gated_repository.dart';
import '../../../shared/fixtures/media_bytes.dart';

const _groupId = 'preview-group';
const _relayCiphertextHash =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
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
  0x00,
  0x00,
  0x69,
  0x73,
  0x6f,
  0x6d,
];

void main() {
  late InMemoryGroupRepository groups;
  late InMemoryGroupMessageRepository messages;
  late InMemoryMediaAttachmentRepository media;
  late FakeMediaFileManager files;
  late Set<String> cleanupPaths;

  setUp(() async {
    groups = InMemoryGroupRepository();
    messages = InMemoryGroupMessageRepository();
    media = InMemoryMediaAttachmentRepository();
    files = FakeMediaFileManager();
    cleanupPaths = <String>{};
    await groups.saveGroup(_group());
  });

  tearDown(() {
    for (final path in cleanupPaths) {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        Link(path).deleteSync();
      } else if (type == FileSystemEntityType.file) {
        File(path).deleteSync();
      } else if (type == FileSystemEntityType.directory) {
        Directory(path).deleteSync(recursive: true);
      }
    }
  });

  Future<({String canonicalPath, MediaAttachment attachment})> seedSource({
    required String messageId,
    required String attachmentId,
    List<int> bytes = validJpegFixtureBytes,
    String mime = 'image/jpeg',
    String mediaType = 'image',
    String? storedPath,
    int? declaredSize,
    InMemoryGroupMessageRepository? messageRepository,
    InMemoryMediaAttachmentRepository? mediaRepository,
    FakeMediaFileManager? fileManager,
  }) async {
    final effectiveMessages = messageRepository ?? messages;
    final effectiveMedia = mediaRepository ?? media;
    final effectiveFiles = fileManager ?? files;
    await effectiveMessages.saveMessage(_message(messageId));
    final canonicalPath = await effectiveFiles.localPathForAttachment(
      contactPeerId: _groupId,
      blobId: attachmentId,
      mime: mime,
    );
    File(canonicalPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    cleanupPaths.add(canonicalPath);
    final attachment = MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: mime,
      size: declaredSize ?? bytes.length,
      mediaType: mediaType,
      localPath:
          storedPath ??
          effectiveFiles.relativePathForAttachment(
            contactPeerId: _groupId,
            blobId: attachmentId,
            mime: mime,
          ),
      downloadStatus: kMediaDownloadStatusDone,
      createdAt: '2026-07-14T00:00:00.000Z',
      contentHash: _relayCiphertextHash,
      encryptionKeyBase64: 'a2V5',
      encryptionNonce: 'bm9uY2U=',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      ownerLane: MediaOwnerLane.group,
    );
    await effectiveMedia.saveAttachment(
      attachment,
      owner: MediaOwnerLane.group,
    );
    return (canonicalPath: canonicalPath, attachment: attachment);
  }

  GroupMediaForwardPreviewGate gate({
    InMemoryGroupMessageRepository? messageRepository,
    InMemoryMediaAttachmentRepository? mediaRepository,
    FakeMediaFileManager? fileManager,
    MediaAttachmentLifecycleLock? lifecycleLock,
  }) => GroupMediaForwardPreviewGate(
    groupRepository: groups,
    messageRepository: messageRepository ?? messages,
    mediaAttachmentRepository: mediaRepository ?? media,
    mediaFileManager: fileManager ?? files,
    lifecycleLock: lifecycleLock,
  );

  test(
    'GMF-01P preview accepts current JPEG and stale-iOS rerooted MP4 canonical plaintext',
    () async {
      final jpeg = await seedSource(
        messageId: 'preview-jpeg-message',
        attachmentId: 'preview-jpeg',
      );
      final jpegResult = await gate().verify(
        groupType: GroupType.chat,
        request: _request('preview-jpeg-message', 'preview-jpeg'),
      );
      expect(jpegResult.resolvedPath, jpeg.canonicalPath);

      const mp4AttachmentId = 'preview-video';
      final staleIosPath =
          '/private/var/mobile/Containers/Data/Application/OLD/Documents/'
          'media/$_groupId/$mp4AttachmentId.mp4';
      final mp4 = await seedSource(
        messageId: 'preview-video-message',
        attachmentId: mp4AttachmentId,
        bytes: _validMp4Bytes,
        mime: 'video/mp4',
        mediaType: 'video',
        storedPath: staleIosPath,
      );
      final mp4Result = await gate().verify(
        groupType: GroupType.chat,
        request: _request('preview-video-message', mp4AttachmentId),
      );
      expect(mp4Result.resolvedPath, mp4.canonicalPath);
      expect(files.resolveStoredPathCount, 1);
    },
  );

  test(
    'GMF-01P preview denies unsafe noncanonical symlink size and signature sources without a path',
    () async {
      final unsafe = await gate().verify(
        groupType: GroupType.chat,
        request: _request('unsafe-message', '../unsafe'),
      );
      expect(unsafe.denialReason, 'unsafe_attachment_id');
      expect(unsafe.resolvedPath, isNull);

      final noncanonicalOutside = File(
        p.join(Directory.systemTemp.path, 'preview_noncanonical_$pid.jpg'),
      )..writeAsBytesSync(validJpegFixtureBytes);
      cleanupPaths.add(noncanonicalOutside.path);
      await seedSource(
        messageId: 'preview-noncanonical-message',
        attachmentId: 'preview-noncanonical',
        storedPath: noncanonicalOutside.path,
      );
      final noncanonical = await gate().verify(
        groupType: GroupType.chat,
        request: _request(
          'preview-noncanonical-message',
          'preview-noncanonical',
        ),
      );
      expect(noncanonical.denialReason, 'noncanonical_local_path');
      expect(noncanonical.resolvedPath, isNull);

      final symlinkSeed = await seedSource(
        messageId: 'preview-symlink-message',
        attachmentId: 'preview-symlink',
      );
      File(symlinkSeed.canonicalPath).deleteSync();
      final symlinkTarget = File(
        p.join(Directory.systemTemp.path, 'preview_symlink_target_$pid.jpg'),
      )..writeAsBytesSync(validJpegFixtureBytes);
      cleanupPaths.add(symlinkTarget.path);
      Link(symlinkSeed.canonicalPath).createSync(symlinkTarget.path);
      final symlink = await gate().verify(
        groupType: GroupType.chat,
        request: _request('preview-symlink-message', 'preview-symlink'),
      );
      expect(symlink.denialReason, 'unsafe_or_missing_local_file');
      expect(symlink.resolvedPath, isNull);

      await seedSource(
        messageId: 'preview-size-message',
        attachmentId: 'preview-size',
        declaredSize: validJpegFixtureBytes.length + 1,
      );
      final size = await gate().verify(
        groupType: GroupType.chat,
        request: _request('preview-size-message', 'preview-size'),
      );
      expect(size.denialReason, 'plaintext_size_mismatch');
      expect(size.resolvedPath, isNull);

      final invalidSignature = List<int>.filled(
        validJpegFixtureBytes.length,
        0x31,
      );
      await seedSource(
        messageId: 'preview-signature-message',
        attachmentId: 'preview-signature',
        bytes: invalidSignature,
      );
      final signature = await gate().verify(
        groupType: GroupType.chat,
        request: _request('preview-signature-message', 'preview-signature'),
      );
      expect(signature.denialReason, 'unknown_signature');
      expect(signature.resolvedPath, isNull);
    },
  );

  test(
    'GMF-01P preview rechecks private deletion terminal and expired drift after awaited work',
    () async {
      final deletionGated = _GatedDeletionStateMessages(gateAtCall: 1);
      await seedSource(
        messageId: 'preview-private-message',
        attachmentId: 'preview-private',
        messageRepository: deletionGated,
      );
      final privateFuture = gate(messageRepository: deletionGated).verify(
        groupType: GroupType.chat,
        request: _request('preview-private-message', 'preview-private'),
      );
      await deletionGated.captured.future.timeout(const Duration(seconds: 2));
      await deletionGated.saveMessage(
        _message(
          'preview-private-message',
          policy: const GroupPrivateMediaPolicy.viewOnce(),
        ),
      );
      deletionGated.release.complete();
      final privateResult = await privateFuture;
      expect(privateResult.denialReason, 'lifecycle_restricted');
      expect(privateResult.resolvedPath, isNull);

      final pathGatedFiles = _GatedTrustedRootMediaFileManager();
      final deletedMessages = InMemoryGroupMessageRepository();
      await seedSource(
        messageId: 'preview-deleted-message',
        attachmentId: 'preview-deleted',
        messageRepository: deletedMessages,
        fileManager: pathGatedFiles,
      );
      final deletedFuture =
          gate(
            messageRepository: deletedMessages,
            fileManager: pathGatedFiles,
          ).verify(
            groupType: GroupType.chat,
            request: _request('preview-deleted-message', 'preview-deleted'),
          );
      await pathGatedFiles.captured.future.timeout(const Duration(seconds: 2));
      await deletedMessages.deleteMessage('preview-deleted-message');
      pathGatedFiles.release.complete();
      final deletedResult = await deletedFuture;
      expect(deletedResult.denialReason, 'parent_missing');
      expect(deletedResult.resolvedPath, isNull);

      for (final state in const ['terminal', 'expired']) {
        final finalReadGated = _GatedParentReadMessages(gateAtCall: 3);
        final attachmentId = 'preview-$state';
        final messageId = 'preview-$state-message';
        await seedSource(
          messageId: messageId,
          attachmentId: attachmentId,
          messageRepository: finalReadGated,
        );
        final future = gate(messageRepository: finalReadGated).verify(
          groupType: GroupType.chat,
          request: _request(messageId, attachmentId),
        );
        await finalReadGated.captured.future.timeout(
          const Duration(seconds: 2),
        );
        await finalReadGated.saveMessage(
          _message(
            messageId,
            cleanupPending: state == 'terminal',
            expiredAt: state == 'expired' ? 1 : null,
          ),
        );
        finalReadGated.release.complete();
        final result = await future;
        expect(result.denialReason, 'lifecycle_restricted', reason: state);
        expect(result.resolvedPath, isNull, reason: state);
      }
    },
  );

  test(
    'GMF-01S preview final-validator row drift denies every load-bearing mutation without a path',
    () async {
      final mutations =
          <String, Future<void> Function(MediaAttachment attachment)>{
            'localPath': (attachment) => media.updateLocalPath(
              attachment.id,
              'media/$_groupId/${attachment.id}-moved.jpg',
            ),
            'status': (attachment) =>
                media.updateDownloadStatus(attachment.id, 'evicted'),
            'size': (attachment) => media.saveAttachment(
              attachment.copyWith(size: attachment.size + 1),
              owner: MediaOwnerLane.group,
            ),
            'signature metadata': (attachment) => media.saveAttachment(
              attachment.copyWith(mime: 'image/png'),
              owner: MediaOwnerLane.group,
            ),
            'relay hash metadata': (attachment) => media.saveAttachment(
              attachment.copyWith(clearContentHash: true),
              owner: MediaOwnerLane.group,
            ),
            'encryption metadata': (attachment) => media.saveAttachment(
              attachment.copyWith(clearEncryptionNonce: true),
              owner: MediaOwnerLane.group,
            ),
          };

      for (final mutation in mutations.entries) {
        final suffix = mutation.key.replaceAll(' ', '-');
        final messageId = 'preview-validator-$suffix-message';
        final attachmentId = 'preview-validator-$suffix';
        final gatedFiles = _GatedTrustedRootMediaFileManager();
        addTearDown(() {
          if (!gatedFiles.release.isCompleted) {
            gatedFiles.release.complete();
          }
        });
        final seeded = await seedSource(
          messageId: messageId,
          attachmentId: attachmentId,
          fileManager: gatedFiles,
        );
        final verification = gate(fileManager: gatedFiles).verify(
          groupType: GroupType.chat,
          request: _request(messageId, attachmentId),
        );

        await gatedFiles.captured.future.timeout(const Duration(seconds: 2));
        await mutation.value(seeded.attachment);
        gatedFiles.release.complete();

        final result = await verification;
        expect(result.denialReason, 'attachment_changed', reason: mutation.key);
        expect(result.resolvedPath, isNull, reason: mutation.key);
      }
    },
  );

  test(
    'GMF-01O preview final parent authority catches every drift during exact-row await',
    () async {
      for (final drift in const <String>[
        'group',
        'parent',
        'tombstone',
        'private',
        'expired',
        'cleanup',
      ]) {
        final messageId = 'preview-final-$drift-message';
        final attachmentId = 'preview-final-$drift-attachment';
        final currentMessages = InMemoryGroupMessageRepository();
        final exactRowAwait = NthExactMediaReadGatedRepository(gateAtCall: 2);
        addTearDown(() {
          if (!exactRowAwait.release.isCompleted) {
            exactRowAwait.release.complete();
          }
        });
        await groups.saveGroup(_group());
        await seedSource(
          messageId: messageId,
          attachmentId: attachmentId,
          messageRepository: currentMessages,
          mediaRepository: exactRowAwait,
        );
        final verification =
            gate(
              messageRepository: currentMessages,
              mediaRepository: exactRowAwait,
            ).verify(
              groupType: GroupType.chat,
              request: _request(messageId, attachmentId),
            );

        await exactRowAwait.captured.future.timeout(const Duration(seconds: 2));
        switch (drift) {
          case 'group':
            await groups.saveGroup(_group().copyWith(type: GroupType.qa));
          case 'parent':
            await currentMessages.deleteMessageForMembershipRepair(messageId);
          case 'tombstone':
            currentMessages.seedLocalDeletion(
              messageId: messageId,
              groupId: _groupId,
            );
          case 'private':
            await currentMessages.saveMessage(
              _message(
                messageId,
                policy: const GroupPrivateMediaPolicy.viewOnce(),
              ),
            );
          case 'expired':
            await currentMessages.saveMessage(
              _message(messageId, expiredAt: 1),
            );
          case 'cleanup':
            await currentMessages.saveMessage(
              _message(messageId, cleanupPending: true),
            );
        }
        exactRowAwait.release.complete();

        final result = await verification;
        expect(
          result.denialReason,
          drift == 'group'
              ? 'source_group_not_forwardable'
              : drift == 'parent' || drift == 'tombstone'
              ? 'parent_missing'
              : 'lifecycle_restricted',
          reason: drift,
        );
        expect(result.resolvedPath, isNull, reason: drift);
      }
    },
  );

  test(
    'GMF-01O lifecycle-queued mutation cannot interleave before preview qualifier returns',
    () async {
      final lifecycleLock = MediaAttachmentLifecycleLock();
      final pathGatedFiles = _GatedTrustedRootMediaFileManager();
      addTearDown(() {
        if (!pathGatedFiles.release.isCompleted) {
          pathGatedFiles.release.complete();
        }
      });
      await seedSource(
        messageId: 'preview-lock-message',
        attachmentId: 'preview-lock',
        fileManager: pathGatedFiles,
      );
      final previewFuture =
          gate(
            fileManager: pathGatedFiles,
            lifecycleLock: lifecycleLock,
          ).verify(
            groupType: GroupType.chat,
            request: _request('preview-lock-message', 'preview-lock'),
          );
      await pathGatedFiles.captured.future.timeout(const Duration(seconds: 2));

      var mutationRan = false;
      final mutation = lifecycleLock.synchronized('preview-lock', () async {
        mutationRan = true;
        await media.updateDownloadStatus('preview-lock', 'evicted');
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        mutationRan,
        isFalse,
        reason: 'the same-ID mutation must queue behind qualification',
      );

      pathGatedFiles.release.complete();
      expect((await previewFuture).isVerified, isTrue);
      await mutation;
      expect(mutationRan, isTrue);
      final rows = await media.getAttachmentsForMessage(
        'preview-lock-message',
        owner: MediaOwnerLane.group,
      );
      expect(rows.single.downloadStatus, 'evicted');
    },
  );
}

GroupModel _group() => GroupModel(
  id: _groupId,
  name: 'Preview group',
  type: GroupType.chat,
  topicName: 'preview-topic',
  createdAt: DateTime.utc(2026, 7, 14),
  createdBy: 'peer-sender',
  myRole: GroupRole.member,
);

GroupMessage _message(
  String id, {
  GroupPrivateMediaPolicy policy = const GroupPrivateMediaPolicy.ordinary(),
  int? expiredAt,
  bool cleanupPending = false,
}) => GroupMessage(
  id: id,
  groupId: _groupId,
  senderPeerId: 'peer-sender',
  text: 'preview',
  timestamp: DateTime.utc(2026, 7, 14),
  isIncoming: true,
  createdAt: DateTime.utc(2026, 7, 14),
  privateMediaPolicy: policy,
  mediaExpiredAt: expiredAt,
  mediaCleanupPending: cleanupPending,
);

GroupMediaForwardRequest _request(String messageId, String attachmentId) =>
    GroupMediaForwardRequest(
      groupId: _groupId,
      messageId: messageId,
      attachmentId: attachmentId,
      initialCaption: 'preview',
      provenance: const ForwardProvenance(operationDedupKey: 'preview-op'),
    );

class _GatedDeletionStateMessages extends InMemoryGroupMessageRepository {
  _GatedDeletionStateMessages({required this.gateAtCall});

  final int gateAtCall;
  final Completer<void> captured = Completer<void>();
  final Completer<void> release = Completer<void>();
  int _calls = 0;

  @override
  Future<GroupMessageLocalDeletionState> getGroupMessageLocalDeletionState(
    String messageId,
  ) async {
    _calls++;
    if (_calls == gateAtCall) {
      captured.complete();
      await release.future;
    }
    return super.getGroupMessageLocalDeletionState(messageId);
  }
}

class _GatedParentReadMessages extends InMemoryGroupMessageRepository {
  _GatedParentReadMessages({required this.gateAtCall});

  final int gateAtCall;
  final Completer<void> captured = Completer<void>();
  final Completer<void> release = Completer<void>();
  int _calls = 0;

  @override
  Future<GroupMessage?> getMessage(String id) async {
    _calls++;
    if (_calls == gateAtCall) {
      captured.complete();
      await release.future;
    }
    return super.getMessage(id);
  }
}

class _GatedTrustedRootMediaFileManager extends FakeMediaFileManager {
  final Completer<void> captured = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<String> trustedMediaRootPath() async {
    final root = await super.trustedMediaRootPath();
    captured.complete();
    await release.future;
    return root;
  }
}
