import 'dart:async';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

/// In-memory [P2PService] for tests.
///
/// Configurable return values, tracks call counts and last arguments.
class FakeP2PService implements P2PService {
  NodeState _currentState;
  final _stateController = StreamController<NodeState>.broadcast();
  final _messageController = StreamController<ChatMessage>.broadcast();

  // Configurable return values
  bool startNodeResult;
  bool stopNodeResult;
  bool sendMessageResult;
  SendMessageResult sendMessageWithReplyResult;
  DiscoveredPeer? discoverPeerResult;
  bool dialPeerResult;
  bool storeInInboxResult;
  List<Map<String, dynamic>> retrieveInboxResult;
  bool registerPushTokenResult;
  bool throwOnHealthCheck;
  bool throwOnDrainInbox;

  // Call tracking
  int startNodeCallCount = 0;
  int stopNodeCallCount = 0;
  int sendMessageCallCount = 0;
  int sendMessageWithReplyCallCount = 0;
  int discoverPeerCallCount = 0;
  int dialPeerCallCount = 0;
  int storeInInboxCallCount = 0;
  int retrieveInboxCallCount = 0;
  int performImmediateHealthCheckCallCount = 0;
  int drainOfflineInboxCallCount = 0;

  // Last arguments
  String? lastStartNodePrivateKey;
  String? lastStartNodePeerId;
  String? lastSendMessagePeerId;
  String? lastSendMessageContent;
  String? lastDiscoverPeerId;
  String? lastDialPeerId;

  FakeP2PService({
    NodeState? initialState,
    this.startNodeResult = true,
    this.stopNodeResult = true,
    this.sendMessageResult = true,
    SendMessageResult? sendMessageWithReplyResult,
    this.discoverPeerResult,
    this.dialPeerResult = true,
    this.storeInInboxResult = true,
    this.retrieveInboxResult = const [],
    this.registerPushTokenResult = true,
    this.throwOnHealthCheck = false,
    this.throwOnDrainInbox = false,
  })  : _currentState = initialState ?? NodeState.stopped,
        sendMessageWithReplyResult = sendMessageWithReplyResult ??
            const SendMessageResult(sent: true, reply: 'ack');

  @override
  NodeState get currentState => _currentState;

  @override
  Stream<NodeState> get stateStream => _stateController.stream;

  @override
  Stream<ChatMessage> get messageStream => _messageController.stream;

  /// Emit a state change for testing.
  void emitState(NodeState state) {
    _currentState = state;
    _stateController.add(state);
  }

  /// Emit an incoming message for testing.
  void emitMessage(ChatMessage message) {
    _messageController.add(message);
  }

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async {
    startNodeCallCount++;
    lastStartNodePrivateKey = privateKeyBase64;
    lastStartNodePeerId = peerId;
    return startNodeResult;
  }

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async {
    return startNode(privateKeyBase64, peerId);
  }

  @override
  Future<void> warmBackground() async {}

  @override
  Future<bool> stopNode() async {
    stopNodeCallCount++;
    return stopNodeResult;
  }

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    sendMessageCallCount++;
    lastSendMessagePeerId = peerId;
    lastSendMessageContent = message;
    return sendMessageResult;
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
      String peerId, String message, {int? timeoutMs}) async {
    sendMessageWithReplyCallCount++;
    lastSendMessagePeerId = peerId;
    lastSendMessageContent = message;
    return sendMessageWithReplyResult;
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async {
    discoverPeerCallCount++;
    lastDiscoverPeerId = peerId;
    return discoverPeerResult;
  }

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async {
    dialPeerCallCount++;
    lastDialPeerId = peerId;
    return dialPeerResult;
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async {
    storeInInboxCallCount++;
    return storeInInboxResult;
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async {
    retrieveInboxCallCount++;
    return retrieveInboxResult;
  }

  @override
  Future<bool> registerPushToken(String token, String platform) async {
    return registerPushTokenResult;
  }

  @override
  Future<void> performImmediateHealthCheck() async {
    performImmediateHealthCheckCallCount++;
    if (throwOnHealthCheck) {
      throw Exception('FakeP2PService: health check error');
    }
  }

  @override
  Future<void> drainOfflineInbox() async {
    drainOfflineInboxCallCount++;
    if (throwOnDrainInbox) {
      throw Exception('FakeP2PService: drain inbox error');
    }
  }

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> sendLocalMessage(
      String peerId, String message, String fromPeerId) async {
    return false;
  }

  @override
  void dispose() {
    _stateController.close();
    _messageController.close();
  }
}
