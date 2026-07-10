import 'dart:convert';

import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';

import '../models/media_attachment.dart';
import '../models/media_library.dart';
import '../models/media_preview_descriptor.dart';
import 'media_attachment_repository.dart';

/// Implementation of MediaAttachmentRepository using database helper functions.
///
/// 228 ownership contract: every message-scoped closure takes the owner-lane
/// string as its final argument, and [saveAttachment] validates the immutable
/// `(attachmentId, ownerLane, messageId)` identity BEFORE `_toStorageRow` or
/// any secure-store side effect. The save closure
/// ([dbSaveMediaAttachmentPreservingLocalState]) must merge atomically,
/// preserving local-only owner/bookmark/playback state and a completed local
/// path, and re-validate identity inside the write transaction as the final
/// race guard.
class MediaAttachmentRepositoryImpl
    implements
        MediaAttachmentRepository,
        MediaAttachmentByIdLookup,
        MediaPreviewDescriptorLookup,
        MediaLibraryStateRepository,
        MediaLibraryRepository {
  final Future<void> Function(Map<String, Object?> row)
  dbSaveMediaAttachmentPreservingLocalState;
  final Future<List<Map<String, Object?>>> Function(
    String messageId,
    String ownerLane,
  )
  dbLoadMediaForMessage;
  final Future<Map<String, Object?>?> Function(String id) dbLoadMediaById;
  final Future<List<Map<String, Object?>>> Function(
    List<String> messageIds,
    String ownerLane,
  )
  dbLoadMediaForMessages;
  final Future<void> Function(
    String id,
    String localPath,
    String downloadStatus,
  )
  dbUpdateMediaLocalPath;
  final Future<void> Function(String id, String downloadStatus)
  dbUpdateMediaDownloadStatus;
  final Future<int> Function(String messageId, String ownerLane)
  dbDeleteMediaForMessage;
  final Future<int> Function(String contactPeerId) dbDeleteMediaForContact;
  final Future<int> Function(String messageId, String ownerLane)
  dbMarkUploadPendingAttachmentsFailedForMessage;
  final Future<List<Map<String, Object?>>> Function()
  dbLoadPendingMediaDownloads;
  final Future<List<Map<String, Object?>>> Function({
    int limit,
    required String ownerLane,
  })
  dbLoadUploadPendingAttachments;
  final Future<void> Function(String id, bool bookmarked) dbSetMediaBookmarked;
  final Future<void> Function(String id, int positionMs)
  dbUpdateMediaPlaybackPosition;
  final Future<List<Map<String, Object?>>> Function({
    required String scopeKind,
    required String scopeId,
    required List<String> mediaTypes,
    required bool bookmarkedOnly,
    required int limit,
    String? afterTimestamp,
    String? afterMessageId,
    String? afterAttachmentId,
  })
  dbLoadMediaLibraryPage;
  final SecureKeyStore? secureKeyStore;

  MediaAttachmentRepositoryImpl({
    required this.dbSaveMediaAttachmentPreservingLocalState,
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
    required this.dbSetMediaBookmarked,
    required this.dbUpdateMediaPlaybackPosition,
    required this.dbLoadMediaLibraryPage,
    this.secureKeyStore,
  });

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_SAVE_START',
      details: {
        'id': attachment.id.length > 8
            ? attachment.id.substring(0, 8)
            : attachment.id,
        'ownerLane': owner.dbValue,
      },
    );

    try {
      // A model stamped with a DIFFERENT lane than the caller's typed owner
      // is a caller bug — fail closed before any side effect.
      if (attachment.ownerLane != null && attachment.ownerLane != owner) {
        throw MediaAttachmentOwnerViolation(
          'attachment ${attachment.id} is stamped ${attachment.ownerLane!.dbValue} '
          'but the caller passed ${owner.dbValue}',
        );
      }
      final stamped = attachment.copyWith(ownerLane: owner);

      // Immutable-identity validation BEFORE _toStorageRow or any
      // secure-store side effect (TC-228-04K): a rejected cross-owner or
      // cross-parent save must leave the existing row, secure-store
      // reference/value and decryptability unchanged.
      final existingRow = await dbLoadMediaById(stamped.id);
      if (existingRow != null) {
        final existingOwner = existingRow['owner_lane'] as String?;
        final existingMessageId = existingRow['message_id'] as String?;
        if (existingOwner != owner.dbValue ||
            existingMessageId != stamped.messageId) {
          throw MediaAttachmentOwnerViolation(
            'save would re-parent attachment ${stamped.id} from '
            '($existingOwner, $existingMessageId) to '
            '(${owner.dbValue}, ${stamped.messageId})',
          );
        }
      }

      await dbSaveMediaAttachmentPreservingLocalState(
        await _toStorageRow(stamped),
      );

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
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final rows = await dbLoadMediaForMessage(messageId, owner.dbValue);
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
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    if (messageIds.isEmpty) return {};

    final rows = await dbLoadMediaForMessages(messageIds, owner.dbValue);
    final Map<String, List<MediaAttachment>> result = {};
    for (final attachment in await _attachmentsFromRows(rows)) {
      result.putIfAbsent(attachment.messageId, () => []).add(attachment);
    }
    return result;
  }

  @override
  Future<Map<String, MediaPreviewDescriptor>> getMediaPreviewDescriptors(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    if (messageIds.isEmpty) return {};

    final rows = await dbLoadMediaForMessages(messageIds, owner.dbValue);
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
  Future<void> setBookmarked(String id, {required bool bookmarked}) async {
    await dbSetMediaBookmarked(id, bookmarked);
  }

  @override
  Future<MediaLibraryPage> getMediaLibraryPage({
    required MediaLibraryScope scope,
    MediaLibraryFilter filter = const MediaLibraryFilter(),
    int limit = 50,
    String? cursor,
  }) async {
    // Every argument-contract failure happens HERE, before any SQL.
    if (limit < 1 || limit > kMediaLibraryMaxPageSize) {
      throw ArgumentError.value(
        limit,
        'limit',
        'must be within 1..$kMediaLibraryMaxPageSize',
      );
    }
    _MediaLibraryCursor? after;
    if (cursor != null) {
      after = _MediaLibraryCursor.decode(cursor);
      if (after.scopeKind != scope.lane.dbValue ||
          after.scopeId != scope.id ||
          after.kind != filter.kind.name ||
          after.bookmarkedOnly != filter.bookmarkedOnly) {
        throw ArgumentError.value(
          cursor,
          'cursor',
          'cursor was minted for a different scope/filter signature',
        );
      }
    }

    final rows = await dbLoadMediaLibraryPage(
      scopeKind: scope.lane.dbValue,
      scopeId: scope.id,
      mediaTypes: filter.kind.mediaTypes,
      bookmarkedOnly: filter.bookmarkedOnly,
      limit: limit,
      afterTimestamp: after?.timestamp,
      afterMessageId: after?.messageId,
      afterAttachmentId: after?.attachmentId,
    );

    final entries = <MediaLibraryEntry>[];
    for (final row in rows) {
      final attachmentMap = await _hydrateRow(
        mediaLibraryRowToAttachmentMap(row),
      );
      entries.add(
        MediaLibraryEntry(
          attachment: MediaAttachment.fromMap(attachmentMap),
          parentTimestamp: row['parent_timestamp'] as String,
          parentSenderPeerId: row['parent_sender_peer_id'] as String?,
        ),
      );
    }

    String? nextCursor;
    if (entries.length == limit) {
      final last = entries.last;
      nextCursor = _MediaLibraryCursor(
        scopeKind: scope.lane.dbValue,
        scopeId: scope.id,
        kind: filter.kind.name,
        bookmarkedOnly: filter.bookmarkedOnly,
        timestamp: last.parentTimestamp,
        messageId: last.attachment.messageId,
        attachmentId: last.attachment.id,
      ).encode();
    }
    return MediaLibraryPage(entries: entries, nextCursor: nextCursor);
  }

  @override
  Future<void> updatePlaybackPosition(String id, int positionMs) async {
    await dbUpdateMediaPlaybackPosition(id, positionMs);
  }

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_DELETE_FOR_MESSAGE_START',
      details: {
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
        'ownerLane': owner.dbValue,
      },
    );

    try {
      final count = await dbDeleteMediaForMessage(messageId, owner.dbValue);

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
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_TERMINALIZE_UPLOADS_START',
      details: {
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
        'ownerLane': owner.dbValue,
      },
    );

    try {
      final count = await dbMarkUploadPendingAttachmentsFailedForMessage(
        messageId,
        owner.dbValue,
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
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async {
    final rows = await dbLoadUploadPendingAttachments(
      ownerLane: owner.dbValue,
    );
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

/// Opaque keyset cursor for [MediaAttachmentRepositoryImpl.getMediaLibraryPage].
/// Embeds the complete scope/filter signature alongside the keyset position so
/// a cursor can never be replayed under another query signature.
class _MediaLibraryCursor {
  const _MediaLibraryCursor({
    required this.scopeKind,
    required this.scopeId,
    required this.kind,
    required this.bookmarkedOnly,
    required this.timestamp,
    required this.messageId,
    required this.attachmentId,
  });

  final String scopeKind;
  final String scopeId;
  final String kind;
  final bool bookmarkedOnly;
  final String timestamp;
  final String messageId;
  final String attachmentId;

  String encode() => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'scopeKind': scopeKind,
        'scopeId': scopeId,
        'kind': kind,
        'bookmarkedOnly': bookmarkedOnly,
        'ts': timestamp,
        'mid': messageId,
        'aid': attachmentId,
      }),
    ),
  );

  static _MediaLibraryCursor decode(String cursor) {
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(cursor)))
              as Map<String, dynamic>;
      if (decoded['v'] != 1) {
        throw const FormatException('unknown cursor version');
      }
      return _MediaLibraryCursor(
        scopeKind: decoded['scopeKind'] as String,
        scopeId: decoded['scopeId'] as String,
        kind: decoded['kind'] as String,
        bookmarkedOnly: decoded['bookmarkedOnly'] as bool,
        timestamp: decoded['ts'] as String,
        messageId: decoded['mid'] as String,
        attachmentId: decoded['aid'] as String,
      );
    } catch (e) {
      throw ArgumentError.value(cursor, 'cursor', 'malformed cursor: $e');
    }
  }
}
