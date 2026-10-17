import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/application/call_scoped_media_bundle_owner.dart';
import 'package:flutter_app/features/call/infrastructure/bridge_call_media_protection_lease.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers like the Go broker: an acquire wins when its generation is at
/// least as new as the holder's, a release clears only the exact
/// (generation, incarnation) pair, and a node restart clears the holder and
/// moves to a new incarnation.
final class _BrokerBridge extends Bridge {
  int incarnation = 1;
  CallMediaProtectionGrant? holder;
  bool restartInProgress = false;
  Object? failure;
  Map<String, Object?>? fixedAnswer;
  Completer<String>? stall;
  Completer<void>? nativeDelay;
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];

  bool get held => holder != null;

  /// Node Stop/Reset: the holder is gone and later grants carry a new
  /// incarnation.
  void restartNode() {
    holder = null;
    incarnation++;
  }

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
    final delayed = nativeDelay;
    if (delayed != null) await delayed.future;
    final request = jsonDecode(message) as Map<String, dynamic>;
    requests.add(request);
    final pending = stall;
    if (pending != null) return pending.future;
    final error = failure;
    if (error != null) throw error;
    final fixed = fixedAnswer;
    if (fixed != null) return jsonEncode(fixed);
    final payload = request['payload'] as Map<String, dynamic>;
    final generation = payload['generation'] as int;
    if (payload['held'] == true) {
      if (restartInProgress) {
        return jsonEncode({
          'ok': true,
          'held': false,
          'generation': generation,
          'reason': 'restart_in_progress',
        });
      }
      final current = holder;
      if (current != null && current.generation > generation) {
        return jsonEncode({
          'ok': true,
          'held': false,
          'generation': generation,
          'reason': 'superseded',
        });
      }
      holder = CallMediaProtectionGrant(
        generation: generation,
        incarnation: incarnation,
      );
      return jsonEncode({
        'ok': true,
        'held': true,
        'generation': generation,
        'incarnation': incarnation,
      });
    }
    final released =
        holder ==
        CallMediaProtectionGrant(
          generation: generation,
          incarnation: payload['incarnation'] as int,
        );
    if (released) holder = null;
    return jsonEncode({'ok': true, 'held': false, 'released': released});
  }
}

List<Map<String, Object?>> _payloads(_BrokerBridge bridge) =>
    <Map<String, Object?>>[
      for (final request in bridge.requests)
        Map<String, Object?>.from(request['payload'] as Map),
    ];

CallMediaProtectionGrant _grant(int generation, [int incarnation = 1]) =>
    CallMediaProtectionGrant(generation: generation, incarnation: incarnation);

Matcher _refused(String reason) => isA<CallMediaProtectionRefused>().having(
  (admission) => admission.reason,
  'reason',
  reason,
);

void main() {
  late _BrokerBridge bridge;
  late List<Map<String, dynamic>> flowEvents;

  setUp(() {
    flowEventLoggingEnabled = false;
    BridgeCallMediaProtectionLease.resetGenerations();
    bridge = _BrokerBridge();
    flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(
      (payload) => flowEvents.add(Map<String, dynamic>.from(payload)),
    );
  });

  tearDown(() {
    debugSetFlowEventSink(null);
    flowEventLoggingEnabled = true;
  });

  List<Map<String, dynamic>> protectionEvents() => <Map<String, dynamic>>[
    for (final event in flowEvents)
      if (event['event'] == 'CALL_MEDIA_PROTECTION')
        Map<String, dynamic>.from(event['details'] as Map),
  ];

  Future<CallMediaProtectionGrant> granted(
    BridgeCallMediaProtectionLease lease,
  ) async {
    final admission = await lease.acquire();
    expect(admission, isA<CallMediaProtectionGranted>());
    return (admission as CallMediaProtectionGranted).grant;
  }

  test(
    'acquire holds a fresh generation and release hands back the same pair',
    () async {
      final lease = BridgeCallMediaProtectionLease(bridge: bridge);

      expect(await granted(lease), _grant(1));
      expect(bridge.requests.single, <String, Object?>{
        'cmd': 'call_media:protection',
        'payload': <String, Object?>{'held': true, 'generation': 1},
      });
      expect(bridge.holder, _grant(1));

      await lease.release(_grant(1));
      expect(_payloads(bridge).last, <String, Object?>{
        'held': false,
        'generation': 1,
        'incarnation': 1,
      });
      expect(bridge.held, isFalse);

      expect(await granted(lease), _grant(2));
      expect(protectionEvents(), <Map<String, Object?>>[
        {
          'action': 'acquire',
          'outcome': 'held',
          'generation': 1,
          'incarnation': 1,
        },
        {
          'action': 'release',
          'outcome': 'released',
          'generation': 1,
          'incarnation': 1,
        },
        {
          'action': 'acquire',
          'outcome': 'held',
          'generation': 2,
          'incarnation': 1,
        },
      ]);
    },
  );

  test('a late release of an older generation leaves the newer hold', () async {
    final lease = BridgeCallMediaProtectionLease(bridge: bridge);
    final first = await granted(lease);
    final second = await granted(lease);

    await lease.release(first);
    expect(bridge.holder, second);
    expect(protectionEvents().last, <String, Object?>{
      'action': 'release',
      'outcome': 'ignored',
      'generation': 1,
      'incarnation': 1,
    });

    await lease.release(second);
    expect(bridge.held, isFalse);
  });

  test(
    'a release names its incarnation, so a hold granted after a node restart '
    'survives releases from before it',
    () async {
      final lease = BridgeCallMediaProtectionLease(bridge: bridge);
      final before = await granted(lease);
      bridge.restartNode();
      final after = await granted(lease);
      expect(after, _grant(2, 2));

      await lease.release(before);
      expect(bridge.holder, after);
      // The same generation from the old incarnation cannot clear it either.
      await lease.release(_grant(2, 1));
      expect(bridge.holder, after);

      await lease.release(after);
      expect(bridge.held, isFalse);
    },
  );

  test("a lease built later in the process continues above an earlier lease's "
      'generations', () async {
    final earlier = BridgeCallMediaProtectionLease(bridge: bridge);
    await granted(earlier);
    await granted(earlier);
    await granted(earlier);
    expect(bridge.holder, _grant(3), reason: 'left behind, never released');

    final later = BridgeCallMediaProtectionLease(bridge: bridge);
    expect(await granted(later), _grant(4));
    expect(bridge.holder, _grant(4));
    expect(
      <Object?>[for (final payload in _payloads(bridge)) payload['generation']],
      <int>[1, 2, 3, 4],
    );
  });

  test(
    'restart_in_progress is a refusal and the next ask after it is granted',
    () async {
      bridge.restartInProgress = true;
      final lease = BridgeCallMediaProtectionLease(bridge: bridge);

      expect(await lease.acquire(), _refused('restart_in_progress'));
      expect(bridge.held, isFalse);

      bridge.restartInProgress = false;
      expect(await granted(lease), _grant(2));
      expect(protectionEvents(), <Map<String, Object?>>[
        {
          'action': 'acquire',
          'outcome': 'refused',
          'generation': 1,
          'reason': 'restart_in_progress',
        },
        {
          'action': 'acquire',
          'outcome': 'held',
          'generation': 2,
          'incarnation': 1,
        },
      ]);
    },
  );

  test('a hold above this process is superseded, not taken over', () async {
    bridge.holder = _grant(7);
    final lease = BridgeCallMediaProtectionLease(bridge: bridge);

    expect(await lease.acquire(), _refused('superseded'));
    expect(bridge.holder, _grant(7));
  });

  test(
    'a missing native method leaves the call unprotected and reports it once',
    () async {
      bridge.failure = MissingPluginException('callMediaProtection');
      final lease = BridgeCallMediaProtectionLease(bridge: bridge);

      expect(await lease.acquire(), isA<CallMediaProtectionUnavailable>());
      await lease.release(_grant(1));
      expect(protectionEvents(), <Map<String, Object?>>[
        {'action': 'acquire', 'outcome': 'unavailable', 'generation': 1},
        {
          'action': 'release',
          'outcome': 'unavailable',
          'generation': 1,
          'incarnation': 1,
        },
      ]);
    },
  );

  test("the bridge client's MISSING_PLUGIN and NOT_IMPLEMENTED answers mean "
      'the same missing method', () async {
    for (final code in const <String>['MISSING_PLUGIN', 'NOT_IMPLEMENTED']) {
      bridge.fixedAnswer = <String, Object?>{'ok': false, 'errorCode': code};
      final lease = BridgeCallMediaProtectionLease(bridge: bridge);
      expect(
        await lease.acquire(),
        isA<CallMediaProtectionUnavailable>(),
        reason: code,
      );
    }
  });

  test('a broker rejection is a refusal named by its code', () async {
    bridge.fixedAnswer = <String, Object?>{
      'ok': false,
      'errorCode': 'NOT_INITIALIZED',
    };
    final lease = BridgeCallMediaProtectionLease(bridge: bridge);

    expect(await lease.acquire(), _refused('NOT_INITIALIZED'));
    expect(protectionEvents(), <Map<String, Object?>>[
      {
        'action': 'acquire',
        'outcome': 'refused',
        'generation': 1,
        'reason': 'NOT_INITIALIZED',
      },
    ]);
  });

  test('a held answer without an incarnation grants nothing', () async {
    bridge.fixedAnswer = <String, Object?>{
      'ok': true,
      'held': true,
      'generation': 1,
    };
    final lease = BridgeCallMediaProtectionLease(bridge: bridge);

    expect(await lease.acquire(), _refused('malformed'));
  });

  test('a stalled broker cannot hold call setup past the lease timeout', () {
    fakeAsync((clock) {
      bridge.stall = Completer<String>();
      final lease = BridgeCallMediaProtectionLease(
        bridge: bridge,
        timeout: const Duration(milliseconds: 800),
      );
      CallMediaProtectionAdmission? result;
      unawaited(lease.acquire().then((value) => result = value));

      clock.elapse(const Duration(milliseconds: 799));
      expect(result, isNull);
      clock.elapse(const Duration(milliseconds: 1));
      expect(result, _refused('timeout'));
      expect(protectionEvents().single, <String, Object?>{
        'action': 'acquire',
        'outcome': 'timeout',
        'generation': 1,
      });
    });
  });

  test('a grant that lands after the acquire timed out is handed back', () {
    fakeAsync((clock) {
      bridge.nativeDelay = Completer<void>();
      final lease = BridgeCallMediaProtectionLease(
        bridge: bridge,
        timeout: const Duration(milliseconds: 800),
      );
      CallMediaProtectionAdmission? result;
      unawaited(lease.acquire().then((value) => result = value));
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 800));
      expect(result, _refused('timeout'));
      expect(bridge.held, isFalse);

      bridge.nativeDelay!.complete();
      clock.flushMicrotasks();
      expect(
        bridge.held,
        isFalse,
        reason:
            'late native grant has no caller-held token and must not strand '
            'the broker',
      );
      expect(_payloads(bridge), <Map<String, Object?>>[
        {'held': true, 'generation': 1},
        {'held': false, 'generation': 1, 'incarnation': 1},
      ]);
      expect(protectionEvents(), <Map<String, Object?>>[
        {'action': 'acquire', 'outcome': 'timeout', 'generation': 1},
        {
          'action': 'release',
          'outcome': 'released',
          'generation': 1,
          'incarnation': 1,
        },
      ]);
    });
  });

  test('a late refusal after the timeout hands nothing back', () {
    fakeAsync((clock) {
      bridge
        ..nativeDelay = Completer<void>()
        ..restartInProgress = true;
      final lease = BridgeCallMediaProtectionLease(
        bridge: bridge,
        timeout: const Duration(milliseconds: 800),
      );
      unawaited(lease.acquire());
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 800));

      bridge.nativeDelay!.complete();
      clock.flushMicrotasks();
      expect(_payloads(bridge), <Map<String, Object?>>[
        {'held': true, 'generation': 1},
      ]);
    });
  });
}
