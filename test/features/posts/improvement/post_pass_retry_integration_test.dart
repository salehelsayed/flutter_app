import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late FakeP2PService service;
  late InMemoryPostRepository posts;
  late InMemoryContactRepository contacts;
  late FakeBridge bridge;

  setUp(() {
    network = FakeP2PNetwork();
    service = FakeP2PService(peerId: 'sender', network: network);
    posts = InMemoryPostRepository();
    contacts = InMemoryContactRepository();
    bridge = FakeBridge();
  });
  tearDown(() {
    service.dispose();
    posts.dispose();
  });

  for (final recipients in <List<String>>[
    ['friend'],
    ['friend', 'other-friend'],
  ]) {
    test(
      'pass to ${recipients.length} friends is rejected without creating delivery or projection state',
      () async {
        final (result, pass) = await passPostAlong(
          p2pService: service,
          postRepo: posts,
          contactRepo: contacts,
          postId: 'thought',
          senderPeerId: 'sender',
          senderUsername: 'Sender',
          recipientPeerIds: recipients,
          bridge: bridge,
        );
        expect(result, PassPostAlongResult.notAllowed);
        expect(pass, isNull);
        expect(await posts.loadPostPasses('thought'), isEmpty);
        expect(await posts.loadRetryableOutgoingPostPasses(), isEmpty);
        expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
        expect(await posts.loadPostPassCount('thought'), 0);
        expect(bridge.commandLog, isEmpty);
        for (final recipient in recipients) {
          expect(network.inboxCount(recipient), 0);
        }
      },
    );
  }

  test('an offline author receives no pass through the inbox', () async {
    final (result, pass) = await passPostAlong(
      p2pService: service,
      postRepo: posts,
      contactRepo: contacts,
      postId: 'thought',
      senderPeerId: 'sender',
      senderUsername: 'Sender',
      recipientPeerIds: const ['offline-author'],
      bridge: bridge,
    );
    expect(result, PassPostAlongResult.notAllowed);
    expect(pass, isNull);
    expect(network.inboxCount('offline-author'), 0);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'the delivery retrier never replays a durable legacy encrypted pass',
    () async {
      final now = DateTime.now().toUtc();
      final createdAt = now.toIso8601String();
      await posts.savePost(
        PostModel(
          id: 'thought',
          eventId: 'event',
          senderPeerId: 'author',
          authorPeerId: 'author',
          authorUsername: 'Author',
          text: 'thought',
          audience: PostAudience.allFriends(),
          createdAt: createdAt,
          visibleAt: createdAt,
          expiresAt: now.add(const Duration(hours: 24)).toIso8601String(),
          deliveryStatus: 'sent',
        ),
      );
      await posts.savePostPass(
        PostPassModel(
          passId: 'legacy-pass',
          postId: 'thought',
          eventId: 'pass-event',
          senderPeerId: 'sender',
          passerPeerId: 'sender',
          passerUsername: 'Sender',
          isIncoming: false,
          passedAt: createdAt,
          createdAt: createdAt,
          deliveryStatus: 'failed',
          innerPayloadJson: '{"post_id":"thought","private":"legacy"}',
        ),
      );
      await posts.saveRecipientDelivery(
        PostRecipientDelivery(
          postId: 'thought',
          recipientPeerId: 'friend',
          deliveryStatus: 'failed',
          lastAttemptAt: createdAt,
          deliveryPath: 'failed',
          createdAt: createdAt,
          updatedAt: createdAt,
          deliveryOwnerKind: postRecipientDeliveryOwnerKindPass,
          deliveryOwnerId: 'legacy-pass',
        ),
      );
      expect(
        await retryPendingPostDeliveries(
          postRepo: posts,
          contactRepo: contacts,
          p2pService: service,
          bridge: bridge,
        ),
        0,
      );
      expect(
        (await posts.loadPostPasses('thought')).single.deliveryStatus,
        'failed',
      );
      expect(bridge.commandLog, isEmpty);
      expect(network.inboxCount('friend'), 0);
    },
  );
}
