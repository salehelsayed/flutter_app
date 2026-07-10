import 'package:path/path.dart' as p;

import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// 235: literal reconciliation page size (TC-235-08 / failure semantics).
const kGroupMediaDeletionReconcilerPageSize = 100;

/// Counters for one bounded reconciliation pass (privacy-safe — counts only).
class GroupMediaDeletionCleanupStats {
  int completed = 0;
  int retained = 0;
  int quarantined = 0;

  @override
  String toString() =>
      'completed=$completed retained=$retained quarantined=$quarantined';
}

/// 235: the idempotent post-commit cleanup saga over the v98 deletion journal.
///
/// Per journal entry, strictly ordered file -> key -> atomic DB finalize:
///  1. VALIDATE (no destructive work on any mismatch — "quarantine"):
///     exact intent; the migration-069 tombstone exists for the exact
///     `(message_id -> group_id)` identity; the parent is absent; when the
///     attachment row still exists it matches the exact
///     `(attachment_id, message_id, owner_lane='group')` tuple. A MISSING
///     row is fine — the journal's own snapshotted MIME/path/key identity
///     drives cleanup (a crash-era bypass may have removed the row first).
///  2. FILE: delete only the journal's validated canonical relative path,
///     re-derived and re-compared before the delete; null/noncanonical
///     authorizes nothing; a missing file is success.
///  3. KEY: delete the attachment's secure encryption key (absent is
///     success).
///  4. FINALIZE: one transaction deletes the exact attachment row (if
///     present) together with the journal row.
///
/// A failure at any stage keeps the journal row so a fresh-process retry
/// converges; one bad item never blocks siblings (per-item isolation). All
/// I/O for one attachment runs under the shared
/// [MediaAttachmentLifecycleLock].
class GroupMediaDeletionJournalReconciler {
  GroupMediaDeletionJournalReconciler({
    required this.loadJournalPage,
    required this.loadAttachmentRow,
    required this.loadLocalDeletionGroupId,
    required this.parentExists,
    required this.finalizeEntry,
    required this.resolveStoredPath,
    required this.secureKeyStore,
    MediaStorageFileGateway? fileGateway,
    MediaAttachmentLifecycleLock? lifecycleLock,
  }) : fileGateway = fileGateway ?? const IoMediaStorageFileGateway(),
       lifecycleLock = lifecycleLock ?? mediaAttachmentLifecycleLock;

  /// Stable `(created_at, attachment_id)` cursor page over the journal.
  final Future<List<GroupMediaDeletionJournalEntry>> Function({
    required int limit,
    String? afterCreatedAt,
    String? afterAttachmentId,
  })
  loadJournalPage;

  /// Untyped by-ID raw attachment row (media_attachments PK lookup), or null.
  final Future<Map<String, Object?>?> Function(String attachmentId)
  loadAttachmentRow;

  /// The migration-069 tombstone's group_id for a message id, or null.
  final Future<String?> Function(String messageId) loadLocalDeletionGroupId;

  /// True when a live exact `(message_id, group_id)` group parent exists.
  final Future<bool> Function({
    required String messageId,
    required String groupId,
  })
  parentExists;

  /// Atomic attachment-row + journal-row finalize
  /// ([dbFinalizeGroupMediaDeletionJournalEntry]).
  final Future<bool> Function({
    required String attachmentId,
    required String messageId,
  })
  finalizeEntry;

  /// Resolves a stored relative path to the absolute in-container path
  /// (MediaFileManager.resolveStoredPath).
  final Future<String> Function(String relativePath) resolveStoredPath;

  final SecureKeyStore secureKeyStore;
  final MediaStorageFileGateway fileGateway;
  final MediaAttachmentLifecycleLock lifecycleLock;

  /// One bounded, paged, per-item-isolated reconciliation pass.
  Future<GroupMediaDeletionCleanupStats> runBounded({
    int pageSize = kGroupMediaDeletionReconcilerPageSize,
  }) async {
    final stats = GroupMediaDeletionCleanupStats();
    String? afterCreatedAt;
    String? afterAttachmentId;
    while (true) {
      final page = await loadJournalPage(
        limit: pageSize,
        afterCreatedAt: afterCreatedAt,
        afterAttachmentId: afterAttachmentId,
      );
      if (page.isEmpty) break;
      for (final entry in page) {
        try {
          await _cleanupEntry(entry, stats);
        } catch (e) {
          // Per-item isolation: the journal row stays; a later pass retries.
          stats.retained += 1;
          _emit(entry, 'retained_after_error', error: e);
        }
      }
      final last = page.last;
      afterCreatedAt = last.createdAt;
      afterAttachmentId = last.attachmentId;
      if (page.length < pageSize) break;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MEDIA_DELETION_RECONCILE_DONE',
      details: {
        'completed': stats.completed,
        'retained': stats.retained,
        'quarantined': stats.quarantined,
      },
    );
    return stats;
  }

  Future<void> _cleanupEntry(
    GroupMediaDeletionJournalEntry entry,
    GroupMediaDeletionCleanupStats stats,
  ) {
    return lifecycleLock.synchronized(entry.attachmentId, () async {
      // ---- Validation: any mismatch quarantines (no destructive work).
      if (entry.operationIntent != kGroupMediaDeletionIntentDeleteForMe) {
        stats.quarantined += 1;
        _emit(entry, 'quarantined_unknown_intent');
        return;
      }
      final tombstoneGroupId = await loadLocalDeletionGroupId(entry.messageId);
      if (tombstoneGroupId == null || tombstoneGroupId != entry.groupId) {
        stats.quarantined += 1;
        _emit(entry, 'quarantined_tombstone_mismatch');
        return;
      }
      if (await parentExists(
        messageId: entry.messageId,
        groupId: entry.groupId,
      )) {
        stats.quarantined += 1;
        _emit(entry, 'quarantined_parent_present');
        return;
      }
      final row = await loadAttachmentRow(entry.attachmentId);
      if (row != null &&
          (row['message_id'] != entry.messageId ||
              row['owner_lane'] != 'group')) {
        stats.quarantined += 1;
        _emit(entry, 'quarantined_attachment_tuple_mismatch');
        return;
      }

      // ---- File: only the validated canonical snapshot, re-derived here.
      final canonical = entry.canonicalRelativePath;
      if (canonical != null) {
        final rederived = canonicalGroupMediaRelativePathOrNull(
          groupId: entry.groupId,
          attachmentId: entry.attachmentId,
          normalizedMime: entry.normalizedMime,
          storedLocalPath: canonical,
        );
        if (rederived == null || p.normalize(rederived) != p.normalize(canonical)) {
          stats.quarantined += 1;
          _emit(entry, 'quarantined_noncanonical_snapshot');
          return;
        }
        final absolute = await resolveStoredPath(canonical);
        // Missing file is success; a real I/O failure throws and retains.
        await fileGateway.delete(
          absolute,
          reason: 'group_media_delete_for_me',
        );
      }

      // ---- Key: absent is success; a store failure throws and retains.
      await secureKeyStore.delete(
        mediaAttachmentEncryptionKeyStoreName(entry.attachmentId),
      );

      // ---- Finalize: atomic attachment-row (exact tuple) + journal delete.
      await finalizeEntry(
        attachmentId: entry.attachmentId,
        messageId: entry.messageId,
      );
      stats.completed += 1;
      _emit(entry, 'completed');
    });
  }

  void _emit(
    GroupMediaDeletionJournalEntry entry,
    String outcome, {
    Object? error,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MEDIA_DELETION_CLEANUP_ITEM',
      details: {
        'attachmentId': entry.attachmentId.length > 8
            ? entry.attachmentId.substring(0, 8)
            : entry.attachmentId,
        'outcome': outcome,
        if (error != null) 'error': error.runtimeType.toString(),
      },
    );
  }
}
