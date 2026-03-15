import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
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
  Future<bool> storeInInbox(String toPeerId, String message) async => true;

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

  test('routes post_comment envelopes to postCommentStream', () async {
    final received = router.postCommentStream.first;
    p2pService.controller.add(
      ChatMessage(
        from: 'peer-bob',
        to: 'self',
        content: jsonEncode(<String, Object?>{
          'type': 'post_comment',
          'version': '1',
          'event_id': 'evt-comment-1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'sender_peer_id': 'peer-bob',
          'payload': <String, Object?>{
            'comment_id': 'comment-1',
            'post_id': 'post-1',
            'body': 'Nice post',
            'commented_at': DateTime.now().toUtc().toIso8601String(),
          },
        }),
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ),
    );

    final message = await received.timeout(const Duration(seconds: 1));
    expect(message.content, contains('"type":"post_comment"'));
  });

  test('routes post_reaction envelopes to postReactionStream', () async {
    final received = router.postReactionStream.first;
    p2pService.controller.add(
      ChatMessage(
        from: 'peer-bob',
        to: 'self',
        content: jsonEncode(<String, Object?>{
          'type': 'post_reaction',
          'version': '1',
          'event_id': 'evt-reaction-1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'sender_peer_id': 'peer-bob',
          'payload': <String, Object?>{
            'reaction_id': 'post_heart:post-1:peer-bob',
            'post_id': 'post-1',
            'kind': 'heart',
            'is_active': true,
            'reacted_at': DateTime.now().toUtc().toIso8601String(),
          },
        }),
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ),
    );

    final message = await received.timeout(const Duration(seconds: 1));
    expect(message.content, contains('"type":"post_reaction"'));
  });

  test(
    'routes post_comment_reaction envelopes to postCommentReactionStream',
    () async {
      final received = router.postCommentReactionStream.first;
      p2pService.controller.add(
        ChatMessage(
          from: 'peer-bob',
          to: 'self',
          content: jsonEncode(<String, Object?>{
            'type': 'post_comment_reaction',
            'version': '1',
            'event_id': 'evt-comment-reaction-1',
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'sender_peer_id': 'peer-bob',
            'payload': <String, Object?>{
              'reaction_id': 'comment_heart:comment-1:peer-bob',
              'post_id': 'post-1',
              'comment_id': 'comment-1',
              'kind': 'heart',
              'is_active': true,
              'reacted_at': DateTime.now().toUtc().toIso8601String(),
            },
          }),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      final message = await received.timeout(const Duration(seconds: 1));
      expect(message.content, contains('"type":"post_comment_reaction"'));
    },
  );
}
