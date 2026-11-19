import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

const _limit = Duration(seconds: 2);
const _profileA = 'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _profileB = 'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _epoch = 91;
const _privateError = 'b294-private-native-error-account-signature-sentinel';
const _qualificationUnixMillis = 1794892800123;

typedef _CapturedOccurrenceMark = void Function(
  ActiveIdentityReporterCapture capture, {
  int? occurredAtUnixMillis,
});

Future<T> _bounded<T>(Future<T> future) => future.timeout(_limit);

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed >= _limit) fail('Expected local reporter operation');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

IdentityModel _identity(String suffix, {String username = 'name'}) => IdentityModel(
  // These are opaque Dart seam fixtures. Cryptographic validation belongs to
  // the separately frozen Go protocol/engine contracts, not this mock bridge.
  peerId: '12D3KooWB294LogicalRootAccount$suffix',
  publicKey: base64Encode(List<int>.filled(32, suffix == 'A' ? 41 : 43)),
  privateKey: base64Encode(List<int>.filled(64, suffix == 'A' ? 41 : 43)),
  mnemonic12: 'b294 root mnemonic remains in memory',
  username: username,
  createdAt: '2026-11-15T12:00:00Z',
  updatedAt: '2026-11-15T12:00:00Z',
);

final class _LocalBridge implements Bridge {
  bool online = true;
  final requests = <Map<String, dynamic>>[];
  Future<String> Function(Map<String, dynamic>, int)? answer;
  int _revision = 0;

  List<Map<String, dynamic>> operations(String op) => requests
      .where((request) => request['op'] == op)
      .toList(growable: false);

  @override
  bool get isInitialized => online;

  @override
  Future<String> send(String message) async {
    final envelope = jsonDecode(message) as Map<String, dynamic>;
    if (envelope['cmd'] != 'active_identity_reporter_v1') {
      throw StateError('Unexpected nonlocal reporter command');
    }
    final payload = Map<String, dynamic>.from(envelope['payload'] as Map);
    requests.add(payload);
    final revision = payload['op'] == 'configure'
        ? ++_revision
        : payload['revision'] as int;
    final responder = answer;
    if (responder != null) return responder(payload, revision);
    return reply(payload, revision);
  }

  static String reply(Map<String, dynamic> request, int revision) => jsonEncode({
    'ok': true,
    'data': {
      'revision': revision,
      'consentEpoch': request['consentEpoch'],
      if (request['op'] == 'configure')
        'configured': request['enabled'] == true &&
            (request['profileBinding'] as String? ?? '').isNotEmpty &&
            (request['accountPeerId'] as String? ?? '').isNotEmpty,
      if (request['op'] == 'mark') 'accepted': true,
      if (request['op'] == 'flush') 'queued': true,
    },
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _LocalBridge bridge;
  late ActiveIdentityReporter reporter;

  setUp(() async {
    directory = await _bounded(Directory.systemTemp.createTemp('b294-dart-'));
    bridge = _LocalBridge();
    reporter = ActiveIdentityReporter(statePath: '${directory.path}/owner.json');
  });

  tearDown(() async {
    await _bounded(reporter.dispose());
    await _bounded(AppDiagnostics.instance.dispose());
    await _bounded(directory.delete(recursive: true));
  });

  Future<void> arm({IdentityModel? identity, String binding = _profileA}) async {
    reporter.attachBridge(bridge);
    final loadedIdentity = identity ?? _identity('A');
    reporter.observeIdentity(
      accountPeerId: loadedIdentity.peerId,
      rootPrivateKeyBase64: loadedIdentity.privateKey,
      profileBinding: binding,
    );
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch)));
    await _until(() => bridge.operations('configure').isNotEmpty);
  }

  test('configuration uses loaded logical root and never creates activity', () async {
    final root = _identity('A');
    final transportKey = base64Encode(List<int>.filled(64, 42));
    await arm(identity: root);
    final config = bridge.operations('configure').last;
    expect(config['version'], 1);
    expect(config['enabled'], isTrue);
    expect(config['consentEpoch'], _epoch);
    expect(config['profileBinding'], _profileA);
    expect(config['accountPeerId'], root.peerId);
    expect(config['rootPrivateKeyBase64'], root.privateKey);
    expect(jsonEncode(config), isNot(contains(transportKey)));
    expect(config['statePath'], '${directory.path}/owner.json');
    expect(config.containsKey('revision'), isFalse,
        reason: 'Only native receipt may issue an admission revision');
    expect(bridge.operations('mark'), isEmpty);
    expect(await _bounded(directory.list().toList()), isEmpty,
        reason: 'The Dart coordinator owns no archive or event queue');
  });

  test('mark requires configured owner and carries its full captured fence', () async {
    reporter.attachBridge(bridge);
    reporter.observeIdentity(
      accountPeerId: _identity('A').peerId,
      rootPrivateKeyBase64: _identity('A').privateKey,
      profileBinding: _profileA,
    );
    reporter.mark();
    await _bounded(reporter.flush());
    expect(bridge.requests, isEmpty);
    await arm();
    reporter.mark();
    await _until(() => bridge.operations('mark').isNotEmpty);
    final mark = bridge.operations('mark').single;
    expect(mark, {
      'version': 1,
      'op': 'mark',
      'revision': 1,
      'consentEpoch': _epoch,
      'profileBinding': _profileA,
      'accountPeerId': _identity('A').peerId,
    });
    await _bounded(reporter.flush());
    final flush = bridge.operations('flush').single;
    expect(flush, {...mark, 'op': 'flush'});
    expect(jsonEncode([mark, flush]), isNot(contains(_identity('A').privateKey)));
  });

  test('late bridge attachment replays latest snapshots without marking', () async {
    reporter.observeIdentity(
      accountPeerId: _identity('A').peerId,
      rootPrivateKeyBase64: _identity('A').privateKey,
      profileBinding: _profileA,
    );
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch)));
    expect(bridge.requests, isEmpty);
    reporter.attachBridge(bridge);
    await _until(() => bridge.operations('configure').isNotEmpty);
    expect(bridge.operations('configure').last['accountPeerId'], _identity('A').peerId);
    expect(bridge.operations('mark'), isEmpty);
  });

  test('unresolved binding stays unarmed until a matching committed snapshot', () async {
    reporter.attachBridge(bridge);
    reporter.observeIdentity(
      accountPeerId: _identity('A').peerId,
      rootPrivateKeyBase64: _identity('A').privateKey,
    );
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch)));
    expect(bridge.requests, isEmpty,
        reason: 'Unknown startup must not tombstone inert disk recovery');
    reporter.mark();
    expect(bridge.operations('mark'), isEmpty);
    expect(bridge.operations('configure').where((r) =>
        (r['rootPrivateKeyBase64'] as String? ?? '').isNotEmpty), isEmpty);
    reporter.observeIdentity(
      accountPeerId: _identity('A').peerId,
      rootPrivateKeyBase64: _identity('A').privateKey,
      profileBinding: _profileA,
    );
    await _until(() => bridge.operations('configure').any((r) => r['profileBinding'] == _profileA));
    reporter.mark();
    await _until(() => bridge.operations('mark').isNotEmpty);
  });

  test('late A configuration completion cannot replace B owner token', () async {
    final releaseA = Completer<void>();
    Future<void>? first;
    bridge.answer = (request, revision) async {
      if (request['op'] == 'configure' && request['profileBinding'] == _profileA) {
        await _bounded(releaseA.future);
      }
      return _LocalBridge.reply(request, revision);
    };
    try {
      reporter.attachBridge(bridge);
      reporter.observeIdentity(
        accountPeerId: _identity('A').peerId,
        rootPrivateKeyBase64: _identity('A').privateKey,
        profileBinding: _profileA,
      );
      first = reporter.observeConsent((enabled: true, consentEpoch: _epoch));
      await _until(() => bridge.operations('configure').isNotEmpty);
      reporter.observeIdentity(
        accountPeerId: _identity('B').peerId,
        rootPrivateKeyBase64: _identity('B').privateKey,
        profileBinding: _profileB,
      );
      await _until(() => bridge.operations('configure').any((r) => r['profileBinding'] == _profileB));
      await Future<void>.delayed(Duration.zero);
      releaseA.complete();
      await _bounded(first);
      reporter.mark();
      await _until(() => bridge.operations('mark').isNotEmpty);
      final mark = bridge.operations('mark').last;
      expect(mark['revision'], 2);
      expect(mark['profileBinding'], _profileB);
      expect(mark['accountPeerId'], _identity('B').peerId);
    } finally {
      if (!releaseA.isCompleted) releaseA.complete();
      if (first != null) await _bounded(first);
    }
  });

  test('OFF invalidates mark immediately while disable response is held', () async {
    await arm();
    final release = Completer<void>();
    Future<void>? disable;
    bridge.answer = (request, revision) async {
      if (request['op'] == 'configure' && request['enabled'] == false) {
        await _bounded(release.future);
      }
      return _LocalBridge.reply(request, revision);
    };
    try {
      var completed = false;
      disable = reporter.observeConsent((enabled: false, consentEpoch: _epoch + 1))
          .whenComplete(() => completed = true);
      reporter.mark();
      await _until(() => bridge.operations('configure').any((r) => r['enabled'] == false));
      expect(completed, isFalse);
      expect(bridge.operations('mark'), isEmpty);
      release.complete();
      await _bounded(disable);
      expect(completed, isTrue);
    } finally {
      if (!release.isCompleted) release.complete();
      if (disable != null) await _bounded(disable);
    }
  });

  test('clear epoch needs a new configured token before any new mark', () async {
    await arm();
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch + 1)));
    reporter.mark();
    await _until(() => bridge.operations('mark').isNotEmpty);
    expect(bridge.operations('mark').last['consentEpoch'], _epoch + 1);
    expect(bridge.operations('mark').last['revision'], 2);
    expect(bridge.operations('configure').last['consentEpoch'], _epoch + 1);
  });

  test('explicit retirement clears while disposal preserves inert restart state', () async {
    await arm();
    await _bounded(reporter.retire());
    final retired = bridge.operations('configure').last;
    expect(retired['profileBinding'], '');
    expect(retired['accountPeerId'], '');
    expect(retired['rootPrivateKeyBase64'], anyOf(isNull, ''));
    expect(retired['preservePendingOnUnarm'], isFalse);
    reporter.mark();
    expect(bridge.operations('mark'), isEmpty);
    reporter.observeIdentity(
      accountPeerId: _identity('A').peerId,
      rootPrivateKeyBase64: _identity('A').privateKey,
      profileBinding: _profileA,
    );
    await _until(() => bridge.operations('configure').last['profileBinding'] == _profileA);
    await _bounded(reporter.dispose());
    final disposed = bridge.operations('configure').last;
    expect(disposed['profileBinding'], '');
    expect(disposed['accountPeerId'], '');
    expect(disposed['preservePendingOnUnarm'], isTrue);
    expect(disposed['consentEpoch'], _epoch);
    final count = bridge.requests.length;
    reporter.observeIdentity(
      accountPeerId: _identity('B').peerId,
      rootPrivateKeyBase64: _identity('B').privateKey,
      profileBinding: _profileB,
    );
    reporter.mark();
    await _bounded(reporter.flush());
    expect(bridge.requests.length, count);
  });

  test('null identity retires synchronously before any replacement is loaded', () async {
    await arm();
    reporter.observeIdentity(
      accountPeerId: null,
      rootPrivateKeyBase64: null,
    );
    reporter.mark();
    await _until(() => bridge.operations('configure').last['profileBinding'] == '');
    expect(bridge.operations('mark'), isEmpty);
    expect(bridge.operations('configure').last['preservePendingOnUnarm'], isFalse);
    reporter.observeIdentity(
      accountPeerId: _identity('B').peerId,
      rootPrivateKeyBase64: _identity('B').privateKey,
      profileBinding: _profileB,
    );
    await _until(() => bridge.operations('configure').last['profileBinding'] == _profileB);
    await Future<void>.delayed(Duration.zero);
    reporter.mark();
    await _until(() => bridge.operations('mark').isNotEmpty);
    expect(bridge.operations('mark').last['accountPeerId'], _identity('B').peerId);
  });

  test('null consent unarms and preserves without inventing an OFF epoch', () async {
    await arm();
    await _bounded(reporter.observeConsent(null));
    final unarmed = bridge.operations('configure').last;
    expect(unarmed['profileBinding'], '');
    expect(unarmed['accountPeerId'], '');
    expect(unarmed['preservePendingOnUnarm'], isTrue);
    expect(unarmed['consentEpoch'], _epoch);
    reporter.mark();
    expect(bridge.operations('mark'), isEmpty);
    final count = bridge.requests.length;
    reporter.observeIdentity(
      accountPeerId: _identity('B').peerId,
      rootPrivateKeyBase64: _identity('B').privateKey,
      profileBinding: _profileB,
    );
    await _bounded(reporter.flush());
    expect(bridge.requests.length, count,
        reason: 'Identity discovery alone cannot restore disposed consent');
  });

  test('same-root metadata refresh does not generate a mark or retire pending', () async {
    await arm();
    final count = bridge.requests.length;
    reporter.observeIdentity(
      accountPeerId: _identity('A', username: 'renamed').peerId,
      rootPrivateKeyBase64: _identity('A', username: 'renamed').privateKey,
      profileBinding: _profileA,
    );
    await _bounded(reporter.flush());
    expect(bridge.operations('mark'), isEmpty);
    expect(bridge.requests.skip(count).where((r) =>
        r['op'] == 'configure' && r['profileBinding'] == ''), isEmpty);
    reporter.mark();
    await _until(() => bridge.operations('mark').isNotEmpty);
    expect(bridge.operations('mark').last['accountPeerId'], _identity('A').peerId);
  });

  test('wrong-epoch and malformed configure replies cannot arm', () async {
    await arm();
    reporter.mark();
    await _until(() => bridge.operations('mark').isNotEmpty);
    final originalMarks = bridge.operations('mark').length;
    final replies = <String Function(int)>[
      (_) => '{"ok":true,"data":{"configured":true,"revision":2,"consentEpoch":999}}',
      (epoch) => jsonEncode({'ok': true, 'data': {'configured': true, 'revision': null, 'consentEpoch': epoch}}),
      (epoch) => jsonEncode({'ok': true, 'data': {'configured': null, 'revision': 2, 'consentEpoch': epoch}}),
      (epoch) => jsonEncode({'ok': true, 'data': {'configured': false, 'revision': 2, 'consentEpoch': epoch}}),
      (_) => '{malformed $_privateError',
    ];
    for (var index = 0; index < replies.length; index++) {
      final epoch = _epoch + index + 1;
      final reply = replies[index](epoch);
      bridge.answer = (_, _) async => reply;
      final configs = bridge.operations('configure').length;
      await _bounded(reporter.observeConsent((enabled: true, consentEpoch: epoch)));
      expect(bridge.operations('configure').length, greaterThan(configs),
          reason: 'Every negative response needs a fresh attempted configuration');
      reporter.mark();
      await Future<void>.delayed(Duration.zero);
      expect(bridge.operations('mark').length, originalMarks);
    }
  });

  test('configure timeout and throwing bridge do not own communication', () async {
    await arm();
    final release = Completer<void>();
    Future<void>? update;
    bridge.answer = (request, revision) => release.future.then((_) =>
        _LocalBridge.reply(request, revision));
    try {
      fakeAsync((clock) {
        try {
          var complete = false;
          var communicationCompleted = false;
          update = reporter.observeConsent((enabled: false, consentEpoch: _epoch + 1))
              .whenComplete(() => complete = true);
          Future<void>.value().then((_) => communicationCompleted = true);
          clock.flushMicrotasks();
          expect(bridge.operations('configure').last['enabled'], isFalse);
          expect(communicationCompleted, isTrue);
          expect(complete, isFalse);
          clock.elapse(_limit);
          clock.flushMicrotasks();
          expect(complete, isTrue);
        } finally {
          if (!release.isCompleted) release.complete();
          clock.flushMicrotasks();
        }
      });
      if (update != null) await _bounded(update!);
      reporter.mark();
      expect(bridge.operations('mark'), isEmpty);
    } finally {
      if (!release.isCompleted) release.complete();
      if (update != null) await _bounded(update!);
    }
    bridge.answer = (_, _) async => throw PlatformException(code: 'LOCAL_FAILURE', message: _privateError);
    await _bounded(reporter.observeConsent((enabled: false, consentEpoch: _epoch + 2)));
    expect(await _bounded(Future<String>.value('second communication completed')), 'second communication completed');
  });

  test('native transport failure emits no private text or recursive telemetry', () async {
    final diagnostics = await _bounded(AppDiagnostics.installForTesting(
      directory: Directory('${directory.path}/diagnostics'),
      useNative: false,
      enabled: true,
    ));
    final events = <Map<String, dynamic>>[];
    final lease = installScopedE2EFlowEventSink(events.add);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const methodChannel = MethodChannel('com.mknoon/go_bridge');
    const eventChannel = MethodChannel('com.mknoon/go_bridge_events');
    var nativeCalls = 0;
    var failNative = false;
    final client = GoBridgeClient();
    messenger.setMockMethodCallHandler(eventChannel, (_) async => null);
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      expect(call.method, 'activeIdentityReporterV1');
      nativeCalls++;
      if (failNative) throw PlatformException(code: 'LOCAL_FAILURE', message: _privateError);
      final request = jsonDecode(call.arguments as String) as Map<String, dynamic>;
      return _LocalBridge.reply(request, nativeCalls);
    });
    try {
      await _bounded(client.initialize());
      reporter.attachBridge(client);
      reporter.observeIdentity(
        accountPeerId: _identity('A').peerId,
        rootPrivateKeyBase64: _identity('A').privateKey,
        profileBinding: _profileA,
      );
      await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch)));
      expect(nativeCalls, greaterThan(0), reason: 'Privacy requires a real positive native-call control');
      final before = (await _bounded(diagnostics.status()))['retainedEvents'];
      failNative = true;
      await _bounded(reporter.observeConsent((enabled: false, consentEpoch: _epoch + 1)));
      final preview = await _bounded(diagnostics.exportPreview());
      final captured = jsonEncode(events);
      for (final secret in [_privateError, _identity('A').privateKey, _identity('A').peerId, _profileA]) {
        expect('$captured$preview', isNot(contains(secret)));
      }
      expect((await _bounded(diagnostics.status()))['retainedEvents'], before,
          reason: 'Reporter bridge failure must not report itself recursively');
    } finally {
      await _bounded(reporter.dispose());
      client.dispose();
      await Future<void>.delayed(Duration.zero);
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockMethodCallHandler(eventChannel, null);
      lease.release();
    }
  });

  ActiveIdentityReporterCapture captureFor(
    ActiveIdentityReporter owner, {
    String? account,
  }) {
    final capture = owner.captureOwner(
      expectedAccountPeerId: account ?? _identity('A').peerId,
    );
    expect(capture, isNotNull, reason: 'Capture the logical owner before work');
    return capture!;
  }

  Future<void> turn() => _bounded(Future<void>(() {}));

  void freshIdentityCommitted({String? account}) {
    try {
      (reporter as dynamic).freshIdentityCommitted(
        accountPeerId: account ?? _identity('A').peerId,
        occurredAtUnixMillis: _qualificationUnixMillis,
      );
    } on NoSuchMethodError {
      // The old reporter drops this qualifying event before runtime readiness.
    }
  }

  Future<void> observeUninitializedOwner() async {
    bridge.online = false;
    reporter.attachBridge(bridge);
    reporter.observeIdentity(
      accountPeerId: _identity('A').peerId,
      rootPrivateKeyBase64: _identity('A').privateKey,
      profileBinding: _profileA,
    );
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch)));
  }

  test('B15REG committed registration survives its original bridge readiness', () async {
    await observeUninitializedOwner();
    freshIdentityCommitted();
    expect(bridge.operations('mark'), isEmpty);
    final configured = Completer<String>();
    String? receipt;
    bridge.answer = (request, revision) {
      receipt = _LocalBridge.reply(request, revision);
      return configured.future;
    };
    try {
      bridge.online = true;
      reporter.attachBridge(bridge);
      await _until(() => receipt != null);
      expect(bridge.operations('mark'), isEmpty);
      bridge.answer = null;
      configured.complete(receipt!);
      await _until(() => bridge.operations('mark').isNotEmpty);
      final mark = bridge.operations('mark').single;
      expect(mark['accountPeerId'], _identity('A').peerId);
      expect(mark['profileBinding'], _profileA);
      expect(mark['consentEpoch'], _epoch);
      expect(mark['occurredAtUnixMillis'], _qualificationUnixMillis);
      reporter.attachBridge(bridge);
      await turn();
      expect(bridge.operations('mark'), hasLength(1));
    } finally {
      bridge.answer = null;
      if (!configured.isCompleted) configured.complete(receipt ?? '{}');
    }
  });

  test('B15REG committed registration marks an already configured owner', () async {
    await arm();
    freshIdentityCommitted();
    await _until(() => bridge.operations('mark').isNotEmpty);
    final mark = bridge.operations('mark').single;
    expect(mark['occurredAtUnixMillis'], _qualificationUnixMillis);
    expect(mark['revision'], 1);
    expect(bridge.operations('markWeekly'), isEmpty);
  });

  test('B15REG bridge readiness alone never creates registration activity', () async {
    await observeUninitializedOwner();
    bridge.online = true;
    reporter.attachBridge(bridge);
    await _until(() => bridge.operations('configure').isNotEmpty);
    await turn();
    expect(bridge.operations('mark'), isEmpty);
  });

  for (final replacement in [
    'off-on',
    'same-epoch configure',
    'bridge',
    'profile',
    'A-B-A',
    'retire',
    'dispose',
  ]) {
    test('B15REG pending registration is fenced by $replacement', () async {
      await observeUninitializedOwner();
      freshIdentityCommitted();
      switch (replacement) {
        case 'off-on':
          await _bounded(reporter.observeConsent((enabled: false, consentEpoch: _epoch + 1)));
          await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch + 2)));
          break;
        case 'same-epoch configure':
          await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch)));
          break;
        case 'bridge':
          bridge = _LocalBridge()..online = false;
          reporter.attachBridge(bridge);
          break;
        case 'profile':
          reporter.observeIdentity(
            accountPeerId: _identity('A').peerId,
            rootPrivateKeyBase64: _identity('A').privateKey,
            profileBinding: _profileB,
          );
          break;
        case 'A-B-A':
          for (final suffix in ['B', 'A']) {
            reporter.observeIdentity(
              accountPeerId: _identity(suffix).peerId,
              rootPrivateKeyBase64: _identity(suffix).privateKey,
              profileBinding: suffix == 'A' ? _profileA : _profileB,
            );
          }
          break;
        case 'retire':
          await _bounded(reporter.retire());
          reporter.observeIdentity(
            accountPeerId: _identity('A').peerId,
            rootPrivateKeyBase64: _identity('A').privateKey,
            profileBinding: _profileA,
          );
          break;
        case 'dispose':
          await _bounded(reporter.dispose());
          break;
      }
      bridge.online = true;
      reporter.attachBridge(bridge);
      await turn();
      expect(bridge.operations('mark'), isEmpty);
    });
  }

  test('B15REG wrong account never queues a registration mark', () async {
    await observeUninitializedOwner();
    freshIdentityCommitted(account: _identity('B').peerId);
    bridge.online = true;
    reporter.attachBridge(bridge);
    await turn();
    expect(bridge.operations('mark'), isEmpty);
  });

  test('B15REG disabled creation never queues a mark for a new consent epoch', () async {
    await observeUninitializedOwner();
    await _bounded(reporter.observeConsent((enabled: false, consentEpoch: _epoch + 1)));
    freshIdentityCommitted();
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch + 2)));
    bridge.online = true;
    reporter.attachBridge(bridge);
    await turn();
    expect(bridge.operations('mark'), isEmpty);
  });

  test('B15REG held registration receipt cannot spend a successor consent epoch', () async {
    await observeUninitializedOwner();
    freshIdentityCommitted();
    final configured = Completer<String>();
    String? originalReceipt;
    bridge.answer = (request, revision) {
      originalReceipt = _LocalBridge.reply(request, revision);
      return configured.future;
    };
    try {
      bridge.online = true;
      reporter.attachBridge(bridge);
      await _until(() => originalReceipt != null);
      bridge.answer = null;
      await _bounded(reporter.observeConsent((enabled: false, consentEpoch: _epoch + 1)));
      await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch + 2)));
      configured.complete(originalReceipt!);
      await turn();
      expect(bridge.operations('mark'), isEmpty);
    } finally {
      bridge.answer = null;
      if (!configured.isCompleted) configured.complete(originalReceipt ?? '{}');
    }
  });

  Object? logicalProfileMarker() {
    try {
      return (reporter as dynamic).logicalProfileMarker;
    } on NoSuchMethodError {
      return null;
    }
  }

  ActiveIdentityReporterCapture? captureLoadedProfile(Object marker) {
    try {
      return (reporter as dynamic).captureForLoadedProfile(
            originalProfileMarker: marker,
            expectedAccountPeerId: _identity('A').peerId,
          )
          as ActiveIdentityReporterCapture?;
    } on NoSuchMethodError {
      return null;
    }
  }

  test('B15LO logical profile is pinned before bridge initialization', () async {
    expect(logicalProfileMarker(), isNull);
    reporter.observeIdentity(
      accountPeerId: _identity('A').peerId,
      rootPrivateKeyBase64: _identity('A').privateKey,
      profileBinding: _profileA,
    );
    final marker = logicalProfileMarker();
    expect(marker, isNotNull);
    expect(captureLoadedProfile(marker!), isNull);
    bridge.online = false;
    reporter.attachBridge(bridge);
    await _bounded(
      reporter.observeConsent((enabled: true, consentEpoch: _epoch)),
    );
    expect(logicalProfileMarker(), same(marker));
    expect(captureLoadedProfile(marker), isNull);
    bridge.online = true;
    reporter.attachBridge(bridge);
    await turn();
    expect(logicalProfileMarker(), same(marker));
    expect(captureLoadedProfile(marker), isNotNull);
    expect(bridge.operations('mark'), isEmpty);
  });

  test('B15LO loaded profile can be pinned while diagnostics is OFF', () async {
    await _bounded(arm());
    await _bounded(
      reporter.observeConsent((enabled: false, consentEpoch: _epoch + 1)),
    );
    final marker = logicalProfileMarker();
    expect(marker, isNotNull);
    expect(logicalProfileMarker(), same(marker));
    expect(captureLoadedProfile(marker!), isNull);
    for (final secret in [
      _identity('A').peerId,
      _identity('A').privateKey,
      _profileA,
    ]) {
      expect('$marker', isNot(contains(secret)));
    }
    await turn();
    expect(bridge.operations('mark'), isEmpty);
  });

  test('B15LO ON renews capture for original profile without marking', () async {
    await _bounded(arm());
    final marker = logicalProfileMarker();
    expect(marker, isNotNull);
    final before = captureLoadedProfile(marker!);
    expect(before, isNotNull);
    await _bounded(
      reporter.observeConsent((enabled: false, consentEpoch: _epoch + 1)),
    );
    expect(logicalProfileMarker(), same(marker));
    expect(captureLoadedProfile(marker), isNull);
    await _bounded(
      reporter.observeConsent((enabled: true, consentEpoch: _epoch + 2)),
    );
    expect(logicalProfileMarker(), same(marker));
    final after = captureLoadedProfile(marker);
    expect(after, isNotNull);
    expect(bridge.operations('mark'), isEmpty);
    reporter.markCaptured(before!);
    await turn();
    expect(bridge.operations('mark'), isEmpty);
    reporter.markCaptured(after!);
    await turn();
    expect(bridge.operations('mark'), hasLength(1));
    expect(bridge.operations('mark').single['consentEpoch'], _epoch + 2);
  });

  test('B15LO same account in another profile cannot rebrand loaded data', () async {
    await _bounded(arm());
    final original = logicalProfileMarker();
    expect(original, isNotNull);
    reporter.observeIdentity(
      accountPeerId: _identity('A').peerId,
      rootPrivateKeyBase64: _identity('A').privateKey,
      profileBinding: _profileB,
    );
    await turn();
    final replacement = logicalProfileMarker();
    expect(replacement, isNotNull);
    expect(replacement, isNot(same(original)));
    expect(captureLoadedProfile(original!), isNull);
    expect(captureLoadedProfile(replacement!), isNotNull);
    expect(bridge.operations('mark'), isEmpty);
  });

  test('B15LO returning to a profile never revives its old marker', () async {
    await _bounded(arm());
    final original = logicalProfileMarker();
    expect(original, isNotNull);
    reporter.observeIdentity(
      accountPeerId: _identity('B').peerId,
      rootPrivateKeyBase64: _identity('B').privateKey,
      profileBinding: _profileB,
    );
    await turn();
    reporter.observeIdentity(
      accountPeerId: _identity('A').peerId,
      rootPrivateKeyBase64: _identity('A').privateKey,
      profileBinding: _profileA,
    );
    await turn();
    expect(logicalProfileMarker(), isNot(same(original)));
    expect(captureLoadedProfile(original!), isNull);
    final replacement = logicalProfileMarker();
    expect(replacement, isNotNull);
    expect(captureLoadedProfile(replacement!), isNotNull);
    expect(bridge.operations('mark'), isEmpty);
  });

  test('B15LO configuration preserves profile marker and retirement clears it', () async {
    await _bounded(arm());
    final marker = logicalProfileMarker();
    expect(marker, isNotNull);
    reporter.attachBridge(_LocalBridge());
    await turn();
    expect(logicalProfileMarker(), same(marker));
    expect(captureLoadedProfile(marker!), isNotNull);
    await _bounded(reporter.retire());
    expect(logicalProfileMarker(), isNull);
    expect(captureLoadedProfile(marker), isNull);
    await _bounded(reporter.dispose());
    expect(logicalProfileMarker(), isNull);
  });

  test('E2D-001 capture alone never marks and unavailable owners stay uncaptured', () async {
    final account = _identity('A').peerId;
    expect(reporter.captureOwner(expectedAccountPeerId: account), isNull);
    reporter.attachBridge(bridge);
    reporter.observeIdentity(
      accountPeerId: account,
      rootPrivateKeyBase64: _identity('A').privateKey,
      profileBinding: _profileA,
    );
    expect(reporter.captureOwner(expectedAccountPeerId: account), isNull);
    await arm();
    captureFor(reporter);
    expect(reporter.captureOwner(expectedAccountPeerId: _identity('B').peerId), isNull);
    await turn();
    expect(bridge.operations('mark'), isEmpty);
    bridge.online = false;
    expect(reporter.captureOwner(expectedAccountPeerId: account), isNull);
    bridge.online = true;
    await _bounded(reporter.observeConsent((enabled: false, consentEpoch: _epoch + 1)));
    expect(reporter.captureOwner(expectedAccountPeerId: account), isNull);
    await _bounded(reporter.observeConsent(null));
    expect(reporter.captureOwner(expectedAccountPeerId: account), isNull);
    await _bounded(reporter.dispose());
    expect(reporter.captureOwner(expectedAccountPeerId: account), isNull);
    expect(bridge.operations('mark'), isEmpty);
  });

  test('E2D-002 captured current owner emits only the existing full native fence', () async {
    await arm();
    final capture = captureFor(reporter);
    expect(bridge.operations('mark'), isEmpty);
    reporter.markCaptured(capture);
    await _until(() => bridge.operations('mark').isNotEmpty);
    expect(bridge.operations('mark'), [
      {
        'version': 1,
        'op': 'mark',
        'revision': 1,
        'consentEpoch': _epoch,
        'profileBinding': _profileA,
        'accountPeerId': _identity('A').peerId,
      },
    ]);
    expect(jsonEncode(bridge.operations('mark')), isNot(contains(_identity('A').privateKey)));
  });

  test('E2D-003 pending configuration binds its eventual native revision to the capture', () async {
    final release = Completer<void>();
    Future<void>? configuration;
    bridge.answer = (request, revision) async {
      if (request['op'] == 'configure' && request['profileBinding'] == _profileA) {
        await _bounded(release.future);
      }
      return _LocalBridge.reply(request, revision);
    };
    try {
      reporter.attachBridge(bridge);
      reporter.observeIdentity(
        accountPeerId: _identity('A').peerId,
        rootPrivateKeyBase64: _identity('A').privateKey,
        profileBinding: _profileA,
      );
      configuration = reporter.observeConsent((enabled: true, consentEpoch: _epoch));
      await _until(() => bridge.operations('configure').isNotEmpty);
      final capture = captureFor(reporter);
      reporter.markCaptured(capture);
      await turn();
      expect(bridge.operations('mark'), isEmpty,
          reason: 'Only a successful native receipt supplies the revision');
      release.complete();
      await _bounded(configuration);
      await _until(() => bridge.operations('mark').isNotEmpty);
      final mark = bridge.operations('mark').single;
      expect(mark['revision'], 1);
      expect(mark['accountPeerId'], _identity('A').peerId);
      expect(mark['profileBinding'], _profileA);
      expect(mark['consentEpoch'], _epoch);
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
      if (configuration != null) {
        await _bounded(configuration);
      }
    }
  });

  test('E2D-004 late pending account A capture never acquires account B owner', () async {
    final releaseA = Completer<void>();
    Future<void>? configurationA;
    bridge.answer = (request, revision) async {
      if (request['op'] == 'configure' && request['accountPeerId'] == _identity('A').peerId) {
        await _bounded(releaseA.future);
      }
      return _LocalBridge.reply(request, revision);
    };
    try {
      reporter.attachBridge(bridge);
      reporter.observeIdentity(
        accountPeerId: _identity('A').peerId,
        rootPrivateKeyBase64: _identity('A').privateKey,
        profileBinding: _profileA,
      );
      configurationA = reporter.observeConsent((enabled: true, consentEpoch: _epoch));
      await _until(() => bridge.operations('configure').isNotEmpty);
      final stale = captureFor(reporter);
      reporter.markCaptured(stale);
      reporter.observeIdentity(
        accountPeerId: _identity('B').peerId,
        rootPrivateKeyBase64: _identity('B').privateKey,
        profileBinding: _profileA,
      );
      await _until(() => bridge.operations('configure').any((r) => r['accountPeerId'] == _identity('B').peerId));
      await turn();
      releaseA.complete();
      await _bounded(configurationA);
      reporter.markCaptured(stale);
      await turn();
      expect(bridge.operations('mark'), isEmpty);
      reporter.markCaptured(captureFor(reporter, account: _identity('B').peerId));
      await _until(() => bridge.operations('mark').isNotEmpty);
      final mark = bridge.operations('mark').single;
      expect(mark['accountPeerId'], _identity('B').peerId);
      expect(mark['revision'], 2);
    } finally {
      if (!releaseA.isCompleted) {
        releaseA.complete();
      }
      if (configurationA != null) {
        await _bounded(configurationA);
      }
    }
  });

  test('E2D-005 changed profile invalidates the old capture for the same account', () async {
    await arm();
    final stale = captureFor(reporter);
    reporter.observeIdentity(
      accountPeerId: _identity('A').peerId,
      rootPrivateKeyBase64: _identity('A').privateKey,
      profileBinding: _profileB,
    );
    await _until(() => bridge.operations('configure').last['profileBinding'] == _profileB);
    await turn();
    reporter.markCaptured(stale);
    await turn();
    expect(bridge.operations('mark'), isEmpty);
    reporter.markCaptured(captureFor(reporter));
    await _until(() => bridge.operations('mark').isNotEmpty);
    expect(bridge.operations('mark').single['profileBinding'], _profileB);
  });

  test('E2D-006 changed consent epoch invalidates the old capture', () async {
    await arm();
    final stale = captureFor(reporter);
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch + 1)));
    reporter.markCaptured(stale);
    await turn();
    expect(bridge.operations('mark'), isEmpty);
    reporter.markCaptured(captureFor(reporter));
    await _until(() => bridge.operations('mark').isNotEmpty);
    expect(bridge.operations('mark').single['consentEpoch'], _epoch + 1);
  });

  test('E2D-007 same tuple reconfiguration still invalidates its prior runtime capture', () async {
    final release = Completer<void>();
    Future<void>? firstConfiguration;
    bridge.answer = (request, revision) async {
      if (request['op'] == 'configure' && revision == 1) {
        await _bounded(release.future);
      }
      return _LocalBridge.reply(request, revision);
    };
    try {
      reporter.attachBridge(bridge);
      reporter.observeIdentity(
        accountPeerId: _identity('A').peerId,
        rootPrivateKeyBase64: _identity('A').privateKey,
        profileBinding: _profileA,
      );
      firstConfiguration = reporter.observeConsent((enabled: true, consentEpoch: _epoch));
      await _until(() => bridge.operations('configure').isNotEmpty);
      final stale = captureFor(reporter);
      reporter.markCaptured(stale);
      await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch)));
      release.complete();
      await _bounded(firstConfiguration);
      reporter.markCaptured(stale);
      await turn();
      expect(bridge.operations('mark'), isEmpty);
      reporter.markCaptured(captureFor(reporter));
      await _until(() => bridge.operations('mark').isNotEmpty);
      final mark = bridge.operations('mark').single;
      expect(mark['revision'], 2);
      expect(mark['accountPeerId'], _identity('A').peerId);
      expect(mark['profileBinding'], _profileA);
      expect(mark['consentEpoch'], _epoch);
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
      if (firstConfiguration != null) {
        await _bounded(firstConfiguration);
      }
    }
  });

  test('E2D-008 another reporter cannot spend the same tuple capture', () async {
    await arm();
    final otherBridge = _LocalBridge();
    final other = ActiveIdentityReporter(statePath: '${directory.path}/other.json');
    try {
      other.attachBridge(otherBridge);
      other.observeIdentity(
        accountPeerId: _identity('A').peerId,
        rootPrivateKeyBase64: _identity('A').privateKey,
        profileBinding: _profileA,
      );
      await _bounded(other.observeConsent((enabled: true, consentEpoch: _epoch)));
      reporter.markCaptured(captureFor(other));
      other.markCaptured(captureFor(reporter));
      await turn();
      expect(bridge.operations('mark'), isEmpty);
      expect(otherBridge.operations('mark'), isEmpty);
      other.mark();
      await _until(() => otherBridge.operations('mark').isNotEmpty);
      expect(otherBridge.operations('mark').single['accountPeerId'], _identity('A').peerId,
          reason: 'The foreign reporter was armed, not an inert negative fixture');
    } finally {
      await _bounded(other.dispose());
    }
  });

  test('E2D-009 unarm bridge replacement retirement and disposal reject old captures', () async {
    await arm();
    final beforeUnarm = captureFor(reporter);
    await _bounded(reporter.observeConsent(null));
    reporter.markCaptured(beforeUnarm);
    expect(reporter.captureOwner(expectedAccountPeerId: _identity('A').peerId), isNull);
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: _epoch)));
    final releaseOldBridge = Completer<void>();
    Future<void>? oldConfiguration;
    bridge.answer = (request, revision) async {
      if (request['op'] == 'configure' && request['profileBinding'] == _profileA) {
        await _bounded(releaseOldBridge.future);
      }
      return _LocalBridge.reply(request, revision);
    };
    try {
      oldConfiguration = reporter.observeConsent((enabled: true, consentEpoch: _epoch));
      final beforeBridgeChange = captureFor(reporter);
      reporter.markCaptured(beforeBridgeChange);
      final replacement = _LocalBridge();
      reporter.attachBridge(replacement);
      await _until(() => replacement.operations('configure').isNotEmpty);
      await turn();
      releaseOldBridge.complete();
      await _bounded(oldConfiguration);
      reporter.markCaptured(beforeBridgeChange);
      final beforeRetire = captureFor(reporter);
      await _bounded(reporter.retire());
      reporter.markCaptured(beforeRetire);
      expect(reporter.captureOwner(expectedAccountPeerId: _identity('A').peerId), isNull);
      reporter.observeIdentity(
        accountPeerId: _identity('A').peerId,
        rootPrivateKeyBase64: _identity('A').privateKey,
        profileBinding: _profileA,
      );
      await _until(() => replacement.operations('configure').last['profileBinding'] == _profileA);
      await turn();
      final beforeDispose = captureFor(reporter);
      await _bounded(reporter.dispose());
      reporter.markCaptured(beforeDispose);
      await turn();
      expect(reporter.captureOwner(expectedAccountPeerId: _identity('A').peerId), isNull);
      expect(bridge.operations('mark'), isEmpty);
      expect(replacement.operations('mark'), isEmpty);
    } finally {
      if (!releaseOldBridge.isCompleted) {
        releaseOldBridge.complete();
      }
      if (oldConfiguration != null) {
        await _bounded(oldConfiguration);
      }
    }
  });

  _CapturedOccurrenceMark occurrenceMark() {
    final Object method = reporter.markCaptured;
    expect(method, isA<_CapturedOccurrenceMark>(),
        reason: 'Core occurrence API must accept the optional qualification instant');
    return method as _CapturedOccurrenceMark;
  }

  test('OCC-001 captured immediate mark preserves the exact qualification instant and fence', () async {
    await arm();
    final mark = occurrenceMark();
    mark(captureFor(reporter), occurredAtUnixMillis: _qualificationUnixMillis);
    await _until(() => bridge.operations('mark').isNotEmpty);
    expect(bridge.operations('mark'), [
      {
        'version': 1,
        'revision': 1,
        'consentEpoch': _epoch,
        'profileBinding': _profileA,
        'accountPeerId': _identity('A').peerId,
        'op': 'mark',
        'occurredAtUnixMillis': _qualificationUnixMillis,
      },
    ]);
    expect(bridge.operations('mark').single['occurredAtUnixMillis'], isA<int>());
    expect(jsonEncode(bridge.operations('mark')), isNot(contains(_identity('A').privateKey)));
  });

  test('OCC-002 configuration deferral preserves the original qualification instant', () async {
    final mark = occurrenceMark();
    final release = Completer<void>();
    Future<void>? configuration;
    bridge.answer = (request, revision) async {
      if (request['op'] == 'configure' && revision == 1) {
        await _bounded(release.future);
      }
      return _LocalBridge.reply(request, revision);
    };
    try {
      reporter.attachBridge(bridge);
      reporter.observeIdentity(
        accountPeerId: _identity('A').peerId,
        rootPrivateKeyBase64: _identity('A').privateKey,
        profileBinding: _profileA,
      );
      configuration = reporter.observeConsent((enabled: true, consentEpoch: _epoch));
      await _until(() => bridge.operations('configure').isNotEmpty);
      final capture = captureFor(reporter);
      var producerInstant = _qualificationUnixMillis;
      mark(capture, occurredAtUnixMillis: producerInstant);
      producerInstant += const Duration(days: 1).inMilliseconds;
      await turn();
      expect(bridge.operations('mark'), isEmpty);
      release.complete();
      await _bounded(configuration);
      await _until(() => bridge.operations('mark').isNotEmpty);
      expect(bridge.operations('mark'), [
        {
          'version': 1,
          'revision': 1,
          'consentEpoch': _epoch,
          'profileBinding': _profileA,
          'accountPeerId': _identity('A').peerId,
          'op': 'mark',
          'occurredAtUnixMillis': _qualificationUnixMillis,
        },
      ]);
      expect(bridge.operations('mark').single['occurredAtUnixMillis'], isNot(producerInstant));
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
      if (configuration != null) {
        await _bounded(configuration);
      }
    }
  });

  test('OCC-003 omitted and explicit null occurrence retain the exact legacy mark payload', () async {
    await arm();
    final mark = occurrenceMark();
    final capture = captureFor(reporter);
    reporter.markCaptured(capture);
    await _until(() => bridge.operations('mark').length == 1);
    final legacy = jsonEncode({
      'version': 1,
      'revision': 1,
      'consentEpoch': _epoch,
      'profileBinding': _profileA,
      'accountPeerId': _identity('A').peerId,
      'op': 'mark',
    });
    expect(jsonEncode(bridge.operations('mark').single), legacy);
    mark(capture);
    mark(capture, occurredAtUnixMillis: null);
    await _until(() => bridge.operations('mark').length == 3);
    expect(bridge.operations('mark').map(jsonEncode), [legacy, legacy, legacy]);
    expect(bridge.operations('mark').any((r) => r.containsKey('occurredAtUnixMillis')), isFalse);
    mark(capture, occurredAtUnixMillis: _qualificationUnixMillis);
    await _until(() => bridge.operations('mark').length == 4);
    expect(bridge.operations('mark').last['occurredAtUnixMillis'], _qualificationUnixMillis);
    reporter.markCaptured(capture);
    await _until(() => bridge.operations('mark').length == 5);
    expect(jsonEncode(bridge.operations('mark').last), legacy,
        reason: 'A timestamp belongs to one operation, not the captured owner');
  });

  for (final deferred in [false, true]) {
    for (final change in ['identity', 'profile', 'consent epoch', 'OFF then ON', 'bridge', 'dispose']) {
      test('OCC-004 ${deferred ? 'deferred' : 'immediate'} occurrence rejects the original capture after $change', () async {
        final mark = occurrenceMark();
        final release = Completer<void>();
        Future<void>? configuration;
        var currentBridge = bridge;
        var currentAccount = _identity('A').peerId;
        var currentBinding = _profileA;
        var currentEpoch = _epoch;
        if (deferred) {
          bridge.answer = (request, revision) async {
            if (request['op'] == 'configure' && revision == 1) {
              await _bounded(release.future);
            }
            return _LocalBridge.reply(request, revision);
          };
        }
        try {
          if (deferred) {
            reporter.attachBridge(bridge);
            reporter.observeIdentity(
              accountPeerId: currentAccount,
              rootPrivateKeyBase64: _identity('A').privateKey,
              profileBinding: currentBinding,
            );
            configuration = reporter.observeConsent((enabled: true, consentEpoch: currentEpoch));
            await _until(() => bridge.operations('configure').isNotEmpty);
          } else {
            await arm();
          }
          final capture = captureFor(reporter);
          if (deferred) {
            mark(capture, occurredAtUnixMillis: _qualificationUnixMillis);
            await turn();
            expect(bridge.operations('mark'), isEmpty);
          }
          switch (change) {
            case 'identity':
              currentAccount = _identity('B').peerId;
              reporter.observeIdentity(
                accountPeerId: currentAccount,
                rootPrivateKeyBase64: _identity('B').privateKey,
                profileBinding: currentBinding,
              );
              await _until(() => bridge.operations('configure').last['accountPeerId'] == currentAccount);
              break;
            case 'profile':
              currentBinding = _profileB;
              reporter.observeIdentity(
                accountPeerId: currentAccount,
                rootPrivateKeyBase64: _identity('A').privateKey,
                profileBinding: currentBinding,
              );
              await _until(() => bridge.operations('configure').last['profileBinding'] == currentBinding);
              break;
            case 'consent epoch':
              currentEpoch++;
              await _bounded(reporter.observeConsent((enabled: true, consentEpoch: currentEpoch)));
              break;
            case 'OFF then ON':
              await _bounded(reporter.observeConsent((enabled: false, consentEpoch: currentEpoch + 1)));
              mark(capture, occurredAtUnixMillis: _qualificationUnixMillis);
              await turn();
              expect(bridge.operations('mark'), isEmpty);
              currentEpoch += 2;
              await _bounded(reporter.observeConsent((enabled: true, consentEpoch: currentEpoch)));
              break;
            case 'bridge':
              currentBridge = _LocalBridge();
              reporter.attachBridge(currentBridge);
              await _until(() => currentBridge.operations('configure').isNotEmpty);
              break;
            case 'dispose':
              await _bounded(reporter.dispose());
              break;
          }
          await turn();
          if (!release.isCompleted) {
            release.complete();
          }
          if (configuration != null) {
            await _bounded(configuration);
          }
          mark(capture, occurredAtUnixMillis: _qualificationUnixMillis);
          await turn();
          expect(bridge.operations('mark'), isEmpty);
          expect(currentBridge.operations('mark'), isEmpty);
          if (change != 'dispose') {
            mark(captureFor(reporter, account: currentAccount),
                occurredAtUnixMillis: _qualificationUnixMillis + 1);
            await _until(() => currentBridge.operations('mark').isNotEmpty);
            final fresh = currentBridge.operations('mark').single;
            expect(fresh.keys.toSet(), {
              'version', 'revision', 'consentEpoch', 'profileBinding',
              'accountPeerId', 'op', 'occurredAtUnixMillis',
            });
            expect(fresh['occurredAtUnixMillis'], _qualificationUnixMillis + 1);
            expect(fresh['accountPeerId'], currentAccount);
            expect(fresh['profileBinding'], currentBinding);
            expect(fresh['consentEpoch'], currentEpoch);
            final expectedRevision = change == 'bridge'
                ? 1
                : change == 'OFF then ON' ? 3 : 2;
            expect(fresh['revision'], expectedRevision);
          }
        } finally {
          if (!release.isCompleted) {
            release.complete();
          }
          if (configuration != null) {
            await _bounded(configuration);
          }
        }
      });
    }
  }

  test('E2D-010 captured emission never joins held or throwing optional native work', () async {
    await arm();
    final capture = captureFor(reporter);
    final entered = Completer<void>();
    final release = Completer<void>();
    final finished = Completer<void>();
    bridge.answer = (request, revision) async {
      if (request['op'] == 'mark') {
        if (!entered.isCompleted) {
          entered.complete();
        }
        try {
          await _bounded(release.future);
          throw StateError(_privateError);
        } finally {
          if (!finished.isCompleted) {
            finished.complete();
          }
        }
      }
      return _LocalBridge.reply(request, revision);
    };
    try {
      final communication = Future<String>.sync(() {
        reporter.markCaptured(capture);
        return 'communication-completed';
      });
      expect(await _bounded(communication), 'communication-completed');
      await _until(() => entered.isCompleted);
      expect(finished.isCompleted, isFalse);
      expect(bridge.operations('mark'), hasLength(1));
      release.complete();
      await _bounded(finished.future);
      await turn();
      await _bounded(reporter.flush());
      expect(bridge.operations('flush'), hasLength(1));
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
      if (entered.isCompleted) {
        await _bounded(finished.future);
      }
    }
  });
}
