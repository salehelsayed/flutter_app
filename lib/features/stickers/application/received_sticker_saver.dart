import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/direct_private_media_path_guard.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/sticker_editor_result.dart';
import 'package:path/path.dart' as p;

import 'account_custom_sticker_library.dart';
import 'custom_sticker_library.dart';
import 'normalize_custom_sticker_asset.dart';

/// Source is borrowed, immutable, and valid until the callback completes.
/// Ready output must live inside outputDirectory; core owns and cleans both
/// directories after admission or cancellation. The editor never saves itself.
typedef ReceivedStickerEditor =
    Future<StickerEditorResult> Function({
      required String sourceImagePath,
      required Directory outputDirectory,
    });

/// Shared file/admission work for the direct and group received-row controllers.
/// Only those controllers supply loadCurrent; presentation passes stable IDs.
final class ReceivedStickerSaver {
  ReceivedStickerSaver({
    MediaFileManager? mediaFileManager,
    AppOwnedMediaPathAuthority? pathAuthority,
    MediaAttachmentLifecycleLock? lifecycleLock,
    Future<void> Function(String source, File target, int size)? copySnapshot,
  }) : _files = mediaFileManager ?? MediaFileManager(),
       _paths = pathAuthority ?? IoAppOwnedMediaPathAuthority(),
       _lifecycle = lifecycleLock ?? mediaAttachmentLifecycleLock,
       _copySnapshot = copySnapshot ?? _copyBounded;

  final MediaFileManager _files;
  final AppOwnedMediaPathAuthority _paths;
  final MediaAttachmentLifecycleLock _lifecycle;
  final Future<void> Function(String source, File target, int size)
  _copySnapshot;

  /// Current keep/copy eligibility without snapshot, editor or library writes.
  /// Codec, quota and storage failures are still checked during the actual save.
  Future<bool> canSave({
    required String attachmentId,
    required CustomStickerLibrary library,
    required Future<MediaAttachment?> Function() loadCurrent,
  }) async {
    if (library is! AccountCustomStickerLibrary) return false;
    try {
      return await library.inspectReceivedStickerEligibility(
        (checkAccess) => _lifecycle.synchronized(attachmentId, () async {
          await _qualify(attachmentId, loadCurrent, checkAccess);
          return true;
        }),
      );
    } catch (_) {
      return false;
    }
  }

  Future<CustomSticker?> save({
    required String attachmentId,
    required CustomStickerLibrary library,
    required Future<MediaAttachment?> Function() loadCurrent,
    required ReceivedStickerEditor editPhoto,
  }) async {
    // The public library contract intentionally exposes no account token. Keep
    // its concrete generation binding here, never in a widget or caller guard.
    if (library is! AccountCustomStickerLibrary) {
      throw const CustomStickerException(CustomStickerErrorCode.unavailable);
    }
    MediaForwardSnapshotLease? lease;
    try {
      return await library.prepareReceivedSticker((checkAccess) async {
        final captured = await _lifecycle.synchronized(attachmentId, () async {
          final qualified = await _qualify(
            attachmentId,
            loadCurrent,
            checkAccess,
          );
          final source = qualified.source;
          final mime = qualified.mime;
          lease = await _files.createMediaForwardSnapshotLease();
          await checkAccess();
          final snapshot = File(
            p.join(
              lease!.directory.path,
              'source${MediaFilePathConvention.extensionFromMime(mime)}',
            ),
          );
          await _copySnapshot(qualified.path, snapshot, source.size);
          await checkAccess();
          final signature = await GroupMediaMimePolicy.validateFile(
            path: snapshot.path,
            mime: mime,
            mediaType: 'image',
          );
          await checkAccess();
          if (!signature.isValid) _invalid();
          final current = await loadCurrent();
          await checkAccess();
          if (current == null || !_sameSource(source, current)) _notEligible();
          return (source: source, snapshot: snapshot, mime: mime);
        });
        await checkAccess();
        // The bounded copy belongs exclusively to this operation. Inspect its
        // plaintext, never the attachment's relay-ciphertext contentHash.
        final bytes = await _readSnapshot(
          captured.snapshot,
          captured.source.size,
        );
        await checkAccess();
        if (bytes.length != captured.source.size) _invalid();
        if (captured.mime == 'image/webp') {
          final canonical = await inspectReceivedStickerWebP(
            bytes,
            filePath: captured.snapshot.path,
          );
          await checkAccess();
          if (canonical != null) {
            await _lifecycle.synchronized(attachmentId, () async {
              final current = await loadCurrent();
              await checkAccess();
              if (current == null || !_sameSource(captured.source, current)) {
                _notEligible();
              }
            });
            return canonical;
          }
        } else if (captured.mime == 'image/png' && _animatedPng(bytes)) {
          // A still-photo editor must never silently discard animation frames.
          _invalid();
        }
        final output = await Directory(
          p.join(lease!.directory.path, 'editor'),
        ).create();
        await checkAccess();
        final result = await editPhoto(
          sourceImagePath: captured.snapshot.path,
          outputDirectory: output,
        );
        await checkAccess();
        if (result is StickerEditorCancelled) return null;
        final asset = (result as StickerEditorReady).asset;
        if (!await DirectPrivateMediaPathGuard.authorizeTarget(
          targetPath: asset.filePath,
          authorityRoot: output.path,
          requireExistingFile: true,
        )) {
          _invalid();
        }
        await checkAccess();
        await _lifecycle.synchronized(attachmentId, () async {
          final current = await loadCurrent();
          await checkAccess();
          if (current == null || !_sameSource(captured.source, current)) {
            _notEligible();
          }
        });
        return asset;
      });
    } on CustomStickerException {
      rethrow;
    } catch (_) {
      throw const CustomStickerException(CustomStickerErrorCode.storageFailure);
    } finally {
      await lease?.dispose();
    }
  }

  Future<({MediaAttachment source, String path, String mime})> _qualify(
    String attachmentId,
    Future<MediaAttachment?> Function() loadCurrent,
    Future<void> Function() checkAccess,
  ) async {
    await checkAccess();
    final source = await loadCurrent();
    await checkAccess();
    if (source == null || source.id != attachmentId) _notEligible();
    final mime = GroupMediaMimePolicy.normalizeMime(source.mime);
    if (source.mediaType != 'image' ||
        !const {
          'image/jpeg',
          'image/png',
          'image/webp',
          'image/heic',
        }.contains(mime) ||
        source.size <= 0 ||
        source.size > kGroupMediaImageLimitBytes ||
        source.localPath == null) {
      _notEligible();
    }
    final resolved = await _files.resolveStoredPath(source.localPath!);
    await checkAccess();
    final path = await _paths.authorize(resolved);
    await checkAccess();
    if (path == null || await File(path).length() != source.size) {
      _notEligible();
    }
    final signature = await GroupMediaMimePolicy.validateFile(
      path: path,
      mime: mime!,
      mediaType: 'image',
    );
    await checkAccess();
    if (!signature.isValid) _invalid();
    final current = await loadCurrent();
    await checkAccess();
    if (current == null || !_sameSource(source, current)) _notEligible();
    return (source: source, path: path, mime: mime);
  }

  static Future<void> _copyBounded(String source, File target, int size) async {
    final input = await File(source).open();
    RandomAccessFile? output;
    try {
      if (await input.length() != size) _notEligible();
      output = await target.open(mode: FileMode.write);
      var remaining = size;
      while (remaining > 0) {
        final bytes = await input.read(min(remaining, 65536));
        if (bytes.isEmpty) _notEligible();
        await output.writeFrom(bytes);
        remaining -= bytes.length;
      }
      if (await input.readByte() != -1 || await input.length() != size) {
        _notEligible();
      }
    } finally {
      await output?.close();
      await input.close();
    }
  }

  Future<Uint8List> _readSnapshot(File file, int size) async {
    final handle = await file.open();
    try {
      if (await handle.length() != size) _invalid();
      final bytes = await handle.read(size);
      if (bytes.length != size ||
          await handle.readByte() != -1 ||
          await handle.length() != size) {
        _invalid();
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }
}

bool _sameSource(MediaAttachment a, MediaAttachment b) =>
    a.id == b.id &&
    a.messageId == b.messageId &&
    a.ownerLane == b.ownerLane &&
    a.mime == b.mime &&
    a.mediaType == b.mediaType &&
    a.size == b.size &&
    a.localPath == b.localPath &&
    a.downloadStatus == b.downloadStatus &&
    a.contentHash == b.contentHash &&
    a.encryptionScheme == b.encryptionScheme &&
    a.encryptionKeyBase64 == b.encryptionKeyBase64 &&
    a.encryptionNonce == b.encryptionNonce;

bool _animatedPng(Uint8List bytes) {
  var offset = 8;
  final data = ByteData.sublistView(bytes);
  while (offset < bytes.length) {
    if (bytes.length - offset < 12) _invalid();
    final size = data.getUint32(offset, Endian.big);
    if (size > bytes.length - offset - 12) _invalid();
    final tag = String.fromCharCodes(bytes, offset + 4, offset + 8);
    if (tag == 'acTL' || tag == 'fcTL' || tag == 'fdAT') return true;
    offset += size + 12;
  }
  return false;
}

Never _notEligible() =>
    throw const CustomStickerException(CustomStickerErrorCode.notEligible);
Never _invalid() =>
    throw const CustomStickerException(CustomStickerErrorCode.invalidAsset);
