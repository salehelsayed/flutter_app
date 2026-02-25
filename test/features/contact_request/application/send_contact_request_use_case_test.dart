import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';

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
    if (req['cmd'] == 'payload.sign') {
      return jsonEncode(signResponse);
    }
    return jsonEncode({'ok': true});
  }
}

class _FakeP2PService implements P2PService {
  NodeState _state = const NodeState(isStarted: true, peerId: 'ownPeer');
  bool sendResult = true;
  bool dialResult = true;
  DiscoveredPeer? discoveredPeer;
  bool localPeerResult = false;
  bool localSendResult = false;
  bool storeInInboxResult = false;

  String? lastSentMessage;
  String? lastSentPeerId;

  @override
  NodeState get currentState => _state;
  set currentState(NodeState s) => _state = s;

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
  Future<bool> sendMessage(String peerId, String message) async {
    lastSentPeerId = peerId;
    lastSentMessage = message;
    return sendResult;
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(String pid, String msg) async =>
      const SendMessageResult(sent: true);

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async => discoveredPeer;

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async =>
      dialResult;

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async =>
      storeInInboxResult;

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => localPeerResult;

  @override
  Future<bool> sendLocalMessage(String pid, String msg, String from) async =>
      localSendResult;

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _testIdentity = IdentityModel(
  peerId: '12D3KooWOwnPeerIdForTesting',
  publicKey: 'ownPubKey',
  privateKey: 'ownPrivKey',
  mnemonic12: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  mlKemPublicKey: 'ownMlKemPub',
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-01T00:00:00Z',
);

void main() {
  late _FakeIdentityRepo identityRepo;
  late _FakeBridge bridge;
  late _FakeP2PService p2pService;

  setUp(() {
    identityRepo = _FakeIdentityRepo()..identity = _testIdentity;
    bridge = _FakeBridge();
    p2pService = _FakeP2PService()
      ..discoveredPeer = DiscoveredPeer(
        id: 'targetPeer123456789',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      );
  });

  test('success: discovers, dials, and sends contact request', () async {
    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.success));
    expect(p2pService.lastSentPeerId, equals('targetPeer123456789'));

    // Verify the sent message is a proper contact_request envelope
    final sent = jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
    expect(sent['type'], equals('contact_request'));
    expect(sent['version'], equals('1'));
    expect(sent['payload']['ns'], equals(_testIdentity.peerId));
    expect(sent['payload']['pk'], equals(_testIdentity.publicKey));
    expect(sent['payload']['sig'], equals('fakeSig'));
    expect(sent['payload']['mlkem'], equals('ownMlKemPub'));
  });

  test('nodeNotRunning: returns error when P2P node is stopped', () async {
    p2pService.currentState = const NodeState(isStarted: false);

    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.nodeNotRunning));
  });

  test('noIdentity: returns error when no identity in repo', () async {
    identityRepo.identity = null;

    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.noIdentity));
  });

  test('signingError: returns error when bridge signing fails', () async {
    bridge.signResponse = {
      'ok': false,
      'errorCode': 'SIGN_FAILED',
      'errorMessage': 'Key not found',
    };

    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.signingError));
  });

  test('sendFailed: falls back to inbox when peer not found and inbox also fails', () async {
    p2pService.discoveredPeer = null;
    p2pService.storeInInboxResult = false;

    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.sendFailed));
  });

  test('success via inbox fallback: stores in inbox when direct send fails', () async {
    p2pService.discoveredPeer = null;
    p2pService.storeInInboxResult = true;

    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.success));
  });

  test('success via local WiFi: sends via local P2P when peer is local', () async {
    p2pService.localPeerResult = true;
    p2pService.localSendResult = true;

    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.success));
  });
}
