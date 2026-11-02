/// Plan 320 P2 (TC-320-08/09), re-grounded by Plan 375 (TC-375-07).
///
/// The relay evicts permanently-unroutable tokens on the first permanent FCM
/// error (plan 320 P1). Before P2, every relay-health transition replayed the
/// CACHED `_lastFcmToken` verbatim, so the very token the relay just evicted
/// was re-registered on the next reconnect — the eviction silently decayed.
/// Plan 375 closes the residual raw path entirely: the persisted-token
/// restore and every relay-health transition now route through the one
/// late-installed `PushRegistrationCoordinator.retryNow` callback, whose
/// registration attempt re-reads the LIVE provider token and the current
/// capability policy inside `registerPushToken` immediately before the bridge
/// send. No raw bridge registration path remains in the service.
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
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart'
    as registration;

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../../core/secure_storage/fake_secure_key_store.dart';

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
  late List<Map<String, dynamic>> registeredPayloads;
  late FakeSecureKeyStore preferences;
  const thoughtNotificationPreferenceKey = 'thought_notifications_enabled_v1';
  late String stickyStatus;
  P2PServiceImpl? service;

  setUp(() {
    bridge = _FakeBridge();
    registeredTokens = [];
    registeredPayloads = [];
    preferences = FakeSecureKeyStore();
    stickyStatus = _statusJson(relayState: 'online');
    bridge.whenCommand('node:status', (_) => stickyStatus);
    bridge.whenCommand('node:start', (_) => _statusJson(relayState: 'online'));
    bridge.whenCommand(
      'inbox:retrieve_pending',
      (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
    );
    bridge.whenCommand(
      'inbox:ack',
      (_) => jsonEncode({'ok': true, 'acked': 1}),
    );
    // Recovery attempts triggered by the degradation must fail fast so the
    // node deterministically STAYS degraded until the online push below.
    bridge.whenCommand(
      'relay:reconnect',
      (_) => jsonEncode({'ok': false, 'errorCode': 'RELAY_ERROR'}),
    );
    bridge.whenCommand('inbox:register_token', (payload) {
      registeredTokens.add(payload?['token'] as String? ?? '<missing>');
      registeredPayloads.add(Map<String, dynamic>.from(payload!));
      return jsonEncode({'ok': true, 'status': 'registered'});
    });
  });

  tearDown(() {
    service?.dispose();
    service = null;
  });

  P2PServiceImpl buildService() {
    final built = P2PServiceImpl(
      bridge: bridge,
      loadThoughtNotificationsEnabled: () async =>
          await preferences.read(thoughtNotificationPreferenceKey) != '0',
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
    service = built;
    return built;
  }

  test(
    'Thought notification registration carries exact default ON and OFF ON OFF booleans',
    () async {
      final svc = buildService();
      await svc.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      expect(await svc.registerPushToken('same-token', 'android'), isTrue);
      for (final value in ['0', '1', '0']) {
        await preferences.write(thoughtNotificationPreferenceKey, value);
        expect(await svc.registerPushToken('same-token', 'android'), isTrue);
      }

      expect(
        registeredPayloads.map(
          (payload) => payload['thought_notifications_enabled'],
        ),
        [true, false, true, false],
      );
      expect(
        registeredPayloads.every(
          (payload) => payload['thought_notifications_enabled'] is bool,
        ),
        isTrue,
      );
      expect(
        registeredPayloads.every((payload) => payload['token'] == 'same-token'),
        isTrue,
      );
    },
  );

  test(
    'Thought notification registration startup refresh and preference retry read durable choice',
    () async {
      final svc = buildService();
      await svc.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await preferences.write(thoughtNotificationPreferenceKey, '0');
      final refresh = StreamController<String>.broadcast();
      addTearDown(refresh.close);
      var liveToken = 'startup-token';
      final coordinator = PushRegistrationCoordinator(
        requestPermission: () async => true,
        readPermission: () async => true,
        registerPushToken: () => registration.registerPushToken(
          p2pService: svc,
          isIOSFn: () => false,
          getTokenFn: () async => liveToken,
          getPlatformFn: () => 'android',
        ),
        tokenRefreshStream: refresh.stream,
      );
      addTearDown(coordinator.dispose);
      await coordinator.ensureStarted();
      expect(registeredPayloads, hasLength(1));

      await preferences.write(thoughtNotificationPreferenceKey, '1');
      liveToken = 'fresh-token';
      refresh.add(liveToken);
      for (var i = 0; i < 100 && registeredPayloads.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(registeredPayloads, hasLength(2));
      await preferences.write(thoughtNotificationPreferenceKey, '0');
      await coordinator.retryNow();

      expect(registeredPayloads.map((payload) => payload['token']), [
        'startup-token',
        'fresh-token',
        'fresh-token',
      ]);
      expect(
        registeredPayloads.map(
          (payload) => payload['thought_notifications_enabled'],
        ),
        [false, true, false],
      );
    },
  );

  test(
    'Thought notification OFF queued during registration is sent last with the same token',
    () async {
      final svc = buildService();
      await svc.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      final firstFrame = Completer<void>();
      final firstResponse = Completer<void>();
      var activeFrames = 0;
      bridge.whenCommand('inbox:register_token', (payload) async {
        activeFrames++;
        expect(
          activeFrames,
          1,
          reason: 'the registration owner serializes writes',
        );
        registeredPayloads.add(Map<String, dynamic>.from(payload!));
        if (registeredPayloads.length == 1) {
          firstFrame.complete();
          await firstResponse.future;
        }
        activeFrames--;
        return jsonEncode({'ok': true});
      });
      final coordinator = PushRegistrationCoordinator(
        requestPermission: () async => true,
        readPermission: () async => true,
        registerPushToken: () => registration.registerPushToken(
          p2pService: svc,
          isIOSFn: () => false,
          getTokenFn: () async => 'same-token',
          getPlatformFn: () => 'android',
        ),
        tokenRefreshStream: const Stream<String>.empty(),
      );
      addTearDown(coordinator.dispose);
      final startup = coordinator.ensureStarted();
      await firstFrame.future;
      await preferences.write(thoughtNotificationPreferenceKey, '0');
      final preferenceRetry = coordinator.retryNow();
      await pumpEventQueue();
      expect(registeredPayloads, hasLength(1));
      firstResponse.complete();
      await Future.wait([startup, preferenceRetry]);

      expect(registeredPayloads.map((payload) => payload['token']), [
        'same-token',
        'same-token',
      ]);
      expect(
        registeredPayloads.map(
          (payload) => payload['thought_notifications_enabled'],
        ),
        [true, false],
        reason: 'an old ON response cannot cover the newer durable OFF',
      );
    },
  );

  /// Starts the node online and seeds the cached token state
  /// (`_lastFcmToken`/`_lastFcmPlatform`) via a normal registration.
  Future<void> startAndSeedCachedToken(P2PServiceImpl svc) async {
    await svc.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
    final ok = await svc.registerPushToken('cached-token-dead', 'android');
    expect(
      ok,
      isTrue,
      reason: 'fixture: seeding the cached token must succeed',
    );
    registeredTokens.clear();
  }

  /// Degrades the relay (push + confirming poll) and settles, then transitions
  /// back to healthy via a `relay:state` push — the re-registration trigger.
  Future<void> degradeThenComeBackOnline(
    P2PServiceImpl svc, {
    Future<bool> Function()? settled,
  }) async {
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
    // The re-register trigger fires unawaited from the push handler — settle.
    for (var i = 0; i < 100; i++) {
      if (settled != null && await settled()) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    // TC-320-08 (Plan-375 shape) / TC-375-07 sibling
    'relay reconnect routes through the one installed coordinator retryNow',
    () async {
      final svc = buildService();
      var retryNowCalls = 0;
      // The production coordinator's retryNow owns the live-token read and
      // the current capability policy; here the callback records ownership
      // and performs the current-policy frame the coordinator would send.
      svc.installPushRegistrationRetryNow(() async {
        retryNowCalls++;
        await svc.registerPushToken('live-token-fresh', 'android');
      });
      await startAndSeedCachedToken(svc);
      expect(
        retryNowCalls,
        0,
        reason:
            'fixture: a plain registration must not consult retryNow — '
            'only relay-health re-registration does',
      );

      await degradeThenComeBackOnline(
        svc,
        settled: () async => registeredTokens.isNotEmpty,
      );

      expect(
        retryNowCalls,
        1,
        reason:
            'TC-320-08: the healthy transition must hand exactly one '
            'trigger to the installed coordinator owner',
      );
      expect(
        registeredTokens,
        ['live-token-fresh'],
        reason:
            'TC-320-08: the coordinator-owned current-policy frame must '
            'be registered, never a raw replay of the cached token',
      );
    },
  );

  test(
    // TC-320-09 (Plan-375 shape)
    'before coordinator install no raw bridge registration path remains',
    () async {
      final svc = buildService();
      await startAndSeedCachedToken(svc);

      final printed = await _capturePrints(() async {
        await degradeThenComeBackOnline(svc);
      });

      expect(
        registeredTokens,
        isEmpty,
        reason:
            'TC-320-09: without the installed coordinator callback the '
            'service must not replay any token through a raw bridge path',
      );
      expect(
        printed
            .where(
              (line) => line.contains(
                'push_reregistration_skipped_before_coordinator_install',
              ),
            )
            .length,
        greaterThanOrEqualTo(1),
        reason: 'TC-320-09: the skipped trigger must be attributable',
      );
    },
  );

  test(
    // Wiring sanity: repeated health flaps coalesce into one policy owner
    // call per transition and never bypass the coordinator.
    'each healthy transition emits at most one coordinator trigger',
    () async {
      final svc = buildService();
      var retryNowCalls = 0;
      svc.installPushRegistrationRetryNow(() async {
        retryNowCalls++;
      });
      await startAndSeedCachedToken(svc);

      await degradeThenComeBackOnline(
        svc,
        settled: () async => retryNowCalls > 0,
      );
      expect(retryNowCalls, 1);
      expect(
        registeredTokens,
        isEmpty,
        reason:
            'the trigger itself must not register anything raw; only the '
            'coordinator decides whether a frame is sent',
      );
    },
  );
}
