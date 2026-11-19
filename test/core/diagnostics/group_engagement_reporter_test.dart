import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/diagnostics/engagement_chat_checkpoint_store.dart';

const _limit = Duration(seconds: 3);
const _account = 'canonical-local-account';
const _other = 'canonical-other-account';
const _binding =
    'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _groupA = 'private-group-alpha';
const _groupB = 'private-group-beta';
const _start = 1794783600000;
const _end = 1795388400000;
const _week = '2026-W47';

Future<T> _bounded<T>(Future<T> f) => f.timeout(_limit);

final class _Bridge implements Bridge {
  final requests = <Map<String, dynamic>>[];
  int revision = 0;
  bool accept = true;
  Completer<void>? markGate;
  int start = _start;
  int end = _end;
  String week = _week;
  @override
  bool get isInitialized => true;

  List<Map<String, dynamic>> operations(String op) =>
      requests.where((p) => p['op'] == op).toList();

  @override
  Future<String> send(String raw) async {
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    expect(envelope['cmd'], 'active_identity_reporter_v1');
    final p = Map<String, dynamic>.from(envelope['payload'] as Map);
    requests.add(p);
    if (p['op'] == 'configure') revision++;
    if (p['op'] == 'markWeekly') await markGate?.future;
    return jsonEncode({
      'ok': true,
      'data': {
        'revision': p['op'] == 'configure' ? revision : p['revision'],
        'consentEpoch': p['consentEpoch'],
        if (p['op'] == 'configure')
          'configured': p['enabled'] == true && p['accountPeerId'] == _account,
        if (p['op'] == 'markWeekly') 'accepted': accept,
        if (p['op'] == 'flush') 'queued': true,
        if (p['op'] == 'weeklyProjection')
          'weekly': {
            'week': week,
            'startUnixMillis': start,
            'endUnixMillis': end,
            'kinds': <String>[],
            'acknowledged': <Object>[],
          },
      },
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The baseline constructor still runs its real configure/fence/bridge path.
// Only absent additive parameters/methods adapt to unavailable observation.
ActiveIdentityReporter _make(
  String state,
  EngagementChatCheckpointStore store,
  int Function() now,
) {
  try {
    return Function.apply(ActiveIdentityReporter.new, [], {
      #statePath: state,
      #groupWitnessStore: store,
      #groupNowMilliseconds: now,
    }) as ActiveIdentityReporter;
  } on NoSuchMethodError {
    return ActiveIdentityReporter(statePath: state);
  }
}

void _post(
  ActiveIdentityReporter reporter,
  ActiveIdentityReporterCapture capture, {
  String group = _groupA,
}) {
  try {
    (reporter as dynamic).groupPostCommittedCaptured(capture, groupId: group);
  } on NoSuchMethodError {
    // RED: the old reporter has no group producer API.
  }
}

void _visible(
  ActiveIdentityReporter reporter,
  ActiveIdentityReporterCapture capture, {
  String group = _groupA,
  String author = _other,
  int postTime = _start + 1000,
}) {
  try {
    (reporter as dynamic).groupOtherPostVisibleCaptured(
      capture,
      groupId: group,
      authorAccountPeerId: author,
      postOccurredAtUnixMillis: postTime,
    );
  } on NoSuchMethodError {
    // RED: the old reporter has no group producer API.
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late EngagementChatCheckpointStore store;
  late ActiveIdentityReporter reporter;
  late _Bridge bridge;
  var now = _start + 10000;
  var failWrites = false;

  setUp(() async {
    now = _start + 10000;
    failWrites = false;
    directory = await _bounded(Directory.systemTemp.createTemp('b15-group-'));
    store = await _bounded(
      EngagementChatCheckpointStore.open(
        '${directory.path}/private-group',
        beforeCommit: (_) async {
          if (failWrites) throw StateError('fixture filesystem refusal');
        },
      ),
    );
    reporter = _make('${directory.path}/native.json', store, () => now);
    bridge = _Bridge();
    reporter.attachBridge(bridge);
    reporter.observeIdentity(
      accountPeerId: _account,
      rootPrivateKeyBase64: 'public-test-fixture-not-a-real-private-key',
      profileBinding: _binding,
    );
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: 91)));
  });

  tearDown(() async {
    await _bounded(reporter.dispose());
    await _bounded(store.close());
    await _bounded(directory.delete(recursive: true));
  });

  ActiveIdentityReporterCapture capture() =>
      reporter.captureOwner(expectedAccountPeerId: _account)!;

  Future<void> flush() => _bounded(reporter.flush());

  void expectGroup({int epoch = 91, int count = 1}) {
    final marks = bridge.operations('markWeekly');
    expect(marks, hasLength(count));
    final mark = marks.last;
    expect(mark.keys.toSet(), {
      'version',
      'op',
      'revision',
      'consentEpoch',
      'accountPeerId',
      'profileBinding',
      'week',
      'kinds',
    });
    expect(mark['accountPeerId'], _account);
    expect(mark['profileBinding'], _binding);
    expect(mark['consentEpoch'], epoch);
    expect(mark['week'], _week);
    expect(mark['kinds'], ['group']);
    expect(
      bridge.operations('mark'),
      isEmpty,
      reason: 'The group witness emits only the weekly group bit; existing producers own daily activity',
    );
    final payloads = jsonEncode(bridge.requests);
    expect(payloads, isNot(contains(_groupA)));
    expect(payloads, isNot(contains(_groupB)));
    expect(payloads, isNot(contains(_other)));
  }

  test(
    'B15G-001 own committed post plus visible other content retains group only',
    () async {
      final owner = capture();
      _post(reporter, owner);
      await flush();
      expect(bridge.operations('markWeekly'), isEmpty);
      _visible(reporter, owner);
      await flush();
      expectGroup();
      final saved = await _bounded(File(store.checkpointPath).readAsString());
      expect(saved, isNot(contains(_groupA)));
      expect(saved, isNot(contains(_other)));
    },
  );

  test('B15G-002 a visible post may precede the own committed post', () async {
    final owner = capture();
    _visible(reporter, owner);
    await flush();
    expect(bridge.operations('markWeekly'), isEmpty);
    _post(reporter, owner);
    await flush();
    expectGroup();
  });

  test('B15G-003 halves from different groups cannot be combined', () async {
    final owner = capture();
    _post(reporter, owner);
    _visible(reporter, owner, group: _groupB);
    await flush();
    expect(bridge.operations('markWeekly'), isEmpty);
    _post(reporter, owner, group: _groupB);
    await flush();
    expectGroup();
  });

  test(
    'B15G-004 own linked author canonical root is never another account',
    () async {
      final owner = capture();
      _post(reporter, owner);
      _visible(reporter, owner, author: _account);
      await flush();
      expect(bridge.operations('markWeekly'), isEmpty);
      _visible(reporter, owner);
      await flush();
      expectGroup();
    },
  );

  test(
    'B15G-005 only content from the open Go calendar week qualifies',
    () async {
      final owner = capture();
      _post(reporter, owner);
      _visible(reporter, owner, postTime: _start - 1);
      await flush();
      expect(bridge.operations('markWeekly'), isEmpty);
      _visible(reporter, owner, postTime: _end);
      await flush();
      expect(bridge.operations('markWeekly'), isEmpty);
      _visible(reporter, owner);
      await flush();
      expectGroup();
    },
  );

  test('B15G-006 OFF clears partial witnesses before a new epoch', () async {
    final old = capture();
    _post(reporter, old);
    await flush();
    await _bounded(reporter.observeConsent((enabled: false, consentEpoch: 92)));
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: 93)));
    _visible(reporter, old);
    final fresh = capture();
    _visible(reporter, fresh);
    await flush();
    expect(bridge.operations('markWeekly'), isEmpty);
    _post(reporter, fresh);
    await flush();
    expectGroup(epoch: 93);
  });

  test(
    'B15G-007 visible content alone and initialization never qualify',
    () async {
      await flush();
      _visible(reporter, capture());
      await flush();
      expect(bridge.operations('markWeekly'), isEmpty);
      expect(bridge.operations('mark'), isEmpty);
    },
  );

  test('B15G-008 queued old ownership cannot spend a replacement profile', () async {
    final old = capture();
    reporter.observeIdentity(
      accountPeerId: 'replacement-account',
      rootPrivateKeyBase64: 'replacement-fixture',
      profileBinding:
          'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    _post(reporter, old);
    _visible(reporter, old);
    await flush();
    expect(bridge.operations('markWeekly'), isEmpty);
  });

  test(
    'B15G-009 repeated observations retain one bit and erase all group IDs',
    () async {
      final owner = capture();
      _post(reporter, owner, group: _groupB);
      _post(reporter, owner);
      _visible(reporter, owner);
      await flush();
      expectGroup();
      for (var i = 0; i < 3; i++) {
        _post(reporter, owner);
        _visible(reporter, owner);
      }
      await flush();
      expectGroup();
      final saved = await _bounded(File(store.checkpointPath).readAsString());
      expect(saved, isNot(contains(_groupA)));
      expect(saved, isNot(contains(_groupB)));
    },
  );

  test(
    'B15G-010 same-owner restart restores only the current private witness',
    () async {
      _post(reporter, capture());
      await flush();
      await _bounded(reporter.dispose());
      reporter = _make('${directory.path}/native.json', store, () => now);
      reporter.attachBridge(bridge);
      reporter.observeIdentity(
        accountPeerId: _account,
        rootPrivateKeyBase64: 'public-test-fixture-not-a-real-private-key',
        profileBinding: _binding,
      );
      await _bounded(
        reporter.observeConsent((enabled: true, consentEpoch: 91)),
      );
      _visible(reporter, capture());
      await flush();
      expectGroup();
    },
  );

  test(
    'B15G-011 a foreign account checkpoint cannot supply the own-post half',
    () async {
      _post(reporter, capture());
      await flush();
      final file = File(store.checkpointPath);
      expect(await _bounded(file.exists()), isTrue);
      await _bounded(reporter.dispose());
      final saved = jsonDecode(
        await _bounded(file.readAsString()),
      ) as Map<String, dynamic>;
      (saved['scope'] as Map)['accountPeerId'] = 'canonical-foreign-account';
      await _bounded(file.writeAsString(jsonEncode(saved)));
      reporter = _make('${directory.path}/native.json', store, () => now);
      reporter.attachBridge(bridge);
      reporter.observeIdentity(
        accountPeerId: _account,
        rootPrivateKeyBase64: 'public-test-fixture-not-a-real-private-key',
        profileBinding: _binding,
      );
      await _bounded(
        reporter.observeConsent((enabled: true, consentEpoch: 91)),
      );
      _visible(reporter, capture());
      await flush();
      expect(bridge.operations('markWeekly'), isEmpty);
      _post(reporter, capture());
      await flush();
      expectGroup();
    },
  );

  test(
    'B15G-012 refused retention stays pending and retries on a later flush',
    () async {
      bridge.accept = false;
      final owner = capture();
      _post(reporter, owner);
      _visible(reporter, owner);
      await flush();
      expect(bridge.operations('markWeekly'), hasLength(1));
      final saved = await _bounded(File(store.checkpointPath).readAsString());
      expect(saved, contains('pending'));
      expect(saved, isNot(contains(_groupA)));
      bridge.accept = true;
      await flush();
      expectGroup(count: 2);
      await flush();
      expectGroup(count: 2);
    },
  );

  test(
    'B15G-013 no native retention before the private pending write succeeds',
    () async {
      failWrites = true;
      final owner = capture();
      _post(reporter, owner);
      _visible(reporter, owner);
      await flush();
      expect(bridge.operations('markWeekly'), isEmpty);
      failWrites = false;
      await flush();
      expectGroup();
    },
  );

  test(
    'B15G-014 expired halves cannot be relabelled into a new Go week',
    () async {
      _post(reporter, capture());
      await flush();
      now = _end + 10000;
      bridge.start = _end;
      bridge.end = _end + 7 * 86400000;
      bridge.week = '2026-W48';
      _visible(reporter, capture(), postTime: _end + 1000);
      await flush();
      expect(bridge.operations('markWeekly'), isEmpty);
      _post(reporter, capture());
      await flush();
      final marks = bridge.operations('markWeekly');
      expect(marks, hasLength(1));
      expect(marks.single['week'], '2026-W48');
      expect(marks.single['kinds'], ['group']);
    },
  );

  test('B15G-015 OFF physically removes a partial checkpoint', () async {
    _post(reporter, capture());
    await flush();
    expect(await _bounded(File(store.checkpointPath).exists()), isTrue);
    await _bounded(reporter.observeConsent((enabled: false, consentEpoch: 92)));
    await flush();
    expect(await _bounded(File(store.checkpointPath).exists()), isFalse);
    expect(bridge.operations('markWeekly'), isEmpty);
  });

  test('B15G-016 a late local receipt cannot qualify a replacement epoch', () async {
    final gate = Completer<void>();
    bridge.markGate = gate;
    try {
      final owner = capture();
      _post(reporter, owner);
      _visible(reporter, owner);
      // Join the actual bridge boundary rather than waiting an arbitrary delay.
      await _bounded(
        Future<void>(() async {
          final waiting = Stopwatch()..start();
          while (bridge.operations('markWeekly').isEmpty &&
              waiting.elapsed < const Duration(seconds: 2)) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        }),
      );
      await _bounded(
        reporter.observeConsent((enabled: false, consentEpoch: 92)),
      );
      await _bounded(
        reporter.observeConsent((enabled: true, consentEpoch: 93)),
      );
      gate.complete();
      bridge.markGate = null;
      _visible(reporter, capture());
      await flush();
      expect(bridge.operations('markWeekly'), hasLength(1));
      _post(reporter, capture());
      await flush();
      expectGroup(epoch: 93, count: 2);
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
  });

  test('B15G-017 bounded groups refuse overflow without destroying an admitted group', () async {
    final owner = capture();
    for (var i = 0; i < 64; i++) _post(reporter, owner, group: 'bounded-$i');
    await flush();
    final snapshot = jsonDecode(
      await _bounded(File(store.checkpointPath).readAsString()),
    ) as Map;
    expect(snapshot['groups'], hasLength(64));
    _post(reporter, owner, group: 'overflow');
    _visible(reporter, owner, group: 'overflow');
    await flush();
    expect(bridge.operations('markWeekly'), isEmpty);
    _visible(reporter, owner, group: 'bounded-0');
    await flush();
    expectGroup();
  });

  test(
    'B15G-018 malformed identifiers cannot contribute either half',
    () async {
      final owner = capture();
      _post(reporter, owner, group: '');
      _visible(reporter, owner, group: '');
      _post(reporter, owner);
      _visible(reporter, owner, author: '');
      _visible(reporter, owner, author: 'a' * 257);
      await flush();
      expect(bridge.operations('markWeekly'), isEmpty);
      _visible(reporter, owner);
      await flush();
      expectGroup();
    },
  );
}
