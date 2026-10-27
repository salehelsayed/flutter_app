import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/thought_views_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _created = '2026-10-27T10:00:00.000Z';
const _viewed = '2026-10-27T12:00:00.000Z';
const _expires = '2026-10-28T10:00:00.000Z';

void main() {
  late Database db;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await runProductionOnCreate(db, currentIdentityDatabaseVersion);
  });
  tearDown(() => db.close());

  Future<void> seed({
    bool incoming = true,
    String author = 'sam',
    String expires = _expires,
  }) => db
      .insert('posts', {
        'post_id': 'thought-1',
        'event_id': 'post-event',
        'sender_peer_id': author,
        'author_peer_id': author,
        'author_username': author,
        'text': 'At the lake',
        'audience_kind': 'all_friends',
        'post_created_at': _created,
        'visible_at': _created,
        'expires_at': expires,
        'is_incoming': incoming ? 1 : 0,
      })
      .then((_) {});

  Map<String, Object?> receipt({
    String viewer = 'me',
    String viewed = _viewed,
  }) => {'post_id': 'thought-1', 'viewer_peer_id': viewer, 'viewed_at': viewed};

  Future<bool> queue({String eventId = 'view-1', String viewed = _viewed}) =>
      dbQueueThoughtView(
        db,
        receipt: receipt(viewed: viewed),
        event: {
          'event_id': eventId,
          'event_type': 'post_view',
          'post_id': 'thought-1',
          'sender_peer_id': 'me',
          'raw_envelope': '{"type":"post_view","version":"2","encrypted":{}}',
          'created_at': viewed,
        },
        recipient: {
          'event_id': eventId,
          'recipient_peer_id': 'sam',
          'delivery_status': 'pending',
          'delivery_path': 'queued',
          'created_at': viewed,
          'updated_at': viewed,
        },
        authorPeerId: 'sam',
        nowIso: viewed,
      );

  Future<void> originalRecipient(String peer) => db
      .insert('post_recipients', {
        'post_id': 'thought-1',
        'recipient_peer_id': peer,
        'delivery_status': 'inbox',
        'last_attempt_at': _created,
        'delivery_path': 'inbox',
        'created_at': _created,
        'updated_at': _created,
      })
      .then((_) {});

  test(
    'the first local view and its one encrypted outbox event commit together',
    () async {
      await seed();
      expect(await queue(), isTrue);
      expect(
        await queue(eventId: 'view-2', viewed: '2026-10-27T13:00:00.000Z'),
        isFalse,
      );
      expect(await dbLoadThoughtViews(db, 'thought-1'), [receipt()]);
      expect(
        (await db.query('post_follow_on_outbox_events')).single['event_id'],
        'view-1',
      );
      expect(
        (await db.query(
          'post_follow_on_outbox_recipient_deliveries',
        )).single['recipient_peer_id'],
        'sam',
      );
    },
  );

  test(
    'an outbox failure rolls back the view so a later open can queue it',
    () async {
      await seed();
      await db.execute('''CREATE TRIGGER fail_view BEFORE INSERT ON
      post_follow_on_outbox_recipient_deliveries BEGIN
      SELECT RAISE(ABORT, 'outbox unavailable'); END''');
      await expectLater(queue(), throwsA(isA<DatabaseException>()));
      expect(await dbLoadThoughtViews(db, 'thought-1'), isEmpty);
      expect(await db.query('post_follow_on_outbox_events'), isEmpty);
      await db.execute('DROP TRIGGER fail_view');
      expect(await queue(), isTrue);
    },
  );

  test(
    'expiry or retirement winning before queue never recreates a view or outbox',
    () async {
      await seed(expires: _viewed);
      expect(await queue(), isFalse);
      await dbDeletePostCascade(db, 'thought-1');
      expect(await queue(), isFalse);
      expect(await db.query('posts'), isEmpty);
      expect(await db.query('post_view_receipts'), isEmpty);
      expect(await db.query('post_follow_on_outbox_events'), isEmpty);
    },
  );

  test(
    'author accepts only an original recipient of their live own thought',
    () async {
      await seed(incoming: false, author: 'me');
      await originalRecipient('sam');
      Future<bool> receive(
        String peer, {
        String local = 'me',
        String at = _viewed,
      }) => dbRecordIncomingThoughtView(
        db,
        receipt: receipt(viewer: peer, viewed: at),
        localPeerId: local,
        nowIso: at,
      );
      expect(await receive('unknown'), isFalse);
      expect(await receive('sam', local: 'other-author'), isFalse);
      expect(await receive('sam'), isTrue);
      expect(await receive('sam', at: '2026-10-27T13:00:00.000Z'), isFalse);
      expect(await dbLoadThoughtViews(db, 'thought-1'), [
        receipt(viewer: 'sam'),
      ]);
    },
  );

  test('inbox custody alone does not count as a view', () async {
    await seed(incoming: false, author: 'me');
    await originalRecipient('sam');
    expect(await dbLoadThoughtViews(db, 'thought-1'), isEmpty);
  });

  test(
    'reaction lookup is limited to incoming ordinary replies to this quote',
    () async {
      Future<void> message(
        String id, {
        String quote = 'thought:thought-1',
        bool incoming = true,
        String? hidden,
      }) => db
          .insert(
            'messages',
            ConversationMessage(
              id: id,
              contactPeerId: 'sam',
              senderPeerId: 'sam',
              text: '❤️',
              timestamp: _viewed,
              createdAt: _viewed,
              isIncoming: incoming,
              status: 'delivered',
              quotedMessageId: quote,
              hiddenAt: hidden,
            ).toMap(),
          )
          .then((_) {});
      await message('reaction');
      await message('other', quote: 'thought:other');
      await message('outgoing', incoming: false);
      await message('hidden', hidden: _viewed);
      await message('photo-caption');
      await db.insert('media_attachments', {
        'id': 'photo',
        'message_id': 'photo-caption',
        'mime': 'image/jpeg',
        'size': 1,
        'media_type': 'image',
        'created_at': _viewed,
      });
      expect(
        (await dbLoadThoughtReactionMessages(
          db,
          'thought-1',
        )).map((row) => row['id']),
        ['reaction'],
      );
      expect(await dbLoadThoughtReactionMessages(db, 'missing'), isEmpty);
    },
  );

  test(
    'deleting a thought removes views and queued views, preserving a retraction',
    () async {
      await seed();
      await queue();
      await db.insert('post_follow_on_outbox_events', {
        'event_id': 'retract-1',
        'event_type': 'post_retract',
        'post_id': 'thought-1',
        'sender_peer_id': 'me',
        'raw_envelope': '{}',
        'created_at': _viewed,
      });
      await dbDeletePostCascade(db, 'thought-1');
      expect(await db.query('post_view_receipts'), isEmpty);
      expect(
        await db.query('post_follow_on_outbox_recipient_deliveries'),
        isEmpty,
      );
      expect(
        (await db.query('post_follow_on_outbox_events')).single['event_id'],
        'retract-1',
      );
    },
  );

  test('late incoming view after expiry or delete is discarded', () async {
    await seed(incoming: false, author: 'me', expires: _viewed);
    await originalRecipient('sam');
    Future<bool> receive() => dbRecordIncomingThoughtView(
      db,
      receipt: receipt(viewer: 'sam'),
      localPeerId: 'me',
      nowIso: _viewed,
    );
    expect(await receive(), isFalse);
    await dbDeletePostCascade(db, 'thought-1');
    expect(await receive(), isFalse);
    expect(await db.query('posts'), isEmpty);
    expect(await db.query('post_view_receipts'), isEmpty);
  });
}
