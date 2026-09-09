import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  }) => AppDiagnostics.installForTesting(
    directory: directory,
    enabled: enabled,
    now: () => now,
    bridge: bridge,
    upload: upload,
    native: native,
    networkAllowed: networkAllowed,
  );

  test('producer and relay share one checked-in closed schema', () async {
    expect(
      appDiagnosticSchemaV1,
      jsonDecode(
        await File('tool/app_diagnostics/schema_v1.json').readAsString(),
      ),
    );
  });

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
