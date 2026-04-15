import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../core/bridge/fake_bridge.dart';
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
    mlKemPublicKey: 'mlkem-$peerId',
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

  test(
    'execute discovers and dials recipients before direct post send',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      addTearDown(bobService.dispose);
      final aliceService = _PolicyFakeP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': _PeerPolicy(requireDiscoverAndDialBeforeSend: true),
        },
      );
      addTearDown(aliceService.dispose);

      final created = await _createLocalPost(
        posts: posts,
        contacts: contacts,
        recipientPeerIds: const ['peer-bob'],
      );

      final (result, post) = await PostDeliveryRunner(
        p2pService: aliceService,
        postRepo: posts,
      ).execute(created);

      expect(result, SendPostResult.success);
      expect(post.deliveryStatus, 'sent');
      expect(aliceService.discoverAttempts, <String>['peer-bob']);
      expect(aliceService.dialAttempts, <String>['peer-bob']);
      expect(network.inboxCount('peer-bob'), 0);

      final deliveries = await posts.getRecipientDeliveries(post.id);
      expect(deliveries.single.deliveryStatus, 'delivered');
      expect(deliveries.single.deliveryPath, 'direct');
    },
  );

  test(
    'executePostPass encrypts repost payloads for each recipient and persists sent status',
    () async {
      final bridge = PassthroughCryptoBridge();
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      contacts.addTestContact(_contact('peer-cara', 'Cara'));
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      addTearDown(bobService.dispose);
      final caraService = FakeP2PService(peerId: 'peer-cara', network: network);
      addTearDown(caraService.dispose);
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      addTearDown(aliceService.dispose);

      const pass = PostPassModel(
        passId: 'pass-enc-1',
        eventId: 'evt-pass-enc-1',
        postId: 'post-pass-source',
        senderPeerId: 'peer-alice',
        passerPeerId: 'peer-alice',
        passerUsername: 'Alice',
        passedAt: '2026-03-15T10:00:02.000Z',
        createdAt: '2026-03-15T10:00:02.000Z',
        isIncoming: false,
      );
      final snapshotPost = _post(
        id: 'post-pass-source',
        deliveryStatus: 'available',
        isIncoming: true,
      ).copyWith(authorPeerId: 'peer-bob', authorUsername: 'Bob');
      final receivedByBob = bobService.messageStream.first;
      final receivedByCara = caraService.messageStream.first;

      final (result, deliveredPass) =
          await PostDeliveryRunner(
            p2pService: aliceService,
            postRepo: posts,
            bridge: bridge,
          ).executePostPass(
            pass: pass,
            snapshotPost: snapshotPost,
            resolvedRecipients: const <CreatedLocalPostRecipient>[
              CreatedLocalPostRecipient(
                contact: ContactModel(
                  peerId: 'peer-bob',
                  publicKey: 'pk-peer-bob',
                  rendezvous: '/dns4/example.invalid/tcp/443',
                  username: 'Bob',
                  signature: 'sig-peer-bob',
                  scannedAt: '2026-03-15T10:00:00.000Z',
                  mlKemPublicKey: 'mlkem-peer-bob',
                ),
              ),
              CreatedLocalPostRecipient(
                contact: ContactModel(
                  peerId: 'peer-cara',
                  publicKey: 'pk-peer-cara',
                  rendezvous: '/dns4/example.invalid/tcp/443',
                  username: 'Cara',
                  signature: 'sig-peer-cara',
                  scannedAt: '2026-03-15T10:00:00.000Z',
                  mlKemPublicKey: 'mlkem-peer-cara',
                ),
              ),
            ],
          );

      expect(result, SendPostResult.success);
      expect(deliveredPass.deliveryStatus, 'sent');
      expect(
        bridge.commandLog.where((command) => command == 'message.encrypt'),
        hasLength(2),
      );

      final bobJson =
          jsonDecode(
                (await receivedByBob.timeout(
                  const Duration(seconds: 1),
                )).content,
              )
              as Map<String, dynamic>;
      final caraJson =
          jsonDecode(
                (await receivedByCara.timeout(
                  const Duration(seconds: 1),
                )).content,
              )
              as Map<String, dynamic>;
      expect(bobJson['version'], '2');
      expect(caraJson['version'], '2');
      expect(
        (bobJson['encrypted'] as Map<String, dynamic>)['ciphertext'],
        isNotEmpty,
      );
      expect(
        (caraJson['encrypted'] as Map<String, dynamic>)['ciphertext'],
        isNotEmpty,
      );
    },
  );

  test(
    'executePostPass marks the repost delivery failed instead of downgrading to plaintext when encryption is unavailable',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      addTearDown(aliceService.dispose);

      const pass = PostPassModel(
        passId: 'pass-fail-1',
        eventId: 'evt-pass-fail-1',
        postId: 'post-pass-fail',
        senderPeerId: 'peer-alice',
        passerPeerId: 'peer-alice',
        passerUsername: 'Alice',
        passedAt: '2026-03-15T10:00:02.000Z',
        createdAt: '2026-03-15T10:00:02.000Z',
        isIncoming: false,
      );
      final snapshotPost = _post(
        id: 'post-pass-fail',
        deliveryStatus: 'available',
        isIncoming: true,
      ).copyWith(authorPeerId: 'peer-bob', authorUsername: 'Bob');

      final (
        result,
        deliveredPass,
      ) = await PostDeliveryRunner(p2pService: aliceService, postRepo: posts)
          .executePostPass(
            pass: pass,
            snapshotPost: snapshotPost,
            resolvedRecipients: const <CreatedLocalPostRecipient>[
              CreatedLocalPostRecipient(
                contact: ContactModel(
                  peerId: 'peer-bob',
                  publicKey: 'pk-peer-bob',
                  rendezvous: '/dns4/example.invalid/tcp/443',
                  username: 'Bob',
                  signature: 'sig-peer-bob',
                  scannedAt: '2026-03-15T10:00:00.000Z',
                  mlKemPublicKey: 'mlkem-peer-bob',
                ),
              ),
            ],
          );

      expect(result, SendPostResult.sendFailed);
      expect(deliveredPass.deliveryStatus, 'failed');
      expect(network.deliverCallCount, 0);
      final deliveries = await posts.getPostPassRecipientDeliveries(
        pass.passId,
      );
      expect(deliveries, hasLength(1));
      expect(deliveries.single.deliveryStatus, 'failed');
      expect(deliveries.single.lastError, 'repost_encryption_unavailable');
    },
  );

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

PostModel _post({
  required String id,
  required String deliveryStatus,
  bool isIncoming = false,
}) {
  return PostModel(
    id: id,
    eventId: 'evt-$id',
    senderPeerId: 'peer-alice',
    authorPeerId: 'peer-alice',
    authorUsername: 'Alice',
    text: 'Hello from Posts',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:00:00.000Z',
    visibleAt: '2026-03-15T10:00:00.000Z',
    expiresAt: '2026-03-18T10:00:00.000Z',
    isIncoming: isIncoming,
    deliveryStatus: deliveryStatus,
  );
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
  final List<String> discoverAttempts = <String>[];
  final List<String> dialAttempts = <String>[];
  final Set<String> _dialedPeers = <String>{};

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
    if (policy?.requireDiscoverAndDialBeforeSend == true &&
        !_dialedPeers.contains(targetPeerId)) {
      return const SendMessageResult(sent: false);
    }
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
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    discoverAttempts.add(peerId);
    return DiscoveredPeer(
      id: peerId,
      addresses: <String>['/ip4/127.0.0.1/tcp/4001/p2p/$peerId'],
    );
  }

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async {
    dialAttempts.add(peerId);
    _dialedPeers.add(peerId);
    return true;
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message, {int? timeoutMs}) async {
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
  final bool requireDiscoverAndDialBeforeSend;

  const _PeerPolicy({
    this.sendResult,
    this.storeInInboxResult,
    this.throwOnSend = false,
    this.throwOnInbox = false,
    this.requireDiscoverAndDialBeforeSend = false,
  });
}
