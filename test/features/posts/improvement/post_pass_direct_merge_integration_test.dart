import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late _MergeUser author;
  late _MergeUser passer;
  late _MergeUser receiver;

  setUp(() {
    network = FakeP2PNetwork();
    author = _MergeUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
    );
    passer = _MergeUser.create(
      peerId: 'peer-alice',
      username: 'Alice',
      network: network,
    );
    receiver = _MergeUser.create(
      peerId: 'peer-cara',
      username: 'Cara',
      network: network,
    );

    passer.addContact(author);
    passer.addContact(receiver);
    receiver.addContact(author);
    receiver.addContact(passer);
    receiver.start();
  });

  tearDown(() {
    author.dispose();
    passer.dispose();
    receiver.dispose();
  });

  test(
    'receiver keeps one card when a reposted copy is later replaced by the direct author copy',
    () async {
      const sharedPost = PostModel(
        id: 'post-1',
        eventId: 'evt-post-1',
        senderPeerId: 'peer-bob',
        authorPeerId: 'peer-bob',
        authorUsername: 'Bob',
        text: 'Lost dog near Neckar bridge.',
        audience: PostAudience(kind: PostAudienceKind.allFriends),
        createdAt: '2026-03-15T10:15:30.000Z',
        visibleAt: '2026-03-15T10:15:30.000Z',
        expiresAt: '2026-03-18T10:15:30.000Z',
        isIncoming: true,
      );
      await passer.postRepo.savePost(sharedPost);

      final (passResult, pass) = await passPostAlong(
        p2pService: passer.p2pService,
        postRepo: passer.postRepo,
        contactRepo: passer.contactRepo,
        postId: sharedPost.id,
        senderPeerId: passer.peerId,
        senderUsername: passer.username,
        recipientPeerIds: const <String>['peer-cara'],
        nowProvider: () => DateTime.parse('2026-03-15T11:15:00.000Z'),
      );

      expect(passResult, PassPostAlongResult.success);
      expect(pass, isNotNull);

      await _waitForCondition(
        () async =>
            (await receiver.postRepo.getPost('post-1'))?.passedByUsername ==
            'Alice',
        'receiver repost delivery',
      );

      final directEnvelope = PostCreateEnvelope.fromPost(sharedPost).toJson();
      final sendResult = await author.p2pService.sendMessageWithReply(
        receiver.peerId,
        directEnvelope,
      );
      expect(sendResult.sent, isTrue);

      await _waitForCondition(
        () async =>
            (await receiver.postRepo.getPostOrigin('post-1'))?.originKind ==
            PostOriginKind.direct,
        'receiver direct merge',
      );

      final feed = await receiver.postRepo.loadFeed();
      final mergedPost = await receiver.postRepo.getPost('post-1');
      final mergedOrigin = await receiver.postRepo.getPostOrigin('post-1');

      expect(feed, hasLength(1));
      expect(mergedPost, isNotNull);
      expect(mergedPost!.senderPeerId, 'peer-bob');
      expect(mergedPost.authorPeerId, 'peer-bob');
      expect(mergedPost.passedByUsername, 'Alice');
      expect(mergedPost.visibleAt, '2026-03-15T11:15:00.000Z');
      expect(mergedOrigin, isNotNull);
      expect(mergedOrigin!.originKind, PostOriginKind.direct);
      expect(mergedOrigin.passerUsername, 'Alice');
      expect(mergedOrigin.passCreatedAt, '2026-03-15T11:15:00.000Z');
    },
  );

  test(
    'receiver keeps one merged card when the direct author copy replays after a repost merge',
    () async {
      const sharedPost = PostModel(
        id: 'post-1',
        eventId: 'evt-post-1',
        senderPeerId: 'peer-bob',
        authorPeerId: 'peer-bob',
        authorUsername: 'Bob',
        text: 'Lost dog near Neckar bridge.',
        audience: PostAudience(kind: PostAudienceKind.allFriends),
        createdAt: '2026-03-15T10:15:30.000Z',
        visibleAt: '2026-03-15T10:15:30.000Z',
        expiresAt: '2026-03-18T10:15:30.000Z',
        isIncoming: true,
      );
      await passer.postRepo.savePost(sharedPost);

      final (passResult, pass) = await passPostAlong(
        p2pService: passer.p2pService,
        postRepo: passer.postRepo,
        contactRepo: passer.contactRepo,
        postId: sharedPost.id,
        senderPeerId: passer.peerId,
        senderUsername: passer.username,
        recipientPeerIds: const <String>['peer-cara'],
        nowProvider: () => DateTime.parse('2026-03-15T11:15:00.000Z'),
      );

      expect(passResult, PassPostAlongResult.success);
      expect(pass, isNotNull);

      await _waitForCondition(
        () async =>
            (await receiver.postRepo.getPost('post-1'))?.passedByUsername ==
            'Alice',
        'receiver repost delivery',
      );

      final directEnvelope = PostCreateEnvelope.fromPost(sharedPost).toJson();

      final firstSendResult = await author.p2pService.sendMessageWithReply(
        receiver.peerId,
        directEnvelope,
      );
      expect(firstSendResult.sent, isTrue);

      await _waitForCondition(
        () async =>
            (await receiver.postRepo.getPostOrigin('post-1'))?.originKind ==
            PostOriginKind.direct,
        'receiver direct merge',
      );

      final replaySendResult = await author.p2pService.sendMessageWithReply(
        receiver.peerId,
        directEnvelope,
      );
      expect(replaySendResult.sent, isTrue);

      await _waitForCondition(() async {
        final feed = await receiver.postRepo.loadFeed();
        final origin = await receiver.postRepo.getPostOrigin('post-1');
        return feed.length == 1 && origin?.originKind == PostOriginKind.direct;
      }, 'receiver direct replay merge');

      final feed = await receiver.postRepo.loadFeed();
      final mergedPost = await receiver.postRepo.getPost('post-1');
      final mergedOrigin = await receiver.postRepo.getPostOrigin('post-1');

      expect(feed, hasLength(1));
      expect(await receiver.postRepo.loadPostPassCount('post-1'), 1);
      expect(mergedPost, isNotNull);
      expect(mergedPost!.senderPeerId, 'peer-bob');
      expect(mergedPost.authorPeerId, 'peer-bob');
      expect(mergedPost.passedByUsername, 'Alice');
      expect(mergedPost.visibleAt, '2026-03-15T11:15:00.000Z');
      expect(mergedOrigin, isNotNull);
      expect(mergedOrigin!.originKind, PostOriginKind.direct);
      expect(mergedOrigin.passerUsername, 'Alice');
      expect(mergedOrigin.passCreatedAt, '2026-03-15T11:15:00.000Z');
    },
  );
}

Future<void> _waitForCondition(
  Future<bool> Function() condition,
  String description,
) async {
  if (await condition()) {
    return;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (await condition()) {
      return;
    }
  }

  throw StateError('Timed out waiting for $description');
}

class _MergeUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;
  final IncomingMessageRouter router;
  final PostListener postListener;
  final PostPassListener passListener;

  _MergeUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.contactRepo,
    required this.postRepo,
    required this.router,
    required this.postListener,
    required this.passListener,
  });

  factory _MergeUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
  }) {
    final p2pService = FakeP2PService(peerId: peerId, network: network);
    final contactRepo = InMemoryContactRepository();
    final postRepo = InMemoryPostRepository();
    final router = IncomingMessageRouter(p2pService: p2pService);
    final postListener = PostListener(
      postCreateStream: router.postCreateStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
    );
    final passListener = PostPassListener(
      postPassStream: router.postPassStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
    );
    return _MergeUser._(
      peerId: peerId,
      username: username,
      p2pService: p2pService,
      contactRepo: contactRepo,
      postRepo: postRepo,
      router: router,
      postListener: postListener,
      passListener: passListener,
    );
  }

  void addContact(_MergeUser other) {
    contactRepo.addTestContact(_contact(other.peerId, other.username));
  }

  void start() {
    router.start();
    postListener.start();
    passListener.start();
  }

  void dispose() {
    passListener.dispose();
    postListener.dispose();
    router.dispose();
    postRepo.dispose();
    p2pService.dispose();
  }
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
