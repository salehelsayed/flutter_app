import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';

Future<List<Map<String, Object?>>> dbLoadThoughtViews(
  Database db,
  String postId,
) => db.query(
  'post_view_receipts',
  where: 'post_id = ?',
  whereArgs: [postId],
  orderBy: 'viewed_at ASC, viewer_peer_id ASC',
);

Future<bool> dbQueueThoughtView(
  Database db, {
  required Map<String, Object?> receipt,
  required Map<String, Object?> event,
  required Map<String, Object?> recipient,
  required String authorPeerId,
  required String nowIso,
}) async {
  if (event['event_type'] != 'post_view' ||
      event['post_id'] != receipt['post_id'] ||
      event['sender_peer_id'] != receipt['viewer_peer_id'] ||
      event['event_id'] != recipient['event_id'] ||
      recipient['recipient_peer_id'] != authorPeerId) {
    return false;
  }
  return dbWriteTransaction(db, (txn) async {
    final post = await txn.query(
      'posts',
      columns: ['post_id'],
      where:
          'post_id = ? AND author_peer_id = ? AND is_incoming = 1 '
          'AND expires_at > ? AND post_created_at <= ?',
      whereArgs: [
        receipt['post_id'],
        authorPeerId,
        nowIso,
        receipt['viewed_at'],
      ],
    );
    if (post.isEmpty || await _alreadyViewed(txn, receipt)) return false;
    await txn.insert('post_view_receipts', receipt);
    await txn.insert('post_follow_on_outbox_events', event);
    await txn.insert('post_follow_on_outbox_recipient_deliveries', recipient);
    return true;
  });
}

Future<bool> dbRecordIncomingThoughtView(
  Database db, {
  required Map<String, Object?> receipt,
  required String localPeerId,
  required String nowIso,
}) => dbWriteTransaction(db, (txn) async {
  final post = await txn.rawQuery(
    '''SELECT p.post_id FROM posts p
       WHERE p.post_id = ? AND p.author_peer_id = ? AND p.is_incoming = 0
         AND p.expires_at > ? AND p.post_created_at <= ?
         AND EXISTS (SELECT 1 FROM post_recipients r
                     WHERE r.post_id = p.post_id AND r.recipient_peer_id = ?)''',
    [
      receipt['post_id'],
      localPeerId,
      nowIso,
      receipt['viewed_at'],
      receipt['viewer_peer_id'],
    ],
  );
  if (post.isEmpty || await _alreadyViewed(txn, receipt)) return false;
  await txn.insert('post_view_receipts', receipt);
  return true;
});

Future<bool> _alreadyViewed(
  Transaction txn,
  Map<String, Object?> receipt,
) async => (await txn.query(
  'post_view_receipts',
  columns: ['post_id'],
  where: 'post_id = ? AND viewer_peer_id = ?',
  whereArgs: [receipt['post_id'], receipt['viewer_peer_id']],
  limit: 1,
)).isNotEmpty;

/// Uses the quote lookup rather than loading every friend's whole chat.
Future<List<Map<String, Object?>>> dbLoadThoughtReactionMessages(
  Database db,
  String postId,
) => db.rawQuery(
  '''SELECT m.* FROM messages m
     WHERE m.quoted_message_id = ? AND m.is_incoming = 1
       AND m.hidden_at IS NULL AND m.deleted_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM media_attachments a
                       WHERE a.message_id = m.id)
     ORDER BY m.timestamp ASC, m.id ASC''',
  ['thought:$postId'],
);
