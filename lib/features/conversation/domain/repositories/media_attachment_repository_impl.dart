import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';

import '../models/media_attachment.dart';
import '../models/media_preview_descriptor.dart';
import 'media_attachment_repository.dart';

/// Implementation of MediaAttachmentRepository using database helper functions.
class MediaAttachmentRepositoryImpl
    implements
        MediaAttachmentRepository,
        MediaAttachmentByIdLookup,
        MediaPreviewDescriptorLookup {
  final Future<void> Function(Map<String, Object?> row) dbInsertMediaAttachment;
  final Future<List<Map<String, Object?>>> Function(String messageId)
  dbLoadMediaForMessage;
  final Future<Map<String, Object?>?> Function(String id) dbLoadMediaById;
  final Future<List<Map<String, Object?>>> Function(List<String> messageIds)
  dbLoadMediaForMessages;
  final Future<void> Function(
    String id,
    String localPath,
    String downloadStatus,
  )
  dbUpdateMediaLocalPath;
  final Future<void> Function(String id, String downloadStatus)
  dbUpdateMediaDownloadStatus;
  final Future<int> Function(String messageId) dbDeleteMediaForMessage;
  final Future<int> Function(String contactPeerId) dbDeleteMediaForContact;
  final Future<int> Function(String messageId)
  dbMarkUploadPendingAttachmentsFailedForMessage;
  final Future<List<Map<String, Object?>>> Function()
  dbLoadPendingMediaDownloads;
  final Future<List<Map<String, Object?>>> Function({int limit})
  dbLoadUploadPendingAttachments;
  final SecureKeyStore? secureKeyStore;

  MediaAttachmentRepositoryImpl({
    required this.dbInsertMediaAttachment,
    required this.dbLoadMediaForMessage,
    required this.dbLoadMediaById,
    required this.dbLoadMediaForMessages,
    required this.dbUpdateMediaLocalPath,
    required this.dbUpdateMediaDownloadStatus,
    required this.dbDeleteMediaForMessage,
    required this.dbDeleteMediaForContact,
    required this.dbMarkUploadPendingAttachmentsFailedForMessage,
    required this.dbLoadPendingMediaDownloads,
    required this.dbLoadUploadPendingAttachments,
    this.secureKeyStore,
  });

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_SAVE_START',
      details: {
        'id': attachment.id.length > 8
            ? attachment.id.substring(0, 8)
            : attachment.id,
      },
    );

    try {
      final storageAttachment = await _preserveCompletedLocalPathIfNeeded(
        attachment,
      );
      await dbInsertMediaAttachment(await _toStorageRow(storageAttachment));

      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_SAVE_SUCCESS',
        details: {
          'id': attachment.id.length > 8
              ? attachment.id.substring(0, 8)
              : attachment.id,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_SAVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async {
    final rows = await dbLoadMediaForMessage(messageId);
    return _attachmentsFromRows(rows);
  }

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    final row = await dbLoadMediaById(id);
    if (row == null) return null;
    return MediaAttachment.fromMap(await _hydrateRow(row));
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return {};

    final rows = await dbLoadMediaForMessages(messageIds);
    final Map<String, List<MediaAttachment>> result = {};
    for (final attachment in await _attachmentsFromRows(rows)) {
      result.putIfAbsent(attachment.messageId, () => []).add(attachment);
    }
    return result;
  }

  @override
  Future<Map<String, MediaPreviewDescriptor>> getMediaPreviewDescriptors(
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return {};

    final rows = await dbLoadMediaForMessages(messageIds);
    // Parse rows WITHOUT _hydrateRow: a preview label is derived purely from
    // media_type/mime/count and never needs the decryption key, so we skip the
    // per-attachment SecureKeyStore.read this path would otherwise pay once per
    // contact/group on every orbit load.
    final Map<String, List<MediaAttachment>> byMessage = {};
    for (final row in rows) {
      final attachment = MediaAttachment.fromMap(row);
      byMessage.putIfAbsent(attachment.messageId, () => []).add(attachment);
    }
    final Map<String, MediaPreviewDescriptor> result = {};
    byMessage.forEach((messageId, attachments) {
      final descriptor = MediaPreviewDescriptor.fromAttachments(attachments);
      if (descriptor != null) result[messageId] = descriptor;
    });
    return result;
  }

  @override
  Future<void> updateLocalPath(String id, String localPath) async {
    await dbUpdateMediaLocalPath(id, localPath, 'done');
  }

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    await dbUpdateMediaDownloadStatus(id, downloadStatus);
  }

  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_DELETE_FOR_MESSAGE_START',
      details: {
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
      },
    );

    try {
      final count = await dbDeleteMediaForMessage(messageId);

      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_DELETE_FOR_MESSAGE_SUCCESS',
        details: {'count': count},
      );

      return count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_DELETE_FOR_MESSAGE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_DELETE_FOR_CONTACT_START',
      details: {
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
      },
    );

    try {
      final count = await dbDeleteMediaForContact(contactPeerId);

      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_DELETE_FOR_CONTACT_SUCCESS',
        details: {'count': count},
      );

      return count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_DELETE_FOR_CONTACT_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId,
  ) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_TERMINALIZE_UPLOADS_START',
      details: {
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
      },
    );

    try {
      final count = await dbMarkUploadPendingAttachmentsFailedForMessage(
        messageId,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_TERMINALIZE_UPLOADS_SUCCESS',
        details: {'count': count},
      );
      return count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_TERMINALIZE_UPLOADS_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async {
    final rows = await dbLoadPendingMediaDownloads();
    return _attachmentsFromRows(rows);
  }

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments() async {
    final rows = await dbLoadUploadPendingAttachments();
    return _attachmentsFromRows(rows);
  }

  Future<Map<String, Object?>> _toStorageRow(MediaAttachment attachment) async {
    final row = Map<String, Object?>.from(attachment.toMap());
    final key = attachment.encryptionKeyBase64;
    final store = secureKeyStore;
    if (store == null ||
        key == null ||
        key.isEmpty ||
        isSecureStoreReference(key)) {
      return row;
    }

    final secureStoreKey = mediaAttachmentEncryptionKeyStoreName(attachment.id);
    await store.write(secureStoreKey, key);
    row['encryption_key_base64'] = secureStoreReferenceForKey(secureStoreKey);
    return row;
  }

  Future<MediaAttachment> _preserveCompletedLocalPathIfNeeded(
    MediaAttachment attachment,
  ) async {
    final existingRow = await dbLoadMediaById(attachment.id);
    if (existingRow == null) {
      return attachment;
    }

    final existing = MediaAttachment.fromMap(await _hydrateRow(existingRow));
    if (!_shouldPreserveCompletedLocalPath(
      existing: existing,
      incoming: attachment,
    )) {
      return attachment;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_SAVE_PRESERVED_COMPLETED_LOCAL_PATH',
      details: {
        'id': attachment.id.length > 8
            ? attachment.id.substring(0, 8)
            : attachment.id,
        'incomingStatus': attachment.downloadStatus,
      },
    );
    return attachment.copyWith(
      localPath: existing.localPath,
      downloadStatus: kMediaDownloadStatusDone,
    );
  }

  bool _shouldPreserveCompletedLocalPath({
    required MediaAttachment existing,
    required MediaAttachment incoming,
  }) {
    if (existing.downloadStatus != kMediaDownloadStatusDone ||
        !_hasLocalPath(existing.localPath)) {
      return false;
    }

    if (_nonTerminalMediaStatuses.contains(incoming.downloadStatus)) {
      return true;
    }

    if (incoming.downloadStatus == kMediaDownloadStatusDone) {
      if (!_hasLocalPath(incoming.localPath)) {
        return true;
      }
      return _isTransientLocalPath(incoming.localPath) &&
          !_isTransientLocalPath(existing.localPath);
    }

    return false;
  }

  static const Set<String> _nonTerminalMediaStatuses = {
    kMediaDownloadStatusPending,
    kMediaDownloadStatusDownloading,
    kMediaDownloadStatusUploadPending,
  };

  bool _hasLocalPath(String? path) => path != null && path.trim().isNotEmpty;

  bool _isTransientLocalPath(String? path) {
    if (path == null || path.isEmpty) {
      return false;
    }
    final normalized = path.replaceAll('\\', '/');
    return normalized.startsWith('pending_uploads/') ||
        normalized.contains('/pending_uploads/');
  }

  Future<List<MediaAttachment>> _attachmentsFromRows(
    List<Map<String, Object?>> rows,
  ) async {
    final attachments = <MediaAttachment>[];
    for (final row in rows) {
      attachments.add(MediaAttachment.fromMap(await _hydrateRow(row)));
    }
    return attachments;
  }

  Future<Map<String, Object?>> _hydrateRow(Map<String, Object?> row) async {
    final keyValue = row['encryption_key_base64'] as String?;
    final store = secureKeyStore;
    if (keyValue == null || !isSecureStoreReference(keyValue)) {
      return row;
    }

    final missingKeyRow = Map<String, Object?>.from(row)
      ..['encryption_key_base64'] = null;
    if (store == null) {
      return missingKeyRow;
    }

    final hydrated = await store.read(secureStoreKeyFromReference(keyValue));
    if (hydrated == null) {
      return missingKeyRow;
    }

    return Map<String, Object?>.from(row)..['encryption_key_base64'] = hydrated;
  }
}
