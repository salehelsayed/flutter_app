import '../support/legacy_post_state.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/post_comment_listener.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/application/post_reaction_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late _BaselineUser solz;
  late _BaselineUser hisam;
  late _BaselineUser ibra;
  late _BaselineUser zoya;

  setUp(() {
    network = FakeP2PNetwork();
    solz = _BaselineUser.create(
      peerId: 'peer-solz',
      username: 'Solz',
      network: network,
    );
    hisam = _BaselineUser.create(
      peerId: 'peer-hisam',
      username: 'Hisam',
      network: network,
    );
    ibra = _BaselineUser.create(
      peerId: 'peer-ibra',
      username: 'Ibra',
      network: network,
    );
    zoya = _BaselineUser.create(
      peerId: 'peer-zoya',
      username: 'Zoya',
      network: network,
    );
  });

  tearDown(() {
    solz.dispose();
    hisam.dispose();
    ibra.dispose();
    zoya.dispose();
  });

  test(
    'rejects legacy pass: fresh repost recipients start with carried heart and repost-total baselines, and later unlike decrements correctly',
    () async {
      hisam.addContact(solz);
      hisam.addContact(ibra);
      ibra.addContact(hisam);
      ibra.addContact(zoya);
      await _seedBaselineSourcePost(hisam);
      await hisam.postRepo.savePostReaction(
        const PostReactionModel(
          reactionId: 'post_heart:post-1:peer-zoya',
          eventId: 'evt-heart-zoya',
          postId: 'post-1',
          senderPeerId: 'peer-zoya',
          isActive: true,
          reactedAt: '2026-03-15T10:50:00.000Z',
        ),
      );
      await hisam.postRepo.savePostPass(
        const PostPassModel(
          passId: 'pass-old-1',
          eventId: 'evt-pass-old-1',
          postId: 'post-1',
          senderPeerId: 'peer-hisam',
          passerPeerId: 'peer-hisam',
          passerUsername: 'Hisam',
          passedAt: '2026-03-15T10:55:00.000Z',
          createdAt: '2026-03-15T10:55:00.000Z',
          isIncoming: false,
        ),
      );
      await hisam.postRepo.savePostPass(
        const PostPassModel(
          passId: 'pass-old-2',
          eventId: 'evt-pass-old-2',
          postId: 'post-1',
          senderPeerId: 'peer-solz',
          passerPeerId: 'peer-solz',
          passerUsername: 'Solz',
          passedAt: '2026-03-15T11:00:00.000Z',
          createdAt: '2026-03-15T11:00:00.000Z',
          isIncoming: true,
        ),
      );

      final previousPassState = await snapshotLegacyPostState(
        hisam.postRepo,
        postId: 'post-1',
      );
      final (result, pass) = await passPostAlong(
        p2pService: hisam.p2pService,
        postRepo: hisam.postRepo,
        contactRepo: hisam.contactRepo,
        bridge: hisam.bridge,
        postId: 'post-1',
        senderPeerId: hisam.peerId,
        senderUsername: hisam.username,
        recipientPeerIds: const <String>['peer-ibra'],
      );
      expect(result, PassPostAlongResult.notAllowed);
      expect(pass, isNull);
      expect(
        await snapshotLegacyPostState(hisam.postRepo, postId: 'post-1'),
        previousPassState,
      );
    },
  );

  test(
    'rejects legacy pass: original-author surfaces reflect reposted-copy comment and heart counts',
    () async {
      _connectTriangle(solz: solz, hisam: hisam, ibra: ibra);
      solz.start();
      hisam.start();
      ibra.start();
      await _seedSharedPost(solz: solz, hisam: hisam);

      final previousPassState = await snapshotLegacyPostState(
        hisam.postRepo,
        postId: 'post-1',
      );
      final (passResult, pass) = await passPostAlong(
        p2pService: hisam.p2pService,
        postRepo: hisam.postRepo,
        contactRepo: hisam.contactRepo,
        bridge: hisam.bridge,
        postId: 'post-1',
        senderPeerId: hisam.peerId,
        senderUsername: hisam.username,
        recipientPeerIds: const <String>['peer-ibra'],
      );
      expect(passResult, PassPostAlongResult.notAllowed);
      expect(pass, isNull);
      expect(
        await snapshotLegacyPostState(hisam.postRepo, postId: 'post-1'),
        previousPassState,
      );
    },
  );
}

void _connectTriangle({
  required _BaselineUser solz,
  required _BaselineUser hisam,
  required _BaselineUser ibra,
}) {
  solz.addContact(hisam);
  solz.addContact(ibra);
  hisam.addContact(solz);
  hisam.addContact(ibra);
  ibra.addContact(solz);
  ibra.addContact(hisam);
}

Future<void> _seedBaselineSourcePost(_BaselineUser owner) async {
  await owner.postRepo.savePost(
    PostModel(
      id: 'post-1',
      eventId: 'evt-post-1',
      senderPeerId: 'peer-solz',
      authorPeerId: 'peer-solz',
      authorUsername: 'Solz',
      text: 'Need help carrying a ladder.',
      audience: PostAudience.allFriends(),
      createdAt: '2026-03-15T10:15:30.000Z',
      visibleAt: '2026-03-15T10:15:30.000Z',
      expiresAt: '2026-03-18T10:15:30.000Z',
      isIncoming: true,
    ),
  );
}

Future<void> _seedSharedPost({
  required _BaselineUser solz,
  required _BaselineUser hisam,
}) async {
  const post = PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: 'peer-solz',
    authorPeerId: 'peer-solz',
    authorUsername: 'Solz',
    text: 'Need help carrying a ladder.',
    audience: PostAudience(kind: PostAudienceKind.allFriends),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    isIncoming: true,
  );
  await solz.postRepo.savePost(post.copyWith(isIncoming: false));
  await solz.postRepo.saveRecipientDelivery(
    const PostRecipientDelivery(
      postId: 'post-1',
      recipientPeerId: 'peer-hisam',
      deliveryStatus: 'delivered',
      lastAttemptAt: '2026-03-15T10:15:31.000Z',
      deliveryPath: 'direct',
      createdAt: '2026-03-15T10:15:31.000Z',
      updatedAt: '2026-03-15T10:15:31.000Z',
    ),
  );
  await hisam.postRepo.savePost(post);
}

class _BaselineUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final PassthroughCryptoBridge bridge;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;
  final IncomingMessageRouter router;
  final PostPassListener passListener;
  final PostCommentListener commentListener;
  final PostReactionListener reactionListener;

  _BaselineUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.bridge,
    required this.contactRepo,
    required this.postRepo,
    required this.router,
    required this.passListener,
    required this.commentListener,
    required this.reactionListener,
  });

  factory _BaselineUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
  }) {
    final p2pService = FakeP2PService(peerId: peerId, network: network);
    final bridge = PassthroughCryptoBridge();
    final contactRepo = InMemoryContactRepository();
    final postRepo = InMemoryPostRepository();
    final router = IncomingMessageRouter(p2pService: p2pService);
    final passListener = PostPassListener(
      postPassStream: router.postPassStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
    );
    final commentListener = PostCommentListener(
      postCommentStream: router.postCommentStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
    );
    final reactionListener = PostReactionListener(
      postReactionStream: router.postReactionStream,
      postCommentReactionStream: router.postCommentReactionStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
    );

    return _BaselineUser._(
      peerId: peerId,
      username: username,
      p2pService: p2pService,
      bridge: bridge,
      contactRepo: contactRepo,
      postRepo: postRepo,
      router: router,
      passListener: passListener,
      commentListener: commentListener,
      reactionListener: reactionListener,
    );
  }

  void addContact(_BaselineUser other) {
    contactRepo.addTestContact(
      ContactModel(
        peerId: other.peerId,
        publicKey: 'pk-${other.peerId}',
        rendezvous: '/dns4/example.invalid/tcp/443',
        username: other.username,
        signature: 'sig-${other.peerId}',
        scannedAt: '2026-03-15T10:00:00.000Z',
        mlKemPublicKey: 'mlkem-${other.peerId}',
      ),
    );
  }

  void start() {
    router.start();
    passListener.start();
    commentListener.start();
    reactionListener.start();
  }

  void dispose() {
    reactionListener.dispose();
    commentListener.dispose();
    passListener.dispose();
    router.dispose();
    postRepo.dispose();
    p2pService.dispose();
  }
}
