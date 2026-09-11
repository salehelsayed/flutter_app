import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostic_events.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostic_schema.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

class DiagnosticBridge implements Bridge {
  bool online = true;
  final requests = <Map<String, dynamic>>[];
  Future<Map<String, Object?>> Function(Map<String, dynamic>)? response;
  @override
  bool get isInitialized => online;
  @override
  Future<String> send(String message) async {
    final envelope = jsonDecode(message) as Map;
    expect(envelope['cmd'], 'app_diagnostics_v1');
    final request = Map<String, dynamic>.from(envelope['payload'] as Map);
    requests.add(request);
    return jsonEncode({
      'ok': true,
      'data': response != null
          ? await response!(request)
          : {
              'supported': true,
              'enabled': request['enabled'] ?? true,
              'consentEpoch': request['consentEpoch'],
              'acceptedEventIds': (request['events'] as List? ?? [])
                  .map((e) => e['eventId'])
                  .toList(),
            },
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DateTime now;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('app-diagnostic-test-');
    now = DateTime.utc(2026, 9, 8);
  });
  tearDown(() async {
    await AppDiagnostics.instance.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  Future<AppDiagnostics> install({
    bool? enabled,
    Bridge? bridge,
    AppDiagnosticUpload? upload,
    Future<bool> Function()? networkAllowed,
    Future<dynamic> Function(String, Map<String, Object?>)? native,
    Future<void> Function(String, Map<String, Object?>)? persist,
  }) => AppDiagnostics.installForTesting(
    directory: directory,
    enabled: enabled,
    now: () => now,
    bridge: bridge,
    upload: upload,
    native: native,
    networkAllowed: networkAllowed,
    persist: persist,
  );

  test('producer and relay share one checked-in closed schema', () async {
    expect(
      appDiagnosticSchemaV1,
      jsonDecode(
        await File('tool/app_diagnostics/schema_v1.json').readAsString(),
      ),
    );
  });

  test('interaction events share one deferred persistence batch', () async {
    final saved = <Map<String, dynamic>>[];
    final diagnostics = await install(
      persist: (_, state) async {
        saved.add(jsonDecode(jsonEncode(state)) as Map<String, dynamic>);
      },
    );
    saved.clear();
    fakeAsync((clock) {
      for (var i = 0; i < 40; i++) {
        final trace = diagnostics.traceForOperation('operation-$i');
        diagnostics.startAttempt(feature: 'message', traceId: trace);
        expect(
          diagnostics.record(
            feature: 'message',
            stage: 'send',
            outcome: 'ok',
            traceId: trace,
          ),
          true,
        );
        diagnostics.finishAttempt(
          feature: 'message',
          traceId: trace,
          outcome: 'success',
        );
      }
      expect(saved, isEmpty);
      clock.flushMicrotasks();
      expect(saved, isEmpty);
      clock.elapse(const Duration(milliseconds: 999));
      expect(saved, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(saved, hasLength(1));
      expect(saved.single['bindings'], hasLength(40));
      expect(saved.single['events'], hasLength(120));
      expect(saved.single['open'], isEmpty);
      clock.elapse(const Duration(seconds: 5));
      expect(saved, hasLength(1));
    });
  });

  test('explicit flush persists a burst before its scheduled batch', () async {
    final saved = <Map<String, dynamic>>[];
    final diagnostics = await install(
      persist: (_, state) async {
        saved.add(jsonDecode(jsonEncode(state)) as Map<String, dynamic>);
      },
    );
    saved.clear();
    fakeAsync((clock) {
      final trace = diagnostics.traceForOperation('message-to-send');
      diagnostics.startAttempt(feature: 'message', traceId: trace);
      diagnostics.finishAttempt(
        feature: 'message',
        traceId: trace,
        outcome: 'success',
      );
      var flushed = false;
      unawaited(diagnostics.flush().then((_) => flushed = true));
      clock.flushMicrotasks();
      expect(flushed, true);
      expect(saved, hasLength(1));
      expect(saved.single['events'], hasLength(2));
      expect(saved.single['open'], isEmpty);
      clock.elapse(const Duration(seconds: 1));
      expect(saved, hasLength(1));
      for (var idleFlush = 0; idleFlush < 3; idleFlush++) {
        unawaited(diagnostics.flush());
        clock.flushMicrotasks();
      }
      expect(saved, hasLength(1));
    });
  });

  test(
    'joining an active flush persists events admitted before the join',
    () async {
      Completer<void>? release;
      final saved = <Map<String, dynamic>>[];
      final diagnostics = await install(
        persist: (_, state) async {
          saved.add(jsonDecode(jsonEncode(state)) as Map<String, dynamic>);
          if (release != null) await release!.future;
        },
      );
      saved.clear();
      fakeAsync((clock) {
        release = Completer<void>();
        try {
          diagnostics.record(feature: 'message', stage: 'send', outcome: 'ok');
          var initialCompleted = false;
          unawaited(diagnostics.flush().then((_) => initialCompleted = true));
          clock.flushMicrotasks();
          expect(saved, hasLength(1));
          expect(initialCompleted, false);
          expect(
            diagnostics.record(
              feature: 'message',
              stage: 'receive',
              outcome: 'ok',
            ),
            true,
          );
          var joiningCompleted = false;
          unawaited(diagnostics.flush().then((_) => joiningCompleted = true));
          clock.flushMicrotasks();
          expect(joiningCompleted, false);
          release!.complete();
          clock.flushMicrotasks();
          expect(joiningCompleted, true);
          expect(saved.last['events'], hasLength(2));
          clock.elapse(const Duration(seconds: 1));
          expect(saved, hasLength(2));
        } finally {
          if (!release!.isCompleted) release!.complete();
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 1));
          release = null;
        }
      });
    },
  );

  test('a held persistence write does not hold an interaction body', () async {
    Completer<void>? release;
    final saved = <Map<String, dynamic>>[];
    final diagnostics = await install(
      persist: (_, state) async {
        saved.add(jsonDecode(jsonEncode(state)) as Map<String, dynamic>);
        if (release != null) await release!.future;
      },
    );
    saved.clear();
    fakeAsync((clock) {
      release = Completer<void>();
      try {
        diagnostics.record(feature: 'message', stage: 'send', outcome: 'ok');
        clock.elapse(const Duration(seconds: 1));
        expect(saved, hasLength(1));
        String? result;
        unawaited(
          diagnostics
              .runWithAttempt(
                feature: 'message',
                body: (trace) async {
                  await Future<void>.value();
                  diagnostics.finishAttempt(
                    feature: 'message',
                    traceId: trace,
                    outcome: 'success',
                  );
                  return 'message delivered';
                },
              )
              .then((value) => result = value),
        );
        clock.flushMicrotasks();
        expect(result, 'message delivered');
        expect(release!.isCompleted, false);
        expect(saved, hasLength(1));
        clock.elapse(const Duration(milliseconds: 500));
        diagnostics.record(feature: 'message', stage: 'send', outcome: 'ok');
        release!.complete();
        clock.flushMicrotasks();
        expect(saved, hasLength(1));
        clock.elapse(const Duration(milliseconds: 499));
        expect(saved, hasLength(1));
        clock.elapse(const Duration(milliseconds: 1));
        expect(saved, hasLength(2));
        final events = saved.last['events'] as List;
        expect(events, hasLength(4));
        expect(
          events.singleWhere((event) => event['stage'] == 'finish')['outcome'],
          'success',
        );
        expect(saved.last['open'], isEmpty);
        clock.elapse(const Duration(seconds: 1));
        expect(saved, hasLength(2));
      } finally {
        if (!release!.isCompleted) release!.complete();
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        release = null;
      }
    });
  });

  test(
    'a failed deferred sink leaves interaction completion unchanged',
    () async {
      var failWrites = false;
      final diagnostics = await install(
        persist: (_, _) async {
          if (failWrites) throw const FileSystemException('unavailable');
        },
      );
      failWrites = true;
      fakeAsync((clock) {
        final result = diagnostics.runWithAttempt(
          feature: 'message',
          body: (trace) {
            diagnostics.finishAttempt(
              feature: 'message',
              traceId: trace,
              outcome: 'success',
            );
            return 'message delivered';
          },
        );
        expect(result, 'message delivered');
        clock.elapse(const Duration(seconds: 1));
        Map<String, Object?>? status;
        unawaited(diagnostics.status().then((value) => status = value));
        clock.flushMicrotasks();
        expect(status!['storageHealthy'], false);
        expect(status!['lastError'], 'sink_unavailable');
        expect(
          diagnostics.runWithAttempt(
            feature: 'message',
            body: (_) => 'next message delivered',
          ),
          'next message delivered',
        );
      });
    },
  );

  for (final disable in [false, true]) {
    test('pending snapshot cannot restore evidence after '
        '${disable ? 'opt-out' : 'clear'}', () async {
      Completer<void>? release;
      final saved = <Map<String, dynamic>>[];
      final diagnostics = await install(
        persist: (_, state) async {
          final snapshot =
              jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
          if (release != null && (snapshot['events'] as List).isNotEmpty) {
            await release!.future;
          }
          saved.add(snapshot);
        },
      );
      final originalEpoch = saved.last['consentEpoch'] as int;
      saved.clear();
      fakeAsync((clock) {
        release = Completer<void>();
        try {
          final trace = diagnostics.traceForOperation('private-operation');
          diagnostics.startAttempt(feature: 'message', traceId: trace);
          clock.elapse(const Duration(seconds: 1));
          expect(saved, isEmpty);
          var completed = false;
          unawaited(
            (disable ? diagnostics.setEnabled(false) : diagnostics.clear())
                .then((_) => completed = true),
          );
          clock.flushMicrotasks();
          expect(diagnostics.enabled, !disable);
          release!.complete();
          clock.flushMicrotasks();
          expect(completed, true);
          expect(saved.last['enabled'], !disable);
          expect(saved.last['consentEpoch'], greaterThan(originalEpoch));
          expect(saved.last['events'], isEmpty);
          expect(saved.last['open'], isEmpty);
          expect(saved.last['bindings'], isEmpty);
          clock.elapse(const Duration(seconds: 2));
          expect(saved.last['events'], isEmpty);
        } finally {
          if (!release!.isCompleted) release!.complete();
          clock.flushMicrotasks();
          release = null;
        }
      });
    });
  }

  test(
    'default-on configures native and relay before uploading real attempts',
    () async {
      final native = <Map<String, Object?>>[];
      final bridge = DiagnosticBridge();
      final diagnostics = await install(
        bridge: bridge,
        native: (method, data) async {
          if (method == 'configure') native.add(data);
          if (method == 'drain') {
            return {'version': 1, 'events': [], 'droppedEvents': 0};
          }
          return true;
        },
      );
      expect(diagnostics.enabled, true);
      expect(native.single['enabled'], true);
      expect(bridge.requests.first['op'], 'configure');
      expect(
        bridge.requests.first['consentEpoch'],
        native.single['consentEpoch'],
      );
      final trace = diagnostics.startAttempt(feature: 'message')!;
      diagnostics.finishAttempt(
        feature: 'message',
        traceId: trace,
        outcome: 'success',
      );
      await diagnostics.flush();
      final events = bridge.requests
          .where((r) => r['op'] == 'upload')
          .expand((r) => r['events'] as List)
          .where((e) => e['feature'] == 'message');
      expect(
        events.map((e) => e['stage']),
        unorderedEquals(['start', 'finish']),
      );
      expect((await diagnostics.status())['queuedEvents'], 0);
    },
  );

  test(
    'account network denial retains evidence without any relay request',
    () async {
      var allowed = false;
      final bridge = DiagnosticBridge();
      final diagnostics = await install(
        bridge: bridge,
        networkAllowed: () async => allowed,
      );
      final trace = diagnostics.startAttempt(feature: 'message')!;
      diagnostics.finishAttempt(
        feature: 'message',
        traceId: trace,
        outcome: 'failed',
        reason: 'offline',
      );
      await diagnostics.flush();
      expect(bridge.requests, isEmpty);
      expect((await diagnostics.status())['queuedEvents'], 2);
      allowed = true;
      now = now.add(const Duration(minutes: 6));
      await diagnostics.flush();
      expect(bridge.requests.map((r) => r['op']), ['configure', 'upload']);
      expect((await diagnostics.status())['queuedEvents'], 0);
    },
  );

  test('offline opt-out persists and revokes after restart', () async {
    final bridge = DiagnosticBridge();
    var diagnostics = await install(bridge: bridge);
    final epoch = bridge.requests.first['consentEpoch'] as int;
    bridge.online = false;
    await diagnostics.setEnabled(false);
    expect(await diagnostics.eventsForTesting(), isEmpty);
    bridge.online = true;
    bridge.requests.clear();
    diagnostics = await install(bridge: bridge);
    expect(diagnostics.enabled, false);
    expect(diagnostics.startAttempt(feature: 'message'), isNull);
    expect(bridge.requests.single['op'], 'configure');
    expect(bridge.requests.single['enabled'], false);
    expect(bridge.requests.single['consentEpoch'], greaterThan(epoch));
  });

  for (final state in [
    'invalid',
    '{"schemaVersion":2}',
    '{"schemaVersion":1}',
  ]) {
    test('unreadable saved preference stays off: $state', () async {
      await File('${directory.path}/state.json').writeAsString(state);
      final bridge = DiagnosticBridge();
      final diagnostics = await install(bridge: bridge);
      expect(diagnostics.enabled, false);
      expect(diagnostics.startAttempt(feature: 'message'), isNull);
      expect(bridge.requests, isEmpty);
    });
  }

  test(
    'retry shares trace but has separate attempts and preserves both outcomes',
    () async {
      final diagnostics = await install();
      final trace = diagnostics.startAttempt(feature: 'media')!;
      diagnostics.finishAttempt(
        feature: 'media',
        traceId: trace,
        outcome: 'failed',
        reason: 'io_failed',
      );
      diagnostics.finishAttempt(
        feature: 'media',
        traceId: trace,
        outcome: 'failed',
      );
      diagnostics.startAttempt(feature: 'media', traceId: trace);
      diagnostics.finishAttempt(
        feature: 'media',
        traceId: trace,
        outcome: 'success',
      );
      final events = await diagnostics.eventsForTesting();
      final terminals = events.where((e) => e['stage'] == 'finish').toList();
      expect(terminals.map((e) => e['outcome']), ['failed', 'success']);
      expect(terminals.map((e) => e['attemptId']).toSet(), hasLength(2));
      expect(terminals.every((e) => e['traceId'] == trace), true);
    },
  );

  test(
    'restart classifies durable open attempt as interrupted, never crash',
    () async {
      var diagnostics = await install();
      final trace = diagnostics.startAttempt(feature: 'startup')!;
      diagnostics = await install();
      final terminals = (await diagnostics.eventsForTesting())
          .where((e) => e['traceId'] == trace && e['stage'] == 'finish')
          .toList();
      expect(terminals, hasLength(1));
      expect(terminals.single['outcome'], 'interrupted_unknown');
      diagnostics = await install();
      expect(
        (await diagnostics.eventsForTesting()).where(
          (e) => e['traceId'] == trace && e['stage'] == 'finish',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'unknown acknowledgments do not discard reports; partial ACK retries remaining',
    () async {
      final batches = <List<Map<String, Object?>>>[];
      var phase = 0;
      final diagnostics = await install(
        upload: (events) async {
          if (events.every((e) => e['feature'] == 'runtime')) {
            return events.map((e) => e['eventId'] as String).toSet();
          }
          batches.add(events);
          if (phase == 0) return {'00000000-0000-4000-8000-000000000999'};
          if (phase == 1) return {events.first['eventId'] as String};
          return events.map((e) => e['eventId'] as String).toSet();
        },
      );
      final trace = diagnostics.startAttempt(feature: 'message')!;
      diagnostics.finishAttempt(
        feature: 'message',
        traceId: trace,
        outcome: 'success',
      );
      await diagnostics.flush();
      expect((await diagnostics.status())['queuedEvents'], 2);
      phase = 1;
      now = now.add(const Duration(seconds: 11));
      await diagnostics.flush();
      expect((await diagnostics.status())['queuedEvents'], 1);
      phase = 2;
      await diagnostics.flush();
      expect((await diagnostics.status())['queuedEvents'], 0);
      expect(batches.first.first['stage'], 'finish');
    },
  );

  test(
    'late upload acknowledgment cannot restore IDs of an evicted group',
    () async {
      final entered = Completer<void>();
      final release = Completer<Set<String>>();
      List<Map<String, Object?>>? held;
      final diagnostics = await install(
        upload: (events) async {
          if (events.any((event) => event['feature'] == 'message')) {
            held = events;
            if (!entered.isCompleted) entered.complete();
            return release.future;
          }
          return events.map((event) => event['eventId'] as String).toSet();
        },
      );
      final oldest = diagnostics.startAttempt(feature: 'message');
      diagnostics.finishAttempt(
        feature: 'message',
        traceId: oldest,
        outcome: 'success',
      );
      final flushing = diagnostics.flush();
      try {
        await entered.future;
        for (var group = 0; group < 100; group++) {
          final trace = diagnostics.startAttempt(feature: 'media');
          diagnostics.finishAttempt(
            feature: 'media',
            traceId: trace,
            outcome: 'success',
          );
        }
        final retained = await diagnostics.eventsForTesting();
        expect(retained, hasLength(200));
        expect(retained.any((event) => event['traceId'] == oldest), false);
        release.complete(
          held!.map((event) => event['eventId'] as String).toSet(),
        );
        await flushing;
        final status = await diagnostics.status();
        expect(status['queuedEvents'], status['retainedEvents']);
        expect(status['queuedEvents'], 200);
        final saved =
            jsonDecode(
                  await File('${directory.path}/state.json').readAsString(),
                )
                as Map;
        final retainedIds = (saved['events'] as List)
            .map((event) => event['eventId'])
            .toSet();
        final uploadedIds = (saved['uploaded'] as List).toSet();
        expect(uploadedIds.difference(retainedIds), isEmpty);
        expect(uploadedIds, isEmpty);
      } finally {
        if (!release.isCompleted) release.complete({});
        await flushing;
      }
    },
  );

  test(
    'clear does not wait for old upload or accept its late completion',
    () async {
      final release = Completer<Set<String>>();
      List<Map<String, Object?>>? held;
      final diagnostics = await install(
        upload: (events) async {
          if (events.any((e) => e['feature'] == 'message')) {
            held = events;
            return release.future;
          }
          return events.map((e) => e['eventId'] as String).toSet();
        },
      );
      diagnostics.startAttempt(feature: 'message');
      final flushing = diagnostics.flush();
      while (held == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await diagnostics.clear().timeout(const Duration(seconds: 1));
      release.complete(held!.map((e) => e['eventId'] as String).toSet());
      await flushing;
      expect(await diagnostics.eventsForTesting(), isEmpty);
      expect((await diagnostics.status())['lastUploadAtMs'], 0);
    },
  );

  test('private keys and exception text cannot enter the archive', () async {
    final diagnostics = await install();
    final trace = diagnostics.traceForOperation('SECRET_CONTACT_AND_MESSAGE')!;
    diagnostics.startAttempt(feature: 'media', traceId: trace);
    diagnostics.record(
      feature: 'media',
      stage: 'decrypt',
      outcome: 'failed',
      values: {'plaintext': 'SECRET_IMAGE_CONTENT'},
    );
    diagnostics.captureError(
      FileSystemException('SECRET_PATH', '/SECRET_PATH'),
      StackTrace.fromString(
        '#0 function (package:flutter_app/core/example.dart:42:5)\nSECRET_STACK',
      ),
    );
    final preview = await diagnostics.exportPreview();
    expect(preview, isNot(contains('SECRET')));
    final errors = (await diagnostics.eventsForTesting()).where(
      (e) => e['feature'] == 'runtime',
    );
    expect(errors.single['values'], containsPair('errorClass', 'file_system'));
    expect(
      (errors.single['values'] as Map)['fingerprint'],
      matches(RegExp(r'^[a-f0-9]{64}$')),
    );
    expect((await diagnostics.status())['droppedEvents'], 1);
  });

  test('errors without app frames do not claim a source fingerprint', () async {
    final diagnostics = await install();
    for (final stack in <StackTrace?>[
      null,
      StackTrace.empty,
      StackTrace.fromString(
        '#0 channel (package:flutter/src/services/platform_channel.dart:1:2)',
      ),
      StackTrace.fromString(
        '#0 plugin (package:flutter_webrtc/src/native/rtc_peerconnection_impl.dart:1:2)\nSECRET_STACK',
      ),
    ]) {
      diagnostics.captureError(
        PlatformException(code: 'SECRET_CODE', message: 'SECRET_MESSAGE'),
        stack,
      );
    }
    final errors = (await diagnostics.eventsForTesting())
        .where((e) => e['feature'] == 'runtime')
        .toList();
    expect(errors, hasLength(4));
    for (final event in errors) {
      expect(event['values'], {'errorClass': 'platform'});
    }
    expect(await diagnostics.exportPreview(), isNot(contains('SECRET')));
  });

  test(
    'app frame fingerprints distinguish boundaries without error text',
    () async {
      final diagnostics = await install();
      for (final line in [10, 20, 10]) {
        diagnostics.captureError(
          PlatformException(code: 'SECRET_$line', message: 'SECRET_MESSAGE'),
          StackTrace.fromString(
            '#0 example (package:flutter_app/core/example.dart:$line:2)',
          ),
        );
      }
      final errors = (await diagnostics.eventsForTesting())
          .where((e) => e['feature'] == 'runtime')
          .map((e) => (e['values'] as Map)['fingerprint'])
          .toList();
      expect(errors, hasLength(3));
      expect(errors[0], isNot(errors[1]));
      expect(errors[0], errors[2]);
      expect(await diagnostics.exportPreview(), isNot(contains('SECRET')));
    },
  );

  test('quota preserves a terminal result and records evidence loss', () async {
    final diagnostics = await install();
    final trace = diagnostics.startAttempt(feature: 'media')!;
    for (var i = 0; i < 300; i++) {
      diagnostics.record(
        feature: 'media',
        stage: 'download',
        outcome: 'ok',
        traceId: trace,
      );
    }
    diagnostics.finishAttempt(
      feature: 'media',
      traceId: trace,
      outcome: 'failed',
      reason: 'io_failed',
    );
    final events = await diagnostics.eventsForTesting();
    expect(events.length, lessThanOrEqualTo(256));
    expect(events.last['stage'], 'finish');
    expect((await diagnostics.status())['droppedEvents'], greaterThan(0));
  });

  test('burst admission retains only the latest 100 attempt groups', () async {
    final diagnostics = await install();
    final traces = <String>[];
    for (var i = 0; i < 120; i++) {
      final trace = diagnostics.startAttempt(feature: 'message')!;
      traces.add(trace);
      diagnostics.finishAttempt(
        feature: 'message',
        traceId: trace,
        outcome: 'success',
      );
    }
    final events = await diagnostics.eventsForTesting();
    expect(events, hasLength(200));
    expect(
      events.map((event) => event['traceId']).toSet(),
      unorderedEquals(traces.skip(20)),
    );
    expect(events.where((event) => event['stage'] == 'finish'), hasLength(100));
    expect((await diagnostics.status())['droppedEvents'], 40);
  });

  test(
    'durable eviction clear and opt-out never restore removed diagnostic rows',
    () async {
      Future<Map<String, dynamic>> savedState() async =>
          jsonDecode(await File('${directory.path}/state.json').readAsString())
              as Map<String, dynamic>;
      var diagnostics = await install();
      final traces = <String>[];
      void completeMessage(int index) {
        final trace = diagnostics.traceForOperation('message-$index')!;
        traces.add(trace);
        diagnostics.startAttempt(feature: 'message', traceId: trace);
        diagnostics.finishAttempt(
          feature: 'message',
          traceId: trace,
          outcome: 'success',
        );
      }

      for (var index = 0; index < 100; index++) {
        completeMessage(index);
      }
      await diagnostics.flush();
      final originalIds = ((await savedState())['events'] as List)
          .map((event) => event['eventId'])
          .toSet();
      expect(originalIds, hasLength(200));
      for (var index = 100; index < 120; index++) {
        completeMessage(index);
      }
      await diagnostics.flush();
      final retained = (await savedState())['events'] as List;
      final retainedIds = retained.map((event) => event['eventId']).toSet();
      expect(retained, hasLength(200));
      expect(originalIds.difference(retainedIds), hasLength(40));
      expect(
        retained.map((event) => event['traceId']).toSet(),
        unorderedEquals(traces.skip(20)),
      );
      diagnostics = await install();
      expect(
        (await diagnostics.eventsForTesting()).map((event) => event['eventId']),
        unorderedEquals(retainedIds),
      );

      // Clearing must erase the persisted rows as well as any pending delta.
      diagnostics.startAttempt(feature: 'media');
      await diagnostics.clear();
      diagnostics = await install();
      expect(await diagnostics.eventsForTesting(), isEmpty);
      var state = await savedState();
      expect(state['events'], isEmpty);
      expect(state['bindings'], isEmpty);
      expect(state['open'], isEmpty);

      // An opt-out after a durable write must also discard observations waiting
      // for the next scheduled batch, and must stay off after restart.
      completeMessage(120);
      await diagnostics.flush();
      diagnostics.startAttempt(feature: 'media');
      await diagnostics.setEnabled(false);
      diagnostics = await install();
      expect(diagnostics.enabled, false);
      state = await savedState();
      expect(state['enabled'], false);
      expect(state['events'], isEmpty);
      expect(state['bindings'], isEmpty);
      expect(state['open'], isEmpty);

      await diagnostics.setEnabled(true);
      completeMessage(121);
      await diagnostics.flush();
      final freshIds = ((await savedState())['events'] as List)
          .map((event) => event['eventId'])
          .toSet();
      expect(freshIds, hasLength(2));
      expect(freshIds.intersection(originalIds), isEmpty);
      expect(freshIds.intersection(retainedIds), isEmpty);
      diagnostics = await install();
      final finalEvents = await diagnostics.eventsForTesting();
      expect(
        finalEvents.map((event) => event['eventId']),
        unorderedEquals(freshIds),
      );
      expect(
        finalEvents.every((event) => event['traceId'] == traces.last),
        true,
      );
      expect(finalEvents.last['stage'], 'finish');
      expect((await savedState())['open'], isEmpty);
    },
  );

  test(
    'large archive obeys group and total byte quotas after batching',
    () async {
      final diagnostics = await install(persist: (_, _) async {});
      String? newest;
      for (var group = 0; group < 100; group++) {
        newest = diagnostics.startAttempt(feature: 'media');
        for (var event = 0; event < 160; event++) {
          diagnostics.record(
            feature: 'media',
            stage: 'download',
            outcome: 'ok',
            traceId: newest,
          );
        }
        diagnostics.finishAttempt(
          feature: 'media',
          traceId: newest,
          outcome: 'success',
        );
      }
      final events = await diagnostics.eventsForTesting();
      final grouped = <Object?, List<Map<String, Object?>>>{};
      var totalBytes = 0;
      for (final event in events) {
        grouped.putIfAbsent(event['attemptId'], () => []).add(event);
        totalBytes += utf8.encode(jsonEncode(event)).length;
      }
      expect(grouped.length, lessThanOrEqualTo(100));
      expect(totalBytes, lessThanOrEqualTo(4 * 1024 * 1024 - 128 * 1024));
      for (final group in grouped.values) {
        expect(group.length, lessThanOrEqualTo(255));
        expect(
          group.fold<int>(
            0,
            (bytes, event) => bytes + utf8.encode(jsonEncode(event)).length,
          ),
          lessThanOrEqualTo(64000),
        );
      }
      expect(events.last['traceId'], newest);
      expect(events.last['stage'], 'finish');
      expect(events.last['outcome'], 'success');
      expect((await diagnostics.status())['droppedEvents'], greaterThan(0));
    },
  );

  test('deferred persistence expires old evidence before saving', () async {
    final diagnostics = await install();
    final oldTrace = diagnostics.startAttempt(feature: 'message');
    diagnostics.finishAttempt(
      feature: 'message',
      traceId: oldTrace,
      outcome: 'success',
    );
    await diagnostics.flush();
    now = now.add(const Duration(days: 8));
    final newTrace = diagnostics.startAttempt(feature: 'message');
    diagnostics.finishAttempt(
      feature: 'message',
      traceId: newTrace,
      outcome: 'success',
    );
    final events = await diagnostics.eventsForTesting();
    expect(events, hasLength(2));
    expect(events.every((event) => event['traceId'] == newTrace), true);
    final state =
        jsonDecode(await File('${directory.path}/state.json').readAsString())
            as Map;
    expect((state['events'] as List), hasLength(2));
    expect(state['open'], isEmpty);
  });

  for (final uploaded in [false, true]) {
    test('terminal preservation counts only unuploaded evictions '
        '(uploaded: $uploaded)', () async {
      final diagnostics = await install(
        upload: uploaded
            ? (events) async =>
                  events.map((e) => e['eventId'] as String).toSet()
            : null,
      );
      final trace = diagnostics.startAttempt(feature: 'media')!;
      for (var i = 0; i < 300; i++) {
        if (!diagnostics.record(
          feature: 'media',
          stage: 'download',
          outcome: 'ok',
          traceId: trace,
        )) {
          break;
        }
      }
      if (uploaded) {
        for (var batch = 0; batch < 10; batch++) {
          await diagnostics.flush();
          if ((await diagnostics.status())['queuedEvents'] == 0) break;
        }
        expect((await diagnostics.status())['queuedEvents'], 0);
      }
      final before = (await diagnostics.eventsForTesting())
          .where((event) => event['traceId'] == trace)
          .map((event) => event['eventId'])
          .toSet();
      final droppedBefore =
          (await diagnostics.status())['droppedEvents'] as int;
      diagnostics.finishAttempt(
        feature: 'media',
        traceId: trace,
        outcome: 'success',
      );
      final after = (await diagnostics.eventsForTesting())
          .where((event) => event['traceId'] == trace)
          .toList();
      expect(
        after.singleWhere((event) => event['stage'] == 'finish')['outcome'],
        'success',
      );
      final evicted = before.difference(
        after.map((event) => event['eventId']).toSet(),
      );
      expect(evicted, isNotEmpty);
      expect(
        (await diagnostics.status())['droppedEvents'],
        droppedBefore + (uploaded ? 0 : evicted.length),
      );
    });
  }

  test(
    'storage observers capture failure without changing operation behavior',
    () async {
      final diagnostics = await install();
      AppDiagnosticEvents.storageTransaction(false, 24);
      final event = (await diagnostics.eventsForTesting()).single;
      expect(event['feature'], 'storage');
      expect(event['reason'], 'storage_failed');
      expect(event['values'], containsPair('durationMs', 24));
      await diagnostics.setEnabled(false);
      AppDiagnosticEvents.storageTransaction(false, 24);
      expect(await diagnostics.eventsForTesting(), isEmpty);
    },
  );

  test(
    'notification lock snapshots coalesce phases without recording owners',
    () async {
      final saved = <Map<String, Object?>>[];
      final diagnostics = await install(
        persist: (_, state) async {
          saved.add(state);
        },
      );
      saved.clear();
      final held = Object();
      final waiting = Object();
      AppDiagnosticEvents.notificationFileLock(
        held,
        NotificationFileLockPhase.waiting,
      );
      AppDiagnosticEvents.notificationFileLock(
        held,
        NotificationFileLockPhase.held,
      );
      AppDiagnosticEvents.notificationFileLock(
        waiting,
        NotificationFileLockPhase.waiting,
      );
      expect(
        saved,
        isEmpty,
        reason: 'acquisition does not persist or construct an archive event',
      );
      expect(await diagnostics.eventsForTesting(), isEmpty);
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.paused);
      final pending = (await diagnostics.eventsForTesting()).single;
      expect(pending['feature'], 'push');
      expect(pending['stage'], 'snapshot');
      expect(pending['outcome'], 'pending');
      expect(
        pending['values'],
        containsPair('operation', 'notification_flock'),
      );
      expect(pending['values'], containsPair('appLifecycle', 'paused'));
      expect(pending['values'], containsPair('count', 1));
      expect(pending['values'], containsPair('queuedEvents', 1));
      expect(pending['values'], containsPair('cleanupComplete', false));
      expect(AppDiagnostics.validateEvent(pending), isNotNull);

      fakeAsync((clock) {
        saved.clear();
        AppDiagnosticEvents.notificationFileLock(
          held,
          NotificationFileLockPhase.released,
        );
        AppDiagnosticEvents.notificationFileLock(
          waiting,
          NotificationFileLockPhase.held,
        );
        AppDiagnosticEvents.notificationFileLock(
          waiting,
          NotificationFileLockPhase.released,
        );
        for (var i = 0; i < 1000; i++) {
          final owner = Object();
          AppDiagnosticEvents.notificationFileLock(
            owner,
            NotificationFileLockPhase.waiting,
          );
          AppDiagnosticEvents.notificationFileLock(
            owner,
            NotificationFileLockPhase.held,
          );
          AppDiagnosticEvents.notificationFileLock(
            owner,
            NotificationFileLockPhase.released,
          );
        }
        clock.flushMicrotasks();
        expect(saved, isEmpty);
        clock.elapse(const Duration(milliseconds: 999));
        expect(saved, isEmpty);
        clock.elapse(const Duration(milliseconds: 1001));
        expect(saved, hasLength(1));
      });
      final events = await diagnostics.eventsForTesting();
      expect(
        events,
        hasLength(2),
        reason: '1000 owners produce one aggregate release snapshot',
      );
      expect(events.last['outcome'], 'ok');
      expect(events.last['values'], containsPair('count', 0));
      expect(events.last['values'], containsPair('queuedEvents', 0));
      expect(events.last['values'], containsPair('cleanupComplete', true));
      expect(jsonEncode(events), isNot(contains('owner')));
      await diagnostics.setEnabled(false);
      AppDiagnosticEvents.notificationFileLock(
        Object(),
        NotificationFileLockPhase.waiting,
      );
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(await diagnostics.eventsForTesting(), isEmpty);
    },
  );

  test(
    'notification lock snapshots retain lifecycle and observe only enabled owners',
    () async {
      final diagnostics = await install();
      final owner = Object();
      AppDiagnosticEvents.notificationFileLock(
        owner,
        NotificationFileLockPhase.waiting,
      );
      AppDiagnosticEvents.notificationFileLock(
        owner,
        NotificationFileLockPhase.held,
      );
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.resumed,
      ]) {
        diagnostics.didChangeAppLifecycleState(state);
      }
      final events = await diagnostics.eventsForTesting();
      expect(events.map((event) => (event['values'] as Map)['appLifecycle']), [
        'inactive',
        'hidden',
        'paused',
        'resumed',
      ]);
      expect(
        events.every((event) => (event['values'] as Map)['count'] == 1),
        isTrue,
      );
      expect(
        AppDiagnostics.validateEvent({
          ...events.first,
          'values': {
            ...events.first['values'] as Map,
            'appLifecycle': '/private/unsafe',
          },
        }),
        isNull,
      );
      await diagnostics.setEnabled(false);
      final unseen = Object();
      AppDiagnosticEvents.notificationFileLock(
        unseen,
        NotificationFileLockPhase.waiting,
      );
      await diagnostics.setEnabled(true);
      AppDiagnosticEvents.notificationFileLock(
        unseen,
        NotificationFileLockPhase.held,
      );
      AppDiagnosticEvents.notificationFileLock(
        owner,
        NotificationFileLockPhase.released,
      );
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(
        (await diagnostics.eventsForTesting()).where(
          (event) =>
              (event['values'] as Map)['operation'] == 'notification_flock',
        ),
        isEmpty,
        reason:
            'owners begun before enable are unobserved, never fabricated as held',
      );
      final observed = Object();
      AppDiagnosticEvents.notificationFileLock(
        observed,
        NotificationFileLockPhase.waiting,
      );
      AppDiagnosticEvents.notificationFileLock(
        observed,
        NotificationFileLockPhase.released,
      );
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final snapshot = (await diagnostics.eventsForTesting()).singleWhere(
        (event) =>
            (event['values'] as Map)['operation'] == 'notification_flock',
      );
      expect(
        snapshot['values'],
        containsPair('cleanupComplete', true),
        reason:
            'cleanupComplete covers only observed owners, not the unseen live owner',
      );
    },
  );

  test(
    'notification lock upload preserves local lifecycle and legacy mixed batch values',
    () async {
      var allowed = false;
      final bridge = DiagnosticBridge();
      final diagnostics = await install(
        bridge: bridge,
        networkAllowed: () async => allowed,
      );
      diagnostics.record(feature: 'message', stage: 'send', outcome: 'ok');
      final owner = Object();
      AppDiagnosticEvents.notificationFileLock(
        owner,
        NotificationFileLockPhase.waiting,
      );
      AppDiagnosticEvents.notificationFileLock(
        owner,
        NotificationFileLockPhase.held,
      );
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.paused);
      final before = await diagnostics.eventsForTesting();
      final localLock = before.singleWhere(
        (event) =>
            (event['values'] as Map)['operation'] == 'notification_flock',
      );
      final oldEvent = before.singleWhere(
        (event) => event['feature'] == 'message',
      );
      var uploads = 0;
      final batches = <List<Map<String, dynamic>>>[];
      bridge.response = (request) async {
        if (request['op'] == 'upload') {
          final batch = (request['events'] as List)
              .cast<Map<String, dynamic>>();
          batches.add(batch);
          uploads++;
          return {
            'supported': true,
            'acceptedEventIds': uploads == 1
                ? []
                : batch.map((event) => event['eventId']).toList(),
          };
        }
        return {
          'supported': true,
          'enabled': true,
          'consentEpoch': request['consentEpoch'],
        };
      };
      // Join installation's deferred offline flush before opening transport.
      await diagnostics.flush();
      allowed = true;
      now = now.add(const Duration(minutes: 1));
      await diagnostics.flush();
      now = now.add(const Duration(minutes: 1));
      await diagnostics.flush();
      expect(batches, hasLength(2));
      for (final batch in batches) {
        expect(
          batch.singleWhere((event) => event['eventId'] == oldEvent['eventId']),
          oldEvent,
        );
        final wireLock = batch.singleWhere(
          (event) => event['eventId'] == localLock['eventId'],
        );
        expect(wireLock, {
          ...localLock,
          'values': {...localLock['values'] as Map, 'operation': 'other'}
            ..remove('appLifecycle'),
        });
        expect(AppDiagnostics.validateEvent(wireLock), isNotNull);
      }
      final retainedLock = (await diagnostics.eventsForTesting()).singleWhere(
        (event) => event['eventId'] == localLock['eventId'],
      );
      expect(
        retainedLock,
        localLock,
        reason: 'failed upload/retry never mutates the rich local record',
      );
      expect(retainedLock['values'], containsPair('appLifecycle', 'paused'));
      expect(
        retainedLock['values'],
        containsPair('operation', 'notification_flock'),
      );
    },
  );

  test(
    'notification lock snapshot marks bounded tracking overflow unknown',
    () async {
      final diagnostics = await install();
      for (var i = 0; i < 140; i++) {
        final owner = Object();
        AppDiagnosticEvents.notificationFileLock(
          owner,
          NotificationFileLockPhase.waiting,
        );
        AppDiagnosticEvents.notificationFileLock(
          owner,
          NotificationFileLockPhase.held,
        );
      }
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.paused);
      final event = (await diagnostics.eventsForTesting()).single;
      expect(event['outcome'], 'unknown');
      expect(event['reason'], 'quota_exceeded');
      expect(event['values'], containsPair('count', 128));
      expect(event['values'], containsPair('droppedEvents', 12));
      expect(event['values'], containsPair('cleanupComplete', false));
    },
  );

  test(
    'invalid final values leave the attempt recoverable and allow a valid finish',
    () async {
      final diagnostics = await install();
      final trace = diagnostics.startAttempt(feature: 'media');
      diagnostics.finishAttempt(
        feature: 'media',
        traceId: trace,
        outcome: 'failed',
        reason: 'io_failed',
        values: {'durationMs': -1},
      );
      expect(
        (await diagnostics.eventsForTesting()).where(
          (e) => e['stage'] == 'finish',
        ),
        isEmpty,
      );
      diagnostics.finishAttempt(
        feature: 'media',
        traceId: trace,
        outcome: 'success',
      );
      final terminals = (await diagnostics.eventsForTesting())
          .where((e) => e['stage'] == 'finish')
          .toList();
      expect(terminals, hasLength(1));
      expect(terminals.single['outcome'], 'success');
    },
  );

  test(
    'mutating a caller map after admission cannot inject private data',
    () async {
      final diagnostics = await install();
      final values = <String, Object?>{'durationMs': 10};
      expect(
        diagnostics.record(
          feature: 'media',
          stage: 'snapshot',
          outcome: 'ok',
          values: values,
        ),
        true,
      );
      values['plaintext'] = 'SECRET_AFTER_VALIDATION';
      values['durationMs'] = -100;
      final event = (await diagnostics.eventsForTesting()).single;
      expect(event['values'], {'durationMs': 10});
      expect(await diagnostics.exportPreview(), isNot(contains('SECRET')));
    },
  );

  test(
    'mixed server ACKs advance even when the remaining batch hits quota',
    () async {
      final bridge = DiagnosticBridge();
      final diagnostics = await install(bridge: bridge);
      final batches = <List<dynamic>>[];
      var limited = true;
      bridge.response = (request) async {
        final events = request['events'] as List? ?? [];
        if (request['op'] == 'upload') batches.add(events);
        return {
          'supported': true,
          'enabled': request['enabled'] ?? true,
          'consentEpoch': request['consentEpoch'],
          if (limited) 'reason': 'quota_exceeded',
          'acceptedEventIds': limited
              ? [events.first['eventId']]
              : events.map((e) => e['eventId']).toList(),
          'rejectedEventIds': limited ? [events[1]['eventId']] : [],
        };
      };
      final trace = diagnostics.startAttempt(feature: 'message');
      diagnostics.record(
        feature: 'message',
        stage: 'send',
        outcome: 'ok',
        traceId: trace,
      );
      diagnostics.finishAttempt(
        feature: 'message',
        traceId: trace,
        outcome: 'success',
      );
      await diagnostics.flush();
      expect((await diagnostics.status())['queuedEvents'], 1);
      expect((await diagnostics.status())['droppedEvents'], 1);
      final completed = {
        batches.single[0]['eventId'],
        batches.single[1]['eventId'],
      };
      limited = false;
      await diagnostics.flush();
      expect(batches.last, hasLength(1));
      expect(completed.contains(batches.last.single['eventId']), false);
      expect((await diagnostics.status())['queuedEvents'], 0);
    },
  );

  test(
    'offline disable and clear establish consent before erasing at the same epoch',
    () async {
      final bridge = DiagnosticBridge();
      var serverEnabled = false;
      var serverEpoch = 0;
      bridge.response = (request) async {
        final epoch = request['consentEpoch'] as int;
        if (request['op'] == 'configure') {
          if (epoch < serverEpoch ||
              (epoch == serverEpoch && request['enabled'] != serverEnabled)) {
            return {
              'supported': true,
              'consentEpoch': serverEpoch,
              'enabled': serverEnabled,
              'reason': 'stale_epoch',
            };
          }
          serverEpoch = epoch;
          serverEnabled = request['enabled'] as bool;
        } else if (request['op'] == 'clear') {
          serverEpoch = epoch;
        }
        return {
          'supported': true,
          'consentEpoch': serverEpoch,
          'enabled': serverEnabled,
          'acceptedEventIds': (request['events'] as List? ?? [])
              .map((e) => e['eventId'])
              .toList(),
        };
      };
      var diagnostics = await install(bridge: bridge);
      expect(serverEnabled, true);
      bridge.online = false;
      await diagnostics.setEnabled(false);
      await diagnostics.clear();
      bridge.requests.clear();
      bridge.online = true;
      diagnostics = await install(bridge: bridge);
      expect(bridge.requests.map((r) => r['op']), ['configure', 'clear']);
      expect(serverEnabled, false);
      expect(diagnostics.enabled, false);
      expect((await diagnostics.status())['consentPending'], false);
    },
  );

  test(
    'concurrent refusal cannot finish a valid transfer on the same trace',
    () async {
      final diagnostics = await install();
      const trace = '00000000-0000-4000-8000-000000000555';
      final release = Completer<void>();
      final valid = diagnostics.runWithAttempt(
        feature: 'media',
        traceId: trace,
        body: (current) async {
          await release.future;
          diagnostics.record(
            feature: 'media',
            stage: 'commit',
            outcome: 'ok',
            traceId: current,
          );
          diagnostics.finishAttempt(
            feature: 'media',
            traceId: current,
            outcome: 'success',
          );
        },
      );
      diagnostics.runWithAttempt(
        feature: 'media',
        traceId: trace,
        body: (current) {
          diagnostics.finishAttempt(
            feature: 'media',
            traceId: current,
            outcome: 'blocked',
            reason: 'authority_rejected',
          );
        },
      );
      release.complete();
      await valid;
      final events = await diagnostics.eventsForTesting();
      final starts = events.where((e) => e['stage'] == 'start').toList();
      final terminals = events.where((e) => e['stage'] == 'finish').toList();
      expect(starts, hasLength(2));
      expect(terminals.map((e) => e['outcome']), ['blocked', 'success']);
      expect(terminals.last['attemptId'], starts.first['attemptId']);
      expect(terminals.first['attemptId'], starts.last['attemptId']);
    },
  );

  test(
    'local keyed aliases survive restart without exporting private lookup material',
    () async {
      var diagnostics = await install();
      const propagated = '00000000-0000-4000-8000-000000000321';
      expect(
        diagnostics.traceForOperation(
          'SECRET_MESSAGE_ID',
          propagatedTraceId: propagated,
        ),
        propagated,
      );
      await diagnostics.eventsForTesting();
      final saved = await File('${directory.path}/state.json').readAsString();
      expect(saved, isNot(contains('SECRET_MESSAGE_ID')));
      final salt = (jsonDecode(saved) as Map)['bindingSalt'] as String;
      expect(await diagnostics.exportPreview(), isNot(contains(salt)));
      diagnostics = await install();
      expect(diagnostics.traceForOperation('SECRET_MESSAGE_ID'), propagated);
      await diagnostics.clear();
      expect(
        diagnostics.traceForOperation('SECRET_MESSAGE_ID'),
        isNot(propagated),
      );
    },
  );

  test(
    'binding deltas retain updates, eviction and exact expiry on disk',
    () async {
      Future<Map> savedState() async =>
          jsonDecode(await File('${directory.path}/state.json').readAsString())
              as Map;
      var diagnostics = await install();
      final traces = [
        for (var index = 0; index < 1000; index++)
          diagnostics.traceForOperation('private-$index')!,
      ];
      await diagnostics.flush();
      expect((await savedState())['bindings'], hasLength(1000));

      now = now.add(const Duration(days: 1));
      const replacement = '00000000-0000-4000-8000-000000000654';
      diagnostics.traceForOperation(
        'private-500',
        propagatedTraceId: replacement,
      );
      final newest = diagnostics.traceForOperation('private-1000');
      await diagnostics.flush();
      final bindings = (await savedState())['bindings'] as Map;
      final retainedTraces = bindings.values
          .map((value) => value['traceId'])
          .toSet();
      expect(bindings, hasLength(1000));
      expect(retainedTraces, containsAll([replacement, newest, traces[1]]));
      expect(retainedTraces, isNot(contains(traces[0])));
      expect(retainedTraces, isNot(contains(traces[500])));
      diagnostics = await install();
      expect(diagnostics.traceForOperation('private-500'), replacement);

      // The seven-day boundary is inclusive. Updating one binding must not
      // postpone expiry of the other entries or lose its refreshed timestamp.
      now = now.add(const Duration(days: 6));
      await diagnostics.flush();
      expect((await savedState())['bindings'], hasLength(1000));
      now = now.add(const Duration(milliseconds: 1));
      await diagnostics.flush();
      expect(
        ((await savedState())['bindings'] as Map).values.map(
          (value) => value['traceId'],
        ),
        unorderedEquals([replacement, newest]),
      );
      diagnostics.traceForOperation('pending-before-clear');
      await diagnostics.clear();
      diagnostics = await install();
      expect((await savedState())['bindings'], isEmpty);
    },
  );

  test(
    'upload metadata survives event patches and removes expired IDs',
    () async {
      Future<Map> savedState() async =>
          jsonDecode(await File('${directory.path}/state.json').readAsString())
              as Map;
      var diagnostics = await install(
        upload: (events) async =>
            events.map((event) => event['eventId'] as String).toSet(),
      );
      final trace = diagnostics.startAttempt(feature: 'message');
      diagnostics.finishAttempt(
        feature: 'message',
        traceId: trace,
        outcome: 'success',
      );
      await diagnostics.flush();
      final acknowledged = (await savedState())['uploaded'] as List;
      expect(acknowledged, isNotEmpty);
      final next = diagnostics.startAttempt(feature: 'media');
      diagnostics.finishAttempt(
        feature: 'media',
        traceId: next,
        outcome: 'success',
      );
      await diagnostics.eventsForTesting();
      expect((await savedState())['uploaded'], unorderedEquals(acknowledged));
      diagnostics = await install();
      expect((await savedState())['uploaded'], unorderedEquals(acknowledged));
      expect((await diagnostics.status())['queuedEvents'], 2);

      now = now.add(const Duration(days: 8));
      diagnostics.record(feature: 'storage', stage: 'commit', outcome: 'ok');
      await diagnostics.eventsForTesting();
      expect((await savedState())['uploaded'], isEmpty);
      diagnostics = await install();
      expect((await savedState())['uploaded'], isEmpty);
      expect((await diagnostics.status())['queuedEvents'], 1);
    },
  );

  test(
    'local aliases expire and explicit off destroys the old association',
    () async {
      var diagnostics = await install();
      final first = diagnostics.traceForOperation('private-operation');
      now = now.add(const Duration(days: 8));
      final expired = diagnostics.traceForOperation('private-operation');
      expect(expired, isNot(first));
      await diagnostics.setEnabled(false);
      diagnostics = await install();
      expect(diagnostics.traceForOperation('private-operation'), isNull);
      await diagnostics.setEnabled(true);
      expect(
        diagnostics.traceForOperation('private-operation'),
        isNot(expired),
      );
    },
  );

  test(
    'native records retain original run while joining the current support code',
    () async {
      var diagnostics = await install();
      diagnostics.startAttempt(feature: 'push');
      final original =
          Map<String, Object?>.from(
              (await diagnostics.eventsForTesting()).single,
            )
            ..['source'] = 'android'
            ..['platform'] = 'android'
            ..['eventId'] = '00000000-0000-4000-8000-000000000777';
      final acknowledgments = <String>[];
      diagnostics = await install(
        native: (method, data) async {
          if (method == 'drain') {
            return {
              'version': 1,
              'events': [original],
              'droppedEvents': 0,
            };
          }
          if (method == 'ack') {
            acknowledgments.addAll((data['eventIds'] as List).cast<String>());
          }
          return true;
        },
      );
      final imported = (await diagnostics.eventsForTesting()).singleWhere(
        (e) => e['source'] == 'android',
      );
      expect(imported['runId'], original['runId']);
      expect(imported['reportingRunId'], diagnostics.supportCode);
      expect(acknowledgments, contains(original['eventId']));
    },
  );

  test(
    'native acknowledgment observes its imported row in the durable archive',
    () async {
      final nativeEvents = <Map<String, Object?>>[];
      final acknowledged = <String>[];
      final diagnostics = await install(
        native: (method, data) async {
          if (method == 'drain') {
            return {'version': 1, 'events': nativeEvents, 'droppedEvents': 0};
          }
          if (method == 'ack') {
            final state =
                jsonDecode(
                      await File('${directory.path}/state.json').readAsString(),
                    )
                    as Map;
            final savedIds = (state['events'] as List)
                .map((event) => event['eventId'])
                .toSet();
            final ids = (data['eventIds'] as List).cast<String>();
            expect(savedIds, containsAll(ids));
            acknowledged.addAll(ids);
          }
          return true;
        },
      );
      diagnostics.record(feature: 'message', stage: 'send', outcome: 'ok');
      final original = (await diagnostics.eventsForTesting()).single;
      const nativeId = '00000000-0000-4000-8000-000000000779';
      nativeEvents.add({
        ...original,
        'source': 'android',
        'platform': 'android',
        'eventId': nativeId,
      });
      await diagnostics.flush();
      expect(acknowledged, [nativeId]);
      final saved =
          jsonDecode(await File('${directory.path}/state.json').readAsString())
              as Map;
      expect(
        (saved['events'] as List).map((event) => event['eventId']),
        unorderedEquals([original['eventId'], nativeId]),
      );
    },
  );

  test(
    'native evidence is not acknowledged if local persistence fails',
    () async {
      final nativeEvents = <Map<String, Object?>>[];
      final acknowledgments = <String>[];
      final diagnostics = await install(
        native: (method, data) async {
          if (method == 'drain') {
            return {'version': 1, 'events': nativeEvents, 'droppedEvents': 0};
          }
          if (method == 'ack') {
            acknowledgments.addAll((data['eventIds'] as List).cast<String>());
          }
          return true;
        },
      );
      diagnostics.startAttempt(feature: 'push');
      final event =
          Map<String, Object?>.from(
              (await diagnostics.eventsForTesting()).single,
            )
            ..['source'] = 'ios'
            ..['platform'] = 'ios'
            ..['eventId'] = '00000000-0000-4000-8000-000000000778';
      nativeEvents.add(event);
      await directory.delete(recursive: true);
      await diagnostics.flush();
      expect(acknowledgments, isEmpty);
      expect(diagnostics.enabled, false);
      expect((await diagnostics.status())['storageHealthy'], false);
    },
  );
}
