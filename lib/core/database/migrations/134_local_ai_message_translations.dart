// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '125_local_ai_previews.dart';

/// Received chat-message translations live in local_ai_translations under
/// owner_kind 'message'. They go with the message: deleted, deleted for
/// everyone, hidden, expired, or edited.
Future<void> runLocalAiMessageTranslationsMigration(Database db) async {
  const clear =
      "DELETE FROM local_ai_translations WHERE owner_kind = 'message'";
  final triggers = <String, String>{
    'local_ai_message_translation_delete':
        'AFTER DELETE ON messages BEGIN $clear AND owner_id = OLD.id; END',
    'local_ai_message_translation_terminal':
        '$localAiMessageTerminalTrigger      '
        'BEGIN $clear AND owner_id = NEW.id; END',
    'local_ai_message_translation_edit':
        'AFTER UPDATE OF text ON messages WHEN OLD.text IS NOT NEW.text '
        'BEGIN $clear AND owner_id = NEW.id; END',
  };
  for (final entry in triggers.entries) {
    await db.execute(
      'CREATE TRIGGER IF NOT EXISTS ${entry.key} ${entry.value}',
    );
  }
}
