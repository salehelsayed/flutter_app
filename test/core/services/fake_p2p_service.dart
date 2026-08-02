import 'dart:async';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

/// In-memory [P2PService] for tests.
///
/// Configurable return values, tracks call counts and last arguments.
class FakeP2PService
    implements P2PService, ReadinessProofRecorder, P2PFullInboxDrain {
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
  DirectInboxDrainOutcome fullInboxDrainOutcome;
  String? recoveryMethod;
  Future<void> Function()? onDrainOfflineInbox;

  /// Optional hook awaited INSIDE [performImmediateHealthCheck], after the call
  /// count is incremented. Lets a test hold the resume re-prime open (e.g. await
  /// a Completer the test never completes) so it can observe the inbox drain
  /// firing CONCURRENTLY while the re-prime is still pending (FDC-05 TC-05-02),
  /// or record re-prime ordering relative to bridge health (TC-05-06).
  Future<void> Function()? onPerformImmediateHealthCheck;

  /// Ordered log of all sendMessage calls for multi-send assertions.
  final List<({String peerId, String content})> sentMessageLog = [];

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
  int drainOfflineInboxFullyCallCount = 0;
  int markResumeStartedCallCount = 0;
  int clearResumeStartedCallCount = 0;
  int noteTransportSessionResetCallCount = 0;
  int recordSuccessfulSendProofCallCount = 0;
  String? lastReadinessTrigger;
  String? lastReadinessProofSource;
  String? lastReadinessSendPath;
  bool hasPendingResumeStartedValue = false;

  // Last arguments
  String? lastStartNodePrivateKey;
  String? lastStartNodePeerId;
  String? lastSendMessagePeerId;
  String? lastSendMessageContent;
  String? lastDiscoverPeerId;
  String? lastDialPeerId;
  String? lastStoreInInboxPeerId;
  String? lastStoreInInboxMessage;
  int? lastStoreInInboxTimeoutMs;

  /// FDC-S4: ordered log of every storeInInbox deposit (recipient + payload +
  /// per-call timeout) so the pause-flush tests can assert newest-first
  /// ordering, the per-message budget, and the cap.
  final List<({String toPeerId, String message, int? timeoutMs})>
  storeInInboxLog = [];

  /// FDC-S4: per-call override for storeInInbox. When set, its result is
  /// returned (and it may advance a virtual clock or throw) instead of the
  /// static [storeInInboxResult] — lets a test make specific recipients
  /// succeed/fail or simulate a slow/hung deposit deterministically. Mirrors
  /// the full storeInInbox signature (including [timeoutMs]) so a test can also
  /// branch on the per-message budget.
  Future<bool> Function(String toPeerId, String message, {int? timeoutMs})?
  onStoreInInbox;

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
    this.fullInboxDrainOutcome = const DirectInboxDrainOutcome(
      isSuccessful: true,
      hasMore: false,
    ),
    this.recoveryMethod,
    this.onDrainOfflineInbox,
  }) : _currentState = initialState ?? NodeState.stopped,
       sendMessageWithReplyResult =
           sendMessageWithReplyResult ??
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

  // FDC-18: benign send-leg delay so a test can make the live `sendMessage`
  // resolve AFTER the concurrent inbox deposit has started (the FDC-18-02/R2
  // live-win-still-deposits race). Default Duration.zero keeps every existing
  // test green.
  Duration sendMessageDelay = Duration.zero;

  // FDC-18: explicit override for `isConnectedToPeer` (the unit fake has no
  // `connectedPeers` set — that lives in the integration fake). Default false
  // preserves the historical bare-`false` behaviour; a test flips this true to
  // exercise the confirmed-path single-path guard (FDC-18-03/R3).
  bool isConnectedToPeerResult = false;

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    if (sendMessageDelay > Duration.zero) {
      await Future.delayed(sendMessageDelay);
    }
    sendMessageCallCount++;
    lastSendMessagePeerId = peerId;
    lastSendMessageContent = message;
    sentMessageLog.add((peerId: peerId, content: message));
    return sendMessageResult;
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendMessageWithReplyCallCount++;
    lastSendMessagePeerId = peerId;
    lastSendMessageContent = message;
    return sendMessageWithReplyResult;
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    discoverPeerCallCount++;
    lastDiscoverPeerId = peerId;
    return discoverPeerResult;
  }

  // FDC-04/FDC-11: warmPeer call tracking (conformance stub for the eager
  // warm-dial interface; `preferQuic` is Go-inert today).
  int warmPeerCallCount = 0;
  String? lastWarmPeerId;

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async {
    dialPeerCallCount++;
    lastDialPeerId = peerId;
    return dialPeerResult;
  }

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {
    warmPeerCallCount++;
    lastWarmPeerId = peerId;
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    storeInInboxCallCount++;
    lastStoreInInboxPeerId = toPeerId;
    lastStoreInInboxMessage = message;
    lastStoreInInboxTimeoutMs = timeoutMs;
    storeInInboxLog.add((
      toPeerId: toPeerId,
      message: message,
      timeoutMs: timeoutMs,
    ));
    final hook = onStoreInInbox;
    if (hook != null) return hook(toPeerId, message, timeoutMs: timeoutMs);
    return storeInInboxResult;
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async {
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
    await onPerformImmediateHealthCheck?.call();
  }

  @override
  Future<void> drainOfflineInbox() async {
    drainOfflineInboxCallCount++;
    if (throwOnDrainInbox) {
      throw Exception('FakeP2PService: drain inbox error');
    }
    await onDrainOfflineInbox?.call();
  }

  @override
  Future<DirectInboxDrainOutcome> drainOfflineInboxFully() async {
    drainOfflineInboxFullyCallCount++;
    await drainOfflineInbox();
    return fullInboxDrainOutcome;
  }

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => isConnectedToPeerResult;

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async => false;

  // NET-REL-05 P3 (sticky transport): configurable learned-transport memory.
  String? lastKnownGoodTransportResult;
  String? lastRecordedTransport;
  int recordSuccessfulTransportCallCount = 0;

  @override
  String? lastKnownGoodTransport(String peerId) => lastKnownGoodTransportResult;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {
    recordSuccessfulTransportCallCount++;
    lastRecordedTransport = transport;
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
    return false;
  }

  // Configurable result for sendLocalMedia
  bool sendLocalMediaResult = false;
  int sendLocalMediaCallCount = 0;
  String? lastSendLocalMediaPeerId;
  String? lastSendLocalMediaFilePath;
  String? lastSendLocalMediaMime;
  bool? lastSendLocalMediaEnc;
  String? lastSendLocalMediaEncScheme;

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
  }) async {
    sendLocalMediaCallCount++;
    lastSendLocalMediaPeerId = peerId;
    lastSendLocalMediaFilePath = filePath;
    lastSendLocalMediaMime = mime;
    lastSendLocalMediaEnc = enc;
    lastSendLocalMediaEncScheme = encScheme;
    return sendLocalMediaResult;
  }

  @override
  String? get lastRecoveryMethod => recoveryMethod;

  @override
  void markResumeStarted() {
    markResumeStartedCallCount++;
    hasPendingResumeStartedValue = true;
  }

  @override
  void clearResumeStarted() {
    clearResumeStartedCallCount++;
    hasPendingResumeStartedValue = false;
  }

  @override
  bool get hasPendingResumeStarted => hasPendingResumeStartedValue;

  @override
  void noteTransportSessionReset({required String trigger}) {
    noteTransportSessionResetCallCount++;
    lastReadinessTrigger = trigger;
  }

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
  void dispose() {
    _stateController.close();
    _messageController.close();
  }
}
