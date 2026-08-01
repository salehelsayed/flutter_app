/// Plan 320 P2 (TC-320-08/09) — relay-health re-registration must not
/// resurrect a push token the provider has retired.
///
/// The relay evicts permanently-unroutable tokens on the first permanent FCM
/// error (plan 320 P1). Before P2, every relay-health transition replayed the
/// CACHED `_lastFcmToken` verbatim, so the very token the relay just evicted
/// was re-registered on the next reconnect — the eviction silently decayed.
/// The service must prefer a LIVE provider read (`liveFcmTokenReader`) and
/// fall back to the cached value only when the live read is unavailable.
///
/// Own fake-bridge copy of the p2p_service_impl_health_drain_test.dart
/// pattern — deliberately a separate file (Scope Guard: do not edit that
/// suite). The trigger used here is the `relay:state` push path
/// (`_handleRelayStateChanged`), the simplest of the three call sites that
/// funnel into `_reregisterStoredPushTokenIfAvailable`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

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

/// Captures `print` output (the `logPushDiagnostic` sink) during [action].
Future<List<String>> _capturePrints(Future<void> Function() action) async {
  final printed = <String>[];
  await runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        printed.add(line);
      },
    ),
  );
  return printed;
}

void main() {
  late _FakeBridge bridge;
  late List<String> registeredTokens;
  late String stickyStatus;
  P2PServiceImpl? service;

  setUp(() {
    bridge = _FakeBridge();
    registeredTokens = [];
    stickyStatus = _statusJson(relayState: 'online');
    bridge.whenCommand('node:status', (_) => stickyStatus);
    bridge.whenCommand('node:start', (_) => _statusJson(relayState: 'online'));
    bridge.whenCommand(
      'inbox:retrieve_pending',
      (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
    );
    bridge.whenCommand('inbox:ack', (_) => jsonEncode({'ok': true, 'acked': 1}));
    // Recovery attempts triggered by the degradation must fail fast so the
    // node deterministically STAYS degraded until the online push below.
    bridge.whenCommand(
      'relay:reconnect',
      (_) => jsonEncode({'ok': false, 'errorCode': 'RELAY_ERROR'}),
    );
    bridge.whenCommand('inbox:register_token', (payload) {
      registeredTokens.add(payload?['token'] as String? ?? '<missing>');
      return jsonEncode({'ok': true, 'status': 'registered'});
    });
  });

  tearDown(() {
    service?.dispose();
    service = null;
  });

  P2PServiceImpl buildService({
    Future<String?> Function()? liveFcmTokenReader,
  }) {
    final built = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
      liveFcmTokenReader: liveFcmTokenReader,
    );
    service = built;
    return built;
  }

  /// Starts the node online and seeds the cached token state
  /// (`_lastFcmToken`/`_lastFcmPlatform`) via a normal registration.
  Future<void> startAndSeedCachedToken(P2PServiceImpl svc) async {
    await svc.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
    final ok = await svc.registerPushToken('cached-token-dead', 'android');
    expect(ok, isTrue, reason: 'fixture: seeding the cached token must succeed');
    registeredTokens.clear();
  }

  /// Degrades the relay (push + confirming poll) and settles, then transitions
  /// back to healthy via a `relay:state` push — the re-registration trigger.
  Future<void> degradeThenComeBackOnline(P2PServiceImpl svc) async {
    stickyStatus = _statusJson(relayState: 'degraded');
    bridge.onRelayStateChanged?.call({
      'relayState': 'degraded',
      'healthyRelayCount': 0,
      'watchdogRestartCount': 0,
      'reason': 'relay_disconnected',
    });
    // The degradation push fires performImmediateHealthCheck unawaited; run an
    // awaited check (it coalesces) so the failed recovery fully settles and
    // the service is deterministically unhealthy before the online push.
    await svc.performImmediateHealthCheck();
    registeredTokens.clear();

    bridge.onRelayStateChanged?.call({
      'relayState': 'online',
      'healthyRelayCount': 1,
      'watchdogRestartCount': 0,
      'reason': 'relay_connected',
    });
    // The re-register is fired unawaited from the push handler — settle.
    for (var i = 0; i < 100 && registeredTokens.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    // TC-320-08
    'relay reconnect re-reads the live token before re-registering',
    () async {
      var liveReads = 0;
      final svc = buildService(
        liveFcmTokenReader: () async {
          liveReads++;
          return 'live-token-fresh';
        },
      );
      await startAndSeedCachedToken(svc);
      expect(
        liveReads,
        0,
        reason: 'fixture: a plain registration must not consult the live '
            'reader — only relay-health re-registration does',
      );

      await degradeThenComeBackOnline(svc);

      expect(
        liveReads,
        greaterThanOrEqualTo(1),
        reason: 'TC-320-08: the healthy transition must consult the live '
            'provider token before re-registering',
      );
      expect(
        registeredTokens,
        ['live-token-fresh'],
        reason: 'TC-320-08: the LIVE token must be registered, not the cached '
            'one (HEAD replayed _lastFcmToken verbatim, resurrecting the '
            'relay-evicted entry on every reconnect)',
      );
    },
  );

  test(
    // TC-320-09
    'falls back to the cached token when the live read fails',
    () async {
      final svc = buildService(
        liveFcmTokenReader: () async {
          throw StateError('FIS_AUTH_ERROR: provider unavailable');
        },
      );
      await startAndSeedCachedToken(svc);

      final printed = await _capturePrints(() async {
        await degradeThenComeBackOnline(svc);
      });

      expect(
        registeredTokens,
        ['cached-token-dead'],
        reason: 'TC-320-09: a throwing live read must fall back to the cached '
            'token — degrading to zero-token would be a regression',
      );
      expect(
        printed
            .where(
              (line) =>
                  line.contains('live_push_token_read_failed_using_cached'),
            )
            .length,
        1,
        reason: 'TC-320-09: the fallback must be attributable — exactly one '
            'diagnostic for the one failed live read',
      );
    },
  );

  test(
    // TC-320-09 (empty-read shape)
    'falls back to the cached token when the live read returns no token',
    () async {
      final svc = buildService(liveFcmTokenReader: () async => '  ');
      await startAndSeedCachedToken(svc);

      final printed = await _capturePrints(() async {
        await degradeThenComeBackOnline(svc);
      });

      expect(
        registeredTokens,
        ['cached-token-dead'],
        reason: 'TC-320-09: an empty/whitespace live read must fall back to '
            'the cached token',
      );
      expect(
        printed
            .where(
              (line) =>
                  line.contains('live_push_token_unavailable_using_cached'),
            )
            .length,
        1,
        reason: 'TC-320-09: the empty-read fallback must be attributable',
      );
    },
  );

  test(
    // Wiring sanity: no reader injected (legacy construction) keeps the
    // pre-320 behaviour — the cached token is re-registered.
    'no live reader injected still re-registers the cached token',
    () async {
      final svc = buildService();
      await startAndSeedCachedToken(svc);

      await degradeThenComeBackOnline(svc);

      expect(
        registeredTokens,
        ['cached-token-dead'],
        reason: 'a construction site without the seam must keep re-registering '
            'the cached token (no zero-token regression)',
      );
    },
  );
}
