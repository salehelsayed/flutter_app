import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
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
  );
}

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

  setUp(() {
    p2pService = FakeP2PService();
    posts = InMemoryPostRepository();
    contacts = FakeContactRepository();
    retrier = PendingPostDeliveryRetrier(
      p2pService: p2pService,
      postRepo: posts,
      contactRepo: contacts,
      bridge: FakeBridge(),
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
        bridge: FakeBridge(),
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
}

class _RecordingFakeP2PService extends FakeP2PService {
  final List<String> orderLog = <String>[];

  _RecordingFakeP2PService()
    : super(
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
