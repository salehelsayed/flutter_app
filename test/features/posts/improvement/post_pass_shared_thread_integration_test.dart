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
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late _RepostThreadUser solz;
  late _RepostThreadUser hisam;
  late _RepostThreadUser ibra;
  late _RepostThreadUser dana;

  setUp(() {
    network = FakeP2PNetwork();
    solz = _RepostThreadUser.create(
      peerId: 'peer-solz',
      username: 'Solz',
      network: network,
    );
    hisam = _RepostThreadUser.create(
      peerId: 'peer-hisam',
      username: 'Hisam',
      network: network,
    );
    ibra = _RepostThreadUser.create(
      peerId: 'peer-ibra',
      username: 'Ibra',
      network: network,
    );
    dana = _RepostThreadUser.create(
      peerId: 'peer-dana',
      username: 'Dana',
      network: network,
    );
  });

  tearDown(() {
    solz.dispose();
    hisam.dispose();
    ibra.dispose();
    dana.dispose();
  });

  test(
    'rejects legacy pass: Solz -> Hisam -> Ibra comment continuity reaches both Solz and Hisam, and Hisam replies back to Solz and Ibra',
    () async {
      _connectTriangle(solz: solz, hisam: hisam, ibra: ibra);
      solz.start();
      hisam.start();
      ibra.start();
      await _seedSourcePost(solz: solz, hisam: hisam);

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

  test(
    'rejects legacy pass: Solz -> Hisam -> Ibra reaction continuity reaches both Solz and Hisam',
    () async {
      _connectTriangle(solz: solz, hisam: hisam, ibra: ibra);
      solz.start();
      hisam.start();
      ibra.start();
      await _seedSourcePost(solz: solz, hisam: hisam);

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

  test(
    'rejects legacy pass: A↔B and B↔C without A↔C should still deliver C comments on the repost to both A and B',
    () async {
      _connectChain(solz: solz, hisam: hisam, ibra: ibra);
      expect(await solz.contactRepo.getContact(ibra.peerId), isNull);
      expect(await ibra.contactRepo.getContact(solz.peerId), isNull);
      solz.start();
      hisam.start();
      ibra.start();
      await _seedSourcePost(solz: solz, hisam: hisam);

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

  test(
    'rejects legacy pass: A↔B and B↔C without A↔C should still deliver C hearts on the repost to both A and B',
    () async {
      _connectChain(solz: solz, hisam: hisam, ibra: ibra);
      expect(await solz.contactRepo.getContact(ibra.peerId), isNull);
      expect(await ibra.contactRepo.getContact(solz.peerId), isNull);
      solz.start();
      hisam.start();
      ibra.start();
      await _seedSourcePost(solz: solz, hisam: hisam);

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

  test(
    'rejects legacy pass: original-audience recipients stay out of repost-thread follow-ons until they become repost participants',
    () async {
      _connectTriangle(solz: solz, hisam: hisam, ibra: ibra);
      solz.addContact(dana);
      dana.addContact(solz);
      solz.start();
      hisam.start();
      ibra.start();
      dana.start();
      await _seedSourcePost(
        solz: solz,
        hisam: hisam,
        additionalRecipients: <_RepostThreadUser>[dana],
      );

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

  test(
    'rejects legacy pass: multi-recipient repost fanout keeps Ibra engagement scoped away from Dana until Dana engages',
    () async {
      _connectTriangle(solz: solz, hisam: hisam, ibra: ibra);
      hisam.addContact(dana);
      solz.addContact(dana);
      dana.addContact(hisam);
      solz.start();
      hisam.start();
      ibra.start();
      dana.start();
      await _seedSourcePost(solz: solz, hisam: hisam);

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
        recipientPeerIds: const <String>['peer-ibra', 'peer-dana'],
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
  required _RepostThreadUser solz,
  required _RepostThreadUser hisam,
  required _RepostThreadUser ibra,
}) {
  solz.addContact(hisam);
  solz.addContact(ibra);
  hisam.addContact(solz);
  hisam.addContact(ibra);
  ibra.addContact(solz);
  ibra.addContact(hisam);
}

void _connectChain({
  required _RepostThreadUser solz,
  required _RepostThreadUser hisam,
  required _RepostThreadUser ibra,
}) {
  solz.addContact(hisam);
  hisam.addContact(solz);
  hisam.addContact(ibra);
  ibra.addContact(hisam);
}

Future<void> _seedSourcePost({
  required _RepostThreadUser solz,
  required _RepostThreadUser hisam,
  List<_RepostThreadUser> additionalRecipients = const <_RepostThreadUser>[],
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
  final recipients = <_RepostThreadUser>[hisam, ...additionalRecipients];
  await solz.postRepo.savePost(post.copyWith(isIncoming: false));
  for (final recipient in recipients) {
    await solz.postRepo.saveRecipientDelivery(
      PostRecipientDelivery(
        postId: 'post-1',
        recipientPeerId: recipient.peerId,
        deliveryStatus: 'delivered',
        lastAttemptAt: '2026-03-15T10:15:31.000Z',
        deliveryPath: 'direct',
        createdAt: '2026-03-15T10:15:31.000Z',
        updatedAt: '2026-03-15T10:15:31.000Z',
      ),
    );
    await recipient.postRepo.savePost(post);
  }
}

class _RepostThreadUser {
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

  _RepostThreadUser._({
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

  factory _RepostThreadUser.create({
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

    return _RepostThreadUser._(
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

  void addContact(_RepostThreadUser other) {
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
