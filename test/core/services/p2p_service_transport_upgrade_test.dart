import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

/// FDC-12 — the Dart half of the DCUtR relay->direct upgrade session.
///
/// EXTENDS the FDC-13 `transport:upgraded` handler so an upgrade ALSO primes the
/// sticky transport cache (`lastKnownGoodTransport` → direct), and ADDS a new
/// `transport:downgraded` handler that reverts the FDC-13 'upgraded' badge and
/// clears the sticky preference when the direct leg dies. Drives the real
/// [P2PServiceImpl] via the transport-diagnostic event stream, exactly as
/// p2p_service_inbound_transport_test.dart (FDC-13) does.
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

void main() {
  late _FakeBridge bridge;
  late InMemoryInboxStagingRepository inboxStagingRepository;
  late P2PServiceImpl service;

  setUp(() {
    bridge = _FakeBridge();
    bridge.whenCommand('inbox:ack', (_) => jsonEncode({'ok': true, 'acked': 1}));
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
    inboxStagingRepository = InMemoryInboxStagingRepository();
    service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: inboxStagingRepository,
    );
  });

  tearDown(() {
    service.dispose();
  });

  // A circuit-connected peer whose full id ends with the sanitized short id the
  // tracer telemetry carries (so _resolveFullPeerId can map short -> full).
  const peerShort = 'abcd1234';
  const peerId = '12D3KooWUpgradeStickyPeerabcd1234';

  void connectViaCircuit() {
    bridge.onPeerConnected?.call(
      const p2p.ConnectionState(
        peerId: peerId,
        multiaddrs: ['/dns4/relay.example/tcp/4001/p2p/relay-peer/p2p-circuit'],
        direction: 'outbound',
        status: 'connected',
      ),
    );
  }

  Future<String?> inboundTransport() async {
    final received = <ChatMessage>[];
    final sub = service.messageStream.listen(received.add);
    bridge.onMessageReceived?.call(
      const ChatMessage(
        from: peerId,
        to: 'self-peer',
        content: 'x',
        timestamp: '2026-01-01T00:00:00.000Z',
        isIncoming: true,
        transport: null,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();
    return received.single.transport;
  }

  test(
    'FDC-12 TC-12-09: transport:upgraded populates sticky lastKnownGoodTransport '
    "(direct) AND preserves the FDC-13 'upgraded' badge",
    () async {
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      connectViaCircuit();

      // Before the upgrade: no sticky direct preference.
      expect(service.lastKnownGoodTransport(peerId), isNot('direct'));

      emitTransportDiagnosticEvent('transport:upgraded', {
        'fromTransport': 'relay',
        'toTransport': 'direct',
        'elapsedMs': 25,
        'remotePeerShort': peerShort,
      });

      // FDC-12 (new): the sticky cache now prefers direct, so the next send's
      // sticky/reuse fast-path reuses the direct conn.
      expect(service.lastKnownGoodTransport(peerId), 'direct');

      // FDC-13 (preserved): the per-message 'upgraded' badge still surfaces.
      expect(await inboundTransport(), 'upgraded');
    },
  );

  test(
    'FDC-12 TC-12-09b: transport:downgraded reverts the upgraded badge and '
    'clears the sticky direct preference',
    () async {
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      connectViaCircuit();

      emitTransportDiagnosticEvent('transport:upgraded', {
        'fromTransport': 'relay',
        'toTransport': 'direct',
        'elapsedMs': 25,
        'remotePeerShort': peerShort,
      });
      expect(service.lastKnownGoodTransport(peerId), 'direct');
      expect(await inboundTransport(), 'upgraded');

      // The direct leg dies; the circuit survives.
      emitTransportDiagnosticEvent('transport:downgraded', {
        'fromTransport': 'direct',
        'toTransport': 'relay',
        'remotePeerShort': peerShort,
      });

      // Sticky cleared → next send re-probes (no dead direct leg trapped).
      expect(service.lastKnownGoodTransport(peerId), isNot('direct'));
      // Badge reverted → the live circuit conn now infers 'relay', not 'upgraded'.
      expect(await inboundTransport(), 'relay');
    },
  );

  test(
    'FDC-12 TC-12-09c: a short-id collision (two connected peers sharing the '
    'last-8-char id) does NOT prime the wrong peer\'s sticky cache',
    () async {
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

      // Two distinct full peer ids whose last 8 chars collide ('collide1').
      const collideShort = 'collide1';
      const peerA = '12D3KooWpeerAcollide1';
      const peerB = '12D3KooWpeerBcollide1';
      for (final p in [peerA, peerB]) {
        bridge.onPeerConnected?.call(
          p2p.ConnectionState(
            peerId: p,
            multiaddrs: const [
              '/dns4/relay.example/tcp/4001/p2p/relay-peer/p2p-circuit',
            ],
            direction: 'outbound',
            status: 'connected',
          ),
        );
      }

      emitTransportDiagnosticEvent('transport:upgraded', {
        'fromTransport': 'relay',
        'toTransport': 'direct',
        'elapsedMs': 25,
        'remotePeerShort': collideShort,
      });

      // Ambiguous short id → resolver returns null → NEITHER peer's sticky cache
      // is primed (fail-safe; the send race still falls back to the full race).
      expect(service.lastKnownGoodTransport(peerA), isNot('direct'));
      expect(service.lastKnownGoodTransport(peerB), isNot('direct'));
    },
  );
}
