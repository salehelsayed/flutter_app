import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/thought_views_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _created = '2026-10-27T10:00:00.000Z';
const _live = '2026-10-28T10:00:00.000Z';
const _gone = '2026-10-27T12:00:00.000Z';

void main() {
  late Database db;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await runProductionOnCreate(db, currentIdentityDatabaseVersion);
    for (final (id, author, incoming, expires) in [
      ('own-live', 'me', false, _live),
      ('own-expired', 'me', false, _gone),
      ('own-unseen', 'me', false, _gone),
      ('incoming', 'sam', true, _live),
    ]) {
      await db.insert('posts', {
        'post_id': id,
        'event_id': 'event-$id',
        'sender_peer_id': author,
        'author_peer_id': author,
        'author_username': author,
        'text': 'thought',
        'audience_kind': 'all_friends',
        'post_created_at': _created,
        'visible_at': _created,
        'expires_at': expires,
        'is_incoming': incoming ? 1 : 0,
      });
    }
    for (final (post, viewer, at) in [
      ('own-live', 'amira', '2026-10-27T10:05:00.000Z'),
      ('own-live', 'bilal', '2026-10-27T10:09:00.000Z'),
      ('own-expired', 'amira', '2026-10-27T11:00:00.000Z'),
      ('incoming', 'me', '2026-10-27T10:30:00.000Z'),
    ]) {
      await db.insert('post_view_receipts', {
        'post_id': post,
        'viewer_peer_id': viewer,
        'viewed_at': at,
      });
    }
  });
  tearDown(() => db.close());

  test('one count per own Thought, live and expired, never incoming', () async {
    expect(
      await dbCountOwnThoughtViews(
        db,
        authorPeerId: 'me',
        postIds: ['own-live', 'own-expired', 'own-unseen', 'incoming'],
      ),
      {'own-live': 2, 'own-expired': 1},
    );
  });

  test('counts only the posts asked for', () async {
    expect(
      await dbCountOwnThoughtViews(
        db,
        authorPeerId: 'me',
        postIds: ['own-expired'],
      ),
      {'own-expired': 1},
    );
    expect(
      await dbCountOwnThoughtViews(db, authorPeerId: 'me', postIds: []),
      isEmpty,
    );
  });

  test('an expired own Thought still lists who saw it', () async {
    expect(
      await dbLoadOwnThoughtViews(
        db,
        authorPeerId: 'me',
        postId: 'own-expired',
      ),
      [
        {
          'post_id': 'own-expired',
          'viewer_peer_id': 'amira',
          'viewed_at': '2026-10-27T11:00:00.000Z',
        },
      ],
    );
  });

  test('viewers come newest first', () async {
    expect(
      [
        for (final row in await dbLoadOwnThoughtViews(
          db,
          authorPeerId: 'me',
          postId: 'own-live',
        ))
          row['viewer_peer_id'],
      ],
      ['bilal', 'amira'],
    );
  });

  test('an incoming Thought never lists viewers', () async {
    expect(
      await dbLoadOwnThoughtViews(db, authorPeerId: 'me', postId: 'incoming'),
      isEmpty,
    );
    expect(
      await dbLoadOwnThoughtViews(db, authorPeerId: 'sam', postId: 'incoming'),
      isEmpty,
    );
  });
}
