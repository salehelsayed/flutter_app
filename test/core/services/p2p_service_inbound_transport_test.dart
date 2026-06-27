import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart'
    show LocalChatMessage;
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../local_discovery/fake_local_p2p_service.dart';

/// U2 — RECEIVE-path transport classification (the Option D bias-fix guard).
///
/// These tests drive the REAL [P2PServiceImpl] receive path via the bridge's
/// `onMessageReceived` callback. The false-result risk is MISLABELING, so every
/// assertion checks an EXACT surfaced transport string and EXACT census counts.
///
/// The critical case (T1) proves a genuinely-unknown inbound (transport:null,
/// peer not connected) surfaces as 'unknown' — NOT the old fabricated 'relay'.

class _FakeBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)>
  _handlers = {};
  bool _initialized = false;

  void whenCommand(
    String cmd,
    FutureOr<String> Function(Map<String, dynamic>?) handler,
  ) {
    _handlers[cmd] = handler;
  }

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;
    final payload = request['payload'] as Map<String, dynamic>?;
    final handler = _handlers[cmd];
    if (handler != null) {
      return await handler(payload);
    }
    return jsonEncode({
      'ok': false,
      'errorCode': 'UNHANDLED',
      'errorMessage': 'no handler for $cmd',
    });
  }
}

Future<List<Map<String, dynamic>>> _captureFlowEvents(
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

void main() {
  late _FakeBridge bridge;
  late TransportMetrics metrics;
  late InMemoryInboxStagingRepository inboxStagingRepository;
  late P2PServiceImpl service;

  setUp(() {
    bridge = _FakeBridge();
    bridge.whenCommand(
      'inbox:ack',
      (_) => jsonEncode({'ok': true, 'acked': 1}),
    );
    bridge.whenCommand(
      'node:start',
      (_) => jsonEncode({
        'ok': true,
        'peerId': 'self-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }),
    );
    metrics = TransportMetrics();
    inboxStagingRepository = InMemoryInboxStagingRepository();
    service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: inboxStagingRepository,
      transportMetrics: metrics,
    );
  });

  tearDown(() {
    service.dispose();
  });

  test('T1 (CORE): unknown inbound (transport:null, peer not connected) '
      'surfaces as unknown, never relay', () async {
    await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

    final received = <ChatMessage>[];
    final sub = service.messageStream.listen(received.add);

    // No onPeerConnected for 'ghost' → _inferTransportForPeer returns null →
    // final default must be 'unknown' (Option D), not the old 'relay'.
    bridge.onMessageReceived?.call(
      const ChatMessage(
        from: 'ghost',
        to: 'self-peer',
        content: 'hello',
        timestamp: '2026-01-01T00:00:00.000Z',
        isIncoming: true,
        transport: null,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(1));
    expect(received.single.transport, 'unknown');
    expect(received.single.transport, isNot('relay'));

    // Census records the post-fix value exactly.
    expect(metrics.transportMix()['unknown'], 1);
    expect(metrics.transportMix()['relay'], 0);

    await sub.cancel();
  });

  test(
    'T2 (NEGATIVE CONTROL): an explicit relay message stays relay',
    () async {
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

      final received = <ChatMessage>[];
      final sub = service.messageStream.listen(received.add);

      // Genuine relay label from Go, no live connection.
      bridge.onMessageReceived?.call(
        const ChatMessage(
          from: 'ghost',
          to: 'self-peer',
          content: 'hello',
          timestamp: '2026-01-01T00:00:00.000Z',
          isIncoming: true,
          transport: 'relay',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, hasLength(1));
      expect(received.single.transport, 'relay');
      expect(metrics.transportMix()['relay'], 1);
      expect(metrics.transportMix()['unknown'], 0);

      await sub.cancel();
    },
  );

  test('T3: the guard does NOT defeat a TRUE inference — a peer with a live '
      'circuit connection infers relay (not fabricated)', () async {
    await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

    final received = <ChatMessage>[];
    final sub = service.messageStream.listen(received.add);

    // Real circuit connection → inference legitimately yields 'relay'.
    bridge.onPeerConnected?.call(
      const p2p.ConnectionState(
        peerId: 'p',
        multiaddrs: ['/dns4/relay.example/tcp/4001/p2p/relay-peer/p2p-circuit'],
        direction: 'outbound',
        status: 'connected',
      ),
    );
    bridge.onMessageReceived?.call(
      const ChatMessage(
        from: 'p',
        to: 'self-peer',
        content: 'hello',
        timestamp: '2026-01-01T00:00:00.000Z',
        isIncoming: true,
        transport: null,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(1));
    expect(received.single.transport, 'relay');
    expect(metrics.transportMix()['relay'], 1);
    expect(metrics.transportMix()['unknown'], 0);

    await sub.cancel();
  });

  test('T4: a peer with a live non-circuit connection infers direct', () async {
    await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

    final received = <ChatMessage>[];
    final sub = service.messageStream.listen(received.add);

    bridge.onPeerConnected?.call(
      const p2p.ConnectionState(
        peerId: 'p',
        multiaddrs: ['/ip4/192.168.1.10/tcp/4001'],
        direction: 'outbound',
        status: 'connected',
      ),
    );
    bridge.onMessageReceived?.call(
      const ChatMessage(
        from: 'p',
        to: 'self-peer',
        content: 'hello',
        timestamp: '2026-01-01T00:00:00.000Z',
        isIncoming: true,
        transport: null,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(1));
    expect(received.single.transport, 'direct');
    expect(metrics.transportMix()['direct'], 1);
    expect(metrics.transportMix()['unknown'], 0);

    await sub.cancel();
  });

  test(
    'DCUTR-002: transport diagnostics drive exact counters and upgrade inference',
    () async {
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

      const upgradedPeerShort = 'abc12345';
      const upgradedPeerId = '12D3KooWHostSideUpgradePeerabc12345';

      emitTransportDiagnosticEvent('holepunch:attempt', {
        'step': 'started',
        'remotePeerShort': upgradedPeerShort,
      });
      emitTransportDiagnosticEvent('holepunch:attempt', {
        'step': 'direct_dial',
        'remotePeerShort': upgradedPeerShort,
      });
      emitTransportDiagnosticEvent('holepunch:attempt', {
        'step': 'attempt',
        'attempt': 1,
        'remotePeerShort': upgradedPeerShort,
      });
      emitTransportDiagnosticEvent('holepunch:success', {
        'step': 'succeeded',
        'fromTransport': 'relay',
        'toTransport': 'direct',
        'elapsedMs': 25,
        'remotePeerShort': upgradedPeerShort,
      });
      emitTransportDiagnosticEvent('holepunch:failure', {
        'step': 'failed',
        'error': 'timeout',
        'remotePeerShort': 'other999',
      });
      emitTransportDiagnosticEvent('transport:upgraded', {
        'fromTransport': 'relay',
        'toTransport': 'direct',
        'elapsedMs': 25,
        'remotePeerShort': upgradedPeerShort,
      });

      expect(metrics.holePunchAttempts, 1);
      expect(metrics.holePunchSuccesses, 1);
      expect(metrics.holePunchFailures, 1);
      expect(metrics.relayToDirectUpgrades, 1);

      final received = <ChatMessage>[];
      final sub = service.messageStream.listen(received.add);

      bridge.onMessageReceived?.call(
        const ChatMessage(
          from: upgradedPeerId,
          to: 'self-peer',
          content: 'hello after upgrade',
          timestamp: '2026-01-01T00:00:00.000Z',
          isIncoming: true,
          transport: null,
        ),
      );
      bridge.onMessageReceived?.call(
        const ChatMessage(
          from: 'not-upgraded-peer',
          to: 'self-peer',
          content: 'hello without upgrade',
          timestamp: '2026-01-01T00:00:01.000Z',
          isIncoming: true,
          transport: null,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, hasLength(2));
      // RT-S1 (FDC-13): the upgraded peer's incoming message now surfaces the
      // DISTINCT 'upgraded' transport on the DATA channel — no longer flattened
      // to plain 'direct'. The non-upgraded, no-conn peer is unaffected
      // ('unknown'), proving set membership (not a blanket relabel).
      expect(received[0].transport, 'upgraded');
      expect(received[1].transport, 'unknown');
      // RT-S1a (FDC-13): the aggregate transport-mix census is UNCHANGED — the
      // step-4a `'upgraded'->'direct'` canonicalization alias keeps the
      // upgraded receive counted in the 'direct' bucket (mirrors 'reuse'),
      // while the badge still carries 'upgraded'. Without that alias the
      // upgraded receive would fold to 'unknown' (['direct']1->0, ['unknown']
      // 1->2), so these three asserts double as the lock on step 4a.
      expect(metrics.transportMix()['direct'], 1);
      expect(metrics.transportMix()['unknown'], 1);
      expect(metrics.transportMix()['relay'], 0);

      await sub.cancel();
    },
  );

  // RT-I1 (FDC-13): end-to-end readout — a synthetic `transport:upgraded`
  // tracer event registers the peer, and a subsequent incoming message from it
  // surfaces 'upgraded' on BOTH the streamed ChatMessage AND the greppable
  // MSG_RECEIVED_TRANSPORT flow event (distinct observation channels from
  // DCUTR-002's messageStream + census).
  test(
    "DCUTR-013: synthetic upgrade event surfaces 'upgraded' on the receiver "
    'readout (streamed message + MSG_RECEIVED_TRANSPORT flow event)',
    () async {
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

      const upgradedPeerShort = 'def67890';
      const upgradedPeerId = '12D3KooWReadoutUpgradePeerdef67890';

      final received = <ChatMessage>[];
      final sub = service.messageStream.listen(received.add);

      final events = await _captureFlowEvents(() async {
        emitTransportDiagnosticEvent('transport:upgraded', {
          'fromTransport': 'relay',
          'toTransport': 'direct',
          'elapsedMs': 25,
          'remotePeerShort': upgradedPeerShort,
        });
        bridge.onMessageReceived?.call(
          const ChatMessage(
            from: upgradedPeerId,
            to: 'self-peer',
            content: 'hello after upgrade',
            timestamp: '2026-01-01T00:00:00.000Z',
            isIncoming: true,
            transport: null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });

      // Streamed ChatMessage readout (copyWith(transport:) at the receive
      // path) carries the distinct 'upgraded' value.
      expect(received, hasLength(1));
      expect(received.single.transport, 'upgraded');

      // Greppable MSG_RECEIVED_TRANSPORT flow-event detail also reads
      // 'upgraded'.
      expect(
        events.any(
          (event) =>
              event['event'] == 'MSG_RECEIVED_TRANSPORT' &&
              (event['details'] as Map<String, dynamic>)['transport'] ==
                  'upgraded',
        ),
        isTrue,
      );

      await sub.cancel();
    },
  );

  test('T5: local WiFi messages surface as wifi and are censused', () async {
    final localP2P = FakeLocalP2PService();
    final wifiMetrics = TransportMetrics();
    final wifiService = P2PServiceImpl(
      bridge: _FakeBridge()
        ..whenCommand('inbox:ack', (_) => jsonEncode({'ok': true, 'acked': 1})),
      inboxStagingRepository: InMemoryInboxStagingRepository(),
      localP2PService: localP2P,
      transportMetrics: wifiMetrics,
    );
    addTearDown(wifiService.dispose);

    final received = <ChatMessage>[];
    final sub = wifiService.messageStream.listen(received.add);

    localP2P.emitLocalMessage(
      LocalChatMessage(
        content: 'hi over wifi',
        from: 'lan-peer',
        to: 'self-peer',
        timestamp: DateTime.utc(2026, 1, 1),
        isIncoming: true,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(1));
    expect(received.single.transport, 'wifi');
    expect(wifiMetrics.transportMix()['wifi'], 1);
    expect(wifiMetrics.transportMix()['relay'], 0);
    expect(wifiMetrics.transportMix()['unknown'], 0);

    await sub.cancel();
  });

  test(
    'T6: handled LAN commits still record wifi transport telemetry',
    () async {
      final localP2P = FakeLocalP2PService();
      final wifiMetrics = TransportMetrics();
      final wifiService = P2PServiceImpl(
        bridge: _FakeBridge()
          ..whenCommand(
            'inbox:ack',
            (_) => jsonEncode({'ok': true, 'acked': 1}),
          ),
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        localP2PService: localP2P,
        transportMetrics: wifiMetrics,
        replayRecoveredInboxChatMessage:
            (message, {String? stagedEntryId}) async {
              expect(stagedEntryId, 'lan:n-telemetry');
              return (
                disposition: RecoveredInboxChatDisposition.committed,
                reasonCode: 'stored',
                reasonDetail: null,
              );
            },
      );
      addTearDown(wifiService.dispose);

      final events = await _captureFlowEvents(() async {
        final decision = await Future<LanInboundDecision>.sync(
          () => localP2P.inboundChatCommitHandler!(
            LocalChatMessage(
              content: jsonEncode({
                'type': 'chat_message',
                'version': '1',
                'payload': {
                  'id': 'msg-lan-telemetry',
                  'text': 'telemetry',
                  'senderPeerId': 'lan-peer',
                  'senderUsername': 'Alice',
                  'timestamp': '2026-01-01T00:00:00.000Z',
                },
              }),
              from: 'lan-peer',
              to: 'self-peer',
              timestamp: DateTime.utc(2026, 1, 1),
              isIncoming: true,
            ),
            nonce: 'n-telemetry',
          ),
        );
        expect(decision.isCommitted, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });

      expect(wifiMetrics.transportMix()['wifi'], 1);
      expect(
        events.any(
          (event) =>
              event['event'] == 'MSG_RECEIVED_TRANSPORT' &&
              (event['details'] as Map<String, dynamic>)['transport'] == 'wifi',
        ),
        isTrue,
      );
    },
  );
}
