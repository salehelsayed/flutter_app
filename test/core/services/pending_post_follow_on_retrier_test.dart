import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';

import '../../shared/fakes/in_memory_post_repository.dart';
import 'fake_p2p_service.dart';

void main() {
  late FakeP2PService p2pService;
  late InMemoryPostRepository postRepo;
  late PendingPostFollowOnRetrier retrier;

  setUp(() {
    p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'peer-self',
        circuitAddresses: <String>['/p2p-circuit/addr1'],
      ),
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

  test('start while already online retries queued pass follow-ons', () async {
    await postRepo.saveFollowOnOutboxEvent(
      const PostFollowOnOutboxEvent(
        eventId: 'evt-pass-1',
        eventType: 'post_pass_along',
        postId: 'post-1',
        senderPeerId: 'peer-self',
        rawEnvelope: '{"type":"post_pass"}',
        createdAt: '2026-03-15T11:25:00.000Z',
      ),
    );
    await postRepo.saveFollowOnOutboxRecipientDelivery(
      const PostFollowOnOutboxRecipientDelivery(
        eventId: 'evt-pass-1',
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
      'evt-pass-1',
    );
    expect(deliveries, hasLength(1));
    expect(deliveries.single.deliveryStatus, 'delivered');
    expect(await postRepo.loadRetryableFollowOnOutboxJobs(), isEmpty);
    expect(p2pService.sendMessageWithReplyCallCount, 1);
  });
}
