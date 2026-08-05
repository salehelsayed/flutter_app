import 'dart:convert';
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart'
    hide sendChatMessage, editChatMessage;
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart'
    as chat_use_case
    show sendChatMessage, editChatMessage;
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';

// -- Fake P2P Service --
class FakeP2PService
    implements
        P2PService,
        ReadinessProofRecorder,
        RelayLiveSendObserver,
        PeerDropSignal {
  final NodeState _currentState;
  bool sendMessageResult;
  String? sendMessageReply;
  bool? sendMessageAcked;
  String? sendMessageTransport;
  final List<Future<SendMessageResult>> queuedSendMessageResults = [];
  bool shouldThrow;
  bool storeInInboxResult;
  RelayProbeResult probeRelayResult;

  DiscoveredPeer? discoverPeerResult;
  bool dialPeerResult;

  int discoverCallCount = 0;
  int dialCallCount = 0;
  int sendCallCount = 0;
  int probeRelayCallCount = 0;
  int storeInInboxCallCount = 0;
  final List<int?> discoverTimeouts = [];
  final List<int?> dialTimeouts = [];
  final List<int?> sendTimeouts = [];

  /// FDC-02 (C2): leg-attributable count of how many times the STAGGERED
  /// relay-LIVE leg actually started its send. Incremented only by
  /// [noteRelayLiveSendStart] (fired by `_tryRelayLiveSend` AFTER the
  /// suppress-on-early-win guard), so a suppressed leg never bumps it and the
  /// direct/reuse/probe sends — which share `sendMessageWithReply` — are NOT
  /// counted here. The load-bearing discriminator for "the live leg did/did not
  /// fire" (delivery alone is masked by receiver dedup, FDC-00 closure caveat).
  int relayLiveSendCount = 0;

  /// FDC-02: the transport label the relay-LIVE leg's send resolves to (Go's
  /// label in prod). Defaults to 'relay' (a live `/p2p-circuit` send). Distinct
  /// from [sendMessageTransport] (the direct/reuse legs) so a rank test can have
  /// the direct leg label 'direct' while the relay-live leg labels 'relay'.
  String? relayLiveSendTransport;

  /// Set synchronously by [noteRelayLiveSendStart] right before the relay-live
  /// leg's `sendMessageWithReply`; consumed (and cleared) synchronously at the
  /// top of that call so the label is attributed to exactly that send.
  bool _relayLiveSendActive = false;

  String? lastSentPeerId;
  String? lastSentMessage;
  String? lastInboxPeerId;
  String? lastInboxMessage;

  // Callback hooks for cross-component ordering tests
  VoidCallback? onDiscover;
  VoidCallback? onSendMessage;
  String? lastSentPayload;

  // Local peer support
  final Set<String> localPeers = {};
  bool localSendResult = true;
  int localSendCallCount = 0;
  int? lastLocalSendTimeoutMs;
  int recordSuccessfulSendProofCallCount = 0;
  String? lastReadinessProofSource;
  String? lastReadinessTrigger;
  String? lastReadinessSendPath;

  /// Use [useNullDiscover] to explicitly request null discoverPeer results.
  FakeP2PService({
    NodeState? currentState,
    this.sendMessageResult = true,
    this.sendMessageReply = 'received: ok',
    this.sendMessageAcked = true,
    this.sendMessageTransport,
    this.shouldThrow = false,
    this.storeInInboxResult = false,
    this.probeRelayResult = RelayProbeResult.error,
    DiscoveredPeer? discoverPeerResult,
    bool useNullDiscover = false,
    this.dialPeerResult = true,
  }) : _currentState = currentState ?? const NodeState(isStarted: true),
       discoverPeerResult = useNullDiscover
           ? null
           : (discoverPeerResult ??
                 const DiscoveredPeer(
                   id: 'target-peer',
                   addresses: ['/ip4/127.0.0.1/tcp/4001'],
                 ));

  @override
  NodeState get currentState => _currentState;

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    if (shouldThrow) throw Exception('Send failed');
    lastSentPeerId = peerId;
    lastSentMessage = message;
    sendCallCount++;
    return sendMessageResult;
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendTimeouts.add(timeoutMs);
    // FDC-02 (C2): capture the relay-live marker SYNCHRONOUSLY before any await,
    // so the relay-live leg's send is labeled distinctly from the direct/reuse
    // sends that share this method. noteRelayLiveSendStart() is fired by
    // _tryRelayLiveSend immediately before this call (single-threaded, no await
    // in between), so the flag belongs to exactly this invocation.
    final isRelayLive = _relayLiveSendActive;
    _relayLiveSendActive = false;
    final queuedResult = queuedSendMessageResults.isEmpty
        ? null
        : queuedSendMessageResults.removeAt(0);
    if (shouldThrow) throw Exception('Send failed');
    lastSentPeerId = peerId;
    lastSentMessage = message;
    lastSentPayload = message;
    sendCallCount++;
    onSendMessage?.call();
    Future<SendMessageResult> complete() async {
      if (sendDelay > Duration.zero) {
        await Future<void>.delayed(sendDelay);
      }
      if (queuedResult != null) return queuedResult;
      return SendMessageResult(
        sent: sendMessageResult,
        acked: sendMessageAcked,
        reply: sendMessageReply,
        transport: isRelayLive
            ? (relayLiveSendTransport ?? 'relay')
            : sendMessageTransport,
      );
    }

    final completion = complete();
    if (timeoutMs == null) return completion;
    return completion.timeout(
      Duration(milliseconds: timeoutMs),
      onTimeout: () => const SendMessageResult(sent: false),
    );
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    discoverTimeouts.add(timeoutMs);
    discoverCallCount++;
    onDiscover?.call();
    if (shouldThrow && discoverCallCount == 1) {
      throw Exception('Discover failed');
    }
    if (discoverDelay > Duration.zero) {
      final nativeBudget = timeoutMs == null
          ? null
          : Duration(milliseconds: timeoutMs);
      if (nativeBudget != null && discoverDelay > nativeBudget) {
        await Future<void>.delayed(nativeBudget);
        return null;
      }
      await Future<void>.delayed(discoverDelay);
    }
    return discoverPeerResult;
  }

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async {
    dialTimeouts.add(timeoutMs);
    dialCallCount++;
    return dialPeerResult;
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    storeInInboxCallCount++;
    lastInboxPeerId = toPeerId;
    lastInboxMessage = message;
    return storeInInboxResult;
  }

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
  bool isLocalPeer(String peerId) => localPeers.contains(peerId);

  int discoverLocalPeerCallCount = 0;
  Duration? lastDiscoverLocalPeerTimeout;

  /// Optional override for the discover-on-send result. When non-null this is
  /// returned instead of the default `localPeers.contains` behavior; setting it
  /// to true (without seeding [localPeers]) simulates an unknown-but-LAN-present
  /// peer that mDNS resolves at send time (U3).
  bool? discoverLocalPeerResult;

  /// When > 0, [discoverLocalPeer] delays this long before resolving (still
  /// bounded by the caller's timeout) to model a bounded resolve that joins the
  /// race within budget.
  Duration discoverLocalPeerDelay = Duration.zero;

  /// NET-REL-05 U-P3 (sticky): seeds the learned-per-peer transport read at the
  /// top of the race. Learned direct/relay may attempt authenticated reuse;
  /// learned local remains routing metadata and enters the normal proof race.
  String? lastKnownGoodTransportResult;

  /// NET-REL-05 U-P3: records of `recordSuccessfulTransport` writes so a test
  /// can assert the live transport that delivered was remembered.
  int recordSuccessfulTransportCallCount = 0;
  String? lastRecordedTransport;
  String? lastRecordedTransportPeerId;

  /// NET-REL-05 U-P2 (grace) / U-P5 (budget): per-leg artificial latency so a
  /// test can model a transport landing slightly behind another (grace) or a
  /// leg overrunning its budget. [sendDelay] gates the direct/reuse/relay
  /// `sendMessageWithReply`; [localSendDelay] gates `sendLocalMessage`.
  Duration sendDelay = Duration.zero;
  Duration localSendDelay = Duration.zero;

  /// FDC-01: per-call discover latency so a test can model a slow-but-online
  /// discover that approaches/exceeds the per-step direct budget. Mirrors
  /// [sendDelay]/[localSendDelay]; honored at the top of [discoverPeer]. Default
  /// zero leaves every existing test unchanged (discoverPeer awaited no delay
  /// before FDC-01).
  Duration discoverDelay = Duration.zero;

  @override
  String? lastKnownGoodTransport(String peerId) => lastKnownGoodTransportResult;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {
    recordSuccessfulTransportCallCount++;
    lastRecordedTransport = transport;
    lastRecordedTransportPeerId = peerId;
  }

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async {
    discoverLocalPeerCallCount++;
    lastDiscoverLocalPeerTimeout = timeout;
    if (discoverLocalPeerDelay > Duration.zero) {
      await Future<void>.delayed(discoverLocalPeerDelay);
    }
    final resolved = discoverLocalPeerResult ?? localPeers.contains(peerId);
    // A successful discover-on-send makes the peer reachable for the
    // subsequent sendLocalMessage call, mirroring the production map write.
    if (resolved) {
      localPeers.add(peerId);
    }
    // Negative-control default: not discovered unless the peer is already local.
    return resolved;
  }

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    localSendCallCount++;
    lastLocalSendTimeoutMs = timeoutMs;
    if (localSendDelay > Duration.zero) {
      await Future<void>.delayed(localSendDelay);
    }
    lastSentPeerId = peerId;
    lastSentMessage = message;
    return localSendResult;
  }

  /// TC-187-20: lets a test model warmPeer having already reconnected the peer
  /// (the pre-ping window) so the reuse/connected precedence — never the skip —
  /// is exercised. Default false preserves every existing test.
  bool isConnectedToPeerResult = false;

  @override
  bool isConnectedToPeer(String peerId) => isConnectedToPeerResult;

  /// 187 (PeerDropSignal) — the keepalive's per-peer suspected-dropped set.
  /// Keyed by the NORMALIZED active key, mirroring P2PServiceImpl, so a raw send
  /// target matches a mark made against the tracker's normalized key.
  final Set<String> suspectedDroppedPeers = {};

  @override
  bool isPeerSuspectedDropped(String peerId) => suspectedDroppedPeers.contains(
    ActiveConversationTracker.normalizeActiveKey(peerId),
  );

  @override
  void setPeerDropSuspected(String peerId, bool dropped) {
    final key = ActiveConversationTracker.normalizeActiveKey(peerId);
    if (dropped) {
      suspectedDroppedPeers.add(key);
    } else {
      suspectedDroppedPeers.remove(key);
    }
  }

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async {
    probeRelayCallCount++;
    return probeRelayResult;
  }

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
    bool enc = false,
    String? encScheme,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

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
  }) {
    recordSuccessfulSendProofCallCount++;
    lastReadinessProofSource = source;
    lastReadinessTrigger = trigger;
    lastReadinessSendPath = sendPath;
  }

  @override
  String? get lastRecoveryMethod => null;

  @override
  void noteRelayLiveSendStart() {
    relayLiveSendCount++;
    _relayLiveSendActive = true;
  }

  @override
  void dispose() {}
}

class DurableLanFakeP2PService extends FakeP2PService
    implements DurableLanSender {
  LanSendAck localSendAck;
  Future<LanSendAck>? controlledLocalSendAck;

  DurableLanFakeP2PService({
    this.localSendAck = LanSendAck.committed,
    super.currentState,
    super.sendMessageResult,
    super.sendMessageReply,
    super.sendMessageAcked,
    super.sendMessageTransport,
    super.shouldThrow,
    super.storeInInboxResult,
    super.probeRelayResult,
    super.discoverPeerResult,
    super.useNullDiscover,
    super.dialPeerResult,
  });

  @override
  Future<LanSendAck> sendLocalMessageDurable(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    localSendCallCount++;
    lastLocalSendTimeoutMs = timeoutMs;
    if (localSendDelay > Duration.zero) {
      await Future<void>.delayed(localSendDelay);
    }
    lastSentPeerId = peerId;
    lastSentMessage = message;
    if (!localSendResult) return LanSendAck.failed;
    if (controlledLocalSendAck case final controlled?) {
      return controlled;
    }
    return localSendAck;
  }

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async =>
      await sendLocalMessageDurable(
        peerId,
        message,
        fromPeerId,
        timeoutMs: timeoutMs,
      ) ==
      LanSendAck.committed;
}

/// Timeout-aware orchestration fake for the R3 absolute-deadline contract.
class _R3DeadlineP2PService extends FakeP2PService {
  _R3DeadlineP2PService({
    super.currentState,
    super.sendMessageTransport,
    super.storeInInboxResult,
  });

  final List<Duration> scriptedSendDelays = [];
  Duration scriptedDiscoverDelay = Duration.zero;
  Duration scriptedDialDelay = Duration.zero;
  int _sendDelayIndex = 0;

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    discoverTimeouts.add(timeoutMs);
    discoverCallCount++;
    onDiscover?.call();
    final nativeBudget = timeoutMs == null
        ? null
        : Duration(milliseconds: timeoutMs);
    if (nativeBudget != null && scriptedDiscoverDelay > nativeBudget) {
      await Future<void>.delayed(nativeBudget);
      return null;
    }
    if (scriptedDiscoverDelay > Duration.zero) {
      await Future<void>.delayed(scriptedDiscoverDelay);
    }
    return discoverPeerResult;
  }

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async {
    dialTimeouts.add(timeoutMs);
    dialCallCount++;
    final nativeBudget = timeoutMs == null
        ? null
        : Duration(milliseconds: timeoutMs);
    if (nativeBudget != null && scriptedDialDelay > nativeBudget) {
      await Future<void>.delayed(nativeBudget);
      return false;
    }
    if (scriptedDialDelay > Duration.zero) {
      await Future<void>.delayed(scriptedDialDelay);
    }
    return dialPeerResult;
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendTimeouts.add(timeoutMs);
    final delay = _sendDelayIndex < scriptedSendDelays.length
        ? scriptedSendDelays[_sendDelayIndex++]
        : Duration.zero;
    final nativeBudget = timeoutMs == null
        ? null
        : Duration(milliseconds: timeoutMs);
    if (nativeBudget != null && delay > nativeBudget) {
      await Future<void>.delayed(nativeBudget);
      sendCallCount++;
      lastSentPeerId = peerId;
      lastSentMessage = message;
      lastSentPayload = message;
      onSendMessage?.call();
      return const SendMessageResult(sent: false);
    }
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final result = await super.sendMessageWithReply(
      peerId,
      message,
      timeoutMs: timeoutMs,
    );
    // This fake records at invocation; the base records once more when the
    // scripted delay hands off. Keep one observation per native call.
    sendTimeouts.removeLast();
    return result;
  }
}

class _R3DelayedCryptoBridge extends PassthroughCryptoBridge {
  _R3DelayedCryptoBridge(this.encryptDelay);

  final Duration encryptDelay;

  @override
  Future<String> send(String message) async {
    final command = (jsonDecode(message) as Map<String, dynamic>)['cmd'];
    if (command == 'message.encrypt' && encryptDelay > Duration.zero) {
      await Future<void>.delayed(encryptDelay);
    }
    return super.send(message);
  }
}

// -- Fake Message Repository --
class FakeMessageRepository
    implements MessageRepository, OutgoingTransportMutationRepository {
  final List<ConversationMessage> saved = [];

  // Section 4: wireEnvelope tracking
  final List<String> wireEnvelopeUpdates = [];
  String? lastWireEnvelopeValue;
  VoidCallback? onUpdateWireEnvelope;

  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {
    wireEnvelopeUpdates.add(id);
    lastWireEnvelopeValue = envelope;
    onUpdateWireEnvelope?.call();
  }

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    saved.add(message);
    existingMessages[message.id] = message;
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async => [];

  /// NET-REL-05 U-P1P4 (concurrent fallback): seeds the prior-attempt the
  /// low-confidence heuristic inspects. Null (default) = no prior attempt =
  /// high-confidence (single-path).
  ConversationMessage? latestMessageForContact;
  int getLatestMessageForContactCallCount = 0;

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    getLatestMessageForContactCallCount++;
    return latestMessageForContact;
  }

  /// 184: records every (id, status) updateMessageStatus call so the mid-send
  /// custody bump (a status-only 'inboxed' update on the existing optimistic
  /// row) is observable distinct from the full-row [saved] list above.
  final List<(String, String)> statusUpdates = [];

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    statusUpdates.add((id, status));
    final current = existingMessages[id];
    if (current != null) {
      _remember(current.copyWith(status: status));
    }
  }

  /// 116 P2: seedable rows for the no-downgrade writer gate's
  /// `getMessage(messageId)` lookup. Empty by default (legacy behavior).
  final Map<String, ConversationMessage> existingMessages = {};

  @override
  Future<ConversationMessage?> getMessage(String id) async =>
      existingMessages[id];

  @override
  Future<bool> messageExists(String id) async =>
      existingMessages.containsKey(id);

  @override
  Future<bool> existsByContent(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  ) async => false;

  @override
  Future<bool> existsByDedupKey(
    String contactPeerId,
    String senderPeerId,
    String dedupKey,
  ) async => false;

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
  Future<int> recoverStuckSendingMessages({
    required Duration olderThan,
  }) async => 0;

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
  }) async {
    final current = existingMessages[id];
    if (current == null || current.status != fromStatus) return 0;
    _remember(current.copyWith(status: toStatus));
    return 1;
  }

  final List<
    ({
      ConversationMessage? expected,
      ConversationMessage staged,
      OutgoingOrdinaryAttemptKind kind,
    })
  >
  ordinaryStageCalls = [];
  final List<
    ({
      String messageId,
      String expectedContactPeerId,
      String? expectedEnvelope,
      String status,
      String? transport,
      int? relayExpiresAt,
      OutgoingOrdinarySettlementMode mode,
      bool tombstone,
    })
  >
  ordinarySettlementCalls = [];
  OutgoingOrdinaryMutationOutcome? forcedStageOutcome;
  VoidCallback? onOrdinaryStage;
  ConversationMessage Function(ConversationMessage staged)?
  authoritativeStageProjection;

  void forceCurrent(ConversationMessage message) => _remember(message);

  void _remember(ConversationMessage message) {
    existingMessages[message.id] = message;
    final index = saved.indexWhere((candidate) => candidate.id == message.id);
    if (index < 0) {
      saved.add(message);
    } else {
      saved[index] = message;
    }
  }

  OutgoingOrdinaryMutationResult _ordinaryResult(
    OutgoingOrdinaryMutationOutcome outcome,
    ConversationMessage? message,
  ) => OutgoingOrdinaryMutationResult(outcome: outcome, message: message);

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttempt({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
  }) async {
    ordinaryStageCalls.add((expected: expected, staged: staged, kind: kind));
    onOrdinaryStage?.call();
    final current = existingMessages[staged.id];
    final forced = forcedStageOutcome;
    if (forced != null && forced != OutgoingOrdinaryMutationOutcome.applied) {
      return _ordinaryResult(forced, current);
    }
    if (kind == OutgoingOrdinaryAttemptKind.fresh) {
      if (expected != null || current != null) {
        return _ordinaryResult(
          OutgoingOrdinaryMutationOutcome.refused,
          current,
        );
      }
    } else {
      if (expected == null) {
        return _ordinaryResult(
          OutgoingOrdinaryMutationOutcome.refused,
          current,
        );
      }
      if (current == null) {
        return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
      }
      if (current.toMap().toString() != expected.toMap().toString()) {
        return _ordinaryResult(
          OutgoingOrdinaryMutationOutcome.preserved,
          current,
        );
      }
    }
    final authoritative = authoritativeStageProjection?.call(staged) ?? staged;
    _remember(authoritative);
    return _ordinaryResult(
      OutgoingOrdinaryMutationOutcome.applied,
      authoritative,
    );
  }

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryTransport({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) => _settleOrdinary(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
    mode: mode,
    tombstone: false,
  );

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryDeleteTombstone({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) => _settleOrdinary(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
    mode: mode,
    tombstone: true,
  );

  Future<OutgoingOrdinaryMutationResult> _settleOrdinary({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
    required bool tombstone,
  }) async {
    ordinarySettlementCalls.add((
      messageId: messageId,
      expectedContactPeerId: expectedContactPeerId,
      expectedEnvelope: expectedEnvelope,
      status: status,
      transport: transport,
      relayExpiresAt: relayExpiresAt,
      mode: mode,
      tombstone: tombstone,
    ));
    final current = existingMessages[messageId];
    if (current == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    if (current.isIncoming ||
        current.contactPeerId != expectedContactPeerId ||
        current.isDeleted != tombstone) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    if (current.status == 'delivered') {
      return _ordinaryResult(
        status == 'delivered'
            ? OutgoingOrdinaryMutationOutcome.idempotent
            : OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    if (current.wireEnvelope != expectedEnvelope) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    final predecessors = mode == OutgoingOrdinarySettlementMode.receipt
        ? const <String>{'inboxed', 'sent', 'failed'}
        : switch (status) {
            'delivered' => const <String>{
              'sending',
              'sent',
              'inboxed',
              'failed',
            },
            'inboxed' => const <String>{'sending', 'sent', 'failed'},
            'sent' => const <String>{'sending', 'failed'},
            'failed' => const <String>{'sending'},
            _ => const <String>{},
          };
    if (!predecessors.contains(current.status)) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    final settled = current.copyWith(
      status: status,
      transport: transport,
      wireEnvelope: status == 'delivered' ? null : expectedEnvelope,
      relayExpiresAt: relayExpiresAt,
      custodyCheckedAt: null,
      hiddenAt: tombstone && status == 'delivered' ? current.deletedAt : null,
    );
    _remember(settled);
    return _ordinaryResult(OutgoingOrdinaryMutationOutcome.applied, settled);
  }

  @override
  Future<OutgoingOrdinaryMutationResult> invalidateOutgoingOrdinaryEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
  }) async => _ordinaryResult(
    OutgoingOrdinaryMutationOutcome.refused,
    existingMessages[messageId],
  );

  @override
  Future<OutgoingOrdinaryMutationResult>
  quarantineUnsafeLegacyOutgoingEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
    required bool isDeleteTombstone,
  }) async => _ordinaryResult(
    OutgoingOrdinaryMutationOutcome.refused,
    existingMessages[messageId],
  );
}

class _MessageRepositoryWithoutOrdinaryCapability implements MessageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockedPrivateSettlementP2PService extends FakeP2PService {
  final Completer<void> transportStarted = Completer<void>();
  final Completer<void> releaseTransport = Completer<void>();

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    lastSentPeerId = peerId;
    lastSentMessage = message;
    sendCallCount++;
    if (!transportStarted.isCompleted) transportStarted.complete();
    await releaseTransport.future;
    return const SendMessageResult(
      sent: true,
      acked: true,
      reply: 'received: ok',
      transport: 'direct',
    );
  }
}

class _PrivateCustodyMessageRepository extends FakeMessageRepository
    implements OutgoingDirectPrivateEnvelopeCustodyRepository {
  _PrivateCustodyMessageRepository(this.current);

  ConversationMessage current;
  int settlementCalls = 0;
  OutgoingDirectPrivateTransportSettlementOutcome? lastSettlementOutcome;

  void hideAndConsume() {
    current = current.copyWith(
      hiddenAt: '2026-07-20T09:00:01.000Z',
      privateMediaState: PrivateMediaLifecycleState.consumed,
      privateMediaTerminalAtMs: 1100,
    );
  }

  @override
  Future<ConversationMessage?> getMessage(String id) async =>
      id == current.id ? current : null;

  @override
  Future<bool> invalidateWireEnvelopeBeforePrivateUpload({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  }) async => false;

  @override
  Future<bool> markOutgoingDirectPrivateUploadHandoffFailed({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  }) async => false;

  @override
  Future<OutgoingDirectPrivateEnvelopeHandoffOutcome>
  commitOutgoingDirectPrivateWireEnvelope({
    required String messageId,
    required MediaAttachment completedAttachment,
    required String expectedPendingLocalPath,
    required String envelope,
    required bool hasOwnedPendingCompletion,
  }) async {
    if (messageId != current.id ||
        completedAttachment.messageId != messageId ||
        current.hiddenAt != null ||
        current.deletedAt != null) {
      return OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
    }
    current = current.copyWith(wireEnvelope: envelope);
    return OutgoingDirectPrivateEnvelopeHandoffOutcome.committed;
  }

  @override
  Future<OutgoingDirectPrivateTransportSettlementOutcome>
  settleOutgoingDirectPrivateTransport({
    required String messageId,
    required String? attachmentId,
    required String expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
  }) async {
    settlementCalls++;
    if (current.hiddenAt != null || current.deletedAt != null) {
      lastSettlementOutcome =
          OutgoingDirectPrivateTransportSettlementOutcome.preservedUserIntent;
      return lastSettlementOutcome!;
    }
    if (messageId != current.id || current.wireEnvelope != expectedEnvelope) {
      lastSettlementOutcome =
          OutgoingDirectPrivateTransportSettlementOutcome.refused;
      return lastSettlementOutcome!;
    }
    current = current.copyWith(
      status: status,
      transport: transport,
      relayExpiresAt: relayExpiresAt,
      wireEnvelope: status == 'delivered' ? null : expectedEnvelope,
    );
    lastSettlementOutcome =
        OutgoingDirectPrivateTransportSettlementOutcome.committed;
    return lastSettlementOutcome!;
  }
}

class _PrivateMutationMediaRepository extends FakeMediaAttachmentRepository
    implements OutgoingDirectPrivateMutationRepository {
  final MediaAttachmentLifecycleLock _lifecycleLock =
      MediaAttachmentLifecycleLock();

  late final OutgoingDirectPrivateMutationCoordinator _coordinator =
      OutgoingDirectPrivateMutationCoordinator(
        lifecycleLock: _lifecycleLock,
        classifyCompletion: (_, _) async =>
            OutgoingDirectPrivateCompletionQualification.refused,
        commitAvailable: (_, _) async => false,
        commitRollback: (_, _, {required mode}) async => false,
      );

  @override
  OutgoingDirectPrivateMutationCoordinator
  get outgoingDirectPrivateMutationCoordinator => _coordinator;

  @override
  Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
  applyOutgoingDirectPrivateNonCompletionMutation(
    MediaAttachment attachment,
  ) async => OutgoingDirectPrivateNonCompletionMutationOutcome.refused;

  @override
  Future<OutgoingDirectPrivatePendingPreparationOutcome>
  prepareOutgoingDirectPrivatePendingAttachments(
    List<MediaAttachment> attachments,
  ) async => OutgoingDirectPrivatePendingPreparationOutcome.refused;

  @override
  Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
  deleteOutgoingDirectPrivatePendingAttachmentsForMessage(
    String messageId, {
    required MediaFileManager mediaFileManager,
  }) async => OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
}

class _StaticIdentityRepository implements IdentityRepository {
  _StaticIdentityRepository(this.identity);

  final IdentityModel identity;

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

Future<List<String>> capturePrintedLines(Future<void> Function() action) async {
  final printed = <String>[];
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await runZoned(
      action,
      zoneSpecification: ZoneSpecification(
        print: (_, parent, zone, line) {
          printed.add(line);
        },
      ),
    );
  } finally {
    debugPrint = originalDebugPrint;
  }
  return printed;
}

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

void expectSendFlowEventsOmitMessagePreview(
  List<Map<String, dynamic>> events, {
  required String terminalEvent,
  required Iterable<String> forbiddenFragments,
}) {
  final sendEvents = events
      .where(
        (event) =>
            (event['event'] as String?)?.startsWith('CHAT_MSG_SEND_') ?? false,
      )
      .toList();
  final sendEventNames = sendEvents.map((event) => event['event']).toList();
  expect(sendEventNames, contains('CHAT_MSG_SEND_START'));
  expect(sendEventNames, contains(terminalEvent));

  for (final event in sendEvents) {
    final details = event['details'];
    if (details is Map) {
      expect(
        details.containsKey('textPreview'),
        isFalse,
        reason: '${event['event']} exposed a textPreview detail',
      );
    }
  }

  final serializedPayload = jsonEncode(sendEvents);
  for (final fragment in forbiddenFragments) {
    expect(serializedPayload, isNot(contains(fragment)));
  }
}

const testRecipientMlKemPublicKey = 'recipient-mlkem-public-key';

Future<(SendChatMessageResult, ConversationMessage?)> sendChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String action = MessagePayload.actionSend,
  String? editedAt,
  String? messageId,
  String? timestamp,
  String? createdAt,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  PrivateMediaPolicy? privateMediaPolicy,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
  TransportMetrics? transportMetrics,
  bool? preassignedMessageIdIsFresh,
}) {
  return chat_use_case.sendChatMessage(
    p2pService: p2pService,
    messageRepo: messageRepo,
    targetPeerId: targetPeerId,
    text: text,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    action: action,
    editedAt: editedAt,
    messageId: messageId,
    preassignedMessageIdIsFresh:
        preassignedMessageIdIsFresh ?? messageId != null,
    timestamp: timestamp,
    createdAt: createdAt,
    bridge: bridge ?? PassthroughCryptoBridge(),
    recipientMlKemPublicKey:
        recipientMlKemPublicKey ?? testRecipientMlKemPublicKey,
    quotedMessageId: quotedMessageId,
    mediaAttachments: mediaAttachments,
    privateMediaPolicy: privateMediaPolicy,
    mediaAttachmentRepo:
        mediaAttachmentRepo ??
        ((mediaAttachments?.isNotEmpty ?? false)
            ? FakeMediaAttachmentRepository()
            : null),
    emitTimingEvent: emitTimingEvent,
    transportMetrics: transportMetrics,
  );
}

Future<(SendChatMessageResult, ConversationMessage?)> editChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage originalMessage,
  required String updatedText,
  required String senderUsername,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
}) {
  if (messageRepo is FakeMessageRepository) {
    messageRepo.existingMessages[originalMessage.id] = originalMessage;
  }
  return chat_use_case.editChatMessage(
    p2pService: p2pService,
    messageRepo: messageRepo,
    originalMessage: originalMessage,
    updatedText: updatedText,
    senderUsername: senderUsername,
    bridge: bridge ?? PassthroughCryptoBridge(),
    recipientMlKemPublicKey:
        recipientMlKemPublicKey ?? testRecipientMlKemPublicKey,
    mediaAttachmentRepo: mediaAttachmentRepo,
    emitTimingEvent: emitTimingEvent,
  );
}

Map<String, dynamic> decodeWirePayload(String wireJson) {
  final envelope = jsonDecode(wireJson) as Map<String, dynamic>;
  final payload = envelope['payload'];
  if (payload is Map<String, dynamic>) {
    return payload;
  }
  final encrypted = envelope['encrypted'] as Map<String, dynamic>;
  return jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
}

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;

  setUp(() {
    p2pService = FakeP2PService();
    messageRepo = FakeMessageRepository();
  });

  test(
    'relayProbeSendAttempts remains one for live introduction and delete consumers',
    () {
      expect(relayProbeSendAttempts, 1);
    },
  );

  group('sendChatMessage', () {
    test(
      'attempt staging is authoritative before transport and late terminal work cannot replace delivery',
      () async {
        const attachment = MediaAttachment(
          id: 'atomic-send-attachment',
          messageId: '',
          mime: 'image/png',
          size: 12,
          mediaType: 'image',
          localPath: 'pending_uploads/source.png',
          downloadStatus: 'upload_pending',
          createdAt: '2026-08-05T11:00:00.000Z',
          contentHash: 'atomic-send-content-hash',
          encryptionKeyBase64: 'atomic-send-key',
          encryptionNonce: 'atomic-send-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        final mediaRepo = FakeMediaAttachmentRepository();
        final stagedBeforeTransport = <bool>[];
        p2pService
          ..isConnectedToPeerResult = true
          ..sendMessageAcked = true
          ..sendMessageTransport = 'direct'
          ..onSendMessage = () {
            stagedBeforeTransport.add(
              messageRepo.ordinaryStageCalls.length == 1,
            );
            final staged = messageRepo.existingMessages.values.single;
            expect(staged.status, 'sending');
            expect(staged.wireEnvelope, isNotEmpty);
            expect(staged.media.single.id, 'atomic-send-attachment');
          };
        messageRepo.authoritativeStageProjection = (staged) =>
            staged.copyWith(text: 'authoritative staged parent');

        final (generatedResult, generatedMessage) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'candidate parent',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: const <MediaAttachment>[attachment],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(generatedResult, SendChatMessageResult.success);
        expect(stagedBeforeTransport, <bool>[true]);
        expect(
          messageRepo.ordinaryStageCalls.single.kind,
          OutgoingOrdinaryAttemptKind.fresh,
        );
        expect(messageRepo.wireEnvelopeUpdates, isEmpty);
        expect(messageRepo.statusUpdates, isEmpty);
        expect(messageRepo.ordinarySettlementCalls, isNotEmpty);
        expect(
          messageRepo.ordinarySettlementCalls.last.mode,
          OutgoingOrdinarySettlementMode.live,
        );
        expect(generatedMessage!.text, 'authoritative staged parent');
        expect(generatedMessage.status, 'delivered');
        expect(generatedMessage.media.single.id, 'atomic-send-attachment');
        expect(
          mediaRepo.allSavedAttachments,
          isEmpty,
          reason:
              'combined staging is the only attachment writer; terminal work '
              'must not call saveAttachment',
        );

        const existingId = 'successful-existing-attempt';
        const existingTimestamp = '2026-08-05T11:10:00.000Z';
        final existingParent = ConversationMessage(
          id: existingId,
          contactPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          text: 'retry existing payload',
          timestamp: existingTimestamp,
          status: 'failed',
          isIncoming: false,
          createdAt: existingTimestamp,
          dedupKey: 'successful-existing-dedup',
        );
        final existingRepo = FakeMessageRepository()
          ..forceCurrent(existingParent);
        var existingTransportEntries = 0;
        final existingP2P = FakeP2PService()
          ..isConnectedToPeerResult = true
          ..sendMessageAcked = true
          ..sendMessageTransport = 'direct';
        existingP2P.onSendMessage = () {
          existingTransportEntries++;
          expect(existingRepo.ordinaryStageCalls, hasLength(1));
          expect(
            existingRepo.ordinaryStageCalls.single.kind,
            OutgoingOrdinaryAttemptKind.existing,
          );
          final staged = existingRepo.existingMessages[existingId];
          expect(staged, isNotNull);
          expect(staged!.status, 'sending');
          expect(staged.wireEnvelope, isNotEmpty);
          expect(staged.wireEnvelope, existingP2P.lastSentMessage);
        };
        final (existingResult, existingMessage) = await sendChatMessage(
          p2pService: existingP2P,
          messageRepo: existingRepo,
          targetPeerId: 'target-peer',
          text: existingParent.text,
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: existingId,
          timestamp: existingTimestamp,
          createdAt: existingTimestamp,
          preassignedMessageIdIsFresh: false,
        );
        expect(existingResult, SendChatMessageResult.success);
        expect(existingMessage!.status, 'delivered');
        expect(existingTransportEntries, 1);

        const editId = 'successful-edit-attempt';
        const editTimestamp = '2026-08-05T11:20:00.000Z';
        final originalForEdit = ConversationMessage(
          id: editId,
          contactPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          text: 'before authoritative edit',
          timestamp: editTimestamp,
          status: 'delivered',
          isIncoming: false,
          createdAt: editTimestamp,
          transport: 'direct',
          dedupKey: 'successful-edit-dedup',
        );
        final editRepo = FakeMessageRepository();
        var editTransportEntries = 0;
        final editP2P = FakeP2PService()
          ..isConnectedToPeerResult = true
          ..sendMessageAcked = true
          ..sendMessageTransport = 'direct';
        editP2P.onSendMessage = () {
          editTransportEntries++;
          expect(editRepo.ordinaryStageCalls, hasLength(1));
          expect(
            editRepo.ordinaryStageCalls.single.kind,
            OutgoingOrdinaryAttemptKind.edit,
          );
          final staged = editRepo.existingMessages[editId];
          expect(staged, isNotNull);
          expect(staged!.status, 'sending');
          expect(staged.text, 'after authoritative edit');
          expect(staged.editedAt, isNotNull);
          expect(staged.wireEnvelope, isNotEmpty);
          expect(staged.wireEnvelope, editP2P.lastSentMessage);
        };
        final (editResult, editedMessage) = await editChatMessage(
          p2pService: editP2P,
          messageRepo: editRepo,
          originalMessage: originalForEdit,
          updatedText: 'after authoritative edit',
          senderUsername: 'Me',
        );
        expect(editResult, SendChatMessageResult.success);
        expect(editedMessage!.status, 'delivered');
        expect(editedMessage.text, 'after authoritative edit');
        expect(editTransportEntries, 1);

        final missingExistingP2P = FakeP2PService();
        final missingExistingRepo = FakeMessageRepository();
        final (
          missingExistingResult,
          missingExistingMessage,
        ) = await sendChatMessage(
          p2pService: missingExistingP2P,
          messageRepo: missingExistingRepo,
          targetPeerId: 'target-peer',
          text: 'missing existing row',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: 'missing-existing-id',
          preassignedMessageIdIsFresh: false,
        );
        expect(missingExistingResult, SendChatMessageResult.sendFailed);
        expect(missingExistingMessage, isNull);
        expect(
          missingExistingRepo.ordinaryStageCalls.single.kind,
          OutgoingOrdinaryAttemptKind.existing,
        );
        expect(missingExistingP2P.sendCallCount, 0);
        expect(missingExistingP2P.localSendCallCount, 0);
        expect(missingExistingP2P.storeInInboxCallCount, 0);

        final missingCapabilityP2P = FakeP2PService();
        final (
          missingCapabilityResult,
          missingCapabilityMessage,
        ) = await sendChatMessage(
          p2pService: missingCapabilityP2P,
          messageRepo: _MessageRepositoryWithoutOrdinaryCapability(),
          targetPeerId: 'target-peer',
          text: 'missing capability',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(missingCapabilityResult, SendChatMessageResult.sendFailed);
        expect(missingCapabilityMessage, isNull);
        expect(missingCapabilityP2P.sendCallCount, 0);
        expect(missingCapabilityP2P.localSendCallCount, 0);
        expect(missingCapabilityP2P.storeInInboxCallCount, 0);

        final refusedP2P = FakeP2PService();
        final refusedRepo = FakeMessageRepository()
          ..forcedStageOutcome = OutgoingOrdinaryMutationOutcome.refused;
        final (refusedResult, refusedMessage) = await sendChatMessage(
          p2pService: refusedP2P,
          messageRepo: refusedRepo,
          targetPeerId: 'target-peer',
          text: 'refused stage',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(refusedResult, SendChatMessageResult.sendFailed);
        expect(refusedMessage, isNull);
        expect(refusedP2P.sendCallCount, 0);
        expect(refusedP2P.localSendCallCount, 0);
        expect(refusedP2P.storeInInboxCallCount, 0);

        final concurrentP2P = FakeP2PService()
          ..isConnectedToPeerResult = true
          ..sendMessageAcked = true
          ..sendMessageTransport = 'direct';
        final concurrentRepo = FakeMessageRepository();
        concurrentP2P.onSendMessage = () {
          final staged = concurrentRepo.existingMessages.values.single;
          concurrentRepo.forceCurrent(
            staged.copyWith(
              text: 'concurrent durable delivery',
              status: 'delivered',
              transport: 'direct',
              wireEnvelope: null,
            ),
          );
        };
        final (concurrentResult, concurrentMessage) = await sendChatMessage(
          p2pService: concurrentP2P,
          messageRepo: concurrentRepo,
          targetPeerId: 'target-peer',
          text: 'stale terminal candidate',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(concurrentResult, SendChatMessageResult.success);
        expect(concurrentMessage!.status, 'delivered');
        expect(concurrentMessage.text, 'concurrent durable delivery');
        expect(concurrentMessage.wireEnvelope, isNull);
        expect(concurrentRepo.ordinarySettlementCalls.last.status, 'delivered');
        expect(concurrentRepo.saved.single.text, 'concurrent durable delivery');
      },
    );

    test(
      'valid private policy is encrypted-inner-only and persists on parent',
      () async {
        const attachment = MediaAttachment(
          id: 'private-valid-blob',
          messageId: '',
          mime: 'image/jpeg',
          size: 1024,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-07-11T09:00:00.000Z',
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          encryptionKeyBase64: 'private-key',
          encryptionNonce: 'private-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        final policy = PrivateMediaPolicy.disappearing(86400);
        final bridge = FakeBridge(
          initialResponses: {
            'message.encrypt': {
              'ok': true,
              'kem': 'opaque-kem',
              'ciphertext': 'opaque-private-ciphertext',
              'nonce': 'opaque-nonce',
            },
          },
        );
        late SendChatMessageResult result;
        ConversationMessage? message;

        final events = await captureFlowEvents(() async {
          (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: '',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: bridge,
            mediaAttachments: const [attachment],
            privateMediaPolicy: policy,
          );
        });

        expect(result, SendChatMessageResult.success);
        expect(message?.privateMediaPolicy, policy);
        expect(
          message?.privateMediaState,
          PrivateMediaLifecycleState.available,
        );
        expect(messageRepo.saved.single.privateMediaPolicy, policy);

        final encryptCommand = bridge.sentMessages
            .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
            .singleWhere((command) => command['cmd'] == 'message.encrypt');
        final plaintext =
            (encryptCommand['payload'] as Map<String, dynamic>)['plaintext']
                as String;
        final inner = jsonDecode(plaintext) as Map<String, dynamic>;
        expect(inner['privateMedia'], {
          'version': 1,
          'mode': 'disappearing',
          'durationSeconds': 86400,
        });

        final outer =
            jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
        expect(outer['version'], '2');
        expect(outer.containsKey('payload'), isFalse);
        expect(outer.containsKey('privateMedia'), isFalse);
        final outerJson = jsonEncode(outer);
        for (final forbidden in [
          'privateMedia',
          'disappearing',
          'durationSeconds',
          'private-valid-blob',
          'image/jpeg',
          'private-key',
        ]) {
          expect(outerJson, isNot(contains(forbidden)));
          expect(jsonEncode(events), isNot(contains(forbidden)));
        }
      },
    );

    test(
      'failed private retry replays a previously guarded envelope and policy',
      () async {
        const messageId = 'private-retry-1';
        const attachmentId = '$messageId-att';
        const policy = PrivateMediaPolicy.protected();
        const originalEnvelope =
            '{"type":"chat_message","version":"2","id":"private-retry-1",'
            '"senderPeerId":"my-peer","encrypted":{"kem":"retry-kem",'
            '"ciphertext":"retry-ciphertext","nonce":"retry-nonce"}}';
        final failingP2p = FakeP2PService(sendMessageResult: false);
        final bridge = FakeBridge();
        final failed = ConversationMessage(
          id: messageId,
          contactPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          text: '',
          timestamp: '2026-07-11T09:00:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-07-11T09:00:00.000Z',
          wireEnvelope: originalEnvelope,
          privateMediaPolicy: policy,
          privateMediaState: PrivateMediaLifecycleState.available,
        );
        final privateMessageRepo = _PrivateCustodyMessageRepository(failed);
        final privateMediaRepo = _PrivateMutationMediaRepository()
          ..seed(const <MediaAttachment>[
            MediaAttachment(
              id: attachmentId,
              messageId: messageId,
              mime: 'image/jpeg',
              size: 1024,
              mediaType: 'image',
              downloadStatus: 'done',
              createdAt: '2026-07-11T09:00:00.000Z',
              contentHash:
                  'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
              encryptionKeyBase64: 'private-retry-key',
              encryptionNonce: 'private-retry-nonce',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              ownerLane: MediaOwnerLane.direct,
            ),
          ]);
        failingP2p.storeInInboxResult = true;

        final retried = await retryFailedMessage(
          messageId: messageId,
          messageRepo: privateMessageRepo,
          identityRepo: _StaticIdentityRepository(
            IdentityModel(
              peerId: 'my-peer',
              publicKey: 'public-key',
              privateKey: 'private-key',
              mnemonic12:
                  'one two three four five six seven eight nine ten eleven twelve',
              username: 'Me',
              createdAt: '2026-07-11T09:00:00.000Z',
              updatedAt: '2026-07-11T09:00:00.000Z',
            ),
          ),
          contactRepo: InMemoryContactRepository(),
          p2pService: failingP2p,
          bridge: bridge,
          mediaAttachmentRepo: privateMediaRepo,
        );

        expect(retried, 1);
        expect(failingP2p.lastInboxMessage, originalEnvelope);
        expect(
          bridge.commandLog
              .where((command) => command == 'message.encrypt')
              .length,
          0,
        );
        final retriedParent = privateMessageRepo.current;
        expect(retriedParent.status, 'inboxed');
        expect(retriedParent.wireEnvelope, originalEnvelope);
        expect(retriedParent.privateMediaPolicy, policy);
        expect(
          retriedParent.privateMediaState,
          PrivateMediaLifecycleState.available,
        );
        expect(privateMessageRepo.settlementCalls, 1);
        expect(
          privateMessageRepo.lastSettlementOutcome,
          OutgoingDirectPrivateTransportSettlementOutcome.committed,
        );
        expect(privateMessageRepo.saved, isEmpty);
      },
    );

    test(
      'private hide after envelope handoff wins blocked transport settlement',
      () async {
        const messageId = 'private-settlement-hide-race';
        const attachmentId = '$messageId-att';
        const contactPeerId = 'private-settlement-contact';
        final attachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 1024,
          mediaType: 'image',
          localPath: MediaFilePathConvention.relativePathForAttachment(
            contactPeerId: contactPeerId,
            blobId: attachmentId,
            mime: 'image/jpeg',
          ),
          downloadStatus: 'done',
          createdAt: '2026-07-20T09:00:00.000Z',
          contentHash:
              'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
          encryptionKeyBase64: 'private-settlement-key',
          encryptionNonce: 'private-settlement-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.direct,
        );
        final privateMessageRepo = _PrivateCustodyMessageRepository(
          ConversationMessage(
            id: messageId,
            contactPeerId: contactPeerId,
            senderPeerId: 'my-peer',
            text: '',
            timestamp: '2026-07-20T09:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-07-20T09:00:00.000Z',
            privateMediaPolicy: const PrivateMediaPolicy.protected(),
            privateMediaState: PrivateMediaLifecycleState.available,
            privateMediaReceivedAtMs: 1000,
            privateMediaClockHighWaterMs: 1000,
          ),
        );
        final privateMediaRepo = _PrivateMutationMediaRepository()
          ..seed(<MediaAttachment>[attachment]);
        final blockedP2p = _BlockedPrivateSettlementP2PService();

        final send = chat_use_case.sendChatMessage(
          p2pService: blockedP2p,
          messageRepo: privateMessageRepo,
          targetPeerId: contactPeerId,
          text: '',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: messageId,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: testRecipientMlKemPublicKey,
          mediaAttachments: <MediaAttachment>[attachment],
          privateMediaPolicy: const PrivateMediaPolicy.protected(),
          mediaAttachmentRepo: privateMediaRepo,
        );

        await blockedP2p.transportStarted.future;
        expect(privateMessageRepo.current.wireEnvelope, isNotNull);
        privateMessageRepo.hideAndConsume();
        blockedP2p.releaseTransport.complete();
        final (result, returned) = await send;

        expect(result, SendChatMessageResult.success);
        expect(returned?.hiddenAt, isNotNull);
        expect(
          returned?.privateMediaState,
          PrivateMediaLifecycleState.consumed,
        );
        expect(privateMessageRepo.current.status, 'sending');
        expect(privateMessageRepo.current.wireEnvelope, isNotNull);
        expect(privateMessageRepo.saved, isEmpty);
        expect(privateMediaRepo.allSavedAttachments, isEmpty);
        expect(privateMessageRepo.settlementCalls, 1);
        expect(
          privateMessageRepo.lastSettlementOutcome,
          OutgoingDirectPrivateTransportSettlementOutcome.preservedUserIntent,
        );
      },
    );

    test(
      'private media with text rejects before encryption persistence or transport',
      () async {
        const attachment = MediaAttachment(
          id: 'private-invalid-shape',
          messageId: '',
          mime: 'image/jpeg',
          size: 1024,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-07-11T09:00:00.000Z',
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          encryptionKeyBase64: 'private-key',
          encryptionNonce: 'private-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        final policy = PrivateMediaPolicy.fromJson(const {
          'version': 1,
          'mode': 'protected',
        });
        final bridge = FakeBridge();

        final (result, message) = await chat_use_case.sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'must never become a private caption',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: bridge,
          recipientMlKemPublicKey: testRecipientMlKemPublicKey,
          mediaAttachments: const [attachment],
          privateMediaPolicy: policy,
        );

        expect(result, SendChatMessageResult.invalidPrivateMedia);
        expect(message, isNull);
        expect(bridge.sendCallCount, 0);
        expect(messageRepo.saved, isEmpty);
        expect(messageRepo.wireEnvelopeUpdates, isEmpty);
        expect(p2pService.sendCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    // --- 112 Phase 2.2: outbound fail-closed media gate (G5) ---
    test(
      'send fails closed when an attachment lacks encryption metadata',
      () async {
        const plaintextAttachment = MediaAttachment(
          id: 'att-plain-1',
          messageId: '',
          mime: 'image/jpeg',
          size: 1024,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-06-12T11:00:00.000Z',
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'photo for you',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: const [plaintextAttachment],
        );

        expect(result, SendChatMessageResult.mediaEncryptionRequired);
        expect(message, isNull);
        // Fails BEFORE any envelope is built/persisted or transport touched.
        expect(messageRepo.saved, isEmpty);
        expect(messageRepo.wireEnvelopeUpdates, isEmpty);
        expect(p2pService.lastSentMessage, isNull);
      },
    );

    test(
      'send rejects a fully encrypted group-owned attachment before every side effect',
      () async {
        const groupOwnedAttachment = MediaAttachment(
          id: 'att-group-owned-direct-boundary',
          messageId: '',
          mime: 'video/mp4',
          size: 4096,
          mediaType: 'video',
          downloadStatus: 'done',
          createdAt: '2026-07-14T12:00:00.000Z',
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          encryptionKeyBase64: 'group-owned-key',
          encryptionNonce: 'group-owned-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.group,
        );
        final bridge = FakeBridge();
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();

        final (result, message) = await chat_use_case.sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: '',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: bridge,
          recipientMlKemPublicKey: testRecipientMlKemPublicKey,
          mediaAttachments: const [groupOwnedAttachment],
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendChatMessageResult.mediaEncryptionRequired);
        expect(message, isNull);
        expect(bridge.sendCallCount, 0, reason: 'must reject before encrypt');
        expect(p2pService.sendCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(messageRepo.saved, isEmpty);
        expect(messageRepo.wireEnvelopeUpdates, isEmpty);
        expect(mediaAttachmentRepo.allSavedAttachments, isEmpty);
      },
    );

    test('send proceeds for attachment with full encryption metadata', () async {
      const encryptedAttachment = MediaAttachment(
        id: 'att-enc-1',
        messageId: '',
        mime: 'image/jpeg',
        size: 1024,
        mediaType: 'image',
        downloadStatus: 'done',
        createdAt: '2026-06-12T11:00:00.000Z',
        contentHash:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        encryptionKeyBase64: 'key-1',
        encryptionNonce: 'nonce-1',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'photo for you',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        mediaAttachments: const [encryptedAttachment],
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      final payload = decodeWirePayload(p2pService.lastSentMessage!);
      final media = payload['media'] as List<dynamic>;
      final wireAttachment = media.single as Map<String, dynamic>;
      expect(wireAttachment['encryptionKeyBase64'], 'key-1');
      expect(wireAttachment['encryptionNonce'], 'nonce-1');
      expect(
        wireAttachment['encryptionScheme'],
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
    });

    test(
      '1:1 media first outgoing change carries renderable attachments in every terminal funnel',
      () async {
        const messageId = 'msg-first-media-change';
        const localPath = '/tmp/renderable-first-frame.jpg';
        const attachment = MediaAttachment(
          id: 'att-first-media-change',
          messageId: '',
          mime: 'image/jpeg',
          size: 1024,
          mediaType: 'image',
          localPath: localPath,
          downloadStatus: 'done',
          createdAt: '2026-07-10T12:00:00.000Z',
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          encryptionKeyBase64: 'key-first-media-change',
          encryptionNonce: 'nonce-first-media-change',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        final cases =
            <
              ({
                String name,
                FakeP2PService service,
                StoreInInboxDetailedFn? detailedStore,
                String expectedStatus,
              })
            >[
              (
                name: 'live success',
                service: FakeP2PService(sendMessageAcked: true),
                detailedStore: null,
                expectedStatus: 'delivered',
              ),
              (
                name: 'inbox accepted',
                service: FakeP2PService(
                  sendMessageResult: false,
                  useNullDiscover: true,
                  storeInInboxResult: true,
                ),
                detailedStore: null,
                expectedStatus: 'inboxed',
              ),
              (
                name: 'inbox full retryable',
                service: FakeP2PService(
                  sendMessageResult: false,
                  useNullDiscover: true,
                  storeInInboxResult: false,
                ),
                detailedStore: (peerId, message, {timeoutMs}) async =>
                    const InboxStoreOutcome(
                      status: InboxStoreStatus.rejectedFull,
                    ),
                expectedStatus: 'sent',
              ),
              (
                name: 'terminal failure',
                service: FakeP2PService(
                  sendMessageResult: false,
                  useNullDiscover: true,
                  storeInInboxResult: false,
                ),
                detailedStore: (peerId, message, {timeoutMs}) async =>
                    const InboxStoreOutcome(status: InboxStoreStatus.failed),
                expectedStatus: 'failed',
              ),
            ];

        for (final testCase in cases) {
          final repository = FakeMessageRepository();
          final (result, returnedMessage) = await chat_use_case.sendChatMessage(
            p2pService: testCase.service,
            messageRepo: repository,
            targetPeerId: 'target-peer',
            text: 'photo',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: messageId,
            preassignedMessageIdIsFresh: true,
            bridge: PassthroughCryptoBridge(),
            recipientMlKemPublicKey: testRecipientMlKemPublicKey,
            mediaAttachments: const [attachment],
            mediaAttachmentRepo: FakeMediaAttachmentRepository(),
            storeInInboxDetailed: testCase.detailedStore,
          );

          expect(
            repository.saved,
            isNotEmpty,
            reason: '${testCase.name} must publish an outgoing change',
          );
          final firstChange = repository.saved.first;
          expect(
            firstChange.status,
            testCase.expectedStatus,
            reason: testCase.name,
          );
          expect(
            firstChange.media,
            hasLength(1),
            reason:
                '${testCase.name} must publish media on its first repository change',
          );
          expect(firstChange.media.single.id, attachment.id);
          expect(firstChange.media.single.messageId, messageId);
          expect(firstChange.media.single.localPath, localPath);
          expect(returnedMessage?.media, hasLength(1));
          expect(
            result == SendChatMessageResult.success ||
                result == SendChatMessageResult.peerNotFound,
            isTrue,
            reason: testCase.name,
          );
        }
      },
    );

    test(
      'sanitizes outgoing comment text while preserving safe markers',
      () async {
        const rawText = 'مرحبا\u202E Hello\u200E 123';
        const sanitizedText = 'مرحبا Hello\u200E 123';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: rawText,
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.text, sanitizedText);
        expect(messageRepo.saved, hasLength(1));
        expect(messageRepo.saved.single.text, sanitizedText);

        final payload = decodeWirePayload(p2pService.lastSentMessage!);
        expect(payload['text'], sanitizedText);
        expect(payload['text'], isNot(contains('\u202E')));
      },
    );

    test(
      'rejects text that becomes empty after sanitization unless attachments exist',
      () async {
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: '\u202E   \u202C',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.invalidMessage);
        expect(message, isNull);
        expect(messageRepo.saved, isEmpty);

        final attachment = MediaAttachment(
          id: 'att-1',
          messageId: '',
          mime: 'image/png',
          size: 0,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-03-15T11:00:00.000Z',
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          encryptionKeyBase64: 'key-att-1',
          encryptionNonce: 'nonce-att-1',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        final (attachmentResult, attachmentMessage) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: '\u202E\u202C',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: [attachment],
        );

        expect(attachmentResult, SendChatMessageResult.success);
        expect(attachmentMessage, isNotNull);
        expect(attachmentMessage!.text, isEmpty);
        expect(attachmentMessage.media, hasLength(1));

        final payload = decodeWirePayload(p2pService.lastSentMessage!);
        expect(payload['text'], isEmpty);
        expect(payload['media'], isNotEmpty);
      },
    );

    test('returns invalidMessage for empty text', () async {
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: '',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.invalidMessage);
      expect(message, isNull);
      expect(messageRepo.saved, isEmpty);
    });

    test('returns invalidMessage for whitespace-only text', () async {
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: '   ',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.invalidMessage);
      expect(message, isNull);
    });

    test('returns nodeNotRunning when P2P is stopped', () async {
      p2pService = FakeP2PService(
        currentState: const NodeState(isStarted: false),
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.nodeNotRunning);
      expect(message, isNull);
    });

    test('returns encryptionRequired when bridge is missing', () async {
      final (result, message) = await chat_use_case.sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.encryptionRequired);
      expect(message, isNull);
      expect(p2pService.sendCallCount, 0);
      expect(p2pService.localSendCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
      expect(messageRepo.saved, isEmpty);
      expect(messageRepo.wireEnvelopeUpdates, isEmpty);
    });

    test(
      'returns encryptionRequired when recipient ML-KEM key is missing',
      () async {
        final (result, message) = await chat_use_case.sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: FakeBridge(),
        );

        expect(result, SendChatMessageResult.encryptionRequired);
        expect(message, isNull);
        expect(p2pService.sendCallCount, 0);
        expect(p2pService.localSendCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(messageRepo.saved, isEmpty);
        expect(messageRepo.wireEnvelopeUpdates, isEmpty);
      },
    );

    test('sends v2 encrypted envelope without plaintext payload', () async {
      final bridge = FakeBridge(
        initialResponses: {
          'message.encrypt': {
            'ok': true,
            'kem': 'opaque-kem',
            'ciphertext': 'opaque-chat-ciphertext',
            'nonce': 'opaque-nonce',
          },
        },
      );

      final (result, _) = await chat_use_case.sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Secret relay text',
        senderPeerId: 'my-peer',
        senderUsername: 'Private Me',
        bridge: bridge,
        recipientMlKemPublicKey: testRecipientMlKemPublicKey,
      );

      expect(result, SendChatMessageResult.success);
      final envelope =
          jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
      expect(envelope['type'], 'chat_message');
      expect(envelope['version'], '2');
      expect(envelope.containsKey('payload'), isFalse);
      expect(envelope['encrypted'], isA<Map<String, dynamic>>());
      expect(p2pService.lastSentMessage, isNot(contains('Secret relay text')));
      expect(p2pService.lastSentMessage, isNot(contains('Private Me')));
    });

    test('returns success and persists message on successful send', () async {
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.text, 'Hello!');
      expect(message.senderPeerId, 'my-peer');
      expect(message.contactPeerId, 'target-peer');
      expect(message.isIncoming, false);
      expect(message.status, 'delivered'); // ack reply present
      expect(message.id, isNotEmpty);

      expect(messageRepo.saved.length, 1);
      expect(messageRepo.saved.first.id, message.id);
    });

    test(
      'replaces a stale upload placeholder for an explicitly fresh media attempt',
      () async {
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        const messageId = 'msg-stable-cleanup-001';

        await mediaAttachmentRepo.saveAttachment(
          owner: MediaOwnerLane.direct,
          const MediaAttachment(
            id: 'placeholder-upload-pending',
            messageId: messageId,
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: '/tmp/pending.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        );

        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Photo',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: messageId,
          preassignedMessageIdIsFresh: true,
          timestamp: '2026-01-01T00:00:00.000Z',
          mediaAttachments: const [
            MediaAttachment(
              id: 'uploaded-final-id',
              messageId: '',
              mime: 'image/jpeg',
              size: 2048,
              mediaType: 'image',
              localPath: '/tmp/final.jpg',
              downloadStatus: 'done',
              createdAt: '2026-01-01T00:00:00.000Z',
              contentHash:
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              encryptionKeyBase64: 'key-final',
              encryptionNonce: 'nonce-final',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
          ],
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendChatMessageResult.success);
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          owner: MediaOwnerLane.direct,
          messageId,
        );
        expect(attachments.length, 1);
        expect(attachments.single.id, 'uploaded-final-id');
        expect(attachments.single.downloadStatus, 'done');
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(
            owner: MediaOwnerLane.direct,
          ),
          isEmpty,
        );
      },
    );

    // 228: the 1:1 outgoing path must persist media under the DIRECT lane —
    // every saveAttachment call carries MediaOwnerLane.direct, never group.
    test('outgoing media save passes direct owner', () async {
      final mediaAttachmentRepo = FakeMediaAttachmentRepository();

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Photo',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        mediaAttachments: const [
          MediaAttachment(
            id: 'direct-owner-attachment',
            messageId: '',
            mime: 'image/jpeg',
            size: 2048,
            mediaType: 'image',
            localPath: '/tmp/photo.jpg',
            downloadStatus: 'done',
            createdAt: '2026-01-01T00:00:00.000Z',
            contentHash:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            encryptionKeyBase64: 'key-direct-owner',
            encryptionNonce: 'nonce-direct-owner',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        ],
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(
        message!.media.single.ownerLane,
        MediaOwnerLane.direct,
        reason:
            'the returned live projection must match the direct-owned DB row',
      );
      expect(
        messageRepo.ordinaryStageCalls.single.kind,
        OutgoingOrdinaryAttemptKind.fresh,
      );
      expect(
        mediaAttachmentRepo.savedOwnerLanes,
        isEmpty,
        reason: 'the combined staging transaction replaces split row saves',
      );
      // Lane-scoped read-back: the group lane must never see this attachment.
      expect(
        await mediaAttachmentRepo.getAttachmentsForMessage(
          message.id,
          owner: MediaOwnerLane.group,
        ),
        isEmpty,
      );
      expect(
        (await mediaAttachmentRepo.getAttachmentsForMessage(
          message.id,
          owner: MediaOwnerLane.direct,
        )).single.id,
        'direct-owner-attachment',
      );
    });

    test(
      'normalizes null-owner outgoing image and video in every live projection',
      () async {
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: '',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: const [
            MediaAttachment(
              id: 'null-owner-image',
              messageId: '',
              mime: 'image/jpeg',
              size: 2048,
              mediaType: 'image',
              localPath: '/tmp/photo.jpg',
              downloadStatus: 'done',
              createdAt: '2026-07-14T12:00:00.000Z',
              contentHash:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              encryptionKeyBase64: 'image-key',
              encryptionNonce: 'image-nonce',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            MediaAttachment(
              id: 'null-owner-video',
              messageId: '',
              mime: 'video/mp4',
              size: 4096,
              mediaType: 'video',
              localPath: '/tmp/video.mp4',
              downloadStatus: 'done',
              createdAt: '2026-07-14T12:00:01.000Z',
              contentHash:
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              encryptionKeyBase64: 'video-key',
              encryptionNonce: 'video-nonce',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
          ],
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.media.map((attachment) => attachment.mediaType), [
          'image',
          'video',
        ]);
        expect(
          message.media.map((attachment) => attachment.ownerLane),
          everyElement(MediaOwnerLane.direct),
        );
        expect(
          messageRepo.saved
              .expand((saved) => saved.media)
              .map((attachment) => attachment.ownerLane),
          everyElement(MediaOwnerLane.direct),
        );
        expect(
          mediaAttachmentRepo.allSavedAttachments.map(
            (attachment) => attachment.ownerLane,
          ),
          everyElement(MediaOwnerLane.direct),
        );
      },
    );

    test(
      'sends GIF-only media with image/gif preserved in the wire envelope',
      () async {
        final attachment = MediaAttachment(
          id: 'gif-attachment',
          messageId: '',
          mime: 'image/gif',
          size: 4096,
          mediaType: 'image',
          localPath: '/tmp/funny.gif',
          downloadStatus: 'done',
          createdAt: '2026-03-15T11:00:00.000Z',
          contentHash:
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          encryptionKeyBase64: 'key-gif',
          encryptionNonce: 'nonce-gif',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: '',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: [attachment],
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.media, hasLength(1));
        expect(message.media.single.mime, 'image/gif');
        expect(message.media.single.isAnimated, isTrue);
        expect(message.privateMediaPolicy, const PrivateMediaPolicy.ordinary());
        expect(
          messageRepo.saved.single.privateMediaPolicy,
          const PrivateMediaPolicy.ordinary(),
        );

        final payload = decodeWirePayload(p2pService.lastSentMessage!);
        expect(payload.containsKey('privateMedia'), isFalse);
        final media = payload['media'] as List<dynamic>;
        expect(media, hasLength(1));
        expect((media.single as Map<String, dynamic>)['mime'], 'image/gif');
      },
    );

    test('sends correct JSON envelope via P2P', () async {
      await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(p2pService.lastSentPeerId, 'target-peer');
      expect(p2pService.lastSentMessage, isNotNull);
      final envelope =
          jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
      final payload = decodeWirePayload(p2pService.lastSentMessage!);
      expect(envelope['type'], 'chat_message');
      expect(envelope['version'], '2');
      expect(envelope.containsKey('payload'), isFalse);
      expect(payload['text'], 'Hello!');
    });

    test('uses provided messageId and timestamp when passed', () async {
      const fixedMessageId = 'msg-fixed-001';
      const fixedTimestamp = '2026-02-11T10:00:00.000Z';

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: fixedMessageId,
        timestamp: fixedTimestamp,
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.id, fixedMessageId);
      expect(message.timestamp, fixedTimestamp);
      expect(messageRepo.saved.first.id, fixedMessageId);
      expect(messageRepo.saved.first.timestamp, fixedTimestamp);
      final payload = decodeWirePayload(p2pService.lastSentMessage!);
      expect(payload['id'], fixedMessageId);
      expect(payload['timestamp'], fixedTimestamp);
    });

    test('editChatMessage preserves the original row contract', () async {
      const original = ConversationMessage(
        id: 'msg-edit-001',
        contactPeerId: 'target-peer',
        senderPeerId: 'my-peer',
        text: 'Original text',
        timestamp: '2026-02-11T10:00:00.000Z',
        status: 'delivered',
        isIncoming: false,
        createdAt: '2026-02-11T10:00:01.000Z',
        quotedMessageId: 'quoted-001',
      );

      final (result, message) = await editChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        originalMessage: original,
        updatedText: 'Edited text',
        senderUsername: 'Me',
      );

      final payload = decodeWirePayload(p2pService.lastSentMessage!);

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.id, original.id);
      expect(message.timestamp, original.timestamp);
      expect(message.createdAt, original.createdAt);
      expect(message.quotedMessageId, original.quotedMessageId);
      expect(message.editedAt, isNotNull);
      expect(messageRepo.saved.first.createdAt, original.createdAt);
      expect(messageRepo.saved.first.editedAt, isNotNull);
      expect(payload['id'], original.id);
      expect(payload['timestamp'], original.timestamp);
      expect(payload['quotedMessageId'], original.quotedMessageId);
      expect(payload['action'], MessagePayload.actionEdit);
      expect(payload['editedAt'], isNotNull);
    });

    test(
      'edit preserves forwarded marker and operation dedup token end to end',
      () async {
        const original = ConversationMessage(
          id: 'msg-forwarded-edit-001',
          contactPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          text: 'Original forwarded caption',
          timestamp: '2026-07-10T10:00:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-07-10T10:00:01.000Z',
          dedupKey: 'forward-operation-edit',
          isForwarded: true,
        );

        final (result, edited) = await editChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          originalMessage: original,
          updatedText: 'Edited forwarded caption',
          senderUsername: 'Me',
        );
        final inner = decodeWirePayload(p2pService.lastSentMessage!);

        expect(result, SendChatMessageResult.success);
        expect(edited, isNotNull);
        expect(edited!.id, original.id);
        expect(edited.dedupKey, 'forward-operation-edit');
        expect(edited.isForwarded, isTrue);
        expect(messageRepo.saved.last.dedupKey, 'forward-operation-edit');
        expect(messageRepo.saved.last.isForwarded, isTrue);
        expect(inner['action'], MessagePayload.actionEdit);
        expect(inner['dedupKey'], 'forward-operation-edit');
        expect(inner['isForwarded'], isTrue);

        final receiverMessages = FakeMessageRepository();
        receiverMessages.existingMessages[original.id] = original.copyWith(
          contactPeerId: 'my-peer',
          isIncoming: true,
          status: 'delivered',
        );
        final receiverContacts = InMemoryContactRepository();
        await receiverContacts.addContact(
          const ContactModel(
            peerId: 'my-peer',
            publicKey: 'sender-public-key',
            rendezvous: '/dns4/relay/tcp/443',
            username: 'Me',
            signature: 'sender-signature',
            scannedAt: '2026-07-10T09:00:00.000Z',
            mlKemPublicKey: 'sender-mlkem-public-key',
          ),
        );
        final (
          receiveResult,
          receiverEdited,
          _,
        ) = await handleIncomingChatMessage(
          message: ChatMessage(
            from: 'my-peer',
            to: 'target-peer',
            content: p2pService.lastSentMessage!,
            timestamp: edited.editedAt!,
            isIncoming: true,
          ),
          messageRepo: receiverMessages,
          contactRepo: receiverContacts,
          bridge: PassthroughCryptoBridge(),
          ownMlKemSecretKey: 'receiver-mlkem-secret-key',
        );
        expect(receiveResult, HandleChatMessageResult.chatMessage);
        expect(receiverEdited, isNotNull);
        expect(receiverEdited!.id, original.id);
        expect(receiverEdited.dedupKey, 'forward-operation-edit');
        expect(receiverEdited.isForwarded, isTrue);
        expect(receiverEdited.text, 'Edited forwarded caption');
        expect(receiverMessages.saved.last.dedupKey, 'forward-operation-edit');
        expect(receiverMessages.saved.last.isForwarded, isTrue);
      },
    );

    test('editChatMessage rejects failed outgoing messages', () async {
      const failed = ConversationMessage(
        id: 'msg-failed-edit-001',
        contactPeerId: 'target-peer',
        senderPeerId: 'my-peer',
        text: 'Recover me',
        timestamp: '2026-02-11T10:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-02-11T10:00:01.000Z',
      );

      final (result, message) = await editChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        originalMessage: failed,
        updatedText: 'Recover me again',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.invalidMessage);
      expect(message, isNull);
      expect(p2pService.sendCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
      expect(messageRepo.saved, isEmpty);
      expect(messageRepo.wireEnvelopeUpdates, isEmpty);
    });

    test('logs CHAT_OUT with delivered status and text preview', () async {
      final lines = await capturePrintedLines(() async {
        await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello from logger',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
      });

      expect(
        lines.any(
          (line) =>
              line.contains('[CHAT_OUT]') &&
              line.contains('status=delivered') &&
              line.contains('Hello from logger'),
        ),
        isTrue,
      );
    });

    test(
      'emits CHAT_MSG_SEND_TIMING with elapsed outcome and attachment flag',
      () async {
        final events = await captureFlowEvents(() async {
          await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Timing proof',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );
        });

        final timing = events.lastWhere(
          (event) => event['event'] == 'CHAT_MSG_SEND_TIMING',
        );
        expect(timing['details']['outcome'], 'success');
        expect(timing['details']['elapsedMs'], isA<int>());
        expect(timing['details']['hasAttachments'], isFalse);
      },
    );

    test('send flow events omit message-derived previews', () async {
      const directBody =
          'TOM001_DIRECT_BODY_FRAGMENT_ALPHA private direct message';
      final directP2P = FakeP2PService();
      final directRepo = FakeMessageRepository();
      final directEvents = await captureFlowEvents(() async {
        final (result, message) = await sendChatMessage(
          p2pService: directP2P,
          messageRepo: directRepo,
          targetPeerId: 'target-peer',
          text: directBody,
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'direct');
      });
      expectSendFlowEventsOmitMessagePreview(
        directEvents,
        terminalEvent: 'CHAT_MSG_SEND_SUCCESS',
        forbiddenFragments: const [directBody, 'TOM001_DIRECT_BODY_FRAGMENT'],
      );

      const inboxBody =
          'TOM001_INBOX_FALLBACK_BODY_FRAGMENT_BETA private inbox message';
      final inboxP2P = FakeP2PService(
        sendMessageResult: false,
        storeInInboxResult: true,
      );
      final inboxRepo = FakeMessageRepository();
      final inboxEvents = await captureFlowEvents(() async {
        final (result, message) = await sendChatMessage(
          p2pService: inboxP2P,
          messageRepo: inboxRepo,
          targetPeerId: 'target-peer',
          text: inboxBody,
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'inbox');
      });
      expectSendFlowEventsOmitMessagePreview(
        inboxEvents,
        terminalEvent: 'CHAT_MSG_SEND_SUCCESS',
        forbiddenFragments: const [
          inboxBody,
          'TOM001_INBOX_FALLBACK_BODY_FRAGMENT',
        ],
      );

      const failedBody =
          'TOM001_FAILED_BODY_FRAGMENT_GAMMA private failed message';
      final failedP2P = FakeP2PService(sendMessageResult: false);
      final failedRepo = FakeMessageRepository();
      final failedEvents = await captureFlowEvents(() async {
        final (result, message) = await sendChatMessage(
          p2pService: failedP2P,
          messageRepo: failedRepo,
          targetPeerId: 'target-peer',
          text: failedBody,
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(result, SendChatMessageResult.sendFailed);
        expect(message!.status, 'failed');
      });
      expectSendFlowEventsOmitMessagePreview(
        failedEvents,
        terminalEvent: 'CHAT_MSG_SEND_FAILED',
        forbiddenFragments: const [failedBody, 'TOM001_FAILED_BODY_FRAGMENT'],
      );
    });

    test(
      'returns sendFailed and persists with failed status when send returns false',
      () async {
        p2pService.sendMessageResult = false;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.sendFailed);
        expect(message, isNotNull);
        expect(message!.status, 'failed');
        expect(messageRepo.saved.length, 1);
        expect(messageRepo.saved.first.status, 'failed');
        // FDC-03: unknown-presence fires the concurrent inbox (attempt 1, fails
        // — storeInInboxResult false) then the serial fallback retries once
        // (attempt 2, also fails) → 2 calls. The message still persists 'failed'.
        expect(p2pService.storeInInboxCallCount, 2);
      },
    );

    test(
      // 115 P1 contract flip: inbox store success is CUSTODY ('inboxed'),
      // not delivery — receipts (115 P2) own the 'delivered' flip.
      'returns success and persists inboxed status when inbox store succeeds',
      () async {
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = true;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello queued!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'inboxed');
        expect(messageRepo.saved.length, 1);
        expect(messageRepo.saved.first.status, 'inboxed');
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.lastInboxPeerId, 'target-peer');
        expect(p2pService.lastInboxMessage, isNotNull);
        expect(p2pService.lastInboxMessage, contains('"type":"chat_message"'));
        expect(p2pService.recordSuccessfulSendProofCallCount, 1);
        expect(p2pService.lastReadinessProofSource, 'chat_send_inbox');
        expect(p2pService.lastReadinessTrigger, 'user_action');
        expect(p2pService.lastReadinessSendPath, 'inbox');
      },
    );

    test('returns sendFailed when P2P throws exception', () async {
      // Make discover succeed but sendMessageWithReply throw
      p2pService = FakeP2PService();
      p2pService.shouldThrow = true;
      // Override discoverPeer so it doesn't throw (shouldThrow only affects send)
      // Actually, shouldThrow in our fake affects discover on first call too.
      // Let's use a cleaner approach:
      final customP2P = _ThrowOnSendP2PService();

      final (result, message) = await sendChatMessage(
        p2pService: customP2P,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.sendFailed);
      expect(message, isNotNull);
      expect(message!.status, 'failed');
    });

    test('returns peerNotFound when discover returns null', () async {
      p2pService = FakeP2PService(useNullDiscover: true);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.peerNotFound);
      expect(message, isNotNull);
      expect(message!.status, 'failed');
      // With the race-based send, discover is called once per attempt
      expect(p2pService.discoverCallCount, 1);
      expect(messageRepo.saved.length, 1);
      expect(messageRepo.saved.first.status, 'failed');
    });

    test('returns dialFailed when dial returns false', () async {
      p2pService = FakeP2PService(dialPeerResult: false);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.dialFailed);
      expect(message, isNotNull);
      expect(message!.status, 'failed');
      // Race-based send: one discover + one dial attempt
      expect(p2pService.dialCallCount, 1);
      expect(messageRepo.saved.length, 1);
    });

    test(
      'flaky discover surfaces peerNotFound when direct discovery loses',
      () async {
        // With race-based send, a single failed discover causes the direct path
        // to fail. The inbox fallback (if available) would then be tried.
        final flakyP2P = _FlakyDiscoverP2PService();

        final (result, message) = await sendChatMessage(
          p2pService: flakyP2P,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        // Discover fails on the direct path, so the user-visible result should
        // preserve the more specific peerNotFound taxonomy.
        expect(result, SendChatMessageResult.peerNotFound);
        expect(message, isNotNull);
        expect(flakyP2P.discoverCallCount, 1);
      },
    );

    test('success with ack sets status to delivered', () async {
      p2pService = FakeP2PService(sendMessageReply: 'received: ok');

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'delivered');
      expect(p2pService.recordSuccessfulSendProofCallCount, 1);
      expect(p2pService.lastReadinessProofSource, 'chat_send_direct');
      expect(p2pService.lastReadinessTrigger, 'user_action');
      expect(p2pService.lastReadinessSendPath, 'direct');
    });

    test('success without ack keeps sent when inbox handoff fails', () async {
      p2pService = FakeP2PService(
        sendMessageAcked: false,
        sendMessageReply: null,
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'sent');
      expect(message.transport, 'direct');
      expect(message.wireEnvelope, isNotNull);
      // FDC-03: concurrent inbox (attempt 1, fails) + serial unacked handoff
      // (attempt 2, fails) → 2 calls; the message still persists 'sent'.
      expect(p2pService.storeInInboxCallCount, 2);
    });

    test(
      'success with empty reply keeps sent when inbox handoff fails',
      () async {
        p2pService = FakeP2PService(
          sendMessageAcked: false,
          sendMessageReply: '',
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'sent');
        expect(message.transport, 'direct');
        expect(message.wireEnvelope, isNotNull);
        // FDC-03: concurrent inbox (attempt 1, fails) + serial unacked handoff
        // (attempt 2, fails) → 2 calls; the message still persists 'sent'.
        expect(p2pService.storeInInboxCallCount, 2);
      },
    );

    test(
      'unacked direct send hands off to inbox immediately when available',
      () async {
        p2pService = FakeP2PService(
          sendMessageAcked: false,
          sendMessageReply: null,
          storeInInboxResult: true,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // 115 P1 contract flip: inbox handoff is custody → 'inboxed' with the
        // envelope retained for the custody sweep / receipt flip.
        expect(message!.status, 'inboxed');
        expect(message.transport, 'inbox');
        expect(message.wireEnvelope, isNotNull);
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test(
      'writes locally but keeps a retryable envelope without libp2p proof',
      () async {
        p2pService = DurableLanFakeP2PService(useNullDiscover: true)
          ..localPeers.add('target-peer');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello local!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message.transport, 'local');
        expect(message.wireEnvelope, isNotNull);
        // Local send was attempted (race includes local + direct)
        expect(p2pService.localSendCallCount, 1);
        expect(p2pService.probeRelayCallCount, 0);
        expect(p2pService.recordSuccessfulSendProofCallCount, 0);
      },
    );

    test('falls through to relay when local send fails', () async {
      p2pService.localPeers.add('target-peer');
      p2pService.localSendResult = false;

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello fallback!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'delivered');
      // Local was attempted but failed
      expect(p2pService.localSendCallCount, 1);
      // Relay path was used
      expect(p2pService.discoverCallCount, 1);
      expect(p2pService.sendCallCount, 1);
    });

    test('passes interactive local budget to the WiFi transport', () async {
      p2pService.localPeers.add('target-peer');
      p2pService.localSendResult = false;

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello timeout budget!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.transport, 'direct');
      expect(
        p2pService.lastLocalSendTimeoutMs,
        interactiveLocalBudget.inMilliseconds,
      );
    });

    test('skips local send when peer is not on local WiFi', () async {
      // localPeers is empty by default
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello relay!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // No local send attempted
      expect(p2pService.localSendCallCount, 0);
      // Relay path used directly
      expect(p2pService.discoverCallCount, 1);
      expect(p2pService.sendCallCount, 1);
    });

    // U-P2-ttl / doc U2: a stale discovered peer is treated as NOT local by
    // the read-time freshness filter (getLocalPeer/isLocalPeer return false).
    // The send path must therefore skip the local leg entirely and let the
    // direct leg carry the message WITHOUT burning the 1500ms local budget.
    test(
      'stale peer skips local send and does not burn the local budget',
      () async {
        // Mirror production: a stale entry makes isLocalPeer() return false, so
        // localPeers stays empty here (the freshness filter already dropped it).
        p2pService = FakeP2PService();
        expect(p2pService.isLocalPeer('target-peer'), isFalse);

        final sw = Stopwatch()..start();
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello stale!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        sw.stop();

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // No local send attempted for a stale (non-fresh) peer.
        expect(p2pService.localSendCallCount, 0);
        // Direct leg carried it — never reports the outbound 'local' label.
        expect(message!.transport, isNot('local'));
        // Far under interactiveLocalBudget (1500ms): no stale host:port burn.
        expect(
          sw.elapsedMilliseconds,
          lessThan(interactiveLocalBudget.inMilliseconds),
        );
      },
    );
  });

  // ─── NET-REL-01 (LAN/WiFi reliability) — labeled coverage ──────────
  // U1 happy / U2 TTL-degraded / U3 discover-on-send / U-N1 negative control.
  // These pin the exact transport label so a future regression that hard-codes
  // 'local' (U1) or drops the discover-on-send leg (U3) is caught, while U-N1
  // proves U1 is not just always reporting 'local'.
  group('NET-REL-01 LAN transport', () {
    // U1 — happy path: peer already in localPeers → the message uses the LAN
    // path (transport=='local'), the local leg fires exactly once, and the
    // relay probe is never reached because local wins the race.
    test(
      'U1 happy: discovered local peer delivers via local transport',
      () async {
        // useNullDiscover makes the parallel direct leg miss, so only the local
        // leg can win — proving 'local' is the path actually taken.
        p2pService = DurableLanFakeP2PService(useNullDiscover: true)
          ..localPeers.add('target-peer');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello on the LAN',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'local');
        expect(p2pService.localSendCallCount, 1);
        expect(p2pService.probeRelayCallCount, 0);
        // Already-local: no discover-on-send resolve needed.
        expect(p2pService.discoverLocalPeerCallCount, 0);
      },
    );

    // U2 — TTL / degraded: a stale entry is dropped by the read-time freshness
    // filter, so isLocalPeer is false and discoverLocalPeer also fails (the peer
    // is genuinely gone). The local leg must NOT deliver and must NOT burn the
    // full 1500ms budget before the direct leg carries it. (Complements the
    // 'stale peer skips local send' test above, which covers the already-local
    // false path; here we assert the discover-on-send leg also fails fast.)
    test(
      'U2 TTL-degraded: stale/absent peer fails local fast, direct carries',
      () async {
        // Not in localPeers and discover-on-send resolves false (peer departed).
        p2pService = FakeP2PService()..discoverLocalPeerResult = false;
        expect(p2pService.isLocalPeer('target-peer'), isFalse);

        final sw = Stopwatch()..start();
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello departed peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        sw.stop();

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // Discover-on-send was attempted but resolved false, so no LAN send.
        expect(p2pService.discoverLocalPeerCallCount, 1);
        expect(p2pService.localSendCallCount, 0);
        expect(message!.transport, isNot('local'));
        // The discover-on-send leg returns false promptly — it must not consume
        // the full local budget before the direct leg wins.
        expect(
          sw.elapsedMilliseconds,
          lessThan(interactiveLocalBudget.inMilliseconds),
        );
      },
    );

    // U3 — discover-on-send: peer is unknown at send time (not in localPeers)
    // but IS present on the LAN. The bounded resolve succeeds within budget, so
    // the local leg joins the race and delivers via 'local'.
    test(
      'U3 discover-on-send: unknown-but-LAN-present peer joins via local',
      () async {
        // Direct leg misses (useNullDiscover) so only the freshly-resolved local
        // leg can win. discoverLocalPeerResult=true models mDNS resolving at send
        // time; a small bounded delay proves it still lands inside the budget.
        p2pService = DurableLanFakeP2PService(useNullDiscover: true)
          ..discoverLocalPeerResult = true
          ..discoverLocalPeerDelay = const Duration(milliseconds: 50);
        // Precondition: peer is NOT already known as local.
        expect(p2pService.isLocalPeer('target-peer'), isFalse);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello just-foregrounded peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // Bounded resolve ran, then the local leg delivered within budget.
        expect(p2pService.discoverLocalPeerCallCount, 1);
        expect(p2pService.lastDiscoverLocalPeerTimeout, interactiveLocalBudget);
        expect(p2pService.localSendCallCount, 1);
        expect(message!.transport, 'local');
      },
    );

    // U-N1 — NEGATIVE CONTROL: peer NOT on the LAN and the LAN send is forced to
    // fail. discover-on-send resolves false, the local leg is never reached, and
    // the message is delivered by a non-local transport. This is what proves U1
    // isn't hard-coding 'local'.
    test(
      'U-N1 negative control: non-LAN peer never uses local transport',
      () async {
        p2pService = FakeP2PService()
          ..discoverLocalPeerResult =
              false // not discoverable on the LAN
          ..localSendResult = false; // and the LAN send would fail anyway
        expect(p2pService.isLocalPeer('target-peer'), isFalse);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello over relay/direct',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // The won transport is anything but local (direct/relay/inbox).
        expect(message!.transport, isNot('local'));
        expect(const ['direct', 'relay', 'inbox'], contains(message.transport));
        // sendLocalMessage was never reached: the LAN leg lost the race outright.
        expect(p2pService.localSendCallCount, 0);
        // The direct leg carried the message.
        expect(p2pService.sendCallCount, 1);
      },
    );
  });

  group('Doc 114 S3 durable LAN ack policy', () {
    test(
      'committed LAN ack remains written-only and keeps retryable custody',
      () async {
        p2pService = DurableLanFakeP2PService(useNullDiscover: true)
          ..localPeers.add('target-peer');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Committed LAN custody',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message.transport, 'local');
        expect(message.wireEnvelope, isNotNull);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.recordSuccessfulTransportCallCount, 0);
        expect(p2pService.lastRecordedTransport, isNull);
      },
    );

    test(
      'legacy LAN ack hands off to inbox custody without sticky local',
      () async {
        p2pService = DurableLanFakeP2PService(
          localSendAck: LanSendAck.legacyAck,
          useNullDiscover: true,
          storeInInboxResult: true,
        )..localPeers.add('target-peer');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Legacy LAN ack needs custody',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'inboxed');
        expect(message.transport, 'inbox');
        expect(message.wireEnvelope, isNotNull);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.recordSuccessfulTransportCallCount, 0);
        expect(p2pService.lastRecordedTransport, isNull);
      },
    );

    test(
      'legacy LAN ack keeps retryable sent envelope when inbox handoff fails',
      () async {
        p2pService = DurableLanFakeP2PService(
          localSendAck: LanSendAck.legacyAck,
          useNullDiscover: true,
          storeInInboxResult: false,
        )..localPeers.add('target-peer');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Legacy LAN ack retryable',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message.transport, 'local');
        expect(message.wireEnvelope, isNotNull);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.recordSuccessfulTransportCallCount, 0);
      },
    );

    test(
      'bool-only local sender is non-durable and uses inbox backstop',
      () async {
        p2pService = FakeP2PService(
          useNullDiscover: true,
          storeInInboxResult: true,
        )..localPeers.add('target-peer');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Bool LAN ack is legacy',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'inboxed');
        expect(message.transport, 'inbox');
        expect(message.wireEnvelope, isNotNull);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.recordSuccessfulTransportCallCount, 0);
      },
    );

    test(
      'learned local does not short-circuit authenticated direct proof',
      () async {
        p2pService =
            DurableLanFakeP2PService(
                localSendAck: LanSendAck.legacyAck,
                storeInInboxResult: true,
              )
              ..localPeers.add('target-peer')
              ..lastKnownGoodTransportResult = 'local';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Sticky local legacy ack',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(message.transport, 'direct');
        expect(message.wireEnvelope, isNull);
        expect(p2pService.localSendCallCount, 1);
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.dialCallCount, 1);
        expect(p2pService.recordSuccessfulTransportCallCount, 1);
      },
    );
  });

  group('R2 authenticated committed live settlement', () {
    test(
      'R2 claimed committed LAN ACK cannot settle suppress authenticated work or train sticky',
      () async {
        final directProof = Completer<SendMessageResult>();
        final provingService = DurableLanFakeP2PService(
          localSendAck: LanSendAck.committed,
        )..localPeers.add('target-peer');
        provingService.queuedSendMessageResults.add(directProof.future);
        final provingRepo = FakeMessageRepository();
        var settled = false;
        final provingSend =
            sendChatMessage(
              p2pService: provingService,
              messageRepo: provingRepo,
              targetPeerId: 'target-peer',
              text: 'LAN write waits for authenticated proof',
              senderPeerId: 'my-peer',
              senderUsername: 'Me',
            ).then((value) {
              settled = true;
              return value;
            });

        for (var i = 0; i < 20 && provingService.sendCallCount == 0; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(provingService.localSendCallCount, 1);
        expect(provingService.sendCallCount, 1);
        expect(settled, isFalse);
        expect(provingService.recordSuccessfulTransportCallCount, 0);

        directProof.complete(
          const SendMessageResult(sent: true, acked: true, transport: 'direct'),
        );
        final (provingResult, provingMessage) = await provingSend;
        expect(provingResult, SendChatMessageResult.success);
        expect(provingMessage!.status, 'delivered');
        expect(provingMessage.transport, 'direct');
        expect(provingService.lastRecordedTransport, 'direct');

        final custodyService = DurableLanFakeP2PService(
          localSendAck: LanSendAck.committed,
          sendMessageAcked: null,
          sendMessageReply: 'legacy reply is not proof',
          storeInInboxResult: true,
        )..localPeers.add('target-peer');
        final (custodyResult, custodyMessage) = await sendChatMessage(
          p2pService: custodyService,
          messageRepo: FakeMessageRepository(),
          targetPeerId: 'target-peer',
          text: 'LAN write needs custody',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(custodyResult, SendChatMessageResult.success);
        expect(custodyMessage!.status, 'inboxed');
        expect(custodyMessage.transport, 'inbox');
        expect(custodyMessage.wireEnvelope, isNotNull);
        expect(custodyService.sendCallCount, 1);
        expect(custodyService.storeInInboxCallCount, 1);
        expect(custodyService.recordSuccessfulTransportCallCount, 0);
      },
    );

    test(
      'R2 first authenticated committed ACK settles before virtual transport grace',
      () {
        fakeAsync((async) {
          final losingLocal = Completer<LanSendAck>();
          final service = DurableLanFakeP2PService()
            ..localPeers.add('target-peer')
            ..controlledLocalSendAck = losingLocal.future;
          (SendChatMessageResult, ConversationMessage?)? outcome;

          sendChatMessage(
            p2pService: service,
            messageRepo: FakeMessageRepository(),
            targetPeerId: 'target-peer',
            text: 'direct proof has zero settlement grace',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          ).then((value) => outcome = value);
          async.flushMicrotasks();

          expect(async.elapsed, Duration.zero);
          expect(outcome, isNotNull);
          expect(outcome!.$2!.status, 'delivered');
          expect(outcome!.$2!.transport, 'direct');
          expect(losingLocal.isCompleted, isFalse);
        });

        fakeAsync((async) {
          final losingLocal = Completer<LanSendAck>();
          final losingDirect = Completer<SendMessageResult>();
          final service =
              DurableLanFakeP2PService(
                  currentState: const NodeState(
                    isStarted: true,
                    connections: [
                      p2p.ConnectionState(
                        peerId: 'target-peer',
                        multiaddrs: [
                          '/ip4/10.0.0.8/tcp/4001/p2p/relay/p2p-circuit',
                        ],
                        direction: 'outbound',
                        status: 'connected',
                      ),
                    ],
                  ),
                )
                ..localPeers.add('target-peer')
                ..controlledLocalSendAck = losingLocal.future
                ..queuedSendMessageResults.addAll([
                  losingDirect.future,
                  Future<SendMessageResult>.value(
                    const SendMessageResult(
                      sent: true,
                      acked: true,
                      transport: 'relay',
                    ),
                  ),
                ]);
          (SendChatMessageResult, ConversationMessage?)? outcome;

          sendChatMessage(
            p2pService: service,
            messageRepo: FakeMessageRepository(),
            targetPeerId: 'target-peer',
            text: 'relay proof has scheduling stagger only',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          ).then((value) => outcome = value);
          async.flushMicrotasks();
          expect(outcome, isNull);
          expect(service.relayLiveSendCount, 0);

          async.elapse(kRelayLegStagger);
          async.flushMicrotasks();
          expect(async.elapsed, kRelayLegStagger);
          expect(service.relayLiveSendCount, 1);
          expect(outcome, isNotNull);
          expect(outcome!.$2!.status, 'delivered');
          expect(outcome!.$2!.transport, 'relay');
          expect(losingLocal.isCompleted, isFalse);
          expect(losingDirect.isCompleted, isFalse);
        });

        fakeAsync((async) {
          final service = FakeP2PService()
            ..lastKnownGoodTransportResult = 'local'
            ..localPeers.add('target-peer')
            ..localSendResult = false;
          (SendChatMessageResult, ConversationMessage?)? outcome;

          sendChatMessage(
            p2pService: service,
            messageRepo: FakeMessageRepository(),
            targetPeerId: 'target-peer',
            text: 'failed learned local cannot delay direct proof',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          ).then((value) => outcome = value);
          async.flushMicrotasks();

          expect(async.elapsed, Duration.zero);
          expect(outcome, isNotNull);
          expect(outcome!.$2!.status, 'delivered');
          expect(outcome!.$2!.transport, 'direct');
        });
      },
    );

    test(
      'R2 uncommitted reuse and learned routes fall through to authenticated race',
      () async {
        const directConnection = p2p.ConnectionState(
          peerId: 'target-peer',
          multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
          direction: 'outbound',
          status: 'connected',
        );
        final reuseService = FakeP2PService(
          currentState: const NodeState(
            isStarted: true,
            connections: [directConnection],
          ),
        )..discoverLocalPeerResult = false;
        reuseService.queuedSendMessageResults.addAll([
          Future<SendMessageResult>.value(
            const SendMessageResult(
              sent: true,
              acked: null,
              reply: 'forged compatibility reply',
              transport: 'direct',
            ),
          ),
          Future<SendMessageResult>.value(
            const SendMessageResult(
              sent: true,
              acked: true,
              transport: 'direct',
            ),
          ),
        ]);
        final (_, reuseMessage) = await sendChatMessage(
          p2pService: reuseService,
          messageRepo: FakeMessageRepository(),
          targetPeerId: 'target-peer',
          text: 'uncommitted reuse falls through',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(reuseMessage!.status, 'delivered');
        expect(reuseService.sendCallCount, 2);
        expect(reuseService.discoverCallCount, 1);

        final learnedService = FakeP2PService()
          ..lastKnownGoodTransportResult = 'direct'
          ..discoverLocalPeerResult = false;
        learnedService.queuedSendMessageResults.addAll([
          Future<SendMessageResult>.value(
            const SendMessageResult(
              sent: true,
              acked: null,
              reply: 'legacy reply is not proof',
              transport: 'direct',
            ),
          ),
          Future<SendMessageResult>.value(
            const SendMessageResult(
              sent: true,
              acked: true,
              transport: 'direct',
            ),
          ),
        ]);
        final (_, learnedMessage) = await sendChatMessage(
          p2pService: learnedService,
          messageRepo: FakeMessageRepository(),
          targetPeerId: 'target-peer',
          text: 'uncommitted learned route falls through',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(learnedMessage!.status, 'delivered');
        expect(learnedService.sendCallCount, 2);
        expect(learnedService.discoverCallCount, 1);

        final provingReuse = FakeP2PService(
          currentState: const NodeState(
            isStarted: true,
            connections: [directConnection],
          ),
          sendMessageAcked: true,
        );
        final (_, provingReuseMessage) = await sendChatMessage(
          p2pService: provingReuse,
          messageRepo: FakeMessageRepository(),
          targetPeerId: 'target-peer',
          text: 'positive reuse remains fast',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(provingReuseMessage!.status, 'delivered');
        expect(provingReuse.sendCallCount, 1);
        expect(provingReuse.discoverCallCount, 0);

        final reuseWithoutCustody = FakeP2PService(
          currentState: const NodeState(
            isStarted: true,
            connections: [directConnection],
          ),
          storeInInboxResult: false,
        )..discoverLocalPeerResult = false;
        reuseWithoutCustody.queuedSendMessageResults.addAll([
          Future<SendMessageResult>.value(
            const SendMessageResult(
              sent: true,
              acked: null,
              reply: 'reuse wrote but did not commit',
              transport: 'direct',
            ),
          ),
          Future<SendMessageResult>.value(const SendMessageResult(sent: false)),
        ]);
        final (reusePendingResult, reusePendingMessage) = await sendChatMessage(
          p2pService: reuseWithoutCustody,
          messageRepo: FakeMessageRepository(),
          targetPeerId: 'target-peer',
          text: 'reuse write remains retryable without later proof or custody',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(reusePendingResult, SendChatMessageResult.success);
        expect(reusePendingMessage!.status, 'sent');
        expect(reusePendingMessage.transport, 'direct');
        expect(reusePendingMessage.wireEnvelope, isNotNull);
        expect(reuseWithoutCustody.sendCallCount, 2);

        final learnedWithoutCustody = FakeP2PService(storeInInboxResult: false)
          ..lastKnownGoodTransportResult = 'direct'
          ..discoverLocalPeerResult = false;
        learnedWithoutCustody.queuedSendMessageResults.addAll([
          Future<SendMessageResult>.value(
            const SendMessageResult(
              sent: true,
              acked: null,
              reply: 'learned route wrote but did not commit',
              transport: 'direct',
            ),
          ),
          Future<SendMessageResult>.value(const SendMessageResult(sent: false)),
        ]);
        final (
          learnedPendingResult,
          learnedPendingMessage,
        ) = await sendChatMessage(
          p2pService: learnedWithoutCustody,
          messageRepo: FakeMessageRepository(),
          targetPeerId: 'target-peer',
          text:
              'learned write remains retryable without later proof or custody',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(learnedPendingResult, SendChatMessageResult.success);
        expect(learnedPendingMessage!.status, 'sent');
        expect(learnedPendingMessage.transport, 'direct');
        expect(learnedPendingMessage.wireEnvelope, isNotNull);
        expect(learnedWithoutCustody.sendCallCount, 2);
      },
    );

    test(
      'R2 LAN-visible authenticated reuse wins and learned local cannot short-circuit proof',
      () async {
        final reuseService = FakeP2PService(
          currentState: const NodeState(
            isStarted: true,
            connections: [
              p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/192.168.1.20/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
          sendMessageAcked: true,
          sendMessageTransport: 'local',
        )..localPeers.add('target-peer');
        final (_, reuseMessage) = await sendChatMessage(
          p2pService: reuseService,
          messageRepo: FakeMessageRepository(),
          targetPeerId: 'target-peer',
          text: 'authenticated private-address reuse',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(reuseMessage!.status, 'delivered');
        expect(reuseMessage.transport, 'local');
        expect(reuseService.sendCallCount, 1);
        expect(reuseService.localSendCallCount, 0);
        expect(reuseService.discoverCallCount, 0);

        final learnedLocalService = DurableLanFakeP2PService()
          ..localPeers.add('target-peer')
          ..lastKnownGoodTransportResult = 'local'
          ..localSendDelay = const Duration(milliseconds: 40);
        final (_, learnedLocalMessage) = await sendChatMessage(
          p2pService: learnedLocalService,
          messageRepo: FakeMessageRepository(),
          targetPeerId: 'target-peer',
          text: 'learned local still races proof',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(learnedLocalMessage!.status, 'delivered');
        expect(learnedLocalMessage.transport, 'direct');
        expect(learnedLocalService.sendCallCount, 1);
        expect(learnedLocalService.discoverCallCount, 1);
      },
    );
  });

  // FDC-03: the SERIAL relay-probe→inbox tail was REMOVED. These tests, formerly
  // "Phase 3 — relay probe recovery," now pin the post-probe-tail reality: a
  // race-fail send to an unknown-presence peer takes durable INBOX custody
  // (probeRelayCallCount == 0 throughout — the probe never runs); LIVE relay
  // recovery is FDC-02's IN-RACE staggered relay-live leg, exercised by the
  // seeded-circuit case below (and the FDC-02 group). TC-03/FDC-03-03b is the
  // canonical probe-tail mutation because it alone reaches the former probe
  // seam; custody-success fixtures return before that seam.
  group('Phase 3 — race-fail recovery (FDC-03: probe tail removed)', () {
    test('circuit-only peer recovers LIVE via the FDC-02 in-race relay leg '
        '(state-inferred relay label)', () async {
      // A live `/p2p-circuit` connection exists → FDC-02's staggered relay-live
      // leg carries the send and `_resolveGoSendTransport` infers 'relay'. This
      // is the live-relay recovery that REPLACED the serial probe tail.
      p2pService = FakeP2PService(
        currentState: NodeState(
          isStarted: true,
          connections: [
            const p2p.ConnectionState(
              peerId: 'target-peer',
              multiaddrs: [
                '/ip4/10.0.0.8/tcp/4001/p2p/12D3KooWRelay/p2p-circuit',
              ],
              direction: 'outbound',
              status: 'connected',
            ),
          ],
        ),
        useNullDiscover: true,
        sendMessageTransport: null,
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello via the in-race relay leg',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'delivered');
      expect(message.transport, 'relay');
      // The probe tail is gone — recovery was the in-race relay leg.
      expect(p2pService.probeRelayCallCount, 0);
    });

    test('discover miss for an unknown-presence peer → durable inbox custody '
        '(no probe)', () async {
      // FDC-03: formerly "discover miss then relay probe connected sends live."
      // With the probe tail removed and no live circuit, the concurrent durable
      // inbox copy holds custody.
      p2pService = FakeP2PService(
        useNullDiscover: true,
        storeInInboxResult: true,
      );
      p2pService.probeRelayResult = RelayProbeResult.connected;

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello → inbox custody',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'inboxed');
      expect(message.transport, 'inbox');
      expect(p2pService.discoverCallCount, 1);
      expect(p2pService.probeRelayCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test('dial failure for an unknown-presence peer → durable inbox custody '
        '(no probe)', () async {
      // FDC-03: formerly "dial failed then relay probe connected sends live."
      p2pService = FakeP2PService(
        dialPeerResult: false,
        storeInInboxResult: true,
      );
      p2pService.probeRelayResult = RelayProbeResult.connected;

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello after dial failure → inbox',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'inboxed');
      expect(message.transport, 'inbox');
      expect(p2pService.probeRelayCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test(
      'offline peer (no reservation) → durable inbox custody, no probe',
      () async {
        p2pService = FakeP2PService(
          useNullDiscover: true,
          storeInInboxResult: true,
        );
        p2pService.probeRelayResult = RelayProbeResult.noReservation;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello queued offline',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'inboxed'); // doc 115: custody, not delivery
        expect(message.transport, 'inbox');
        // FDC-03: the probe no longer runs; custody is the concurrent inbox.
        expect(p2pService.probeRelayCallCount, 0);
        expect(p2pService.sendCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test(
      'unacked live attempt for an unknown-presence peer hands off to inbox',
      () async {
        // FDC-03: formerly "probe-connected send with lost ACK." With the probe
        // gone, the unacked custody is the concurrent inbox copy.
        p2pService = FakeP2PService(
          sendMessageAcked: false,
          sendMessageReply: null,
          storeInInboxResult: true,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello with lost ack',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // doc 115 P1 contract: custody → 'inboxed', envelope retained.
        expect(message!.status, 'inboxed');
        expect(message.transport, 'inbox');
        expect(message.wireEnvelope, isNotNull);
        expect(p2pService.probeRelayCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test('live send fails for an unknown-presence peer → durable inbox custody '
        '(no probe, no post-probe send)', () async {
      // FDC-03: formerly the P5 post-probe-send-attempt pin. The probe loop is
      // gone, so there is no post-probe send and probeRelayCallCount == 0; the
      // direct leg missed (useNullDiscover) so sendCallCount stays 0.
      p2pService = FakeP2PService(
        useNullDiscover: true,
        sendMessageResult: false,
        storeInInboxResult: true,
      );
      p2pService.probeRelayResult = RelayProbeResult.connected;

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello with failing live send',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'inboxed');
      expect(message.transport, 'inbox');
      expect(p2pService.probeRelayCallCount, 0);
      expect(p2pService.sendCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 1);
    });
  });

  // ─── Phase 1: Interactive Send Path Tests ─────────────────────────
  group('Phase 1 — interactive send path', () {
    test(
      'direct discover path persists actual send transport when Go returns relay',
      () async {
        p2pService = FakeP2PService(sendMessageTransport: 'relay');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello through actual relay',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'relay');
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.sendCallCount, 1);
      },
    );

    test(
      'existing connected peer is used before launching new transport attempts',
      () async {
        // Set up a FakeP2PService with the target peer already connected
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello connected!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'direct');
        // Should have sent without discover/dial (connection reuse)
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
        expect(p2pService.probeRelayCallCount, 0);
      },
    );

    test(
      'FDC-02: a circuit-only connection enters the full authenticated proof race',
      () async {
        // FDC-02 resolution A (C1): a peer whose ONLY live connection is a
        // `/p2p-circuit` must NOT take the reuse fast-path (which would carry a
        // warmed relay before the independently scheduled live legs can run.
        // It now falls into the full race. Here there is no LAN and the direct
        // dial succeeds with proof — and because a circuit conn
        // exists with no explicit Go transport, `_resolveGoSendTransport` still
        // infers 'relay'. So transport stays 'relay', but discover/dial now run
        // (proof the reuse short-circuit was skipped), and the staggered
        // relay-live leg is suppressed by the early direct proof.
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: [
                  '/ip4/10.0.0.8/tcp/4001/p2p/12D3KooWRelay/p2p-circuit',
                ],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello through reused relay',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'relay');
        // The reuse short-circuit was skipped: the direct leg discovered+dialed.
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.dialCallCount, 1);
        // One live send (the direct leg). The staggered relay-live leg was
        // suppressed by the early direct proof, so it never sent.
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.relayLiveSendCount, 0);
      },
    );

    // R2: LAN visibility is route metadata. An existing target-Peer-ID stream
    // remains authenticated and therefore retains reuse authority.
    test(
      'TC-04-12: LAN-visible peer with a direct conn reuses authenticated proof',
      () async {
        p2pService = FakeP2PService(
          useNullDiscover: true, // any fallback discovery would miss
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: [
                  '/ip4/192.168.1.20/tcp/4001',
                ], // DIRECT, not circuit
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
        )..localPeers.add('target-peer'); // isLocalPeer → true

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'same-wifi hello',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'direct');
        expect(p2pService.localSendCallCount, 0);
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.discoverCallCount, 0);
      },
    );

    // A learned direct/relay route reuses an authenticated stream even when the
    // peer is also LAN-visible. Only learned WebSocket-local is ineligible.
    test(
      'TC-04-13: learned relay sticky may prove delivery for a LAN peer',
      () async {
        p2pService = FakeP2PService(useNullDiscover: true)
          ..localPeers.add('target-peer') // isLocalPeer → true
          ..lastKnownGoodTransportResult = 'relay'; // learned relay

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'same-wifi hello 2',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'direct');
        expect(p2pService.localSendCallCount, 0);
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.discoverCallCount, 0);
      },
    );

    // TC-04-14: PS-2 preservation — a NON-local peer with a DIRECT conn STILL
    // takes the reuse fast-path (the gate is LAN-only, not a blanket disable).
    // Green-on-HEAD; re-reds only under a broaden-the-gate mutation.
    test('TC-04-14: non-local direct-conn peer still reuses (PS-2)', () async {
      p2pService = FakeP2PService(
        currentState: NodeState(
          isStarted: true,
          connections: [
            const p2p.ConnectionState(
              peerId: 'target-peer',
              multiaddrs: ['/ip4/127.0.0.1/tcp/4001'], // DIRECT
              direction: 'outbound',
              status: 'connected',
            ),
          ],
        ),
      ); // isLocalPeer → false (not in localPeers)

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'remote reuse',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.transport, 'direct'); // reuse preserved
      expect(p2pService.sendCallCount, 1); // the reuse send fired
      expect(p2pService.localSendCallCount, 0);
      expect(p2pService.discoverCallCount, 0); // no race — it reused
      expect(p2pService.dialCallCount, 0);
    });

    test(
      'explicit send transport beats conflicting mixed peer state on the reuse fast path',
      () async {
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/192.168.1.20/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: [
                  '/ip4/10.0.0.8/tcp/4001/p2p/12D3KooWRelay/p2p-circuit',
                ],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
          sendMessageTransport: 'direct',
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello through actual direct stream',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'direct');
      },
    );

    test(
      // FDC-04 (RC2/INV-2 / TC-04-12): this non-local connected control proves
      // the authenticated reuse path records the actual Go transport label.
      'existing non-local connected peer records actual Go transport on the reuse fast path',
      () async {
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/192.168.1.20/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
        ); // NOT LAN-visible → still reuses under FDC-04

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello through reused direct',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'direct');
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
        expect(p2pService.recordSuccessfulTransportCallCount, 1);
        expect(p2pService.lastRecordedTransport, 'direct');
      },
    );

    test(
      'existing connected unacked write falls through the authenticated race to inbox',
      () async {
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
          sendMessageAcked: false,
          sendMessageReply: null,
          storeInInboxResult: true,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello connected!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // 115 P1 contract flip: custody → 'inboxed', envelope retained.
        expect(message!.status, 'inboxed');
        expect(message.transport, 'inbox');
        expect(message.wireEnvelope, isNotNull);
        expect(p2pService.sendCallCount, 2);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.dialCallCount, 1);
      },
    );

    test(
      'local wifi and direct send race commits only the first successful path',
      () async {
        p2pService = DurableLanFakeP2PService()..localPeers.add('target-peer');
        // Both local and direct will succeed — but only one message should be persisted

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Race test!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        // Only one message should be persisted regardless of how many paths won
        expect(messageRepo.saved.length, 1);
      },
    );

    test(
      'slow local wifi does not block direct success beyond interactive budget',
      () async {
        // Create a service where local is slow but direct succeeds quickly
        final slowLocalP2P = _SlowLocalFastDirectP2PService();

        final stopwatch = Stopwatch()..start();
        final (result, message) = await sendChatMessage(
          p2pService: slowLocalP2P,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Speed test!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        stopwatch.stop();

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // Should complete quickly (direct path wins before local timeout)
        expect(stopwatch.elapsed.inSeconds, lessThan(3));
      },
    );

    test(
      'interactive direct discover uses short budget while background discover remains longer',
      () async {
        // This is a design/constant test — verify the budgets are distinct
        expect(interactiveLocalBudget.inMilliseconds, lessThanOrEqualTo(1500));
        expect(interactiveDirectBudget.inSeconds, lessThanOrEqualTo(4));
      },
    );

    test(
      'relay probe does not block direct discovery on the interactive path',
      () async {
        // Direct path should succeed without needing relay probe first
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'No relay probe!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // Direct discover/dial/send succeeded without relay gates
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.probeRelayCallCount, 0);
      },
    );

    test('all active send paths failing falls back to inbox once', () async {
      p2pService = FakeP2PService(
        sendMessageResult: false,
        useNullDiscover: true,
        storeInInboxResult: true,
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Inbox fallback!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'inboxed'); // 115 P1: custody, not delivery
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test(
      'same messageId winning on two paths persists only one outgoing message',
      () async {
        p2pService.localPeers.add('target-peer');
        const fixedMessageId = 'msg-dedup-001';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Dedup test!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: fixedMessageId,
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // Only one message with this ID should be persisted
        expect(messageRepo.saved.length, 1);
        expect(messageRepo.saved.first.id, fixedMessageId);
      },
    );
  });

  // ─── Section 4 — direct-first send with early wireEnvelope persistence ──
  group(
    'Section 4 — direct-first send with early wireEnvelope persistence',
    () {
      test(
        'RED: wireEnvelope is persisted to DB before discover is called',
        () async {
          // Track cross-component ordering via a shared list
          final callOrder = <String>[];
          messageRepo.onOrdinaryStage = () =>
              callOrder.add('stageOutgoingOrdinaryAttempt');
          p2pService.onDiscover = () => callOrder.add('discover');
          p2pService.onSendMessage = () => callOrder.add('sendMessage');

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'wireEnvelope persistence test',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: 'msg-wire-001',
          );

          expect(result, SendChatMessageResult.success);
          // wireEnvelope must be persisted
          expect(
            messageRepo.ordinaryStageCalls.single.staged.id,
            'msg-wire-001',
          );
          // wireEnvelope persist must happen before any P2P operation
          final wireIdx = callOrder.indexOf('stageOutgoingOrdinaryAttempt');
          final discoverIdx = callOrder.indexOf('discover');
          expect(
            wireIdx,
            isNot(-1),
            reason: 'the typed attempt stage must be called',
          );
          expect(
            wireIdx < discoverIdx,
            isTrue,
            reason: 'wireEnvelope persist must precede discover',
          );
        },
      );

      test(
        'RED: wireEnvelope is persisted even on the connection-reuse fast path',
        () async {
          p2pService = FakeP2PService(
            currentState: NodeState(
              isStarted: true,
              connections: [
                const p2p.ConnectionState(
                  peerId: 'target-peer',
                  multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
                  direction: 'outbound',
                  status: 'connected',
                ),
              ],
            ),
          );

          final (result, _) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Connected peer wireEnvelope',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: 'msg-wire-002',
          );

          expect(result, SendChatMessageResult.success);
          expect(
            messageRepo.ordinaryStageCalls.single.staged.id,
            'msg-wire-002',
          );
          expect(p2pService.discoverCallCount, 0); // reuse path skips discover
        },
      );

      test('RED: wireEnvelope is persisted on local WiFi path', () async {
        p2pService = FakeP2PService(useNullDiscover: true)
          ..localPeers.add('target-peer');

        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'WiFi wireEnvelope',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: 'msg-wire-003',
        );

        expect(result, SendChatMessageResult.success);
        expect(messageRepo.ordinaryStageCalls.single.staged.id, 'msg-wire-003');
      });

      test(
        'RED: wireEnvelope contains the same JSON as the P2P send payload',
        () async {
          final (result, _) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Envelope parity',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: 'fixed-id-001',
          );

          expect(result, SendChatMessageResult.success);
          // Verify the persisted wireEnvelope matches what was sent over P2P
          final stagedEnvelope =
              messageRepo.ordinaryStageCalls.single.staged.wireEnvelope;
          expect(stagedEnvelope, isNotNull);
          expect(p2pService.lastSentPayload, isNotNull);
          expect(stagedEnvelope, equals(p2pService.lastSentPayload));
          expect(stagedEnvelope, contains('"id":"fixed-id-001"'));
        },
      );

      test(
        'RED: wireEnvelope is persisted even when all P2P paths fail',
        () async {
          p2pService = FakeP2PService(
            sendMessageResult: false,
            useNullDiscover: true,
            storeInInboxResult: false,
          );

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'All fail but envelope persisted',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: 'msg-wire-fail',
          );

          expect(result, SendChatMessageResult.peerNotFound);
          expect(message!.status, 'failed');
          // wireEnvelope was still persisted before the transport race
          expect(
            messageRepo.ordinaryStageCalls.single.staged.id,
            'msg-wire-fail',
          );
        },
      );
    },
  );

  // ─── Section 4 — inbox call-site regression guard ──────────────────────
  group('Section 4 — inbox call-site regression guard', () {
    test(
      // FDC-03: the durability tier now fires CONCURRENTLY for unknown-presence
      // sends even when the direct leg ACKs (receiver messageId dedup discards
      // the duplicate). The "no phantom push on a confirmed path" guard now lives
      // on the reuse/local single-path locks (FDC-03-P1/P2), not on direct ACKs.
      'storeInInbox IS called once (concurrent durability) when direct P2P '
      'succeeds with ACK (FDC-03)',
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: true, // P2P succeeds with ACK
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Direct success concurrent inbox',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(message.transport, 'direct'); // the live leg wins the label
        // One concurrent durable copy fired alongside the winning live leg.
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test('storeInInbox is called when P2P succeeds without ACK', () async {
      p2pService = FakeP2PService(
        sendMessageResult: true,
        sendMessageAcked: false,
        sendMessageReply: '',
        storeInInboxResult: true,
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Unacked send',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // 115 P1 contract flip: custody → 'inboxed', envelope retained.
      expect(message!.status, 'inboxed');
      expect(message.transport, 'inbox');
      expect(message.wireEnvelope, isNotNull);
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test(
      'explicit acked=false hands off to inbox-backed custody when available',
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: true,
          sendMessageAcked: false,
          sendMessageReply: '',
          sendMessageTransport: 'direct',
          storeInInboxResult: true,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Explicit unacked send',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // 115 P1 contract flip: custody → 'inboxed', envelope retained.
        expect(message!.status, 'inboxed');
        expect(message.transport, 'inbox');
        expect(message.wireEnvelope, isNotNull);
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test(
      'storeInInbox IS called once when all P2P paths fail (existing behavior)',
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: false,
          useNullDiscover: true,
          storeInInboxResult: true,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'All fail inbox fallback',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'inboxed'); // 115 P1: custody, not delivery
        expect(message.transport, 'inbox');
        // Exactly one inbox call from the failure fallback — not zero, not two
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test(
      'when all P2P paths fail and inbox also fails, message persists as failed',
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: false,
          useNullDiscover: true,
          storeInInboxResult: false,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Both fail',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.peerNotFound);
        expect(message!.status, 'failed');
        // FDC-03: the concurrent inbox attempt fails (storeInInboxResult false),
        // then the serial fallback retries once — both fail → 2 calls.
        expect(p2pService.storeInInboxCallCount, 2);
      },
    );
  });

  // ─── Section 4 — inbox fallback edge cases ─────────────────────────────
  group('Section 4 — inbox fallback edge cases', () {
    test('storeInInbox throwing in the fallback path marks message as failed '
        'and wireEnvelope is still persisted for retry', () async {
      final throwingInboxP2P = _ThrowOnInboxP2PService();

      final (result, message) = await sendChatMessage(
        p2pService: throwingInboxP2P,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Inbox throws after P2P fails',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'msg-edge-001',
      );

      // P2P failed, inbox threw — message should be marked failed
      expect(result, SendChatMessageResult.peerNotFound);
      expect(message!.status, 'failed');
      // wireEnvelope was still persisted, so Section 1 retrier can recover
      expect(messageRepo.ordinaryStageCalls.single.staged.id, 'msg-edge-001');
    });

    test(
      'storeInInbox throwing does not affect result when direct P2P succeeds',
      () async {
        // P2P succeeds, so inbox fallback is never reached
        final throwingInboxP2P = _ThrowOnInboxP2PService(p2pSucceeds: true);

        final (result, message) = await sendChatMessage(
          p2pService: throwingInboxP2P,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Inbox throws but P2P succeeds',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
      },
    );

    test(
      'slow relay does not block P2P path — P2P result returns promptly',
      () async {
        // The existing behavior already runs inbox only on failure.
        // This test confirms P2P success returns without waiting for any
        // inbox operation (since inbox is not called on ACK'd success).
        p2pService = FakeP2PService(sendMessageResult: true);

        final stopwatch = Stopwatch()..start();
        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Fast direct',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        stopwatch.stop();

        expect(result, SendChatMessageResult.success);
        expect(stopwatch.elapsed.inSeconds, lessThan(3));
        // FDC-03: unknown-presence fires the concurrent durable copy even on a
        // fast direct success — fire-and-forget, so it does not block the sub-3s
        // return (the timing assertion above proves the live path is not stalled).
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );
  });

  group('NET-REL-04 — per-leg send-attempt census', () {
    test('direct leg failure is recorded even when the durable inbox delivers '
        '(the delivered-only mix cannot show this)', () async {
      // FDC-03: formerly "even when the relay probe delivers." The probe tail
      // is gone; the direct race leg fails (discover miss → peer_not_found) and
      // the CONCURRENT durable inbox carries custody. The census must still
      // record the direct FAILURE alongside the inbox SUCCESS.
      p2pService = FakeP2PService(
        useNullDiscover: true,
        storeInInboxResult: true,
      );
      final metrics = TransportMetrics();

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello through durable inbox',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        transportMetrics: metrics,
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'inboxed'); // custody, not delivery (doc 115)

      // The direct attempt failed; the inbox attempt succeeded — the per-leg
      // census shows the failed leg even though delivery happened elsewhere.
      expect(metrics.attemptCounts()['direct'], 1);
      expect(metrics.attemptFailureCounts()['direct'], 1);
      expect(metrics.attemptCounts()['inbox'], 1);
      expect(metrics.attemptFailureCounts()['inbox'], 0);
      // Not a terminal failure; the probe leg never ran (pre-init stays 0).
      expect(metrics.rungDistribution()['failed'], 0);
      expect(metrics.attemptCounts()['relay_probe'], 0);
    });

    test(
      'connection reuse success records exactly one successful reuse attempt '
      'and no race-leg attempts',
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: true,
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
        );
        final metrics = TransportMetrics();

        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Reuse hello',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          transportMetrics: metrics,
        );

        expect(result, SendChatMessageResult.success);
        expect(metrics.attemptCounts()['reuse'], 1);
        expect(metrics.attemptFailureCounts()['reuse'], 0);
        expect(metrics.attemptCounts()['direct'], 0);
        expect(metrics.attemptCounts()['local'], 0);
        expect(metrics.rungDistribution()['reuse'], 1);
      },
    );

    test(
      'total send failure records failed attempts for every leg it tried',
      () async {
        // No reuse (not connected), discover miss, relay probe errors, inbox
        // store fails → terminal failure.
        p2pService = FakeP2PService(useNullDiscover: true);
        p2pService.probeRelayResult = RelayProbeResult.error;
        p2pService.storeInInboxResult = false;
        final metrics = TransportMetrics();

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Doomed send',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          transportMetrics: metrics,
        );

        expect(result, isNot(SendChatMessageResult.success));
        expect(message!.status, 'failed');
        expect(metrics.attemptFailureCounts()['direct'], 1);
        // FDC-03: the probe tail is gone, so no relay_probe leg is attempted
        // (pre-init stays 0); the concurrent inbox attempt is the failed durable
        // leg here.
        expect(metrics.attemptFailureCounts()['relay_probe'], 0);
        // FDC-03: the inbox leg is tried TWICE (concurrent attempt + serial retry),
        // both fail → 2 recorded inbox failures.
        expect(metrics.attemptFailureCounts()['inbox'], 2);
        expect(metrics.rungDistribution()['failed'], 1);
        // No transport bucket incremented for a failed send.
        expect(metrics.totalTransportSamples, 0);
      },
    );
  });

  // ─── NET-REL-05/R2 — send orchestration, sticky, concurrent, dedup ───────
  //
  // Each happy case is paired with the negative control the doc names so a weak
  // test cannot pass falsely. U1/U-N1 now prove authenticated commitment beats
  // unauthenticated route rank without hanging on a failed leg. U2/U-N2 prove
  // authenticated learned reuse saves discovery work WITHOUT trapping the send
  // on a dead path or trusting learned WebSocket-local. U3/U-N3 prove the concurrent inbox fires for a
  // low-confidence send only, NOT a blanket dual-write. U4/U-N4 prove send-side
  // single-row dedup (same id → 1, different ids → 2). U5 + its budget control
  // prove the offline tail is bounded and a budget is actually ENFORCED.
  group('NET-REL-05 send orchestration', () {
    // R2 replacement for U1: direct proves delivery immediately; a later LAN
    // committed claim is written-only and cannot replace that proof.
    test(
      'U1 R2: first authenticated direct proof ignores later LAN evidence',
      () async {
        p2pService = DurableLanFakeP2PService()
          ..localPeers.add('target-peer')
          // Direct resolves immediately; unauthenticated LAN lands ~40ms later.
          ..localSendDelay = const Duration(milliseconds: 40);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Direct proof settles immediately',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'direct');
        expect(p2pService.localSendCallCount, 1);
        expect(p2pService.sendCallCount, 1);
      },
    );

    // U-N1 — local failure cannot delay a direct authenticated commitment.
    test('U-N1 R2: local failure does not delay direct proof', () async {
      p2pService = FakeP2PService()
        ..localPeers.add('target-peer')
        ..localSendResult = false; // local leg fails outright

      final sw = Stopwatch()..start();
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Local fails, direct carries',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );
      sw.stop();

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.transport, 'direct');
      expect(p2pService.localSendCallCount, 1);
      // The direct proof is not parked on a winner-selection timer.
      expect(sw.elapsedMilliseconds, lessThan(120));
    });

    // U2 — sticky SHORT-CIRCUIT (the real latency win, R3). A learned+valid
    // transport REUSES the known-good path and SKIPS discover/dial entirely.
    // The assertion is load-bearing and mutation-resistant: a sticky 'direct'
    // send must do ZERO discover and ZERO dial (it goes straight to
    // sendMessageWithReply), while the paired cold send (no learned transport)
    // pays exactly ONE discover + ONE dial. Deleting the short-circuit block in
    // send_chat_message_use_case.dart makes the sticky send fall into the full
    // race → discoverCallCount/dialCallCount become 1 → this test goes RED.
    test(
      'U2 sticky short-circuit: learned direct skips discover+dial',
      () async {
        p2pService = FakeP2PService(sendMessageTransport: 'direct')
          ..lastKnownGoodTransportResult = 'direct';
        // Peer is NOT in connections (reuse block does not fire) and NOT local —
        // so any discover/dial seen would come from the cold race, not reuse.
        expect(p2pService.currentState.connections, isEmpty);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Reuse the learned direct path',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'direct');
        // The short-circuit sent directly over the learned transport: no
        // re-discovery, no re-dial.
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
        expect(p2pService.sendCallCount, 1);
      },
    );

    // R2 replacement: a learned local label cannot establish authentication and
    // therefore joins the ordinary race instead of short-circuiting direct.
    test(
      'U2 R2: learned local cannot skip authenticated direct proof',
      () async {
        p2pService = DurableLanFakeP2PService()
          ..localPeers.add('target-peer')
          ..lastKnownGoodTransportResult = 'local';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Reuse the learned local path',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'direct');
        expect(p2pService.localSendCallCount, 1);
        expect(p2pService.discoverLocalPeerCallCount, 0);
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.dialCallCount, 1);
      },
    );

    // COLD control paired with U2: with NO learned transport, the same send
    // pays the full discover + dial. This is the counter-baseline that makes
    // the U2 short-circuit assertions (==0) meaningful rather than vacuous.
    test(
      'U2 cold baseline: no learned transport pays one discover + one dial',
      () async {
        p2pService = FakeP2PService(sendMessageTransport: 'direct');
        expect(p2pService.lastKnownGoodTransport('target-peer'), isNull);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Cold send pays full discovery',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'direct');
        // Full cold race: the direct leg discovered once and dialed once.
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.dialCallCount, 1);
      },
    );

    // U2 (write half) — the LIVE transport that delivered is RECORDED so the
    // next send can be weighted toward it. Proves the memory layer is written
    // on a successful live (acked) delivery.
    test(
      'U2 sticky write: a delivered live send records its transport',
      () async {
        p2pService = FakeP2PService(sendMessageTransport: 'direct');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Record me',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(p2pService.recordSuccessfulTransportCallCount, 1);
        expect(p2pService.lastRecordedTransport, 'direct');
        expect(p2pService.lastRecordedTransportPeerId, 'target-peer');
      },
    );

    // U-N2 — sticky NEGATIVE control (a): the learned transport FAILS at the
    // short-circuit. The send must NOT be trapped on the dead learned path: it
    // falls THROUGH to today's full parallel race and the surviving local leg
    // delivers. Here learned == 'direct' but the direct send returns sent:false
    // (the learned connection is gone), so the sticky short-circuit fails and
    // the local leg carries the message. Proves the short-circuit is a pure
    // fast-path: on any miss it degrades to the cold race, never blocks.
    test(
      'U-N2 sticky neg: learned transport fails → full race still delivers',
      () async {
        p2pService = DurableLanFakeP2PService(sendMessageResult: false)
          ..localPeers.add('target-peer') // local can carry it
          ..lastKnownGoodTransportResult = 'direct';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Dead learned leg',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // The learned (direct) short-circuit failed; the surviving local leg
        // delivered via the full race fallback.
        expect(message!.transport, 'local');
        expect(p2pService.localSendCallCount, 1);
      },
    );

    // U-N2 — sticky NEGATIVE control (b): a fake that reports NO learned
    // transport (the production behavior for an expired/stale preference, which
    // returns null) runs the FULL cold race — discover fires exactly once. This
    // pins that a null/ignored preference does not change the race shape.
    test(
      'U-N2 sticky neg: absent/expired preference runs the full cold race',
      () async {
        p2pService = FakeP2PService(); // lastKnownGoodTransportResult == null
        expect(p2pService.lastKnownGoodTransport('target-peer'), isNull);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Stale ignored',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // Full race ran exactly as a cold send would.
        expect(p2pService.discoverCallCount, 1);
      },
    );

    // U3 — concurrent durable fallback (happy): a LOW-confidence send (peer not
    // connected/local AND a recent prior outgoing attempt terminally failed)
    // fires the inbox copy CONCURRENTLY with the live race. Assert BOTH fired:
    // the live send (sendCallCount == 1) AND the concurrent inbox
    // (storeInInboxCallCount == 1). The live send wins the label here.
    test(
      'U3 concurrent: low-confidence send fires inbox AND live in parallel',
      () async {
        p2pService = FakeP2PService(); // direct live send succeeds with ack
        messageRepo.latestMessageForContact = ConversationMessage(
          id: 'prior-attempt-id',
          contactPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          text: 'Earlier failed message',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          status: 'failed', // terminal failure → low confidence
          isIncoming: false,
          createdAt: DateTime.now()
              .toUtc()
              .subtract(const Duration(seconds: 5))
              .toIso8601String(),
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Low-confidence retry',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // BOTH paths fired: the concurrent durable copy AND the live send.
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendCallCount, 1);
        // The live race won the transport label (concurrent inbox is a durability
        // side-effect, not the label).
        expect(message!.transport, 'direct');
      },
    );

    // NET-REL-05 E2 correlation: the send-path FLOW events the device runbook
    // correlates by messageId ("live attempt AND inbox store fired") previously
    // omitted the id. These pin that BEGIN / CUSTODY / RELAY_PROBE_CONNECTED now
    // carry it. Mutation: drop the 'id' from any of the three events → the
    // matching expectation goes RED.
    group('E2 correlation: send-path FLOW events carry the message id', () {
      ConversationMessage priorFailedAttempt() => ConversationMessage(
        id: 'prior-attempt-id',
        contactPeerId: 'target-peer',
        senderPeerId: 'my-peer',
        text: 'Earlier failed message',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        status: 'failed', // terminal failure → low confidence
        isIncoming: false,
        createdAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(seconds: 5))
            .toIso8601String(),
      );

      Map<String, dynamic>? detailsOf(
        List<Map<String, dynamic>> events,
        String name,
      ) {
        for (final e in events) {
          if (e['event'] == name) {
            return e['details'] as Map<String, dynamic>;
          }
        }
        return null;
      }

      test(
        'BEGIN + CUSTODY carry the id (low-confidence, inbox takes custody)',
        () async {
          final p2p = FakeP2PService(
            sendMessageResult: false, // live race fails
            storeInInboxResult: true, // concurrent inbox takes custody
          );
          final repo = FakeMessageRepository();
          repo.latestMessageForContact = priorFailedAttempt();

          late ConversationMessage sent;
          final events = await captureFlowEvents(() async {
            final (result, message) = await sendChatMessage(
              p2pService: p2p,
              messageRepo: repo,
              targetPeerId: 'target-peer',
              text: 'low-confidence retry',
              senderPeerId: 'my-peer',
              senderUsername: 'Me',
            );
            expect(result, SendChatMessageResult.success);
            sent = message!;
          });

          final idPrefix = sent.id.substring(0, 8);
          final begin = detailsOf(
            events,
            'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
          );
          final custody = detailsOf(
            events,
            'CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY',
          );
          expect(
            begin,
            isNotNull,
            reason: 'low-confidence send must fire the inbox arm',
          );
          expect(
            custody,
            isNotNull,
            reason: 'inbox must take custody when the live race fails',
          );
          expect(begin!['id'], idPrefix);
          expect(custody!['id'], idPrefix);
        },
      );

      // FDC-03: the RELAY_PROBE_CONNECTED id-correlation test is RETIRED — the
      // serial relay-probe tail (and its CHAT_MSG_SEND_RELAY_PROBE_CONNECTED
      // event) was removed. Live relay recovery is FDC-02's in-race relay-live
      // leg; the BEGIN/CUSTODY id correlation above still covers the durable
      // inbox path that now carries an offline send.
    });

    // ─── FDC-03 — generalize the concurrent durable inbox to ALL unknown- ──
    // presence sends (R6 / P0-2). The 30s prior-attempt recency gate is REMOVED:
    // a send that is not already-connected, not LAN-local, and has no live peer
    // connection fires the durable inbox copy CONCURRENTLY with the live race,
    // independent of prior-attempt recency. The OLD "U-N3 high-confidence does
    // NOT fire" / "stale stays high-confidence" negative controls are INVERTED by
    // FDC-03 (a high-confidence unknown-presence send now DOES fire) and replaced
    // by FDC-03-01..05 below. The "not a blanket dual-write" invariant now lives
    // on the kept reuse/local structural guards (FDC-03-P1/P2) and the 116 EF-2
    // gate (which already asserts storeInInboxCallCount==0 on a downgrade-blocked
    // send — the FDC-03-P3 lock), NOT on prior-attempt recency. FDC-03-P4 is the
    // existing U3 test above (low-confidence ⊂ unknown-presence, still fires).
    group('FDC-03 concurrent durable inbox — unknown-presence generalization', () {
      test('FDC-03-01 unknown-presence live-success ALSO deposits one concurrent '
          'inbox copy', () async {
        // Default fake: not connected, not local, discover succeeds, live send
        // acked. No prior attempt → HIGH confidence on HEAD, where the old gate
        // fired NO concurrent inbox (the old U-N3 asserted count 0).
        p2pService = FakeP2PService();
        expect(messageRepo.latestMessageForContact, isNull);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'First-ever send to an unknown-presence peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // The live leg wins the transport label...
        expect(message!.status, 'delivered');
        expect(message.transport, 'direct');
        // ...AND the durable inbox copy fired CONCURRENTLY exactly once.
        // Mutation: re-add the recency gate (wrap the arm back in a low-confidence
        // `if` / restore getLatestMessageForContact) → count back to 0 → RED.
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendCallCount, 1);
      });

      test('FDC-03-02 CONCURRENT_INBOX_BEGIN fires for an unknown-presence send '
          'whose live leg WINS', () async {
        final p2p = FakeP2PService(); // live success, no prior attempt
        final repo = FakeMessageRepository();

        late ConversationMessage sent;
        final events = await captureFlowEvents(() async {
          final (result, message) = await sendChatMessage(
            p2pService: p2p,
            messageRepo: repo,
            targetPeerId: 'target-peer',
            text: 'unknown-presence live win',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );
          expect(result, SendChatMessageResult.success);
          sent = message!;
        });

        final names = events.map((e) => e['event']).toList();
        // The deposit ran CONCURRENTLY (not on the serial unhappy path)...
        // Mutation: move the BEGIN emit back behind the recency gate → absent.
        expect(names, contains('CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN'));
        final begin = events.firstWhere(
          (e) => e['event'] == 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
        );
        expect((begin['details'] as Map)['id'], sent.id.substring(0, 8));
        // ...in parallel with a WINNING live leg (terminal success via direct).
        final success = events.firstWhere(
          (e) => e['event'] == 'CHAT_MSG_SEND_SUCCESS',
        );
        expect((success['details'] as Map)['via'], 'direct');
      });

      test('FDC-03-03 race failure for an unknown-presence peer commits inbox '
          'custody WITHOUT the relay probe', () async {
        // Direct leg misses (peer_not_found → relay-probe-eligible on HEAD); the
        // concurrent inbox accepts custody. The serial probe tail is GONE.
        p2pService = FakeP2PService(
          useNullDiscover: true,
          storeInInboxResult: true,
        )..probeRelayResult = RelayProbeResult.connected;

        late ConversationMessage sent;
        final events = await captureFlowEvents(() async {
          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'unknown-presence race failure → inbox custody',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );
          expect(result, SendChatMessageResult.success);
          sent = message!;
        });

        expect(sent.status, 'inboxed');
        expect(sent.transport, 'inbox');
        expect(sent.wireEnvelope, isNotNull); // custody retained (doc 115)
        // RED on HEAD because the recency gate left concurrentInbox null, so a
        // race-fail ran the probe (count 1) and delivered live; FDC-03 takes
        // concurrent-inbox custody instead. NOTE: with storeInInboxResult true the
        // custody short-circuit returns BEFORE the (removed) probe location, so
        // the dedicated probe-tail-removal mutation lock is FDC-03-03b below
        // (which fails the concurrent copy to actually reach that spot).
        expect(p2pService.probeRelayCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 1);
        final names = events.map((e) => e['event']).toList();
        expect(names, contains('CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN'));
        expect(names, contains('CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY'));
        expect(names, isNot(contains('CHAT_MSG_SEND_RELAY_PROBE_CONNECTED')));
      });

      test(
        'FDC-03-03b race-fail whose concurrent copy ALSO fails reaches the '
        'former probe location WITHOUT running the probe (invariant #4 lock)',
        () async {
          // The concurrent copy FAILS (storeInInboxResult: false), so the custody
          // short-circuit does NOT fire and control reaches the spot where the
          // serial relay-probe tail used to sit. The probe is gone, so it never
          // runs even though the race is relay-eligible (peer_not_found). This is
          // the ONLY test that actually exercises the removed-probe location.
          // RED on the pre-FDC-03 implementation: concurrentInbox was null, so
          // the probe ran and delivered live. Mutation recipe: temporarily
          // restore the helper, then immediately before the offline-inbox
          // fallback insert:
          // if (raceResult.relayProbeEligible) {
          //   await _tryRelayProbeSend(
          //     p2pService,
          //     targetPeerId,
          //     jsonString,
          //     failureReason: failureReason,
          //     messageId: resolvedMessageId,
          //   );
          // }
          // That makes probeRelayCallCount == 1 and this assertion RED.
          p2pService = FakeP2PService(
            useNullDiscover:
                true, // direct misses → peer_not_found (relay-eligible)
            storeInInboxResult:
                false, // concurrent copy fails → no short-circuit
          )..probeRelayResult = RelayProbeResult.connected;

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'concurrent fails → reach the removed probe location',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );

          // The probe never runs (invariant #4: no serial relay-probe carrier)...
          expect(
            p2pService.probeRelayCallCount,
            0,
            reason: 'DTR05-MUTATION serial-probe-count',
          );
          // ...and control reached the serial tail past the probe spot: the inbox
          // was attempted twice (concurrent + serial retry), both failing.
          expect(p2pService.storeInInboxCallCount, 2);
          expect(result, SendChatMessageResult.peerNotFound);
          expect(message!.status, 'failed');
        },
      );

      test(
        'FDC-03-04 concurrent custody writes storeInInbox EXACTLY once',
        () async {
          // Live race fails to land (send returns false); the concurrent inbox
          // succeeds and takes custody — so the serial store must be SKIPPED.
          p2pService = FakeP2PService(
            sendMessageResult: false,
            storeInInboxResult: true,
          );

          late ConversationMessage sent;
          final events = await captureFlowEvents(() async {
            final (result, message) = await sendChatMessage(
              p2pService: p2pService,
              messageRepo: messageRepo,
              targetPeerId: 'target-peer',
              text: 'one relay write only',
              senderPeerId: 'my-peer',
              senderUsername: 'Me',
            );
            expect(result, SendChatMessageResult.success);
            sent = message!;
          });

          expect(sent.status, 'inboxed');
          // Exactly one storeInInbox: the concurrent copy. Mutation: remove the
          // "skip serial store when concurrent custody succeeded" short-circuit →
          // the serial store runs after the concurrent one → count 2 → RED.
          expect(p2pService.storeInInboxCallCount, 1);
          final names = events.map((e) => e['event']).toList();
          expect(names, contains('CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN'));
          expect(names, contains('CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY'));
        },
      );

      test('FDC-03-05 unacked live write for an unknown-presence peer settles '
          'inboxed via the concurrent copy', () async {
        // The live write is sent-but-unacked (sendMessageReply: null); the
        // concurrent inbox already holds custody, so the unacked branch settles
        // 'inboxed' WITHOUT a second sequential store.
        p2pService = FakeP2PService(
          sendMessageAcked: false,
          sendMessageReply: null,
          storeInInboxResult: true,
        );

        late ConversationMessage sent;
        final events = await captureFlowEvents(() async {
          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'unacked → concurrent custody',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );
          expect(result, SendChatMessageResult.success);
          sent = message!;
        });

        expect(sent.status, 'inboxed');
        expect(sent.transport, 'inbox');
        expect(sent.wireEnvelope, isNotNull);
        expect(p2pService.storeInInboxCallCount, 1);
        final names = events.map((e) => e['event']).toList();
        // Settled via the concurrent copy, NOT the serial handoff. Mutation:
        // re-gate the unacked concurrent branch behind the old low-conf flag →
        // it falls to the serial handoff → HANDOFF_BEGIN reappears → RED.
        expect(
          names,
          contains('CHAT_MSG_SEND_UNACKED_CONCURRENT_INBOX_CUSTODY'),
        );
        expect(
          names,
          isNot(contains('CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_BEGIN')),
        );
      });

      // ── Preserved single-path locks (green on HEAD) — "not a blanket dual- ──
      // write." FDC-03-P3 = the existing 116 EF-2 gate (a downgrade-blocked send
      // already asserts storeInInboxCallCount==0); FDC-03-P4 = the existing U3
      // low-confidence test (low-confidence ⊂ unknown-presence, still fires).
      test('FDC-03-P1 reuse send does NOT fire the concurrent inbox', () async {
        // A peer with a live (non-circuit) connection reuses the wire ack and
        // returns BEFORE the unknownPresence gate is evaluated. The load-bearing
        // lock is discoverCallCount == 0 (the reuse early-return is taken); the
        // gate's !isAlreadyConnected term then keeps storeInInboxCallCount at 0.
        // Mutation: remove the reuse early-return → discoverCallCount == 1 → RED.
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'reuse stays single-path',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'direct'); // reuse labels 'direct'
        expect(p2pService.discoverCallCount, 0); // proof of the reuse path
        expect(p2pService.storeInInboxCallCount, 0);
      });

      test(
        'FDC-03-P2 LAN-local send does NOT fire the concurrent inbox',
        () async {
          // LAN visibility still keeps the eager concurrent inbox off; the
          // authenticated direct race leg proves delivery and LAN remains
          // written-only. The sequential inbox backstop remains available if no
          // proof arrives.
          p2pService = DurableLanFakeP2PService()
            ..localPeers.add('target-peer');

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'LAN-local stays single-path',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );

          expect(result, SendChatMessageResult.success);
          expect(message!.transport, 'direct');
          expect(p2pService.storeInInboxCallCount, 0);
        },
      );
    });

    // U4 — dedup (happy): the same messageId winning on more than one path
    // persists exactly ONE outgoing row. Local + direct both succeed for the
    // same id; only one message is saved.
    test(
      'U4 dedup: same messageId across paths persists exactly one row',
      () async {
        p2pService = DurableLanFakeP2PService()..localPeers.add('target-peer');
        const fixedId = 'msg-nr05-dedup-001';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Dedup one row',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: fixedId,
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(messageRepo.saved, hasLength(1));
        expect(messageRepo.saved.single.id, fixedId);
      },
    );

    // U-N4 — dedup NEGATIVE control: two DIFFERENT messageIds persist TWO rows.
    // Proves the single-row behavior is keyed on identity, not swallowing
    // distinct messages.
    test('U-N4 dedup neg: two different messageIds persist two rows', () async {
      p2pService = FakeP2PService();

      final (r1, m1) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'First distinct',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'msg-nr05-distinct-A',
      );
      final (r2, m2) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Second distinct',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'msg-nr05-distinct-B',
      );

      expect(r1, SendChatMessageResult.success);
      expect(r2, SendChatMessageResult.success);
      expect(messageRepo.saved, hasLength(2));
      expect(
        messageRepo.saved.map((m) => m.id),
        containsAll(<String>['msg-nr05-distinct-A', 'msg-nr05-distinct-B']),
      );
      expect(m1!.id, isNot(m2!.id));
    });

    // U5 — worst-case timeline (offline peer): discover misses, the relay probe
    // returns NO_RESERVATION (peer offline), so the tail goes STRAIGHT to inbox
    // and durable custody is taken. Assert the bounded sequential tail: probe
    // fired once, NO post-probe live send (NO_RESERVATION short-circuits), and
    // inbox took custody → delivered.
    test(
      'U5 worst-case: offline peer → NO_RESERVATION → durable inbox custody',
      () async {
        p2pService = FakeP2PService(
          useNullDiscover: true, // direct leg: peer_not_found (relay-eligible)
          storeInInboxResult: true, // inbox accepts custody
        );
        p2pService.probeRelayResult = RelayProbeResult.noReservation;

        final sw = Stopwatch()..start();
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Offline peer durable',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        sw.stop();

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'inboxed'); // 115 P1: custody, not delivery
        expect(message.transport, 'inbox');
        // FDC-03: the probe tail is gone — the concurrent durable inbox carries
        // custody; no probe and no live send fire for this discover-miss peer.
        expect(p2pService.probeRelayCallCount, 0);
        expect(p2pService.sendCallCount, 0);
        // Inbox took custody exactly once (the concurrent copy).
        expect(p2pService.storeInInboxCallCount, 1);
        // The whole offline path stays comfortably bounded.
        expect(sw.elapsedMilliseconds, lessThan(2000));
      },
    );

    // U5 — budget ENFORCEMENT (negative control): a deliberately slow local leg
    // (overruns the 1500ms interactiveLocalBudget) must be CUT at its budget,
    // not allowed to run to completion. The fast direct leg carries the
    // message, and the local timeout is the budget — proving the cutoff fires,
    // not luck. Patterned after the lastLocalSendTimeoutMs assertion.
    test('U5 budget: a slow local leg is cut at the local budget', () async {
      p2pService = FakeP2PService()
        ..localPeers.add('target-peer')
        // Local send overruns the 1500ms budget by a wide margin.
        ..localSendDelay = const Duration(seconds: 5);

      final sw = Stopwatch()..start();
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Slow local cut at budget',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );
      sw.stop();

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // The over-budget local leg lost — direct carried it.
      expect(message!.transport, 'direct');
      // The local leg was invoked with the local budget as its timeout
      // (enforced cutoff), and the overall send did NOT wait out the 5s local
      // send (it is cut well before that).
      expect(
        p2pService.lastLocalSendTimeoutMs,
        interactiveLocalBudget.inMilliseconds,
      );
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
  });

  // ─── 115 Phase 1 — inbox custody truthfulness ──────────────────────────
  // Relay-inbox acceptance is CUSTODY, not delivery: the relay silently
  // evicts at the 100-cap and TTL-prunes at 7 days with no protocol signal
  // (doc 115 §1). Sender rows must persist the distinct non-terminal status
  // 'inboxed' with the wire envelope RETAINED so the custody sweep (115 P3)
  // can re-store and delivery receipts (115 P2) can flip to 'delivered'.
  group('115 Phase 1 — inbox custody truthfulness', () {
    test(
      "sequential inbox fallback persists status 'inboxed' with transport 'inbox' and retains wire_envelope",
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: false,
          useNullDiscover: true, // direct leg: peer_not_found
          storeInInboxResult: true, // sequential inbox tail takes custody
        );

        final events = await captureFlowEvents(() async {
          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Custody not delivery',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );

          expect(result, SendChatMessageResult.success);
          expect(message, isNotNull);
          expect(message!.status, 'inboxed');
          expect(message.transport, 'inbox');
          expect(
            message.wireEnvelope,
            isNotNull,
            reason: 'custody sweep re-store needs the envelope retained',
          );
          expect(messageRepo.saved.single.status, 'inboxed');
          expect(messageRepo.saved.single.wireEnvelope, isNotNull);
        });

        final success = events.lastWhere(
          (event) => event['event'] == 'CHAT_MSG_SEND_SUCCESS',
        );
        expect(success['details']['status'], 'inboxed');
      },
    );

    test(
      "unacked live write with successful inbox handoff persists 'inboxed', not 'delivered'",
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: true,
          sendMessageAcked: false, // live write unacked
          sendMessageReply: '',
          sendMessageTransport: 'direct',
          storeInInboxResult: true, // handoff takes custody
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Unacked handoff custody',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'inboxed');
        expect(message.transport, 'inbox');
        expect(message.wireEnvelope, isNotNull);
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test(
      "concurrent durable-copy custody short-circuit persists 'inboxed'",
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: false, // live race fails
          storeInInboxResult: true, // concurrent inbox copy wins custody
        );
        // Prior terminally-failed attempt → low-confidence send → the
        // concurrent inbox arm fires alongside the live race.
        messageRepo.latestMessageForContact = ConversationMessage(
          id: 'prior-attempt-id',
          contactPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          text: 'Earlier failed message',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          status: 'failed',
          isIncoming: false,
          createdAt: DateTime.now()
              .toUtc()
              .subtract(const Duration(seconds: 5))
              .toIso8601String(),
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Concurrent custody short-circuit',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'inboxed');
        expect(message.transport, 'inbox');
        expect(message.wireEnvelope, isNotNull);
      },
    );

    // Green-on-arrival PIN (does not count toward the phase RED count):
    // the live deferred-ack is G4 allowed minting site (b) — Go withholds
    // the wire ack until the receiver durably stages (node.go:1616-1652),
    // so an acked live send IS receiver-confirmed and stays 'delivered'.
    test('live acked send still persists delivered (live transport)', () async {
      p2pService = FakeP2PService(); // acked direct send

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Live ack stays delivered',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'delivered');
      expect(message.transport, 'direct');
      // FDC-03: unknown-presence now fires one concurrent durable copy alongside
      // the winning live leg (status/transport unchanged).
      expect(p2pService.storeInInboxCallCount, 1);
    });
  });

  // ─── 116 Phase 2 — no-downgrade writer gate (EF-2) ──────────────────────
  // A plain-send invocation under a message id whose outgoing row carries
  // editedAt or deletedAt must fail closed BEFORE encryption and before the
  // pre-race updateWireEnvelope — so a stored edit envelope can never be
  // overwritten (poisoned) by a plain envelope, and plain content can never
  // be transmitted under an edit/tombstone id. All UI retry paths route
  // through retryFailedMessage, so this gate has ZERO legitimate trips: any
  // field occurrence of CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED is a bug
  // detector, not a feature.
  group('116 Phase 2 — no-downgrade writer gate', () {
    const editEnvelope =
        '{"type":"chat_message","version":"2","id":"msg-gate-edit-001","senderPeerId":"my-peer","encrypted":{"kem":"k","ciphertext":"{\\"id\\":\\"msg-gate-edit-001\\",\\"action\\":\\"edit\\"}","nonce":"n"}}';

    test(
      'refuses a plain send under an edited message id and leaves the stored edit envelope untouched',
      () async {
        final editedRow = ConversationMessage(
          id: 'msg-gate-edit-001',
          contactPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          text: 'edited text',
          timestamp: '2026-01-01T00:00:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-01-01T00:00:00.000Z',
          editedAt: '2026-01-01T00:05:00.000Z',
          wireEnvelope: editEnvelope,
        );
        messageRepo.existingMessages[editedRow.id] = editedRow;

        final events = await captureFlowEvents(() async {
          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'anything',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: 'msg-gate-edit-001',
          );
          expect(result, SendChatMessageResult.invalidMessage);
          expect(message, isNull);
        });

        expect(
          messageRepo.wireEnvelopeUpdates,
          isEmpty,
          reason: 'the pre-race envelope overwrite must never run (EF-2)',
        );
        expect(messageRepo.saved, isEmpty);
        expect(p2pService.sendCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        final blocked = events.singleWhere(
          (e) => e['event'] == 'CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED',
        );
        expect(blocked['details']['reason'], 'edited_row_plain_send');
      },
    );

    test('refuses a plain send under a deleted tombstone id', () async {
      final tombstoneRow = ConversationMessage(
        id: 'msg-gate-del-001',
        contactPeerId: 'target-peer',
        senderPeerId: 'my-peer',
        text: '',
        timestamp: '2026-01-01T00:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-01-01T00:00:00.000Z',
        deletedAt: '2026-01-01T00:01:00.000Z',
        deletedByPeerId: 'my-peer',
        wireEnvelope:
            '{"type":"message_deletion","version":"2","encrypted":{}}',
      );
      messageRepo.existingMessages[tombstoneRow.id] = tombstoneRow;

      final events = await captureFlowEvents(() async {
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          // Non-empty so the empty-text gate cannot mask the check: without
          // the gate this would transmit a plain chat payload under a
          // tombstone id (resurrection hazard).
          text: 'non-empty so the empty-text gate does not mask the check',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: 'msg-gate-del-001',
        );
        expect(result, SendChatMessageResult.invalidMessage);
        expect(message, isNull);
      });

      expect(messageRepo.wireEnvelopeUpdates, isEmpty);
      expect(messageRepo.saved, isEmpty);
      expect(p2pService.sendCallCount, 0);
      final blocked = events.singleWhere(
        (e) => e['event'] == 'CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED',
      );
      expect(blocked['details']['reason'], 'deleted_row_plain_send');
    });
  });

  // ─── FDC-01 — direct_timeout mis-route + per-step budget decouple ──────────
  // Proposal §4.1: a slow-but-ONLINE peer was silently routed to the durable
  // inbox because (1) the per-step direct budgets were not independent of the
  // outer aggregate cap (2s ≡ 2s starved dial+send), and (2) the resulting
  // `direct_timeout` was not relay-probe-eligible. These lock the decouple +
  // eligibility; preservation of offline-inbox / happy-direct lives above.
  group('FDC-01 — direct-timeout misroute + per-step budget', () {
    test('FDC-01 slow discover within step budget still delivers direct '
        '(no starvation)', () async {
      // High-confidence (no prior failed/inboxed row), not local, not
      // connected. Inner total ≈ 1900ms discover + ~0 dial + 300ms send ≈
      // 2200ms: every step stays under the 2s per-step budget, but the sum
      // exceeds the OLD 2s outer cap. On HEAD that cap fires mid-send →
      // non-eligible direct_timeout → inboxed. With the decoupled aggregate
      // (6s) the direct leg lands live.
      p2pService =
          FakeP2PService(
              storeInInboxResult: true,
              sendMessageAcked: true,
              dialPeerResult: true,
            )
            ..discoverDelay = const Duration(milliseconds: 1900)
            ..sendDelay = const Duration(milliseconds: 300);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Slow but online',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'delivered');
      expect(message.transport, 'direct');
      // FDC-03: the concurrent durable copy fires for this unknown-presence
      // send (count 1); the direct leg still WINS (no starvation) — FDC-01's
      // intent is preserved, only the durability side-effect is new.
      expect(p2pService.storeInInboxCallCount, 1);
      expect(p2pService.probeRelayCallCount, 0);
      expect(p2pService.recordSuccessfulTransportCallCount, 1);
    });

    test('FDC-01 discover-step timeout → durable inbox custody '
        '(FDC-03: probe tail removed)', () async {
      // Discover overruns the 2s per-step budget → eligible peer_not_found
      // (NOT swallowed by the aggregate). FDC-03: the serial probe tail is
      // gone, so the eligible-timeout peer takes durable custody via the
      // CONCURRENT inbox (the live-relay path is now FDC-02's in-race leg, which
      // requires a pre-existing circuit). FDC-01's step-budget enforcement is
      // still exercised here (the discover times out at the step budget).
      p2pService = FakeP2PService(
        storeInInboxResult: true,
        probeRelayResult: RelayProbeResult.connected,
        sendMessageAcked: true,
      )..discoverDelay = const Duration(milliseconds: 2100);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Online via durable inbox',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // The probe never runs (tail removed); custody is the concurrent inbox.
      expect(p2pService.probeRelayCallCount, 0);
      expect(message!.transport, 'inbox');
      expect(message.status, 'inboxed');
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test(
      'FDC-01 committed send keeps the remaining live deadline for ACK',
      () async {
        // R3 replaces the obsolete 1.5s send cap with the exact remaining T0
        // allocation. A 2.1s deferred commitment remains a valid live delivery
        // instead of being misclassified as a send-step timeout.
        p2pService = FakeP2PService(
          storeInInboxResult: true,
          probeRelayResult: RelayProbeResult.noReservation,
          dialPeerResult: true,
          sendMessageAcked: true,
          sendMessageTransport: 'direct',
        )..sendDelay = const Duration(milliseconds: 2100);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Send times out',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(p2pService.probeRelayCallCount, 0);
        expect(message!.status, 'delivered');
        expect(message.transport, 'direct');
        expect(p2pService.sendTimeouts.single, greaterThan(3000));
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test('FDC-01 aggregate direct budget exceeds the per-step budget', () {
      // Compile-level RED on HEAD (constant absent). Encodes the decouple
      // invariant: the serial ceiling strictly exceeds — and is ≥3× — any
      // single per-step budget, while the per-step bound stays ≤4s (:2486).
      expect(
        interactiveDirectAggregateBudget.inMilliseconds,
        greaterThan(interactiveDirectBudget.inMilliseconds),
      );
      expect(
        interactiveDirectAggregateBudget.inMilliseconds,
        greaterThanOrEqualTo(3 * interactiveDirectBudget.inMilliseconds),
      );
      expect(interactiveDirectBudget.inSeconds, lessThanOrEqualTo(4));
    });
  });

  // ─── FDC-02/R2 — staggered relay scheduling + proof-first settlement ─────
  // Proposal §6.2: relay is no longer folded (penalty-free) into the direct leg.
  // A live `/p2p-circuit` peer no longer reuse-short-circuits (C1 resolution A) —
  // it RACES, with a staggered relay-LIVE leg that (a) is started kRelayLegStagger
  // behind the LAN/direct legs, (b) is suppressed only if authenticated proof
  // already committed, and (c) never carries media/large payloads. Leg-attributable proof via
  // relayLiveSendCount (delivery alone is masked by receiver dedup — FDC-00).
  group('FDC-02 — staggered relay proof race', () {
    const circuitMultiaddr =
        '/ip4/10.0.0.8/tcp/4001/p2p/12D3KooWRelay/p2p-circuit';
    NodeState circuitOnlyState() => const NodeState(
      isStarted: true,
      connections: [
        p2p.ConnectionState(
          peerId: 'target-peer',
          multiaddrs: [circuitMultiaddr],
          direction: 'outbound',
          status: 'connected',
        ),
      ],
    );

    // R2 replacement for TC-02-01: a LAN committed claim before the stagger is
    // written-only, so the authenticated relay leg still starts and proves.
    test(
      'FDC-02 relay penalty: LAN write before the relay stagger cannot suppress '
      'the relay-live proof',
      () async {
        p2pService =
            DurableLanFakeP2PService(
                currentState: circuitOnlyState(),
                dialPeerResult: false,
              )
              ..localPeers.add('target-peer')
              // LAN acks at ~40ms — far inside kRelayLegStagger (500ms).
              ..localSendDelay = const Duration(milliseconds: 40);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'LAN write precedes relay proof',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'relay');
        expect(p2pService.localSendCallCount, 1);
        expect(p2pService.relayLiveSendCount, 1);
      },
    );

    // TC-02-01b — an authenticated direct proof before the stagger completes the
    // selector, so the later relay timer observes completion and suppresses its
    // send. Written-only evidence would not satisfy this guard.
    test(
      'FDC-02 relay penalty: a direct win within the stagger window suppresses '
      'the relay-live leg after authenticated settlement',
      () async {
        p2pService = DurableLanFakeP2PService(currentState: circuitOnlyState())
          ..localPeers.add('target-peer')
          // Local leg stays in flight; it cannot delay the direct proof.
          ..localSendDelay = const Duration(milliseconds: 2000)
          // Direct ack lands at ~400ms (inside the 500ms stagger) and is labeled
          // 'direct' by Go.
          ..sendMessageTransport = 'direct'
          ..sendMessageAcked = true
          ..discoverDelay = const Duration(milliseconds: 400);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Direct win inside the stagger suppresses relay-live',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'direct');
        await Future<void>.delayed(const Duration(milliseconds: 700));
        expect(p2pService.relayLiveSendCount, 0);
      },
    );

    // TC-02-02 — §6.2a: when LAN+direct both fail, the staggered relay-live leg
    // still races and carries (LAN-first is by priority, not suppression). Also
    // locks C4: the relay-live leg is counted in pendingCount, so the fast
    // LAN+direct double-failure cannot settle the race as failed before 500ms.
    test('FDC-02 relay penalty: when LAN+direct both fail, the staggered '
        'relay-live leg still carries', () async {
      p2pService = FakeP2PService(
        currentState: circuitOnlyState(),
        dialPeerResult: false, // direct leg fails at dial
        // C6: pin the probe tail OFF so its identical 'relay' label cannot mask
        // the remove-_tryRelayLiveSend mutation.
        probeRelayResult: RelayProbeResult.error,
        sendMessageAcked: true,
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Relay carries when LAN+direct fail',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.transport, 'relay');
      expect(p2pService.relayLiveSendCount, 1);
    });

    // TC-02-03 — §6.2b: a media payload with a live circuit skips the relay-live
    // leg. LAN+direct fail and the probe tail is pinned off, so it lands in inbox
    // custody — never the live relay socket.
    test('FDC-02 media never live-relay: media payload with a live circuit skips '
        'the relay-live leg', () async {
      const encryptedAttachment = MediaAttachment(
        id: 'att-fdc02-media',
        messageId: '',
        mime: 'image/jpeg',
        size: 1024,
        mediaType: 'image',
        downloadStatus: 'done',
        createdAt: '2026-06-26T11:00:00.000Z',
        contentHash:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        encryptionKeyBase64: 'key-1',
        encryptionNonce: 'nonce-1',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
      p2pService = FakeP2PService(
        currentState: circuitOnlyState(),
        dialPeerResult: false, // direct leg fails at dial
        probeRelayResult: RelayProbeResult.error, // probe tail off
        storeInInboxResult: true, // inbox takes custody
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'photo over a live circuit?',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        mediaAttachments: const [encryptedAttachment],
        mediaAttachmentRepo: FakeMediaAttachmentRepository(),
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // Media never traversed the live relay leg; it landed in durable custody.
      expect(p2pService.relayLiveSendCount, 0);
      expect(message!.transport, 'inbox');
      expect(message.transport, isNot('relay'));
    });

    // TC-02-04 — §6.2b: a >ceiling text payload skips the relay-live leg too.
    test('FDC-02 large payload never live-relay: a >budget text payload skips the '
        'relay-live leg', () async {
      // Encrypted envelope (jsonString.length) must exceed kLiveRelayMaxPayloadBytes
      // (96KB). PassthroughCryptoBridge carries the plaintext, so a ~200K text
      // yields a >96KB envelope.
      final bigText = 'x' * 200000;
      p2pService = FakeP2PService(
        currentState: circuitOnlyState(),
        dialPeerResult: false,
        probeRelayResult: RelayProbeResult.error,
        storeInInboxResult: true,
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: bigText,
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(p2pService.relayLiveSendCount, 0);
      expect(message!.transport, isNot('relay'));
    });

    // TC-02-05 — P0-3 latency half: a slow discover (1.8s) under the per-step
    // discover budget still delivers live 'direct' (no starvation). Preservation
    // under FDC-02's per-leg split; re-reds when the discover budget is shrunk.
    test(
      'FDC-02 independent budgets: a slow discover (1.8s) still delivers direct',
      () async {
        p2pService = FakeP2PService(
          sendMessageTransport: 'direct',
          sendMessageAcked: true,
        )..discoverDelay = const Duration(milliseconds: 1800);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Slow discover still direct',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'direct');
        expect(p2pService.probeRelayCallCount, 0);
        // FDC-03: the concurrent durable copy fires for this unknown-presence
        // send; the direct leg still wins (FDC-02's no-starvation intent holds).
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    // TC-02-06 — per-leg budget isolation: a discover overrunning its OWN budget
    // fails fast and dial/send are never reached. Re-reds when the discover
    // budget is widened to the aggregate ceiling.
    test('FDC-02 per-leg budget cap: a discover that overruns its budget fails '
        'fast, dial/send untouched', () async {
      p2pService = FakeP2PService(
        probeRelayResult: RelayProbeResult.noReservation,
        storeInInboxResult: true,
      )..discoverDelay = const Duration(milliseconds: 2100); // > 2000 budget

      final sw = Stopwatch()..start();
      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Discover overruns its budget',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );
      sw.stop();

      expect(result, SendChatMessageResult.success);
      // Discover timed out at its budget → dial/send never ran.
      expect(p2pService.discoverCallCount, 1);
      expect(p2pService.dialCallCount, 0);
      expect(p2pService.sendCallCount, 0);
      // FDC-03: the probe tail is gone — the eligible peer_not_found takes
      // durable custody via the concurrent inbox; bounded well under the 6s
      // aggregate.
      expect(p2pService.probeRelayCallCount, 0);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    // R2 replacement for TC-02-07: once scheduled, the first authenticated
    // explicit ACK settles. A later transport label cannot replace it.
    test(
      'FDC-02 proof: relay-live ACK settles before a later direct ACK',
      () async {
        p2pService = FakeP2PService(
          currentState: circuitOnlyState(),
          // Direct leg's send is labeled 'direct' by Go (a direct conn opened);
          // the relay-live leg labels 'relay' (its own circuit send) via
          // relayLiveSendTransport's default.
          sendMessageTransport: 'direct',
          sendMessageAcked: true,
          // Slow discover delays the direct ACK until after the existing 500ms
          // relay scheduling stagger, so relay proof arrives first.
        )..discoverDelay = const Duration(milliseconds: 600);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'First relay proof settles while direct remains in flight',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'relay');
        expect(p2pService.relayLiveSendCount, 1);
      },
    );

    // Learned WebSocket-local adds no winner delay: the first authenticated
    // relay proof still settles while the slower direct attempt is in flight.
    test(
      'FDC-02 proof with learned local: relay ACK settles before direct',
      () async {
        p2pService =
            FakeP2PService(
                currentState: circuitOnlyState(),
                sendMessageTransport: 'direct', // direct leg labels 'direct'
                sendMessageAcked: true,
              )
              // Learned local is ineligible for an authority short-circuit.
              ..lastKnownGoodTransportResult = 'local'
              ..localSendResult = false
              // Slow discover delays the direct ack to ~600ms (> the 500ms stagger),
              // so the relay-live explicit ACK resolves first.
              ..discoverDelay = const Duration(milliseconds: 600);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Relay proof settles while direct remains in flight',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'relay');
        expect(p2pService.relayLiveSendCount, 1);
      },
    );

    // TC-02-08 — §12 constant alignment: the stagger/tail ordering and the
    // per-leg budgets remain bounded by the aggregate ceiling. Settlement
    // behavior is locked by TC-02-07/TC-02-01/TC-02-10.
    test(
      'FDC-02 scheduling invariant: stagger/tail ordering + bounded per-leg budgets',
      () {
        expect(kRelayLegStagger > kPublicAddrTail, isTrue);
        expect(kPublicAddrTail > kPrivateAddrTail, isTrue);
        // Worst-case serial sum of the per-leg budgets stays within the FDC-01
        // aggregate ceiling.
        expect(
          kDirectDiscoverBudget + kDirectDialBudget + kDirectSendBudget,
          lessThanOrEqualTo(interactiveDirectAggregateBudget),
        );
        // Live-relay payload ceiling sits under the 128KB circuit-v2 cap.
        expect(kLiveRelayMaxPayloadBytes, lessThan(128 * 1024));
      },
    );

    // R2 replacement for TC-02-09: LAN writes and relay proof share one message
    // ID; the authenticated relay settles and sender persistence remains one row.
    test(
      'FDC-02 proof migration: LAN write plus relay proof persists one row',
      () async {
        // dialPeerResult:false isolates the stagger as the load-bearing guard
        // (see TC-02-01) so the kRelayLegStagger=0 mutation re-reds this lock.
        p2pService =
            DurableLanFakeP2PService(
                currentState: circuitOnlyState(),
                dialPeerResult: false,
              )
              ..localPeers.add('target-peer')
              ..localSendDelay = const Duration(milliseconds: 40);
        const fixedId = 'msg-fdc02-dedup-001';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'One row, relay proves delivery',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: fixedId,
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'relay');
        expect(messageRepo.saved, hasLength(1));
        expect(messageRepo.saved.single.id, fixedId);
        expect(p2pService.relayLiveSendCount, 1);
      },
    );

    // R2: an unauthenticated LAN claim cannot replace an authenticated libp2p
    // proof. Here Go labels the ordinary circuit send as relay before the
    // separate staggered relay-live leg needs to start.
    test(
      'FDC-02 R2: LAN claim with a live circuit yields libp2p proof',
      () async {
        p2pService = DurableLanFakeP2PService(currentState: circuitOnlyState())
          ..localPeers.add('target-peer')
          ..localSendDelay = const Duration(milliseconds: 40);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Authenticated circuit proves delivery',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'relay');
        expect(p2pService.localSendCallCount, 1);
        expect(p2pService.relayLiveSendCount, 0);
      },
    );
  });

  // ─── 187 — keepalive-informed send: skip the doomed direct dial ───────────
  //
  // When the 183 keepalive has latched the ACTIVE 1:1 peer as dropped, a send to
  // that peer must NOT burn the direct discover/dial WAN leg — the concurrent
  // durable inbox has already secured custody. The direct leg stays PRESENT in
  // direct race slot (Option A: leg ordering/count untouched) but
  // short-circuits at its top, emitting SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP.
  // At the unit tier the discover/dial spy counts (discoverCallCount /
  // dialCallCount) are the leg-ran discriminator (the fake doesn't emit the
  // native P2P_SERVICE_DISCOVER_PEER_BEGIN / DIAL events — that's the device
  // tier, TC-187-32).
  group('187 — skip doomed direct dial for a latched-dropped active peer', () {
    // A fake for the primary skip path: unknown-presence (not connected/local),
    // the target latched-dropped, LAN misses (useNullDiscover + no localPeers),
    // durable inbox secures custody (storeInInboxResult true).
    FakeP2PService droppedActivePeerFake() =>
        FakeP2PService(useNullDiscover: true, storeInInboxResult: true)
          ..setPeerDropSuspected('target-peer', true);

    bool hasEvent(List<Map<String, dynamic>> events, String name) =>
        events.any((e) => e['event'] == name);

    // TC-187-01 — the direct discover/dial leg is skipped for a latched-dropped
    // active peer. Mutation: revert the _tryDirectSend short-circuit → discover/
    // dial fire again (discoverCallCount/dialCallCount 1) → red.
    test(
      'TC-187-01: latched-dropped active peer → direct discover/dial skipped',
      () async {
        p2pService = droppedActivePeerFake();

        SendChatMessageResult? result;
        ConversationMessage? message;
        final events = await captureFlowEvents(() async {
          final r = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'to a dropped peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );
          result = r.$1;
          message = r.$2;
        });

        // The distinct discriminator proves the skip happened for the KEEPALIVE-
        // DROP reason (not presence, not a budget timeout).
        expect(
          hasEvent(events, 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP'),
          isTrue,
        );
        // The doomed WAN direct leg never discovered or dialed.
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
        expect(p2pService.sendCallCount, 0);
        // No doomed relay probe either (the skip is not relay-probe-eligible).
        expect(p2pService.probeRelayCallCount, 0);
        // Custody still landed via the concurrent durable inbox.
        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'inboxed');
      },
    );

    // TC-187-02 — the skip never trades away durability: the concurrent inbox
    // still fires and custody is still confirmed. Mutation: make the skip also
    // suppress the concurrent inbox → CUSTODY_CONFIRMED gone → red.
    test('TC-187-02: skip still secures concurrent-inbox custody', () async {
      p2pService = droppedActivePeerFake();

      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'custody must survive the skip',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
      });

      expect(hasEvent(events, 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN'), isTrue);
      expect(hasEvent(events, 'CHAT_MSG_SEND_CUSTODY_CONFIRMED'), isTrue);
      expect(p2pService.storeInInboxCallCount, greaterThanOrEqualTo(1));
      expect(
        messageRepo.ordinarySettlementCalls.any(
          (settlement) => settlement.status == 'inboxed',
        ),
        isTrue,
        reason:
            'the mid-send custody bump must still advance the row to inboxed',
      );
    });

    // TC-187-03 — a skipped send lands a RETRIABLE 'inboxed' row (the self-
    // healing lane), never a terminal 'failed' and never a false 'delivered'.
    // Mutation: skip returns a terminal failed result → row not retriable → red.
    // (Full on-wire recovery to delivered = the device tier, TC-187-32.)
    test(
      "TC-187-03: skipped send lands retriable 'inboxed' (not failed/delivered)",
      () async {
        p2pService = droppedActivePeerFake();

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'retriable inbox row',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(
          message!.status,
          'inboxed',
        ); // retriable, NOT 'failed', NOT 'delivered'
        expect(message.transport, 'inbox');
      },
    );

    // TC-187-10 — no over-reach: a REACHABLE active peer (signal clear) runs the
    // direct leg with its FULL budget. Mutation: make the skip fire regardless of
    // the signal → discover/dial skipped → red (over-reach caught).
    test(
      'TC-187-10: reachable active peer (signal false) → direct leg runs full',
      () async {
        p2pService = FakeP2PService(
          storeInInboxResult: true,
          sendMessageAcked: true,
        ); // signal NOT set → isPeerSuspectedDropped false

        SendChatMessageResult? result;
        ConversationMessage? message;
        final events = await captureFlowEvents(() async {
          final r = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'reachable peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );
          result = r.$1;
          message = r.$2;
        });

        expect(
          hasEvent(events, 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP'),
          isFalse,
        );
        expect(p2pService.discoverCallCount, 1); // direct leg ran full budget
        expect(p2pService.dialCallCount, 1);
        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'direct');
      },
    );

    // TC-187-11 — FDC-01/02 preserved: a peer that was never marked (unknown
    // liveness) runs the direct leg with the FULL budget, even when a DIFFERENT
    // peer is latched-dropped. Mutation: signal not keyed by peer → the send
    // skips → red.
    test(
      'TC-187-11: unknown / non-active peer → direct leg runs full budget',
      () async {
        p2pService = FakeP2PService(
          storeInInboxResult: true,
          sendMessageAcked: true,
        )..setPeerDropSuspected('some-other-peer', true); // a DIFFERENT peer

        final events = await captureFlowEvents(() async {
          await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer', // never marked
            text: 'unknown-liveness peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );
        });

        expect(
          hasEvent(events, 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP'),
          isFalse,
        );
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.dialCallCount, 1);
      },
    );

    // TC-187-20 — a reconnected peer is never penalized: even with the drop mark
    // still set, a peer with a live DIRECT connection takes the reuse fast path
    // (:527-540) and the skip is never evaluated. Mutation: drop the reuse
    // precedence → the marked peer would fall into the race and skip → red.
    test(
      'TC-187-20: reconnected (connected) peer → reuse path, never skip',
      () async {
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/127.0.0.1/tcp/4001'], // DIRECT (not circuit)
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
        )..setPeerDropSuspected('target-peer', true); // stale mark still set

        SendChatMessageResult? result;
        ConversationMessage? message;
        final events = await captureFlowEvents(() async {
          final r = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'reconnected — reuse me',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );
          result = r.$1;
          message = r.$2;
        });

        expect(hasEvent(events, 'CHAT_MSG_SEND_REUSE_CONNECTION'), isTrue);
        expect(
          hasEvent(events, 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP'),
          isFalse,
        );
        expect(p2pService.sendCallCount, 1); // reuse sent
        expect(
          p2pService.discoverCallCount,
          0,
        ); // never discovered (reuse, not skip)
        expect(p2pService.dialCallCount, 0);
        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'direct');
      },
    );

    // TC-187-21 — normalized-key match: a mark made against a key carrying
    // whitespace (as the tracker's normalizeActiveKey would strip) matches the
    // raw send target. Mutation: raw `==` instead of normalizeActiveKey → the
    // padded mark no longer matches → no skip → discover runs → red. Locks the
    // REFUTED naive-`targetPeerId == activePeerId` finding.
    test(
      'TC-187-21: normalized-key match (raw target normalizes to the marked key)',
      () async {
        p2pService = FakeP2PService(
          useNullDiscover: true,
          storeInInboxResult: true,
        )..setPeerDropSuspected('  target-peer  ', true); // padded → normalizes

        final events = await captureFlowEvents(() async {
          await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer', // raw form matches the normalized mark
            text: 'normalized match',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );
        });

        expect(
          hasEvent(events, 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP'),
          isTrue,
          reason:
              'a normalized-key match must still skip the doomed direct dial',
        );
        expect(p2pService.discoverCallCount, 0);
        // A genuinely different peer must NOT be considered dropped (keyed match).
        expect(p2pService.isPeerSuspectedDropped('different-peer'), isFalse);
      },
    );

    // TC-187-30 — never falsely delivered: the skip relies on the concurrent
    // inbox + a future receiver receipt; no row is marked 'delivered' without a
    // receipt. Mutation: skip mints delivered → red.
    test('TC-187-30: skipped send is never falsely marked delivered', () async {
      p2pService = droppedActivePeerFake();

      final (_, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'no false delivered',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(message!.status, isNot('delivered'));
      expect(
        messageRepo.statusUpdates.any((u) => u.$2 == 'delivered'),
        isFalse,
        reason: 'no delivered status may be minted without a receiver receipt',
      );
      expect(
        p2pService.recordSuccessfulTransportCallCount,
        0,
        reason: 'a skipped (undelivered) send records no live transport',
      );
    });

    // TC-187-31 — one relay write: skipping the direct leg does not cause a
    // second inbox store (the concurrentInbox tail short-circuit still holds).
    // Mutation: break the concurrent-inbox tail short-circuit → 2 stores → red.
    test('TC-187-31: skip does not cause a double relay write', () async {
      p2pService = droppedActivePeerFake();

      await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'exactly one store',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(p2pService.storeInInboxCallCount, 1);
    });
  });

  group('R3 cross-layer outgoing deadline', () {
    test(
      'R3 committed ACK window is shared by reuse sticky cold direct and live relay',
      () {
        const preparationDelay = Duration(milliseconds: 200);
        const committedAckDelay = Duration(milliseconds: 2200);
        const directConnection = p2p.ConnectionState(
          peerId: 'target-peer',
          multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
          direction: 'outbound',
          status: 'connected',
        );
        const relayConnection = p2p.ConnectionState(
          peerId: 'target-peer',
          multiaddrs: ['/ip4/10.0.0.8/tcp/4001/p2p/relay/p2p-circuit'],
          direction: 'outbound',
          status: 'connected',
        );
        final rows =
            <
              ({
                String name,
                NodeState state,
                String? learned,
                String? transport,
                bool liveRelay,
                String expectedTransport,
              })
            >[
              (
                name: 'reuse',
                state: const NodeState(
                  isStarted: true,
                  connections: [directConnection],
                ),
                learned: null,
                transport: 'direct',
                liveRelay: false,
                expectedTransport: 'direct',
              ),
              (
                name: 'sticky-direct',
                state: const NodeState(isStarted: true),
                learned: 'direct',
                transport: 'direct',
                liveRelay: false,
                expectedTransport: 'direct',
              ),
              (
                name: 'sticky-relay',
                state: const NodeState(isStarted: true),
                learned: 'relay',
                transport: 'relay',
                liveRelay: false,
                expectedTransport: 'relay',
              ),
              (
                name: 'cold-direct',
                state: const NodeState(isStarted: true),
                learned: null,
                transport: 'direct',
                liveRelay: false,
                expectedTransport: 'direct',
              ),
              (
                name: 'live-relay',
                state: const NodeState(
                  isStarted: true,
                  connections: [relayConnection],
                ),
                learned: null,
                transport: 'direct',
                liveRelay: true,
                expectedTransport: 'relay',
              ),
            ];

        for (final row in rows) {
          fakeAsync((async) {
            final service = _R3DeadlineP2PService(
              currentState: row.state,
              sendMessageTransport: row.transport,
            )..lastKnownGoodTransportResult = row.learned;
            service.scriptedSendDelays.addAll(
              row.liveRelay
                  ? const [Duration(seconds: 10), committedAckDelay]
                  : const [committedAckDelay],
            );
            (SendChatMessageResult, ConversationMessage?)? outcome;

            sendChatMessage(
              p2pService: service,
              messageRepo: FakeMessageRepository(),
              targetPeerId: 'target-peer',
              text: 'R3 ${row.name}',
              senderPeerId: 'my-peer',
              senderUsername: 'Me',
              bridge: _R3DelayedCryptoBridge(preparationDelay),
            ).then((value) => outcome = value);
            async.flushMicrotasks();

            async.elapse(preparationDelay);
            async.flushMicrotasks();
            if (row.liveRelay) {
              async.elapse(kRelayLegStagger);
              async.flushMicrotasks();
            }
            async.elapse(committedAckDelay);
            async.flushMicrotasks();

            expect(outcome, isNotNull, reason: row.name);
            expect(outcome!.$1, SendChatMessageResult.success);
            expect(outcome!.$2!.status, 'delivered', reason: row.name);
            expect(
              outcome!.$2!.transport,
              row.expectedTransport,
              reason: row.name,
            );
            expect(
              service.sendTimeouts,
              row.liveRelay ? <int?>[5300, 4800] : <int?>[5300],
              reason: '${row.name} must allocate from the original T0',
            );
          });
        }
      },
    );

    test('R3 T0 includes envelope preparation before live send admission', () {
      fakeAsync((async) {
        const directConnection = p2p.ConnectionState(
          peerId: 'target-peer',
          multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
          direction: 'outbound',
          status: 'connected',
        );
        final service = _R3DeadlineP2PService(
          currentState: const NodeState(
            isStarted: true,
            connections: [directConnection],
          ),
          storeInInboxResult: true,
        );
        (SendChatMessageResult, ConversationMessage?)? outcome;

        sendChatMessage(
          p2pService: service,
          messageRepo: FakeMessageRepository(),
          targetPeerId: 'target-peer',
          text: 'preparation consumes ACK reserve',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: _R3DelayedCryptoBridge(const Duration(milliseconds: 2500)),
        ).then((value) => outcome = value);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 2500));
        async.flushMicrotasks();

        expect(outcome, isNotNull);
        expect(outcome!.$2!.status, 'inboxed');
        expect(service.sendTimeouts, isEmpty);
        expect(service.sendCallCount, 0);
      });
    });

    test('R3 failed reuse discovery and dial consume one T0 deadline', () {
      fakeAsync((async) {
        const directConnection = p2p.ConnectionState(
          peerId: 'target-peer',
          multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
          direction: 'outbound',
          status: 'connected',
        );
        final service =
            _R3DeadlineP2PService(
                currentState: const NodeState(
                  isStarted: true,
                  connections: [directConnection],
                ),
                sendMessageTransport: 'direct',
              )
              ..scriptedDiscoverDelay = const Duration(milliseconds: 500)
              ..scriptedDialDelay = const Duration(milliseconds: 500)
              ..scriptedSendDelays.addAll(const [
                Duration(milliseconds: 250),
                Duration(milliseconds: 250),
              ])
              ..queuedSendMessageResults.addAll([
                Future<SendMessageResult>.value(
                  const SendMessageResult(sent: false),
                ),
                Future<SendMessageResult>.value(
                  const SendMessageResult(
                    sent: true,
                    acked: true,
                    transport: 'direct',
                  ),
                ),
              ]);
        (SendChatMessageResult, ConversationMessage?)? outcome;

        sendChatMessage(
          p2pService: service,
          messageRepo: FakeMessageRepository(),
          targetPeerId: 'target-peer',
          text: 'one T0 through every phase',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        ).then((value) => outcome = value);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1500));
        async.flushMicrotasks();

        expect(outcome, isNotNull);
        expect(outcome!.$2!.status, 'delivered');
        expect(service.sendTimeouts, <int?>[5500, 4250]);
        expect(service.discoverTimeouts, <int?>[2000]);
        expect(service.dialTimeouts, <int?>[1500]);
      });

      fakeAsync((async) {
        const directConnection = p2p.ConnectionState(
          peerId: 'target-peer',
          multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
          direction: 'outbound',
          status: 'connected',
        );
        final service = _R3DeadlineP2PService(
          currentState: const NodeState(
            isStarted: true,
            connections: [directConnection],
          ),
          storeInInboxResult: true,
        );
        (SendChatMessageResult, ConversationMessage?)? outcome;
        const preparation = Duration(microseconds: 5499001);

        sendChatMessage(
          p2pService: service,
          messageRepo: FakeMessageRepository(),
          targetPeerId: 'target-peer',
          text: 'floored zero phase is suppressed',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: _R3DelayedCryptoBridge(preparation),
        ).then((value) => outcome = value);
        async.flushMicrotasks();
        async.elapse(preparation);
        async.flushMicrotasks();

        expect(outcome, isNotNull);
        expect(outcome!.$2!.status, 'inboxed');
        expect(service.sendTimeouts, isEmpty);
        expect(service.discoverTimeouts, isEmpty);
        expect(service.dialTimeouts, isEmpty);
      });
    });
  });
}

/// P2P service where discover/dial succeed but storeInInbox throws.
/// Used to test inbox fallback error handling.
class _ThrowOnInboxP2PService implements P2PService {
  final bool p2pSucceeds;

  _ThrowOnInboxP2PService({this.p2pSucceeds = false});

  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async => p2pSucceeds;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => SendMessageResult(
    sent: p2pSucceeds,
    acked: p2pSucceeds,
    reply: p2pSucceeds ? 'received: ok' : null,
  );

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      p2pSucceeds
      ? const DiscoveredPeer(
          id: 'target-peer',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        )
      : null;

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async => p2pSucceeds;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async => throw Exception('Inbox store exploded');

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
  bool isLocalPeer(String peerId) => false;

  @override
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async => false;

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
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

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
    bool enc = false,
    String? encScheme,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}

/// P2P service that discovers and dials successfully but throws on send.
class _ThrowOnSendP2PService implements P2PService {
  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async =>
      throw Exception('Send exploded');

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => throw Exception('Send exploded');

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      const DiscoveredPeer(
        id: 'target-peer',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      );

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async => true;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async => false;

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
  bool isLocalPeer(String peerId) => false;

  @override
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async => false;

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
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

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
    bool enc = false,
    String? encScheme,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}

/// P2P service where discover fails on first attempt, succeeds on subsequent.
class _FlakyDiscoverP2PService implements P2PService {
  int discoverCallCount = 0;

  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async =>
      const SendMessageResult(sent: true, acked: true, reply: 'received: ok');

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    discoverCallCount++;
    if (discoverCallCount == 1) return null;
    return const DiscoveredPeer(
      id: 'target-peer',
      addresses: ['/ip4/127.0.0.1/tcp/4001'],
    );
  }

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async => true;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async => false;

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
  bool isLocalPeer(String peerId) => false;

  @override
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async => false;

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
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

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
    bool enc = false,
    String? encScheme,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}

/// P2P service where local send is slow but direct path succeeds fast.
class _SlowLocalFastDirectP2PService implements P2PService {
  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

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
      const DiscoveredPeer(
        id: 'target-peer',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      );

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async => true;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async => false;

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
  bool isLocalPeer(String peerId) => true;

  @override
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async => true;

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    // Simulate slow local send (3 seconds)
    await Future.delayed(const Duration(seconds: 3));
    return true;
  }

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

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
    bool enc = false,
    String? encScheme,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}
