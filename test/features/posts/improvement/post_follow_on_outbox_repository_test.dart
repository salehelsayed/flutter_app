import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_follow_on_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/033_posts_follow_on_outbox.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runPostsCoreMigration(db);
    await runPostsFollowOnOutboxMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  PostRepositoryImpl buildRepository() {
    return PostRepositoryImpl(
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (postId) => dbLoadPost(db, postId),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db),
      dbUpsertRecipientDelivery: (row) => dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (postId) => dbLoadPostRecipientDeliveries(db, postId),
      dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
      dbUpsertFollowOnOutboxEvent: (row) =>
          dbUpsertPostFollowOnOutboxEvent(db, row),
      dbLoadFollowOnOutboxEvent: (eventId) =>
          dbLoadPostFollowOnOutboxEvent(db, eventId),
      dbLoadRetryableFollowOnOutboxEvents: () =>
          dbLoadRetryablePostFollowOnOutboxEvents(db),
      dbUpsertFollowOnOutboxRecipientDelivery: (row) =>
          dbUpsertPostFollowOnOutboxRecipientDelivery(db, row),
      dbLoadFollowOnOutboxRecipientDeliveries: (eventId) =>
          dbLoadPostFollowOnOutboxRecipientDeliveries(db, eventId),
      dbLoadRetryableFollowOnOutboxRecipientDeliveries: (eventIds) =>
          dbLoadRetryablePostFollowOnOutboxRecipientDeliveries(db, eventIds),
    );
  }

  test(
    'repository round-trip preserves outbox rows and retryable loading excludes settled recipients',
    () async {
      final firstRepository = buildRepository();
      const event = PostFollowOnOutboxEvent(
        eventId: 'evt-follow-on-1',
        eventType: 'post_comment',
        postId: 'post-1',
        commentId: 'comment-1',
        senderPeerId: 'peer-bob',
        rawEnvelope: '{"type":"post_comment","event_id":"evt-follow-on-1"}',
        createdAt: '2026-03-16T10:00:00.000Z',
      );
      const deliveries = <PostFollowOnOutboxRecipientDelivery>[
        PostFollowOnOutboxRecipientDelivery(
          eventId: 'evt-follow-on-1',
          recipientPeerId: 'peer-cara',
          deliveryStatus: 'delivered',
          deliveryPath: 'direct',
          lastAttemptAt: '2026-03-16T10:01:00.000Z',
          createdAt: '2026-03-16T10:00:00.000Z',
          updatedAt: '2026-03-16T10:01:00.000Z',
        ),
        PostFollowOnOutboxRecipientDelivery(
          eventId: 'evt-follow-on-1',
          recipientPeerId: 'peer-drew',
          deliveryStatus: 'inbox',
          deliveryPath: 'inbox',
          lastAttemptAt: '2026-03-16T10:01:30.000Z',
          createdAt: '2026-03-16T10:00:00.000Z',
          updatedAt: '2026-03-16T10:01:30.000Z',
        ),
        PostFollowOnOutboxRecipientDelivery(
          eventId: 'evt-follow-on-1',
          recipientPeerId: 'peer-erin',
          deliveryStatus: 'failed',
          deliveryPath: 'inbox',
          lastError: 'timeout',
          lastAttemptAt: '2026-03-16T10:02:00.000Z',
          createdAt: '2026-03-16T10:00:00.000Z',
          updatedAt: '2026-03-16T10:02:00.000Z',
        ),
        PostFollowOnOutboxRecipientDelivery(
          eventId: 'evt-follow-on-1',
          recipientPeerId: 'peer-fern',
          deliveryStatus: 'pending',
          deliveryPath: 'unknown',
          createdAt: '2026-03-16T10:00:00.000Z',
          updatedAt: '2026-03-16T10:00:00.000Z',
        ),
      ];

      await firstRepository.saveFollowOnOutboxEvent(event);
      for (final delivery in deliveries) {
        await firstRepository.saveFollowOnOutboxRecipientDelivery(delivery);
      }
      firstRepository.dispose();

      final secondRepository = buildRepository();
      final loadedEvent = await secondRepository.getFollowOnOutboxEvent(
        event.eventId,
      );
      final loadedDeliveries = await secondRepository
          .loadFollowOnOutboxRecipientDeliveries(event.eventId);
      final retryableJobs = await secondRepository.loadRetryableFollowOnOutboxJobs();

      expect(loadedEvent, isNotNull);
      expect(loadedEvent!.eventId, event.eventId);
      expect(loadedEvent.eventType, event.eventType);
      expect(loadedEvent.postId, event.postId);
      expect(loadedEvent.commentId, event.commentId);
      expect(loadedEvent.senderPeerId, event.senderPeerId);
      expect(loadedEvent.rawEnvelope, event.rawEnvelope);
      expect(loadedEvent.createdAt, event.createdAt);

      expect(
        loadedDeliveries.map((delivery) => delivery.recipientPeerId).toList(),
        <String>['peer-cara', 'peer-drew', 'peer-erin', 'peer-fern'],
      );
      expect(
        loadedDeliveries
            .map(
              (delivery) =>
                  '${delivery.recipientPeerId}:${delivery.deliveryStatus}:${delivery.deliveryPath}',
            )
            .toList(growable: false),
        <String>[
          'peer-cara:delivered:direct',
          'peer-drew:inbox:inbox',
          'peer-erin:failed:inbox',
          'peer-fern:pending:unknown',
        ],
      );
      expect(
        loadedDeliveries
            .firstWhere((delivery) => delivery.recipientPeerId == 'peer-erin')
            .lastError,
        'timeout',
      );
      expect(
        loadedDeliveries
            .firstWhere((delivery) => delivery.recipientPeerId == 'peer-erin')
            .lastAttemptAt,
        '2026-03-16T10:02:00.000Z',
      );

      expect(retryableJobs, hasLength(1));
      expect(retryableJobs.single.event.eventId, event.eventId);
      expect(
        retryableJobs.single.recipientDeliveries
            .map((delivery) => delivery.recipientPeerId)
            .toList(growable: false),
        <String>['peer-erin', 'peer-fern'],
      );

      secondRepository.dispose();
    },
  );
}
