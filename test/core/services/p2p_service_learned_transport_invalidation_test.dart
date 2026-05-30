/// NET-REL-05 P3 — learned/sticky transport invalidation, tested DIRECTLY
/// against the REAL `P2PServiceImpl` (NOT the integration fake in
/// `fake_p2p_service_integration.dart`, which re-implements the same logic and
/// therefore cannot catch a regression in production).
///
/// These tests record a learned transport on the real service, fire each
/// invalidation trigger through the real bridge callbacks (`onPeerDisconnected`,
/// `onRelayStateChanged`, `onAddressesUpdated`), and assert
/// `lastKnownGoodTransport` returns null afterward. A TTL-expiry case drives the
/// read-time eviction inside `lastKnownGoodTransport` via `withClock`.
///
/// Mutation evidence (recorded in the remediation step): removing the
/// `_learnedTransport.remove(conn.peerId)` line in `_handlePeerDisconnected`
/// turns the disconnect test RED; restoring it returns GREEN.
library;

import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

// ---------------------------------------------------------------------------
// Fake Bridge — minimal, only what P2PServiceImpl needs to start a node and
// expose the push callbacks we drive.
// ---------------------------------------------------------------------------

class _FakeBridge extends Bridge {
  /// Mutable so a test can flip the node into a healthy-relay state.
  Map<String, dynamic> statusResponse = {
    'ok': true,
    'peerId': 'test-peer-id',
    'isStarted': true,
    'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
    'circuitAddresses': <String>[],
    'connections': <Map<String, dynamic>>[],
  };

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

  @override
  Future<String> send(String message) async {
    final req = jsonDecode(message) as Map<String, dynamic>;
    final cmd = req['cmd'] as String;
    switch (cmd) {
      case 'node:start':
      case 'node:status':
        return jsonEncode(statusResponse);
      case 'inbox:retrieve':
      case 'inbox:retrieve_pending':
        return jsonEncode({'ok': true, 'messages': <Map<String, dynamic>>[]});
      case 'inbox:ack':
        return jsonEncode({'ok': true, 'acked': 0});
      default:
        return jsonEncode({'ok': true});
    }
  }
}

void main() {
  const peerId = '12D3KooWBobPeerIdxxxxxxxxxxxxxxx0002';

  late _FakeBridge bridge;
  late P2PServiceImpl service;

  setUp(() async {
    bridge = _FakeBridge();
    service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
    await service.startNodeCore('AAAA', 'test-peer-id');
  });

  tearDown(() {
    service.dispose();
  });

  // -------------------------------------------------------------------------
  // Sanity: recording + reading round-trips on the REAL service. Without this
  // baseline, an invalidation test could go green simply because nothing was
  // ever learned. (No _localP2P is injected, so isLocalPeer() is false; we use
  // 'direct'/'relay' which are not gated on live LAN visibility.)
  // -------------------------------------------------------------------------
  test('recordSuccessfulTransport then lastKnownGoodTransport round-trips', () {
    expect(service.lastKnownGoodTransport(peerId), isNull);
    service.recordSuccessfulTransport(peerId, 'direct');
    expect(service.lastKnownGoodTransport(peerId), 'direct');
  });

  test('ignores a non-live transport label (inbox is a custody handoff)', () {
    service.recordSuccessfulTransport(peerId, 'inbox');
    expect(service.lastKnownGoodTransport(peerId), isNull);
  });

  // -------------------------------------------------------------------------
  // Trigger 1: peer disconnect (_handlePeerDisconnected, ~:2618).
  // -------------------------------------------------------------------------
  test('disconnect invalidates the learned transport', () {
    service.recordSuccessfulTransport(peerId, 'direct');
    expect(service.lastKnownGoodTransport(peerId), 'direct');

    bridge.onPeerDisconnected!(
      const ConnectionState(
        peerId: peerId,
        multiaddrs: [],
        direction: 'outbound',
        status: 'disconnected',
      ),
    );

    expect(
      service.lastKnownGoodTransport(peerId),
      isNull,
      reason: 'a disconnected peer\'s learned transport is no longer '
          'trustworthy and must be dropped',
    );
  });

  test('disconnect of a DIFFERENT peer leaves the learned transport intact', () {
    service.recordSuccessfulTransport(peerId, 'relay');

    bridge.onPeerDisconnected!(
      const ConnectionState(
        peerId: 'some-other-peer',
        multiaddrs: [],
        direction: 'outbound',
        status: 'disconnected',
      ),
    );

    // Negative control: invalidation must be keyed by peerId, not blanket.
    expect(service.lastKnownGoodTransport(peerId), 'relay');
  });

  // -------------------------------------------------------------------------
  // Trigger 2a: relay-health transition via the MODERN relay:state push
  // (_handleRelayStateChanged). This is the path the R2 production fix added.
  // -------------------------------------------------------------------------
  test('relay:state health transition (offline->online) drops non-local '
      'learned transports', () {
    service.recordSuccessfulTransport(peerId, 'relay');
    expect(service.lastKnownGoodTransport(peerId), 'relay');

    // Node starts with circuitAddresses empty + no relayState => not healthy.
    // Push an 'online' relay:state — a was!=now health transition.
    bridge.onRelayStateChanged!({'relayState': 'online', 'healthyRelayCount': 1});

    expect(
      service.lastKnownGoodTransport(peerId),
      isNull,
      reason: 'a relay-health transition delivered via relay:state must drop '
          'non-local learned transports (direct/relay may no longer be '
          'reachable)',
    );
  });

  test('relay:state with NO health transition keeps the learned transport', () {
    // Bring the node online first (transition offline->online clears).
    bridge.onRelayStateChanged!({'relayState': 'online', 'healthyRelayCount': 1});
    // NOW learn — while already healthy.
    service.recordSuccessfulTransport(peerId, 'relay');
    expect(service.lastKnownGoodTransport(peerId), 'relay');

    // A second 'online' push with a different healthyRelayCount changes state
    // meaningfully but is NOT a health transition (healthy->healthy).
    bridge.onRelayStateChanged!({'relayState': 'online', 'healthyRelayCount': 2});

    // Negative control: only a was!=now health transition invalidates.
    expect(service.lastKnownGoodTransport(peerId), 'relay');
  });

  // -------------------------------------------------------------------------
  // Trigger 2b: relay-health transition via the LEGACY addresses:updated push
  // (_handleAddressesUpdated, ~:2647-2648).
  // -------------------------------------------------------------------------
  test('addresses:updated health transition drops non-local learned '
      'transports', () {
    service.recordSuccessfulTransport(peerId, 'direct');
    expect(service.lastKnownGoodTransport(peerId), 'direct');

    // Was unhealthy (empty circuit), now healthy (a circuit address appears).
    bridge.onAddressesUpdated!(
      ['/ip4/127.0.0.1/tcp/1234'],
      ['/dns4/relay.example.com/tcp/4001/p2p/QmRelay/p2p-circuit'],
    );

    expect(service.lastKnownGoodTransport(peerId), isNull);
  });

  // -------------------------------------------------------------------------
  // Trigger 3: TTL expiry (read-time eviction in lastKnownGoodTransport).
  // 'direct'/'relay' use a 10min TTL; advance the clock past it.
  // -------------------------------------------------------------------------
  test('TTL expiry evicts a learned non-local transport at read time', () {
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);

    withClock(Clock.fixed(t0), () {
      service.recordSuccessfulTransport(peerId, 'relay');
      // Fresh: still returned.
      expect(service.lastKnownGoodTransport(peerId), 'relay');
    });

    // Just inside the 10min TTL — still valid.
    withClock(Clock.fixed(t0.add(const Duration(minutes: 9, seconds: 59))), () {
      expect(service.lastKnownGoodTransport(peerId), 'relay');
    });

    // Past the 10min TTL — read-time eviction returns null.
    withClock(Clock.fixed(t0.add(const Duration(minutes: 10, seconds: 1))), () {
      expect(
        service.lastKnownGoodTransport(peerId),
        isNull,
        reason: 'a learned transport older than its TTL must be evicted on '
            'read and return null',
      );
    });
  });

  test('a re-read after TTL eviction stays null (entry was removed)', () {
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    withClock(Clock.fixed(t0), () {
      service.recordSuccessfulTransport(peerId, 'direct');
    });
    withClock(Clock.fixed(t0.add(const Duration(minutes: 11))), () {
      expect(service.lastKnownGoodTransport(peerId), isNull);
    });
    // Back at t0+11 again (no clock => DateTime.now(), well past TTL): the
    // entry was removed on the first stale read, so it stays null.
    expect(service.lastKnownGoodTransport(peerId), isNull);
  });
}
