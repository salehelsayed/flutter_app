import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/test_user.dart';

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

void main() {
  late FakeP2PNetwork network;
  late _RecordingPostRepository posts;
  late InMemoryContactRepository contacts;

  setUp(() {
    network = FakeP2PNetwork();
    posts = _RecordingPostRepository();
    contacts = InMemoryContactRepository();
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'execute updates recipient rows as results arrive and recomputes post status after each update',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      contacts.addTestContact(_contact('peer-cara', 'Cara'));
      FakeP2PService(peerId: 'peer-bob', network: network);
      final aliceService = _PolicyFakeP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-cara': _PeerPolicy(
            sendResult: false,
            storeInInboxResult: false,
          ),
        },
      );

      final created = await _createLocalPost(
        posts: posts,
        contacts: contacts,
        recipientPeerIds: const ['peer-bob', 'peer-cara'],
      );
      posts.clearWriteLog();

      final (result, post) = await PostDeliveryRunner(
        p2pService: aliceService,
        postRepo: posts,
      ).execute(created);

      expect(result, SendPostResult.partialSuccess);
      expect(post.deliveryStatus, 'partial');
      expect(posts.writeLog, hasLength(4));
      expect(posts.writeLog[1], 'post:sending');
      expect(posts.writeLog[3], 'post:partial');
      expect(
        <String>{posts.writeLog[0], posts.writeLog[2]},
        <String>{'delivery:peer-bob:delivered', 'delivery:peer-cara:failed'},
      );

      final deliveries = await posts.getRecipientDeliveries(post.id);
      expect(
        deliveries.map(
          (entry) => '${entry.recipientPeerId}:${entry.deliveryStatus}',
        ),
        <String>['peer-bob:delivered', 'peer-cara:failed'],
      );
    },
  );

  test('execute marks post sent when all recipients succeed', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-cara', 'Cara'));
    FakeP2PService(peerId: 'peer-bob', network: network);
    final aliceService = FakeP2PService(peerId: 'peer-alice', network: network);

    final created = await _createLocalPost(
      posts: posts,
      contacts: contacts,
      recipientPeerIds: const ['peer-bob', 'peer-cara'],
    );

    final (result, post) = await PostDeliveryRunner(
      p2pService: aliceService,
      postRepo: posts,
    ).execute(created);

    expect(result, SendPostResult.success);
    expect(post.deliveryStatus, 'sent');

    final deliveries = await posts.getRecipientDeliveries(post.id);
    expect(
      deliveries.map(
        (entry) => '${entry.recipientPeerId}:${entry.deliveryStatus}',
      ),
      <String>['peer-bob:delivered', 'peer-cara:inbox'],
    );
    expect(network.inboxCount('peer-cara'), 1);
  });

  test('execute marks post failed when all recipients fail', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-cara', 'Cara'));
    final aliceService = _PolicyFakeP2PService(
      peerId: 'peer-alice',
      network: network,
      policies: const {
        'peer-bob': _PeerPolicy(sendResult: false, storeInInboxResult: false),
        'peer-cara': _PeerPolicy(sendResult: false, storeInInboxResult: false),
      },
    );

    final created = await _createLocalPost(
      posts: posts,
      contacts: contacts,
      recipientPeerIds: const ['peer-bob', 'peer-cara'],
    );

    final (result, post) = await PostDeliveryRunner(
      p2pService: aliceService,
      postRepo: posts,
    ).execute(created);

    expect(result, SendPostResult.sendFailed);
    expect(post.deliveryStatus, 'failed');

    final deliveries = await posts.getRecipientDeliveries(post.id);
    expect(
      deliveries.every((entry) => entry.deliveryStatus == 'failed'),
      isTrue,
    );
  });

  test(
    'execute catches internal exceptions and persists terminal post failure',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final aliceService = _PolicyFakeP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': _PeerPolicy(sendResult: false, throwOnInbox: true),
        },
      );

      final created = await _createLocalPost(
        posts: posts,
        contacts: contacts,
        recipientPeerIds: const ['peer-bob'],
      );

      final (result, post) = await PostDeliveryRunner(
        p2pService: aliceService,
        postRepo: posts,
      ).execute(created);

      expect(result, SendPostResult.sendFailed);
      expect(post.deliveryStatus, 'failed');

      final storedPost = await posts.getPost(post.id);
      expect(storedPost, isNotNull);
      expect(storedPost!.deliveryStatus, 'failed');
    },
  );

  test('execute does not write conversation messages', () async {
    final bob = TestUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
      withReactions: true,
    );
    addTearDown(bob.dispose);
    bob.start();
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    final aliceService = FakeP2PService(peerId: 'peer-alice', network: network);

    final created = await _createLocalPost(
      posts: posts,
      contacts: contacts,
      recipientPeerIds: const ['peer-bob'],
    );

    final (result, _) = await PostDeliveryRunner(
      p2pService: aliceService,
      postRepo: posts,
    ).execute(created);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(result, SendPostResult.success);
    expect(bob.messageRepo.count, 0);
  });

  test('PostDeliveryRunner stays widget agnostic', () async {
    final source = await File(
      'lib/features/posts/application/post_delivery_runner.dart',
    ).readAsString();

    expect(source, isNot(contains('package:flutter/')));
    expect(source, isNot(contains('BuildContext')));
    expect(source, isNot(contains('StatefulWidget')));
    expect(source, isNot(contains('setState(')));
  });
}

Future<CreatedLocalPost> _createLocalPost({
  required _RecordingPostRepository posts,
  required InMemoryContactRepository contacts,
  required List<String> recipientPeerIds,
}) async {
  final (result, created) = await createLocalPost(
    postRepo: posts,
    contactRepo: contacts,
    senderPeerId: 'peer-alice',
    senderUsername: 'Alice',
    text: 'Hello from Posts',
    audience: PostAudience.pickPeople(recipientPeerIds),
  );

  expect(result, SendPostResult.success);
  expect(created, isNotNull);
  return created!;
}

class _RecordingPostRepository extends InMemoryPostRepository {
  final List<String> writeLog = <String>[];

  @override
  Future<void> savePost(PostModel post) async {
    writeLog.add('post:${post.deliveryStatus}');
    await super.savePost(post);
  }

  @override
  Future<void> saveRecipientDelivery(PostRecipientDelivery delivery) async {
    writeLog.add(
      'delivery:${delivery.recipientPeerId}:${delivery.deliveryStatus}',
    );
    await super.saveRecipientDelivery(delivery);
  }

  void clearWriteLog() {
    writeLog.clear();
  }
}

class _PolicyFakeP2PService extends FakeP2PService {
  final Map<String, _PeerPolicy> policies;

  _PolicyFakeP2PService({
    required super.peerId,
    required super.network,
    this.policies = const <String, _PeerPolicy>{},
  });

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final policy = policies[targetPeerId];
    if (policy?.throwOnSend == true) {
      throw StateError('send failed for $targetPeerId');
    }
    if (policy?.sendResult != null) {
      final sent = policy!.sendResult!;
      return SendMessageResult(
        sent: sent,
        reply: sent ? 'received: $message' : null,
      );
    }
    return super.sendMessageWithReply(
      targetPeerId,
      message,
      timeoutMs: timeoutMs,
    );
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async {
    final policy = policies[toPeerId];
    if (policy?.throwOnInbox == true) {
      throw StateError('inbox failed for $toPeerId');
    }
    if (policy?.storeInInboxResult != null) {
      return policy!.storeInInboxResult!;
    }
    return super.storeInInbox(toPeerId, message);
  }
}

class _PeerPolicy {
  final bool? sendResult;
  final bool? storeInInboxResult;
  final bool throwOnSend;
  final bool throwOnInbox;

  const _PeerPolicy({
    this.sendResult,
    this.storeInInboxResult,
    this.throwOnSend = false,
    this.throwOnInbox = false,
  });
}
