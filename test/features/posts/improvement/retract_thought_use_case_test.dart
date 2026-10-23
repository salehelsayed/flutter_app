import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/application/retract_thought_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  final createdAt = DateTime.utc(2026, 10, 23, 9);
  final now = createdAt.add(const Duration(hours: 2));
  late FakeP2PNetwork network;
  late FakeP2PService p2pService;
  late InMemoryPostRepository posts;
  late FakeMediaFileManager media;

  setUp(() {
    network = FakeP2PNetwork();
    p2pService = FakeP2PService(peerId: 'me', network: network);
    posts = InMemoryPostRepository();
    media = FakeMediaFileManager();
  });

  tearDown(() {
    posts.dispose();
    p2pService.dispose();
  });

  PostModel ownThought() => PostModel(
    id: 'thought-1',
    eventId: 'evt-thought-1',
    senderPeerId: 'me',
    authorPeerId: 'me',
    authorUsername: 'Me',
    text: 'Gone soon',
    audience: PostAudience.allFriends(),
    createdAt: createdAt.toIso8601String(),
    visibleAt: createdAt.toIso8601String(),
    expiresAt: ThoughtLifetime.expiresAt(createdAt).toIso8601String(),
    isIncoming: false,
    deliveryStatus: 'delivered',
  );

  Future<void> seedSentThought(List<String> recipients) async {
    await posts.savePost(ownThought());
    final sentAt = createdAt.add(const Duration(seconds: 5)).toIso8601String();
    for (final peerId in recipients) {
      await posts.saveRecipientDelivery(
        PostRecipientDelivery(
          postId: 'thought-1',
          recipientPeerId: peerId,
          deliveryStatus: 'delivered',
          lastAttemptAt: sentAt,
          deliveryPath: 'direct',
          createdAt: sentAt,
          updatedAt: sentAt,
        ),
      );
    }
  }

  Future<ThoughtRetraction> retract({String senderPeerId = 'me'}) {
    return retractThought(
      postRepo: posts,
      p2pService: p2pService,
      mediaFileManager: media,
      postId: 'thought-1',
      senderPeerId: senderPeerId,
      nowProvider: () => now,
    );
  }

  test(
    'deletes the thought and its media at once and queues one retraction per friend',
    () async {
      await seedSentThought(['bob', 'cara']);
      network.inboxDisabled = true;

      final retraction = await retract();

      expect(retraction.result, RetractThoughtResult.deleted);
      expect(await posts.getPost('thought-1'), isNull);
      expect(media.deletedPostIds, ['thought-1']);
      await retraction.delivery;

      final jobs = await posts.loadRetryableFollowOnOutboxJobs();
      expect(jobs, hasLength(1));
      final job = jobs.single;
      expect(job.event.eventType, 'post_retract');
      expect(job.event.postId, 'thought-1');
      expect(job.event.senderPeerId, 'me');
      expect(
        job.recipientDeliveries.map((delivery) => delivery.recipientPeerId),
        unorderedEquals(['bob', 'cara']),
      );
      final envelope = jsonDecode(job.event.rawEnvelope) as Map<String, dynamic>;
      expect(envelope['type'], 'post_retract');
      final payload = envelope['payload'] as Map<String, dynamic>;
      expect(payload['post_id'], 'thought-1');
      expect(payload['post_created_at'], '2026-10-23T09:00:00.000Z');
      expect(network.storeInInboxCallCount, 2);
    },
  );

  test('a friend who could not be reached gets the retraction on retry', () async {
    await seedSentThought(['bob']);
    network.inboxDisabled = true;
    final retraction = await retract();
    await retraction.delivery;
    expect(network.storeInInboxCallCount, 1);
    expect(network.inboxCount('bob'), 0);

    network.inboxDisabled = false;
    final retried = await retryPendingPostFollowOns(
      postRepo: posts,
      p2pService: p2pService,
      nowProvider: () => now.add(const Duration(minutes: 5)),
    );

    expect(retried, 1);
    expect(network.storeInInboxCallCount, 2);
    expect(network.inboxCount('bob'), 1);
    expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
  });

  test('retries stop once the thought would have expired', () async {
    await seedSentThought(['bob']);
    network.inboxDisabled = true;
    final retraction = await retract();
    await retraction.delivery;
    final eventId = (await posts.loadRetryableFollowOnOutboxJobs())
        .single
        .event
        .eventId;

    network.inboxDisabled = false;
    final retried = await retryPendingPostFollowOns(
      postRepo: posts,
      p2pService: p2pService,
      nowProvider: () =>
          ThoughtLifetime.expiresAt(createdAt).add(const Duration(minutes: 1)),
    );

    expect(retried, 0);
    expect(network.storeInInboxCallCount, 1);
    expect(network.inboxCount('bob'), 0);
    expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    final rows = await posts.loadFollowOnOutboxRecipientDeliveries(eventId);
    expect(rows.map((row) => row.deliveryStatus), ['expired']);
  });

  test('a thought nobody received is deleted without queuing anything', () async {
    await posts.savePost(ownThought());

    final retraction = await retract();

    expect(retraction.result, RetractThoughtResult.deleted);
    expect(retraction.delivery, isNull);
    expect(await posts.getPost('thought-1'), isNull);
    expect(media.deletedPostIds, ['thought-1']);
    expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    expect(network.storeInInboxCallCount, 0);
  });

  test('only the author can retract a thought', () async {
    await seedSentThought(['bob']);

    final retraction = await retract(senderPeerId: 'bob');

    expect(retraction.result, RetractThoughtResult.notAuthor);
    expect(retraction.delivery, isNull);
    expect(await posts.getPost('thought-1'), isNotNull);
    expect(media.deletedPostIds, isEmpty);
    expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    expect(network.storeInInboxCallCount, 0);
  });

  test('an unknown thought id is reported and changes nothing', () async {
    final retraction = await retract();

    expect(retraction.result, RetractThoughtResult.postNotFound);
    expect(media.deletedPostIds, isEmpty);
    expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
  });
}
