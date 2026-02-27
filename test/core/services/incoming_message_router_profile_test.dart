import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

class FakeP2PService implements P2PService {
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
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async => false;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;
  @override
  Future<bool> sendMessage(String peerId, String message) async => true;
  @override
  Future<SendMessageResult> sendMessageWithReply(String peerId, String message, {int? timeoutMs}) async =>
      const SendMessageResult(sent: true);
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async => null;
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
  Future<bool> sendLocalMessage(String peerId, String message, String fromPeerId) async => false;
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
  void dispose() => _messageController.close();
}

void main() {
  late FakeP2PService p2pService;
  late IncomingMessageRouter router;

  setUp(() {
    p2pService = FakeP2PService();
    router = IncomingMessageRouter(p2pService: p2pService);
    router.start();
  });

  tearDown(() {
    router.dispose();
    p2pService.dispose();
  });

  group('IncomingMessageRouter — profile_update routing', () {
    test('routes profile_update messages to profileUpdateStream', () async {
      final received = router.profileUpdateStream.first;

      p2pService.inject(ChatMessage(
        from: 'peer-a',
        to: 'peer-b',
        content: jsonEncode({
          'type': 'profile_update',
          'version': '1',
          'payload': {
            'peerId': 'peer-a',
            'avatarVersion': '2026-02-21T12:00:00.000Z',
          },
        }),
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ));

      final msg = await received.timeout(const Duration(seconds: 1));
      expect(msg.from, 'peer-a');
      expect(msg.content, contains('"type":"profile_update"'));
    });

    test('does not route profile_update to chatMessageStream or contactRequestStream', () async {
      final contactRequests = <ChatMessage>[];
      final chatMessages = <ChatMessage>[];
      final profileUpdates = <ChatMessage>[];
      final unknowns = <ChatMessage>[];

      router.contactRequestStream.listen(contactRequests.add);
      router.chatMessageStream.listen(chatMessages.add);
      router.profileUpdateStream.listen(profileUpdates.add);
      router.unknownMessageStream.listen(unknowns.add);

      p2pService.inject(ChatMessage(
        from: 'peer-a',
        to: 'peer-b',
        content: jsonEncode({
          'type': 'profile_update',
          'version': '1',
          'payload': {'peerId': 'peer-a', 'avatarVersion': '2026-02-21T12:00:00.000Z'},
        }),
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(profileUpdates.length, 1);
      expect(contactRequests, isEmpty);
      expect(chatMessages, isEmpty);
      expect(unknowns, isEmpty);
    });

    test('ignores outgoing profile_update messages', () async {
      final profileUpdates = <ChatMessage>[];
      router.profileUpdateStream.listen(profileUpdates.add);

      p2pService.inject(ChatMessage(
        from: 'peer-b',
        to: 'peer-a',
        content: jsonEncode({
          'type': 'profile_update',
          'version': '1',
          'payload': {'peerId': 'peer-b', 'avatarVersion': '2026-02-21T12:00:00.000Z'},
        }),
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: false,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(profileUpdates, isEmpty);
    });
  });
}
