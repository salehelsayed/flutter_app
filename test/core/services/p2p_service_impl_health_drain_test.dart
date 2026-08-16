/// Plan 189 — Degraded-relay inbox-drain starvation + no-exit restart loop.
///
/// Locks the health-check drain invariants (INV-1..INV-4 of the 189 TDD plan):
/// every health-check tick issues a drain regardless of branch/outcome,
/// `phase=recovered` is truthful, and failed recoveries back off while drains
/// never do. Own fake-bridge copy of the p2p_service_impl_test.dart pattern —
/// deliberately a separate file (Scope Guard: do not edit that suite).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

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

String _statusJson({
  required String relayState,
  List<String> circuitAddresses = const [],
  int watchdogRestartCount = 0,
}) {
  return jsonEncode({
    'ok': true,
    'peerId': 'self-peer',
    'isStarted': true,
    'listenAddresses': <String>[],
    'circuitAddresses': circuitAddresses,
    'connections': <dynamic>[],
    'relayState': relayState,
    'healthyRelayCount': relayState == 'online' ? 1 : 0,
    'watchdogRestartCount': watchdogRestartCount,
  });
}

/// Sequenced node:status responses: a queue consumed one entry per poll, then
/// the last consumed entry stays sticky. Lets a single recovery tick see
/// (degraded initial poll, online retry poll) without call-index bookkeeping.
class _StatusFeed {
  final List<String> _queue = [];
  String sticky;

  _StatusFeed({required this.sticky});

  void enqueue(List<String> responses) => _queue.addAll(responses);

  String next() {
    if (_queue.isNotEmpty) {
      sticky = _queue.removeAt(0);
    }
    return sticky;
  }
}

void main() {
  late _FakeBridge bridge;
  late P2PServiceImpl service;
  late _StatusFeed statusFeed;

  setUp(() {
    bridge = _FakeBridge();
    statusFeed = _StatusFeed(sticky: _statusJson(relayState: 'online'));
    bridge.whenCommand('node:status', (_) => statusFeed.next());
    bridge.whenCommand('node:start', (_) => _statusJson(relayState: 'online'));
    bridge.whenCommand(
      'inbox:retrieve_pending',
      (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
    );
    bridge.whenCommand(
      'inbox:ack',
      (_) => jsonEncode({'ok': true, 'acked': 1}),
    );
    bridge.whenCommand(
      'relay:reconnect',
      (_) => jsonEncode({'ok': true, 'recoveryMode': 'in_place'}),
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
  int reconnects() =>
      bridge.calledCommands.where((c) => c == 'relay:reconnect').length;

  /// Starts the node online and runs one healthy tick so `_hasEverBeenOnline`
  /// latches (the incident precondition: the device HAS been online, then the
  /// relay chronically degrades). Leaves exactly 1 drain on the counters.
  Future<void> startAndLatchOnline() async {
    await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
    await service.performImmediateHealthCheck();
    expect(drains(), 1, reason: 'fixture: healthy tick drains exactly once');
    bridge.calledCommands.clear();
  }

  test(
    // TC-189-01 (INV-1)
    'recovery tick still drains — 3 degraded ticks issue 3 inbox:retrieve_pending',
    () async {
      await startAndLatchOnline();
      statusFeed.sticky = _statusJson(relayState: 'degraded');

      final events = await _captureFlowEvents(() async {
        for (var i = 0; i < 3; i++) {
          await service.performImmediateHealthCheck();
        }
      });

      final recoveryStarts = events
          .where((e) => e['event'] == 'RELAY_RECOVERY_START')
          .length;
      expect(
        recoveryStarts,
        3,
        reason:
            'discriminator: every tick must have taken the recovery '
            'branch, not the healthy path',
      );
      expect(
        drains(),
        greaterThanOrEqualTo(3),
        reason:
            'INV-1: each recovery tick must issue an inbox drain '
            '(HEAD returns at the recovery branch before the drain)',
      );
    },
  );

  test(
    // TC-189-02 (INV-1)
    'drain fires even when recovery fails (reconnect error, retry still degraded)',
    () async {
      bridge.whenCommand(
        'relay:reconnect',
        (_) => jsonEncode({'ok': false, 'errorCode': 'RELAY_ERROR'}),
      );
      await startAndLatchOnline();
      statusFeed.sticky = _statusJson(relayState: 'degraded');

      await service.performImmediateHealthCheck();

      expect(reconnects(), 1, reason: 'fixture: the recovery attempt ran');
      expect(
        drains(),
        greaterThanOrEqualTo(1),
        reason:
            'INV-1: a failed recovery must not starve the drain — a '
            'degraded relay session can still serve retrieve_pending',
      );
    },
  );

  test(
    // TC-189-03 (INV-1, error path)
    'drain fires and tick survives when relay:reconnect throws',
    () async {
      bridge.whenCommand(
        'relay:reconnect',
        (_) => throw StateError('bridge crash mid-recovery'),
      );
      await startAndLatchOnline();
      statusFeed.sticky = _statusJson(relayState: 'degraded');

      await service.performImmediateHealthCheck();
      expect(
        drains(),
        greaterThanOrEqualTo(1),
        reason: 'INV-1: a throwing recovery must not starve the drain',
      );

      // The periodic loop must survive: a subsequent tick still runs fully.
      final before = drains();
      await service.performImmediateHealthCheck();
      expect(
        drains(),
        greaterThan(before),
        reason: 'subsequent tick must still run after the exception tick',
      );
    },
  );

  test(
    // TC-189-04 (push funnel)
    'degraded relay:state push → immediate health check → drain',
    () async {
      await startAndLatchOnline();
      statusFeed.sticky = _statusJson(relayState: 'degraded');

      bridge.onRelayStateChanged?.call({
        'relayState': 'degraded',
        'healthyRelayCount': 0,
        'watchdogRestartCount': 0,
        'reason': 'relay_disconnected',
      });
      // The push handler fires performImmediateHealthCheck unawaited — settle.
      for (var i = 0; i < 50 && reconnects() < 1; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(
        reconnects(),
        greaterThanOrEqualTo(1),
        reason: 'fixture: the push must have funneled into recovery',
      );
      // Give the post-recovery drain a moment (the immediate check is
      // unawaited from the push handler).
      for (var i = 0; i < 50 && drains() < 1; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        drains(),
        greaterThanOrEqualTo(1),
        reason:
            'INV-1: performImmediateHealthCheck inherits the per-tick '
            'drain guarantee',
      );
    },
  );

  test(
    // TC-189-05 (preservation — GREEN on HEAD and must stay GREEN)
    'healthy tick drains exactly once; concurrent manual drain coalesces',
    () async {
      await startAndLatchOnline();

      // Slow retrieve: hold the in-flight drain open while a second drain
      // arrives; the coalescing guard must keep a single in-flight retrieve.
      final gate = Completer<void>();
      bridge.whenCommand('inbox:retrieve_pending', (_) async {
        await gate.future;
        return jsonEncode({'ok': true, 'messages': [], 'hasMore': false});
      });

      final first = service.drainOfflineInbox();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final second = service.drainOfflineInbox();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        drains(),
        1,
        reason: 'coalescing: concurrent drains share ONE in-flight retrieve',
      );

      gate.complete();
      await first;
      await second;
      expect(
        drains(),
        1,
        reason: 'the coalesced caller must not issue a second retrieve',
      );
    },
  );

  test(
    // TC-189-06 (outcome bound, const half — device half is the runsheet)
    'health check cadence stays 30s so the drain bound stays one interval',
    () {
      expect(
        P2PServiceImpl.healthCheckInterval,
        const Duration(seconds: 30),
        reason:
            'TC-189-06: store→ack ≤ ~35s derives from drain-per-tick '
            '(TC-189-01) + this cadence',
      );
    },
  );

  test(
    // TC-189-07 (starvation lock)
    'starvation lock: 5 consecutive degraded ticks → 5 recovery starts AND ≥5 drains',
    () async {
      await startAndLatchOnline();
      statusFeed.sticky = _statusJson(relayState: 'degraded');

      final events = await _captureFlowEvents(() async {
        for (var i = 0; i < 5; i++) {
          await service.performImmediateHealthCheck();
        }
      });

      final recoveryStarts = events
          .where((e) => e['event'] == 'RELAY_RECOVERY_START')
          .length;
      expect(recoveryStarts, 5, reason: 'every tick took the recovery branch');
      expect(
        drains(),
        greaterThanOrEqualTo(5),
        reason: 'INV-1: the incident shape — zero ticks may skip the drain',
      );
    },
  );

  test(
    // TC-189-11 (INV-2, Dart half) + TC-189-42 counter accounting
    'phase=recovered emitted ONLY on truthful recovery; failure counter not reset on NO_CIRCUIT',
    () async {
      bridge.whenCommand(
        'relay:reconnect',
        (_) => jsonEncode({
          'ok': true,
          'success': false,
          'errorCode': 'NO_CIRCUIT',
          'recoveryMode': 'watchdog_restart',
        }),
      );
      await startAndLatchOnline();
      statusFeed.sticky = _statusJson(relayState: 'degraded');

      final events = await _captureFlowEvents(() async {
        await service.performImmediateHealthCheck();
      });

      final recovered = events.where(
        (e) =>
            e['event'] == 'RELAY_OUTAGE_TIMING' &&
            (e['details'] as Map<String, dynamic>)['phase'] == 'recovered',
      );
      expect(
        recovered,
        isEmpty,
        reason:
            'INV-2: a Success:false/NO_CIRCUIT reconnect is NOT a '
            'recovery — HEAD branches on ok alone and lies',
      );
      expect(
        service.consecutiveRefreshFailures,
        1,
        reason: 'failure accounting must engage instead of resetting',
      );
      expect(
        events.any((e) => e['event'] == 'P2P_HEALTH_CHECK_RECOVERY_FAILED'),
        isTrue,
        reason: 'the failed recovery must be surfaced in FLOW telemetry',
      );
    },
  );

  test(
    // TC-189-12 (INV-4) + TC-189-42 (refreshFailureThreshold load-bearing)
    'failed-recovery backoff: 6 degraded ticks → sublinear relay:reconnect count, drains stay per-tick',
    () async {
      bridge.whenCommand(
        'relay:reconnect',
        (_) => jsonEncode({
          'ok': true,
          'success': false,
          'errorCode': 'NO_CIRCUIT',
          'recoveryMode': 'watchdog_restart',
        }),
      );
      await startAndLatchOnline();
      statusFeed.sticky = _statusJson(relayState: 'degraded');

      final events = await _captureFlowEvents(() async {
        for (var i = 0; i < 6; i++) {
          await service.performImmediateHealthCheck();
        }
      });

      expect(
        reconnects(),
        lessThanOrEqualTo(4),
        reason:
            'INV-4: from the refreshFailureThreshold-th consecutive '
            'failure on, recovery attempts must start skipping ticks '
            '(HEAD hammers one attempt per tick forever)',
      );
      final skips = events
          .where((e) => e['event'] == 'RELAY_RECOVERY_BACKOFF_SKIP')
          .length;
      expect(
        skips,
        greaterThanOrEqualTo(2),
        reason: 'the skipped ticks must be observable in FLOW',
      );
      expect(
        drains(),
        6,
        reason:
            'INV-4: recovery attempts back off; drains NEVER do — one '
            'drain per tick, including skipped-recovery ticks',
      );
    },
  );

  test(
    // TC-189-12b (INV-4, review finding): a PURE self-heal (autorelay flips the
    // relay back online with no successful Dart relay:reconnect) must break the
    // failure streak — a fresh outage may not inherit a stale skip budget.
    'backoff resets on pure self-heal: fresh outage starts with an immediate recovery attempt',
    () async {
      bridge.whenCommand(
        'relay:reconnect',
        (_) => jsonEncode({
          'ok': true,
          'success': false,
          'errorCode': 'NO_CIRCUIT',
          'recoveryMode': 'watchdog_restart',
        }),
      );
      await startAndLatchOnline();
      statusFeed.sticky = _statusJson(relayState: 'degraded');

      // 3 failing attempts: reaches refreshFailureThreshold and arms the
      // backoff (skip budget left > 0, streak left at 3).
      for (var i = 0; i < 3; i++) {
        await service.performImmediateHealthCheck();
      }
      expect(reconnects(), 3, reason: 'fixture: three failing attempts');

      // Pure self-heal: the next poll observes online WITHOUT any successful
      // relay:reconnect (autorelay re-reserved on its own).
      statusFeed.sticky = _statusJson(
        relayState: 'online',
        circuitAddresses: ['/p2p-circuit/relay1'],
      );
      await service.performImmediateHealthCheck();
      expect(
        service.consecutiveRefreshFailures,
        0,
        reason: 'an observed-healthy relay must break the failure streak',
      );

      // Fresh outage: the FIRST tick must attempt recovery immediately —
      // not consume a stale skip budget from the previous outage.
      statusFeed.sticky = _statusJson(relayState: 'degraded');
      final events = await _captureFlowEvents(() async {
        await service.performImmediateHealthCheck();
      });

      expect(
        events.where((e) => e['event'] == 'RELAY_RECOVERY_BACKOFF_SKIP'),
        isEmpty,
        reason: 'a fresh outage may not start backed-off',
      );
      expect(
        reconnects(),
        4,
        reason: 'the fresh outage attempts recovery on its first tick',
      );
      expect(
        service.consecutiveRefreshFailures,
        1,
        reason: 'the fresh outage counts failures from 1, not from the stale 3',
      );
    },
  );

  test(
    // TC-189-13 (INV-2 + INV-4 convergence)
    'backoff resets on truthful recovery; exactly one phase=recovered on convergence',
    () async {
      var reconnectSucceeds = false;
      bridge.whenCommand('relay:reconnect', (_) {
        if (reconnectSucceeds) {
          return jsonEncode({
            'ok': true,
            'success': true,
            'recoveryMode': 'in_place',
          });
        }
        return jsonEncode({
          'ok': true,
          'success': false,
          'errorCode': 'NO_CIRCUIT',
          'recoveryMode': 'watchdog_restart',
        });
      });
      bridge.whenCommand(
        'inbox:register_token',
        (_) => jsonEncode({'ok': true, 'status': 'registered'}),
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await service.registerPushToken('token-189', 'android');
      // Plan 375: the healthy transition hands re-registration to the one
      // installed coordinator owner; its attempt sends the current-policy
      // frame (production wires PushRegistrationCoordinator.retryNow here).
      service.installPushRegistrationRetryNow(() async {
        await service.registerPushToken('token-189', 'android');
      });
      await service.performImmediateHealthCheck();
      bridge.calledCommands.clear();

      statusFeed.sticky = _statusJson(relayState: 'degraded');

      final events = await _captureFlowEvents(() async {
        // 3 failing attempts (threshold reached on the 3rd) + 1 backoff tick.
        for (var i = 0; i < 4; i++) {
          await service.performImmediateHealthCheck();
        }
        // The relay comes back: next allowed attempt succeeds truthfully.
        reconnectSucceeds = true;
        statusFeed.enqueue([
          _statusJson(relayState: 'degraded'), // initial poll: still degraded
          _statusJson(
            relayState: 'online',
            circuitAddresses: ['/p2p-circuit/relay1'],
          ), // retry poll after the successful reconnect
        ]);
        await service.performImmediateHealthCheck();
        // Converged: the next tick takes the normal branch.
        await service.performImmediateHealthCheck();
        // Settle the unawaited push-token re-register.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      final recovered = events.where(
        (e) =>
            e['event'] == 'RELAY_OUTAGE_TIMING' &&
            (e['details'] as Map<String, dynamic>)['phase'] == 'recovered',
      );
      expect(
        recovered.length,
        1,
        reason:
            'INV-2: exactly ONE truthful phase=recovered on convergence '
            '(HEAD emits one per tick)',
      );
      expect(
        service.consecutiveRefreshFailures,
        0,
        reason: 'truthful success resets the failure accounting',
      );
      final recoveryStarts = events
          .where((e) => e['event'] == 'RELAY_RECOVERY_START')
          .length;
      expect(
        recoveryStarts,
        4,
        reason:
            '3 failing attempts + 1 successful attempt; the backoff tick '
            'and the converged tick must not attempt recovery',
      );
      expect(
        bridge.calledCommands.where((c) => c == 'inbox:register_token').length,
        greaterThanOrEqualTo(1),
        reason:
            'invariant re-verification: the healthy transition must '
            're-register the stored push token',
      );
      expect(
        drains(),
        6,
        reason:
            'INV-1 across the whole convergence: every tick drained '
            '(4 degraded + 1 recovering + 1 converged)',
      );
    },
  );
}
