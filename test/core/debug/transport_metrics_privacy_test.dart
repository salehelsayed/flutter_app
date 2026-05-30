import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

/// PR1 — privacy gate for TransportMetrics + the transport flow events.
///
/// Two distinct concerns:
///  PR1a — the emitFlowEvent SEAM: events fired while exercising the transport
///         arms must carry no FULL peer ID (>12 chars), no multiaddr, no message
///         content, and no per-conversation trace. A negative control proves the
///         sanitizer actively redacts a fabricated identifying payload.
///  PR1b — the EXTERNAL getters / baselineReport (read by the debug card) are
///         surfaced OUTSIDE emitFlowEvent, so the sanitizer never touches them.
///         They must still contain only counts/ratios/ms — no identifiers.

// A long, real-looking peer ID and a circuit multiaddr that must never leak.
const _longPeerId = '12D3KooWLongRealisticPeerIdAbcdefghijklmnop1234567890';
const _circuitMultiaddr =
    '/dns4/relay.example/tcp/4001/p2p/12D3KooWRelayServerNodeXYZ/p2p-circuit';
const _secretContent = 'TOP-SECRET-MESSAGE-BODY';

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
    final handler = _handlers[cmd];
    if (handler != null) {
      return await handler(request['payload'] as Map<String, dynamic>?);
    }
    return jsonEncode({'ok': false, 'errorCode': 'UNHANDLED'});
  }
}

/// Recursively flattens a captured flow-event payload to a single searchable
/// string so we can assert no identifier substring survives anywhere.
String _flatten(Object? value) {
  if (value is Map) {
    return value.entries.map((e) => '${e.key}=${_flatten(e.value)}').join(';');
  }
  if (value is Iterable) {
    return value.map(_flatten).join(',');
  }
  return value.toString();
}

void main() {
  group('PR1a — emitFlowEvent seam', () {
    late List<Map<String, dynamic>> events;

    setUp(() {
      events = [];
      debugSetFlowEventSink(events.add);
    });
    tearDown(() {
      debugSetFlowEventSink(null);
    });

    test(
      'receive-arm flow events carry no full peer ID, multiaddr, or content',
      () async {
        final bridge = _FakeBridge()
          ..whenCommand(
            'inbox:ack',
            (_) => jsonEncode({'ok': true, 'acked': 1}),
          )
          ..whenCommand(
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
        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          transportMetrics: TransportMetrics(),
        );
        addTearDown(service.dispose);
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

        // Connect via a circuit multiaddr (so the multiaddr is in state), then
        // inject an inbound plaintext message from the long peer ID.
        bridge.onPeerConnected?.call(
          const p2p.ConnectionState(
            peerId: _longPeerId,
            multiaddrs: [_circuitMultiaddr],
            direction: 'outbound',
            status: 'connected',
          ),
        );
        bridge.onMessageReceived?.call(
          const ChatMessage(
            from: _longPeerId,
            to: 'self-peer',
            content: _secretContent,
            timestamp: '2026-01-01T00:00:00.000Z',
            isIncoming: true,
            transport: null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(events, isNotEmpty);

        // Allow-known-good: every detail key emitted by the transport arms must
        // belong to an explicit allow-list of non-identifying fields. Any
        // unexpected key fails the test, so a FUTURE transport/holepunch event
        // that adds e.g. 'remotePeer' or 'topic' is caught here even if its
        // value were to slip past the sanitizer. This deliberately replaces the
        // previous deny-known-bad approach (which only checked three fixtures +
        // the literal 'conversationId' key) — that approach would have passed an
        // identifier leaked under a new key.
        const allowedDetailKeys = <String>{
          // P2P_SERVICE_MESSAGE_RECEIVED + transport census/latency events.
          'from', // short prefix only (length-gated by the sanitizer)
          'isIncoming',
          'contentLength',
          'envelopeType',
          'streamClosed',
          'transport',
          'rung',
          'outcome',
          'latencyMs',
          'count',
          'deliveryMs',
          'relayState',
          'reason',
          // Node start / readiness lifecycle events fired during setup.
          'peerId', // sanitizer redacts full IDs; only 'self-peer' survives
          'autoRegister',
          'ok',
          'proofWindowId',
          'phase',
          'trigger',
        };
        // Identifier-shaped keys that must never appear on a transport event.
        const forbiddenDetailKeys = <String>{
          'conversationId',
          'remotePeer',
          'topic',
          'multiaddr',
          'to',
          'sender',
          'recipient',
        };

        for (final event in events) {
          final flat = _flatten(event);
          expect(
            flat.contains(_longPeerId),
            isFalse,
            reason: 'full peer ID leaked in event ${event['event']}: $flat',
          );
          expect(
            flat.contains('/p2p-circuit'),
            isFalse,
            reason: 'multiaddr leaked in event ${event['event']}: $flat',
          );
          expect(
            flat.contains(_secretContent),
            isFalse,
            reason: 'message content leaked in event ${event['event']}: $flat',
          );

          final detailKeys =
              (event['details'] as Map?)?.keys.map((k) => k.toString()) ??
              const <String>[];
          for (final key in detailKeys) {
            // Allow-known-good.
            expect(
              allowedDetailKeys.contains(key),
              isTrue,
              reason:
                  'event ${event['event']} emitted unexpected detail key '
                  '"$key"; add it to allowedDetailKeys only after confirming it '
                  'is non-identifying',
            );
            // Defense in depth: explicitly forbid identifier-shaped keys.
            expect(
              forbiddenDetailKeys.contains(key),
              isFalse,
              reason: 'event ${event['event']} leaked identifier key "$key"',
            );
          }
        }
      },
    );

    test(
      'NEGATIVE CONTROL: a fabricated identifying payload is actively redacted',
      () {
        // Emit a payload that DOES contain a long peerId, a multiaddr, and a
        // private key — the sanitizer must redact each.
        emitFlowEvent(
          layer: 'FL',
          event: 'TEST_TRANSPORT_LEAK_PROBE',
          details: {
            'peerId': _longPeerId,
            'addr': _circuitMultiaddr,
            'privateKey': 'deadbeefdeadbeefdeadbeef',
            'transport': 'relay', // a legit, non-identifying field survives
          },
        );

        expect(events, hasLength(1));
        final details = events.single['details'] as Map<String, dynamic>;
        // Long peerId key → redacted (value > 12 chars).
        expect(details['peerId'], '[redacted]');
        // Multiaddr value → redacted.
        expect(details['addr'].toString(), contains('[redacted'));
        expect(details['addr'].toString().contains('/p2p-circuit'), isFalse);
        // Private key → redacted.
        expect(details['privateKey'], '[redacted]');
        // The non-identifying transport label is preserved.
        expect(details['transport'], 'relay');
      },
    );

    test('a bare peer ID under an arbitrary (non-peerId) key is redacted', () {
      // A real base58 libp2p peer ID (valid alphabet, no 0/O/I/l) embedded in
      // a free-text value under a non-peerId key. A bare peer ID is not
      // multiaddr-shaped (no leading '/'), so redaction here must come from
      // the value-level base58 backstop, not the key name — covering future
      // events that emit a peer ID under e.g. 'remotePeer' or inside prose.
      const realPeerId = '12D3KooWBmwXbFvtKfYc2Ybgr9G2g4SjPmaC7nXh7sFkEvL2dRfQ';
      emitFlowEvent(
        layer: 'FL',
        event: 'TEST_BARE_PEER_ID_PROBE',
        details: {
          // Key-based redaction (remotePeer is a known peer-id key).
          'remotePeer': realPeerId,
          // Value-based redaction (note is NOT a peer-id key, so the base58
          // backstop must fire on the embedded token).
          'note': 'connected to $realPeerId via relay',
          'transport': 'relay',
        },
      );

      final details = events.single['details'] as Map<String, dynamic>;
      expect(details['remotePeer'].toString().contains(realPeerId), isFalse);
      expect(details['note'].toString().contains(realPeerId), isFalse);
      expect(details['note'].toString(), contains('[redacted'));
      expect(details['transport'], 'relay');
    });
  });

  group('PR1b — external getters / baselineReport carry no identifiers', () {
    test('baselineReport and stringified getters contain only aggregates', () {
      final metrics = TransportMetrics();
      // Drive a realistic mix; no identifier is ever passed to the recorders.
      metrics.recordTransport('direct');
      metrics.recordTransport('relay');
      metrics.recordTransport('relay');
      metrics.recordTransport('wifi');
      metrics.recordTransport(null); // → unknown
      metrics.recordRung('reuse');
      metrics.recordRung('relay');
      metrics.recordSendLatency(transport: 'direct', latencyMs: 42);
      metrics.recordSendLatency(transport: 'relay', latencyMs: 350);
      metrics.recordHolePunchAttempt();
      metrics.recordHolePunchSuccess();
      metrics.recordHolePunchFailure();
      metrics.recordRelayToDirectUpgrade();
      metrics.updateLanAvailability(
        const LanAvailabilitySnapshot(
          discoveryActive: true,
          discoveredPeerCount: 2,
        ),
      );

      final surfaces = <String>[
        metrics.baselineReport(),
        metrics.transportMix().toString(),
        metrics.rungDistribution().toString(),
        metrics.latencyByTransport().toString(),
        '${metrics.lanAvailability.discoveryActive} '
            '${metrics.lanAvailability.discoveredPeerCount}',
      ];

      for (final surface in surfaces) {
        // No identifier substrings of any kind.
        expect(surface.contains(_longPeerId), isFalse);
        expect(surface.contains('/p2p-circuit'), isFalse);
        expect(surface.contains('/ip4/'), isFalse);
        expect(surface.contains(_secretContent), isFalse);
      }

      // The baseline report is composed only of the known vocabulary:
      // bucket names, rung names, integers, %, ms, and the LAN line.
      final report = metrics.baselineReport();
      expect(report, contains('Transport mix'));
      expect(report, contains('Median latency'));
      expect(report, contains('Fallback rungs'));
      expect(report, contains('LAN: discovery active, 2 peers'));
      expect(
        report,
        contains(
          'Hole punch (attempt/success/fail): 1/1/1, '
          'relay->direct upgrades: 1',
        ),
      );
    });

    test('P4 suspected-permission-denied surface carries no identifiers', () {
      final metrics = TransportMetrics();
      metrics.recordTransport('direct');
      metrics.updateLanAvailability(
        const LanAvailabilitySnapshot(
          discoveryActive: true,
          discoveredPeerCount: 0,
          suspectedPermissionDenied: true,
        ),
      );

      final surfaces = <String>[
        metrics.baselineReport(),
        '${metrics.lanAvailability.discoveryActive} '
            '${metrics.lanAvailability.discoveredPeerCount} '
            '${metrics.lanAvailability.suspectedPermissionDenied}',
      ];
      for (final surface in surfaces) {
        expect(surface.contains(_longPeerId), isFalse);
        expect(surface.contains('/p2p-circuit'), isFalse);
        expect(surface.contains('/ip4/'), isFalse);
        expect(surface.contains(_secretContent), isFalse);
      }
      // The heuristic surfaces only as the aggregate "suspected-denied" token.
      expect(metrics.baselineReport(), contains('perm: suspected-denied'));
    });

    test('the recorders accept no identifier-typed parameters', () {
      // Structural guard: recordTransport/recordRung take only the transport
      // string and sendPath label; recordSendLatency takes a transport + ms.
      // None of these can carry a peer ID, content, or conversation ID — this
      // test documents that contract by exercising them with only such values
      // and confirming the aggregate surface stays identifier-free.
      final metrics = TransportMetrics();
      metrics.recordTransport('direct');
      metrics.recordRung('reuse');
      metrics.recordSendLatency(transport: 'direct', latencyMs: 10);
      expect(metrics.totalTransportSamples, 1);
      expect(metrics.baselineReport().contains(_longPeerId), isFalse);
    });
  });
}
