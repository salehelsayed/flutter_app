import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late FakeP2PService aliceService;
  late FakeP2PService bobService;
  late FakeP2PService caraService;
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;

  setUp(() {
    network = FakeP2PNetwork();
    aliceService = FakeP2PService(peerId: 'peer-alice', network: network);
    bobService = FakeP2PService(peerId: 'peer-bob', network: network);
    caraService = FakeP2PService(peerId: 'peer-cara', network: network);
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();

    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-cara', 'Cara'));
  });

  tearDown(() {
    posts.dispose();
    aliceService.dispose();
    bobService.dispose();
    caraService.dispose();
  });

  test(
    'passes an eligible direct post along with a renderable original snapshot',
    () async {
      await posts.savePost(_directPost());

      final receivedByCara = caraService.messageStream.first;

      final (result, pass) = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);

      final message = await receivedByCara.timeout(const Duration(seconds: 1));
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final payload = json['payload'] as Map<String, dynamic>;
      final snapshot = payload['original_snapshot'] as Map<String, dynamic>;

      expect(json['type'], 'post_pass');
      expect(payload['post_id'], 'post-1');
      expect(payload['passer_peer_id'], 'peer-alice');
      expect(snapshot['post_id'], 'post-1');
      expect(snapshot['author_peer_id'], 'peer-bob');
      expect(snapshot['text'], 'Lost dog near Neckar bridge.');
      expect(snapshot['audience'], <String, dynamic>{
        'kind': 'people_nearby',
        'radius_m': 2000,
        'scope_label': 'Shared nearby',
      });
    },
  );

  test('blocks pass-along for pick-people posts', () async {
    await posts.savePost(
      _directPost(
        audience: PostAudience.pickPeople(const <String>['peer-alice']),
      ),
    );

    final (result, pass) = await passPostAlong(
      p2pService: aliceService,
      postRepo: posts,
      contactRepo: contacts,
      postId: 'post-1',
      senderPeerId: 'peer-alice',
      senderUsername: 'Alice',
      recipientPeerIds: const <String>['peer-cara'],
    );

    expect(result, PassPostAlongResult.pickPeopleNotAllowed);
    expect(pass, isNull);
  });

  test('enforces the explicit one-hop rule for already-passed posts', () async {
    await posts.savePost(_directPost(senderPeerId: 'peer-james'));

    final (result, pass) = await passPostAlong(
      p2pService: aliceService,
      postRepo: posts,
      contactRepo: contacts,
      postId: 'post-1',
      senderPeerId: 'peer-alice',
      senderUsername: 'Alice',
      recipientPeerIds: const <String>['peer-cara'],
    );

    expect(result, PassPostAlongResult.oneHopLimitReached);
    expect(pass, isNull);
  });
}

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

PostModel _directPost({
  PostAudience? audience,
  String senderPeerId = 'peer-bob',
}) {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: senderPeerId,
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: 'Lost dog near Neckar bridge.',
    audience: audience ?? PostAudience.peopleNearby(radiusM: 2000),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}
