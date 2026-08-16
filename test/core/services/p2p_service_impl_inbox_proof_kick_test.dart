/// Plan 216 — Cold-start "connecting"→"online" inbox-proof kick on send-proof
/// store.
///
/// Locks the missing send→inbox readiness mirror (INV-1..INV-3 of the 216 TDD
/// plan): when the proactive send-proof stores in an active readiness window,
/// a targeted inbox drain is kicked immediately — guarded on
/// `!inboxCapabilityReady` — so the badge flips connecting→online off the store
/// instead of waiting for the first 30s `Timer.periodic` health-check tick.
///
/// The send side already mirrors inbox→send (`_recordSuccessfulInboxProof`
/// tail-calls `_retryProactiveSendProofIfNeeded('inbox_proof_success')`); this
/// suite locks the missing other half.
///
/// Own fake-bridge copy of the `p2p_service_impl_health_drain_test.dart`
/// pattern — deliberately a separate file (Scope Guard: do not edit the dirty
/// `p2p_service_impl_test.dart`). `startNodeCore` alone opens the readiness
/// window WITHOUT starting the health-check timer / startup drain / warm
/// background, so every drain observed here is attributable to a driven event —
/// no 30s timer is ever advanced.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../../../integration_test/_support/node_readiness.dart';

/// Captures [FLOW] log lines emitted during [action] and returns parsed events.
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

/// A fake bridge that records commands and returns configurable responses.
class _FakeBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)>
  _handlers = {};
  final List<String> calledCommands = [];
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

    calledCommands.add(cmd);

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

String _statusJson({required String relayState}) {
  return jsonEncode({
    'ok': true,
    'peerId': 'self-peer',
    'isStarted': true,
    'listenAddresses': <String>[],
    'circuitAddresses': <String>[],
    'connections': <dynamic>[],
    'relayState': relayState,
    'healthyRelayCount': relayState == 'online' ? 1 : 0,
    'watchdogRestartCount': 0,
  });
}

void main() {
  late _FakeBridge bridge;
  late P2PServiceImpl service;

  // Models the device send/inbox asymmetry on the relay-became-healthy edge:
  // before the reservation opens the relay serves neither store nor retrieve;
  // once it is healthy both succeed. Both the send-probe store and the inbox
  // drain consult this single flag.
  late bool relayHealthy;

  setUp(() {
    bridge = _FakeBridge();
    relayHealthy = false;

    bridge.whenCommand(
      'node:start',
      (_) => _statusJson(relayState: relayHealthy ? 'online' : 'connecting'),
    );
    bridge.whenCommand(
      'node:status',
      (_) => _statusJson(relayState: relayHealthy ? 'online' : 'connecting'),
    );

    // The proactive send-proof probe stores only once the relay is reachable.
    bridge.whenCommand(
      'inbox:store',
      (_) => jsonEncode(
        relayHealthy ? {'ok': true} : {'ok': false, 'errorCode': 'NO_RELAY'},
      ),
    );

    // The inbox drain (retrieve) likewise fails before the relay is healthy.
    bridge.whenCommand('inbox:retrieve_pending', (payload) {
      expect(payload?['custodyContract'], ackOrExpiryInboxCustodyContract);
      return jsonEncode(
        relayHealthy
            ? {
                'ok': true,
                'custodyContract': payload?['custodyContract'],
                'messages': <dynamic>[],
                'hasMore': false,
              }
            : {'ok': false, 'errorCode': 'NO_RELAY'},
      );
    });

    bridge.whenCommand('inbox:ack', (payload) {
      expect(payload?['custodyContract'], ackOrExpiryInboxCustodyContract);
      return jsonEncode({
        'ok': true,
        'acked': 1,
        'custodyContract': payload?['custodyContract'],
      });
    });
    // Recovery never truthfully reconnects in these tests — the relay comes
    // back via the relay:state push (autorelay), not a Dart relay:reconnect.
    bridge.whenCommand(
      'relay:reconnect',
      (_) => jsonEncode({
        'ok': true,
        'success': false,
        'errorCode': 'NO_CIRCUIT',
        'recoveryMode': 'watchdog_restart',
      }),
    );

    service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
  });

  tearDown(() {
    service.dispose();
  });

  int drains() =>
      bridge.calledCommands.where((c) => c == 'inbox:retrieve_pending').length;
  int stores() => bridge.calledCommands.where((c) => c == 'inbox:store').length;
  int reconnects() =>
      bridge.calledCommands.where((c) => c == 'relay:reconnect').length;

  /// Pumps the microtask/timer queue until [condition] holds or the bound is
  /// hit. The fake bridge is synchronous, so a handful of turns settles every
  /// unawaited send-proof/drain chain; the bound only caps the RED case where
  /// the condition never becomes true.
  Future<void> pumpUntil(
    bool Function() condition, {
    int maxIterations = 80,
  }) async {
    for (var i = 0; i < maxIterations && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> settle({int iterations = 20}) async {
    for (var i = 0; i < iterations; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
    // TC-01 (INV-1)
    'send-proof store kicks an immediate inbox drain — inboxCapabilityReady '
    'flips without a periodic health-check tick',
    () async {
      // Cold start with the relay NOT yet healthy: the readiness window opens
      // (badge=connecting) but neither proof lands — the device state at t+0
      // before the relay reservation completes.
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      expect(
        service.currentState.inboxCapabilityReady,
        isFalse,
        reason: 'fixture: no drain has proven inbox yet',
      );
      expect(
        service.currentState.sendCapabilityReady,
        isFalse,
        reason: 'fixture: no send proof yet',
      );
      expect(
        service.currentState.badgeReadinessState,
        BadgeReadinessState.connecting,
        reason: 'fixture: cold start sits on connecting',
      );

      bridge.calledCommands.clear();

      // The relay reservation opens: relay:state pushes online. This is the
      // earliest Dart-visible "became healthy" signal (same Go tick as
      // reservation-open) and it fires the proactive SEND proof, which stores.
      relayHealthy = true;

      final events = await _captureFlowEvents(() async {
        bridge.onRelayStateChanged?.call({
          'relayState': 'online',
          'healthyRelayCount': 1,
        });
        await pumpUntil(() => service.currentState.inboxCapabilityReady);
      });

      // The send proof stored (the probe envelope is now retrievable)...
      expect(
        stores(),
        1,
        reason: 'the became-healthy push stored the send probe once',
      );
      // ...and the store kicked exactly one inbox drain that proved inbox.
      expect(
        service.currentState.inboxCapabilityReady,
        isTrue,
        reason:
            'INV-1: the send-proof store must kick an inbox drain that '
            'proves inbox WITHOUT waiting for a 30s health-check tick',
      );
      expect(
        isSendableBadgeState(service.currentState),
        isTrue,
        reason: 'the badge must leave connecting once both proofs land',
      );
      expect(
        drains(),
        1,
        reason: 'exactly one drain, attributable to the send-proof store',
      );

      // Distinct-event discriminator: the proof came from the store seam, not a
      // health-check tick — no immediate health check / recovery ran, and no
      // relay:reconnect was issued in the window.
      expect(
        reconnects(),
        0,
        reason: 'no relay:reconnect — no health/recovery machinery ran',
      );
      expect(
        events.where(
          (e) =>
              e['event'] == 'P2P_SERVICE_IMMEDIATE_HEALTH_CHECK_BEGIN' ||
              e['event'] == 'RELAY_RECOVERY_START',
        ),
        isEmpty,
        reason: 'the inbox proof must be driven by the store seam, not a tick',
      );
    },
  );

  test(
    // TC-02 (INV-2)
    'inbox kick is a no-op when inbox was already proven in the window '
    '(guarded on !inboxCapabilityReady)',
    () async {
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      relayHealthy = true;

      // The opportunistic/startup drain proves INBOX first, while SEND is still
      // unproven — the fast-relay ordering the guard must tolerate (this is the
      // TC-05 sim shape: startup drain wins the race before the send proof).
      await service.drainOfflineInbox();
      await pumpUntil(() => service.currentState.inboxCapabilityReady);
      expect(
        service.currentState.inboxCapabilityReady,
        isTrue,
        reason: 'fixture: inbox proven ahead of send',
      );
      expect(
        service.currentState.sendCapabilityReady,
        isFalse,
        reason: 'fixture: send NOT yet proven',
      );

      // The inbox-success callback is allowed to start its send proof
      // immediately and does so unawaited. Do not clear command history here:
      // that races the already-started store and can erase the only proof from
      // the observation window. The invariant is total work in this readiness
      // window: one initial drain and one send store, with no second drain.
      bridge.onRelayStateChanged?.call({
        'relayState': 'online',
        'healthyRelayCount': 1,
      });
      await pumpUntil(() => service.currentState.sendCapabilityReady);
      // Give any (incorrectly un-guarded) kick a chance to fire a drain.
      await settle();

      expect(
        service.currentState.sendCapabilityReady,
        isTrue,
        reason: 'the became-healthy push proved send',
      );
      expect(
        stores(),
        1,
        reason: 'the send probe stored exactly once in the window',
      );
      expect(
        drains(),
        1,
        reason:
            'INV-2: the kick is guarded on !inboxCapabilityReady — with '
            'inbox already proven the initial drain must be the only drain',
      );
      expect(
        service.currentState.inboxCapabilityReady,
        isTrue,
        reason: 'inbox stays proven',
      );
    },
  );

  test(
    // TC-03 (INV-3)
    'a fresh readiness window (offline→online recovery) re-arms the inbox kick',
    () async {
      // Window 1: prove both proofs via the store-seam kick.
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      relayHealthy = true;
      bridge.onRelayStateChanged?.call({
        'relayState': 'online',
        'healthyRelayCount': 1,
      });
      await pumpUntil(() => service.currentState.inboxCapabilityReady);
      expect(
        service.currentState.inboxCapabilityReady,
        isTrue,
        reason: 'window 1: inbox proven via the kick',
      );

      // Relay drops: a fresh readiness window opens and both proofs reset. The
      // degradation branch also runs performImmediateHealthCheck, but while the
      // relay is down it can prove nothing (store & retrieve both fail).
      relayHealthy = false;
      bridge.onRelayStateChanged?.call({
        'relayState': 'connecting',
        'healthyRelayCount': 0,
        'reason': 'relay_disconnected',
      });
      await pumpUntil(() => !service.currentState.inboxCapabilityReady);
      expect(
        service.currentState.inboxCapabilityReady,
        isFalse,
        reason: 'the new window reset the inbox proof',
      );
      expect(
        service.currentState.sendCapabilityReady,
        isFalse,
        reason: 'the new window reset the send proof',
      );

      // Let the degraded-phase immediate health check fully settle so no send
      // proof is left in flight into the recovery, then start a clean count.
      await settle();
      bridge.calledCommands.clear();

      // Relay comes back: the became-healthy push re-fires the send proof,
      // which stores and must RE-ARM the inbox kick in the NEW window.
      relayHealthy = true;
      bridge.onRelayStateChanged?.call({
        'relayState': 'online',
        'healthyRelayCount': 1,
      });
      await pumpUntil(() => service.currentState.inboxCapabilityReady);

      expect(
        service.currentState.inboxCapabilityReady,
        isTrue,
        reason:
            'INV-3: a fresh window must re-arm the kick — the store in the '
            'new window proves inbox again without a periodic tick',
      );
      expect(
        isSendableBadgeState(service.currentState),
        isTrue,
        reason: 'the badge is online again after recovery',
      );
      expect(
        drains(),
        greaterThanOrEqualTo(1),
        reason: 'the re-armed kick drained again in the new window',
      );
    },
  );
}
