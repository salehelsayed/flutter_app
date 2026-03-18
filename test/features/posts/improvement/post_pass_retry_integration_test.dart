import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late _PassUser sender;
  late _PassUser author;
  late _PassUser recipient;
  late _PassUser recipientTwo;

  setUp(() {
    network = FakeP2PNetwork();
    sender = _PassUser.create(
      peerId: 'peer-alice',
      username: 'Alice',
      network: network,
    );
    author = _PassUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
    );
    recipient = _PassUser.create(
      peerId: 'peer-cara',
      username: 'Cara',
      network: network,
    );
    recipientTwo = _PassUser.create(
      peerId: 'peer-dan',
      username: 'Dan',
      network: network,
    );

    sender.addContact(author);
    sender.addContact(recipient);
    sender.addContact(recipientTwo);
    author.addContact(sender);
    recipient.addContact(sender);
    recipientTwo.addContact(sender);
    author.start();
    recipient.start();
    recipientTwo.start();
  });

  tearDown(() {
    sender.dispose();
    author.dispose();
    recipient.dispose();
    recipientTwo.dispose();
  });

  test(
    'pass retry uses the post delivery retrier, preserves explicit recipient plus author notification, and does not duplicate pass records',
    () async {
      await _seedSharedPost(sender: sender, author: author);
      author.p2pService.setOnline(false);
      network.inboxDisabled = true;

      final (result, pass) = await passPostAlong(
        p2pService: sender.p2pService,
        postRepo: sender.postRepo,
        contactRepo: sender.contactRepo,
        bridge: sender.bridge,
        postId: 'post-1',
        senderPeerId: sender.peerId,
        senderUsername: sender.username,
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.partiallySettled);
      expect(pass, isNotNull);
      expect(await sender.postRepo.loadPostPasses('post-1'), hasLength(1));
      await _waitForPassCount(
        recipient,
        expectedCount: 1,
        description: 'explicit recipient pass delivery',
      );
      expect(await author.postRepo.loadPostPasses('post-1'), isEmpty);

      final retryablePasses = await sender.postRepo
          .loadRetryableOutgoingPostPasses();
      expect(retryablePasses, hasLength(1));
      expect(retryablePasses.single.passId, pass!.passId);
      expect(await sender.postRepo.loadRetryableFollowOnOutboxJobs(), isEmpty);
      expect(
        (await sender.postRepo.getPostPassRecipientDeliveries(pass.passId))
            .where(
              (delivery) =>
                  delivery.deliveryStatus != 'delivered' &&
                  delivery.deliveryStatus != 'inbox',
            )
            .map((delivery) => delivery.recipientPeerId),
        <String>[author.peerId],
      );

      author.p2pService.setOnline(true);
      network.inboxDisabled = false;

      final followOnRetried = await retryPendingPostFollowOns(
        postRepo: sender.postRepo,
        p2pService: sender.p2pService,
      );
      expect(followOnRetried, 0);

      final retried = await retryPendingPostDeliveries(
        postRepo: sender.postRepo,
        contactRepo: sender.contactRepo,
        p2pService: sender.p2pService,
        bridge: sender.bridge,
      );

      expect(retried, 1);
      await _waitForPassCount(
        author,
        expectedCount: 1,
        description: 'author notification retry delivery',
      );
      expect(await sender.postRepo.loadPostPasses('post-1'), hasLength(1));
      expect(await recipient.postRepo.loadPostPasses('post-1'), hasLength(1));
      expect(await author.postRepo.loadPostPasses('post-1'), hasLength(1));
      expect(await author.postRepo.loadPostPassCount('post-1'), 1);
      expect(await sender.postRepo.loadRetryableOutgoingPostPasses(), isEmpty);
      expect(await sender.postRepo.loadRetryableFollowOnOutboxJobs(), isEmpty);

      final secondRetry = await retryPendingPostDeliveries(
        postRepo: sender.postRepo,
        contactRepo: sender.contactRepo,
        p2pService: sender.p2pService,
        bridge: sender.bridge,
      );

      expect(secondRetry, 0);
      expect(await sender.postRepo.loadPostPasses('post-1'), hasLength(1));
      expect(await recipient.postRepo.loadPostPasses('post-1'), hasLength(1));
      expect(await author.postRepo.loadPostPasses('post-1'), hasLength(1));
      expect(
        sender.bridge.commandLog.where(
          (command) => command == 'message.encrypt',
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'pass retry preserves shared-to totals with multi-recipient baseline replay on the receiving side',
    () async {
      await _seedSharedPost(sender: sender, author: author);
      await sender.postRepo.seedRepostSharedToBaseline(
        postId: 'post-1',
        sharedToCountBaseline: 4,
        existingLocalSharedToCount: 0,
        currentPassRecipientCount: 0,
        createdAt: '2026-03-15T11:10:00.000Z',
      );
      author.p2pService.setOnline(false);
      network.inboxDisabled = true;

      final (result, pass) = await passPostAlong(
        p2pService: sender.p2pService,
        postRepo: sender.postRepo,
        contactRepo: sender.contactRepo,
        bridge: sender.bridge,
        postId: 'post-1',
        senderPeerId: sender.peerId,
        senderUsername: sender.username,
        recipientPeerIds: const <String>['peer-cara', 'peer-dan'],
      );

      expect(result, PassPostAlongResult.partiallySettled);
      expect(pass, isNotNull);
      expect(pass!.recipientCount, 2);
      await _waitForPassCount(
        recipient,
        expectedCount: 1,
        description: 'explicit recipient pass delivery with shared-to baseline',
      );
      await _waitForProjectedTotalSharedToCount(
        recipient,
        expectedCount: 6,
        description: 'explicit recipient shared-to projection',
      );

      author.p2pService.setOnline(true);
      network.inboxDisabled = false;

      final retried = await retryPendingPostDeliveries(
        postRepo: sender.postRepo,
        contactRepo: sender.contactRepo,
        p2pService: sender.p2pService,
        bridge: sender.bridge,
      );

      expect(retried, 1);
      await _waitForPassCount(
        author,
        expectedCount: 1,
        description: 'author notification retry delivery with shared-to replay',
      );
      await _waitForProjectedTotalSharedToCount(
        author,
        expectedCount: 6,
        description: 'author notification shared-to projection',
      );
      expect(await sender.postRepo.loadPostPasses('post-1'), hasLength(1));
      expect(await recipient.postRepo.loadPostPasses('post-1'), hasLength(1));
      expect(await author.postRepo.loadPostPasses('post-1'), hasLength(1));
    },
  );

  test(
    'offline-inbox fallback persists an encrypted post_pass payload for the author notification path',
    () async {
      await _seedSharedPost(sender: sender, author: author);
      author.p2pService.setOnline(false);

      final (result, pass) = await passPostAlong(
        p2pService: sender.p2pService,
        postRepo: sender.postRepo,
        contactRepo: sender.contactRepo,
        bridge: sender.bridge,
        postId: 'post-1',
        senderPeerId: sender.peerId,
        senderUsername: sender.username,
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);
      expect(network.inboxCount(author.peerId), 1);
      await _waitForPassCount(
        recipient,
        expectedCount: 1,
        description: 'explicit recipient pass delivery before inbox inspection',
      );

      final storedInbox = network.retrieveInbox(author.peerId);
      expect(storedInbox, hasLength(1));
      final storedMessage = storedInbox.single['message'] as String;
      final storedJson = jsonDecode(storedMessage) as Map<String, dynamic>;
      final payload = _decodeEncryptedPassPayload(storedJson);

      expect(storedJson['type'], 'post_pass');
      expect(storedJson['version'], '2');
      expect(storedJson.containsKey('encrypted'), isTrue);
      expect(payload['post_id'], 'post-1');
      expect(payload.containsKey('original_snapshot'), isTrue);
      expect(payload['participant_peer_ids'], <String>[
        'peer-alice',
        'peer-bob',
      ]);
      expect(payload['repost_total_baseline'], 0);
    },
  );

  test(
    'retryPendingPostDeliveries rebuilds an encrypted post_pass envelope from durable inner payload state',
    () async {
      await _seedSharedPost(sender: sender, author: author);
      author.p2pService.setOnline(false);
      network.inboxDisabled = true;

      final (result, pass) = await passPostAlong(
        p2pService: sender.p2pService,
        postRepo: sender.postRepo,
        contactRepo: sender.contactRepo,
        bridge: sender.bridge,
        postId: 'post-1',
        senderPeerId: sender.peerId,
        senderUsername: sender.username,
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.partiallySettled);
      expect(pass, isNotNull);
      await _waitForPassCount(
        recipient,
        expectedCount: 1,
        description: 'explicit recipient pass delivery before retry replay',
      );

      final storedPass = (await sender.postRepo.loadPostPasses(
        'post-1',
      )).single;
      expect(storedPass.innerPayloadJson, isNotNull);

      final receivedOnRetry = author.p2pService.messageStream.first;
      author.p2pService.setOnline(true);
      network.inboxDisabled = false;

      final retried = await retryPendingPostDeliveries(
        postRepo: sender.postRepo,
        contactRepo: sender.contactRepo,
        p2pService: sender.p2pService,
        bridge: sender.bridge,
      );

      expect(retried, 1);
      await _waitForPassCount(
        author,
        expectedCount: 1,
        description: 'author retry pass persistence',
      );

      final retriedMessage = await receivedOnRetry.timeout(
        const Duration(seconds: 1),
      );
      final retriedJson =
          jsonDecode(retriedMessage.content) as Map<String, dynamic>;
      final payload = _decodeEncryptedPassPayload(retriedJson);

      expect(retriedJson['type'], 'post_pass');
      expect(retriedJson['version'], '2');
      expect(retriedJson.containsKey('encrypted'), isTrue);
      expect(payload['post_id'], 'post-1');
      expect(payload['participant_peer_ids'], <String>[
        'peer-alice',
        'peer-bob',
      ]);
      expect(payload['repost_total_baseline'], 0);
      expect(
        PostPassEnvelope.parseEncryptedEnvelope(retriedMessage.content),
        isNotNull,
      );
    },
  );
}

Future<void> _seedSharedPost({
  required _PassUser sender,
  required _PassUser author,
}) async {
  final post = _sharedPost();
  await sender.postRepo.savePost(post);
  await author.postRepo.savePost(post);
}

PostModel _sharedPost() {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: 'Lost dog near Neckar bridge.',
    audience: PostAudience.peopleNearby(radiusM: 2000),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    isIncoming: true,
  );
}

Future<void> _waitForPassCount(
  _PassUser user, {
  required int expectedCount,
  required String description,
}) async {
  Future<bool> condition() async {
    return (await user.postRepo.loadPostPasses('post-1')).length ==
        expectedCount;
  }

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

Future<void> _waitForProjectedTotalSharedToCount(
  _PassUser user, {
  required int expectedCount,
  required String description,
}) async {
  Future<bool> condition() async {
    return (await user.postRepo.getPost('post-1'))?.totalSharedToCount ==
        expectedCount;
  }

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

class _PassUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;
  final IncomingMessageRouter router;
  final PostPassListener passListener;
  final PassthroughCryptoBridge bridge;

  _PassUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.contactRepo,
    required this.postRepo,
    required this.router,
    required this.passListener,
    required this.bridge,
  });

  factory _PassUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
  }) {
    final p2pService = FakeP2PService(peerId: peerId, network: network);
    final contactRepo = InMemoryContactRepository();
    final postRepo = InMemoryPostRepository();
    final router = IncomingMessageRouter(p2pService: p2pService);
    final bridge = PassthroughCryptoBridge();
    final passListener = PostPassListener(
      postPassStream: router.postPassStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
    );

    return _PassUser._(
      peerId: peerId,
      username: username,
      p2pService: p2pService,
      contactRepo: contactRepo,
      postRepo: postRepo,
      router: router,
      passListener: passListener,
      bridge: bridge,
    );
  }

  void addContact(_PassUser other) {
    contactRepo.addTestContact(_contact(other.peerId, other.username));
  }

  void start() {
    router.start();
    passListener.start();
  }

  void dispose() {
    passListener.dispose();
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
    mlKemPublicKey: 'mlkem-$peerId',
  );
}

Map<String, dynamic> _decodeEncryptedPassPayload(Map<String, dynamic> json) {
  final encrypted = json['encrypted'] as Map<String, dynamic>;
  return jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
}
