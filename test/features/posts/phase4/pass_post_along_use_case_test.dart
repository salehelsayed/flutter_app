import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

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

  test(
    'includes stored media attachments in the outgoing original snapshot',
    () async {
      await posts.savePost(_directPost(mediaKind: 'image'));
      await posts.savePostMediaAttachment(
        const PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: 'post-1',
          blobId: 'blob-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: 248120,
          width: 1440,
          height: 1080,
          localPath: 'post_media/post-1/blob-1.jpg',
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );

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
      final media = (snapshot['media'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(snapshot['media_kind'], 'image');
      expect(media, hasLength(1));
      expect(media.single['media_id'], 'media-1');
      expect(media.single['blob_id'], 'blob-1');
    },
  );

  test(
    'createLocalPostPass persists a local pass and queued recipient deliveries before background delivery starts',
    () async {
      await posts.savePost(_directPost());

      final (result, created) = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.success);
      expect(created, isNotNull);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);

      final localPasses = await posts.loadPostPasses('post-1');
      expect(localPasses, hasLength(1));
      expect(created!.pass.passId, localPasses.single.passId);
      expect(localPasses.single.deliveryStatus, 'sending');
      final deliveries = await posts.getPostPassRecipientDeliveries(
        created.pass.passId,
      );
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-bob',
        'peer-cara',
      ]);
      expect(
        deliveries.map((delivery) => delivery.deliveryStatus),
        everyElement('pending'),
      );
      expect(
        deliveries.map((delivery) => delivery.deliveryOwnerKind),
        everyElement(postRecipientDeliveryOwnerKindPass),
      );
      expect(
        deliveries.map((delivery) => delivery.deliveryOwnerId),
        everyElement(created.pass.passId),
      );
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    },
  );

  test(
    'persists a local pass and shared recipient deliveries before delivery completes',
    () async {
      await posts.savePost(_directPost());
      network.deliveryDelay = const Duration(milliseconds: 150);

      final sendFuture = passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final localPasses = await posts.loadPostPasses('post-1');
      expect(localPasses, hasLength(1));
      expect(localPasses.single.deliveryStatus, 'sending');
      final deliveries = await posts.getPostPassRecipientDeliveries(
        localPasses.single.passId,
      );
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-bob',
        'peer-cara',
      ]);
      expect(
        deliveries.map((delivery) => delivery.deliveryStatus),
        everyElement('pending'),
      );
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);

      final (result, pass) = await sendFuture;
      expect(result, PassPostAlongResult.success);
      expect(pass?.passId, localPasses.single.passId);
    },
  );

  test(
    'does not create a duplicate delivery target when the sender explicitly selects the original author',
    () async {
      await posts.savePost(_directPost());

      final receivedByBob = bobService.messageStream.first;
      final receivedByCara = caraService.messageStream.first;

      final (result, pass) = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
      );

      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);
      expect(network.deliverCallCount, 2);

      final deliveries = await posts.getPostPassRecipientDeliveries(
        pass!.passId,
      );
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-bob',
        'peer-cara',
      ]);
      expect(
        deliveries.where((delivery) => delivery.recipientPeerId == 'peer-bob'),
        hasLength(1),
      );
      expect(
        deliveries.where((delivery) => delivery.recipientPeerId == 'peer-cara'),
        hasLength(1),
      );

      await receivedByBob.timeout(const Duration(seconds: 1));
      await receivedByCara.timeout(const Duration(seconds: 1));
    },
  );

  test(
    'passPostAlong uses the post delivery runner default concurrency cap of 25',
    () async {
      final recipientPeerIds = List<String>.generate(
        30,
        (index) => 'peer-${index.toString().padLeft(2, '0')}',
      );
      final sendGates = <String, Completer<void>>{
        for (final peerId in recipientPeerIds) peerId: Completer<void>(),
      };
      final service = _ControlledP2PService(
        peerId: 'peer-bob',
        network: network,
        policies: {
          for (final peerId in recipientPeerIds)
            peerId: _PeerPolicy(sendGate: sendGates[peerId]),
        },
      );
      addTearDown(service.dispose);

      await posts.savePost(_directPost());
      for (final peerId in recipientPeerIds) {
        contacts.addTestContact(_contact(peerId, peerId));
      }

      final sendFuture = passPostAlong(
        p2pService: service,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        recipientPeerIds: recipientPeerIds,
      );

      await service
          .waitForSendCount(25)
          .timeout(const Duration(milliseconds: 200));
      await _drainMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder, recipientPeerIds.take(25).toList());

      sendGates[recipientPeerIds.first]!.complete();
      await service
          .waitForSendCount(26)
          .timeout(const Duration(milliseconds: 200));
      await _drainMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder, recipientPeerIds.take(26).toList());

      for (final gate in sendGates.values) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }

      final (result, pass) = await sendFuture;
      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);
      expect(service.maxInFlightSends, 25);
    },
  );

  test(
    'deliverCreatedLocalPostPass keeps the local pass and queued recipient deliveries when every delivery path fails',
    () async {
      await posts.savePost(_directPost());
      bobService.setOnline(false);
      caraService.setOnline(false);
      network.inboxDisabled = true;

      final (createResult, created) = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(createResult, PassPostAlongResult.success);
      expect(created, isNotNull);

      final deliveryResult = await deliverCreatedLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        created: created!,
      );

      expect(deliveryResult.$1, SendPostResult.sendFailed);
      final localPasses = await posts.loadPostPasses('post-1');
      expect(localPasses, hasLength(1));
      expect(localPasses.single.deliveryStatus, 'failed');

      final deliveries = await posts.getPostPassRecipientDeliveries(
        created.pass.passId,
      );
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-bob',
        'peer-cara',
      ]);
      expect(deliveries.map((delivery) => delivery.deliveryStatus), <String>[
        'failed',
        'failed',
      ]);

      final retryablePasses = await posts.loadRetryableOutgoingPostPasses();
      expect(retryablePasses, hasLength(1));
      expect(retryablePasses.single.passId, created.pass.passId);
    },
  );

  test(
    'keeps a local pass and retryable recipient-delivery state when the author notification is unresolved',
    () async {
      await posts.savePost(_directPost());
      bobService.setOnline(false);
      network.inboxDisabled = true;

      final (result, pass) = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.partiallySettled);
      expect(pass, isNotNull);
      expect(await posts.loadPostPasses('post-1'), hasLength(1));

      final deliveries = await posts.getPostPassRecipientDeliveries(
        pass!.passId,
      );
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-bob',
        'peer-cara',
      ]);
      expect(deliveries.map((delivery) => delivery.deliveryStatus), <String>[
        'failed',
        'delivered',
      ]);

      final retryablePasses = await posts.loadRetryableOutgoingPostPasses();
      expect(retryablePasses, hasLength(1));
      expect(retryablePasses.single.passId, pass.passId);
      expect(retryablePasses.single.deliveryStatus, 'partial');
      expect(
        deliveries
            .where(
              (delivery) =>
                  delivery.deliveryStatus != 'delivered' &&
                  delivery.deliveryStatus != 'inbox',
            )
            .map((delivery) => delivery.recipientPeerId),
        <String>['peer-bob'],
      );
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    },
  );

  test(
    'rejects a non-renderable snapshot before persisting a local pass or recipient-delivery state',
    () async {
      await posts.savePost(_directPost(mediaKind: 'image'));

      final (result, pass) = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.sendFailed);
      expect(pass, isNull);
      expect(await posts.loadPostPasses('post-1'), isEmpty);
      expect(await posts.loadRetryableOutgoingPostPasses(), isEmpty);
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
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
  String mediaKind = 'none',
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
    mediaKind: mediaKind,
  );
}

Future<void> _drainMicrotasks([int turns = 3]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ControlledP2PService extends FakeP2PService {
  final Map<String, _PeerPolicy> policies;
  final List<String> sendStartOrder = <String>[];
  final StreamController<void> _sendStarted =
      StreamController<void>.broadcast();

  int _inFlightSends = 0;
  int maxInFlightSends = 0;

  _ControlledP2PService({
    required super.peerId,
    required super.network,
    this.policies = const <String, _PeerPolicy>{},
  });

  Future<void> waitForSendCount(int count) async {
    while (sendStartOrder.length < count) {
      await _sendStarted.stream.first;
    }
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final policy = policies[targetPeerId] ?? const _PeerPolicy();
    sendStartOrder.add(targetPeerId);
    _inFlightSends++;
    if (_inFlightSends > maxInFlightSends) {
      maxInFlightSends = _inFlightSends;
    }
    _sendStarted.add(null);

    try {
      final gate = policy.sendGate;
      if (gate != null) {
        await gate.future;
      }
      return const SendMessageResult(sent: true, reply: 'received');
    } finally {
      _inFlightSends--;
    }
  }

  @override
  void dispose() {
    _sendStarted.close();
    super.dispose();
  }
}

class _PeerPolicy {
  final Completer<void>? sendGate;

  const _PeerPolicy({this.sendGate});
}
