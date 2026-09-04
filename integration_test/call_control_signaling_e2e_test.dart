import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_signaling_runtime.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'direct failure gains mailbox custody and duplicate paths converge once',
    (_) async {
      final harness = await _TwoPeerCallHarness.create();
      addTearDown(harness.dispose);

      final call = await harness.inviteWithDirectFailure();
      expect(call.transport.directAccepted, isFalse);
      expect(call.transport.mailboxStored, isTrue);
      expect(harness.callerState, CallState.inviting);
      expect(harness.callerMailboxCustodyConfirmed, isTrue);
      expect(harness.mailboxWakeRequests, 1);

      await harness.wakeCalleeAndDrain();
      expect(harness.calleeState, CallState.ringing);
      expect(harness.callPresentationRequests, 1);
      expect(harness.mailboxAcknowledgements, 1);

      await harness.replayLastMailboxFrameDirectly();
      await harness.wakeCalleeAndDrain();
      expect(harness.calleeState, CallState.ringing);
      expect(harness.callPresentationRequests, 1);

      await harness.answerAndConverge(call);
      expect(harness.callerState, CallState.accepted);
      expect(harness.calleeState, CallState.accepted);

      await harness.enterMediaPlaceholderBoundary(call);
      expect(harness.callerState, CallState.connected);
      expect(harness.calleeState, CallState.connected);

      await harness.terminateAgainstLateAnswer(call);
      expect(harness.callerTerminalReason, CallEndReason.localHangup);
      expect(harness.calleeTerminalReason, CallEndReason.remoteHangup);
      expect(harness.callerState, CallState.ended);
      expect(harness.calleeState, CallState.ended);
      expect(harness.historyStatus(call), CallHistoryStatus.completed);
      harness.expectExactlyOnce(call);
      harness.expectOrdinaryPathsUnused();
    },
  );

  testWidgets(
    'decline cancel and expiry races preserve terminal and history precedence',
    (_) async {
      final harness = await _TwoPeerCallHarness.create();
      addTearDown(harness.dispose);

      final declined = await harness.declineJourney();
      expect(harness.historyStatus(declined), CallHistoryStatus.declined);
      harness.expectExactlyOnce(declined);

      final cancelled = await harness.cancelAgainstAnswerJourney();
      expect(harness.historyStatus(cancelled), CallHistoryStatus.cancelled);
      harness.expectExactlyOnce(cancelled);

      final expired = await harness.expiryJourney();
      expect(harness.historyStatus(expired), CallHistoryStatus.missed);
      harness.expectExactlyOnce(expired);

      await harness.replayAllTerminalFrames();
      harness.expectExactlyOnce(declined);
      harness.expectExactlyOnce(cancelled);
      harness.expectExactlyOnce(expired);
      harness.expectOrdinaryPathsUnused();
    },
  );
}

const int _initialNowMs = 1_788_067_200_000;
const Duration _signalLifetime = Duration(seconds: 45);

final class _PathCounters {
  int callRouterFrames = 0;
  int ordinaryRouterDeliveries = 0;
  int genericOutboxWrites = 0;
  int genericRetrierSchedules = 0;
  int ordinaryNotificationRequests = 0;
  int dedicatedMailboxStores = 0;
  int dedicatedMailboxRetrieves = 0;
  int dedicatedMailboxAcks = 0;
  int mailboxWakeRequests = 0;
  int callPresentationRequests = 0;
  int callDismissalRequests = 0;

  void recordOrdinaryRouterDelivery() {
    ordinaryRouterDeliveries++;
    ordinaryNotificationRequests++;
  }

  void recordOrdinaryOutboxWrite() {
    genericOutboxWrites++;
    genericRetrierSchedules++;
  }
}

final class _DeterministicCrypto implements CallEnvelopeCrypto {
  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async => CallCiphertext(
    kem: base64Encode(utf8.encode('kem:$recipientMlKemPublicKey')),
    ciphertext: base64Encode(utf8.encode(plaintext)),
    nonce: base64Encode(utf8.encode('deterministic-nonce')),
  );

  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) async => utf8.decode(base64Decode(ciphertext.ciphertext));

  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) async =>
      base64Encode(utf8.encode('$senderSigningPrivateKey:$canonicalData'));

  @override
  Future<bool> verify({
    required String senderSigningPublicKey,
    required String canonicalData,
    required String signature,
  }) async =>
      signature ==
      base64Encode(utf8.encode('$senderSigningPublicKey:$canonicalData'));
}

final class _MailboxFrame {
  const _MailboxFrame({
    required this.senderDevicePeerId,
    required this.recipientDevicePeerId,
    required this.callHandle,
    required this.messageId,
    required this.envelopeJson,
    required this.receiptAtMs,
    required this.expiresAtMs,
  });

  final String senderDevicePeerId;
  final String recipientDevicePeerId;
  final String callHandle;
  final String messageId;
  final String envelopeJson;
  final int receiptAtMs;
  final int expiresAtMs;

  Map<String, Object?> toBridgeMap() => <String, Object?>{
    'callHandle': callHandle,
    'messageId': messageId,
    'senderPeerId': senderDevicePeerId,
    'recipientDevicePeerId': recipientDevicePeerId,
    'envelope': envelopeJson,
    'receiptAtMs': receiptAtMs,
    'expiresAtMs': expiresAtMs,
  };
}

final class _MailboxFixture {
  _MailboxFixture(this.counters, this.nowMs);

  final _PathCounters counters;
  final int Function() nowMs;
  final List<_MailboxFrame> _events = <_MailboxFrame>[];
  _MailboxFrame? lastStored;

  Future<String> invoke(String localDevicePeerId, String rawRequest) async {
    final request = jsonDecode(rawRequest) as Map<String, dynamic>;
    final command = request['cmd'] as String?;
    final payload = Map<String, dynamic>.from(
      request['payload'] as Map? ?? const <String, Object?>{},
    );
    final response = switch (command) {
      callStoreV1BridgeCommand => _store(localDevicePeerId, payload),
      callRetrieveV1BridgeCommand => _retrieve(localDevicePeerId, payload),
      callAckV1BridgeCommand => _ack(localDevicePeerId, payload),
      callCancelV1BridgeCommand => _cancel(payload),
      _ => _ordinaryBridgePath(command),
    };
    return jsonEncode(response);
  }

  Map<String, Object?> _store(
    String senderDevicePeerId,
    Map<String, dynamic> payload,
  ) {
    counters.dedicatedMailboxStores++;
    counters.mailboxWakeRequests++;
    final recipient = payload['toPeerId']! as String;
    final handle = payload['callHandle']! as String;
    final messageId = payload['messageId']! as String;
    final duplicate = _events.any(
      (event) =>
          event.recipientDevicePeerId == recipient &&
          event.callHandle == handle &&
          event.messageId == messageId,
    );
    final frame = _MailboxFrame(
      senderDevicePeerId: senderDevicePeerId,
      recipientDevicePeerId: recipient,
      callHandle: handle,
      messageId: messageId,
      envelopeJson: payload['envelope']! as String,
      receiptAtMs: nowMs(),
      expiresAtMs: payload['expiresAtMs']! as int,
    );
    if (!duplicate) _events.add(frame);
    lastStored = frame;
    final sameHandle = _events.where(
      (event) =>
          event.recipientDevicePeerId == recipient &&
          event.callHandle == handle,
    );
    return <String, Object?>{
      'ok': true,
      'storeStatus': duplicate ? 'duplicate' : 'stored',
      'receiptAtMs': frame.receiptAtMs,
      'expiresAtMs': frame.expiresAtMs,
      'eventCount': sameHandle.length,
      'totalBytes': sameHandle.fold<int>(
        0,
        (total, event) => total + utf8.encode(event.envelopeJson).length,
      ),
      'pendingHandles': _events
          .where((event) => event.recipientDevicePeerId == recipient)
          .map((event) => event.callHandle)
          .toSet()
          .length,
    };
  }

  Map<String, Object?> _retrieve(
    String recipientDevicePeerId,
    Map<String, dynamic> payload,
  ) {
    counters.dedicatedMailboxRetrieves++;
    final callHandle = payload['callHandle'] as String?;
    final limit = payload['limit']! as int;
    final selected = _events
        .where(
          (event) =>
              event.recipientDevicePeerId == recipientDevicePeerId &&
              (callHandle == null || event.callHandle == callHandle),
        )
        .take(limit)
        .toList(growable: false);
    return <String, Object?>{
      'ok': true,
      'events': selected.map((event) => event.toBridgeMap()).toList(),
      'receiptAtMs': nowMs(),
      'expiresAtMs': selected.isEmpty
          ? nowMs()
          : selected
                .map((event) => event.expiresAtMs)
                .reduce((left, right) => left < right ? left : right),
      'hasMore':
          _events
              .where(
                (event) =>
                    event.recipientDevicePeerId == recipientDevicePeerId &&
                    (callHandle == null || event.callHandle == callHandle),
              )
              .length >
          selected.length,
    };
  }

  Map<String, Object?> _ack(
    String recipientDevicePeerId,
    Map<String, dynamic> payload,
  ) {
    counters.dedicatedMailboxAcks++;
    final handle = payload['callHandle']! as String;
    final messageIds = (payload['messageIds']! as List)
        .map((value) => value as String)
        .toSet();
    final before = _events.length;
    _events.removeWhere(
      (event) =>
          event.recipientDevicePeerId == recipientDevicePeerId &&
          event.callHandle == handle &&
          messageIds.contains(event.messageId),
    );
    return <String, Object?>{'ok': true, 'acked': before - _events.length};
  }

  Map<String, Object?> _cancel(Map<String, dynamic> payload) {
    final recipient = payload['toPeerId']! as String;
    final handle = payload['callHandle']! as String;
    final before = _events.length;
    _events.removeWhere(
      (event) =>
          event.recipientDevicePeerId == recipient &&
          event.callHandle == handle,
    );
    return <String, Object?>{'ok': true, 'canceled': before != _events.length};
  }

  Map<String, Object?> _ordinaryBridgePath(String? command) {
    if (command?.contains('inbox') == true ||
        command?.contains('outbox') == true) {
      counters.recordOrdinaryOutboxWrite();
    }
    return const <String, Object?>{'ok': false};
  }

  _MailboxFrame byMessageId(String messageId) => _events.firstWhere(
    (event) => event.messageId == messageId,
    orElse: () {
      final last = lastStored;
      if (last != null && last.messageId == messageId) return last;
      throw StateError('missing deterministic mailbox frame');
    },
  );
}

final class _MailboxBridge implements Bridge {
  const _MailboxBridge({
    required this.localDevicePeerId,
    required this.fixture,
  });

  final String localDevicePeerId;
  final _MailboxFixture fixture;

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) =>
      fixture.invoke(localDevicePeerId, message);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DirectNetwork {
  _DirectNetwork(this.counters, this.now);

  final _PathCounters counters;
  final DateTime Function() now;
  final Map<String, _PeerP2PService> _peers = <String, _PeerP2PService>{};

  void register(_PeerP2PService peer) {
    _peers[peer.localDevicePeerId] = peer;
  }

  Future<SendMessageResult> send({
    required _PeerP2PService sender,
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) async {
    if (sender.failNextDirect) {
      sender.failNextDirect = false;
      return const SendMessageResult(
        sent: false,
        acked: false,
        transport: 'direct',
      );
    }
    final recipient = _peers[recipientDevicePeerId];
    if (recipient == null) {
      return const SendMessageResult(sent: false, acked: false);
    }
    recipient.inject(
      ChatMessage(
        from: sender.localDevicePeerId,
        to: recipientDevicePeerId,
        content: envelopeJson,
        timestamp: now().toUtc().toIso8601String(),
        isIncoming: true,
        transport: 'direct',
      ),
    );
    return const SendMessageResult(
      sent: true,
      acked: true,
      reply: 'ACK',
      transport: 'direct',
    );
  }

  void replay(_MailboxFrame frame) {
    final recipient = _peers[frame.recipientDevicePeerId];
    if (recipient == null) throw StateError('unknown replay recipient');
    recipient.inject(
      ChatMessage(
        from: frame.senderDevicePeerId,
        to: frame.recipientDevicePeerId,
        content: frame.envelopeJson,
        timestamp: now().toUtc().toIso8601String(),
        isIncoming: true,
        transport: 'direct',
      ),
    );
  }
}

final class _PeerP2PService implements P2PService {
  _PeerP2PService({
    required this.localDevicePeerId,
    required this.network,
    required this.counters,
  }) {
    network.register(this);
  }

  final String localDevicePeerId;
  final _DirectNetwork network;
  final _PathCounters counters;
  final StreamController<ChatMessage> _messages =
      StreamController<ChatMessage>.broadcast();
  bool failNextDirect = false;

  void inject(ChatMessage message) => _messages.add(message);

  @override
  Stream<ChatMessage> get messageStream => _messages.stream;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) => network.send(
    sender: this,
    recipientDevicePeerId: peerId,
    envelopeJson: message,
  );

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    counters.recordOrdinaryOutboxWrite();
    return false;
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    counters.recordOrdinaryOutboxWrite();
    return false;
  }

  @override
  void dispose() => _messages.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _MemoryHistoryRepository implements CallHistoryRepository {
  final Map<String, CallHistoryEntry> entries = <String, CallHistoryEntry>{};
  final Map<String, int> writeAttempts = <String, int>{};

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async =>
      entries[callId.value];

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async => entries
      .values
      .where((entry) => entry.contactAccountPeerId == peerId)
      .toList(growable: false);

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    writeAttempts.update(
      entry.callId.value,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    entries.putIfAbsent(entry.callId.value, () => entry);
  }
}

final class _RecordingEffects implements CallEffectExecutor {
  final List<CallEffectType> effects = <CallEffectType>[];

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    effects.add(effect.type);
    return null;
  }
}

final class _ScheduledTimer implements CallTimerHandle {
  _ScheduledTimer(this.delay, this.callback);

  final Duration delay;
  final Future<void> Function() callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  Future<void> fire() async {
    if (!_active) return;
    _active = false;
    await callback();
  }
}

final class _DeterministicTimerScheduler implements CallTimerScheduler {
  final List<_ScheduledTimer> _timers = <_ScheduledTimer>[];

  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) {
    final timer = _ScheduledTimer(delay, callback);
    _timers.add(timer);
    return timer;
  }

  Future<void> fire(Duration delay) async {
    final matches = _timers
        .where((timer) => timer.isActive && timer.delay == delay)
        .toList(growable: false);
    for (final timer in matches) {
      await timer.fire();
    }
  }
}

final class _TrustedRoster implements CallTrustedRosterProvider {
  const _TrustedRoster(this.remote);

  final TrustedCallDeviceAuthority remote;

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String peerId) async =>
      CallTrustedRosterSnapshot(
        contactAccountPeerId: remote.accountPeerId,
        contactAccepted: true,
        contactBlocked: false,
        devices: <TrustedCallDeviceAuthority>[remote],
      );

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String transportPeerId,
  ) async => transportPeerId == remote.devicePeerId ? remote : null;
}

final class _DeterministicPresenter implements IncomingCallPresenter {
  const _DeterministicPresenter(this.counters);

  final _PathCounters counters;

  @override
  Future<bool> present(IncomingCallPresentation presentation) async {
    counters.callPresentationRequests++;
    return true;
  }

  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {
    counters.callDismissalRequests++;
  }
}

final class _Peer {
  const _Peer({
    required this.accountPeerId,
    required this.devicePeerId,
    required this.signingKey,
    required this.mlKemKey,
    required this.p2p,
    required this.router,
    required this.mailbox,
    required this.coordinator,
    required this.history,
    required this.cleanupCounts,
    required this.timers,
    required this.signaling,
    required this.runtime,
  });

  final String accountPeerId;
  final String devicePeerId;
  final String signingKey;
  final String mlKemKey;
  final _PeerP2PService p2p;
  final IncomingMessageRouter router;
  final BridgeCallMailboxClient mailbox;
  final CallCoordinator coordinator;
  final _MemoryHistoryRepository history;
  final Map<String, int> cleanupCounts;
  final _DeterministicTimerScheduler timers;
  final CallSignalingService signaling;
  final CallSignalingRuntime runtime;
}

final class _JourneyCall {
  const _JourneyCall({
    required this.callId,
    required this.callHandle,
    required this.transport,
    required this.inviteFrame,
  });

  final CallId callId;
  final String callHandle;
  final CallSignalTransportResult transport;
  final _MailboxFrame inviteFrame;
}

final class _SignalTransmission {
  const _SignalTransmission({
    required this.signal,
    required this.transport,
    required this.frame,
  });

  final CallSignal signal;
  final CallSignalTransportResult transport;
  final _MailboxFrame frame;
}

final class _TwoPeerCallHarness {
  _TwoPeerCallHarness._({
    required this.counters,
    required this.mailboxFixture,
    required this.network,
    required this.caller,
    required this.callee,
  });

  final _PathCounters counters;
  final _MailboxFixture mailboxFixture;
  final _DirectNetwork network;
  final _Peer caller;
  final _Peer callee;
  final List<_MailboxFrame> _terminalReplayFrames = <_MailboxFrame>[];
  final Map<String, _MailboxFrame> _answerFrames = <String, _MailboxFrame>{};
  int _nowMs = _initialNowMs;
  int _callCounter = 0;
  int _messageCounter = 0;
  _JourneyCall? _lastInvite;

  static Future<_TwoPeerCallHarness> create() async {
    final counters = _PathCounters();
    var nowMs = _initialNowMs;
    DateTime now() => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
    final mailboxFixture = _MailboxFixture(counters, () => nowMs);
    final network = _DirectNetwork(counters, now);
    final presenter = _DeterministicPresenter(counters);

    final callerP2P = _PeerP2PService(
      localDevicePeerId: 'caller-device-peer',
      network: network,
      counters: counters,
    );
    final calleeP2P = _PeerP2PService(
      localDevicePeerId: 'callee-device-peer',
      network: network,
      counters: counters,
    );
    final callerRouter = IncomingMessageRouter(p2pService: callerP2P);
    final calleeRouter = IncomingMessageRouter(p2pService: calleeP2P);
    _observeRouterIsolation(callerRouter, counters);
    _observeRouterIsolation(calleeRouter, counters);
    callerRouter.start();
    calleeRouter.start();

    final callerHistory = _MemoryHistoryRepository();
    final calleeHistory = _MemoryHistoryRepository();
    final callerCleanup = <String, int>{};
    final calleeCleanup = <String, int>{};
    final callerTimers = _DeterministicTimerScheduler();
    final calleeTimers = _DeterministicTimerScheduler();
    final callerCoordinator = _coordinator(
      now: now,
      history: callerHistory,
      cleanupCounts: callerCleanup,
      timers: callerTimers,
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    final calleeCoordinator = _coordinator(
      now: now,
      history: calleeHistory,
      cleanupCounts: calleeCleanup,
      timers: calleeTimers,
      id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );
    final callerMailbox = BridgeCallMailboxClient(
      bridge: _MailboxBridge(
        localDevicePeerId: 'caller-device-peer',
        fixture: mailboxFixture,
      ),
    );
    final calleeMailbox = BridgeCallMailboxClient(
      bridge: _MailboxBridge(
        localDevicePeerId: 'callee-device-peer',
        fixture: mailboxFixture,
      ),
    );
    final callerCodec = SecureCallEnvelopeCodec(
      crypto: _DeterministicCrypto(),
      nowMs: () => nowMs,
      replayStore: InMemoryBoundedCallReplayProtectionStore(maxEntries: 128),
    );
    final calleeCodec = SecureCallEnvelopeCodec(
      crypto: _DeterministicCrypto(),
      nowMs: () => nowMs,
      replayStore: InMemoryBoundedCallReplayProtectionStore(maxEntries: 128),
    );
    final callerHandler = HandleIncomingCallSignal(
      codec: callerCodec,
      coordinator: callerCoordinator,
      trustedRosterProvider: const _TrustedRoster(
        TrustedCallDeviceAuthority(
          accountPeerId: 'callee-account-peer',
          devicePeerId: 'callee-device-peer',
          linked: true,
          deviceKeyEpoch: 1,
          signingPublicKey: 'callee-signing-key',
          mlKemPublicKey: 'callee-mlkem-key',
        ),
      ),
      localAuthorityProvider: () async => const CallLocalDeviceAuthority(
        accountPeerId: 'caller-account-peer',
        devicePeerId: 'caller-device-peer',
        mlKemSecretKey: 'caller-mlkem-key',
      ),
      incomingCallPresenter: presenter,
      networkEffectsAllowed: () => true,
    );
    final calleeHandler = HandleIncomingCallSignal(
      codec: calleeCodec,
      coordinator: calleeCoordinator,
      trustedRosterProvider: const _TrustedRoster(
        TrustedCallDeviceAuthority(
          accountPeerId: 'caller-account-peer',
          devicePeerId: 'caller-device-peer',
          linked: true,
          deviceKeyEpoch: 1,
          signingPublicKey: 'caller-signing-key',
          mlKemPublicKey: 'caller-mlkem-key',
        ),
      ),
      localAuthorityProvider: () async => const CallLocalDeviceAuthority(
        accountPeerId: 'callee-account-peer',
        devicePeerId: 'callee-device-peer',
        mlKemSecretKey: 'callee-mlkem-key',
      ),
      incomingCallPresenter: presenter,
      networkEffectsAllowed: () => true,
    );
    final callerRuntime = CallSignalingRuntime(
      directCallSignalStream: callerRouter.callSignalStream,
      mailboxClient: callerMailbox,
      handleIncoming: callerHandler.handle,
      coordinator: callerCoordinator,
      networkEffectsAllowed: () => true,
      maxPendingOperations: 16,
    );
    final calleeRuntime = CallSignalingRuntime(
      directCallSignalStream: calleeRouter.callSignalStream,
      mailboxClient: calleeMailbox,
      handleIncoming: calleeHandler.handle,
      coordinator: calleeCoordinator,
      networkEffectsAllowed: () => true,
      maxPendingOperations: 16,
    );
    final callerSignaling = CallSignalingService(
      codec: callerCodec,
      directTransport: P2PCallTransport(p2pService: callerP2P),
      mailboxClient: callerMailbox,
      coordinator: callerCoordinator,
      networkEffectsAllowed: () => true,
    );
    final calleeSignaling = CallSignalingService(
      codec: calleeCodec,
      directTransport: P2PCallTransport(p2pService: calleeP2P),
      mailboxClient: calleeMailbox,
      coordinator: calleeCoordinator,
      networkEffectsAllowed: () => true,
    );
    final harness = _TwoPeerCallHarness._(
      counters: counters,
      mailboxFixture: mailboxFixture,
      network: network,
      caller: _Peer(
        accountPeerId: 'caller-account-peer',
        devicePeerId: 'caller-device-peer',
        signingKey: 'caller-signing-key',
        mlKemKey: 'caller-mlkem-key',
        p2p: callerP2P,
        router: callerRouter,
        mailbox: callerMailbox,
        coordinator: callerCoordinator,
        history: callerHistory,
        cleanupCounts: callerCleanup,
        timers: callerTimers,
        signaling: callerSignaling,
        runtime: callerRuntime,
      ),
      callee: _Peer(
        accountPeerId: 'callee-account-peer',
        devicePeerId: 'callee-device-peer',
        signingKey: 'callee-signing-key',
        mlKemKey: 'callee-mlkem-key',
        p2p: calleeP2P,
        router: calleeRouter,
        mailbox: calleeMailbox,
        coordinator: calleeCoordinator,
        history: calleeHistory,
        cleanupCounts: calleeCleanup,
        timers: calleeTimers,
        signaling: calleeSignaling,
        runtime: calleeRuntime,
      ),
    );
    harness._nowMs = nowMs;
    await callerRuntime.start();
    await calleeRuntime.start();
    return harness;
  }

  static CallCoordinator _coordinator({
    required DateTime Function() now,
    required _MemoryHistoryRepository history,
    required Map<String, int> cleanupCounts,
    required _DeterministicTimerScheduler timers,
    required String id,
  }) => CallCoordinator(
    reducer: const CallReducer(),
    cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
      CallCleanupStep('release_call_resources', (snapshot) async {
        cleanupCounts.update(
          snapshot.callId!.value,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }),
    ]),
    historyProjector: CallHistoryProjector(history, clock: now),
    effectExecutor: _RecordingEffects(),
    timerScheduler: timers,
    clock: now,
    idSource: () => CallId.parse(id),
  );

  static void _observeRouterIsolation(
    IncomingMessageRouter router,
    _PathCounters counters,
  ) {
    router.callSignalStream.listen((_) => counters.callRouterFrames++);
    router.chatMessageStream.listen(
      (_) => counters.recordOrdinaryRouterDelivery(),
    );
    router.contactRequestStream.listen(
      (_) => counters.recordOrdinaryRouterDelivery(),
    );
    router.deliveryReceiptStream.listen(
      (_) => counters.recordOrdinaryRouterDelivery(),
    );
    router.unknownMessageStream.listen(
      (_) => counters.recordOrdinaryRouterDelivery(),
    );
  }

  CallState get callerState =>
      caller.coordinator.lastSnapshot?.state ?? CallState.idle;
  CallState get calleeState =>
      callee.coordinator.lastSnapshot?.state ?? CallState.idle;
  CallEndReason? get callerTerminalReason =>
      caller.coordinator.lastSnapshot?.endReason;
  CallEndReason? get calleeTerminalReason =>
      callee.coordinator.lastSnapshot?.endReason;
  bool get callerMailboxCustodyConfirmed =>
      caller.coordinator.lastSnapshot?.mailboxCustodyConfirmed ?? false;
  int get mailboxWakeRequests => counters.mailboxWakeRequests;
  int get mailboxAcknowledgements => counters.dedicatedMailboxAcks;
  int get callPresentationRequests => counters.callPresentationRequests;

  Future<_JourneyCall> inviteWithDirectFailure() =>
      _invite(directFailure: true);

  Future<_JourneyCall> _invite({required bool directFailure}) async {
    final callId = CallId.parse(_nextUuid('10000000', ++_callCounter));
    final callHandle = _nextUuid('30000000', _callCounter);
    await _prepareOutgoing(caller, callee, callId);
    caller.p2p.failNextDirect = directFailure;
    final signal = _signal(
      sender: caller,
      recipient: callee,
      callId: callId,
      type: CallSignalType.invite,
      senderSequence: 1,
    );
    final transport = await caller.signaling.send(
      signal: signal,
      callHandle: callHandle,
      endpoint: _endpoint(callee),
      senderSigningPrivateKey: caller.signingKey,
    );
    await _settleNetwork();
    final call = _JourneyCall(
      callId: callId,
      callHandle: callHandle,
      transport: transport,
      inviteFrame: mailboxFixture.byMessageId(signal.messageId),
    );
    _lastInvite = call;
    return call;
  }

  Future<void> wakeCalleeAndDrain() async {
    await callee.runtime.onResume();
    await _settleNetwork();
  }

  Future<void> replayLastMailboxFrameDirectly() async {
    network.replay(_lastInvite!.inviteFrame);
    await _settleNetwork();
  }

  Future<void> answerAndConverge(_JourneyCall call) async {
    await callee.coordinator.dispatch(
      _event(
        type: CallEventType.answer,
        id: 'local-answer-${call.callId.value}',
        call: call,
        local: callee,
        remote: caller,
      ),
    );
    final transmitted = await _transmit(
      sender: callee,
      recipient: caller,
      call: call,
      type: CallSignalType.accept,
      senderSequence: 1,
    );
    _answerFrames[call.callId.value] = transmitted.frame;
    await _settleNetwork();
  }

  Future<void> enterMediaPlaceholderBoundary(_JourneyCall call) async {
    await Future.wait(<Future<CallReduction>>[
      caller.coordinator.dispatch(
        _event(
          type: CallEventType.negotiationReady,
          id: 'caller-negotiate-${call.callId.value}',
          call: call,
          local: caller,
          remote: callee,
        ),
      ),
      callee.coordinator.dispatch(
        _event(
          type: CallEventType.negotiationReady,
          id: 'callee-negotiate-${call.callId.value}',
          call: call,
          local: callee,
          remote: caller,
        ),
      ),
    ]);
    await Future.wait(<Future<CallReduction>>[
      caller.coordinator.dispatch(
        _event(
          type: CallEventType.mediaConnected,
          id: 'caller-media-placeholder-${call.callId.value}',
          call: call,
          local: caller,
          remote: callee,
        ),
      ),
      callee.coordinator.dispatch(
        _event(
          type: CallEventType.mediaConnected,
          id: 'callee-media-placeholder-${call.callId.value}',
          call: call,
          local: callee,
          remote: caller,
        ),
      ),
    ]);
  }

  Future<void> terminateAgainstLateAnswer(_JourneyCall call) async {
    await caller.coordinator.dispatch(
      _event(
        type: CallEventType.end,
        id: 'caller-end-${call.callId.value}',
        call: call,
        local: caller,
        remote: callee,
      ),
    );
    final transmitted = await _transmit(
      sender: caller,
      recipient: callee,
      call: call,
      type: CallSignalType.terminate,
      senderSequence: 2,
      reason: CallEndReason.remoteHangup,
    );
    await callee.coordinator.dispatch(
      _event(
        type: CallEventType.answer,
        id: 'late-answer-${call.callId.value}',
        call: call,
        local: callee,
        remote: caller,
      ),
    );
    _terminalReplayFrames.add(transmitted.frame);
    await _settleNetwork();
    network.replay(_answerFrames[call.callId.value]!);
    await caller.runtime.onResume();
    await callee.runtime.onResume();
    await _settleNetwork();
  }

  Future<_JourneyCall> declineJourney() async {
    final call = await _invite(directFailure: false);
    expect(calleeState, CallState.ringing);
    await callee.coordinator.dispatch(
      _event(
        type: CallEventType.decline,
        id: 'callee-decline-${call.callId.value}',
        call: call,
        local: callee,
        remote: caller,
      ),
    );
    final transmitted = await _transmit(
      sender: callee,
      recipient: caller,
      call: call,
      type: CallSignalType.reject,
      senderSequence: 1,
      reason: CallEndReason.declined,
    );
    _terminalReplayFrames.add(transmitted.frame);
    await _settleNetwork();
    return call;
  }

  Future<_JourneyCall> cancelAgainstAnswerJourney() async {
    final call = await _invite(directFailure: false);
    expect(calleeState, CallState.ringing);
    await caller.coordinator.dispatch(
      _event(
        type: CallEventType.cancel,
        id: 'caller-cancel-${call.callId.value}',
        call: call,
        local: caller,
        remote: callee,
      ),
    );
    final transmission = _transmit(
      sender: caller,
      recipient: callee,
      call: call,
      type: CallSignalType.terminate,
      senderSequence: 2,
      reason: CallEndReason.callerCancelled,
    );
    final lateAnswer = callee.coordinator.dispatch(
      _event(
        type: CallEventType.answer,
        id: 'racing-answer-${call.callId.value}',
        call: call,
        local: callee,
        remote: caller,
      ),
    );
    final transmitted = await transmission;
    await lateAnswer;
    _terminalReplayFrames.add(transmitted.frame);
    await _settleNetwork();
    expect(calleeTerminalReason, CallEndReason.callerCancelled);
    return call;
  }

  Future<_JourneyCall> expiryJourney() async {
    final call = await _invite(directFailure: false);
    expect(calleeState, CallState.ringing);
    await Future.wait(<Future<void>>[
      caller.timers.fire(_signalLifetime),
      callee.timers.fire(_signalLifetime),
    ]);
    _terminalReplayFrames.add(call.inviteFrame);
    expect(callerTerminalReason, CallEndReason.expired);
    expect(calleeTerminalReason, CallEndReason.expired);
    return call;
  }

  CallHistoryStatus? historyStatus(_JourneyCall call) {
    final callerEntry = caller.history.entries[call.callId.value];
    final calleeEntry = callee.history.entries[call.callId.value];
    expect(callerEntry?.status, calleeEntry?.status);
    return callerEntry?.status;
  }

  void expectExactlyOnce(_JourneyCall call) {
    for (final peer in <_Peer>[caller, callee]) {
      expect(peer.cleanupCounts[call.callId.value], 1);
      expect(peer.history.writeAttempts[call.callId.value], 1);
      final entry = peer.history.entries[call.callId.value];
      expect(entry, isNotNull);
      final keys = entry!.toMap().keys.map((key) => key.toLowerCase()).toSet();
      for (final forbidden in const <String>{
        'call_handle',
        'wake_handle',
        'sdp',
        'candidate',
        'token',
        'key',
      }) {
        expect(keys, isNot(contains(forbidden)));
      }
    }
  }

  Future<void> replayAllTerminalFrames() async {
    for (final frame in _terminalReplayFrames) {
      network.replay(frame);
    }
    await _settleNetwork();
    await caller.runtime.onResume();
    await callee.runtime.onResume();
    await _settleNetwork();
  }

  void expectOrdinaryPathsUnused() {
    expect(counters.callRouterFrames, greaterThan(0));
    expect(counters.dedicatedMailboxStores, greaterThan(0));
    expect(counters.dedicatedMailboxRetrieves, greaterThan(0));
    expect(counters.dedicatedMailboxAcks, greaterThan(0));
    expect(counters.ordinaryRouterDeliveries, 0);
    expect(counters.genericOutboxWrites, 0);
    expect(counters.genericRetrierSchedules, 0);
    expect(counters.ordinaryNotificationRequests, 0);
  }

  Future<_SignalTransmission> _transmit({
    required _Peer sender,
    required _Peer recipient,
    required _JourneyCall call,
    required CallSignalType type,
    required int senderSequence,
    CallEndReason? reason,
  }) async {
    final signal = _signal(
      sender: sender,
      recipient: recipient,
      callId: call.callId,
      type: type,
      senderSequence: senderSequence,
      reason: reason,
    );
    final transport = await sender.signaling.send(
      signal: signal,
      callHandle: call.callHandle,
      endpoint: _endpoint(recipient),
      senderSigningPrivateKey: sender.signingKey,
    );
    return _SignalTransmission(
      signal: signal,
      transport: transport,
      frame: mailboxFixture.byMessageId(signal.messageId),
    );
  }

  CallSignal _signal({
    required _Peer sender,
    required _Peer recipient,
    required CallId callId,
    required CallSignalType type,
    required int senderSequence,
    CallEndReason? reason,
  }) => CallSignal.create(
    callId: callId,
    messageId: _nextUuid('20000000', ++_messageCounter),
    event: type,
    senderAccountPeerId: sender.accountPeerId,
    senderDevicePeerId: sender.devicePeerId,
    recipientAccountPeerId: recipient.accountPeerId,
    recipientDevicePeerId: recipient.devicePeerId,
    senderSequence: senderSequence,
    iceGeneration: 0,
    createdAtMs: _nowMs,
    expiresAtMs: _nowMs + _signalLifetime.inMilliseconds,
    payload: reason == null
        ? const <String, Object?>{}
        : <String, Object?>{'reason': reason.wireName},
  );

  ResolvedCallEndpoint _endpoint(_Peer recipient) => ResolvedCallEndpoint(
    accountPeerId: recipient.accountPeerId,
    devicePeerId: recipient.devicePeerId,
    signingPublicKey: recipient.signingKey,
    mlKemPublicKey: recipient.mlKemKey,
    deviceKeyEpoch: 1,
    preferenceEpoch: 1,
    platform: CallEndpointPlatform.android,
    expiresAtMs: _nowMs + const Duration(hours: 1).inMilliseconds,
    routingHandle: recipient == caller
        ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        : 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    wakeHandle: recipient == caller
        ? 'cccccccccccccccccccccccccccccccc'
        : 'dddddddddddddddddddddddddddddddd',
  );

  Future<void> _prepareOutgoing(
    _Peer sender,
    _Peer recipient,
    CallId callId,
  ) async {
    await sender.coordinator.dispatch(
      CallEvent(
        type: CallEventType.place,
        eventId: 'place-${callId.value}',
        occurredAt: _now(),
        callId: callId,
        contactPeerId: recipient.accountPeerId,
        localAccountPeerId: sender.accountPeerId,
        localDeviceId: sender.devicePeerId,
        remoteAccountPeerId: recipient.accountPeerId,
        remoteDeviceId: recipient.devicePeerId,
      ),
    );
    await sender.coordinator.dispatch(
      CallEvent(
        type: CallEventType.outgoingInviteReady,
        eventId: 'invite-ready-${callId.value}',
        occurredAt: _now(),
        callId: callId,
        contactPeerId: recipient.accountPeerId,
        localAccountPeerId: sender.accountPeerId,
        localDeviceId: sender.devicePeerId,
        remoteAccountPeerId: recipient.accountPeerId,
        remoteDeviceId: recipient.devicePeerId,
      ),
    );
  }

  CallEvent _event({
    required CallEventType type,
    required String id,
    required _JourneyCall call,
    required _Peer local,
    required _Peer remote,
  }) => CallEvent(
    type: type,
    eventId: id,
    occurredAt: _now(),
    callId: call.callId,
    contactPeerId: remote.accountPeerId,
    localAccountPeerId: local.accountPeerId,
    localDeviceId: local.devicePeerId,
    remoteAccountPeerId: remote.accountPeerId,
    remoteDeviceId: remote.devicePeerId,
  );

  DateTime _now() => DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true);

  Future<void> _settleNetwork() async {
    for (var pass = 0; pass < 3; pass++) {
      await Future<void>.delayed(Duration.zero);
      await caller.runtime.settle();
      await callee.runtime.settle();
    }
  }

  String _nextUuid(String prefix, int value) =>
      '$prefix-0000-4000-8000-${value.toString().padLeft(12, '0')}';

  Future<void> dispose() async {
    await caller.runtime.shutdown();
    await callee.runtime.shutdown();
    caller.router.dispose();
    callee.router.dispose();
    caller.p2p.dispose();
    callee.p2p.dispose();
  }
}
