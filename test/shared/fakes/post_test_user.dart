import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart'
    as send_post_uc;
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../core/bridge/fake_bridge.dart';
import 'fake_p2p_network.dart';
import 'fake_p2p_service_integration.dart';
import 'in_memory_contact_repository.dart';
import 'in_memory_post_repository.dart';

class PostTestUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;
  final IncomingMessageRouter router;
  final PostListener postListener;
  final Bridge bridge;

  PostTestUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.contactRepo,
    required this.postRepo,
    required this.router,
    required this.postListener,
    required this.bridge,
  });

  factory PostTestUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
    Bridge? bridge,
  }) {
    final effectiveBridge = bridge ?? PassthroughCryptoBridge();
    final p2pService = FakeP2PService(peerId: peerId, network: network);
    final contactRepo = InMemoryContactRepository();
    final postRepo = InMemoryPostRepository();
    final router = IncomingMessageRouter(p2pService: p2pService);
    final postListener = PostListener(
      postCreateStream: router.postCreateStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
      bridge: effectiveBridge,
      getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
    );
    return PostTestUser._(
      peerId: peerId,
      username: username,
      p2pService: p2pService,
      contactRepo: contactRepo,
      postRepo: postRepo,
      router: router,
      postListener: postListener,
      bridge: effectiveBridge,
    );
  }

  void addContact(PostTestUser other, {bool archived = false, bool blocked = false}) {
    contactRepo.addTestContact(
      ContactModel(
        peerId: other.peerId,
        publicKey: 'pk-${other.peerId}',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: other.username,
        signature: 'sig-${other.peerId}',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: 'mlkem-${other.peerId}',
        isArchived: archived,
        archivedAt: archived ? DateTime.now().toUtc().toIso8601String() : null,
        isBlocked: blocked,
        blockedAt: blocked ? DateTime.now().toUtc().toIso8601String() : null,
      ),
    );
  }

  void start() {
    router.start();
    postListener.start();
  }

  void setOnline(bool online) => p2pService.setOnline(online);

  Future<(send_post_uc.SendPostResult, PostModel?)> sendPost({
    required String text,
    required PostAudience audience,
  }) {
    return send_post_uc.sendPost(
      p2pService: p2pService,
      postRepo: postRepo,
      contactRepo: contactRepo,
      senderPeerId: peerId,
      senderUsername: username,
      text: text,
      audience: audience,
      bridge: bridge,
    );
  }

  Future<int> drainOfflineInbox() => p2pService.drainOfflineInboxCount();

  void dispose() {
    postListener.dispose();
    router.dispose();
    postRepo.dispose();
    p2pService.dispose();
  }
}
