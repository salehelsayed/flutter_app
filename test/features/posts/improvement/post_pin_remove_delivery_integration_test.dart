import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/posts/application/pin_post_use_case.dart';
import 'package:flutter_app/features/posts/application/post_pin_listener.dart';
import 'package:flutter_app/features/posts/application/remove_pin_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../phase5/support/post_pin_fixtures.dart';

import '../support/legacy_post_state.dart';

void main() {
  late FakeP2PNetwork network;
  late _PostPinUser author;
  late _PostPinUser recipient;

  setUp(() {
    network = FakeP2PNetwork();
    author = _PostPinUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
    );
    recipient = _PostPinUser.create(
      peerId: 'peer-cara',
      username: 'Cara',
      network: network,
    );
    recipient.addContact(author);
    recipient.start();
  });

  tearDown(() {
    author.dispose();
    recipient.dispose();
  });

  test(
    'disabled legacy feature produces no delivery or retry: author pin and remove travel through router and listener to update recipient pinned state',
    () async {
      await _seedSharedPost(author: author, recipient: recipient);
      final before = <Map<String, Object?>>[
        await snapshotLegacyPostState(author.postRepo),
        await snapshotLegacyPostState(recipient.postRepo),
      ];
      final rejection = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      final removal = await removePin(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(removal.$1, RemovePinResult.sendFailed);
      expect(removal.$2, isNull);
      final after = <Map<String, Object?>>[
        await snapshotLegacyPostState(author.postRepo),
        await snapshotLegacyPostState(recipient.postRepo),
      ];
      expect(after, before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'disabled legacy feature produces no delivery or retry: full remove delivery failure leaves a queued sender remove and retryable outbox state',
    () async {
      await _seedSharedPost(author: author, recipient: recipient);
      final before = <Map<String, Object?>>[
        await snapshotLegacyPostState(author.postRepo),
        await snapshotLegacyPostState(recipient.postRepo),
      ];
      final rejection = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      final removal = await removePin(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(removal.$1, RemovePinResult.sendFailed);
      expect(removal.$2, isNull);
      final after = <Map<String, Object?>>[
        await snapshotLegacyPostState(author.postRepo),
        await snapshotLegacyPostState(recipient.postRepo),
      ];
      expect(after, before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );
}

Future<void> _seedSharedPost({
  required _PostPinUser author,
  required _PostPinUser recipient,
}) async {
  await author.postRepo.savePost(
    postPinBasePost(
      authorPeerId: author.peerId,
      authorUsername: author.username,
      keepAvailable: false,
    ),
  );
  await author.postRepo.saveRecipientDelivery(
    PostRecipientDelivery(
      postId: 'post-1',
      recipientPeerId: recipient.peerId,
      deliveryStatus: 'delivered',
      lastAttemptAt: '2026-03-15T10:16:00.000Z',
      deliveryPath: 'direct',
      createdAt: '2026-03-15T10:16:00.000Z',
      updatedAt: '2026-03-15T10:16:00.000Z',
    ),
  );
  await recipient.postRepo.savePost(
    postPinBasePost(
      authorPeerId: author.peerId,
      authorUsername: author.username,
      keepAvailable: false,
    ),
  );
}

class _PostPinUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;
  final IncomingMessageRouter router;
  final PostPinListener pinListener;

  _PostPinUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.contactRepo,
    required this.postRepo,
    required this.router,
    required this.pinListener,
  });

  factory _PostPinUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
  }) {
    final p2pService = FakeP2PService(peerId: peerId, network: network);
    final contactRepo = InMemoryContactRepository();
    final postRepo = InMemoryPostRepository();
    final router = IncomingMessageRouter(p2pService: p2pService);
    final pinListener = PostPinListener(
      postPinUpdateStream: router.postPinUpdateStream,
      postPinRemoveStream: router.postPinRemoveStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
    );
    return _PostPinUser._(
      peerId: peerId,
      username: username,
      p2pService: p2pService,
      contactRepo: contactRepo,
      postRepo: postRepo,
      router: router,
      pinListener: pinListener,
    );
  }

  void addContact(_PostPinUser other) {
    contactRepo.addTestContact(postPinContact(other.peerId, other.username));
  }

  void start() {
    router.start();
    pinListener.start();
  }

  void dispose() {
    pinListener.dispose();
    router.dispose();
    postRepo.dispose();
    p2pService.dispose();
  }
}
