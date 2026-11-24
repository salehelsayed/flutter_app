import 'package:flutter_app/core/database/helpers/local_ai_preview_db_helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_preview_fixture.dart';

const _source = 'انا جاى بعد شوية، استنانى تحت 😂';
const _translation = 'Ich komme gleich, warte auf dich unten 😂';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LocalPreviewFixture fixture;

  setUp(() async {
    fixture = LocalPreviewFixture();
    await fixture.open();
    final iso = DateTime.fromMillisecondsSinceEpoch(
      fixture.nowMs,
      isUtc: true,
    ).toIso8601String();
    for (final (id, incoming) in [('received', 1), ('sent', 0)]) {
      await fixture.db.insert('messages', {
        'id': id,
        'contact_peer_id': 'contact',
        'sender_peer_id': incoming == 1 ? 'contact' : 'me',
        'text': _source,
        'timestamp': iso,
        'created_at': iso,
        'is_incoming': incoming,
      });
    }
  });
  tearDown(() => fixture.dispose());

  Future<bool> save(String messageId) => dbSaveLocalTranslation(
    fixture.db,
    ownerKind: 'message',
    ownerId: messageId,
    source: _source,
    targetLanguage: 'de',
    result: _translation,
    nowMs: fixture.nowMs,
  );

  Future<String?> load(String messageId, {String source = _source}) =>
      dbLoadLocalTranslation(
        fixture.db,
        ownerKind: 'message',
        ownerId: messageId,
        source: source,
        targetLanguage: 'de',
        nowMs: fixture.nowMs,
      );

  Future<void> seedStoredRow() => fixture.db.insert('local_ai_translations', {
    'owner_kind': 'message',
    'owner_id': 'received',
    'target_language': 'de',
    'source_sha256': 'stored',
    'translated_text': _translation,
  });

  Future<int> storedRows() async => (await fixture.db.query(
    'local_ai_translations',
    where: "owner_kind = 'message'",
  )).length;

  test('a received message translation is saved and read back after a '
      'restart', () async {
    expect(await save('received'), isTrue);
    await fixture.reopen();
    expect(await load('received'), _translation);
  });

  test('a saved translation is not shown once the message text changed', () async {
    expect(await save('received'), isTrue);
    expect(await load('received', source: 'something else'), isNull);
  });

  test('an outgoing message is never a translation source', () async {
    expect(await save('sent'), isFalse);
    expect(await storedRows(), 0);
  });

  for (final (label, change) in <(String, String)>[
    ('deleting the message', "DELETE FROM messages WHERE id = 'received'"),
    (
      'deleting it for everyone',
      "UPDATE messages SET deleted_at = '2030-01-01T00:00:00Z' "
          "WHERE id = 'received'",
    ),
    (
      'hiding it',
      "UPDATE messages SET hidden_at = '2030-01-01T00:00:00Z' "
          "WHERE id = 'received'",
    ),
    (
      'editing its text',
      "UPDATE messages SET text = 'edited' WHERE id = 'received'",
    ),
  ]) {
    test('$label removes its stored translation', () async {
      await seedStoredRow();
      await fixture.db.execute(change);
      expect(await storedRows(), 0);
    });
  }
}
