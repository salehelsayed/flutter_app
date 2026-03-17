import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
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
  late _EncryptedPassUser sender;
  late _EncryptedPassUser author;
  late _EncryptedPassUser recipient;

  setUp(() {
    network = FakeP2PNetwork();
    sender = _EncryptedPassUser.create(
      peerId: 'peer-alice',
      username: 'Alice',
      network: network,
    );
    author = _EncryptedPassUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
    );
    recipient = _EncryptedPassUser.create(
      peerId: 'peer-cara',
      username: 'Cara',
      network: network,
    );

    sender.addContact(author);
    sender.addContact(recipient);
    author.addContact(sender);
    recipient.addContact(sender);
    author.start();
    recipient.start();
  });

  tearDown(() {
    sender.dispose();
    author.dispose();
    recipient.dispose();
  });

  test(
    'encrypted repost direct delivery goes through router and listener for both explicit recipient and original author',
    () async {
      await _seedSharedPost(sender: sender, author: author);
      final authorWireMessage = author.p2pService.messageStream.first;
      final recipientWireMessage = recipient.p2pService.messageStream.first;

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
      await _waitForPassCount(author, expectedCount: 1);
      await _waitForPassCount(recipient, expectedCount: 1);

      final authorJson =
          jsonDecode(
                (await authorWireMessage.timeout(
                  const Duration(seconds: 1),
                )).content,
              )
              as Map<String, dynamic>;
      final recipientJson =
          jsonDecode(
                (await recipientWireMessage.timeout(
                  const Duration(seconds: 1),
                )).content,
              )
              as Map<String, dynamic>;
      final authorPayload = _decodeEncryptedPassPayload(authorJson);
      final recipientPayload = _decodeEncryptedPassPayload(recipientJson);

      expect(
        PostPassEnvelope.parseEncryptedEnvelope(jsonEncode(authorJson)),
        isNotNull,
      );
      expect(
        PostPassEnvelope.parseEncryptedEnvelope(jsonEncode(recipientJson)),
        isNotNull,
      );
      expect(authorJson['version'], '2');
      expect(recipientJson['version'], '2');
      expect(authorPayload['post_id'], 'post-1');
      expect(recipientPayload['post_id'], 'post-1');
      expect(authorPayload['participant_peer_ids'], <String>[
        'peer-alice',
        'peer-bob',
      ]);
      expect(recipientPayload['participant_peer_ids'], <String>[
        'peer-alice',
        'peer-bob',
      ]);
      expect(authorPayload['repost_total_baseline'], 0);
      expect(recipientPayload['repost_total_baseline'], 0);
      expect(await recipient.postRepo.getPost('post-1'), isNotNull);
      expect(await author.postRepo.getPost('post-1'), isNotNull);
      expect(
        sender.bridge.commandLog.where(
          (command) => command == 'message.encrypt',
        ),
        hasLength(2),
      );
    },
  );
}

Future<void> _seedSharedPost({
  required _EncryptedPassUser sender,
  required _EncryptedPassUser author,
}) async {
  final post = PostModel(
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
  await sender.postRepo.savePost(post);
  await author.postRepo.savePost(post);
}

Future<void> _waitForPassCount(
  _EncryptedPassUser user, {
  required int expectedCount,
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

  throw StateError('Timed out waiting for encrypted repost delivery');
}

class _EncryptedPassUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final PassthroughCryptoBridge bridge;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;
  final IncomingMessageRouter router;
  final PostPassListener passListener;

  _EncryptedPassUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.bridge,
    required this.contactRepo,
    required this.postRepo,
    required this.router,
    required this.passListener,
  });

  factory _EncryptedPassUser.create({
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

    return _EncryptedPassUser._(
      peerId: peerId,
      username: username,
      p2pService: p2pService,
      bridge: bridge,
      contactRepo: contactRepo,
      postRepo: postRepo,
      router: router,
      passListener: passListener,
    );
  }

  void addContact(_EncryptedPassUser other) {
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
  }

  void dispose() {
    passListener.dispose();
    router.dispose();
    postRepo.dispose();
    p2pService.dispose();
  }
}

Map<String, dynamic> _decodeEncryptedPassPayload(Map<String, dynamic> json) {
  final encrypted = json['encrypted'] as Map<String, dynamic>;
  return jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
}
