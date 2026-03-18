import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../core/bridge/fake_bridge.dart';

ContactModel _contact(
  String peerId,
  String username, {
  String? mlKemPublicKey,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    mlKemPublicKey: mlKemPublicKey,
  );
}

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late FakeP2PNetwork network;

  setUp(() {
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    network = FakeP2PNetwork();
  });

  tearDown(() {
    posts.dispose();
  });

  test('execute uses the default concurrency cap of 25', () async {
    final recipientPeerIds = List<String>.generate(
      30,
      (index) => 'peer-${index.toString().padLeft(2, '0')}',
    );
    for (final peerId in recipientPeerIds) {
      contacts.addTestContact(_contact(peerId, peerId));
    }

    final sendGates = <String, Completer<void>>{
      for (final peerId in recipientPeerIds) peerId: Completer<void>(),
    };
    final service = _ControlledP2PService(
      peerId: 'peer-alice',
      network: network,
      policies: {
        for (final peerId in recipientPeerIds)
          peerId: _PeerPolicy(sendGate: sendGates[peerId]),
      },
    );
    addTearDown(service.dispose);

    final created = await _createLocalPost(
      posts: posts,
      contacts: contacts,
      recipientPeerIds: recipientPeerIds,
    );

    final runFuture = PostDeliveryRunner(
      p2pService: service,
      postRepo: posts,
    ).execute(created);

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

    final (result, post) = await runFuture;
    expect(result, SendPostResult.success);
    expect(post.deliveryStatus, 'sent');
    expect(service.maxInFlightSends, 25);
  });

  test('execute never exceeds the configured concurrency limit', () async {
    const recipientPeerIds = <String>[
      'peer-bob',
      'peer-cara',
      'peer-drew',
      'peer-erin',
    ];
    for (final peerId in recipientPeerIds) {
      contacts.addTestContact(_contact(peerId, peerId));
    }

    final sendGates = <String, Completer<void>>{
      for (final peerId in recipientPeerIds) peerId: Completer<void>(),
    };
    final service = _ControlledP2PService(
      peerId: 'peer-alice',
      network: network,
      policies: {
        for (final peerId in recipientPeerIds)
          peerId: _PeerPolicy(sendGate: sendGates[peerId]),
      },
    );
    addTearDown(service.dispose);

    final created = await _createLocalPost(
      posts: posts,
      contacts: contacts,
      recipientPeerIds: recipientPeerIds,
    );

    final runFuture = PostDeliveryRunner(
      p2pService: service,
      postRepo: posts,
      maxConcurrentRecipients: 2,
    ).execute(created);

    await service.waitForSendCount(2);
    await _drainMicrotasks();

    expect(service.maxInFlightSends, 2);
    expect(service.sendStartOrder, recipientPeerIds.take(2).toList());

    sendGates['peer-bob']!.complete();
    await service.waitForSendCount(3);
    await _drainMicrotasks();

    expect(service.maxInFlightSends, 2);
    expect(service.sendStartOrder, recipientPeerIds.take(3).toList());

    for (final gate in sendGates.values) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }

    final (result, post) = await runFuture;
    expect(result, SendPostResult.success);
    expect(post.deliveryStatus, 'sent');
    expect(service.maxInFlightSends, 2);
  });

  test(
    'execute starts the next recipient while earlier repo writes stay blocked',
    () async {
      const recipientPeerIds = <String>['peer-bob', 'peer-cara'];
      for (final peerId in recipientPeerIds) {
        contacts.addTestContact(_contact(peerId, peerId));
      }

      final blockedDeliveryGate = Completer<void>();
      final blockedPosts = _BlockingWritePostRepository();
      addTearDown(blockedPosts.dispose);

      final service = _ControlledP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      addTearDown(service.dispose);

      final created = await _createLocalPost(
        posts: blockedPosts,
        contacts: contacts,
        recipientPeerIds: recipientPeerIds,
      );
      blockedPosts.clearWriteLog();
      blockedPosts.deliveryWriteGates['peer-bob'] = blockedDeliveryGate;

      final runFuture = PostDeliveryRunner(
        p2pService: service,
        postRepo: blockedPosts,
        maxConcurrentRecipients: 1,
      ).execute(created);

      await blockedPosts.waitForDeliveryWriteCount(1);
      await service
          .waitForSendCount(2)
          .timeout(const Duration(milliseconds: 200));

      expect(service.sendStartOrder, recipientPeerIds);
      expect(blockedPosts.deliveryWriteStartOrder, <String>['peer-bob']);

      final queuedDeliveries = await blockedPosts.getRecipientDeliveries(
        created.post.id,
      );
      expect(
        queuedDeliveries.every(
          (delivery) => delivery.deliveryStatus == 'pending',
        ),
        isTrue,
      );

      blockedDeliveryGate.complete();

      final (result, post) = await runFuture;
      expect(result, SendPostResult.success);
      expect(post.deliveryStatus, 'sent');
      expect(blockedPosts.deliveryWriteStartOrder, <String>[
        'peer-bob',
        'peer-cara',
      ]);
    },
  );

  test(
    'execute builds encrypted envelopes lazily as worker slots open',
    () async {
      const recipients = <({String peerId, String mlKemPublicKey})>[
        (peerId: 'peer-bob', mlKemPublicKey: 'mlkem-bob'),
        (peerId: 'peer-cara', mlKemPublicKey: 'mlkem-cara'),
        (peerId: 'peer-drew', mlKemPublicKey: 'mlkem-drew'),
      ];
      for (final recipient in recipients) {
        contacts.addTestContact(
          _contact(
            recipient.peerId,
            recipient.peerId,
            mlKemPublicKey: recipient.mlKemPublicKey,
          ),
        );
      }

      final bridge = _ControlledEncryptBridge(
        gates: {
          for (final recipient in recipients)
            recipient.mlKemPublicKey: Completer<void>(),
        },
      );
      addTearDown(bridge.close);

      final service = _ControlledP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      addTearDown(service.dispose);

      final created = await _createLocalPost(
        posts: posts,
        contacts: contacts,
        recipientPeerIds: recipients
            .map((recipient) => recipient.peerId)
            .toList(growable: false),
      );

      final runFuture = PostDeliveryRunner(
        p2pService: service,
        postRepo: posts,
        bridge: bridge,
        maxConcurrentRecipients: 2,
      ).execute(created);

      await bridge.waitForEncryptCount(2);
      await _drainMicrotasks();

      expect(bridge.encryptRecipientKeys, <String>['mlkem-bob', 'mlkem-cara']);
      expect(bridge.maxInFlightEncryptions, 2);

      bridge.release('mlkem-bob');
      await bridge.waitForEncryptCount(3);
      await _drainMicrotasks();

      expect(bridge.encryptRecipientKeys, <String>[
        'mlkem-bob',
        'mlkem-cara',
        'mlkem-drew',
      ]);
      expect(bridge.maxInFlightEncryptions, 2);

      bridge.release('mlkem-cara');
      bridge.release('mlkem-drew');

      final (result, post) = await runFuture;
      expect(result, SendPostResult.success);
      expect(post.deliveryStatus, 'sent');
    },
  );

  test(
    'execute encrypts once per recipient and sends recipient-specific envelopes',
    () async {
      const recipients = <({String peerId, String mlKemPublicKey})>[
        (peerId: 'peer-bob', mlKemPublicKey: 'mlkem-bob'),
        (peerId: 'peer-cara', mlKemPublicKey: 'mlkem-cara'),
      ];
      for (final recipient in recipients) {
        contacts.addTestContact(
          _contact(
            recipient.peerId,
            recipient.peerId,
            mlKemPublicKey: recipient.mlKemPublicKey,
          ),
        );
      }

      final bridge = _ControlledEncryptBridge();
      addTearDown(bridge.close);

      final service = _ControlledP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      addTearDown(service.dispose);

      final created = await _createLocalPost(
        posts: posts,
        contacts: contacts,
        recipientPeerIds: recipients
            .map((recipient) => recipient.peerId)
            .toList(growable: false),
      );

      final (result, post) = await PostDeliveryRunner(
        p2pService: service,
        postRepo: posts,
        bridge: bridge,
        maxConcurrentRecipients: 2,
      ).execute(created);

      expect(result, SendPostResult.success);
      expect(post.deliveryStatus, 'sent');
      expect(bridge.encryptRecipientKeys, <String>['mlkem-bob', 'mlkem-cara']);
      expect(service.sendAttempts, hasLength(2));

      final ciphertextByPeerId = <String, String>{};
      for (final attempt in service.sendAttempts) {
        final message = jsonDecode(attempt.message) as Map<String, dynamic>;
        ciphertextByPeerId[attempt.recipientPeerId] =
            (message['encrypted'] as Map<String, dynamic>)['ciphertext']
                as String;
        expect(
          PostCreateEnvelope.parseEncryptedEnvelope(attempt.message),
          isNotNull,
        );
      }

      expect(ciphertextByPeerId, <String, String>{
        'peer-bob': 'ciphertext:mlkem-bob',
        'peer-cara': 'ciphertext:mlkem-cara',
      });
    },
  );

  test(
    'execute improves total latency for multi-recipient text posts versus serial fanout',
    () async {
      const recipientPeerIds = <String>[
        'peer-bob',
        'peer-cara',
        'peer-drew',
        'peer-erin',
        'peer-faye',
        'peer-gio',
      ];
      for (final peerId in recipientPeerIds) {
        contacts.addTestContact(_contact(peerId, peerId));
      }

      const sendDelay = Duration(milliseconds: 120);
      final serialElapsed = await _measureDeliveryDuration(
        contacts: contacts,
        network: network,
        recipientPeerIds: recipientPeerIds,
        maxConcurrentRecipients: 1,
        sendDelay: sendDelay,
      );
      final parallelElapsed = await _measureDeliveryDuration(
        contacts: contacts,
        network: network,
        recipientPeerIds: recipientPeerIds,
        maxConcurrentRecipients: 4,
        sendDelay: sendDelay,
      );

      expect(parallelElapsed, lessThan(serialElapsed));
      expect(
        serialElapsed.inMilliseconds - parallelElapsed.inMilliseconds,
        greaterThanOrEqualTo(sendDelay.inMilliseconds),
      );
    },
  );
}

Future<CreatedLocalPost> _createLocalPost({
  required InMemoryPostRepository posts,
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

Future<void> _drainMicrotasks([int turns = 3]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<Duration> _measureDeliveryDuration({
  required InMemoryContactRepository contacts,
  required FakeP2PNetwork network,
  required List<String> recipientPeerIds,
  required int maxConcurrentRecipients,
  required Duration sendDelay,
}) async {
  final posts = InMemoryPostRepository();
  final service = _ControlledP2PService(
    peerId: 'peer-alice',
    network: network,
    policies: {
      for (final peerId in recipientPeerIds)
        peerId: _PeerPolicy(sendDelay: sendDelay),
    },
  );

  try {
    final created = await _createLocalPost(
      posts: posts,
      contacts: contacts,
      recipientPeerIds: recipientPeerIds,
    );

    final stopwatch = Stopwatch()..start();
    final (result, post) = await PostDeliveryRunner(
      p2pService: service,
      postRepo: posts,
      maxConcurrentRecipients: maxConcurrentRecipients,
    ).execute(created);
    stopwatch.stop();

    expect(result, SendPostResult.success);
    expect(post.deliveryStatus, 'sent');
    return stopwatch.elapsed;
  } finally {
    service.dispose();
    posts.dispose();
  }
}

class _ControlledP2PService extends FakeP2PService {
  final Map<String, _PeerPolicy> policies;
  final List<String> sendStartOrder = <String>[];
  final List<({String recipientPeerId, String message})> sendAttempts =
      <({String recipientPeerId, String message})>[];
  final StreamController<void> _sendStarted =
      StreamController<void>.broadcast();

  int _inFlightSends = 0;
  int maxInFlightSends = 0;
  final Set<String> _dialedPeers = <String>{};

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
    if (policy.requireDiscoverAndDialBeforeSend &&
        !_dialedPeers.contains(targetPeerId)) {
      return const SendMessageResult(sent: false);
    }
    sendStartOrder.add(targetPeerId);
    sendAttempts.add((recipientPeerId: targetPeerId, message: message));
    _inFlightSends++;
    if (_inFlightSends > maxInFlightSends) {
      maxInFlightSends = _inFlightSends;
    }
    _sendStarted.add(null);

    try {
      final sendDelay = policy.sendDelay;
      if (sendDelay != null) {
        await Future<void>.delayed(sendDelay);
      }
      final gate = policy.sendGate;
      if (gate != null) {
        await gate.future;
      }
      if (policy.throwOnSend) {
        throw StateError('send failed for $targetPeerId');
      }
      final sent = policy.sendResult ?? true;
      return SendMessageResult(sent: sent, reply: sent ? 'received' : null);
    } finally {
      _inFlightSends--;
    }
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async {
    final policy = policies[toPeerId] ?? const _PeerPolicy();
    final gate = policy.inboxGate;
    if (gate != null) {
      await gate.future;
    }
    if (policy.throwOnInbox) {
      throw StateError('inbox failed for $toPeerId');
    }
    return policy.storeInInboxResult ?? true;
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
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
    _dialedPeers.add(peerId);
    return true;
  }

  @override
  void dispose() {
    _sendStarted.close();
    super.dispose();
  }
}

class _PeerPolicy {
  final Completer<void>? sendGate;
  final Completer<void>? inboxGate;
  final Duration? sendDelay;
  final bool? sendResult;
  final bool? storeInInboxResult;
  final bool throwOnSend;
  final bool throwOnInbox;
  final bool requireDiscoverAndDialBeforeSend;

  const _PeerPolicy({
    this.sendGate,
    this.inboxGate,
    this.sendDelay,
    this.sendResult,
    this.storeInInboxResult,
    this.throwOnSend = false,
    this.throwOnInbox = false,
    this.requireDiscoverAndDialBeforeSend = false,
  });
}

class _BlockingWritePostRepository extends InMemoryPostRepository {
  final Map<String, Completer<void>> deliveryWriteGates;
  final List<String> deliveryWriteStartOrder = <String>[];
  final StreamController<void> _deliveryWriteStarted =
      StreamController<void>.broadcast();

  _BlockingWritePostRepository({
    Map<String, Completer<void>>? deliveryWriteGates,
  }) : deliveryWriteGates = deliveryWriteGates ?? <String, Completer<void>>{};

  Future<void> waitForDeliveryWriteCount(int count) async {
    while (deliveryWriteStartOrder.length < count) {
      await _deliveryWriteStarted.stream.first;
    }
  }

  void clearWriteLog() {
    deliveryWriteStartOrder.clear();
  }

  @override
  Future<void> saveRecipientDelivery(PostRecipientDelivery delivery) async {
    deliveryWriteStartOrder.add(delivery.recipientPeerId);
    _deliveryWriteStarted.add(null);
    final gate = deliveryWriteGates[delivery.recipientPeerId];
    if (gate != null) {
      await gate.future;
    }
    await super.saveRecipientDelivery(delivery);
  }

  @override
  void dispose() {
    _deliveryWriteStarted.close();
    super.dispose();
  }
}

class _ControlledEncryptBridge extends FakeBridge {
  final Map<String, Completer<void>> gates;
  final List<String> encryptRecipientKeys = <String>[];
  final StreamController<void> _encryptStarted =
      StreamController<void>.broadcast();

  int _inFlightEncryptions = 0;
  int maxInFlightEncryptions = 0;

  _ControlledEncryptBridge({this.gates = const <String, Completer<void>>{}});

  Future<void> waitForEncryptCount(int count) async {
    while (encryptRecipientKeys.length < count) {
      await _encryptStarted.stream.first;
    }
  }

  void release(String recipientPublicKey) {
    final gate = gates[recipientPublicKey];
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  Future<void> close() async {
    _encryptStarted.close();
    dispose();
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd != 'message.encrypt') {
      return super.send(message);
    }

    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;
    commandLog.add(cmd!);

    final payload = parsed['payload'] as Map<String, dynamic>;
    final recipientPublicKey = payload['recipientPublicKey'] as String;
    encryptRecipientKeys.add(recipientPublicKey);
    _inFlightEncryptions++;
    if (_inFlightEncryptions > maxInFlightEncryptions) {
      maxInFlightEncryptions = _inFlightEncryptions;
    }
    _encryptStarted.add(null);

    try {
      final gate = gates[recipientPublicKey];
      if (gate != null) {
        await gate.future;
      }
      return jsonEncode({
        'ok': true,
        'kem': 'kem:$recipientPublicKey',
        'ciphertext': 'ciphertext:$recipientPublicKey',
        'nonce': 'nonce:$recipientPublicKey',
      });
    } finally {
      _inFlightEncryptions--;
    }
  }
}
