import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/handle_incoming_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/application/pass_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/send_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';

import '../../core/bridge/fake_bridge.dart';
import 'fake_p2p_network.dart';
import 'fake_p2p_service_integration.dart';
import 'in_memory_contact_repository.dart';
import 'in_memory_introduction_repository.dart';

/// Encapsulates the full per-user introduction stack for integration tests.
///
/// Wraps P2P service, repos, listener, and router to provide a simple API
/// for multi-node introduction tests.
class IntroTestUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final InMemoryContactRepository contactRepo;
  final InMemoryIntroductionRepository introRepo;
  final IntroductionListener introListener;
  final IncomingMessageRouter router;
  final Bridge bridge;

  IntroTestUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.contactRepo,
    required this.introRepo,
    required this.introListener,
    required this.router,
    required this.bridge,
  });

  factory IntroTestUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
    Bridge? bridge,
  }) {
    final effectiveBridge = bridge ?? PassthroughCryptoBridge();
    final p2p = FakeP2PService(peerId: peerId, network: network);
    final contactRepo = InMemoryContactRepository();
    final introRepo = InMemoryIntroductionRepository();
    final router = IncomingMessageRouter(p2pService: p2p);

    final listener = IntroductionListener(
      introductionStream: router.introductionStream,
      introRepo: introRepo,
      contactRepo: contactRepo,
      bridge: effectiveBridge,
      getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
      getOwnPeerId: () async => peerId,
    );

    return IntroTestUser._(
      peerId: peerId,
      username: username,
      p2pService: p2p,
      contactRepo: contactRepo,
      introRepo: introRepo,
      introListener: listener,
      router: router,
      bridge: effectiveBridge,
    );
  }

  /// Adds another user as a contact with ML-KEM key.
  void addContact(IntroTestUser other) {
    contactRepo.addTestContact(
      ContactModel(
        peerId: other.peerId,
        publicKey: 'pk-${other.peerId}',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: other.username,
        signature: 'sig-${other.peerId}',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: 'test-mlkem-pk-${other.peerId}',
      ),
    );
  }

  /// Sends introductions to a recipient for the given friends.
  Future<List<IntroductionModel>> sendIntroductions({
    required String recipientPeerId,
    required List<ContactModel> friends,
  }) async {
    final recipient = await contactRepo.getContact(recipientPeerId);
    return sendIntroductionsUseCase(
      contactRepo: contactRepo,
      introRepo: introRepo,
      p2pService: p2pService,
      bridge: bridge,
      introducerPeerId: peerId,
      introducerUsername: username,
      recipientPeerId: recipientPeerId,
      recipientUsername: recipient?.username ?? 'Unknown',
      recipientMlKemPublicKey: recipient?.mlKemPublicKey,
      friendsToIntroduce: friends,
    );
  }

  /// Accepts an introduction by ID.
  Future<IntroductionModel?> acceptIntro(String introId) {
    return acceptIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      introductionId: introId,
      ownPeerId: peerId,
      ownUsername: username,
    );
  }

  /// Passes (declines) an introduction by ID.
  Future<IntroductionModel?> passIntro(String introId) {
    return passIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      introductionId: introId,
      ownPeerId: peerId,
      ownUsername: username,
    );
  }

  /// Simulates receiving an accept/pass notification from another user.
  ///
  /// In a real system, when B accepts, B sends a notification that C's
  /// listener processes via handleIncomingIntroduction. In multi-node tests
  /// with separate repos, call this to replicate the cross-node effect.
  Future<IntroductionModel?> receiveAcceptNotification({
    required String introId,
    required String responderId,
    required String responderUsername,
  }) async {
    final (_, model) = await handleIncomingIntroduction(
      payload: IntroductionPayload(
        action: 'accept',
        introductionId: introId,
        responderId: responderId,
        responderUsername: responderUsername,
        timestamp: DateTime.now().toUtc().toIso8601String(),
      ),
      introRepo: introRepo,
      contactRepo: contactRepo,
      ownPeerId: peerId,
    );
    return model;
  }

  /// Simulates receiving a pass notification from another user.
  Future<IntroductionModel?> receivePassNotification({
    required String introId,
    required String responderId,
    required String responderUsername,
  }) async {
    final (_, model) = await handleIncomingIntroduction(
      payload: IntroductionPayload(
        action: 'pass',
        introductionId: introId,
        responderId: responderId,
        responderUsername: responderUsername,
        timestamp: DateTime.now().toUtc().toIso8601String(),
      ),
      introRepo: introRepo,
      contactRepo: contactRepo,
      ownPeerId: peerId,
    );
    return model;
  }

  /// Loads pending introductions for this user.
  Future<List<IntroductionModel>> loadPendingIntros() {
    return loadIntroductionsForUser(
      introRepo: introRepo,
      peerId: peerId,
    );
  }

  /// Starts the router and listener.
  void start() {
    router.start();
    introListener.start();
  }

  /// Disposes of the listener, router, and p2p service.
  void dispose() {
    introListener.dispose();
    router.dispose();
    p2pService.dispose();
  }
}

/// Alias so the send use case doesn't clash with the method name.
Future<List<IntroductionModel>> sendIntroductionsUseCase({
  required InMemoryContactRepository contactRepo,
  required InMemoryIntroductionRepository introRepo,
  required FakeP2PService p2pService,
  required Bridge bridge,
  required String introducerPeerId,
  required String introducerUsername,
  required String recipientPeerId,
  required String recipientUsername,
  required String? recipientMlKemPublicKey,
  required List<ContactModel> friendsToIntroduce,
}) =>
    sendIntroductions(
      contactRepo: contactRepo,
      introRepo: introRepo,
      p2pService: p2pService,
      bridge: bridge,
      introducerPeerId: introducerPeerId,
      introducerUsername: introducerUsername,
      recipientPeerId: recipientPeerId,
      recipientUsername: recipientUsername,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      friendsToIntroduce: friendsToIntroduce,
    );
