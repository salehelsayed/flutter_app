import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';

const _limit = Duration(seconds: 3);
const _account = 'b15-logical-account';
const _binding =
    'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _week = '2026-W47';
const _start = 1794783600000;
const _end = 1795388400000;
typedef _Interval = ({String week, int startMilliseconds, int endMilliseconds});

Future<T> _bounded<T>(Future<T> f) => f.timeout(_limit);

// Capability adaptation keeps this additive-API RED executable on the exact
// old reporter. Only an absent method becomes refusal; real errors propagate.
// Every positive case still checks the real bridge request and its receipt.
Future<_Interval?> _projection(
  ActiveIdentityReporter reporter,
  ActiveIdentityReporterCapture capture,
) async {
  try {
    return await _bounded(
      (reporter as dynamic).weeklyProjectionCaptured(capture)
          as Future<_Interval?>,
    );
  } on NoSuchMethodError {
    return null;
  }
}

Future<bool> _retain(
  ActiveIdentityReporter reporter,
  ActiveIdentityReporterCapture capture, {
  String week = _week,
  List<String> kinds = const ['group'],
}) async {
  try {
    return await _bounded(
      (reporter as dynamic).markWeeklyCaptured(
        capture,
        week: week,
        kinds: kinds,
      ) as Future<bool>,
    );
  } on NoSuchMethodError {
    return false;
  }
}

final class _Bridge implements Bridge {
  bool online = true;
  int revision = 0;
  final requests = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? respond;

  @override
  bool get isInitialized => online;

  List<Map<String, dynamic>> operations(String op) =>
      requests.where((p) => p['op'] == op).toList();

  Map<String, dynamic> reply(Map<String, dynamic> p) => {
    'ok': true,
    'data': {
      'revision': p['op'] == 'configure' ? ++revision : p['revision'],
      'consentEpoch': p['consentEpoch'],
      if (p['op'] == 'configure') 'configured': p['enabled'] == true,
      if (p['op'] == 'markWeekly') 'accepted': true,
      if (p['op'] == 'weeklyProjection')
        'weekly': {
          'week': _week,
          'startUnixMillis': _start,
          'endUnixMillis': _end,
          'kinds': <String>[],
          'acknowledged': <Object>[],
        },
    },
  };

  @override
  Future<String> send(String raw) async {
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    expect(envelope['cmd'], 'active_identity_reporter_v1');
    final p = Map<String, dynamic>.from(envelope['payload'] as Map);
    requests.add(p);
    return jsonEncode(await (respond?.call(p) ?? Future.value(reply(p))));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Bridge bridge;
  late ActiveIdentityReporter reporter;
  final gates = <Completer<Map<String, dynamic>>>[];

  setUp(() {
    bridge = _Bridge();
    reporter = ActiveIdentityReporter(
      statePath: '/unused-b15-public-fixture.json',
    );
    reporter.attachBridge(bridge);
    reporter.observeIdentity(
      accountPeerId: _account,
      rootPrivateKeyBase64: 'b15-in-memory-fixture-not-a-real-key',
      profileBinding: _binding,
    );
  });

  tearDown(() async {
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete({'ok': false});
    }
    gates.clear();
    await _bounded(reporter.dispose());
  });

  Future<ActiveIdentityReporterCapture> arm() async {
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: 91)));
    return reporter.captureOwner(expectedAccountPeerId: _account)!;
  }

  test(
    'B15W-001 Go projection supplies interval without activity or IDs',
    () async {
      final capture = await arm();
      expect(await _projection(reporter, capture), (
        week: _week,
        startMilliseconds: _start,
        endMilliseconds: _end,
      ));
      expect(bridge.operations('weeklyProjection').single, {
        'version': 1,
        'op': 'weeklyProjection',
        'revision': 1,
        'consentEpoch': 91,
        'profileBinding': _binding,
        'accountPeerId': _account,
      });
      expect(bridge.operations('mark'), isEmpty);
      expect(bridge.operations('markWeekly'), isEmpty);
    },
  );

  for (final kind in ['active', 'chat', 'call', 'group']) {
    test(
      'B15W-002-$kind retains existing once-per-identity kind only',
      () async {
        final capture = await arm();
        expect(await _retain(reporter, capture, kinds: [kind]), isTrue);
        expect(bridge.operations('markWeekly').single, {
          'version': 1,
          'op': 'markWeekly',
          'revision': 1,
          'consentEpoch': 91,
          'profileBinding': _binding,
          'accountPeerId': _account,
          'week': _week,
          'kinds': [kind],
        });
        expect(bridge.operations('mark'), isEmpty);
      },
    );
  }

  for (final mutation in ['epoch', 'revision', 'accepted', 'extra']) {
    test('B15W-003-$mutation receipt cannot authorize retention', () async {
      final capture = await arm();
      expect(await _retain(reporter, capture), isTrue);
      bridge.respond = (p) async {
        final result = bridge.reply(p);
        final data = result['data'] as Map<String, dynamic>;
        if (mutation == 'epoch') data['consentEpoch'] = 92;
        if (mutation == 'revision') data['revision'] = 77;
        if (mutation == 'accepted') data['accepted'] = false;
        if (mutation == 'extra') data['groupId'] = 'private-must-not-escape';
        return result;
      };
      expect(await _retain(reporter, capture), isFalse);
      expect(bridge.operations('markWeekly'), hasLength(2));
    });
  }

  for (final mutation in ['off-on', 'profile', 'bridge']) {
    test(
      'B15W-004-$mutation old capture never spends successor fence',
      () async {
        final capture = await arm();
        expect(await _retain(reporter, capture), isTrue);
        if (mutation == 'off-on') {
          await _bounded(
            reporter.observeConsent((enabled: false, consentEpoch: 92)),
          );
          await _bounded(
            reporter.observeConsent((enabled: true, consentEpoch: 93)),
          );
        } else if (mutation == 'profile') {
          reporter.observeIdentity(
            accountPeerId: 'other-account',
            rootPrivateKeyBase64: 'other-fixture',
            profileBinding: _binding,
          );
        } else {
          reporter.attachBridge(_Bridge());
        }
        expect(await _retain(reporter, capture), isFalse);
        expect(await _projection(reporter, capture), isNull);
        expect(bridge.operations('markWeekly'), hasLength(1));
      },
    );
  }

  test(
    'B15W-005 foreign reporter capture cannot spend identical owner values',
    () async {
      final capture = await arm();
      expect(await _retain(reporter, capture), isTrue);
      final other = ActiveIdentityReporter(statePath: '/unused-b15-other.json');
      try {
        other.attachBridge(bridge);
        other.observeIdentity(
          accountPeerId: _account,
          rootPrivateKeyBase64: 'b15-other-fixture',
          profileBinding: _binding,
        );
        await _bounded(other.observeConsent((enabled: true, consentEpoch: 91)));
        expect(await _retain(other, capture), isFalse);
        expect(bridge.operations('markWeekly'), hasLength(1));
      } finally {
        await _bounded(other.dispose());
      }
    },
  );

  test(
    'B15W-006 OFF during native retention rejects late positive receipt',
    () async {
      final capture = await arm();
      expect(await _retain(reporter, capture), isTrue);
      final gate = Completer<Map<String, dynamic>>();
      gates.add(gate);
      final entered = Completer<void>();
      Map<String, dynamic>? saved;
      bridge.respond = (p) {
        if (p['op'] == 'markWeekly') {
          saved = bridge.reply(p);
          entered.complete();
          return gate.future;
        }
        return Future.value(bridge.reply(p));
      };
      final pending = _retain(reporter, capture);
      await _bounded(entered.future);
      await _bounded(
        reporter.observeConsent((enabled: false, consentEpoch: 92)),
      );
      gate.complete(saved!);
      expect(await pending, isFalse);
    },
  );

  for (final mutation in [
    'extra',
    'reversed',
    'bad-week',
    'fractional',
    'minInt64',
  ]) {
    test('B15W-007-$mutation malformed Go projection fails closed', () async {
      final capture = await arm();
      expect(await _projection(reporter, capture), isNotNull);
      bridge.respond = (p) async {
        final result = bridge.reply(p);
        final weekly = (result['data'] as Map)['weekly'] as Map;
        if (mutation == 'extra') weekly['groupId'] = 'private-id';
        if (mutation == 'reversed') weekly['endUnixMillis'] = _start;
        if (mutation == 'bad-week') weekly['week'] = '2026-W7';
        if (mutation == 'fractional') weekly['startUnixMillis'] = _start + 0.5;
        if (mutation == 'minInt64') {
          weekly['startUnixMillis'] = -9223372036854775808;
          weekly['endUnixMillis'] = 0;
        }
        return result;
      };
      expect(await _projection(reporter, capture), isNull);
    });
  }

  test(
    'B15W-009 pending configuration retains original capture and kind copy',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      gates.add(gate);
      Map<String, dynamic>? configured;
      bridge.respond = (p) {
        final result = bridge.reply(p);
        if (p['op'] == 'configure' && p['enabled'] == true) {
          configured = result;
          return gate.future;
        }
        return Future.value(result);
      };
      final configuring = reporter.observeConsent((
        enabled: true,
        consentEpoch: 91,
      ));
      final capture = reporter.captureOwner(expectedAccountPeerId: _account)!;
      final kinds = ['group'];
      final pending = _retain(reporter, capture, kinds: kinds);
      kinds[0] = 'call';
      expect(bridge.operations('markWeekly'), isEmpty);
      gate.complete(configured!);
      await _bounded(configuring);
      expect(await pending, isTrue);
      expect(bridge.operations('markWeekly').single['kinds'], ['group']);
      expect(bridge.operations('markWeekly').single['revision'], 1);
    },
  );

  test('B15W-010 late projection never crosses an epoch replacement', () async {
    final capture = await arm();
    expect(await _projection(reporter, capture), isNotNull);
    final gate = Completer<Map<String, dynamic>>();
    gates.add(gate);
    final entered = Completer<void>();
    Map<String, dynamic>? saved;
    bridge.respond = (p) {
      final result = bridge.reply(p);
      if (p['op'] == 'weeklyProjection') {
        saved = result;
        entered.complete();
        return gate.future;
      }
      return Future.value(result);
    };
    final pending = _projection(reporter, capture);
    await _bounded(entered.future);
    await _bounded(reporter.observeConsent((enabled: false, consentEpoch: 92)));
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: 93)));
    gate.complete(saved!);
    expect(await pending, isNull);
  });

  test('B15W-011 invalid local kinds and week never reach native', () async {
    final capture = await arm();
    expect(await _retain(reporter, capture), isTrue);
    for (final kinds in <List<String>>[
      [],
      ['reciprocal'],
      ['group', 'group'],
      ['chat', 'arbitrary-count'],
    ]) {
      expect(await _retain(reporter, capture, kinds: kinds), isFalse);
    }
    for (final week in ['2026-W1', '2026-W00', '2026-W54', '2026-W47\n']) {
      expect(await _retain(reporter, capture, week: week), isFalse);
    }
    expect(bridge.operations('markWeekly'), hasLength(1));
  });

  test(
    'B15W-012 bridge exception remains an optional analytics refusal',
    () async {
      final capture = await arm();
      expect(await _retain(reporter, capture), isTrue);
      bridge.respond = (_) async => throw StateError('private-native-fixture');
      expect(await _retain(reporter, capture), isFalse);
      expect(await _projection(reporter, capture), isNull);
    },
  );

  test(
    'B15W-013 projection receipt must match its original native revision',
    () async {
      final capture = await arm();
      expect(await _projection(reporter, capture), isNotNull);
      bridge.respond = (p) async {
        final result = bridge.reply(p);
        (result['data'] as Map)['revision'] = 99;
        return result;
      };
      expect(await _projection(reporter, capture), isNull);
    },
  );

  test(
    'B15W-014 retained kinds and ACKs expose only the Go interval',
    () async {
      final capture = await arm();
      bridge.respond = (p) async {
        final result = bridge.reply(p);
        if (p['op'] == 'weeklyProjection') {
          final weekly = (result['data'] as Map)['weekly'] as Map;
          weekly['kinds'] = ['active', 'chat', 'group'];
          weekly['acknowledged'] = [
            {
              'relayPeerId': 'public-relay-fixture',
              'kinds': ['active', 'chat'],
            },
          ];
        }
        return result;
      };
      expect(await _projection(reporter, capture), (
        week: _week,
        startMilliseconds: _start,
        endMilliseconds: _end,
      ));
    },
  );

  test(
    'B15W-008 OFF default capture control never invokes weekly bridge',
    () async {
      await _bounded(
        reporter.observeConsent((enabled: false, consentEpoch: 91)),
      );
      expect(reporter.captureOwner(expectedAccountPeerId: _account), isNull);
      expect(bridge.operations('weeklyProjection'), isEmpty);
      expect(bridge.operations('markWeekly'), isEmpty);
    },
  );
}
