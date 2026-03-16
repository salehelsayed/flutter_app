import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_reaction_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

const _senderPeerId = 'peer-bob';
const _resolvedRecipientPeerIds = <String>{'peer-alice', 'peer-cara', 'peer-drew'};

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

PostModel _post(String postId) {
  return PostModel(
    id: postId,
    eventId: 'evt-$postId',
    senderPeerId: 'peer-alice',
    authorPeerId: 'peer-alice',
    authorUsername: 'Alice',
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    isIncoming: false,
  );
}

void main() {
  late FakeP2PNetwork network;
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;

  setUp(() {
    network = FakeP2PNetwork();
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    contacts.addTestContact(_contact('peer-alice', 'Alice'));
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-cara', 'Cara'));
    contacts.addTestContact(_contact('peer-drew', 'Drew'));
  });

  tearDown(() {
    posts.dispose();
  });

  test('sendPostReaction uses bounded concurrent fanout when configured', () async {
    await _seedPostWithDeliveries(posts);
    final service = _createControlledService(network);
    addTearDown(service.dispose);

    final sendFuture = sendPostReaction(
      p2pService: service,
      postRepo: posts,
      contactRepo: contacts,
      postId: 'post-1',
      senderPeerId: _senderPeerId,
      isActive: true,
      maxConcurrentRecipients: 2,
    );

    await _assertBoundedStart(service);
    service.releaseOneStartedRecipient();
    await _assertAllRecipientsStarted(service);
    service.releaseAllRecipients();

    final (result, reaction) = await sendFuture;
    expect(result, SendPostReactionResult.success);
    expect(reaction, isNotNull);
  });

  test('sendPostComment uses bounded concurrent fanout when configured', () async {
    await _seedPostWithDeliveries(posts);
    final service = _createControlledService(network);
    addTearDown(service.dispose);

    final sendFuture = sendPostComment(
      p2pService: service,
      postRepo: posts,
      contactRepo: contacts,
      postId: 'post-1',
      senderPeerId: _senderPeerId,
      senderUsername: 'Bob',
      body: 'I can lend one.',
      maxConcurrentRecipients: 2,
    );

    await _assertBoundedStart(service);
    service.releaseOneStartedRecipient();
    await _assertAllRecipientsStarted(service);
    service.releaseAllRecipients();

    final (result, comment) = await sendFuture;
    expect(result, SendPostCommentResult.success);
    expect(comment, isNotNull);
  });

  test(
    'sendPostCommentReaction uses bounded concurrent fanout when configured',
    () async {
      await _seedPostWithDeliveries(posts);
      await posts.saveComment(
        const PostCommentModel(
          id: 'comment-1',
          eventId: 'evt-comment-1',
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          authorUsername: 'Alice',
          body: 'I can lend one.',
          commentedAt: '2026-03-15T11:00:00.000Z',
        ),
      );
      final service = _createControlledService(network);
      addTearDown(service.dispose);

      final sendFuture = sendPostCommentReaction(
        p2pService: service,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        commentId: 'comment-1',
        senderPeerId: _senderPeerId,
        isActive: true,
        maxConcurrentRecipients: 2,
      );

      await _assertBoundedStart(service);
      service.releaseOneStartedRecipient();
      await _assertAllRecipientsStarted(service);
      service.releaseAllRecipients();

      final (result, reaction) = await sendFuture;
      expect(result, SendPostCommentReactionResult.success);
      expect(reaction, isNotNull);
    },
  );
}

Future<void> _seedPostWithDeliveries(InMemoryPostRepository posts) async {
  await posts.savePost(_post('post-1'));
  for (final delivery in const <PostRecipientDelivery>[
    PostRecipientDelivery(
      postId: 'post-1',
      recipientPeerId: 'peer-bob',
      deliveryStatus: 'delivered',
      lastAttemptAt: '2026-03-15T10:15:31.000Z',
      deliveryPath: 'direct',
      createdAt: '2026-03-15T10:15:31.000Z',
      updatedAt: '2026-03-15T10:15:31.000Z',
    ),
    PostRecipientDelivery(
      postId: 'post-1',
      recipientPeerId: 'peer-cara',
      deliveryStatus: 'delivered',
      lastAttemptAt: '2026-03-15T10:15:31.000Z',
      deliveryPath: 'direct',
      createdAt: '2026-03-15T10:15:31.000Z',
      updatedAt: '2026-03-15T10:15:31.000Z',
    ),
    PostRecipientDelivery(
      postId: 'post-1',
      recipientPeerId: 'peer-drew',
      deliveryStatus: 'inbox',
      lastAttemptAt: '2026-03-15T10:15:31.000Z',
      deliveryPath: 'inbox',
      createdAt: '2026-03-15T10:15:31.000Z',
      updatedAt: '2026-03-15T10:15:31.000Z',
    ),
  ]) {
    await posts.saveRecipientDelivery(delivery);
  }
}

_ControlledP2PService _createControlledService(FakeP2PNetwork network) {
  final sendGates = <String, Completer<void>>{
    for (final peerId in _resolvedRecipientPeerIds) peerId: Completer<void>(),
  };
  return _ControlledP2PService(
    peerId: _senderPeerId,
    network: network,
    sendGates: sendGates,
  );
}

Future<void> _assertBoundedStart(_ControlledP2PService service) async {
  await service.waitForSendCount(2);
  await _drainMicrotasks();

  expect(service.maxInFlightSends, 2);
  expect(service.sendStartOrder.take(2).toSet(), hasLength(2));
  expect(
    service.sendStartOrder.take(2).toSet().difference(_resolvedRecipientPeerIds),
    isEmpty,
  );
}

Future<void> _assertAllRecipientsStarted(_ControlledP2PService service) async {
  await service.waitForSendCount(3);
  await _drainMicrotasks();

  expect(service.maxInFlightSends, 2);
  expect(service.sendStartOrder.toSet(), _resolvedRecipientPeerIds);
}

Future<void> _drainMicrotasks([int turns = 3]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ControlledP2PService extends FakeP2PService {
  final Map<String, Completer<void>> sendGates;
  final List<String> sendStartOrder = <String>[];
  final StreamController<void> _sendStarted =
      StreamController<void>.broadcast();

  int _inFlightSends = 0;
  int maxInFlightSends = 0;

  _ControlledP2PService({
    required super.peerId,
    required super.network,
    required this.sendGates,
  });

  Future<void> waitForSendCount(int count) async {
    while (sendStartOrder.length < count) {
      await _sendStarted.stream.first;
    }
  }

  void releaseOneStartedRecipient() {
    for (final recipientPeerId in sendStartOrder) {
      final gate = sendGates[recipientPeerId];
      if (gate != null && !gate.isCompleted) {
        gate.complete();
        return;
      }
    }
    fail('No started recipient remained blocked.');
  }

  void releaseAllRecipients() {
    for (final gate in sendGates.values) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendStartOrder.add(targetPeerId);
    _inFlightSends++;
    if (_inFlightSends > maxInFlightSends) {
      maxInFlightSends = _inFlightSends;
    }
    _sendStarted.add(null);

    try {
      final gate = sendGates[targetPeerId];
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
