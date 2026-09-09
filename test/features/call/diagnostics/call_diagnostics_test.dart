import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    Bridge? bridge,
  }) => CallDiagnostics.installForTesting(
    directory: directory,
    enabled: enabled,
    now: () => now,
    upload: upload,
    bridge: bridge,
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
    'storage failure is contained and never changes the call action result',
    () async {
      final diagnostics = await install();
      await directory.delete(recursive: true);
      final result = diagnostics.runWithTrace(
        diagnostics.beginAttempt(),
        () => 42,
      );
      expect(result, 42);
      await diagnostics.flush();
      expect((await diagnostics.status())['storageHealthy'], false);
      await directory.create();
    },
  );
}
