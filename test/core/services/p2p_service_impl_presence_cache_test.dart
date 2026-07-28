import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

// FDC-08 C3/C4/C3b — the client-side presence cache + move-feature gate on
// P2PServiceImpl.lookupRelayPresence. The cache TTL eviction mirrors
// lastKnownGoodTransport (clock.now()-based, withClock-testable).

class _CountingBridge extends Bridge {
  String presence = 'reachable';
  Object? ageMs = 1200;
  int presenceCallCount = 0;
  Completer<String>? presenceResponseGate;

  // FDC-09 presence_set (write twin).
  int presenceSetCallCount = 0;
  final List<Map<String, dynamic>> presenceSetPayloads = [];
  // Response the fake relay returns for relay:presence_set. Default: accepted.
  Map<String, dynamic> presenceSetResponse = const {'ok': true};

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
    if (req['cmd'] == 'relay:presence_get') {
      presenceCallCount++;
      final gate = presenceResponseGate;
      if (gate != null) return await gate.future;
      return jsonEncode({'ok': true, 'presence': presence, 'ageMs': ageMs});
    }
    if (req['cmd'] == 'relay:presence_set') {
      presenceSetCallCount++;
      presenceSetPayloads.add(Map<String, dynamic>.from(req['payload'] as Map));
      return jsonEncode(presenceSetResponse);
    }
    return jsonEncode({'ok': false, 'errorCode': 'UNHANDLED'});
  }
}

void main() {
  late _CountingBridge bridge;
  late InMemoryInboxStagingRepository staging;
  late P2PServiceImpl service;

  setUp(() {
    flowEventLoggingEnabled = false;
    debugSetFlowEventSink(null);
    bridge = _CountingBridge();
    staging = InMemoryInboxStagingRepository();
    service = P2PServiceImpl(bridge: bridge, inboxStagingRepository: staging);
  });

  tearDown(() {
    service.dispose();
    debugSetFlowEventSink(null);
  });

  // C3 — short-TTL cache hit avoids a second bridge call; re-queries past TTL.
  test(
    'lookupRelayPresence caches within TTL and re-queries after expiry',
    () async {
      var now = DateTime.utc(2026, 6, 27, 12);
      await withClock(Clock(() => now), () async {
        final r1 = await service.lookupRelayPresence('peer-x');
        expect(r1, RelayPresence.reachable);

        // Second call inside the TTL is served from cache (no bridge call).
        final r2 = await service.lookupRelayPresence('peer-x');
        expect(r2, RelayPresence.reachable);
        expect(bridge.presenceCallCount, 1);

        // Past the TTL the entry is re-queried.
        now = now.add(const Duration(seconds: 13));
        final r3 = await service.lookupRelayPresence('peer-x');
        expect(r3, RelayPresence.reachable);
        expect(bridge.presenceCallCount, 2);
      });
    },
  );

  // C4 — an expired `reachable` entry is evicted on read; never trusted stale.
  test(
    'expired presence entry is evicted on read (never a stale reachable)',
    () async {
      var now = DateTime.utc(2026, 6, 27, 12);
      await withClock(Clock(() => now), () async {
        bridge.presence = 'reachable';
        expect(
          await service.lookupRelayPresence('peer-y'),
          RelayPresence.reachable,
        );

        // The peer goes offline; advance past the TTL; the relay now says so.
        bridge.presence = 'unreachable';
        now = now.add(const Duration(seconds: 13));

        final r = await service.lookupRelayPresence('peer-y');
        expect(
          r,
          isNot(RelayPresence.reachable),
        ); // the stale reachable is gone
        expect(r, RelayPresence.unreachable); // re-queried for the truth
        expect(bridge.presenceCallCount, 2);
      });
    },
  );

  test(
    'DTR-17 late presence completion cannot repopulate after dispose',
    () async {
      final gate = Completer<String>();
      bridge.presenceResponseGate = gate;

      final lookup = service.lookupRelayPresence('late-peer');
      while (bridge.presenceCallCount == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      service.dispose();
      gate.complete(
        jsonEncode({'ok': true, 'presence': 'reachable', 'ageMs': 1}),
      );

      expect(await lookup, RelayPresence.unknown);
      expect(
        await service.lookupRelayPresence('late-peer'),
        RelayPresence.unknown,
      );
      expect(bridge.presenceCallCount, 1);
    },
  );

  // C3b — a paused account-move makes NO bridge call and returns unknown.
  test(
    'lookupRelayPresence is gated by _allowsAccountNetworkSideEffects',
    () async {
      final gatedService = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: staging,
        // Migration paused / fail-closed: deny all network side-effects.
        accountMigrationNetworkGate:
            ({String? peerId, required String operation}) async => false,
      );
      addTearDown(gatedService.dispose);

      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(
        (p) => flowEvents.add(Map<String, dynamic>.from(p)),
      );

      final r = await gatedService.lookupRelayPresence('peer-z');

      expect(r, RelayPresence.unknown);
      expect(bridge.presenceCallCount, 0); // gate-blocked => zero bridge calls

      final blocked = flowEvents.where(
        (e) => e['event'] == 'P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED',
      );
      expect(blocked, isNotEmpty);
      expect(
        (blocked.first['details'] as Map)['operation'],
        'p2p_get_presence',
      );
    },
  );

  // FDC-09 happy path — setPresence sends the self-publish and reports published.
  test('setPresence publishes foreground/background to the relay', () async {
    final r = await service.setPresence('foreground', 180000);
    expect(r, PresenceSetResult.published);
    expect(bridge.presenceSetCallCount, 1);
    expect(bridge.presenceSetPayloads.single['state'], 'foreground');
    expect(bridge.presenceSetPayloads.single['ttlMs'], 180000);
  });

  // TC-09-07 (move-feature safety; mirrors C3b) — a paused account-move makes
  // NO presence_set bridge call on EITHER state and returns `blocked`, emitting
  // P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED{operation: p2p_set_presence}.
  // A moving device must not announce itself reachable while ceding the account.
  test(
    'TC-09-07: setPresence is gated by _allowsAccountNetworkSideEffects',
    () async {
      final gatedService = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: staging,
        accountMigrationNetworkGate:
            ({String? peerId, required String operation}) async => false,
      );
      addTearDown(gatedService.dispose);

      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(
        (p) => flowEvents.add(Map<String, dynamic>.from(p)),
      );

      // Both the pause (background) AND resume (foreground) paths must no-op.
      expect(
        await gatedService.setPresence('background', 180000),
        PresenceSetResult.blocked,
      );
      expect(
        await gatedService.setPresence('foreground', 180000),
        PresenceSetResult.blocked,
      );

      expect(
        bridge.presenceSetCallCount,
        0,
      ); // gate-blocked => zero bridge calls

      final blocked = flowEvents.where(
        (e) => e['event'] == 'P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED',
      );
      expect(blocked, isNotEmpty);
      expect(
        (blocked.first['details'] as Map)['operation'],
        'p2p_set_presence',
      );
    },
  );

  // TC-09-08 (impl half / NET-REL-07) — an OLD relay's "Unknown action:
  // presence_set" maps to PresenceSetResult.unsupported (skip), never a hard
  // failure or retry. Delivery is never affected (presence is a HINT).
  test(
    'TC-09-08: old relay Unknown action maps setPresence to unsupported',
    () async {
      bridge.presenceSetResponse = {
        'status': 'ERROR',
        'error': 'Unknown action: presence_set',
      };
      final r = await service.setPresence('foreground', 180000);
      expect(r, PresenceSetResult.unsupported);
      expect(bridge.presenceSetCallCount, 1); // tried once, not retried
    },
  );
}
