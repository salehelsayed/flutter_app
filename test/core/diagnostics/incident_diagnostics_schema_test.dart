import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

// Frozen schemas from 87812872e: changes to the current vocabulary must not make
// this simulated older receiver silently accept previously unknown fields.
Map<String, dynamic> legacySchema(String kind) =>
    jsonDecode(
          File(
            'test/core/diagnostics/fixtures/${kind}_schema_before_incident_fields.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void expectLegacyAccepted(Map<String, Object?> event, String kind) {
  final schema = legacySchema(kind);
  for (final key in [
    'source',
    'feature',
    'stage',
    'action',
    'outcome',
    'reason',
  ]) {
    if (event.containsKey(key)) expect(schema[key], contains(event[key]));
  }
  final enums = schema['enumValues'] as Map;
  for (final entry in (event['values'] as Map).entries) {
    if ((schema['booleanValues'] as List).contains(entry.key)) {
      expect(entry.value, isA<bool>());
    } else if ((schema['integerValues'] as List).contains(entry.key)) {
      expect(entry.value, isA<int>());
    } else if ((schema['hashValues'] as List? ?? []).contains(entry.key)) {
      expect(entry.value, matches(RegExp(r'^[a-f0-9]{64}$')));
    } else {
      expect(
        enums.containsKey(entry.key),
        isTrue,
        reason: 'legacy receiver rejects unknown value ${entry.key}',
      );
      expect(enums[entry.key], contains(entry.value));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('incident-schema-');
  });
  tearDown(() async {
    await AppDiagnostics.instance.dispose();
    await CallDiagnostics.instance.dispose();
    await directory.delete(recursive: true);
  });

  for (final origin in const [
    'incoming_report',
    'outgoing_transaction',
    'audio_configuration',
    'audio_activation',
    'action_timeout',
    'answer_adoption_timeout',
    'unknown',
  ]) {
    test(
      'native failure origin $origin stays local with legacy ACKs',
      () async {
        final uploads = <Map<String, Object?>>[];
        final diagnostics = await CallDiagnostics.installForTesting(
          directory: Directory('${directory.path}/call'),
          upload: (batch) async {
            uploads.addAll(batch);
            return batch.map((event) => event['eventId']! as String).toSet();
          },
        );
        diagnostics.record(
          stage: 'terminal',
          action: 'commit',
          outcome: 'ok',
          reason: 'native_lifecycle_failed',
          values: {
            'nativeCommitted': true,
            'terminal': true,
            'nativeFailureOrigin': origin,
          },
        );
        final event = (await diagnostics.eventsForTesting()).single;
        expect(event['values'], containsPair('nativeFailureOrigin', origin));
        expect(
          CallDiagnostics.validateEvent({...event, 'source': 'ios'}),
          isNotNull,
        );
        final exported = jsonDecode(await diagnostics.exportPreview()) as Map;
        expect(
          (exported['events'] as List).single['values'],
          containsPair('nativeFailureOrigin', origin),
        );
        await diagnostics.flush();
        final uploaded = uploads.singleWhere(
          (row) => row['eventId'] == event['eventId'],
        );
        expectLegacyAccepted(uploaded, 'call');
        expect(uploaded['values'], {'nativeCommitted': true, 'terminal': true});
        expect((await diagnostics.eventsForTesting()).single, event);
        expect((await diagnostics.status())['queuedEvents'], 0);
      },
    );
  }

  test('BL8 contact request relay upload preserves closed fields without private content', () async {
    final uploads = <Map<String, Object?>>[];
    final diagnostics = await AppDiagnostics.installForTesting(
      directory: Directory('${directory.path}/app'),
      upload: (batch) async {
        uploads.addAll(batch);
        return batch.map((e) => e['eventId']! as String).toSet();
      },
    );
    const detail = <String, Object?>{
      'requestSource': 'live',
      'consentClass': 'withdrawn',
      'requestAction': 'admit',
      'requestDisposition': 'ignored',
    };
    diagnostics.record(
      feature: 'contact_request',
      stage: 'verify',
      outcome: 'rejected',
      values: {
        ...detail,
        'peerId': 'PRIVATE_PEER',
        'name': 'PRIVATE_NAME',
        'message': 'PRIVATE_MESSAGE',
      },
    );
    final local = (await diagnostics.eventsForTesting()).singleWhere(
      (e) => e['feature'] == 'contact_request',
    );
    expect(local['values'], detail);
    await diagnostics.flush();
    final uploaded = uploads.singleWhere(
      (e) => e['eventId'] == local['eventId'],
    );
    expect(uploaded['feature'], 'contact_request');
    expect(uploaded['values'], detail);
    expect(AppDiagnostics.validateEvent(uploaded), isNotNull);
    final relaySchema = jsonDecode(
      File('go-relay-server/app_diagnostics_schema_v1.json').readAsStringSync(),
    ) as Map;
    expect(relaySchema['feature'], contains(uploaded['feature']));
    for (final entry in detail.entries) {
      expect(
        (relaySchema['enumValues'] as Map)[entry.key],
        contains(entry.value),
      );
    }
    expect(uploaded.containsKey('traceId'), isFalse);
    expect(uploaded.containsKey('attemptId'), isFalse);
    expect(jsonEncode(uploads), isNot(contains('PRIVATE_')));
    expect(await diagnostics.exportPreview(), isNot(contains('PRIVATE_')));
    expect(
      (await diagnostics.eventsForTesting()).singleWhere(
        (e) => e['eventId'] == local['eventId'],
      ),
      local,
    );
    expect((await diagnostics.status())['queuedEvents'], 0);
  });

  test('BL8 other app kinds keep their existing relay projection', () async {
    final uploads = <Map<String, Object?>>[];
    final diagnostics = await AppDiagnostics.installForTesting(
      directory: Directory('${directory.path}/app'),
      upload: (batch) async {
        uploads.addAll(batch);
        return batch.map((e) => e['eventId']! as String).toSet();
      },
    );
    const detail = <String, Object?>{
      'requestSource': 'live',
      'consentClass': 'withdrawn',
      'requestAction': 'admit',
      'requestDisposition': 'ignored',
      'count': 2,
    };
    diagnostics.record(
      feature: 'runtime',
      stage: 'verify',
      outcome: 'rejected',
      values: detail,
    );
    final local = (await diagnostics.eventsForTesting()).singleWhere(
      (e) => (e['values'] as Map)['requestSource'] == 'live',
    );
    await diagnostics.flush();
    final uploaded = uploads.singleWhere(
      (e) => e['eventId'] == local['eventId'],
    );
    expect(uploaded['feature'], 'runtime');
    expect(uploaded['values'], {'count': 2});
    expectLegacyAccepted(uploaded, 'app');
    expect(local['values'], detail);
  });

  test(
    'call incident details survive locally without rejecting old-relay terminal record',
    () async {
      final uploads = <Map<String, Object?>>[];
      final diagnostics = await CallDiagnostics.installForTesting(
        directory: Directory('${directory.path}/call'),
        upload: (batch) async {
          uploads.addAll(batch);
          return batch.map((e) => e['eventId']! as String).toSet();
        },
      );
      final trace = diagnostics.beginAttempt();
      const snapshot = <String, Object?>{
        'contactAccepted': true,
        'contactBlocked': false,
        'trustedDeviceCount': 16,
        'relayEndpointPresent': true,
        'wakeHandleGrantPresent': false,
      };
      diagnostics.record(
        stage: 'preflight',
        action: 'snapshot',
        outcome: 'ok',
        traceId: trace,
        values: snapshot,
      );
      diagnostics.finishAttempt(
        traceId: trace,
        outcome: 'no_answer',
        values: {
          'accepted': false,
          'connected': false,
          'remoteRingingObserved': true,
          'timeToRemoteRingingMs': 250,
        },
      );
      final events = await diagnostics.eventsForTesting();
      final input = events.singleWhere((e) => e['stage'] == 'preflight');
      expect(input['values'], snapshot);
      final terminal = events.singleWhere((e) => e['stage'] == 'terminal');
      expect(terminal['values'], containsPair('remoteRingingObserved', true));
      expect(terminal['values'], containsPair('timeToRemoteRingingMs', 250));
      await diagnostics.flush();
      for (final event in uploads) {
        expectLegacyAccepted(event, 'call');
      }
      final uploaded = uploads.singleWhere(
        (e) => e['eventId'] == terminal['eventId'],
      );
      expect(uploaded['values'], containsPair('accepted', false));
      expect(uploaded['values'], isNot(contains('remoteRingingObserved')));
      expect(uploaded['values'], isNot(contains('timeToRemoteRingingMs')));
      expect(
        (await diagnostics.eventsForTesting()).singleWhere(
          (e) => e['eventId'] == terminal['eventId'],
        ),
        terminal,
      );
      expect((await diagnostics.status())['queuedEvents'], 0);
    },
  );

  test(
    'call support code uses the latest retained trace and clears with consent',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting(
        directory: Directory('${directory.path}/call'),
      );
      expect((await diagnostics.status()).containsKey('supportCode'), isFalse);
      final first = diagnostics.beginAttempt();
      expect((await diagnostics.status())['supportCode'], first);
      diagnostics.finishAttempt(traceId: first, outcome: 'no_answer');
      final latest = diagnostics.beginAttempt();
      expect((await diagnostics.status())['supportCode'], latest);
      await diagnostics.clear();
      expect((await diagnostics.status()).containsKey('supportCode'), isFalse);
      diagnostics.beginAttempt();
      await diagnostics.setEnabled(false);
      expect((await diagnostics.status()).containsKey('supportCode'), isFalse);
    },
  );

  test(
    'call export status is an explicit allowlist and never exposes raw upload errors',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting(
        directory: Directory('${directory.path}/call'),
        upload: (_) async => throw StateError('PRIVATE_UPLOAD_CONTENT'),
      );
      final trace = diagnostics.beginAttempt();
      await diagnostics.flush();
      final preview = await diagnostics.exportPreview();
      final header = jsonDecode(preview) as Map;
      expect(header['status'], isA<Map>());
      final status = header['status'] as Map;
      expect(status.keys.toSet(), {
        'enabled',
        'retainedEvents',
        'queuedEvents',
        'droppedEvents',
        'storageHealthy',
        'nativeStorageHealthy',
        'consentPending',
        'lastUploadAtMs',
        'lastError',
        'supportCode',
      });
      expect(status['supportCode'], trace);
      expect(status['lastError'], 'sink_unavailable');
      expect(status['queuedEvents'], greaterThan(0));
      expect(preview, isNot(contains('PRIVATE_UPLOAD_CONTENT')));
      expect(status.containsKey('traceCodes'), isFalse);
    },
  );

  test(
    'app rejects private fields and free text in incident vocabulary',
    () async {
      final diagnostics = await AppDiagnostics.installForTesting(
        directory: Directory('${directory.path}/app'),
      );
      diagnostics.record(feature: 'message', stage: 'verify', outcome: 'ok');
      final event = (await diagnostics.eventsForTesting()).last;
      for (final entry in const <String, Object?>{
        'peerId': 'PRIVATE_PEER',
        'content': 'PRIVATE_CONTENT',
        'requestSource': 'PRIVATE_SOURCE',
        'consentClass': 'PRIVATE_CONSENT',
        'requestAction': 'PRIVATE_ACTION',
        'requestDisposition': 'PRIVATE_OUTCOME',
      }.entries) {
        expect(
          AppDiagnostics.validateEvent({
            ...event,
            'values': {entry.key: entry.value},
          }),
          isNull,
        );
      }
      expect(await diagnostics.exportPreview(), isNot(contains('PRIVATE_')));
    },
  );

  test(
    'call rejects peer, grant, content and mistyped incident fields',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting(
        directory: Directory('${directory.path}/call'),
      );
      diagnostics.beginAttempt();
      final event = (await diagnostics.eventsForTesting()).last;
      for (final entry in const <String, Object?>{
        'peerId': 'PRIVATE_PEER',
        'grant': 'PRIVATE_GRANT',
        'content': 'PRIVATE_CONTENT',
        'contactAccepted': 'PRIVATE_BOOL',
        'trustedDeviceCount': 'PRIVATE_COUNT',
        'remoteRingingObserved': 'PRIVATE_BOOL',
        'timeToRemoteRingingMs': 'PRIVATE_TIME',
        'nativeFailureOrigin': 'PRIVATE_ORIGIN',
      }.entries) {
        expect(
          CallDiagnostics.validateEvent({
            ...event,
            'values': {entry.key: entry.value},
          }),
          isNull,
        );
      }
      expect(await diagnostics.exportPreview(), isNot(contains('PRIVATE_')));
    },
  );
}
