import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostic_schema.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

class DiagnosticBridge implements Bridge {
  bool online = true;
  Future<String>? Function(Map<String, dynamic>)? response;
  final requests = <Map<String, dynamic>>[];
  @override
  bool get isInitialized => online;
  @override
  Future<String> send(String message) async {
    final envelope = jsonDecode(message) as Map<String, dynamic>;
    if (envelope['cmd'] != 'call_diagnostics_v1' ||
        envelope['payload'] is! Map<String, dynamic>) {
      return jsonEncode({'ok': false, 'errorCode': 'INVALID_BRIDGE_REQUEST'});
    }
    final request = envelope['payload']! as Map<String, dynamic>;
    requests.add(request);
    final custom = response?.call(request);
    if (custom != null) return custom;
    return jsonEncode({
      'ok': true,
      'data': {
        'supported': true,
        'enabled': request['enabled'] ?? true,
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
  var now = DateTime.utc(2026, 9, 8, 14);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('call-diagnostic-test-');
    now = DateTime.utc(2026, 9, 8, 14);
  });
  tearDown(() async {
    await CallDiagnostics.instance.dispose();
    await directory.delete(recursive: true);
  });

  Future<CallDiagnostics> install({
    bool? enabled = true,
    CallDiagnosticUpload? upload,
    CallDiagnosticPersist? persist,
    Bridge? bridge,
  }) => CallDiagnostics.installForTesting(
    directory: directory,
    enabled: enabled,
    now: () => now,
    upload: upload,
    persist: persist,
    bridge: bridge,
  );

  test('new trace and event IDs retain the UUIDv4 wire contract', () async {
    final diagnostics = await install(
      upload: (_) async => {},
      persist: (_, _) async {},
    );
    final traces = <String>[];
    for (var i = 0; i < 128; i++) {
      traces.add(diagnostics.beginAttempt()!);
    }
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(traces.toSet(), hasLength(traces.length));
    expect(traces.every(uuidV4.hasMatch), true);
    final events = await diagnostics.eventsForTesting();
    expect(
      events.every((event) => uuidV4.hasMatch(event['eventId']! as String)),
      true,
    );
    expect(
      events.map((event) => event['eventId']).toSet(),
      hasLength(events.length),
    );
    expect(
      events.every((event) => CallDiagnostics.validateEvent(event) != null),
      true,
    );
  });

  test(
    'closed-value normalization preserves private-input filtering and snapshots',
    () async {
      final diagnostics = await install(persist: (_, _) async {});
      final values = <String, Object?>{
        'transport': 'turnTls',
        'route': 'wiredHeadset',
        'network': 'wifi',
        'durationMs': 9007199254740991,
        'foreground': true,
        'unknown': 'PRIVATE_VALUE',
        'retry': -1,
      };
      diagnostics.record(
        stage: 'media',
        action: 'snapshot',
        outcome: 'mediaFlowVerified',
        reason: 'userAction',
        values: values,
      );
      values
        ..clear()
        ..['transport'] = 'PRIVATE_MUTATION';
      diagnostics.record(
        stage: 'PRIVATE_STAGE',
        action: 'PRIVATE_ACTION',
        outcome: 'PRIVATE_OUTCOME',
        reason: 'PRIVATE_REASON',
        values: {'route': 'PRIVATE_ROUTE', 'foreground': 'PRIVATE_BOOLEAN'},
      );
      final events = await diagnostics.eventsForTesting();
      final normalized = events.first;
      expect(normalized['stage'], 'media');
      expect(normalized['action'], 'snapshot');
      expect(normalized['outcome'], 'media_flow_verified');
      expect(normalized['reason'], 'user_action');
      expect(normalized['values'], {
        'transport': 'turn_tls',
        'route': 'wired_headset',
        'network': 'wifi',
        'durationMs': 9007199254740991,
        'foreground': true,
      });
      expect(events.last['stage'], 'runtime');
      expect(events.last['action'], 'snapshot');
      expect(events.last['outcome'], 'unknown');
      expect(events.last['reason'], 'unknown');
      expect(events.last['values'], isEmpty);
      expect(await diagnostics.exportPreview(), isNot(contains('PRIVATE_')));
      expect(CallDiagnostics.validateEvent(normalized), isNotNull);
      expect(
        CallDiagnostics.validateEvent({
          ...normalized,
          'values': {'transport': 'turnTls'},
        }),
        isNull,
        reason:
            'foreign rows must remain strictly closed, without normalization',
      );
    },
  );

  test(
    'large closed value maps obey the exact UTF8 attempt byte quota',
    () async {
      final diagnostics = await install(
        upload: (_) async => {},
        persist: (_, _) async {},
      );
      final values = <String, Object?>{
        for (final key in callDiagnosticSchemaV1['booleanValues'] as List)
          key as String: true,
        for (final key in callDiagnosticSchemaV1['integerValues'] as List)
          key as String: 9007199254740991,
        for (final entry
            in (callDiagnosticSchemaV1['enumValues'] as Map<String, dynamic>)
                .entries)
          entry.key: (entry.value as List).cast<String>().reduce(
            (a, b) => a.length >= b.length ? a : b,
          ),
      };
      final trace = diagnostics.beginAttempt()!;
      for (var i = 0; i < 128; i++) {
        diagnostics.record(
          traceId: trace,
          stage: 'media',
          action: 'snapshot',
          outcome: 'ok',
          values: values,
        );
      }
      final retained = await diagnostics.eventsForTesting();
      final bytes = retained.fold<int>(
        0,
        (total, event) => total + utf8.encode(jsonEncode(event)).length,
      );
      expect(bytes, lessThanOrEqualTo(64 * 1024));
      expect(retained.length, lessThan(128));
      expect((await diagnostics.status())['droppedEvents'], greaterThan(0));
      expect(
        64 * 1024 - bytes,
        lessThan(utf8.encode(jsonEncode(retained.last)).length + 16),
      );
      diagnostics.finishAttempt(
        traceId: trace,
        outcome: 'media_failed',
        reason: 'media_stalled',
      );
      final completed = await diagnostics.eventsForTesting();
      expect(completed.last['stage'], 'terminal');
      expect(
        completed.last['values'],
        containsPair('completeness', 'truncated'),
      );
      expect(
        completed.fold<int>(
          0,
          (total, event) => total + utf8.encode(jsonEncode(event)).length,
        ),
        lessThanOrEqualTo(64 * 1024),
      );
    },
  );

  test('call milestones share one fixed-window persistence batch', () async {
    final saved = <Map<String, Object?>>[];
    final diagnostics = await install(
      upload: (_) async => {},
      persist: (_, state) async => saved.add(state),
    );
    saved.clear();
    fakeAsync((clock) {
      for (var i = 0; i < 40; i++) {
        final trace = diagnostics.beginAttempt();
        diagnostics.record(
          traceId: trace,
          stage: 'media',
          action: 'snapshot',
          outcome: 'ok',
        );
        diagnostics.finishAttempt(traceId: trace, outcome: 'success');
      }
      clock.flushMicrotasks();
      expect(saved, isEmpty);
      clock.elapse(const Duration(milliseconds: 999));
      expect(saved, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(saved, hasLength(1));
      expect(saved.single['events'], hasLength(120));
      expect(saved.single['open'], isEmpty);
      clock.elapse(const Duration(seconds: 5));
      expect(saved, hasLength(1));
    });
  });

  test(
    'explicit flush persists promptly without rewriting an idle archive',
    () async {
      final saved = <Map<String, Object?>>[];
      final diagnostics = await install(
        persist: (_, state) async => saved.add(state),
      );
      saved.clear();
      fakeAsync((clock) {
        diagnostics.beginAttempt();
        var flushed = false;
        unawaited(diagnostics.flush().then((_) => flushed = true));
        clock.flushMicrotasks();
        expect(flushed, true);
        expect(saved, hasLength(1));
        expect(saved.single['events'], hasLength(1));
        for (var i = 0; i < 3; i++) {
          unawaited(diagnostics.flush());
          clock.flushMicrotasks();
        }
        clock.elapse(const Duration(seconds: 2));
        expect(saved, hasLength(1));
      });
    },
  );

  test(
    'a pending sink never owns the call and a joined flush persists new events',
    () async {
      Completer<void>? release;
      final saved = <Map<String, Object?>>[];
      final diagnostics = await install(
        persist: (_, state) async {
          saved.add(state);
          if (release != null) await release!.future;
        },
      );
      saved.clear();
      fakeAsync((clock) {
        release = Completer<void>();
        try {
          final first = diagnostics.beginAttempt();
          var initialCompleted = false;
          unawaited(diagnostics.flush().then((_) => initialCompleted = true));
          clock.flushMicrotasks();
          expect(saved, hasLength(1));
          expect(initialCompleted, false);
          final result = diagnostics.runWithTrace(first, () {
            diagnostics.record(
              stage: 'media',
              action: 'snapshot',
              outcome: 'ok',
            );
            return 'call connected';
          });
          expect(result, 'call connected');
          var joined = false;
          unawaited(diagnostics.flush().then((_) => joined = true));
          clock.flushMicrotasks();
          expect(joined, false);
          // Later samples may schedule another timer but cannot defer the
          // explicit flush's required snapshot behind that timer.
          diagnostics.record(stage: 'media', action: 'snapshot', outcome: 'ok');
          release!.complete();
          clock.flushMicrotasks();
          expect(joined, true);
          expect(saved.last['events'], hasLength(3));
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

  for (final disable in [false, true]) {
    test('pending call snapshot cannot restore evidence after '
        '${disable ? 'opt-out' : 'clear'}', () async {
      Completer<void>? release;
      final saved = <Map<String, Object?>>[];
      final diagnostics = await install(
        persist: (_, state) async {
          if (release != null && (state['events'] as List).isNotEmpty) {
            await release!.future;
          }
          saved.add(state);
        },
      );
      final originalEpoch = saved.last['consentEpoch'];
      saved.clear();
      fakeAsync((clock) {
        release = Completer<void>();
        try {
          diagnostics.beginAttempt();
          clock.elapse(const Duration(seconds: 1));
          expect(saved, isEmpty);
          var cleared = false;
          unawaited(
            (disable ? diagnostics.setEnabled(false) : diagnostics.clear())
                .then((_) => cleared = true),
          );
          clock.flushMicrotasks();
          expect(cleared, false);
          release!.complete();
          clock.flushMicrotasks();
          expect(cleared, true);
          expect(saved.last['events'], isEmpty);
          expect(saved.last['open'], isEmpty);
          expect(saved.last['traceAliases'], isEmpty);
          expect(saved.last['enabled'], !disable);
          expect(saved.last['consentEpoch'], isNot(originalEpoch));
        } finally {
          if (!release!.isCompleted) release!.complete();
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 1));
          release = null;
        }
      });
    });
  }

  test(
    'incremental archive preserves loaded rows and writes rebinds and clear',
    () async {
      final diagnostics = await install(upload: (_) async => {});
      final provisional = diagnostics.beginAttempt(role: 'callee')!;
      diagnostics.bindCall(
        callHandle: 'PRIVATE_CALL_HANDLE',
        traceId: provisional,
        role: 'callee',
      );
      final original = (await diagnostics.eventsForTesting()).single;
      const resolved = '00000000-0000-4000-8000-000000000001';
      diagnostics.bindCall(
        callHandle: 'PRIVATE_CALL_HANDLE',
        traceId: resolved,
        role: 'callee',
      );
      diagnostics.finishAttempt(traceId: resolved, outcome: 'media_failed');
      await diagnostics.dispose();
      final savedFile = File('${directory.path}/state.json');
      final saved = jsonDecode(await savedFile.readAsString()) as Map;
      expect(
        (saved['events'] as List).singleWhere(
          (event) => event['eventId'] == original['eventId'],
        )['traceId'],
        resolved,
      );
      expect(
        await savedFile.readAsString(),
        isNot(contains('PRIVATE_CALL_HANDLE')),
      );
      final oldIds = (saved['events'] as List).map((e) => e['eventId']).toSet();
      // A rejected duplicate must not replace the validated row when the
      // persistent writer loads the same file independently.
      await savedFile.writeAsString(
        jsonEncode({
          ...saved,
          'events': [
            ...saved['events'] as List,
            {
              ...(saved['events'] as List).first as Map,
              'privateField': 'PRIVATE_REJECTED_ROW',
            },
          ],
        }),
      );

      final reopened = await install(upload: (_) async => {});
      reopened.record(stage: 'runtime', action: 'snapshot', outcome: 'ok');
      await reopened.eventsForTesting();
      final updated = jsonDecode(await savedFile.readAsString()) as Map;
      final rows = updated['events'] as List;
      expect(rows, hasLength(oldIds.length + 1));
      expect(rows.map((e) => e['eventId']), containsAll(oldIds));
      expect(
        await savedFile.readAsString(),
        isNot(contains('PRIVATE_REJECTED_ROW')),
      );
      await reopened.clear();
      expect(
        (jsonDecode(await savedFile.readAsString()) as Map)['events'],
        isEmpty,
      );
    },
  );

  test(
    'event expiry removes only expired worker rows after a later write',
    () async {
      final diagnostics = await install(upload: (_) async => {});
      final trace = diagnostics.beginAttempt()!;
      final originalId =
          (await diagnostics.eventsForTesting()).single['eventId'];
      now = now.add(const Duration(days: 4));
      diagnostics.record(
        traceId: trace,
        stage: 'media',
        action: 'snapshot',
        outcome: 'ok',
      );
      await diagnostics.eventsForTesting();
      now = now.add(const Duration(days: 3, milliseconds: 1));
      await diagnostics.flush();
      final saved =
          jsonDecode(await File('${directory.path}/state.json').readAsString())
              as Map;
      expect(saved['events'], hasLength(1));
      expect((saved['events'] as List).single['eventId'], isNot(originalId));
      expect(saved['open'], isEmpty);
    },
  );

  test(
    'file-based preview validates rows and excludes storage metadata',
    () async {
      final diagnostics = await install(upload: (_) async => {});
      diagnostics.beginAttempt();
      final original = (await diagnostics.eventsForTesting()).single;
      final savedFile = File('${directory.path}/state.json');
      final saved = jsonDecode(await savedFile.readAsString()) as Map;
      await savedFile.writeAsString(
        jsonEncode({
          ...saved,
          'privateMetadata': 'PRIVATE_ARCHIVE_METADATA',
          'events': [
            original,
            {...original, 'privateField': 'PRIVATE_REJECTED_ROW'},
          ],
        }),
      );
      final preview = await diagnostics.exportPreview();
      final exported = jsonDecode(preview) as Map;
      expect(
        exported.keys,
        unorderedEquals([
          'schemaVersion',
          'exportedAtMs',
          'retentionDays',
          'droppedEvents',
          'events',
        ]),
      );
      expect(exported['events'], [original]);
      expect(preview, isNot(contains('PRIVATE_')));
      await savedFile.delete();
      // A missing file still permits support export from retained safe evidence.
      final fallback = jsonDecode(await diagnostics.exportPreview()) as Map;
      expect(fallback['events'], [original]);
    },
  );

  test(
    'production bridge carries consent upload resolve and clear as native payloads',
    () async {
      const methodChannel = MethodChannel('com.mknoon/go_bridge');
      const eventChannel = 'com.mknoon/go_bridge_events';
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final nativeRequests = <Map<String, dynamic>>[];
      const sharedTrace = '00000000-0000-4000-8000-000000000789';
      messenger.setMockMessageHandler(
        eventChannel,
        (_) async => codec.encodeSuccessEnvelope(null),
      );
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        expect(call.method, 'callDiagnosticsV1');
        final payload =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
        nativeRequests.add(payload);
        expect(payload.containsKey('cmd'), false);
        expect(payload.containsKey('action'), false);
        expect(payload['consentEpoch'], isA<int>());
        final data = switch (payload['op']) {
          'configure' => <String, Object?>{
            'supported': true,
            'enabled': payload['enabled'],
          },
          'upload' => <String, Object?>{
            'supported': true,
            'acceptedEventIds': (payload['events'] as List)
                .map((event) => event['eventId'])
                .toList(),
            'rejectedEventIds': <String>[],
          },
          'resolve' => <String, Object?>{
            'supported': true,
            'resolved': true,
            'traceId': sharedTrace,
          },
          'clear' => <String, Object?>{'supported': true},
          _ => throw StateError('unexpected diagnostic operation'),
        };
        return jsonEncode({'ok': true, 'data': data});
      });
      final bridge = GoBridgeClient();
      addTearDown(() async {
        await CallDiagnostics.instance.dispose();
        bridge.dispose();
        await Future<void>.delayed(Duration.zero);
        messenger.setMockMethodCallHandler(methodChannel, null);
        messenger.setMockMessageHandler(eventChannel, null);
      });
      await bridge.initialize();
      final diagnostics = await install(enabled: false, bridge: bridge);
      await diagnostics.setEnabled(true);
      await diagnostics.flush();
      expect(
        nativeRequests.where((request) => request['op'] == 'configure'),
        isNotEmpty,
      );
      expect((await diagnostics.status())['consentPending'], false);
      final enabledRequest = nativeRequests.firstWhere(
        (request) => request['op'] == 'configure',
      );
      expect(enabledRequest.keys.toSet(), {
        'op',
        'enabled',
        'pushTrace',
        'consentEpoch',
      });
      expect(enabledRequest['enabled'], true);
      expect(enabledRequest['pushTrace'], true);
      final trace = diagnostics.beginAttempt()!;
      diagnostics.finishAttempt(
        traceId: trace,
        outcome: 'preflight_failed',
        reason: 'endpoint_not_found',
      );
      await diagnostics.flush();
      expect(
        nativeRequests.where((request) => request['op'] == 'upload'),
        isNotEmpty,
      );
      expect((await diagnostics.status())['queuedEvents'], 0);
      const privateHandle = 'private-call-handle';
      expect(
        await diagnostics.resolveTraceForCall(callHandle: privateHandle),
        sharedTrace,
      );
      expect(
        nativeRequests.lastWhere(
          (request) => request['op'] == 'resolve',
        )['callHandle'],
        privateHandle,
      );
      await diagnostics.setEnabled(false);
      await diagnostics.clear();
      expect(
        nativeRequests.lastWhere(
          (request) => request['op'] == 'configure',
        )['enabled'],
        false,
      );
      expect(
        nativeRequests.where((request) => request['op'] == 'clear'),
        hasLength(1),
      );
      expect(
        nativeRequests
            .lastWhere((request) => request['op'] == 'clear')
            .keys
            .toSet(),
        {'op', 'consentEpoch'},
      );
      expect((await diagnostics.status())['consentPending'], false);
      expect(await diagnostics.eventsForTesting(), isEmpty);
    },
  );

  test('checked-in producer schema matches the shared protocol', () async {
    expect(
      callDiagnosticSchemaV1,
      jsonDecode(
        await File('tool/call_diagnostics/schema_v1.json').readAsString(),
      ),
    );
  });

  test(
    'native admission vocabulary accepts closed dispositions and strict readiness booleans',
    () async {
      final diagnostics = await install();
      final trace = diagnostics.beginAttempt(role: 'callee')!;
      for (final disposition in const [
        'admitted',
        'terminal',
        'permanent_reject',
        'empty_or_already_acked',
        'deferred',
        'unknown',
      ]) {
        final values = <String, Object?>{
          'admissionDisposition': disposition,
          'databaseClosed': true,
          'leaseReleased': false,
          'requiredPersistenceComplete': true,
        };
        diagnostics.record(
          traceId: trace,
          stage: 'admission',
          action: 'commit',
          outcome: 'ok',
          values: values,
        );
        final emitted = (await diagnostics.eventsForTesting()).last;
        expect(emitted['stage'], 'admission');
        expect(emitted['values'], values);
        final native = <String, Object?>{...emitted, 'source': 'android'};
        expect(CallDiagnostics.validateEvent(native), native);
        expect(
          CallDiagnostics.validateEvent({
            ...native,
            'values': {...values, 'admissionDisposition': 'unrecognized'},
          }),
          isNull,
        );
        for (final readiness in const [
          'databaseClosed',
          'leaseReleased',
          'requiredPersistenceComplete',
        ]) {
          expect(
            CallDiagnostics.validateEvent({
              ...native,
              'values': {...values, readiness: 'true'},
            }),
            isNull,
            reason: '$readiness must remain a boolean',
          );
        }
      }
    },
  );

  test(
    'Dart emits the exact advisory context consumed by node and relay fixtures',
    () async {
      final fixtures =
          jsonDecode(
                await File(
                  'tool/call_diagnostics/wire_fixtures_v1.json',
                ).readAsString(),
              )
              as Map;
      final diagnostics = await install();
      for (final raw in (fixtures['contexts'] as Map).values) {
        final expected = Map<String, Object?>.from(raw as Map);
        final actual = diagnostics.contextForWire(
          traceId: expected['traceId'] as String?,
          operationId: expected['operationId'] as String?,
          parentOperationId: expected['parentOperationId'] as String?,
          reason: expected['cause']! as String,
        )!;
        expect(actual.keys.toSet(), expected.keys.toSet());
        expect(
          (fixtures['contextFields'] as List).toSet().containsAll(actual.keys),
          true,
        );
        actual.remove('requestId');
        expected.remove('requestId');
        expect(actual, expected);
        expect(actual.containsKey('reason'), false);
      }
    },
  );

  test(
    'first launch enables native and relay diagnostics and uploads call outcomes',
    () async {
      final bridge = DiagnosticBridge();
      final nativeConfigurations = <Map<String, Object?>>[];
      final diagnostics = await CallDiagnostics.installForTesting(
        directory: directory,
        enabled: null,
        now: () => now,
        bridge: bridge,
        native: (method, data) async {
          if (method == 'configure') nativeConfigurations.add(data);
          if (method == 'drain') {
            return {'version': 1, 'events': [], 'droppedEvents': 0};
          }
          return true;
        },
      );
      expect(diagnostics.enabled, true);
      expect(nativeConfigurations.single['enabled'], true);
      final configured = bridge.requests.singleWhere(
        (request) => request['op'] == 'configure',
      );
      expect(configured['enabled'], true);
      expect(
        configured['consentEpoch'],
        nativeConfigurations.single['consentEpoch'],
      );
      final trace = diagnostics.beginAttempt()!;
      diagnostics.finishAttempt(
        traceId: trace,
        outcome: 'preflight_failed',
        reason: 'endpoint_not_found',
      );
      await diagnostics.flush();
      final uploaded = bridge.requests
          .where((request) => request['op'] == 'upload')
          .expand((request) => request['events'] as List);
      expect(
        uploaded.singleWhere((event) => event['stage'] == 'terminal'),
        containsPair('outcome', 'preflight_failed'),
      );
      expect((await diagnostics.status())['queuedEvents'], 0);
    },
  );

  test(
    'saved off from an earlier build remains off when the default changes',
    () async {
      await File('${directory.path}/state.json').writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'enabled': false,
          'consentEpoch': now.millisecondsSinceEpoch,
        }),
      );
      final bridge = DiagnosticBridge();
      final diagnostics = await install(enabled: null, bridge: bridge);
      expect(diagnostics.enabled, false);
      expect(diagnostics.beginAttempt(), isNull);
      expect(await diagnostics.eventsForTesting(), isEmpty);
      expect(bridge.requests, isEmpty);
    },
  );

  for (final state in [
    'invalid json',
    '{"schemaVersion":2}',
    '{"schemaVersion":1}',
  ]) {
    test('unreadable saved preference never defaults on: $state', () async {
      await File('${directory.path}/state.json').writeAsString(state);
      final bridge = DiagnosticBridge();
      final diagnostics = await install(enabled: null, bridge: bridge);
      expect(diagnostics.enabled, false);
      expect(diagnostics.beginAttempt(), isNull);
      expect(bridge.requests, isEmpty);
    });
  }

  test(
    'preflight rejection survives restart without requiring a call handle',
    () async {
      var diagnostics = await install();
      final trace = diagnostics.beginAttempt()!;
      diagnostics.finishAttempt(
        traceId: trace,
        outcome: 'preflight_failed',
        reason: 'endpoint_not_found',
      );
      diagnostics.finishAttempt(traceId: trace, outcome: 'unknown');
      diagnostics = await install(enabled: null);
      final terminal = (await diagnostics.eventsForTesting())
          .where((e) => e['stage'] == 'terminal')
          .toList();
      expect(terminal, hasLength(1));
      expect(terminal.single, containsPair('outcome', 'preflight_failed'));
      expect(terminal.single, containsPair('reason', 'endpoint_not_found'));
      expect(terminal.single['traceId'], trace);
      diagnostics.finishAttempt(traceId: trace, outcome: 'unknown');
      expect(
        (await diagnostics.eventsForTesting()).where(
          (e) => e['stage'] == 'terminal',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'unfinished durable attempt is classified as interrupted, without claiming a crash',
    () async {
      var diagnostics = await install();
      final trace = diagnostics.beginAttempt()!;
      diagnostics = await install(enabled: null);
      final events = await diagnostics.eventsForTesting();
      expect(
        events.where((e) => e['traceId'] == trace && e['action'] == 'recover'),
        hasLength(1),
      );
      expect(events.last['outcome'], 'interrupted_unknown');
      diagnostics = await install(enabled: null);
      expect(
        (await diagnostics.eventsForTesting()).where(
          (e) => e['action'] == 'recover',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'protocol identities and arbitrary payloads cannot enter persisted or exported events',
    () async {
      final diagnostics = await install();
      final trace = diagnostics.beginAttempt()!;
      diagnostics.bindCall(
        callId: 'SECRET_CALL',
        callHandle: 'SECRET_HANDLE',
        traceId: trace,
      );
      diagnostics.record(
        traceId: trace,
        stage: 'media',
        action: 'snapshot',
        outcome: 'ok',
        reason: 'SECRET_ERROR',
        values: {
          'sdp': 'SECRET_SDP',
          'peerId': 'SECRET_PEER',
          'inboundPackets': 5,
          'transport': 'SECRET_IP',
          'muted': true,
        },
      );
      final exported = await diagnostics.exportPreview();
      final state = await File('${directory.path}/state.json').readAsString();
      expect(exported, isNot(contains('SECRET')));
      expect(state, isNot(contains('SECRET')));
      final event = (await diagnostics.eventsForTesting()).last;
      expect(event['values'], {'inboundPackets': 5, 'muted': true});
      expect(event['reason'], 'unknown');
      expect(CallDiagnostics.validateEvent(event), isNotNull);
      expect(
        CallDiagnostics.validateEvent({...event, 'rawError': 'SECRET'}),
        isNull,
      );
      expect(
        CallDiagnostics.validateEvent({...event, 'reason': 'SECRET'}),
        isNull,
      );
      expect(
        CallDiagnostics.validateEvent({
          ...event,
          'values': {'address': 'SECRET'},
        }),
        isNull,
      );
    },
  );

  test(
    'concurrent asynchronous calls and causal operations keep separate context',
    () async {
      final diagnostics = await install();
      final first = diagnostics.beginAttempt()!;
      final second = diagnostics.beginAttempt()!;
      final contexts = await Future.wait(
        [first, second].map(
          (trace) => diagnostics.runWithTrace(trace, () async {
            await Future<void>.delayed(Duration.zero);
            return diagnostics.contextForWire()!;
          }),
        ),
      );
      expect(contexts.map((e) => e['traceId']).toList(), [first, second]);
      expect(contexts.map((e) => e['requestId']).toSet(), hasLength(2));
      expect(diagnostics.currentTraceId, isNull);
      final parent = diagnostics.beginOperation(reason: 'provider_reset')!;
      final child = diagnostics.runWithOperation(
        parent,
        () => diagnostics.beginOperation(reason: 'token_rotation_cleanup'),
      )!;
      final context = diagnostics.runWithOperation(
        child,
        () => diagnostics.contextForWire(),
      )!;
      expect(context.containsKey('traceId'), false);
      expect(context['operationId'], child);
      expect(context['parentOperationId'], parent);
      expect(context['cause'], 'token_rotation_cleanup');
    },
  );

  test(
    'full trace preserves terminal and first media proof while permanent rejects advance',
    () async {
      final bridge = DiagnosticBridge();
      var phase = 'offline';
      final uploads = <List<Map<String, dynamic>>>[];
      bridge.response = (request) {
        if (request['op'] != 'upload') return null;
        final events = (request['events'] as List).cast<Map<String, dynamic>>();
        uploads.add(events);
        final priority = events.where(
          (e) =>
              e['stage'] == 'terminal' || e['outcome'] == 'media_flow_verified',
        );
        return Future.value(
          jsonEncode({
            'ok': true,
            'data': {
              'supported': true,
              'acceptedEventIds': phase == 'offline'
                  ? []
                  : priority.map((e) => e['eventId']).toList(),
              'rejectedEventIds': phase == 'offline'
                  ? []
                  : events
                        .where((e) => !priority.contains(e))
                        .map((e) => e['eventId'])
                        .toList(),
              'reason': phase == 'offline'
                  ? 'sink_unavailable'
                  : 'quota_exceeded',
            },
          }),
        );
      };
      final diagnostics = await install(bridge: bridge);
      final trace = diagnostics.beginAttempt(role: 'callee')!;
      for (var i = 0; i < 100; i++) {
        diagnostics.record(
          traceId: trace,
          stage: 'signaling',
          action: 'commit',
          outcome: 'ok',
        );
      }
      diagnostics.record(
        traceId: trace,
        stage: 'media',
        action: 'snapshot',
        outcome: 'media_flow_verified',
        values: {'inboundRtp': true, 'outboundRtp': true},
      );
      final firstMedia = (await diagnostics.eventsForTesting()).last['eventId'];
      diagnostics.finishAttempt(traceId: trace, outcome: 'connected');
      await diagnostics.flush();
      final retained = (await diagnostics.eventsForTesting()).length;
      expect((await diagnostics.status())['queuedEvents'], retained);
      expect((await diagnostics.status())['droppedEvents'], 0);

      phase = 'quota';
      now = now.add(const Duration(minutes: 6));
      await diagnostics.flush();
      expect(uploads.last.first['stage'], 'terminal');
      expect(uploads.last[1]['eventId'], firstMedia);
      expect((await diagnostics.status())['queuedEvents'], retained - 64);
      final remaining = retained - 64;
      await diagnostics.flush();
      // This second batch contains only permanent rejections, which are ACKed
      // progress, not a transient sink failure deserving another backoff.
      expect(uploads.last, hasLength(remaining));
      expect((await diagnostics.status())['queuedEvents'], 0);
      expect((await diagnostics.status())['lastError'], 'none');
      expect((await diagnostics.status())['droppedEvents'], retained - 2);
      final requestsAfterCompletion = uploads.length;
      await diagnostics.flush();
      expect(uploads, hasLength(requestsAfterCompletion));
      expect((await diagnostics.status())['droppedEvents'], retained - 2);
    },
  );

  test(
    'native callback role follows the known endpoint without relabeling unbound events',
    () async {
      final nativeEvents = <Map<String, Object?>>[];
      final diagnostics = await CallDiagnostics.installForTesting(
        directory: directory,
        now: () => now,
        native: (method, data) async {
          if (method == 'drain') {
            return {'version': 1, 'events': nativeEvents, 'droppedEvents': 0};
          }
          return true;
        },
      );
      final trace = diagnostics.beginAttempt(role: 'caller')!;
      diagnostics.bindCall(callHandle: 'PRIVATE_HANDLE', traceId: trace);
      final event = (await diagnostics.eventsForTesting()).single;
      nativeEvents.addAll([
        {
          ...event,
          'eventId': '00000000-0000-4000-8000-000000000793',
          'source': 'ios',
          'role': 'callee',
          'stage': 'push',
          'action': 'receive',
        },
        {
          ...event,
          'eventId': '00000000-0000-4000-8000-000000000794',
          'source': 'android',
          'role': 'local',
          'traceId': '00000000-0000-4000-8000-000000000795',
        },
      ]);
      await diagnostics.flush();
      final events = await diagnostics.eventsForTesting();
      expect(events.singleWhere((e) => e['source'] == 'ios')['role'], 'caller');
      expect(
        events.singleWhere((e) => e['source'] == 'android')['role'],
        'local',
      );
    },
  );

  test(
    'uploaded metadata survives event patches and removes expired and cleared IDs',
    () async {
      var acknowledge = true;
      Future<Set<String>> upload(List<Map<String, Object?>> events) async =>
          acknowledge
          ? events.map((event) => event['eventId']! as String).toSet()
          : {};
      Future<Map<String, dynamic>> saved() async =>
          jsonDecode(await File('${directory.path}/state.json').readAsString())
              as Map<String, dynamic>;

      var diagnostics = await install(upload: upload);
      diagnostics.record(stage: 'runtime', action: 'snapshot', outcome: 'ok');
      final oldId = (await diagnostics.eventsForTesting()).single['eventId'];
      await diagnostics.flush();
      expect((await saved())['uploaded'], [oldId]);

      acknowledge = false;
      now = now.add(const Duration(days: 6));
      diagnostics.record(stage: 'runtime', action: 'snapshot', outcome: 'ok');
      final newId = (await diagnostics.eventsForTesting()).last['eventId'];
      expect((await saved())['uploaded'], [oldId]);

      diagnostics = await install(enabled: null, upload: upload);
      expect((await saved())['uploaded'], [oldId]);
      expect((await diagnostics.status())['queuedEvents'], 1);

      now = now.add(const Duration(days: 2));
      final retained = await diagnostics.eventsForTesting();
      expect(retained.single['eventId'], newId);
      expect((await saved())['uploaded'], isEmpty);

      acknowledge = true;
      await diagnostics.flush();
      expect((await saved())['uploaded'], [newId]);
      await diagnostics.clear();
      expect((await saved())['uploaded'], isEmpty);
      expect((await saved())['events'], isEmpty);
      diagnostics = await install(enabled: null, upload: upload);
      expect((await saved())['uploaded'], isEmpty);
      expect(await diagnostics.eventsForTesting(), isEmpty);
    },
  );

  test(
    'failed ACK metadata writes recover without resending acknowledged events',
    () async {
      var uploads = 0;
      Future<Set<String>> upload(List<Map<String, Object?>> events) async {
        uploads++;
        // The event snapshot is durable before upload; fail its ACK write.
        if (uploads == 1) await directory.delete(recursive: true);
        return events.map((event) => event['eventId']! as String).toSet();
      }

      var diagnostics = await install(upload: upload);
      diagnostics.record(stage: 'runtime', action: 'snapshot', outcome: 'ok');
      final id = (await diagnostics.eventsForTesting()).single['eventId'];
      await diagnostics.flush();
      expect((await diagnostics.status())['storageHealthy'], false);
      expect(uploads, 1);
      await directory.create();
      await diagnostics.flush();
      expect((await diagnostics.status())['storageHealthy'], true);
      final saved =
          jsonDecode(await File('${directory.path}/state.json').readAsString())
              as Map;
      expect(saved['uploaded'], [id]);
      expect((saved['events'] as List).single['eventId'], id);
      diagnostics = await install(enabled: null, upload: upload);
      expect((await diagnostics.status())['queuedEvents'], 0);
      expect(uploads, 1);
    },
  );

  test(
    'offline queue retries and only acknowledged records stop uploading across restart',
    () async {
      var online = false;
      final batches = <List<String>>[];
      Future<Set<String>> upload(List<Map<String, Object?>> events) async {
        final ids = events.map((e) => e['eventId']! as String).toList();
        batches.add(ids);
        if (!online) throw StateError('offline');
        return {ids.first};
      }

      var diagnostics = await install(upload: upload);
      await diagnostics.flush();
      final trace = diagnostics.beginAttempt()!;
      diagnostics.finishAttempt(
        traceId: trace,
        outcome: 'declined',
        reason: 'remote_user',
      );
      await diagnostics.flush();
      expect((await diagnostics.status())['queuedEvents'], 2);
      online = true;
      now = now.add(const Duration(minutes: 6));
      await diagnostics.flush();
      expect((await diagnostics.status())['queuedEvents'], 1);
      final acknowledged = batches.last.first;
      diagnostics = await install(enabled: null, upload: upload);
      await diagnostics.flush();
      expect(batches.last, isNot(contains(acknowledged)));
      expect((await diagnostics.status())['queuedEvents'], 0);
    },
  );

  test(
    'concurrent flush joins the same upload; clear discards its stale completion',
    () async {
      final started = Completer<void>();
      final release = Completer<Set<String>>();
      var count = 0;
      final diagnostics = await install(
        upload: (events) {
          count++;
          started.complete();
          return release.future;
        },
      );
      await diagnostics.flush();
      diagnostics.beginAttempt();
      final first = diagnostics.flush();
      await started.future;
      var joinedDone = false;
      final second = diagnostics.flush().then((_) => joinedDone = true);
      await Future<void>.delayed(Duration.zero);
      expect(joinedDone, false);
      final oldIds = (await diagnostics.eventsForTesting())
          .map((e) => e['eventId']! as String)
          .toSet();
      await diagnostics.clear();
      release.complete(oldIds);
      await Future.wait([first, second]);
      expect(count, 1);
      expect(await diagnostics.eventsForTesting(), isEmpty);
      expect((await diagnostics.status())['lastUploadAtMs'], 0);
    },
  );

  test(
    'offline opt-out persists its revocation and resends it after restart',
    () async {
      final bridge = DiagnosticBridge();
      var diagnostics = await install(enabled: null, bridge: bridge);
      expect(diagnostics.enabled, true);
      await diagnostics.flush();
      final enabledEpoch =
          bridge.requests
                  .where((r) => r['op'] == 'configure')
                  .last['consentEpoch']
              as int;
      bridge.online = false;
      await diagnostics.setEnabled(false);
      expect(await diagnostics.eventsForTesting(), isEmpty);
      bridge.online = true;
      bridge.requests.clear();
      diagnostics = await install(enabled: null, bridge: bridge);
      await diagnostics.flush();
      final revoked = bridge.requests.singleWhere(
        (r) => r['op'] == 'configure',
      );
      expect(revoked['enabled'], false);
      expect(revoked['consentEpoch'], greaterThan(enabledEpoch));
      expect(bridge.requests.where((r) => r['op'] == 'upload'), isEmpty);
      expect(diagnostics.enabled, false);
    },
  );

  test(
    'per-attempt quota retains terminal evidence and reports dropped records',
    () async {
      final diagnostics = await install();
      final trace = diagnostics.beginAttempt()!;
      for (var i = 0; i < 280; i++) {
        diagnostics.record(
          traceId: trace,
          stage: 'media',
          action: 'snapshot',
          outcome: 'ok',
        );
      }
      diagnostics.finishAttempt(
        traceId: trace,
        outcome: 'media_failed',
        reason: 'media_stalled',
      );
      final events = await diagnostics.eventsForTesting();
      expect(events.length, lessThanOrEqualTo(256));
      expect(utf8.encode(jsonEncode(events)).length, lessThan(66 * 1024));
      expect(events.last['outcome'], 'media_failed');
      expect(events.last['values'], containsPair('truncated', true));
      expect(events.last['values'], containsPair('completeness', 'truncated'));
      expect((await diagnostics.status())['droppedEvents'], greaterThan(0));
    },
  );

  test('attempt count and age are bounded', () async {
    final diagnostics = await install();
    for (var i = 0; i < 103; i++) {
      diagnostics.beginAttempt();
    }
    expect((await diagnostics.status())['traceCodes'], hasLength(100));
    now = now.add(const Duration(days: 8));
    await diagnostics.flush();
    expect(await diagnostics.eventsForTesting(), isEmpty);
  });

  test(
    'callee provisional events wait for authenticated trace resolution',
    () async {
      final bridge = DiagnosticBridge();
      final diagnostics = await install(bridge: bridge);
      final provisional = diagnostics.beginAttempt(role: 'callee')!;
      diagnostics.bindCall(
        callHandle: 'PRIVATE_HANDLE',
        traceId: provisional,
        role: 'callee',
      );
      final resolved = Completer<String>();
      bridge.response = (r) => r['op'] == 'resolve' ? resolved.future : null;
      final resolving = diagnostics.resolveTraceForCall(
        callHandle: 'PRIVATE_HANDLE',
      );
      await diagnostics.flush();
      expect(bridge.requests.where((r) => r['op'] == 'upload'), isEmpty);
      const shared = '00000000-0000-4000-8000-000000000123';
      resolved.complete(
        jsonEncode({
          'ok': true,
          'data': {'supported': true, 'resolved': true, 'traceId': shared},
        }),
      );
      expect(await resolving, shared);
      await diagnostics.flush();
      final upload = bridge.requests.singleWhere((r) => r['op'] == 'upload');
      expect(
        (upload['events'] as List).every((e) => e['traceId'] == shared),
        true,
      );
      expect(await diagnostics.exportPreview(), isNot(contains(provisional)));
      expect(
        await diagnostics.exportPreview(),
        isNot(contains('PRIVATE_HANDLE')),
      );
    },
  );

  test(
    'late presentation callbacks and native drain keep the resolved callee trace',
    () async {
      const shared = '00000000-0000-4000-8000-000000000789';
      const nativeEventId = '00000000-0000-4000-8000-000000000790';
      final bridge = DiagnosticBridge();
      final resolved = Completer<String>();
      final nativeEvents = <Map<String, Object?>>[];
      final nativeAcks = <String>[];
      final diagnostics = await CallDiagnostics.installForTesting(
        directory: directory,
        bridge: bridge,
        native: (method, data) async {
          if (method == 'lookup') return {'version': 1};
          if (method == 'drain') {
            return {'version': 1, 'events': nativeEvents, 'droppedEvents': 0};
          }
          if (method == 'ack') {
            nativeAcks.addAll((data['eventIds'] as List).cast<String>());
            nativeEvents.clear();
          }
          return true;
        },
      );
      final provisional = diagnostics.beginAttempt(role: 'callee')!;
      diagnostics.bindCall(
        callId: 'PRIVATE_CALL',
        callHandle: 'PRIVATE_HANDLE',
        traceId: provisional,
        role: 'callee',
      );
      final nativeCompletion = <String, Object?>{
        ...(await diagnostics.eventsForTesting()).single,
        'eventId': nativeEventId,
        'source': 'ios',
        'role': 'local',
        'stage': 'presentation',
        'action': 'present',
        'outcome': 'ok',
      };
      bridge.response = (r) => r['op'] == 'resolve' ? resolved.future : null;
      final resolving = diagnostics.resolveTraceForCall(
        callHandle: 'PRIVATE_HANDLE',
      );
      final presentation = Completer<void>();
      Map<String, Object?>? lateContext;
      final callback = diagnostics.runWithTrace(provisional, () async {
        await presentation.future;
        // The incoming handler retains this value across native presentation.
        diagnostics.record(
          traceId: provisional,
          stage: 'presentation',
          action: 'present',
          outcome: 'ok',
        );
        lateContext = diagnostics.contextForWire();
      });
      await diagnostics.flush();
      expect(bridge.requests.where((r) => r['op'] == 'upload'), isEmpty);
      resolved.complete(
        jsonEncode({
          'ok': true,
          'data': {'supported': true, 'resolved': true, 'traceId': shared},
        }),
      );
      expect(await resolving, shared);
      presentation.complete();
      await callback;
      nativeEvents.add(nativeCompletion);
      await diagnostics.flush();

      final events = await diagnostics.eventsForTesting();
      expect(events, hasLength(3));
      expect(events.every((e) => e['traceId'] == shared), true);
      expect(events.every((e) => e['role'] == 'callee'), true);
      expect(lateContext?['traceId'], shared);
      expect(nativeAcks, contains(nativeEventId));
      final uploaded = bridge.requests
          .where((r) => r['op'] == 'upload')
          .expand((r) => r['events'] as List);
      expect(uploaded.every((e) => e['traceId'] == shared), true);
      // A stale completion must not move the binding backwards or finish twice.
      diagnostics.bindCall(
        callHandle: 'PRIVATE_HANDLE',
        traceId: provisional,
        role: 'callee',
      );
      expect(diagnostics.traceForCall(callId: 'PRIVATE_CALL'), shared);
      diagnostics.finishAttempt(traceId: shared, outcome: 'declined');
      diagnostics.finishAttempt(traceId: provisional, outcome: 'failed');
      expect(
        (await diagnostics.eventsForTesting()).where(
          (e) => e['stage'] == 'terminal',
        ),
        hasLength(1),
      );
      final preview = await diagnostics.exportPreview();
      expect(preview, isNot(contains(provisional)));
      expect(preview, isNot(contains('PRIVATE_')));
    },
  );

  test(
    'resolved trace aliases survive restart for a delayed native presentation',
    () async {
      const shared = '00000000-0000-4000-8000-000000000791';
      const nativeEventId = '00000000-0000-4000-8000-000000000792';
      var diagnostics = await install();
      final provisional = diagnostics.beginAttempt(role: 'callee')!;
      diagnostics.bindCall(
        callHandle: 'PRIVATE_HANDLE',
        traceId: provisional,
        role: 'callee',
      );
      final delayedNative = <String, Object?>{
        ...(await diagnostics.eventsForTesting()).single,
        'eventId': nativeEventId,
        'source': 'ios',
        'role': 'local',
        'stage': 'presentation',
        'action': 'present',
        'outcome': 'ok',
      };
      diagnostics.bindCall(
        callHandle: 'PRIVATE_HANDLE',
        traceId: shared,
        role: 'callee',
      );
      await diagnostics.exportPreview();
      final acks = <String>[];
      diagnostics = await CallDiagnostics.installForTesting(
        directory: directory,
        enabled: null,
        now: () => now,
        native: (method, data) async {
          if (method == 'drain') {
            return {
              'version': 1,
              'events': [delayedNative],
              'droppedEvents': 0,
            };
          }
          if (method == 'ack') {
            acks.addAll((data['eventIds'] as List).cast<String>());
          }
          return true;
        },
      );
      final native = (await diagnostics.eventsForTesting()).singleWhere(
        (event) => event['eventId'] == nativeEventId,
      );
      expect(native['traceId'], shared);
      expect(native['role'], 'callee');
      expect(acks, contains(nativeEventId));
      expect(await diagnostics.exportPreview(), isNot(contains(provisional)));
      await diagnostics.clear();
      final state = jsonDecode(
        await File('${directory.path}/state.json').readAsString(),
      );
      expect(state['traceAliases'], isEmpty);
    },
  );

  test(
    'offline clear is durable and precedes upload after reconnect',
    () async {
      final bridge = DiagnosticBridge();
      var diagnostics = await install(bridge: bridge);
      final oldEpoch = bridge.requests.last['consentEpoch'] as int;
      bridge.online = false;
      diagnostics.beginAttempt();
      await diagnostics.clear();
      bridge.requests.clear();
      bridge.online = true;
      diagnostics = await install(enabled: null, bridge: bridge);
      expect(bridge.requests.map((r) => r['op']).toList(), [
        'clear',
        'configure',
      ]);
      expect(bridge.requests.first['consentEpoch'], greaterThan(oldEpoch));
      expect(await diagnostics.eventsForTesting(), isEmpty);
      expect(diagnostics.enabled, true);
    },
  );

  test(
    'native drain completing after clear cannot restore or acknowledge old records',
    () async {
      final drain = Completer<Map<String, Object?>>();
      var armed = false;
      final acknowledgments = <Object?>[];
      final diagnostics = await CallDiagnostics.installForTesting(
        directory: directory,
        native: (method, data) async {
          if (method == 'drain') {
            if (armed) return drain.future;
            return {'version': 1, 'events': [], 'droppedEvents': 0};
          }
          if (method == 'ack') acknowledgments.add(data['eventIds']);
          return true;
        },
      );
      diagnostics.beginAttempt();
      final oldEvent = {
        ...(await diagnostics.eventsForTesting()).single,
        'source': 'android',
      };
      armed = true;
      final pending = diagnostics.flush();
      await Future<void>.delayed(Duration.zero);
      await diagnostics.clear();
      drain.complete({
        'version': 1,
        'events': [oldEvent],
        'droppedEvents': 55,
      });
      await pending;
      expect(await diagnostics.eventsForTesting(), isEmpty);
      expect(acknowledgments, isEmpty);
      expect((await diagnostics.status())['droppedEvents'], 0);
    },
  );

  test(
    'native opt-out persistence failure stays pending and is retried',
    () async {
      var failed = false;
      final configurations = <Map<String, Object?>>[];
      final diagnostics = await CallDiagnostics.installForTesting(
        directory: directory,
        native: (method, data) async {
          if (method == 'configure') {
            configurations.add(data);
            return !failed;
          }
          if (method == 'drain') {
            return {'version': 1, 'events': [], 'droppedEvents': 0};
          }
          return true;
        },
      );
      failed = true;
      await diagnostics.setEnabled(false);
      expect((await diagnostics.status())['nativeStorageHealthy'], false);
      expect((await diagnostics.status())['consentPending'], true);
      final epoch = configurations.last['consentEpoch'];
      failed = false;
      await diagnostics.flush();
      expect(configurations.last['enabled'], false);
      expect(configurations.last['consentEpoch'], epoch);
      expect((await diagnostics.status())['nativeStorageHealthy'], true);
      expect(diagnostics.enabled, false);
    },
  );

  test(
    'cold native trace is adopted without overwriting it with a provisional callee trace',
    () async {
      const shared = '00000000-0000-4000-8000-000000000456';
      final binds = <Map<String, Object?>>[];
      final bridge = DiagnosticBridge();
      bridge.response = (r) => r['op'] == 'resolve'
          ? Future.value(
              jsonEncode({
                'ok': true,
                'data': {'supported': false},
              }),
            )
          : null;
      final diagnostics = await CallDiagnostics.installForTesting(
        directory: directory,
        bridge: bridge,
        native: (method, data) async {
          if (method == 'lookup') return {'version': 1, 'traceId': shared};
          if (method == 'bind') binds.add(data);
          if (method == 'drain') {
            return {'version': 1, 'events': [], 'droppedEvents': 0};
          }
          return true;
        },
      );
      final provisional = diagnostics.beginAttempt(role: 'callee')!;
      diagnostics.bindCall(
        callHandle: 'PRIVATE_HANDLE',
        traceId: provisional,
        role: 'callee',
      );
      expect(binds, isEmpty);
      expect(
        await diagnostics.resolveTraceForCall(callHandle: 'PRIVATE_HANDLE'),
        shared,
      );
      expect(binds.every((b) => b['traceId'] == shared), true);
      expect(
        (await diagnostics.eventsForTesting()).every(
          (e) => e['traceId'] == shared,
        ),
        true,
      );
    },
  );

  test(
    'storage failure preserves the call result and recovers after restoring the sink',
    () async {
      final diagnostics = await install();
      await directory.delete(recursive: true);
      final trace = diagnostics.beginAttempt();
      final result = diagnostics.runWithTrace(trace, () => 42);
      expect(result, 42);
      await diagnostics.flush();
      expect((await diagnostics.status())['storageHealthy'], false);
      await directory.create();
      await diagnostics.flush();
      expect((await diagnostics.status())['storageHealthy'], true);
      final saved =
          jsonDecode(await File('${directory.path}/state.json').readAsString())
              as Map;
      expect(saved['events'], hasLength(1));
      expect((saved['events'] as List).single['traceId'], trace);
    },
  );
}
