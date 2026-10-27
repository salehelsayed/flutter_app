import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_follow_on_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/124_thought_photo_previews_and_view_receipts.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/031_posts_pins.dart';
import 'package:flutter_app/core/database/migrations/033_posts_follow_on_outbox.dart';
import 'package:flutter_app/core/database/migrations/034_posts_media_upload_recovery.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:flutter_app/core/database/migrations/039_posts_pass_avatar_snapshots.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/application/retract_thought_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_retract_envelope.dart';
import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late PathProviderPlatform previousPathProvider;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('post_follow_on_outbox_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _PathProvider(tempDir.path);
    db = await openDatabase('${tempDir.path}/posts.db', version: 1);
    await runPostsCoreMigration(db);
    await runPostsEngagementMigration(db);
    await runPostsPassAlongMigration(db);
    await runPostsPinsMigration(db);
    await runPostsFollowOnOutboxMigration(db);
    await runPostsMediaUploadRecoveryMigration(db);
    await runPostsRepostEngagementStateMigration(db);
    await runPostsPassAvatarSnapshotsMigration(db);
    await runMessagesTableMigration(db);
    await runQuotedMessageIdMigration(db);
    await runThoughtPhotoPreviewsAndViewReceiptsMigration(db);
  });

  tearDown(() async {
    await db.close();
    PathProviderPlatform.instance = previousPathProvider;
    await tempDir.delete(recursive: true);
  });

  PostRepositoryImpl buildRepository({
    Future<void> Function()? afterInitialQueueWrite,
  }) {
    return PostRepositoryImpl(
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (postId) => dbLoadPost(
        db,
        postId,
        nowProvider: () => DateTime.utc(2026, 3, 15, 12),
      ),
      dbLoadPostsFeed: () =>
          dbLoadPostsFeed(db, nowProvider: () => DateTime.utc(2026, 3, 15, 12)),
      dbDeletePostCascade: (postId) => dbDeletePostCascade(db, postId),
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (postId) =>
          dbLoadPostRecipientDeliveries(db, postId),
      dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
      dbUpsertFollowOnOutboxEvent: (row) =>
          dbUpsertPostFollowOnOutboxEvent(db, row),
      dbUpsertFollowOnOutboxEventWithRecipients: (event, recipients) async {
        await dbUpsertPostFollowOnOutboxEventWithRecipients(
          db,
          event,
          recipients,
        );
        await afterInitialQueueWrite?.call();
      },
      dbLoadFollowOnOutboxEvent: (eventId) =>
          dbLoadPostFollowOnOutboxEvent(db, eventId),
      dbDeleteFollowOnOutboxEvent: (eventId) =>
          dbDeletePostFollowOnOutboxEvent(db, eventId),
      dbLoadRetryableFollowOnOutboxEvents: () =>
          dbLoadRetryablePostFollowOnOutboxEvents(db),
      dbUpsertFollowOnOutboxRecipientDelivery: (row) async {
        await dbUpsertPostFollowOnOutboxRecipientDelivery(db, row);
        if (row['recipient_peer_id'] == 'bob' &&
            row['delivery_status'] == 'pending') {
          await afterInitialQueueWrite?.call();
        }
      },
      dbLoadFollowOnOutboxRecipientDeliveries: (eventId) =>
          dbLoadPostFollowOnOutboxRecipientDeliveries(db, eventId),
      dbLoadRetryableFollowOnOutboxRecipientDeliveries: (eventIds) =>
          dbLoadRetryablePostFollowOnOutboxRecipientDeliveries(db, eventIds),
    );
  }

  test('initial retraction snapshot survives retry during queueing', () async {
    final firstWrite = Completer<void>();
    final finishQueueing = Completer<void>();
    addTearDown(() {
      if (!finishQueueing.isCompleted) finishQueueing.complete();
    });
    final queueRepository = buildRepository(
      afterInitialQueueWrite: () async {
        firstWrite.complete();
        await finishQueueing.future;
      },
    );
    final retryRepository = buildRepository();
    addTearDown(queueRepository.dispose);
    addTearDown(retryRepository.dispose);
    final network = FakeP2PNetwork()..inboxDisabled = true;
    final service = _RetractP2PService(
      network,
      acknowledgedRecipients: {'bob'},
    );
    addTearDown(service.dispose);
    final now = DateTime.utc(2026, 3, 15, 12);
    final envelope = PostRetractEnvelope(
      eventId: 'evt-queue-interleaving',
      postId: 'thought-queue-interleaving',
      createdAt: now,
      postCreatedAt: now.subtract(const Duration(hours: 2)),
    );
    final queueing = queuePostFollowOn(
      postRepo: queueRepository,
      eventId: envelope.eventId,
      eventType: PostRetractEnvelope.type,
      postId: envelope.postId,
      senderPeerId: 'me',
      envelope: envelope.toJson(),
      createdAt: now.toIso8601String(),
      recipientPeerIds: ['bob', 'cara'],
    );
    await firstWrite.future.timeout(const Duration(seconds: 5));
    final initiallyVisible = await retryRepository
        .loadFollowOnOutboxRecipientDeliveries(envelope.eventId);
    expect(initiallyVisible.map((row) => row.recipientPeerId), contains('bob'));
    try {
      expect(
        await retryPendingPostFollowOns(
          postRepo: retryRepository,
          p2pService: service,
          nowProvider: () => now,
        ),
        1,
      );
    } finally {
      finishQueueing.complete();
    }
    final deliveries = await queueing;
    await deliverQueuedPostFollowOn(
      postRepo: queueRepository,
      p2pService: service,
      eventId: envelope.eventId,
      envelope: envelope.toJson(),
      deliveries: deliveries,
    );

    await db.close();
    db = await openDatabase('${tempDir.path}/posts.db');
    final reopened = buildRepository();
    addTearDown(reopened.dispose);
    final jobs = await reopened.loadRetryableFollowOnOutboxJobs();
    expect(
      jobs,
      hasLength(1),
      reason:
          'later recipient must stay durable; initial visible snapshot had ${initiallyVisible.length} recipients',
    );
    expect(jobs.single.recipientDeliveries.single.recipientPeerId, 'cara');
    expect(jobs.single.recipientDeliveries.single.deliveryStatus, 'failed');
    expect(
      initiallyVisible.map((row) => row.recipientPeerId),
      unorderedEquals(['bob', 'cara']),
    );

    network.inboxDisabled = false;
    expect(
      await retryPendingPostFollowOns(
        postRepo: reopened,
        p2pService: service,
        nowProvider: () => now.add(const Duration(minutes: 1)),
      ),
      1,
    );
    expect(network.inboxCount('cara'), 1);
    expect(await db.query('post_follow_on_outbox_events'), isEmpty);
    expect(
      await db.query('post_follow_on_outbox_recipient_deliveries'),
      isEmpty,
    );
  });

  test(
    'failed initial recipient write rolls back the entire snapshot',
    () async {
      final repository = buildRepository();
      addTearDown(repository.dispose);
      await db.execute('''
      CREATE TRIGGER reject_later_recipient
      BEFORE INSERT ON post_follow_on_outbox_recipient_deliveries
      WHEN NEW.recipient_peer_id = 'cara'
      BEGIN SELECT RAISE(ABORT, 'fixture recipient write failed'); END
    ''');

      await expectLater(
        queuePostFollowOn(
          postRepo: repository,
          eventId: 'evt-snapshot-rollback',
          eventType: 'post_retract',
          postId: 'thought-snapshot-rollback',
          senderPeerId: 'me',
          envelope: '{"type":"post_retract"}',
          createdAt: '2026-03-15T12:00:00.000Z',
          recipientPeerIds: ['bob', 'cara'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('post_follow_on_outbox_events'), isEmpty);
      expect(
        await db.query('post_follow_on_outbox_recipient_deliveries'),
        isEmpty,
      );
      await db.close();
      db = await openDatabase('${tempDir.path}/posts.db');
      expect(await db.query('post_follow_on_outbox_events'), isEmpty);
      expect(
        await db.query('post_follow_on_outbox_recipient_deliveries'),
        isEmpty,
      );
    },
  );

  for (final expireBeforeRetry in [false, true]) {
    test(
      'local retraction survives SQLite reopen and ${expireBeforeRetry ? 'expires at the original deadline' : 'retries after inbox recovery'}',
      () async {
        var repository = buildRepository();
        addTearDown(() => repository.dispose());
        final network = FakeP2PNetwork()..inboxDisabled = true;
        final service = _RetractP2PService(network);
        addTearDown(service.dispose);
        final createdAt = DateTime.utc(2026, 3, 15, 10);
        final now = createdAt.add(const Duration(hours: 2));
        final createdIso = createdAt.toIso8601String();
        await repository.savePost(
          PostModel(
            id: 'thought-1',
            eventId: 'evt-thought-1',
            senderPeerId: 'me',
            authorPeerId: 'me',
            authorUsername: 'Me',
            text: 'Retract this thought',
            audience: PostAudience.allFriends(),
            createdAt: createdIso,
            visibleAt: createdIso,
            expiresAt: ThoughtLifetime.expiresAt(createdAt).toIso8601String(),
            isIncoming: false,
            deliveryStatus: 'delivered',
          ),
        );
        await repository.saveRecipientDelivery(
          PostRecipientDelivery(
            postId: 'thought-1',
            recipientPeerId: 'bob',
            deliveryStatus: 'delivered',
            deliveryPath: 'direct',
            lastAttemptAt: createdIso,
            createdAt: createdIso,
            updatedAt: createdIso,
          ),
        );
        final mediaFile = File(
          '${tempDir.path}/post_media/thought-1/photo.jpg',
        );
        await mediaFile.parent.create(recursive: true);
        await mediaFile.writeAsBytes([1, 2, 3]);
        await db.insert('post_media_attachments', {
          'media_id': 'media-1',
          'post_id': 'thought-1',
          'blob_id': 'blob-1',
          'kind': 'image',
          'mime': 'image/jpeg',
          'local_path': mediaFile.path,
          'created_at': createdIso,
        });
        await queuePostFollowOn(
          postRepo: repository,
          eventId: 'evt-legacy',
          eventType: 'post_comment',
          postId: 'thought-1',
          senderPeerId: 'me',
          envelope: '{"type":"post_comment"}',
          createdAt: createdIso,
          recipientPeerIds: ['bob'],
        );

        final retraction = await retractThought(
          postRepo: repository,
          p2pService: service,
          mediaFileManager: MediaFileManager(),
          postId: 'thought-1',
          senderPeerId: 'me',
          nowProvider: () => now,
        );
        final firstDelivery = await retraction.delivery;

        expect(retraction.result, RetractThoughtResult.deleted);
        expect(await repository.getPost('thought-1'), isNull);
        expect(await mediaFile.exists(), isFalse);
        expect(await db.query('post_media_attachments'), isEmpty);
        expect(await db.query('post_recipients'), isEmpty);
        final events = await db.query('post_follow_on_outbox_events');
        expect(
          events,
          hasLength(1),
          reason: 'the cascade must retain the queued retraction event',
        );
        expect(events.single['event_type'], 'post_retract');
        final eventId = events.single['event_id']! as String;
        expect(await repository.getFollowOnOutboxEvent('evt-legacy'), isNull);
        expect(
          await repository.loadFollowOnOutboxRecipientDeliveries('evt-legacy'),
          isEmpty,
        );
        expect(firstDelivery!.settlement, PostFollowOnSettlement.notSettled);
        expect(network.storeInInboxCallCount, 1);
        expect(service.directAttempts, 1);

        repository.dispose();
        await db.close();
        db = await openDatabase('${tempDir.path}/posts.db');
        repository = buildRepository();
        final jobs = await repository.loadRetryableFollowOnOutboxJobs();
        expect(jobs, hasLength(1));
        expect(jobs.single.event.eventId, eventId);
        expect(jobs.single.recipientDeliveries.single.recipientPeerId, 'bob');
        expect(jobs.single.recipientDeliveries.single.deliveryStatus, 'failed');
        expect(
          jobs.single.recipientDeliveries.single.lastError,
          'direct_send_unacknowledged',
        );

        network.inboxDisabled = false;
        final retryAt = expireBeforeRetry
            ? ThoughtLifetime.expiresAt(
                createdAt,
              ).add(const Duration(minutes: 1))
            : now.add(const Duration(minutes: 5));
        final retried = await retryPendingPostFollowOns(
          postRepo: repository,
          p2pService: service,
          nowProvider: () => retryAt,
        );
        expect(retried, expireBeforeRetry ? 0 : 1);
        expect(service.directAttempts, expireBeforeRetry ? 1 : 2);
        expect(network.storeInInboxCallCount, expireBeforeRetry ? 1 : 2);
        expect(network.inboxCount('bob'), expireBeforeRetry ? 0 : 1);
        final rows = await repository.loadFollowOnOutboxRecipientDeliveries(
          eventId,
        );
        expect(
          rows,
          isEmpty,
          reason: 'terminal retraction recipients must be retired',
        );
        expect(await repository.getFollowOnOutboxEvent(eventId), isNull);
        expect(await repository.loadRetryableFollowOnOutboxJobs(), isEmpty);
        expect(
          await retryPendingPostFollowOns(
            postRepo: repository,
            p2pService: service,
            nowProvider: () => retryAt.add(const Duration(minutes: 5)),
          ),
          0,
        );
        expect(service.directAttempts, expireBeforeRetry ? 1 : 2);
        expect(network.storeInInboxCallCount, expireBeforeRetry ? 1 : 2);

        // An earlier delivery may finish after retry or expiry retires the job.
        await repository.saveFollowOnOutboxRecipientDelivery(
          jobs.single.recipientDeliveries.single.copyWith(
            deliveryStatus: 'delivered',
            deliveryPath: 'direct',
          ),
        );
        repository.dispose();
        await db.close();
        db = await openDatabase('${tempDir.path}/posts.db');
        repository = buildRepository();
        expect(await db.query('post_follow_on_outbox_events'), isEmpty);
        expect(
          await db.query('post_follow_on_outbox_recipient_deliveries'),
          isEmpty,
        );
      },
    );
  }

  test('an expired retraction row is never loaded for retry again', () async {
    final repository = buildRepository();
    addTearDown(repository.dispose);
    const event = PostFollowOnOutboxEvent(
      eventId: 'evt-retract-1',
      eventType: 'post_retract',
      postId: 'post-1',
      senderPeerId: 'peer-bob',
      rawEnvelope: '{"type":"post_retract"}',
      createdAt: '2026-03-16T10:00:00.000Z',
    );
    await repository.saveFollowOnOutboxEvent(event);
    const failed = PostFollowOnOutboxRecipientDelivery(
      eventId: 'evt-retract-1',
      recipientPeerId: 'peer-cara',
      deliveryStatus: 'failed',
      deliveryPath: 'inbox',
      createdAt: '2026-03-16T10:00:00.000Z',
      updatedAt: '2026-03-16T10:00:00.000Z',
    );
    await repository.saveFollowOnOutboxRecipientDelivery(failed);
    expect(await repository.loadRetryableFollowOnOutboxJobs(), hasLength(1));

    await repository.saveFollowOnOutboxRecipientDelivery(
      failed.copyWith(
        deliveryStatus: 'expired',
        updatedAt: '2026-03-17T10:01:00.000Z',
      ),
    );

    expect(await repository.loadRetryableFollowOnOutboxJobs(), isEmpty);
    final rows = await repository.loadFollowOnOutboxRecipientDeliveries(
      'evt-retract-1',
    );
    expect(rows.map((row) => row.deliveryStatus), ['expired']);
  });

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
      final retryableJobs = await secondRepository
          .loadRetryableFollowOnOutboxJobs();

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

class _PathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _PathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _RetractP2PService extends FakeP2PService {
  _RetractP2PService(
    FakeP2PNetwork network, {
    this.acknowledgedRecipients = const {},
  }) : super(peerId: 'me', network: network);

  final Set<String> acknowledgedRecipients;
  int directAttempts = 0;

  @override
  bool isConnectedToPeer(String peerId) => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    directAttempts++;
    return SendMessageResult(
      sent: true,
      acked: acknowledgedRecipients.contains(targetPeerId),
    );
  }
}
