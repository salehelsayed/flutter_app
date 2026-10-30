// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> runLocalAiPreviewsMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
  if (!columns.any((row) => row['name'] == 'local_transcript')) {
    await db.execute(
      'ALTER TABLE media_attachments ADD COLUMN local_transcript TEXT',
    );
  }
  await db.execute('''
    CREATE TABLE IF NOT EXISTS local_ai_translations (
      owner_kind TEXT NOT NULL,
      owner_id TEXT NOT NULL,
      target_language TEXT NOT NULL,
      source_sha256 TEXT NOT NULL,
      translated_text TEXT NOT NULL,
      PRIMARY KEY (owner_kind, owner_id, target_language)
    )
  ''');
  const clearVoice = '''
    DELETE FROM local_ai_translations
    WHERE owner_kind = 'voiceAttachment' AND owner_id IN (
      SELECT id FROM media_attachments
      WHERE message_id = OLD.id AND owner_lane != 'group'
    );
    UPDATE media_attachments SET local_transcript = NULL
    WHERE message_id = OLD.id AND owner_lane != 'group';
  ''';
  final triggers = <String, String>{
    'local_ai_message_delete': 'AFTER DELETE ON messages BEGIN $clearVoice END',
    'local_ai_message_terminal':
        '''
      AFTER UPDATE OF deleted_at, hidden_at, private_media_state,
        private_media_terminal_at_ms, private_media_clock_high_water_ms,
        private_media_expires_at_ms ON messages
      WHEN NEW.deleted_at IS NOT NULL OR NEW.hidden_at IS NOT NULL
        OR NEW.private_media_state IN ('consumed','expired','unsupported')
        OR NEW.private_media_terminal_at_ms IS NOT NULL
        OR (NEW.private_media_mode = 'disappearing'
          AND NEW.private_media_expires_at_ms IS NOT NULL
          AND NEW.private_media_clock_high_water_ms >= NEW.private_media_expires_at_ms)
      BEGIN $clearVoice END
    ''',
    'local_ai_attachment_delete': '''
      AFTER DELETE ON media_attachments BEGIN
        DELETE FROM local_ai_translations
        WHERE owner_kind = 'voiceAttachment' AND owner_id = OLD.id;
      END
    ''',
    'local_ai_attachment_identity': '''
      AFTER UPDATE OF message_id, media_type, content_hash, owner_lane
        ON media_attachments
      WHEN OLD.message_id IS NOT NEW.message_id
        OR OLD.media_type IS NOT NEW.media_type
        OR OLD.content_hash IS NOT NEW.content_hash
        OR OLD.owner_lane IS NOT NEW.owner_lane
      BEGIN
        UPDATE media_attachments SET local_transcript = NULL WHERE id = NEW.id;
        DELETE FROM local_ai_translations
        WHERE owner_kind = 'voiceAttachment' AND owner_id = NEW.id;
      END
    ''',
    'local_ai_transcript_change': '''
      AFTER UPDATE OF local_transcript ON media_attachments
      WHEN OLD.local_transcript IS NOT NEW.local_transcript BEGIN
        DELETE FROM local_ai_translations
        WHERE owner_kind = 'voiceAttachment' AND owner_id = NEW.id;
      END
    ''',
    'local_ai_thought_delete': '''
      AFTER DELETE ON posts BEGIN
        DELETE FROM local_ai_translations
        WHERE owner_kind = 'thought' AND owner_id = OLD.post_id;
      END
    ''',
    'local_ai_thought_edit': '''
      AFTER UPDATE OF text ON posts WHEN OLD.text IS NOT NEW.text BEGIN
        DELETE FROM local_ai_translations
        WHERE owner_kind = 'thought' AND owner_id = NEW.post_id;
      END
    ''',
    'local_ai_thought_replace': '''
      BEFORE INSERT ON posts BEGIN
        DELETE FROM local_ai_translations
        WHERE owner_kind = 'thought' AND owner_id IN (
          SELECT post_id FROM posts
          WHERE (post_id = NEW.post_id AND text IS NOT NEW.text)
            OR (event_id = NEW.event_id AND post_id != NEW.post_id)
        );
      END
    ''',
    'local_ai_thought_hide': '''
      AFTER UPDATE OF is_hidden ON post_feed_state WHEN NEW.is_hidden != 0 BEGIN
        DELETE FROM local_ai_translations
        WHERE owner_kind = 'thought' AND owner_id = NEW.post_id;
      END
    ''',
  };
  for (final entry in triggers.entries) {
    await db.execute(
      'CREATE TRIGGER IF NOT EXISTS ${entry.key} ${entry.value}',
    );
  }
}
