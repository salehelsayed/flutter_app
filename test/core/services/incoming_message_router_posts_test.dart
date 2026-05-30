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
  final _messageController = StreamController<ChatMessage>.broadcast();

  void inject(ChatMessage message) => _messageController.add(message);

  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => _messageController.stream;

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      true;

  @override
  Future<void> warmBackground() async {}

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: true);

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => true;

  @override
  Future<bool> storeInInbox(String toPeerId, String message, {int? timeoutMs}) async => false;

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      const [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

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
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;

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
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {
    _messageController.close();
  }
}

ChatMessage _postCreateMessage() {
  return ChatMessage(
    from: 'peer-a',
    to: 'peer-b',
    content: jsonEncode({
      'type': 'post_create',
      'version': '1',
      'event_id': 'evt-1',
      'created_at': '2026-03-15T10:15:30.000Z',
      'sender_peer_id': 'peer-a',
      'payload': {
        'post_id': 'post-1',
        'snapshot': {
          'post_id': 'post-1',
          'author_peer_id': 'peer-a',
          'author_username': 'Alice',
          'post_created_at': '2026-03-15T10:15:30.000Z',
          'audience': {
            'kind': 'all_friends',
            'radius_m': null,
            'scope_label': null,
          },
          'text': 'Hello posts',
          'media_kind': 'none',
          'media': const [],
          'keep_available': false,
          'expires_at': '2026-03-18T10:15:30.000Z',
        },
      },
    }),
    timestamp: '2026-03-15T10:15:30.000Z',
    isIncoming: true,
  );
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

  test('routes post_create envelopes to postCreateStream', () async {
    final received = router.postCreateStream.first;

    p2pService.inject(_postCreateMessage());

    final routed = await received.timeout(const Duration(seconds: 1));
    expect(routed.content, contains('"type":"post_create"'));
  });

  test('does not route post_create to unknown stream', () async {
    final unknownMessages = <ChatMessage>[];
    router.unknownMessageStream.listen(unknownMessages.add);

    p2pService.inject(_postCreateMessage());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(unknownMessages, isEmpty);
  });
}
