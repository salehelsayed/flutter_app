import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_follow_on_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  final wallNow = DateTime.now().toUtc();
  final oldCreated = wallNow.subtract(const Duration(hours: 3));
  final clocks = <String, DateTime>{
    'clock after the replacement': wallNow.add(const Duration(minutes: 5)),
    'clock behind the replacement': wallNow.subtract(const Duration(hours: 1)),
  };

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        onCreate: runProductionOnCreate,
      ),
    );
  });
  tearDown(() => db.close());

  PostRepositoryImpl repository(DateTime now) {
    final posts = PostRepositoryImpl(
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (id) => dbLoadPost(db, id, nowProvider: () => now),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db, nowProvider: () => now),
      dbLoadRetryableOutgoingPosts: () =>
          dbLoadRetryableOutgoingPosts(db, nowProvider: () => now),
      dbLoadExpiredOwnPosts: (iso, {limit, offset = 0}) =>
          dbLoadExpiredOwnPosts(db, iso, limit: limit, offset: offset),
      dbRetireReplacedThought: (id, replacedAt) =>
          dbRetireReplacedThought(db, id, replacedAt),
      dbDeletePostCascade: (id) => dbDeletePostCascade(db, id),
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (id) => dbLoadPostRecipientDeliveries(db, id),
      dbUpsertFollowOnOutboxEventWithRecipients: (event, recipients) =>
          dbUpsertPostFollowOnOutboxEventWithRecipients(db, event, recipients),
      dbMarkPostFocused: (id) => dbMarkPostFocused(db, id),
    );
    addTearDown(posts.dispose);
    return posts;
  }

  Future<void> seedOldThought(PostRepositoryImpl posts) async {
    final at = oldCreated.toIso8601String();
    await dbInsertPost(db, <String, Object?>{
      'post_id': 'old',
      'event_id': 'evt-old',
      'sender_peer_id': 'me',
      'author_peer_id': 'me',
      'author_username': 'Me',
      'text': 'old thought',
      'audience_kind': 'all_friends',
      'post_created_at': at,
      'visible_at': at,
      'expires_at': oldCreated.add(const Duration(hours: 24)).toIso8601String(),
      'is_incoming': 0,
      'delivery_status': 'partial',
      'keep_available': 0,
    });
    for (final friend in ['peer-bob', 'peer-carl']) {
      await posts.saveRecipientDelivery(
        PostRecipientDelivery(
          postId: 'old',
          recipientPeerId: friend,
          deliveryStatus: friend == 'peer-bob' ? 'delivered' : 'failed',
          lastAttemptAt: at,
          deliveryPath: friend == 'peer-bob' ? 'direct' : 'failed',
          createdAt: at,
          updatedAt: at,
        ),
      );
    }
    await db.insert('post_view_receipts', {
      'post_id': 'old',
      'viewer_peer_id': 'peer-bob',
      'viewed_at': at,
    });
    await db.insert('post_reactions', {
      'reaction_id': 'reaction-bob',
      'event_id': 'evt-reaction-bob',
      'post_id': 'old',
      'sender_peer_id': 'peer-bob',
      'kind': 'heart',
      'is_active': 1,
      'reacted_at': at,
      'created_at': at,
    });
    await db.insert('post_follow_on_outbox_events', {
      'event_id': 'evt-unsent-follow-on',
      'event_type': 'post_view',
      'post_id': 'old',
      'sender_peer_id': 'me',
      'raw_envelope': '{}',
      'created_at': at,
    });
    await db.insert('post_follow_on_outbox_recipient_deliveries', {
      'event_id': 'evt-unsent-follow-on',
      'recipient_peer_id': 'peer-bob',
      'delivery_status': 'pending',
      'delivery_path': 'pending',
      'created_at': at,
      'updated_at': at,
    });
    await db.insert('post_pending_child_events', {
      'event_id': 'evt-pending-child',
      'post_id': 'old',
      'event_type': 'post_reaction',
      'sender_peer_id': 'peer-bob',
      'created_at': at,
      'raw_envelope': '{}',
    });
    await db.insert('post_media_upload_recovery', {
      'post_id': 'old',
      'position': 0,
      'local_file_path': '/drafts/old.jpg',
      'mime': 'image/jpeg',
      'kind': 'image',
      'created_at': at,
    });
  }

  Future<List<Object?>> column(String sql) async => (await db.rawQuery(sql, [
    'old',
  ])).map((row) => row.values.single).toList();

  for (final MapEntry(key: clock, value: now) in clocks.entries) {
    test('$clock: a newer thought keeps the old one in history', () async {
      final posts = repository(now);
      await seedOldThought(posts);
      final contacts = InMemoryContactRepository()
        ..addTestContact(
          ContactModel(
            peerId: 'peer-bob',
            publicKey: 'pk-bob',
            rendezvous: 'rendezvous',
            username: 'Bob',
            signature: 'sig-bob',
            scannedAt: oldCreated.toIso8601String(),
          ),
        );
      final media = FakeMediaFileManager();

      final (result, created) = await createLocalPost(
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'me',
        senderUsername: 'Me',
        text: 'newer thought',
        audience: PostAudience.allFriends(),
        mediaFileManager: media,
      );

      expect(result, SendPostResult.success);
      final newId = created!.post.id;
      expect((await posts.loadFeed()).map((post) => post.id), [newId]);
      expect(await posts.getPost('old'), isNull);
      expect(
        (await posts.loadRetryableOutgoingPosts()).map((post) => post.id),
        [newId],
      );
      final history = await posts.loadExpiredOwnPosts(now.toIso8601String());
      expect(history.map((post) => post.id), ['old']);
      expect(history.single.expiresAt, created.post.createdAt);
      expect(history.single.deliveryStatus, 'sent');
      expect(
        await column(
          'SELECT viewer_peer_id FROM post_view_receipts WHERE post_id = ?',
        ),
        ['peer-bob'],
      );
      expect(
        await column(
          'SELECT reaction_id FROM post_reactions WHERE post_id = ?',
        ),
        ['reaction-bob'],
      );
      expect(
        await column(
          'SELECT recipient_peer_id FROM post_recipients WHERE post_id = ? '
          'ORDER BY recipient_peer_id',
        ),
        ['peer-bob', 'peer-carl'],
      );
      expect(
        await column(
          "SELECT e.event_type || ':' || d.recipient_peer_id "
          'FROM post_follow_on_outbox_events e '
          'JOIN post_follow_on_outbox_recipient_deliveries d '
          'ON d.event_id = e.event_id WHERE e.post_id = ?',
        ),
        ['post_retract:peer-carl'],
      );
      expect(
        await column(
          'SELECT event_id FROM post_pending_child_events WHERE post_id = ?1 '
          'UNION ALL SELECT local_file_path FROM post_media_upload_recovery '
          'WHERE post_id = ?1',
        ),
        isEmpty,
      );
      expect(media.deletedPostIds, isEmpty);
    });
  }
}
