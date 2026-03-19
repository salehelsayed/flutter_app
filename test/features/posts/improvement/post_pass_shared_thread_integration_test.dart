import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/post_comment_listener.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/application/post_reaction_listener.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_reaction_use_case.dart';
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
    'Solz -> Hisam -> Ibra comment continuity reaches both Solz and Hisam, and Hisam replies back to Solz and Ibra',
    () async {
      _connectTriangle(solz: solz, hisam: hisam, ibra: ibra);
      solz.start();
      hisam.start();
      ibra.start();
      await _seedSourcePost(solz: solz, hisam: hisam);

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

      expect(passResult, PassPostAlongResult.success);
      expect(pass, isNotNull);
      await _waitForPassCount(solz, expectedCount: 1);
      await _waitForPassCount(ibra, expectedCount: 1);

      final (ibraCommentResult, ibraComment) = await sendPostComment(
        p2pService: ibra.p2pService,
        postRepo: ibra.postRepo,
        contactRepo: ibra.contactRepo,
        postId: 'post-1',
        senderPeerId: ibra.peerId,
        senderUsername: ibra.username,
        body: 'I can help too.',
      );

      expect(ibraCommentResult, SendPostCommentResult.success);
      expect(ibraComment, isNotNull);
      await _waitForCommentCount(solz, expectedCount: 1);
      await _waitForCommentCount(hisam, expectedCount: 1);

      expect(
        (await solz.postRepo.loadComments('post-1')).single.body,
        'I can help too.',
      );
      expect(
        (await hisam.postRepo.loadComments('post-1')).single.body,
        'I can help too.',
      );

      final (hisamCommentResult, hisamComment) = await sendPostComment(
        p2pService: hisam.p2pService,
        postRepo: hisam.postRepo,
        contactRepo: hisam.contactRepo,
        postId: 'post-1',
        senderPeerId: hisam.peerId,
        senderUsername: hisam.username,
        body: 'Bring it around back.',
      );

      expect(hisamCommentResult, SendPostCommentResult.success);
      expect(hisamComment, isNotNull);
      await _waitForCommentCount(solz, expectedCount: 2);
      await _waitForCommentCount(ibra, expectedCount: 2);

      expect(
        (await solz.postRepo.loadComments('post-1')).last.body,
        'Bring it around back.',
      );
      expect(
        (await ibra.postRepo.loadComments('post-1')).last.body,
        'Bring it around back.',
      );
    },
  );

  test(
    'Solz -> Hisam -> Ibra reaction continuity reaches both Solz and Hisam',
    () async {
      _connectTriangle(solz: solz, hisam: hisam, ibra: ibra);
      solz.start();
      hisam.start();
      ibra.start();
      await _seedSourcePost(solz: solz, hisam: hisam);

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

      expect(passResult, PassPostAlongResult.success);
      expect(pass, isNotNull);
      await _waitForPassCount(solz, expectedCount: 1);
      await _waitForPassCount(ibra, expectedCount: 1);

      final (reactionResult, reaction) = await sendPostReaction(
        p2pService: ibra.p2pService,
        postRepo: ibra.postRepo,
        contactRepo: ibra.contactRepo,
        postId: 'post-1',
        senderPeerId: ibra.peerId,
        isActive: true,
      );

      expect(reactionResult, SendPostReactionResult.success);
      expect(reaction, isNotNull);
      await _waitForPostReaction(
        solz,
        senderPeerId: 'peer-ibra',
        isActive: true,
      );
      await _waitForPostReaction(
        hisam,
        senderPeerId: 'peer-ibra',
        isActive: true,
      );
    },
  );

  test(
    'A↔B and B↔C without A↔C should still deliver C comments on the repost to both A and B',
    () async {
      _connectChain(solz: solz, hisam: hisam, ibra: ibra);
      expect(await solz.contactRepo.getContact(ibra.peerId), isNull);
      expect(await ibra.contactRepo.getContact(solz.peerId), isNull);
      solz.start();
      hisam.start();
      ibra.start();
      await _seedSourcePost(solz: solz, hisam: hisam);

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

      expect(passResult, PassPostAlongResult.success);
      expect(pass, isNotNull);
      await _waitForPassCount(solz, expectedCount: 1);
      await _waitForPassCount(ibra, expectedCount: 1);

      final (commentResult, comment) = await sendPostComment(
        p2pService: ibra.p2pService,
        postRepo: ibra.postRepo,
        contactRepo: ibra.contactRepo,
        postId: 'post-1',
        senderPeerId: ibra.peerId,
        senderUsername: ibra.username,
        body: 'This should reach both the passer and the original author.',
      );

      expect(commentResult, SendPostCommentResult.success);
      expect(comment, isNotNull);
      await _waitForCommentCount(solz, expectedCount: 1);
      await _waitForCommentCount(hisam, expectedCount: 1);
    },
  );

  test(
    'A↔B and B↔C without A↔C should still deliver C hearts on the repost to both A and B',
    () async {
      _connectChain(solz: solz, hisam: hisam, ibra: ibra);
      expect(await solz.contactRepo.getContact(ibra.peerId), isNull);
      expect(await ibra.contactRepo.getContact(solz.peerId), isNull);
      solz.start();
      hisam.start();
      ibra.start();
      await _seedSourcePost(solz: solz, hisam: hisam);

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

      expect(passResult, PassPostAlongResult.success);
      expect(pass, isNotNull);
      await _waitForPassCount(solz, expectedCount: 1);
      await _waitForPassCount(ibra, expectedCount: 1);

      final (reactionResult, reaction) = await sendPostReaction(
        p2pService: ibra.p2pService,
        postRepo: ibra.postRepo,
        contactRepo: ibra.contactRepo,
        postId: 'post-1',
        senderPeerId: ibra.peerId,
        isActive: true,
      );

      expect(reactionResult, SendPostReactionResult.success);
      expect(reaction, isNotNull);
      await _waitForPostReaction(
        solz,
        senderPeerId: 'peer-ibra',
        isActive: true,
      );
      await _waitForPostReaction(
        hisam,
        senderPeerId: 'peer-ibra',
        isActive: true,
      );
    },
  );

  test(
    'original-audience recipients stay out of repost-thread follow-ons until they become repost participants',
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

      expect(passResult, PassPostAlongResult.success);
      expect(pass, isNotNull);
      await _waitForPassCount(solz, expectedCount: 1);
      await _waitForPassCount(ibra, expectedCount: 1);
      expect(await dana.postRepo.loadPostPasses('post-1'), isEmpty);

      final (firstCommentResult, firstComment) = await sendPostComment(
        p2pService: solz.p2pService,
        postRepo: solz.postRepo,
        contactRepo: solz.contactRepo,
        postId: 'post-1',
        senderPeerId: solz.peerId,
        senderUsername: solz.username,
        body: 'Use the side gate.',
      );

      expect(firstCommentResult, SendPostCommentResult.success);
      expect(firstComment, isNotNull);
      await _waitForCommentCount(hisam, expectedCount: 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await dana.postRepo.loadComments('post-1'), isEmpty);

      await solz.postRepo.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: dana.peerId,
        createdAt: '2026-03-15T11:20:00.000Z',
      );

      final (secondCommentResult, secondComment) = await sendPostComment(
        p2pService: solz.p2pService,
        postRepo: solz.postRepo,
        contactRepo: solz.contactRepo,
        postId: 'post-1',
        senderPeerId: solz.peerId,
        senderUsername: solz.username,
        body: 'Dana is now opted into the repost thread.',
      );

      expect(secondCommentResult, SendPostCommentResult.success);
      expect(secondComment, isNotNull);
      await _waitForCommentCount(hisam, expectedCount: 2);
      await _waitForCommentCount(dana, expectedCount: 1);
      expect(
        (await dana.postRepo.loadComments('post-1')).single.body,
        'Dana is now opted into the repost thread.',
      );
    },
  );

  test(
    'multi-recipient repost fanout keeps Ibra engagement scoped away from Dana until Dana engages',
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

      expect(passResult, PassPostAlongResult.success);
      expect(pass, isNotNull);
      await _waitForPassCount(solz, expectedCount: 1);
      await _waitForPassCount(ibra, expectedCount: 1);
      await _waitForPassCount(dana, expectedCount: 1);

      final (commentResult, comment) = await sendPostComment(
        p2pService: ibra.p2pService,
        postRepo: ibra.postRepo,
        contactRepo: ibra.contactRepo,
        postId: 'post-1',
        senderPeerId: ibra.peerId,
        senderUsername: ibra.username,
        body: 'I found one nearby.',
      );

      expect(commentResult, SendPostCommentResult.success);
      expect(comment, isNotNull);
      await _waitForCommentCount(solz, expectedCount: 1);
      await _waitForCommentCount(hisam, expectedCount: 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await dana.postRepo.loadComments('post-1'), isEmpty);
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

Future<void> _waitForPassCount(
  _RepostThreadUser user, {
  required int expectedCount,
  Duration timeout = const Duration(seconds: 1),
}) async {
  await _waitUntil(
    description: '${user.username} pass count $expectedCount',
    timeout: timeout,
    condition: () async =>
        (await user.postRepo.loadPostPasses('post-1')).length ==
            expectedCount &&
        await user.postRepo.getPost('post-1') != null,
  );
}

Future<void> _waitForCommentCount(
  _RepostThreadUser user, {
  required int expectedCount,
  Duration timeout = const Duration(seconds: 1),
}) async {
  await _waitUntil(
    description: '${user.username} comment count $expectedCount',
    timeout: timeout,
    condition: () async =>
        (await user.postRepo.loadComments('post-1')).length == expectedCount,
  );
}

Future<void> _waitForPostReaction(
  _RepostThreadUser user, {
  required String senderPeerId,
  required bool isActive,
  Duration timeout = const Duration(seconds: 1),
}) async {
  await _waitUntil(
    description: '${user.username} reaction from $senderPeerId',
    timeout: timeout,
    condition: () async {
      final reactions = await user.postRepo.loadPostReactions('post-1');
      return reactions.any(
        (reaction) =>
            reaction.senderPeerId == senderPeerId &&
            reaction.isActive == isActive,
      );
    },
  );
}

Future<void> _waitUntil({
  required String description,
  required Future<bool> Function() condition,
  Duration timeout = const Duration(seconds: 1),
}) async {
  if (await condition()) {
    return;
  }
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (await condition()) {
      return;
    }
  }
  throw StateError('Timed out waiting for $description');
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
