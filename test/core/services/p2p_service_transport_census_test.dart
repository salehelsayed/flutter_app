import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart'
    as chat_use_case;
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../bridge/fake_bridge.dart';

/// U1 — exact-count transport census across the SEND arm.
///
/// Drives [chat_use_case.sendChatMessage] with a configurable
/// [_CensusFakeP2PService] so each invocation deterministically takes a known
/// terminal exit. The false-result risk is MISLABELING, so the census is
/// asserted with EXACT map equality — never `> 0`.

/// Fake P2P with per-instance forced transport / connection / inbox results, so
/// a sequence of sends can each take a chosen terminal exit. Records the method
/// call sequence to make the taken path observable.
class _CensusFakeP2PService implements P2PService, ReadinessProofRecorder {
  final bool connected;
  final String? forcedTransport;
  final bool inboxOk;
  final DiscoveredPeer? discovered;

  final List<String> calls = [];

  _CensusFakeP2PService({
    required this.connected,
    this.forcedTransport,
    this.inboxOk = false,
    this.discovered,
  });

  /// The live send (sendMessageWithReply) reports success only when the peer is
  /// connected (reuse path). When not connected, the discover/dial race and the
  /// inbox fallback decide the outcome.
  bool get _sendOk => connected;

  // The reuse path checks currentState.connections, so expose the connection
  // there when [connected] is true.
  @override
  NodeState get currentState => NodeState(
    isStarted: true,
    connections: connected
        ? const [
            ConnectionState(
              peerId: 'connected-peer',
              multiaddrs: ['/ip4/192.168.1.10/tcp/4001'],
              direction: 'outbound',
              status: 'connected',
            ),
          ]
        : const [],
  );

  @override
  bool isConnectedToPeer(String peerId) {
    calls.add('isConnectedToPeer');
    return connected;
  }

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
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    calls.add('sendMessageWithReply');
    return SendMessageResult(
      sent: _sendOk,
      acked: _sendOk,
      reply: 'received: ok',
      transport: forcedTransport,
    );
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    calls.add('discoverPeer');
    return discovered;
  }

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
  }) async {
    calls.add('storeInInbox');
    return inboxOk;
  }

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;

  // ---- unused interface surface ----
  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();
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
  Future<bool> sendMessage(String peerId, String message) async => _sendOk;
  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async => [];
  @override
  Future<bool> registerPushToken(String token, String platform) async => true;
  @override
  Future<void> performImmediateHealthCheck() async {}
  @override
  Future<void> drainOfflineInbox() async {}
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
  bool get hasPendingResumeStarted => false;
  @override
  void markResumeStarted() {}
  @override
  void clearResumeStarted() {}
  @override
  void noteTransportSessionReset({required String trigger}) {}
  @override
  void recordSuccessfulSendProof({
    required String source,
    required String trigger,
    String? sendPath,
  }) {}
  @override
  String? get lastRecoveryMethod => null;
  @override
  void dispose() {}
}

class _FakeMessageRepository implements MessageRepository {
  @override
  Future<void> saveMessage(ConversationMessage message) async {}
  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {}
  @override
  Future<void> updateMessageStatus(String id, String status) async {}
  @override
  Future<ConversationMessage?> getMessage(String id) async => null;
  @override
  Future<bool> messageExists(String id) async => false;
  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async => [];
  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async => null;
  @override
  Future<int> getMessageCountForContact(String contactPeerId) async => 0;
  @override
  Future<int> markConversationAsRead(String contactPeerId) async => 0;
  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async => 0;
  @override
  Future<int> getTotalUnreadCount() async => 0;
  @override
  Future<int> getTotalUnreadCountExcludingArchived() async => 0;
  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async => 0;
  @override
  Future<int> deleteMessage(String id) async => 0;
  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
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
  Future<int> recoverStuckSendingMessages({required Duration olderThan}) async =>
      0;
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

Future<(chat_use_case.SendChatMessageResult, ConversationMessage?)> _send(
  P2PService p2p,
  TransportMetrics metrics, {
  required String id,
}) {
  return chat_use_case.sendChatMessage(
    p2pService: p2p,
    messageRepo: _FakeMessageRepository(),
    targetPeerId: 'connected-peer',
    text: 'hello $id',
    senderPeerId: 'self-peer',
    senderUsername: 'Alice',
    // Production logging does resolvedMessageId.substring(0, 8); use a long,
    // UUID-shaped id so that slice is always valid.
    messageId: 'census-message-id-$id',
    timestamp: '2026-04-01T00:00:00.000Z',
    // A real crypto bridge + recipient key so the send reaches the transport
    // race/inbox terminals (a null bridge exits early at encryption_required).
    bridge: PassthroughCryptoBridge(),
    recipientMlKemPublicKey: 'recipient-mlkem-public-key',
    transportMetrics: metrics,
  );
}

void main() {
  test(
    'U1: a known mix (2x direct, 1x relay, 1x inbox) yields the exact census',
    () async {
      final metrics = TransportMetrics();

      // 2x direct via the reuse path (connected + Go reports 'direct').
      await _send(
        _CensusFakeP2PService(connected: true, forcedTransport: 'direct'),
        metrics,
        id: 'd1',
      );
      await _send(
        _CensusFakeP2PService(connected: true, forcedTransport: 'direct'),
        metrics,
        id: 'd2',
      );

      // 1x relay via the reuse path (connected + Go reports 'relay').
      await _send(
        _CensusFakeP2PService(connected: true, forcedTransport: 'relay'),
        metrics,
        id: 'r1',
      );

      // 1x inbox: not connected, discovery yields nothing, inbox store succeeds.
      await _send(
        _CensusFakeP2PService(
          connected: false,
          discovered: null,
          inboxOk: true,
        ),
        metrics,
        id: 'i1',
      );

      // EXACT census — not `> 0`.
      expect(metrics.transportMix(), {
        'direct': 2,
        'relay': 1,
        'wifi': 0,
        'inbox': 1,
        'unknown': 0,
      });
      expect(metrics.totalTransportSamples, 4);

      // Mislabel guard: the relay and direct counts are not swapped.
      expect(metrics.transportMix()['relay'], 1);
      expect(metrics.transportMix()['direct'], 2);
    },
  );

  test('U1: rung distribution is exact for the forced terminal exits', () async {
    final metrics = TransportMetrics();

    // 3 reuse-path sends → rung 'reuse'.
    await _send(
      _CensusFakeP2PService(connected: true, forcedTransport: 'direct'),
      metrics,
      id: 'a',
    );
    await _send(
      _CensusFakeP2PService(connected: true, forcedTransport: 'direct'),
      metrics,
      id: 'b',
    );
    await _send(
      _CensusFakeP2PService(connected: true, forcedTransport: 'relay'),
      metrics,
      id: 'c',
    );
    // 1 inbox-fallback send → rung 'inbox_fallback'.
    await _send(
      _CensusFakeP2PService(connected: false, discovered: null, inboxOk: true),
      metrics,
      id: 'd',
    );

    expect(metrics.rungDistribution(), {
      'reuse': 3,
      'local_race': 0,
      'direct_race': 0,
      'relay_probe': 0,
      'inbox_fallback': 1,
      'failed': 0,
    });
  });

  test(
    'U1: a non-delivered send does NOT increment any transport-mix bucket',
    () async {
      final metrics = TransportMetrics();
      // Not connected, no discovery, inbox store fails → final failure exit.
      final fake = _CensusFakeP2PService(
        connected: false,
        discovered: null,
        inboxOk: false,
      );
      final result = await _send(fake, metrics, id: 'fail');

      // The send genuinely failed (no transport delivered it).
      expect(result.$1, isNot(chat_use_case.SendChatMessageResult.success));

      // A non-delivered message must NOT increment any transport bucket
      // (no spurious 'relay'/'unknown' census entry for a failed send).
      expect(metrics.totalTransportSamples, 0);
      expect(metrics.transportMix(), {
        'direct': 0,
        'relay': 0,
        'wifi': 0,
        'inbox': 0,
        'unknown': 0,
      });

      // The failure exit records exactly the 'failed' rung.
      expect(
        metrics.rungDistribution()['failed'],
        1,
        reason: 'rungs=${metrics.rungDistribution()} calls=${fake.calls}',
      );
    },
  );
}
