// ignore_for_file: file_names
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration 124 (407 Thoughts, build 128).
///
/// `post_media_attachments.preview_base64` holds a tiny encoded copy of a
/// photo, shown blurred until the photo itself downloads. Nullable, no
/// backfill: older rows and older senders simply have none.
///
/// `post_view_receipts` records the first time each friend viewed the
/// author's thought. Rows are removed with their post.
///
/// `idx_messages_thought_quote` lets the author's thought view count the
/// replies and reactions quoting a thought without reading every chat.
Future<void> runThoughtPhotoPreviewsAndViewReceiptsMigration(
  Database db,
) async {
  final columns = await db.rawQuery(
    'PRAGMA table_info(post_media_attachments)',
  );
  if (!columns.any((column) => column['name'] == 'preview_base64')) {
    await db.execute(
      'ALTER TABLE post_media_attachments ADD COLUMN preview_base64 TEXT',
    );
  }
  await db.execute('''CREATE TABLE IF NOT EXISTS post_view_receipts (
    post_id TEXT NOT NULL,
    viewer_peer_id TEXT NOT NULL,
    viewed_at TEXT NOT NULL,
    PRIMARY KEY (post_id, viewer_peer_id)
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_messages_thought_quote '
    'ON messages(quoted_message_id) WHERE quoted_message_id IS NOT NULL',
  );
}
