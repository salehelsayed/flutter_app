// test/features/conversation/application/send_voice_message_no_bg_task_test.dart
//
// Phase 2 Unit 2C — Step 3.6
// Regression guard: sendVoiceMessage use case must NOT call bg:begin / bg:end.
// Background task management belongs exclusively to the presentation layer.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

import 'dart:async';

/// Bridge that records every command it receives.
class _AuditBridge implements Bridge {
  final List<String> callLog = [];

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final cmd = decoded['cmd'] as String;
    callLog.add(cmd);
    // Return minimal valid responses for the upload + send pipeline
    if (cmd == 'blob:keygen') {
      return jsonEncode({'ok': true, 'keyBase64': 'AAAA'});
    }
    if (cmd == 'blob:encrypt') {
      return jsonEncode({
        'ok': true,
        'encryptedPath': '/tmp/test_voice.m4a.enc',
        'nonce': 'fake-nonce',
      });
    }
    if (cmd == 'media:upload') {
      return jsonEncode({
        'ok': true,
        'blobId': 'blob-123',
        'url': 'https://example.com/blob-123',
      });
    }
    if (cmd == 'message.encrypt') {
      return jsonEncode({
        'ok': true,
        'kem': 'fake-kem',
        'ciphertext': 'fake-ct',
        'nonce': 'fake-nonce',
      });
    }
    return jsonEncode({'ok': true});
  }

  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String>, List<String>)? onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
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
}

/// Minimal P2PService that records send calls.
class _FakeP2PService implements P2PService {
  @override
  NodeState get currentState =>
      const NodeState(isStarted: true, peerId: 'peer-alice');
  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();
  @override
  Future<bool> startNode(String pk, String peerId) async => true;
  @override
  Future<bool> startNodeCore(String pk, String peerId) async => true;
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
  }) async => const SendMessageResult(sent: true, reply: 'received: ok');
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
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async => true;
  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];
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
  void dispose() {}
}

/// Minimal in-memory MessageRepository.
class _FakeMessageRepo
    implements MessageRepository, MessageRepositoryChangeSource {
  final _ctrl = StreamController<ConversationMessage>.broadcast();

  @override
  Stream<ConversationMessage> get messageChanges => _ctrl.stream;
  @override
  Future<void> saveMessage(ConversationMessage m) async {}
  @override
  Future<List<ConversationMessage>> getMessagesForContact(String pid) async =>
      [];
  @override
  Future<ConversationMessage?> getLatestMessageForContact(String pid) async =>
      null;
  @override
  Future<ConversationMessage?> getMessage(String id) async => null;
  @override
  Future<bool> messageExists(String id) async => false;
  @override
  Future<void> updateMessageStatus(String id, String status) async {}
  @override
  Future<int> getMessageCountForContact(String pid) async => 0;
  @override
  Future<int> markConversationAsRead(String pid) async => 0;
  @override
  Future<int> getUnreadCountForContact(String pid) async => 0;
  @override
  Future<int> getTotalUnreadCount() async => 0;
  @override
  Future<int> getTotalUnreadCountExcludingArchived() async => 0;
  @override
  Future<int> deleteMessagesForContact(String pid) async => 0;
  @override
  Future<int> deleteMessage(String id) async => 0;
  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String pid, {
    int limit = 50,
    String? beforeTimestamp,
  }) async => [];
  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];
  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async => [];
  @override
  Future<int> recoverStuckSendingMessages({
    required Duration olderThan,
  }) async => 0;
  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {}
  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async => [];

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async => 0;
}

void main() {
  group('sendVoiceMessage — no bg:begin/bg:end (presentation-only rule)', () {
    test('sendVoiceMessage does NOT call bg:begin or bg:end', () async {
      final bridge = _AuditBridge();
      final recording = AudioRecording(
        filePath: '/tmp/test_voice_no_bg.m4a',
        durationMs: 3000,
        sizeBytes: 50000,
        mime: 'audio/mp4',
      );

      // Create the test file so validation passes
      final file = File('/tmp/test_voice_no_bg.m4a');
      file.writeAsBytesSync(List.filled(50000, 0));
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      try {
        await sendVoiceMessage(
          p2pService: _FakeP2PService(),
          messageRepo: _FakeMessageRepo(),
          targetPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          senderUsername: 'alice',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: 'mlkem-public-key',
        );
      } catch (_) {
        // We don't care about the result — only about which commands were called
      }

      expect(
        bridge.callLog,
        isNot(contains('bg:begin')),
        reason:
            'sendVoiceMessage must NOT call bg:begin — '
            'background task management belongs to the presentation layer only',
      );
      expect(
        bridge.callLog,
        isNot(contains('bg:end')),
        reason:
            'sendVoiceMessage must NOT call bg:end — '
            'background task management belongs to the presentation layer only',
      );
    });
  });
}
