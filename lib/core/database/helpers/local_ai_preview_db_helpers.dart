import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../media/private_media_policy.dart';
import '../db_write_transaction.dart';
import 'messages_db_helpers.dart';

int _now(int? nowMs) => nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;

Future<Map<String, Object?>?> _liveVoice(
  DatabaseExecutor txn,
  String attachmentId,
  int nowMs,
  String expectedMessageId,
) async {
  final attachments = await txn.query(
    'media_attachments',
    where:
        "id = ? AND message_id = ? AND media_type = 'audio' AND owner_lane = 'direct'",
    whereArgs: [attachmentId, expectedMessageId],
    limit: 1,
  );
  if (attachments.isEmpty) return null;
  final messageId = attachments.single['message_id'] as String;
  await dbAdvanceDirectPrivateMediaClockWithinTransaction(
    txn,
    messageId,
    nowMs: nowMs,
  );
  final parents = await txn.query(
    'messages',
    where:
        'id = ? AND is_incoming = 1 AND deleted_at IS NULL AND hidden_at IS NULL',
    whereArgs: [messageId],
    limit: 1,
  );
  if (parents.isEmpty) return null;
  final parent = parents.single;
  final policy = PrivateMediaPolicy.fromDatabase(
    version: parent['private_media_policy_version'],
    mode: parent['private_media_mode'],
    durationSeconds: parent['private_media_duration_seconds'],
  );
  final state = PrivateMediaLifecycleState.fromWireValue(
    parent['private_media_state'],
  );
  if (policy.isUnsupported ||
      state.isTerminal ||
      parent['private_media_terminal_at_ms'] != null) {
    return null;
  }
  if (policy.mode == PrivateMediaMode.ordinary) {
    if (policy.version != 0 ||
        state != PrivateMediaLifecycleState.none ||
        const [
          'private_media_received_at_ms',
          'private_media_expires_at_ms',
          'private_media_revealed_at_ms',
          'private_media_clock_high_water_ms',
        ].any((column) => parent[column] != null)) {
      return null;
    }
  } else if (!const {
    PrivateMediaLifecycleState.available,
    PrivateMediaLifecycleState.opening,
    PrivateMediaLifecycleState.viewing,
  }.contains(state)) {
    return null;
  }
  if (policy.mode == PrivateMediaMode.disappearing &&
      parent['private_media_expires_at_ms'] == null) {
    return null;
  }
  return (await txn.query(
    'media_attachments',
    where: 'id = ? AND message_id = ?',
    whereArgs: [attachmentId, messageId],
    limit: 1,
  )).single;
}

Future<String?> dbLoadLocalTranscript(
  Database db,
  String attachmentId,
  String messageId, {
  int? nowMs,
}) => dbWriteTransaction(db, (txn) async {
  final row = await _liveVoice(txn, attachmentId, _now(nowMs), messageId);
  return row?['local_transcript'] as String?;
});

Future<bool> dbSaveLocalTranscript(
  Database db,
  String attachmentId,
  String messageId,
  String result, {
  int? nowMs,
}) => dbWriteTransaction(db, (txn) async {
  if (result.isEmpty ||
      await _liveVoice(txn, attachmentId, _now(nowMs), messageId) == null) {
    return false;
  }
  await txn.update(
    'media_attachments',
    {'local_transcript': result},
    where: 'id = ?',
    whereArgs: [attachmentId],
  );
  return true;
});

Future<String?> _currentSource(
  DatabaseExecutor txn,
  String kind,
  String id,
  int nowMs,
  String? messageId,
) async {
  if (kind == 'voiceAttachment') {
    if (messageId == null) return null;
    return (await _liveVoice(txn, id, nowMs, messageId))?['local_transcript']
        as String?;
  }
  if (kind != 'thought') return null;
  final rows = await txn.rawQuery(
    '''
    SELECT p.text FROM posts p
    LEFT JOIN post_feed_state f ON f.post_id = p.post_id
    WHERE p.post_id = ? AND COALESCE(f.is_hidden, 0) = 0
      AND julianday(p.expires_at) > julianday(?) LIMIT 1
  ''',
    [
      id,
      DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true).toIso8601String(),
    ],
  );
  return rows.isEmpty ? null : rows.single['text'] as String;
}

String _sourceHash(String source) =>
    sha256.convert(utf8.encode(source)).toString();

Future<String?> dbLoadLocalTranslation(
  Database db, {
  required String ownerKind,
  required String ownerId,
  required String source,
  required String targetLanguage,
  String? messageId,
  int? nowMs,
}) => dbWriteTransaction(db, (txn) async {
  if (await _currentSource(txn, ownerKind, ownerId, _now(nowMs), messageId) !=
      source) {
    return null;
  }
  final rows = await txn.query(
    'local_ai_translations',
    columns: ['translated_text'],
    where:
        'owner_kind = ? AND owner_id = ? AND target_language = ? AND source_sha256 = ?',
    whereArgs: [ownerKind, ownerId, targetLanguage, _sourceHash(source)],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single['translated_text'] as String;
});

Future<bool> dbSaveLocalTranslation(
  Database db, {
  required String ownerKind,
  required String ownerId,
  required String source,
  required String targetLanguage,
  required String result,
  String? messageId,
  int? nowMs,
}) => dbWriteTransaction(db, (txn) async {
  if (result.isEmpty ||
      await _currentSource(txn, ownerKind, ownerId, _now(nowMs), messageId) !=
          source) {
    return false;
  }
  await txn.insert('local_ai_translations', {
    'owner_kind': ownerKind,
    'owner_id': ownerId,
    'target_language': targetLanguage,
    'source_sha256': _sourceHash(source),
    'translated_text': result,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  return true;
});
