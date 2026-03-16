import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/test_user.dart';

ContactModel _contact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
  );
}

class _StoppedFakeP2PService extends FakeP2PService {
  _StoppedFakeP2PService({required super.peerId, required super.network});

  @override
  NodeState get currentState => NodeState(isStarted: false, peerId: peerId);
}

void main() {
  late FakeP2PNetwork network;
  late FakeP2PService aliceService;
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;

  setUp(() {
    network = FakeP2PNetwork();
    aliceService = FakeP2PService(peerId: 'peer-alice', network: network);
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'sendPost returns invalidPost before nodeNotRunning for empty payloads',
    () async {
      final stoppedService = _StoppedFakeP2PService(
        peerId: 'peer-stopped',
        network: network,
      );

      final (result, post) = await sendPost(
        p2pService: stoppedService,
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: '   ',
        audience: PostAudience.allFriends(),
      );

      expect(result, SendPostResult.invalidPost);
      expect(post, isNull);
      expect(await posts.loadFeed(), isEmpty);
    },
  );

  test(
    'sendPost remains a synchronous facade that returns terminal failure',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      network.deliveryFails = true;
      network.inboxDisabled = true;

      final (result, post) = await sendPost(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'Hello Bob',
        audience: PostAudience.allFriends(),
      );

      expect(result, SendPostResult.sendFailed);
      expect(post, isNotNull);
      expect(post!.deliveryStatus, 'failed');

      final deliveries = await posts.getRecipientDeliveries(post.id);
      expect(deliveries, hasLength(1));
      expect(deliveries.single.deliveryStatus, 'failed');
    },
  );

  test('sendPost does not write conversation messages', () async {
    final bob = TestUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
      withReactions: true,
    );
    addTearDown(bob.dispose);
    bob.start();
    contacts.addTestContact(_contact('peer-bob', 'Bob'));

    final (result, post) = await sendPost(
      p2pService: aliceService,
      postRepo: posts,
      contactRepo: contacts,
      senderPeerId: 'peer-alice',
      senderUsername: 'Alice',
      text: 'Posts stay out of chat',
      audience: PostAudience.allFriends(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(result, SendPostResult.success);
    expect(post, isNotNull);
    expect(bob.messageRepo.count, 0);
  });
}
