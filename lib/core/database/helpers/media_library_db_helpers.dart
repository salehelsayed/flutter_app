import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// 228: every attachment column a library page returns, each with an explicit
/// `att_` alias. Parent columns are aliased `parent_` — no unqualified
/// duplicate `id` / `created_at` / `timestamp` ever reaches mapping code.
const List<String> _attachmentColumns = [
  'id',
  'message_id',
  'mime',
  'size',
  'media_type',
  'width',
  'height',
  'duration_ms',
  'local_path',
  'download_status',
  'created_at',
  'waveform',
  'upload_retry_count',
  'download_retry_count',
  'content_hash',
  'thumbnail_hash',
  'encryption_key_base64',
  'encryption_nonce',
  'encryption_scheme',
  'owner_lane',
  'is_bookmarked',
  'last_playback_position_ms',
];

String _attachmentSelectList() =>
    _attachmentColumns.map((c) => 'm.$c AS att_$c').join(', ');

/// Strips the `att_` alias prefix back into plain attachment column names so
/// `MediaAttachment.fromMap` (and secure-store hydration) can consume the row.
Map<String, Object?> mediaLibraryRowToAttachmentMap(Map<String, Object?> row) {
  final map = <String, Object?>{};
  for (final column in _attachmentColumns) {
    map[column] = row['att_$column'];
  }
  return map;
}

/// Loads one raw shared-media-library page (228 TC-228-06/07/09).
///
/// Owner scoping, parent visibility, filters AND the keyset predicate are all
/// SQL, applied before `LIMIT`:
///  - `direct` scope: `owner_lane='direct'`, the named contact, and a live
///    parent (`hidden_at IS NULL AND deleted_at IS NULL`);
///  - `group` scope: `owner_lane='group'`, a live parent row in the named
///    group, and an anti-join against the durable
///    `group_message_local_deletions` tombstones (which outlive the parent
///    row, so a replayed/reinserted deleted parent stays invisible).
///
/// Ordering is the stable newest-first keyset
/// `(parent.timestamp DESC, message_id DESC, attachment id DESC)`.
/// Callers validate scope/filter/cursor/limit BEFORE calling; [limit] is
/// nonetheless re-checked here as a final guard.
Future<List<Map<String, Object?>>> dbLoadMediaLibraryPage(
  Database db, {
  required String scopeKind, // 'direct' | 'group'
  required String scopeId,
  required List<String> mediaTypes,
  required bool bookmarkedOnly,
  required int limit,
  String? afterTimestamp,
  String? afterMessageId,
  String? afterAttachmentId,
}) async {
  if (limit < 1 || limit > 100) {
    throw ArgumentError.value(limit, 'limit', 'must be within 1..100');
  }
  if (scopeKind != 'direct' && scopeKind != 'group') {
    throw ArgumentError.value(scopeKind, 'scopeKind', 'unknown scope kind');
  }
  if (mediaTypes.isEmpty) {
    throw ArgumentError.value(mediaTypes, 'mediaTypes', 'must not be empty');
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_LIBRARY_DB_PAGE_START',
    details: {
      'scopeKind': scopeKind,
      'mediaTypes': mediaTypes,
      'bookmarkedOnly': bookmarkedOnly,
      'limit': limit,
    },
  );

  try {
    final typePlaceholders = List.filled(mediaTypes.length, '?').join(', ');
    final args = <Object?>[];

    final String parentJoin;
    final String parentPredicate;
    final String senderSelect;
    if (scopeKind == 'direct') {
      parentJoin = 'JOIN messages p ON p.id = m.message_id';
      parentPredicate =
          "m.owner_lane = 'direct' AND p.contact_peer_id = ? "
          'AND p.hidden_at IS NULL AND p.deleted_at IS NULL';
      senderSelect = 'p.sender_peer_id AS parent_sender_peer_id';
    } else {
      parentJoin = 'JOIN group_messages p ON p.id = m.message_id';
      parentPredicate =
          "m.owner_lane = 'group' AND p.group_id = ? "
          'AND NOT EXISTS (SELECT 1 FROM group_message_local_deletions t '
          'WHERE t.message_id = p.id)';
      senderSelect = 'p.sender_peer_id AS parent_sender_peer_id';
    }
    args.add(scopeId);
    args.addAll(mediaTypes);

    var bookmarkPredicate = '';
    if (bookmarkedOnly) {
      bookmarkPredicate = ' AND m.is_bookmarked = 1';
    }

    var keysetPredicate = '';
    if (afterTimestamp != null &&
        afterMessageId != null &&
        afterAttachmentId != null) {
      keysetPredicate =
          ' AND (p.timestamp < ? '
          'OR (p.timestamp = ? AND m.message_id < ?) '
          'OR (p.timestamp = ? AND m.message_id = ? AND m.id < ?))';
      args.addAll([
        afterTimestamp,
        afterTimestamp,
        afterMessageId,
        afterTimestamp,
        afterMessageId,
        afterAttachmentId,
      ]);
    }
    args.add(limit);

    final rows = await db.rawQuery(
      'SELECT ${_attachmentSelectList()}, '
      'p.timestamp AS parent_timestamp, $senderSelect '
      'FROM media_attachments m '
      '$parentJoin '
      'WHERE $parentPredicate '
      'AND m.media_type IN ($typePlaceholders)'
      '$bookmarkPredicate'
      '$keysetPredicate '
      'ORDER BY p.timestamp DESC, m.message_id DESC, m.id DESC '
      'LIMIT ?',
      args,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_LIBRARY_DB_PAGE_SUCCESS',
      details: {'count': rows.length},
    );

    return rows;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_LIBRARY_DB_PAGE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads one raw owner-scoped all-media STORAGE page (229 TC-229-08).
///
/// Same owner scoping, parent visibility and tombstone rules as
/// [dbLoadMediaLibraryPage] — direct requires a live un-hidden parent, group
/// anti-joins the durable local-deletion tombstones, `unresolved` rows never
/// match — but serves the storage inventory instead of the visual library:
/// all four media types are addressable, there is no bookmark dimension, and
/// only rows with a stored `local_path` (the only rows that can occupy local
/// storage) are returned. Byte truth stays with the caller: it must stat the
/// canonical file and never trust `size` for storage totals.
Future<List<Map<String, Object?>>> dbLoadMediaStoragePage(
  Database db, {
  required String scopeKind, // 'direct' | 'group'
  required String scopeId,
  required List<String> mediaTypes,
  required int limit,
  String? afterTimestamp,
  String? afterMessageId,
  String? afterAttachmentId,
}) async {
  if (limit < 1 || limit > 100) {
    throw ArgumentError.value(limit, 'limit', 'must be within 1..100');
  }
  if (scopeKind != 'direct' && scopeKind != 'group') {
    throw ArgumentError.value(scopeKind, 'scopeKind', 'unknown scope kind');
  }
  if (mediaTypes.isEmpty) {
    throw ArgumentError.value(mediaTypes, 'mediaTypes', 'must not be empty');
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_STORAGE_DB_PAGE_START',
    details: {
      'scopeKind': scopeKind,
      'mediaTypes': mediaTypes,
      'limit': limit,
    },
  );

  try {
    final typePlaceholders = List.filled(mediaTypes.length, '?').join(', ');
    final args = <Object?>[];

    final String parentJoin;
    final String parentPredicate;
    if (scopeKind == 'direct') {
      parentJoin = 'JOIN messages p ON p.id = m.message_id';
      parentPredicate =
          "m.owner_lane = 'direct' AND p.contact_peer_id = ? "
          'AND p.hidden_at IS NULL AND p.deleted_at IS NULL';
    } else {
      parentJoin = 'JOIN group_messages p ON p.id = m.message_id';
      parentPredicate =
          "m.owner_lane = 'group' AND p.group_id = ? "
          'AND NOT EXISTS (SELECT 1 FROM group_message_local_deletions t '
          'WHERE t.message_id = p.id)';
    }
    args.add(scopeId);
    args.addAll(mediaTypes);

    var keysetPredicate = '';
    if (afterTimestamp != null &&
        afterMessageId != null &&
        afterAttachmentId != null) {
      keysetPredicate =
          ' AND (p.timestamp < ? '
          'OR (p.timestamp = ? AND m.message_id < ?) '
          'OR (p.timestamp = ? AND m.message_id = ? AND m.id < ?))';
      args.addAll([
        afterTimestamp,
        afterTimestamp,
        afterMessageId,
        afterTimestamp,
        afterMessageId,
        afterAttachmentId,
      ]);
    }
    args.add(limit);

    final rows = await db.rawQuery(
      'SELECT ${_attachmentSelectList()}, '
      'p.timestamp AS parent_timestamp '
      'FROM media_attachments m '
      '$parentJoin '
      'WHERE $parentPredicate '
      'AND m.media_type IN ($typePlaceholders) '
      'AND m.local_path IS NOT NULL'
      '$keysetPredicate '
      'ORDER BY p.timestamp DESC, m.message_id DESC, m.id DESC '
      'LIMIT ?',
      args,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_STORAGE_DB_PAGE_SUCCESS',
      details: {'count': rows.length},
    );

    return rows;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_STORAGE_DB_PAGE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
