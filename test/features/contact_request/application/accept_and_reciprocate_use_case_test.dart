import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeIdentityRepo implements IdentityRepository {
  IdentityModel? identity;

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

class _FakeBridge extends Bridge {
  Map<String, dynamic> signResponse = {'ok': true, 'signature': 'fakeSig'};
  Map<String, dynamic> encryptResponse = {
    'ok': true,
    'ephemeralPublicKey': 'ephPub',
    'ciphertext': 'ct',
    'nonce': 'nonce',
  };
  int signCallCount = 0;
  int encryptCallCount = 0;
  Map<String, dynamic>? lastEncryptPayload;
  final List<String> commandLog = [];

  @override
  bool get isInitialized => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final req = jsonDecode(message) as Map<String, dynamic>;
    final cmd = req['cmd'] as String?;
    if (cmd != null) commandLog.add(cmd);
    if (cmd == 'payload.sign') {
      signCallCount++;
      return jsonEncode(signResponse);
    }
    if (cmd == 'contactrequest.encrypt') {
      encryptCallCount++;
      lastEncryptPayload = req['payload'] as Map<String, dynamic>?;
      return jsonEncode(encryptResponse);
    }
    return jsonEncode({'ok': true});
  }
}

class _FakeP2PService implements P2PService {
  String? lastSentMessage;
  String? lastSentPeerId;

  @override
  NodeState get currentState =>
      const NodeState(isStarted: true, peerId: 'ownPeer');
  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();
  @override
  Future<bool> startNode(String pk, String pid) async => true;
  @override
  Future<bool> startNodeCore(String pk, String pid) async => true;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;
  @override
  Future<bool> sendMessage(String peerId, String message) async => true;
  @override
  Future<SendMessageResult> sendMessageWithReply(String pid, String msg, {int? timeoutMs}) async {
    lastSentPeerId = pid;
    lastSentMessage = msg;
    return const SendMessageResult(sent: true);
  }
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async =>
      DiscoveredPeer(id: peerId, addresses: ['/ip4/127.0.0.1/tcp/4001']);
  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async => true;
  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;
  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];
  @override
  Future<bool> registerPushToken(String token, String platform) async => true;
  @override
  Future<void> performImmediateHealthCheck() async {}
  @override
  Future<void> drainOfflineInbox() async {}
  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;
  @override
  bool isConnectedToPeer(String peerId) => false;
  @override
  bool isLocalPeer(String peerId) => false;
  @override
  Future<bool> sendLocalMessage(String pid, String msg, String from) async =>
      false;
  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async => false;
  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _bobPeerId = '12D3KooWBobPeerIdxxx00000000001';

final _testIdentity = IdentityModel(
  peerId: '12D3KooWOwnPeerIdForTesting',
  publicKey: 'ownPubKey',
  privateKey: 'ownPrivKey',
  mnemonic12:
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  mlKemPublicKey: 'ownMlKemPub',
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-01T00:00:00Z',
);

void _seedPendingRequest(InMemoryContactRequestRepository repo) {
  repo.addRequest(ContactRequestModel(
    peerId: _bobPeerId,
    publicKey: 'pk-bob',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: 'Bob',
    signature: 'sig-bob',
    status: ContactRequestStatus.pending,
    receivedAt: '2026-01-01T00:00:00Z',
  ));
}

void main() {
  late InMemoryContactRequestRepository requestRepo;
  late InMemoryContactRepository contactRepo;
  late _FakeIdentityRepo identityRepo;
  late _FakeBridge bridge;
  late _FakeP2PService p2pService;

  setUp(() {
    requestRepo = InMemoryContactRequestRepository();
    contactRepo = InMemoryContactRepository();
    identityRepo = _FakeIdentityRepo()..identity = _testIdentity;
    bridge = _FakeBridge();
    p2pService = _FakeP2PService();
  });

  test('success: calls acceptContactRequest and returns success', () async {
    _seedPendingRequest(requestRepo);

    final result = await acceptAndReciprocateContactRequest(
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      peerId: _bobPeerId,
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
    );

    expect(result, AcceptContactRequestResult.success);

    // Verify contact was added
    final contact = await contactRepo.getContact(_bobPeerId);
    expect(contact, isNotNull);
    expect(contact!.username, 'Bob');
  });

  test('success: fires sendContactRequest on success', () async {
    _seedPendingRequest(requestRepo);

    await acceptAndReciprocateContactRequest(
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      peerId: _bobPeerId,
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
    );

    // Allow fire-and-forget future to complete
    await Future.delayed(const Duration(milliseconds: 200));

    // Evidence of reciprocal send: bridge.send was called with both sign and encrypt
    expect(bridge.signCallCount, greaterThanOrEqualTo(1));
    expect(bridge.encryptCallCount, greaterThanOrEqualTo(1));

    // Verify recipient public key was threaded to encrypt
    expect(bridge.lastEncryptPayload, isNotNull);
    expect(bridge.lastEncryptPayload!['recipientPublicKey'], equals('pk-bob'));
  });

  test('notFound: does not fire reciprocal when accept fails', () async {
    // No request seeded → notFound
    final result = await acceptAndReciprocateContactRequest(
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      peerId: _bobPeerId,
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
    );

    expect(result, AcceptContactRequestResult.notFound);
    await Future.delayed(Duration.zero);
    expect(bridge.signCallCount, 0);
  });

  test('notPending: does not fire reciprocal when not pending', () async {
    // Seed as already-accepted
    requestRepo.addRequest(ContactRequestModel(
      peerId: _bobPeerId,
      publicKey: 'pk-bob',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Bob',
      signature: 'sig-bob',
      status: ContactRequestStatus.accepted,
      receivedAt: '2026-01-01T00:00:00Z',
    ));

    final result = await acceptAndReciprocateContactRequest(
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      peerId: _bobPeerId,
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
    );

    expect(result, AcceptContactRequestResult.notPending);
    await Future.delayed(Duration.zero);
    expect(bridge.signCallCount, 0);
  });

  test('reciprocal failure does not affect return value', () async {
    _seedPendingRequest(requestRepo);

    // Make bridge throw during sign → reciprocal sendContactRequest will fail
    bridge.signResponse = {
      'ok': false,
      'errorCode': 'SIGN_FAILED',
      'errorMessage': 'Key not found',
    };

    final result = await acceptAndReciprocateContactRequest(
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      peerId: _bobPeerId,
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
    );

    // Accept still succeeds even though reciprocal will fail
    expect(result, AcceptContactRequestResult.success);
    await Future.delayed(Duration.zero);

    // Contact was still added
    final contact = await contactRepo.getContact(_bobPeerId);
    expect(contact, isNotNull);
  });

  test('success: reciprocal send produces v2 encrypted envelope', () async {
    _seedPendingRequest(requestRepo);

    await acceptAndReciprocateContactRequest(
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      peerId: _bobPeerId,
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
    );

    await Future.delayed(const Duration(milliseconds: 200));

    expect(p2pService.lastSentMessage, isNotNull);
    final sent = jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
    expect(sent['type'], equals('contact_request'));
    expect(sent['version'], equals('2'));
    expect(sent['encrypted'], isA<Map>());
    expect(sent.containsKey('payload'), isFalse);
  });
}
