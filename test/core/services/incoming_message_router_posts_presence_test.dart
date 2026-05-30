import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

class _FakeP2PService implements P2PService {
  final StreamController<ChatMessage> controller =
      StreamController<ChatMessage>.broadcast();

  @override
  NodeState get currentState =>
      const NodeState(isStarted: true, peerId: 'self');

  @override
  Stream<ChatMessage> get messageStream => controller.stream;

  @override
  Stream<NodeState> get stateStream => const Stream<NodeState>.empty();

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async =>
      false;

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

  @override
  String? get lastRecoveryMethod => null;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      const [];

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
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;

  @override
  Future<bool> sendMessage(String peerId, String message) async => false;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: false);

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> storeInInbox(String toPeerId, String message, {int? timeoutMs}) async => true;

  @override
  Future<void> warmBackground() async {}

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => false;

  @override
  void dispose() {
    controller.close();
  }
}

void main() {
  late _FakeP2PService p2pService;
  late IncomingMessageRouter router;

  setUp(() {
    p2pService = _FakeP2PService();
    router = IncomingMessageRouter(p2pService: p2pService)..start();
  });

  tearDown(() {
    router.dispose();
    p2pService.dispose();
  });

  test('routes post_presence_update envelopes to postPresenceStream', () async {
    final received = router.postPresenceStream.first;
    p2pService.controller.add(
      ChatMessage(
        from: 'peer-bob',
        to: 'self',
        content: jsonEncode(<String, Object?>{
          'type': 'post_presence_update',
          'version': '1',
          'event_id': 'evt-presence-1',
          'created_at': '2026-03-15T11:10:00.000Z',
          'sender_peer_id': 'peer-bob',
          'payload': <String, Object?>{
            'status': 'active',
            'lat_e3': 52520,
            'lng_e3': 13405,
            'captured_at': '2026-03-15T11:10:00.000Z',
            'accuracy_m': 120,
          },
        }),
        timestamp: '2026-03-15T11:10:00.000Z',
        isIncoming: true,
      ),
    );

    final message = await received.timeout(const Duration(seconds: 1));
    expect(message.content, contains('"type":"post_presence_update"'));
  });
}
