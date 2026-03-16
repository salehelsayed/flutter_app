import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/032_posts_retry_recipient_context.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late PostRepositoryImpl repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runPostsCoreMigration(db);
    await runPostsPassAlongMigration(db);
    await runPostsRetryRecipientContextMigration(db);
    repository = PostRepositoryImpl(
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (postId) => dbLoadPost(db, postId),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db),
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (postId) =>
          dbLoadPostRecipientDeliveries(db, postId),
      dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
    );
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  test('migration creates posts core tables', () async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((row) => row['name']).toList();

    expect(names, contains('posts'));
    expect(names, contains('post_recipients'));
    expect(names, contains('post_feed_state'));
  });

  test(
    'repository round-trip persists posts and recipient delivery state',
    () async {
      const post = PostModel(
        id: 'post-1',
        eventId: 'evt-1',
        senderPeerId: 'peer-a',
        authorPeerId: 'peer-a',
        authorUsername: 'Alice',
        text: 'Hello posts',
        audience: PostAudience(kind: PostAudienceKind.allFriends),
        createdAt: '2026-03-15T10:15:30.000Z',
        visibleAt: '2026-03-15T10:15:30.000Z',
        expiresAt: '2026-03-18T10:15:30.000Z',
        isIncoming: true,
        deliveryStatus: 'delivered',
      );
      const delivery = PostRecipientDelivery(
        postId: 'post-1',
        recipientPeerId: 'peer-b',
        deliveryStatus: 'delivered',
        lastAttemptAt: '2026-03-15T10:15:31.000Z',
        deliveryPath: 'direct',
        nearbyDistanceM: 87,
        createdAt: '2026-03-15T10:15:31.000Z',
        updatedAt: '2026-03-15T10:15:31.000Z',
      );

      await repository.savePost(post);
      await repository.saveRecipientDelivery(delivery);
      await repository.markFocused(post.id);

      final loaded = await repository.getPost(post.id);
      final deliveries = await repository.getRecipientDeliveries(post.id);

      expect(loaded, isNotNull);
      expect(loaded!.text, 'Hello posts');
      expect(loaded.isFocused, isTrue);
      expect(deliveries, hasLength(1));
      expect(deliveries.single.deliveryStatus, 'delivered');
      expect(deliveries.single.nearbyDistanceM, 87);
    },
  );
}
