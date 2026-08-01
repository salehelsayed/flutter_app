import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/database/helpers/group_message_local_deletions_db_helpers.dart';

/// 235: the only operation intent DB v98 supports (schema CHECK-enforced).
const kGroupMediaDeletionIntentDeleteForMe = 'delete_for_me';

/// One `group_media_deletion_journal` row: the explicit, self-contained
/// cleanup authority for exactly one group-owned attachment of one confirmed
/// whole-message Delete-for-me operation. Snapshot identity is carried on the
/// row itself — cleanup never re-derives it from orphan shape.
class GroupMediaDeletionJournalEntry {
  const GroupMediaDeletionJournalEntry({
    required this.attachmentId,
    required this.operationId,
    required this.messageId,
    required this.groupId,
    required this.operationIntent,
    required this.normalizedMime,
    required this.canonicalRelativePath,
    required this.createdAt,
  });

  factory GroupMediaDeletionJournalEntry.fromRow(Map<String, Object?> row) {
    return GroupMediaDeletionJournalEntry(
      attachmentId: row['attachment_id'] as String,
      operationId: row['operation_id'] as String,
      messageId: row['message_id'] as String,
      groupId: row['group_id'] as String,
      operationIntent: row['operation_intent'] as String,
      normalizedMime: row['normalized_mime'] as String,
      canonicalRelativePath: row['canonical_relative_path'] as String?,
      createdAt: row['created_at'] as String,
    );
  }

  final String attachmentId;
  final String operationId;
  final String messageId;
  final String groupId;
  final String operationIntent;
  final String normalizedMime;

  /// The exact plan-229 canonical relative path snapshotted from the SAME
  /// row version the prepare transaction journaled, or null when the stored
  /// path was absent/noncanonical. Null NEVER authorizes a file deletion.
  final String? canonicalRelativePath;
  final String createdAt;
}

/// Outcome of one atomic delete-prepare transaction.
enum GroupMediaDeletePrepareOutcome {
  /// Journal rows + tombstone + reaction cleanup + parent delete committed.
  prepared,

  /// The exact `(group_id, message_id)` parent is already tombstoned locally
  /// and absent — a repeat confirm is a no-op.
  alreadyDeleted,

  /// No such parent and no local tombstone: nothing to delete.
  parentMissing,

  /// A same-ID tombstone belongs to ANOTHER group. Deleting (or
  /// re-tombstoning) would clobber that group's replay protection — fail
  /// closed with zero writes.
  conflictingTombstone,
}

class GroupMediaDeletePrepareResult {
  const GroupMediaDeletePrepareResult(
    this.outcome, {
    this.journaledAttachments = 0,
  });

  final GroupMediaDeletePrepareOutcome outcome;
  final int journaledAttachments;

  bool get prepared => outcome == GroupMediaDeletePrepareOutcome.prepared;
}

/// Returns the exact canonical relative path when the stored path already IS
/// the canonical location for this `(group, attachment, mime)`; else null.
/// A null snapshot never authorizes file deletion during cleanup.
String? canonicalGroupMediaRelativePathOrNull({
  required String groupId,
  required String attachmentId,
  required String normalizedMime,
  required String? storedLocalPath,
}) {
  if (storedLocalPath == null || storedLocalPath.isEmpty) return null;
  if (normalizedMime.isEmpty) return null;
  if (MediaFilePathConvention.extensionFromMime(normalizedMime).isEmpty) {
    return null;
  }
  final expected = MediaFilePathConvention.relativePathForAttachment(
    contactPeerId: groupId,
    blobId: attachmentId,
    mime: normalizedMime,
  );
  final normalizedStored = p.normalize(storedLocalPath.replaceAll('\\', '/'));
  return normalizedStored == p.normalize(expected) ? expected : null;
}

/// 235: the ONE SQLite transaction behind a confirmed whole-message
/// Delete-for-me (TC-235-07). Inside a single [dbWriteTransaction]:
///
///  1. fails closed (zero writes) when a same-ID tombstone belongs to another
///     group;
///  2. verifies a LIVE exact `(message_id, group_id)` parent (absent parent +
///     own-group tombstone -> idempotent [alreadyDeleted]; absent both ->
///     [parentMissing]);
///  3. snapshots ONLY exact group-owned attachments of this message into
///     journal rows (normalized MIME + canonical-relative-path-or-null from
///     the same row version); a zero-attachment message journals nothing;
///  4. upserts the exact migration-069 local tombstone;
///  5. deletes exact `(group_id, message_id)` pending reactions and exact
///     pending/failed reaction replay-outbox rows (`stored` rows survive as
///     inert completed-delivery evidence; ordinary untyped `message_reactions`
///     are retained and merely hidden);
///  6. deletes the parent with BOTH identifiers.
///
/// Any SQL failure rolls back all of it. No file or secure-key I/O happens
/// here — that is the post-commit cleanup saga's job, authorized exclusively
/// by the journal rows this transaction wrote.
Future<GroupMediaDeletePrepareResult> dbPrepareGroupMediaDeleteForMe(
  Database db, {
  required String groupId,
  required String messageId,
  required String operationId,
  DateTime? deletedAt,
}) async {
  final result = await dbWriteTransaction(db, (txn) async {
    final tombstoneRows = await txn.query(
      'group_message_local_deletions',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    final tombstoneGroupId = tombstoneRows.isEmpty
        ? null
        : tombstoneRows.first['group_id'] as String?;
    if (tombstoneGroupId != null && tombstoneGroupId != groupId) {
      return const GroupMediaDeletePrepareResult(
        GroupMediaDeletePrepareOutcome.conflictingTombstone,
      );
    }

    final parentRows = await txn.query(
      'group_messages',
      columns: ['id'],
      where: 'id = ? AND group_id = ?',
      whereArgs: [messageId, groupId],
      limit: 1,
    );
    if (parentRows.isEmpty) {
      return GroupMediaDeletePrepareResult(
        tombstoneGroupId != null
            ? GroupMediaDeletePrepareOutcome.alreadyDeleted
            : GroupMediaDeletePrepareOutcome.parentMissing,
      );
    }

    final attachments = await txn.query(
      'media_attachments',
      where: 'message_id = ? AND owner_lane = ?',
      whereArgs: [messageId, 'group'],
    );
    final nowIso = (deletedAt ?? DateTime.now().toUtc()).toIso8601String();
    for (final row in attachments) {
      final attachmentId = row['id'] as String;
      final normalizedMime =
          GroupMediaMimePolicy.normalizeMime(row['mime'] as String?) ?? '';
      // A leftover journal row for this attachment id makes the plain insert
      // throw -> the whole prepare rolls back (fail closed, quarantine-level
      // anomaly: journal rows must only coexist with a deleted parent).
      await txn.insert('group_media_deletion_journal', {
        'attachment_id': attachmentId,
        'operation_id': operationId,
        'message_id': messageId,
        'group_id': groupId,
        'operation_intent': kGroupMediaDeletionIntentDeleteForMe,
        'normalized_mime': normalizedMime,
        'canonical_relative_path': canonicalGroupMediaRelativePathOrNull(
          groupId: groupId,
          attachmentId: attachmentId,
          normalizedMime: normalizedMime,
          storedLocalPath: row['local_path'] as String?,
        ),
        'created_at': nowIso,
      });
    }

    await dbUpsertGroupMessageLocalDeletion(
      txn,
      messageId: messageId,
      groupId: groupId,
      deletedAt: deletedAt,
    );
    await txn.delete(
      'group_pending_reactions',
      where: 'group_id = ? AND message_id = ?',
      whereArgs: [groupId, messageId],
    );
    await txn.delete(
      'group_reaction_replay_outbox',
      where:
          "group_id = ? AND message_id = ? AND delivery_status IN ('pending', 'failed', 'needs_build')",
      whereArgs: [groupId, messageId],
    );
    await txn.delete(
      'group_messages',
      where: 'id = ? AND group_id = ?',
      whereArgs: [messageId, groupId],
    );
    return GroupMediaDeletePrepareResult(
      GroupMediaDeletePrepareOutcome.prepared,
      journaledAttachments: attachments.length,
    );
  });

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEDIA_DELETE_PREPARE',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'messageId': messageId.length > 8
          ? messageId.substring(0, 8)
          : messageId,
      'outcome': result.outcome.name,
      'journaled': result.journaledAttachments,
    },
  );
  return result;
}

/// Loads one bounded journal page in stable `(created_at, attachment_id)`
/// cursor order (TC-235-08: literal page size 100 at the reconciler).
Future<List<GroupMediaDeletionJournalEntry>> dbLoadGroupMediaDeletionJournalPage(
  Database db, {
  int limit = 100,
  String? afterCreatedAt,
  String? afterAttachmentId,
}) async {
  final List<Map<String, Object?>> rows;
  if (afterCreatedAt == null || afterAttachmentId == null) {
    rows = await db.query(
      'group_media_deletion_journal',
      orderBy: 'created_at, attachment_id',
      limit: limit,
    );
  } else {
    rows = await db.rawQuery(
      'SELECT * FROM group_media_deletion_journal '
      'WHERE (created_at > ?) OR (created_at = ? AND attachment_id > ?) '
      'ORDER BY created_at, attachment_id LIMIT ?',
      [afterCreatedAt, afterCreatedAt, afterAttachmentId, limit],
    );
  }
  return rows.map(GroupMediaDeletionJournalEntry.fromRow).toList();
}

/// Loads one journal entry by attachment id, or null.
Future<GroupMediaDeletionJournalEntry?> dbLoadGroupMediaDeletionJournalEntry(
  Database db,
  String attachmentId,
) async {
  final rows = await db.query(
    'group_media_deletion_journal',
    where: 'attachment_id = ?',
    whereArgs: [attachmentId],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return GroupMediaDeletionJournalEntry.fromRow(rows.first);
}

/// True when an active deletion journal reserves [attachmentId].
Future<bool> dbIsGroupMediaDeletionJournaled(
  DatabaseExecutor db,
  String attachmentId,
) async {
  final rows = await db.query(
    'group_media_deletion_journal',
    columns: ['attachment_id'],
    where: 'attachment_id = ?',
    whereArgs: [attachmentId],
    limit: 1,
  );
  return rows.isNotEmpty;
}

/// 235: the saga's final DB step — atomically deletes the attachment row (if
/// still present, ONLY under its exact `(id, message_id, owner_lane='group')`
/// tuple) together with the journal row. Both survive any earlier failure so
/// a fresh-process retry converges. Returns true when the journal row was
/// consumed.
Future<bool> dbFinalizeGroupMediaDeletionJournalEntry(
  Database db, {
  required String attachmentId,
  required String messageId,
}) async {
  return dbWriteTransaction(db, (txn) async {
    await txn.delete(
      'media_attachments',
      where: "id = ? AND message_id = ? AND owner_lane = 'group'",
      whereArgs: [attachmentId, messageId],
    );
    final journalDeleted = await txn.delete(
      'group_media_deletion_journal',
      where: 'attachment_id = ?',
      whereArgs: [attachmentId],
    );
    return journalDeleted > 0;
  });
}
