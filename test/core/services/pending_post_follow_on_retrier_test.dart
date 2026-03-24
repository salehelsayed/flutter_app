import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../shared/fakes/in_memory_post_repository.dart';
import 'fake_p2p_service.dart';

void main() {
  late FakeP2PService p2pService;
  late InMemoryPostRepository postRepo;
  late PendingPostFollowOnRetrier retrier;
  const discoverablePeer = DiscoveredPeer(
    id: 'peer-bob',
    addresses: <String>['/dns4/example.invalid/tcp/443'],
  );

  setUp(() {
    p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'peer-self',
        circuitAddresses: <String>['/p2p-circuit/addr1'],
      ),
      discoverPeerResult: discoverablePeer,
    );
    postRepo = InMemoryPostRepository();
    retrier = PendingPostFollowOnRetrier(
      p2pService: p2pService,
      postRepo: postRepo,
      retryDebounce: Duration.zero,
      periodicRetryInterval: const Duration(hours: 1),
    );
  });

  tearDown(() {
    retrier.dispose();
    p2pService.dispose();
    postRepo.dispose();
  });

  test('start while already online retries queued pin follow-ons', () async {
    await postRepo.saveFollowOnOutboxEvent(
      const PostFollowOnOutboxEvent(
        eventId: 'evt-pin-remove-1',
        eventType: 'post_pin_remove',
        postId: 'post-1',
        senderPeerId: 'peer-self',
        rawEnvelope: '{"type":"post_pin_remove"}',
        createdAt: '2026-03-15T11:25:00.000Z',
      ),
    );
    await postRepo.saveFollowOnOutboxRecipientDelivery(
      const PostFollowOnOutboxRecipientDelivery(
        eventId: 'evt-pin-remove-1',
        recipientPeerId: 'peer-bob',
        deliveryStatus: 'failed',
        deliveryPath: 'failed',
        lastError: 'inbox_store_failed',
        lastAttemptAt: '2026-03-15T11:25:10.000Z',
        createdAt: '2026-03-15T11:25:00.000Z',
        updatedAt: '2026-03-15T11:25:10.000Z',
      ),
    );

    retrier.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final deliveries = await postRepo.loadFollowOnOutboxRecipientDeliveries(
      'evt-pin-remove-1',
    );
    expect(deliveries, hasLength(1));
    expect(deliveries.single.deliveryStatus, 'delivered');
    expect(await postRepo.loadRetryableFollowOnOutboxJobs(), isEmpty);
    expect(p2pService.sendMessageWithReplyCallCount, 1);
  });

  test(
    'start while already online ignores repost delivery state because repost no longer uses follow-on outbox jobs',
    () async {
      await postRepo.savePost(
        const PostModel(
          id: 'post-1',
          eventId: 'evt-post-1',
          senderPeerId: 'peer-bob',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
          text: 'Need a ladder',
          audience: PostAudience(kind: PostAudienceKind.allFriends),
          createdAt: '2026-03-15T10:00:00.000Z',
          visibleAt: '2026-03-15T10:00:00.000Z',
          expiresAt: '2026-03-18T10:00:00.000Z',
          isIncoming: true,
        ),
      );
      await postRepo.savePostPass(
        const PostPassModel(
          passId: 'pass-1',
          eventId: 'evt-pass-1',
          postId: 'post-1',
          senderPeerId: 'peer-self',
          passerPeerId: 'peer-self',
          passerUsername: 'Alice',
          passedAt: '2026-03-15T11:25:00.000Z',
          createdAt: '2026-03-15T11:25:00.000Z',
          isIncoming: false,
          deliveryStatus: 'failed',
        ),
      );
      await postRepo.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-1',
          deliveryOwnerKind: postRecipientDeliveryOwnerKindPass,
          deliveryOwnerId: 'pass-1',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'failed',
          deliveryPath: 'failed',
          lastError: 'inbox_store_failed',
          lastAttemptAt: '2026-03-15T11:25:10.000Z',
          createdAt: '2026-03-15T11:25:00.000Z',
          updatedAt: '2026-03-15T11:25:10.000Z',
        ),
      );

      retrier.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final deliveries = await postRepo.getPostPassRecipientDeliveries(
        'pass-1',
      );
      expect(deliveries, hasLength(1));
      expect(deliveries.single.deliveryStatus, 'failed');
      expect(await postRepo.loadRetryableOutgoingPostPasses(), hasLength(1));
      expect(await postRepo.loadRetryableFollowOnOutboxJobs(), isEmpty);
      expect(p2pService.sendMessageWithReplyCallCount, 0);
    },
  );
}
