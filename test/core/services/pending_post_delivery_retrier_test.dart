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
    createdAt: '2026-03-15T10:00:00.000Z',
    visibleAt: '2026-03-15T10:00:00.000Z',
    expiresAt: '2026-03-18T10:00:00.000Z',
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
      final recordingP2PService = _RecordingFakeP2PService();
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
    'offline to online transition retries queued repost deliveries through the post delivery retrier',
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

      expect(p2pService.sendMessageWithReplyCallCount, 1);
      expect(bridge.commandLog, contains('message.encrypt'));
      final deliveries = await posts.getPostPassRecipientDeliveries(
        pass.passId,
      );
      expect(deliveries, hasLength(1));
      expect(deliveries.single.deliveryStatus, 'delivered');
      expect(await posts.loadRetryableOutgoingPostPasses(), isEmpty);
      expect(
        (await posts.loadPostPasses('post-pass-source')).single.deliveryStatus,
        'sent',
      );
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    },
  );

  test(
    'offline to online transition retries queued repost deliveries with the post-create concurrency cap of 25',
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
      retrier = PendingPostDeliveryRetrier(
        p2pService: controlledP2PService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        retryDebounce: Duration.zero,
        periodicRetryInterval: const Duration(hours: 1),
      );

      await posts.savePost(_post(id: 'post-pass-25', deliveryStatus: 'sent'));
      await posts.savePostPass(
        const PostPassModel(
          passId: 'pass-25',
          eventId: 'evt-pass-25',
          postId: 'post-pass-25',
          senderPeerId: 'peer-self',
          passerPeerId: 'peer-self',
          passerUsername: 'Alice',
          passedAt: '2026-03-15T10:00:02.000Z',
          createdAt: '2026-03-15T10:00:02.000Z',
          isIncoming: false,
          deliveryStatus: 'failed',
        ),
      );

      contacts.seed(
        recipientPeerIds.map((peerId) => _contact(peerId, peerId)).toList(),
      );
      for (final peerId in recipientPeerIds) {
        await posts.saveRecipientDelivery(
          PostRecipientDelivery(
            postId: 'post-pass-25',
            deliveryOwnerKind: postRecipientDeliveryOwnerKindPass,
            deliveryOwnerId: 'pass-25',
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

      final deliveries = await posts.getPostPassRecipientDeliveries('pass-25');
      expect(deliveries, hasLength(30));
      expect(
        deliveries.every((delivery) => delivery.deliveryStatus == 'delivered'),
        isTrue,
      );
      expect(
        bridge.commandLog.where((command) => command == 'message.encrypt'),
        hasLength(30),
      );
      expect(
        (await posts.loadPostPasses('post-pass-25')).single.deliveryStatus,
        'sent',
      );
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
