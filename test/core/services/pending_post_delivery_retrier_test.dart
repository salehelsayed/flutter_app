import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../bridge/fake_bridge.dart';
import 'fake_p2p_service.dart';
import '../../shared/fakes/in_memory_post_repository.dart';

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

const DiscoveredPeer _discoverablePeer = DiscoveredPeer(
  id: 'discoverable-peer',
  addresses: <String>['/dns4/example.invalid/tcp/443'],
);

PostModel _post({
  required String id,
  required String deliveryStatus,
  bool isIncoming = false,
}) {
  return PostModel(
    id: id,
    eventId: 'evt-$id',
    senderPeerId: 'peer-self',
    authorPeerId: 'peer-self',
    authorUsername: 'Alice',
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: DateTime.now().toUtc().toIso8601String(),
    visibleAt: DateTime.now().toUtc().toIso8601String(),
    expiresAt: DateTime.now()
        .toUtc()
        .add(const Duration(hours: 24))
        .toIso8601String(),
    isIncoming: isIncoming,
    deliveryStatus: deliveryStatus,
  );
}

void main() {
  late FakeP2PService p2pService;
  late InMemoryPostRepository posts;
  late FakeContactRepository contacts;
  late PendingPostDeliveryRetrier retrier;
  late PassthroughCryptoBridge bridge;

  setUp(() {
    p2pService = FakeP2PService(discoverPeerResult: _discoverablePeer);
    posts = InMemoryPostRepository();
    contacts = FakeContactRepository();
    bridge = PassthroughCryptoBridge();
    retrier = PendingPostDeliveryRetrier(
      p2pService: p2pService,
      postRepo: posts,
      contactRepo: contacts,
      bridge: bridge,
      retryDebounce: Duration.zero,
      periodicRetryInterval: const Duration(hours: 1),
    );
  });

  tearDown(() {
    retrier.dispose();
    p2pService.dispose();
    posts.dispose();
  });

  Future<void> seedKeylessThought() async {
    contacts.seed([_contact('peer-bob', 'Bob').copyWith(mlKemPublicKey: '')]);
    await posts.savePost(_post(id: 'key-waiting', deliveryStatus: 'partial'));
    await posts.saveRecipientDelivery(
      const PostRecipientDelivery(
        postId: 'key-waiting',
        recipientPeerId: 'peer-bob',
        deliveryStatus: 'failed',
        deliveryPath: 'failed',
        lastAttemptAt: '2026-03-15T10:00:01.000Z',
        createdAt: '2026-03-15T10:00:01.000Z',
        updatedAt: '2026-03-15T10:00:01.000Z',
      ),
    );
    p2pService.emitState(
      const NodeState(
        isStarted: true,
        peerId: 'peer-self',
        circuitAddresses: ['/p2p-circuit/addr1'],
      ),
    );
  }

  test('BL23 key arrival retries failed Thought within debounce without duplicates', () async {
    await seedKeylessThought();
    final keys = StreamController<void>.broadcast(sync: true);
    addTearDown(keys.close);
    retrier.dispose();
    retrier = PendingPostDeliveryRetrier(
      p2pService: p2pService,
      postRepo: posts,
      contactRepo: contacts,
      bridge: bridge,
      contactKeyUpdatedSignal: keys.stream,
      retryDebounce: const Duration(milliseconds: 10),
      periodicRetryInterval: const Duration(minutes: 5),
    );
    retrier.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(p2pService.sendMessageWithReplyCallCount, 0);
    expect(p2pService.storeInInboxCallCount, 0);
    expect(
      (await posts.getRecipientDeliveries('key-waiting')).single.deliveryStatus,
      'failed',
    );
    contacts.seed([_contact('peer-bob', 'Bob')]);
    keys.add(null);
    keys.add(null);
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while ((await posts.getPost('key-waiting'))!.deliveryStatus != 'sent' &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect((await posts.getPost('key-waiting'))!.deliveryStatus, 'sent');
    expect(p2pService.storeInInboxCallCount, 1);
    expect(p2pService.lastStoreInInboxPeerId, 'peer-bob');
    expect(p2pService.sendMessageWithReplyCallCount, 0);
  });

  test('BL23 disposed retrier ignores key arrivals', () async {
    await seedKeylessThought();
    final keys = StreamController<void>.broadcast(sync: true);
    addTearDown(keys.close);
    retrier.dispose();
    retrier = PendingPostDeliveryRetrier(
      p2pService: p2pService,
      postRepo: posts,
      contactRepo: contacts,
      bridge: bridge,
      contactKeyUpdatedSignal: keys.stream,
      retryDebounce: const Duration(milliseconds: 10),
    );
    retrier.start();
    retrier.dispose();
    contacts.seed([_contact('peer-bob', 'Bob')]);
    keys.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(p2pService.sendMessageWithReplyCallCount, 0);
    expect(p2pService.storeInInboxCallCount, 0);
    expect(
      (await posts.getRecipientDeliveries('key-waiting')).single.deliveryStatus,
      'failed',
    );
  });

  test('BL23 key and resume requests coalesce behind an active retry', () async {
    await seedKeylessThought();
    final keys = StreamController<void>.broadcast(sync: true);
    addTearDown(keys.close);
    final entered = Completer<void>();
    final release = Completer<void>();
    var passes = 0;
    retrier.dispose();
    retrier = PendingPostDeliveryRetrier(
      p2pService: p2pService, postRepo: posts, contactRepo: contacts, bridge: bridge,
      contactKeyUpdatedSignal: keys.stream,
      retryDebounce: const Duration(milliseconds: 10),
      beforeRetry: () async {
        passes++;
        if (passes == 1) {
          entered.complete();
          await release.future;
        }
        return 0;
      },
    );
    retrier.start();
    await entered.future.timeout(const Duration(seconds: 1));
    contacts.seed([_contact('peer-bob', 'Bob')]);
    keys.add(null);
    keys.add(null);
    await retrier.retryNow();
    await retrier.retryNow();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(passes, 1);
    expect(p2pService.sendMessageWithReplyCallCount, 0);
    expect(p2pService.storeInInboxCallCount, 0);
    release.complete();
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (passes < 2 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(passes, 2);
    expect((await posts.getPost('key-waiting'))!.deliveryStatus, 'sent');
    expect(p2pService.storeInInboxCallCount, 1);
    expect(p2pService.lastStoreInInboxPeerId, 'peer-bob');
    expect(p2pService.sendMessageWithReplyCallCount, 0);
  });

  test('BL23 dispose clears a retry queued behind an active pass', () async {
    await seedKeylessThought();
    final entered = Completer<void>();
    final release = Completer<void>();
    var passes = 0;
    retrier.dispose();
    retrier = PendingPostDeliveryRetrier(
      p2pService: p2pService, postRepo: posts, contactRepo: contacts, bridge: bridge,
      retryDebounce: Duration.zero,
      beforeRetry: () async {
        passes++;
        entered.complete();
        await release.future;
        return 0;
      },
    );
    final active = retrier.retryNow();
    await entered.future;
    await retrier.retryNow();
    retrier.dispose();
    contacts.seed([_contact('peer-bob', 'Bob')]);
    release.complete();
    await active;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(passes, 1);
    expect(p2pService.sendMessageWithReplyCallCount, 0);
    expect(p2pService.storeInInboxCallCount, 0);
  });

  for (final exclusion in ['blocked', 'archived', 'expired']) {
    test('BL23 key event preserves $exclusion exclusion', () async {
      await seedKeylessThought();
      if (exclusion == 'expired') {
        final post = (await posts.getPost('key-waiting'))!;
        await posts.savePost(post.copyWith(
          createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 25)).toIso8601String(),
        ));
      }
      final keys = StreamController<void>.broadcast(sync: true);
      addTearDown(keys.close);
      var passes = 0;
      retrier.dispose();
      retrier = PendingPostDeliveryRetrier(
        p2pService: p2pService, postRepo: posts, contactRepo: contacts, bridge: bridge,
        contactKeyUpdatedSignal: keys.stream,
        retryDebounce: const Duration(milliseconds: 10),
        beforeRetry: () async { passes++; return 0; },
      );
      retrier.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      contacts.seed([_contact('peer-bob', 'Bob').copyWith(
        isBlocked: exclusion == 'blocked', isArchived: exclusion == 'archived',
      )]);
      keys.add(null);
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (passes < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(passes, 2);
      expect(p2pService.sendMessageWithReplyCallCount, 0);
    expect(p2pService.storeInInboxCallCount, 0);
      expect((await posts.getRecipientDeliveries('key-waiting')).single.deliveryStatus, 'failed');
    });
  }

  test(
    'offline to online transition retries outgoing post deliveries',
    () async {
      contacts.seed(<ContactModel>[_contact('peer-bob', 'Bob')]);
      await posts.savePost(_post(id: 'post-1', deliveryStatus: 'failed'));
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'failed',
          lastAttemptAt: '2026-03-15T10:00:01.000Z',
          deliveryPath: 'failed',
          createdAt: '2026-03-15T10:00:01.000Z',
          updatedAt: '2026-03-15T10:00:01.000Z',
        ),
      );

      retrier.start();
      p2pService.emitState(
        const NodeState(
          isStarted: true,
          peerId: 'peer-self',
          circuitAddresses: <String>['/p2p-circuit/addr1'],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final post = await posts.getPost('post-1');
      expect(post, isNotNull);
      expect(post!.deliveryStatus, 'sent');
    },
  );

  test(
    'account migration gate blocks delivery retry before beforeRetry and network work',
    () async {
      contacts.seed(<ContactModel>[_contact('peer-bob', 'Bob')]);
      await posts.savePost(_post(id: 'post-blocked', deliveryStatus: 'failed'));
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-blocked',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'failed',
          lastAttemptAt: '2026-03-15T10:00:01.000Z',
          deliveryPath: 'failed',
          createdAt: '2026-03-15T10:00:01.000Z',
          updatedAt: '2026-03-15T10:00:01.000Z',
        ),
      );
      p2pService.emitState(
        const NodeState(
          isStarted: true,
          peerId: 'peer-self',
          circuitAddresses: <String>['/p2p-circuit/addr1'],
        ),
      );
      var beforeRetryCalls = 0;
      var gateCalls = 0;
      retrier = PendingPostDeliveryRetrier(
        p2pService: p2pService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        retryDebounce: Duration.zero,
        periodicRetryInterval: const Duration(hours: 1),
        beforeRetry: () async {
          beforeRetryCalls++;
          return 1;
        },
        accountMigrationNetworkGate:
            ({String? peerId, required String operation}) async {
              gateCalls++;
              expect(peerId, 'peer-self');
              expect(operation, 'pending_post_delivery_retry');
              return false;
            },
      );

      final retried = await retrier.retryNow();

      expect(retried, 0);
      expect(gateCalls, 1);
      expect(beforeRetryCalls, 0);
      expect(p2pService.sendMessageWithReplyCallCount, 0);
      expect(bridge.commandLog, isNot(contains('message.encrypt')));
      expect((await posts.getPost('post-blocked'))!.deliveryStatus, 'failed');
    },
  );

  test('does not retry incoming posts', () async {
    contacts.seed(<ContactModel>[_contact('peer-bob', 'Bob')]);
    await posts.savePost(
      _post(id: 'post-incoming', deliveryStatus: 'failed', isIncoming: true),
    );
    await posts.saveRecipientDelivery(
      const PostRecipientDelivery(
        postId: 'post-incoming',
        recipientPeerId: 'peer-bob',
        deliveryStatus: 'failed',
        lastAttemptAt: '2026-03-15T10:00:01.000Z',
        deliveryPath: 'failed',
        createdAt: '2026-03-15T10:00:01.000Z',
        updatedAt: '2026-03-15T10:00:01.000Z',
      ),
    );

    retrier.start();
    p2pService.emitState(
      const NodeState(
        isStarted: true,
        peerId: 'peer-self',
        circuitAddresses: <String>['/p2p-circuit/addr1'],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(p2pService.sendMessageWithReplyCallCount, 0);
    expect((await posts.getPost('post-incoming'))!.deliveryStatus, 'failed');
  });

  test(
    'reconnect runs media recovery before post-create delivery retry',
    () async {
      final recordingP2PService = _RecordingFakeP2PService()
        ..isConnectedToPeerResult = true;
      final orderLog = recordingP2PService.orderLog;
      contacts.seed(<ContactModel>[_contact('peer-bob', 'Bob')]);
      await posts.savePost(_post(id: 'post-ordered', deliveryStatus: 'failed'));
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-ordered',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'failed',
          lastAttemptAt: '2026-03-15T10:00:01.000Z',
          deliveryPath: 'failed',
          createdAt: '2026-03-15T10:00:01.000Z',
          updatedAt: '2026-03-15T10:00:01.000Z',
        ),
      );

      retrier = PendingPostDeliveryRetrier(
        p2pService: recordingP2PService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        retryDebounce: Duration.zero,
        periodicRetryInterval: const Duration(hours: 1),
        beforeRetry: () async {
          orderLog.add('media');
          return 1;
        },
      );

      retrier.start();
      recordingP2PService.emitState(
        const NodeState(
          isStarted: true,
          peerId: 'peer-self',
          circuitAddresses: <String>['/p2p-circuit/addr1'],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(orderLog, isNotEmpty);
      expect(orderLog.first, 'media');
      expect(orderLog, contains('delivery'));
      expect((await posts.getPost('post-ordered'))!.deliveryStatus, 'sent');
    },
  );

  test(
    'offline to online transition leaves legacy repost deliveries unchanged',
    () async {
      contacts.seed(<ContactModel>[_contact('peer-bob', 'Bob')]);
      await posts.savePost(
        _post(
          id: 'post-pass-source',
          deliveryStatus: 'available',
          isIncoming: true,
        ).copyWith(authorUsername: 'Bob'),
      );
      const pass = PostPassModel(
        passId: 'pass-1',
        eventId: 'evt-pass-1',
        postId: 'post-pass-source',
        senderPeerId: 'peer-self',
        passerPeerId: 'peer-self',
        passerUsername: 'Alice',
        passedAt: '2026-03-15T10:00:02.000Z',
        createdAt: '2026-03-15T10:00:02.000Z',
        isIncoming: false,
        deliveryStatus: 'failed',
      );
      await posts.savePostPass(pass);
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-pass-source',
          deliveryOwnerKind: postRecipientDeliveryOwnerKindPass,
          deliveryOwnerId: 'pass-1',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'failed',
          lastAttemptAt: '2026-03-15T10:00:03.000Z',
          deliveryPath: 'failed',
          createdAt: '2026-03-15T10:00:02.000Z',
          updatedAt: '2026-03-15T10:00:03.000Z',
        ),
      );

      retrier.start();
      p2pService.emitState(
        const NodeState(
          isStarted: true,
          peerId: 'peer-self',
          circuitAddresses: <String>['/p2p-circuit/addr1'],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(p2pService.sendMessageWithReplyCallCount, 0);
      expect(bridge.commandLog, isNot(contains('message.encrypt')));
      final deliveries = await posts.getPostPassRecipientDeliveries(
        pass.passId,
      );
      expect(deliveries, hasLength(1));
      expect(deliveries.single.deliveryStatus, 'failed');
      expect(await posts.loadRetryableOutgoingPostPasses(), hasLength(1));
      expect(
        (await posts.loadPostPasses('post-pass-source')).single.deliveryStatus,
        'failed',
      );
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    },
  );

  test(
    'offline to online transition retries thoughts with the concurrency cap of 25',
    () async {
      final recipientPeerIds = List<String>.generate(
        30,
        (index) => 'peer-${index.toString().padLeft(2, '0')}',
      );
      final sendGates = <String, Completer<void>>{
        for (final peerId in recipientPeerIds) peerId: Completer<void>(),
      };
      final controlledP2PService = _ControlledRetryP2PService(
        initialState: NodeState.stopped,
        policies: {
          for (final peerId in recipientPeerIds)
            peerId: _RetryPeerPolicy(sendGate: sendGates[peerId]),
        },
      );
      p2pService.dispose();
      p2pService = controlledP2PService;
      controlledP2PService.isConnectedToPeerResult = true;
      retrier = PendingPostDeliveryRetrier(
        p2pService: controlledP2PService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        retryDebounce: Duration.zero,
        periodicRetryInterval: const Duration(hours: 1),
      );

      await posts.savePost(_post(id: 'post-pass-25', deliveryStatus: 'failed'));

      contacts.seed(
        recipientPeerIds.map((peerId) => _contact(peerId, peerId)).toList(),
      );
      for (final peerId in recipientPeerIds) {
        await posts.saveRecipientDelivery(
          PostRecipientDelivery(
            postId: 'post-pass-25',
            recipientPeerId: peerId,
            deliveryStatus: 'failed',
            lastAttemptAt: '2026-03-15T10:00:03.000Z',
            deliveryPath: 'failed',
            createdAt: '2026-03-15T10:00:02.000Z',
            updatedAt: '2026-03-15T10:00:03.000Z',
          ),
        );
      }

      retrier.start();
      controlledP2PService.emitState(
        const NodeState(
          isStarted: true,
          peerId: 'peer-self',
          circuitAddresses: <String>['/p2p-circuit/addr1'],
        ),
      );

      await controlledP2PService
          .waitForSendCount(25)
          .timeout(const Duration(milliseconds: 200));

      expect(controlledP2PService.maxInFlightSends, 25);
      expect(
        controlledP2PService.sendStartOrder,
        recipientPeerIds.take(25).toList(),
      );

      sendGates[recipientPeerIds.first]!.complete();
      await controlledP2PService
          .waitForSendCount(26)
          .timeout(const Duration(milliseconds: 200));

      expect(controlledP2PService.maxInFlightSends, 25);
      expect(
        controlledP2PService.sendStartOrder,
        recipientPeerIds.take(26).toList(),
      );

      for (final gate in sendGates.values) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final deliveries = await posts.getRecipientDeliveries('post-pass-25');
      expect(deliveries, hasLength(30));
      expect(
        deliveries.every((delivery) => delivery.deliveryStatus == 'delivered'),
        isTrue,
      );
      expect(
        bridge.commandLog.where((command) => command == 'message.encrypt'),
        hasLength(30),
      );
      expect((await posts.getPost('post-pass-25'))!.deliveryStatus, 'sent');
      expect(controlledP2PService.maxInFlightSends, 25);
    },
  );
}

class _RecordingFakeP2PService extends FakeP2PService {
  final List<String> orderLog = <String>[];

  _RecordingFakeP2PService()
    : super(
        discoverPeerResult: _discoverablePeer,
        sendMessageWithReplyResult: const SendMessageResult(
          sent: true,
          reply: 'ack',
        ),
      );

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    orderLog.add('delivery');
    return super.sendMessageWithReply(peerId, message, timeoutMs: timeoutMs);
  }
}

class _ControlledRetryP2PService extends FakeP2PService {
  final Map<String, _RetryPeerPolicy> policies;
  final List<String> sendStartOrder = <String>[];
  final StreamController<void> _sendStarted =
      StreamController<void>.broadcast();

  int _inFlightSends = 0;
  int maxInFlightSends = 0;

  _ControlledRetryP2PService({
    super.initialState,
    this.policies = const <String, _RetryPeerPolicy>{},
  }) : super(discoverPeerResult: _discoverablePeer);

  Future<void> waitForSendCount(int count) async {
    while (sendStartOrder.length < count) {
      await _sendStarted.stream.first;
    }
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    final policy = policies[peerId] ?? const _RetryPeerPolicy();
    sendStartOrder.add(peerId);
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
      return const SendMessageResult(sent: true, reply: 'ack');
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

class _RetryPeerPolicy {
  final Completer<void>? sendGate;

  const _RetryPeerPolicy({this.sendGate});
}
