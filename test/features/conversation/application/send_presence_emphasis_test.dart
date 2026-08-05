import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart'
    show SendChatMessageResult;
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

// Reuse the canonical send-use-case test harness (fake p2pService + message
// repo + the sendChatMessage wrapper + flow-event capture) so these presence
// tests exercise the REAL send path. `show` avoids the duplicate `main` clash.
import 'send_chat_message_use_case_test.dart'
    show
        FakeP2PService,
        FakeMessageRepository,
        DurableLanFakeP2PService,
        sendChatMessage,
        captureFlowEvents;

// FDC-08/R4 — relay presence remains best-effort advice at the structurally
// unknown send seam. It never gates eligible authenticated work or changes
// custody scheduling/cancellation authority.

/// A send-path fake that adds a configurable [RelayPresence] (the optional
/// [RelayPresenceLookup] capability) and records inbox-vs-live ordering.
class _PresenceFake extends FakeP2PService implements RelayPresenceLookup {
  _PresenceFake({
    required this.presence,
    this.inboxDelay = Duration.zero,
    this.connected = false,
    this.presenceLookup,
    this.storeInInboxDetailedCallback,
    super.currentState,
    super.sendMessageResult,
    super.storeInInboxResult,
    super.useNullDiscover,
  });

  final RelayPresence presence;
  final Duration inboxDelay;
  final Future<RelayPresence> Function(String peerId)? presenceLookup;
  final StoreInInboxDetailedFn? storeInInboxDetailedCallback;

  /// When true, the sender is already connected to the target → `unknownPresence`
  /// is false → the presence block is skipped entirely (TC-181-50 boundary).
  final bool connected;
  int presenceLookupCount = 0;
  int storeInInboxDetailedCallCount = 0;

  /// Ordered completion/entry markers: 'inbox-call', 'inbox-done', 'live'.
  final List<String> order = [];

  @override
  Future<RelayPresence> lookupRelayPresence(String peerId) async {
    presenceLookupCount++;
    final lookup = presenceLookup;
    if (lookup != null) return lookup(peerId);
    return presence;
  }

  @override
  bool isConnectedToPeer(String peerId) => connected;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    order.add('inbox-call');
    final r = await super.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
    if (inboxDelay > Duration.zero) {
      await Future<void>.delayed(inboxDelay);
    }
    order.add('inbox-done');
    return r;
  }

  Future<InboxStoreOutcome> storeInInboxDetailed(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final callback = storeInInboxDetailedCallback;
    if (callback == null) {
      throw StateError('No detailed inbox-store callback was configured');
    }
    storeInInboxDetailedCallCount++;
    order.add('inbox-call');
    final result = await callback(toPeerId, message, timeoutMs: timeoutMs);
    if (inboxDelay > Duration.zero) {
      await Future<void>.delayed(inboxDelay);
    }
    order.add('inbox-done');
    return result;
  }

  void _markLive() {
    if (!order.contains('live')) order.add('live');
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) {
    _markLive();
    return super.discoverPeer(peerId, timeoutMs: timeoutMs);
  }

  @override
  Future<bool> discoverLocalPeer(String peerId, {required Duration timeout}) {
    _markLive();
    return super.discoverLocalPeer(peerId, timeout: timeout);
  }
}

typedef _DetailedInboxStep = Future<InboxStoreOutcome> Function();

class _ScriptedDetailedInboxStore {
  _ScriptedDetailedInboxStore(List<_DetailedInboxStep> steps, {this.order})
    : _steps = List<_DetailedInboxStep>.from(steps);

  final List<_DetailedInboxStep> _steps;
  final List<String>? order;
  int callCount = 0;
  String? lastEnvelope;
  final List<bool> callOutcomes = [];

  Future<InboxStoreOutcome> call(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    if (_steps.isEmpty) {
      throw StateError('Detailed inbox-store script exhausted');
    }
    callCount++;
    lastEnvelope = message;
    order?.add('inbox-call');
    try {
      final outcome = await _steps.removeAt(0)();
      callOutcomes.add(outcome.accepted);
      order?.add('inbox-done');
      return outcome;
    } catch (_) {
      callOutcomes.add(false);
      order?.add('inbox-error');
      rethrow;
    }
  }
}

const _connectedPeerInboxHedgeBudget = Duration(milliseconds: 2500);

Map<String, dynamic>? _emphasis(List<Map<String, dynamic>> events) {
  for (final e in events) {
    if (e['event'] == 'CHAT_MSG_PRESENCE_EMPHASIS') return e;
  }
  return null;
}

bool _has(List<Map<String, dynamic>> events, String name) =>
    events.any((e) => e['event'] == name);

void main() {
  // C5 / R4 — reachable advice cannot suppress the immediate hedge selected by
  // the peer's structurally unknown routing state.
  test(
    'reachable advice does not suppress the structurally unknown inbox hedge',
    () async {
      final p2p = _PresenceFake(
        presence: RelayPresence.reachable,
        storeInInboxResult: true,
      );
      final repo = FakeMessageRepository();

      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'hi',
          senderPeerId: 'me',
          senderUsername: 'Me',
        );
        await Future<void>.delayed(Duration.zero);
      });

      // The durable copy fired independently of the later reachable hint.
      expect(p2p.storeInInboxCallCount, greaterThanOrEqualTo(1));
      expect(p2p.presenceLookupCount, 1);
      final emphasis = _emphasis(events);
      expect(emphasis, isNotNull);
      expect((emphasis!['details'] as Map)['presence'], 'reachable');
    },
  );

  test(
    'R4 slow unreachable or throwing presence cannot delay authenticated live launch or settlement',
    () {
      for (final row in const [
        (name: 'controlled-unreachable', throws: false),
        (name: 'throwing', throws: true),
      ]) {
        fakeAsync((async) {
          final controlledPresence = row.throws
              ? null
              : Completer<RelayPresence>();
          final releaseCapture = Completer<void>();
          final p2p = _PresenceFake(
            presence: RelayPresence.unknown,
            presenceLookup: (_) => row.throws
                ? Future<RelayPresence>.error(
                    StateError('scripted presence failure'),
                  )
                : controlledPresence!.future,
            sendMessageResult: true,
            storeInInboxResult: false,
          )..sendMessageTransport = 'direct';
          final repo = FakeMessageRepository();
          SendChatMessageResult? result;
          Object? sendError;
          Object? captureError;
          var sendSettled = false;
          var captureSettled = false;
          var events = <Map<String, dynamic>>[];

          final capture = captureFlowEvents(() async {
            try {
              final (sendResult, _) = await sendChatMessage(
                p2pService: p2p,
                messageRepo: repo,
                targetPeerId: 'target-peer',
                text: 'presence is only advice',
                senderPeerId: 'me',
                senderUsername: 'Me',
              );
              result = sendResult;
            } catch (error) {
              sendError = error;
            } finally {
              sendSettled = true;
            }
            await releaseCapture.future;
          });
          capture.then(
            (captured) {
              events = captured;
              captureSettled = true;
            },
            onError: (Object error) {
              captureError = error;
              captureSettled = true;
            },
          );

          async.flushMicrotasks();
          final liveStartedBeforeAdvice =
              p2p.discoverCallCount > 0 || p2p.sendCallCount > 0;
          final settledBeforeAdvice = sendSettled;

          // Production may deliberately event-defer the best-effort refresh so
          // eligible live futures are constructed first. Run that zero-delay
          // event while controlled advice is still unresolved; the throwing
          // row must genuinely invoke (and contain) its failed lookup.
          async.elapse(Duration.zero);
          async.flushMicrotasks();
          final presenceWasConsulted = p2p.presenceLookupCount;

          controlledPresence?.complete(RelayPresence.unreachable);
          async.flushMicrotasks();
          if (!releaseCapture.isCompleted) releaseCapture.complete();
          async.flushMicrotasks();

          expect(
            liveStartedBeforeAdvice,
            isTrue,
            reason: '${row.name}: presence advice must not gate live launch',
          );
          expect(
            settledBeforeAdvice,
            isTrue,
            reason: '${row.name}: an authenticated ACK settles independently',
          );
          expect(sendError, isNull, reason: row.name);
          expect(captureError, isNull, reason: row.name);
          expect(captureSettled, isTrue, reason: row.name);
          expect(presenceWasConsulted, 1, reason: row.name);
          expect(result, SendChatMessageResult.success, reason: row.name);
          expect(repo.saved.single.status, 'delivered', reason: row.name);
          expect(repo.saved.single.transport, 'direct', reason: row.name);
          expect(
            _has(events, 'CHAT_MSG_PRESENCE_INBOX_FIRST'),
            isFalse,
            reason: '${row.name}: obsolete inbox-first advice is retired',
          );
        });
      }
    },
  );

  test(
    'R4 structurally unknown peer starts one inbox hedge between staging and committed sticky return',
    () async {
      final inboxResult = Completer<InboxStoreOutcome>();
      final p2p =
          _PresenceFake(
              presence: RelayPresence.unknown,
              sendMessageResult: true,
              storeInInboxResult: false,
              storeInInboxDetailedCallback:
                  (toPeerId, message, {int? timeoutMs}) => inboxResult.future,
            )
            ..lastKnownGoodTransportResult = 'direct'
            ..sendMessageTransport = 'direct';
      final repo = FakeMessageRepository()
        ..onOrdinaryStage = () => p2p.order.add('stage');
      p2p.onSendMessage = () => p2p.order.add('sticky-send');

      final (result, _) = await sendChatMessage(
        p2pService: p2p,
        messageRepo: repo,
        targetPeerId: 'target-peer',
        text: 'stage before the unknown-peer hedge',
        senderPeerId: 'me',
        senderUsername: 'Me',
        storeInInboxDetailed: p2p.storeInInboxDetailed,
      );
      final orderAtStickyReturn = List<String>.from(p2p.order);

      inboxResult.complete(
        const InboxStoreOutcome(
          status: InboxStoreStatus.stored,
          expiresAtMs: 34002,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(orderAtStickyReturn.take(3), <String>[
        'stage',
        'inbox-call',
        'sticky-send',
      ]);
      expect(p2p.storeInInboxDetailedCallCount, 1);
      expect(p2p.storeInInboxCallCount, 0);
      expect(p2p.discoverCallCount, 0);
      expect(p2p.discoverLocalPeerCallCount, 0);
      expect(p2p.dialCallCount, 0);
      expect(p2p.sendCallCount, 1);
      expect(p2p.presenceLookupCount, 0);
      expect(result, SendChatMessageResult.success);
      expect(repo.saved.single.status, 'delivered');
      expect(repo.saved.single.transport, 'direct');
      expect(repo.saved.single.relayExpiresAt, isNull);
    },
  );

  test(
    'R4 connected reuse hedge starts at T0 bound and late proof upgrades custody',
    () {
      fakeAsync((async) {
        const expiresAtMs = 34003001;
        final reuseAck = Completer<SendMessageResult>();
        final metrics = TransportMetrics();
        final p2p = _PresenceFake(
          presence: RelayPresence.unreachable,
          currentState: const NodeState(
            isStarted: true,
            connections: [
              ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/192.0.2.1/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
          storeInInboxResult: false,
          storeInInboxDetailedCallback:
              (toPeerId, message, {int? timeoutMs}) async =>
                  const InboxStoreOutcome(
                    status: InboxStoreStatus.stored,
                    expiresAtMs: expiresAtMs,
                  ),
        )..queuedSendMessageResults.add(reuseAck.future);
        final repo = FakeMessageRepository();
        SendChatMessageResult? result;
        Object? sendError;
        var sendSettled = false;

        sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'connected reuse remains hedged',
          senderPeerId: 'me',
          senderUsername: 'Me',
          transportMetrics: metrics,
          storeInInboxDetailed: p2p.storeInInboxDetailed,
        ).then(
          (completion) {
            result = completion.$1;
            sendSettled = true;
          },
          onError: (Object error) {
            sendError = error;
            sendSettled = true;
          },
        );
        async.flushMicrotasks();

        async.elapse(
          _connectedPeerInboxHedgeBudget - const Duration(milliseconds: 1),
        );
        async.flushMicrotasks();
        final detailedBeforeBound = p2p.storeInInboxDetailedCallCount;
        final booleanBeforeBound = p2p.storeInInboxCallCount;

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        final detailedAtBound = p2p.storeInInboxDetailedCallCount;
        final booleanAtBound = p2p.storeInInboxCallCount;
        final inboxAttemptsAtBound = metrics.attemptCounts()['inbox'];
        final inboxFailuresAtBound = metrics.attemptFailureCounts()['inbox'];
        final rowAtBound = repo.existingMessages.values.single;

        reuseAck.complete(
          const SendMessageResult(sent: true, acked: true, transport: 'direct'),
        );
        async.flushMicrotasks();
        final finalRow = repo.existingMessages.values.single;

        expect(detailedBeforeBound, 0);
        expect(booleanBeforeBound, 0);
        expect(detailedAtBound, 1);
        expect(booleanAtBound, 0);
        expect(inboxAttemptsAtBound, 1);
        expect(inboxFailuresAtBound, 0);
        expect(rowAtBound.status, 'inboxed');
        expect(rowAtBound.transport, 'inbox');
        expect(rowAtBound.relayExpiresAt, expiresAtMs);
        expect(sendError, isNull);
        expect(sendSettled, isTrue);
        expect(result, SendChatMessageResult.success);
        expect(p2p.storeInInboxDetailedCallCount, 1);
        expect(metrics.attemptCounts()['inbox'], 1);
        expect(finalRow.status, 'delivered');
        expect(finalRow.transport, 'direct');
        expect(finalRow.relayExpiresAt, isNull);
        expect(p2p.presenceLookupCount, 0);
      });
    },
  );

  test('R4 LAN WebSocket evidence cannot cancel the T0 inbox hedge', () {
    fakeAsync((async) {
      const expiresAtMs = 34004001;
      final authenticatedDirectResult = Completer<SendMessageResult>();
      final detailedOrder = <String>[];
      final detailedStore = _ScriptedDetailedInboxStore([
        () async => const InboxStoreOutcome(
          status: InboxStoreStatus.stored,
          expiresAtMs: expiresAtMs,
        ),
      ], order: detailedOrder);
      final p2p =
          DurableLanFakeP2PService(
              localSendAck: LanSendAck.committed,
              storeInInboxResult: true,
            )
            ..localPeers.add('target-peer')
            ..queuedSendMessageResults.add(authenticatedDirectResult.future);
      final repo = FakeMessageRepository();
      SendChatMessageResult? result;
      Object? sendError;
      var sendSettled = false;

      sendChatMessage(
        p2pService: p2p,
        messageRepo: repo,
        targetPeerId: 'target-peer',
        text: 'LAN writes do not own delivery authority',
        senderPeerId: 'me',
        senderUsername: 'Me',
        storeInInboxDetailed: detailedStore.call,
      ).then(
        (completion) {
          result = completion.$1;
          sendSettled = true;
        },
        onError: (Object error) {
          sendError = error;
          sendSettled = true;
        },
      );
      async.flushMicrotasks();
      final localWritesBeforeBound = p2p.localSendCallCount;

      async.elapse(
        _connectedPeerInboxHedgeBudget - const Duration(milliseconds: 1),
      );
      async.flushMicrotasks();
      final detailedBeforeBound = detailedStore.callCount;
      final booleanBeforeBound = p2p.storeInInboxCallCount;

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      final detailedAtBound = detailedStore.callCount;
      final booleanAtBound = p2p.storeInInboxCallCount;
      final rowAtBound = repo.existingMessages.values.single;

      authenticatedDirectResult.complete(
        const SendMessageResult(sent: false, acked: false, transport: 'direct'),
      );
      async.flushMicrotasks();
      async.elapse(_connectedPeerInboxHedgeBudget);
      async.flushMicrotasks();
      final finalDetailedCalls = detailedStore.callCount;
      final finalBooleanCalls = p2p.storeInInboxCallCount;
      final finalRow = repo.existingMessages.values.single;

      expect(localWritesBeforeBound, 1);
      expect(detailedBeforeBound, 0);
      expect(booleanBeforeBound, 0);
      expect(detailedAtBound, 1);
      expect(booleanAtBound, 0);
      expect(rowAtBound.status, 'inboxed');
      expect(rowAtBound.transport, 'inbox');
      expect(rowAtBound.relayExpiresAt, expiresAtMs);
      expect(sendError, isNull);
      expect(sendSettled, isTrue);
      expect(result, SendChatMessageResult.success);
      expect(finalDetailedCalls, 1);
      expect(finalBooleanCalls, 0);
      expect(detailedOrder, <String>['inbox-call', 'inbox-done']);
      expect(detailedStore.callOutcomes, <bool>[true]);
      expect(finalRow.status, 'inboxed');
      expect(finalRow.transport, 'inbox');
      expect(finalRow.relayExpiresAt, expiresAtMs);
    });
  });

  test('R4 typed hedge preserves outcomes retries and per-call metrics', () {
    const storedExpiry = 34008001;
    const duplicateExpiry = 34008002;
    const retryStoredExpiry = 34008003;
    const retryDuplicateExpiry = 34008004;
    final rows =
        <
          ({
            String name,
            List<_DetailedInboxStep> steps,
            List<bool> expectedCallOutcomes,
            int expectedCalls,
            int expectedFailedCalls,
            bool custodyAtBound,
            String expectedStatus,
            int? expectedExpiry,
          })
        >[
          (
            name: 'stored',
            steps: [
              () async => const InboxStoreOutcome(
                status: InboxStoreStatus.stored,
                expiresAtMs: storedExpiry,
              ),
            ],
            expectedCallOutcomes: const [true],
            expectedCalls: 1,
            expectedFailedCalls: 0,
            custodyAtBound: true,
            expectedStatus: 'inboxed',
            expectedExpiry: storedExpiry,
          ),
          (
            name: 'duplicate',
            steps: [
              () async => const InboxStoreOutcome(
                status: InboxStoreStatus.duplicate,
                expiresAtMs: duplicateExpiry,
              ),
            ],
            expectedCallOutcomes: const [true],
            expectedCalls: 1,
            expectedFailedCalls: 0,
            custodyAtBound: true,
            expectedStatus: 'inboxed',
            expectedExpiry: duplicateExpiry,
          ),
          (
            name: 'rejected-full',
            steps: [
              () async => const InboxStoreOutcome(
                status: InboxStoreStatus.rejectedFull,
                errorCode: 'INBOX_FULL',
              ),
            ],
            expectedCallOutcomes: const [false],
            expectedCalls: 1,
            expectedFailedCalls: 1,
            custodyAtBound: false,
            expectedStatus: 'sent',
            expectedExpiry: null,
          ),
          (
            name: 'failed-then-stored',
            steps: [
              () async => const InboxStoreOutcome(
                status: InboxStoreStatus.failed,
                errorCode: 'STORE_FAILED',
              ),
              () async => const InboxStoreOutcome(
                status: InboxStoreStatus.stored,
                expiresAtMs: retryStoredExpiry,
              ),
            ],
            expectedCallOutcomes: const [false, true],
            expectedCalls: 2,
            expectedFailedCalls: 1,
            custodyAtBound: false,
            expectedStatus: 'inboxed',
            expectedExpiry: retryStoredExpiry,
          ),
          (
            name: 'throw-then-duplicate',
            steps: [
              () => Future<InboxStoreOutcome>.error(
                StateError('scripted detailed inbox failure'),
              ),
              () async => const InboxStoreOutcome(
                status: InboxStoreStatus.duplicate,
                expiresAtMs: retryDuplicateExpiry,
              ),
            ],
            expectedCallOutcomes: const [false, true],
            expectedCalls: 2,
            expectedFailedCalls: 1,
            custodyAtBound: false,
            expectedStatus: 'inboxed',
            expectedExpiry: retryDuplicateExpiry,
          ),
        ];

    for (final row in rows) {
      fakeAsync((async) {
        final authenticatedDirectResult = Completer<SendMessageResult>();
        final detailedStore = _ScriptedDetailedInboxStore(row.steps);
        final metrics = TransportMetrics();
        final p2p =
            DurableLanFakeP2PService(
                localSendAck: LanSendAck.committed,
                storeInInboxResult: false,
              )
              ..localPeers.add('target-peer')
              ..queuedSendMessageResults.add(authenticatedDirectResult.future);
        final repo = FakeMessageRepository();
        SendChatMessageResult? result;
        Object? sendError;
        var sendSettled = false;

        sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'typed hedge row ${row.name}',
          senderPeerId: 'me',
          senderUsername: 'Me',
          transportMetrics: metrics,
          storeInInboxDetailed: detailedStore.call,
        ).then(
          (completion) {
            result = completion.$1;
            sendSettled = true;
          },
          onError: (Object error) {
            sendError = error;
            sendSettled = true;
          },
        );
        async.flushMicrotasks();

        async.elapse(
          _connectedPeerInboxHedgeBudget - const Duration(milliseconds: 1),
        );
        async.flushMicrotasks();
        final callsBeforeBound = detailedStore.callCount;
        final booleanCallsBeforeBound = p2p.storeInInboxCallCount;

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        final callsAtBound = detailedStore.callCount;
        final booleanCallsAtBound = p2p.storeInInboxCallCount;
        final attemptsAtBound = metrics.attemptCounts()['inbox'];
        final failuresAtBound = metrics.attemptFailureCounts()['inbox'];
        final rowAtBound = repo.existingMessages.values.single;

        authenticatedDirectResult.complete(
          const SendMessageResult(
            sent: false,
            acked: false,
            transport: 'direct',
          ),
        );
        async.flushMicrotasks();
        async.elapse(_connectedPeerInboxHedgeBudget);
        async.flushMicrotasks();
        final finalRow = repo.existingMessages.values.single;

        expect(callsBeforeBound, 0, reason: row.name);
        expect(booleanCallsBeforeBound, 0, reason: row.name);
        expect(callsAtBound, 1, reason: row.name);
        expect(booleanCallsAtBound, 0, reason: row.name);
        expect(attemptsAtBound, 1, reason: row.name);
        expect(failuresAtBound, row.custodyAtBound ? 0 : 1, reason: row.name);
        expect(
          rowAtBound.status,
          row.custodyAtBound ? 'inboxed' : 'sending',
          reason: row.name,
        );
        if (row.custodyAtBound) {
          expect(rowAtBound.transport, 'inbox', reason: row.name);
          expect(
            rowAtBound.relayExpiresAt,
            row.expectedExpiry,
            reason: row.name,
          );
        }
        expect(sendError, isNull, reason: row.name);
        expect(sendSettled, isTrue, reason: row.name);
        expect(result, SendChatMessageResult.success, reason: row.name);
        expect(detailedStore.callCount, row.expectedCalls, reason: row.name);
        expect(p2p.storeInInboxCallCount, 0, reason: row.name);
        expect(
          detailedStore.callOutcomes,
          row.expectedCallOutcomes,
          reason: row.name,
        );
        expect(
          metrics.attemptCounts()['inbox'],
          row.expectedCalls,
          reason: row.name,
        );
        expect(
          metrics.attemptFailureCounts()['inbox'],
          row.expectedFailedCalls,
          reason: row.name,
        );
        expect(finalRow.status, row.expectedStatus, reason: row.name);
        expect(finalRow.transport, 'inbox', reason: row.name);
        expect(finalRow.relayExpiresAt, row.expectedExpiry, reason: row.name);
        expect(finalRow.wireEnvelope, isNotEmpty, reason: row.name);
        expect(
          detailedStore.lastEnvelope,
          finalRow.wireEnvelope,
          reason: row.name,
        );
        expect(
          repo.ordinarySettlementCalls.any((call) => call.status == 'inboxed'),
          row.expectedStatus == 'inboxed',
          reason: '${row.name}: custody candidates match accepted outcomes',
        );
      });
    }
  });

  // C7 ⭐ — a WRONG `reachable` hint for an actually-offline peer STILL deposits
  // the durable copy (+ relay push-to-wake). The single load-bearing gate:
  // presence is a HINT, never a delivery gate.
  test(
    'reachable hint for an offline peer still deposits the durable copy',
    () async {
      final p2p = _PresenceFake(
        presence: RelayPresence.reachable, // WRONG hint
        sendMessageResult:
            false, // every live leg fails (peer is really offline)
        useNullDiscover: true, // direct discover yields nothing
        storeInInboxResult: true,
      );
      final repo = FakeMessageRepository();

      SendChatMessageResult? result;
      final events = await captureFlowEvents(() async {
        final (r, _) = await sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'hi',
          senderPeerId: 'me',
          senderUsername: 'Me',
        );
        result = r;
        await Future<void>.delayed(Duration.zero);
      });

      // The hint was (wrongly) reachable...
      expect((_emphasis(events)!['details'] as Map)['presence'], 'reachable');
      // ...yet the structurally unknown hedge still started. The correlated
      // BEGIN event proves a real store call, independently of terminal rescue.
      expect(_has(events, 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN'), isTrue);
      expect(p2p.storeInInboxCallCount, greaterThanOrEqualTo(1));
      // And the message is delivered (durable inbox custody), never lost.
      expect(result, SendChatMessageResult.success);
    },
  );

  // TC-181-32u / R4 preservation — `unknown` advice may still emit emphasis,
  // but no presence value can restore the retired inbox-first ordering branch.
  test('unknown presence emits EMPHASIS but not INBOX_FIRST', () async {
    final p2p = _PresenceFake(
      presence: RelayPresence.unknown,
      storeInInboxResult: true,
    );
    final repo = FakeMessageRepository();

    final events = await captureFlowEvents(() async {
      await sendChatMessage(
        p2pService: p2p,
        messageRepo: repo,
        targetPeerId: 'target-peer',
        text: 'hi',
        senderPeerId: 'me',
        senderUsername: 'Me',
      );
      await Future<void>.delayed(Duration.zero);
    });

    expect((_emphasis(events)!['details'] as Map)['presence'], 'unknown');
    expect(_has(events, 'CHAT_MSG_PRESENCE_INBOX_FIRST'), isFalse);
    // The durable copy still fires (fully-concurrent behavior unchanged).
    expect(p2p.storeInInboxCallCount, greaterThanOrEqualTo(1));
  });

  // TC-181-50 / R4 preservation — presence remains unconsulted for peers already
  // known live. R4 separately arms a delayed custody hedge for this structural
  // class; a fast authenticated proof cancels that unstarted hedge.
  test(
    'connected peer (unknownPresence=false) skips the presence block entirely',
    () async {
      final p2p = _PresenceFake(
        presence:
            RelayPresence.unreachable, // would short-circuit IF the block ran
        connected: true, // isConnectedToPeer => true → unknownPresence false
        storeInInboxResult: true,
      );
      final repo = FakeMessageRepository();

      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'hi',
          senderPeerId: 'me',
          senderUsername: 'Me',
        );
        await Future<void>.delayed(Duration.zero);
      });

      // Block skipped: presence never consulted, no emphasis, no short-circuit.
      expect(_emphasis(events), isNull);
      expect(p2p.presenceLookupCount, 0);
      expect(_has(events, 'CHAT_MSG_PRESENCE_INBOX_FIRST'), isFalse);
      expect(p2p.storeInInboxCallCount, 0);
    },
  );

  // -------------------------------------------------------------------------
  // 184 — optimistic 2-tick send-status progression: the concurrent-inbox ACK
  // surfaces a custody milestone MID-send (status:'inboxed' +
  // CHAT_MSG_SEND_CUSTODY_CONFIRMED) so the 1:1 bubble advances to two ticks at
  // ~110 ms instead of resting on the optimistic single tick until the race
  // resolves. The atomic settlement writer prevents a weaker custody candidate
  // from regressing delivery; INV-4 keeps one tick when custody is not secured.
  // -------------------------------------------------------------------------

  // TC-184-10 — the concurrent-inbox ACK persists a non-terminal 'inboxed'
  // mid-send AND emits CHAT_MSG_SEND_CUSTODY_CONFIRMED, distinct from (and
  // BEFORE) the terminal save. RED on HEAD: the `.then` only records a metric.
  test('custody-confirmed persists inboxed mid-send + emits CUSTODY_CONFIRMED '
      'before the terminal', () async {
    final p2p = _PresenceFake(
      presence: RelayPresence.unknown,
      sendMessageResult: false, // live legs fail (offline peer)
      useNullDiscover: true, // direct discover yields nothing
      storeInInboxResult: true, // the durable inbox ACKs
    );
    final repo = FakeMessageRepository();

    final events = await captureFlowEvents(() async {
      await sendChatMessage(
        p2pService: p2p,
        messageRepo: repo,
        targetPeerId: 'target-peer',
        text: 'hi',
        senderPeerId: 'me',
        senderUsername: 'Me',
      );
    });

    // The mid-send custody milestone fired...
    expect(_has(events, 'CHAT_MSG_SEND_CUSTODY_CONFIRMED'), isTrue);
    // ...and an atomic 'inboxed' settlement was applied at the ACK in addition
    // to the terminal custody settlement.
    expect(
      repo.ordinarySettlementCalls.where((call) => call.status == 'inboxed'),
      hasLength(greaterThanOrEqualTo(2)),
    );
    // Distinct-event discriminator: the custody bump STRICTLY precedes the
    // terminal timing event, so it is the mid-send milestone, not the terminal
    // 'inboxed' save (both carry status=='inboxed').
    final custodyIdx = events.indexWhere(
      (e) => e['event'] == 'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
    );
    final timingIdx = events.indexWhere(
      (e) => e['event'] == 'CHAT_MSG_SEND_TIMING',
    );
    expect(custodyIdx, greaterThanOrEqualTo(0));
    expect(timingIdx, greaterThanOrEqualTo(0));
    expect(
      custodyIdx,
      lessThan(timingIdx),
      reason:
          'custody-confirmed is the MID-send milestone — it must precede '
          'the terminal timing event',
    );
  });

  // TC-184-12 / R4 — once storage starts it is not canceled. Its late weaker
  // candidate still reaches the atomic writer; the authoritative row remains
  // delivered and therefore emits no false custody milestone.
  test(
    'live ack before inbox ack invokes atomic candidate without regressing delivery',
    () {
      fakeAsync((async) {
        final p2p =
            _PresenceFake(
                presence: RelayPresence.unknown,
                inboxDelay: const Duration(milliseconds: 60),
                sendMessageResult: true,
                storeInInboxResult: true,
                storeInInboxDetailedCallback:
                    (toPeerId, message, {int? timeoutMs}) async =>
                        const InboxStoreOutcome(
                          status: InboxStoreStatus.stored,
                        ),
              )
              ..sendMessageAcked = true
              ..sendMessageTransport = 'direct';
        final repo = FakeMessageRepository();
        Object? captureError;
        var captureSettled = false;
        var events = <Map<String, dynamic>>[];

        captureFlowEvents(() async {
          await sendChatMessage(
            p2pService: p2p,
            messageRepo: repo,
            targetPeerId: 'target-peer',
            text: 'late custody candidate',
            senderPeerId: 'me',
            senderUsername: 'Me',
            storeInInboxDetailed: p2p.storeInInboxDetailed,
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }).then(
          (captured) {
            events = captured;
            captureSettled = true;
          },
          onError: (Object error) {
            captureError = error;
            captureSettled = true;
          },
        );

        async.flushMicrotasks();
        final rowAfterLiveAck = repo.existingMessages.values.single;
        async.elapse(const Duration(milliseconds: 60));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 40));
        async.flushMicrotasks();
        final finalRow = repo.existingMessages.values.single;

        expect(captureError, isNull);
        expect(captureSettled, isTrue);
        expect(rowAfterLiveAck.status, 'delivered');
        expect(rowAfterLiveAck.transport, 'direct');
        expect(
          repo.ordinarySettlementCalls.where(
            (call) => call.status == 'inboxed',
          ),
          hasLength(1),
        );
        expect(finalRow.status, 'delivered');
        expect(finalRow.transport, 'direct');
        expect(finalRow.relayExpiresAt, isNull);
        expect(_has(events, 'CHAT_MSG_SEND_CUSTODY_CONFIRMED'), isFalse);
      });
    },
  );

  // TC-184-13 — an offline send (live legs fail) RESTS at 'inboxed' custody, and
  // the custody bump lands MID-send (an ADDITIONAL 'inboxed' write on top of the
  // terminal persist) so the bubble shows two ticks from ~110 ms, not after the
  // full race. RED on HEAD: only the single terminal 'inboxed' write exists.
  test('offline send rests at inboxed with a mid-send custody bump', () async {
    final p2p = _PresenceFake(
      presence: RelayPresence.unknown,
      sendMessageResult: false,
      useNullDiscover: true,
      storeInInboxResult: true,
    );
    final repo = FakeMessageRepository();

    final events = await captureFlowEvents(() async {
      await sendChatMessage(
        p2pService: p2p,
        messageRepo: repo,
        targetPeerId: 'target-peer',
        text: 'hi',
        senderPeerId: 'me',
        senderUsername: 'Me',
      );
    });

    // The bubble rests at custody (two ticks): the terminal persist writes the
    // full 'inboxed' custody row...
    expect(repo.saved.last.status, 'inboxed');
    // ...AND the mid-send bump advanced the status to 'inboxed' through an
    // additional atomic settlement before the terminal custody settlement.
    expect(
      repo.ordinarySettlementCalls.where((call) => call.status == 'inboxed'),
      hasLength(greaterThanOrEqualTo(2)),
    );
    expect(_has(events, 'CHAT_MSG_SEND_CUSTODY_CONFIRMED'), isTrue);
  });

  // TC-184-14 — if custody is NOT secured (inbox store returns false) the
  // mid-send bump must NOT fire: no false two-tick (INV-4). Guard lock: passes
  // on HEAD; mutation-verified by removing the `ok==true` guard.
  test(
    'inbox store failure keeps the single tick — no false custody bump',
    () async {
      final p2p = _PresenceFake(
        presence: RelayPresence.unknown,
        sendMessageResult: false,
        useNullDiscover: true,
        storeInInboxResult: false, // custody NOT secured
      );
      final repo = FakeMessageRepository();

      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: p2p,
          messageRepo: repo,
          targetPeerId: 'target-peer',
          text: 'hi',
          senderPeerId: 'me',
          senderUsername: 'Me',
        );
      });

      expect(_has(events, 'CHAT_MSG_SEND_CUSTODY_CONFIRMED'), isFalse);
      expect(
        repo.ordinarySettlementCalls.any((call) => call.status == 'inboxed'),
        isFalse,
      );
    },
  );
}
