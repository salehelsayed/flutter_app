import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

ContactModel _contact(
  String peerId,
  String username, {
  bool blocked = false,
  bool archived = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    isBlocked: blocked,
    isArchived: archived,
  );
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

  test('all friends excludes blocked and archived contacts', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-cara', 'Cara', blocked: true));
    contacts.addTestContact(_contact('peer-dan', 'Dan', archived: true));

    final (result, post) = await sendPost(
      p2pService: aliceService,
      postRepo: posts,
      contactRepo: contacts,
      senderPeerId: 'peer-alice',
      senderUsername: 'Alice',
      text: 'Hello everyone',
      audience: PostAudience.allFriends(),
    );

    expect(result, SendPostResult.success);
    final deliveries = await posts.getRecipientDeliveries(post!.id);
    expect(deliveries.map((delivery) => delivery.recipientPeerId), [
      'peer-bob',
    ]);
  });

  test(
    'persists direct and inbox recipient statuses for the same post',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      contacts.addTestContact(_contact('peer-cara', 'Cara'));

      FakeP2PService(peerId: 'peer-bob', network: network);
      // Cara is offline, so the use case should fall back to the inbox.

      final (result, post) = await sendPost(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'Status mix',
        audience: PostAudience.allFriends(),
      );

      expect(result, SendPostResult.success);
      final deliveries = await posts.getRecipientDeliveries(post!.id);
      expect(deliveries, hasLength(2));
      expect(
        deliveries.any(
          (delivery) =>
              delivery.recipientPeerId == 'peer-bob' &&
              delivery.deliveryStatus == 'delivered',
        ),
        isTrue,
      );
      expect(
        deliveries.any(
          (delivery) =>
              delivery.recipientPeerId == 'peer-cara' &&
              delivery.deliveryStatus == 'inbox',
        ),
        isTrue,
      );
      expect(network.inboxCount('peer-cara'), 1);
    },
  );

  test(
    'returns invalidPost when text-only payload becomes empty after sanitization',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));

      final (result, post) = await sendPost(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: '\u202E\u202D',
        audience: PostAudience.allFriends(),
      );

      expect(result, SendPostResult.invalidPost);
      expect(post, isNull);
    },
  );
}
