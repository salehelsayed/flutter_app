import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

const _wait = Duration(seconds: 3);
const _detail = <String, Object?>{
  'endCause': 'recovery_denied',
  'endCauseStage': 'authority',
  'recoveryCheck': 'preference_epoch',
  'durationMs': 2000,
};

final class _LegacyRelay implements Bridge {
  _LegacyRelay() {
    final schema = jsonDecode(File(
      'test/core/diagnostics/fixtures/call_schema_before_incident_fields.json',
    ).readAsStringSync()) as Map;
    knownValues = <Object?>{
      ...(schema['booleanValues'] as List),
      ...(schema['integerValues'] as List),
      ...(schema['enumValues'] as Map).keys,
    };
  }

  late final Set<Object?> knownValues;
  final accepted = <Map<String, dynamic>>[];
  final rejected = <Map<String, dynamic>>[];

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) async {
    final envelope = jsonDecode(message) as Map;
    if (envelope['cmd'] != 'call_diagnostics_v1' ||
        envelope['payload'] is! Map) {
      return jsonEncode({'ok': false, 'errorCode': 'INVALID_BRIDGE_REQUEST'});
    }
    final request = envelope['payload'] as Map;
    final events = (request['events'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final acceptedIds = <String>[];
    final rejectedIds = <String>[];
    for (final event in events) {
      final values = event['values'] as Map;
      if (values.keys.every(knownValues.contains)) {
        accepted.add(event);
        acceptedIds.add(event['eventId'] as String);
      } else {
        rejected.add(event);
        rejectedIds.add(event['eventId'] as String);
      }
    }
    return jsonEncode({
      'ok': true,
      'data': {
        'supported': true,
        'enabled': request['enabled'] ?? true,
        'acceptedEventIds': acceptedIds,
        'rejectedEventIds': rejectedIds,
      },
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp
        .createTemp('call-end-detail-')
        .timeout(_wait);
  });
  tearDown(() async {
    await CallDiagnostics.instance.dispose().timeout(_wait);
    await directory.delete(recursive: true).timeout(_wait);
  });

  test('BL43 closed call-end detail survives export and relay upload', () async {
    final uploads = <Map<String, Object?>>[];
    final diagnostics = await CallDiagnostics.installForTesting(
      directory: directory,
      enabled: true,
      upload: (batch) async {
        uploads.addAll(batch);
        return batch.map((event) => event['eventId']! as String).toSet();
      },
    ).timeout(_wait);
    diagnostics.record(
      stage: 'terminal',
      action: 'snapshot',
      outcome: 'failed',
      reason: 'authority_rejected',
      values: _detail,
    );
    final local = (await diagnostics.eventsForTesting().timeout(_wait)).single;
    expect(local['values'], _detail);
    final preview = jsonDecode(
      await diagnostics.exportPreview().timeout(_wait),
    ) as Map;
    expect((preview['events'] as List).single['values'], _detail);
    await diagnostics.flush().timeout(_wait);
    expect(uploads.single['values'], _detail);
  });

  test('BL43 older relay can reject detail while accepting the original final',
      () async {
    final relay = _LegacyRelay();
    final diagnostics = await CallDiagnostics.installForTesting(
      directory: directory,
      enabled: true,
      bridge: relay,
    ).timeout(_wait);
    final trace = diagnostics.beginAttempt();
    diagnostics.record(
      traceId: trace,
      stage: 'terminal',
      action: 'snapshot',
      outcome: 'failed',
      reason: 'authority_rejected',
      values: _detail,
    );
    diagnostics.finishAttempt(
      traceId: trace,
      outcome: 'dropped_after_media',
      reason: 'media_stalled',
      values: const {'durationMs': 2499},
    );
    await diagnostics.flush().timeout(_wait);
    expect(relay.rejected, hasLength(1));
    final original = relay.accepted.singleWhere(
      (event) => event['stage'] == 'terminal' && event['action'] == 'finish',
    );
    expect(original['outcome'], 'dropped_after_media');
    expect(original['values'], {'durationMs': 2499, 'terminal': true});
    expect((await diagnostics.status().timeout(_wait))['queuedEvents'], 0);
    expect((await diagnostics.status().timeout(_wait))['droppedEvents'], 1);
  });

  test('BL43 arbitrary cause strings and personal fields never enter exports',
      () async {
    final diagnostics = await CallDiagnostics.installForTesting(
      directory: directory,
      enabled: true,
      upload: (batch) async =>
          batch.map((event) => event['eventId']! as String).toSet(),
    ).timeout(_wait);
    diagnostics.record(
      stage: 'terminal',
      action: 'snapshot',
      outcome: 'failed',
      values: const {
        'endCause': 'PRIVATE_PEER',
        'endCauseStage': 'PRIVATE_PHONE',
        'recoveryCheck': 'PRIVATE_KEY',
        'peerId': 'PRIVATE_PEER',
        'phoneNumber': 'PRIVATE_PHONE',
        'ipAddress': '192.0.2.1',
        'message': 'PRIVATE_MESSAGE',
        'durationMs': 2000,
      },
    );
    final preview = await diagnostics.exportPreview().timeout(_wait);
    expect(preview, isNot(contains('PRIVATE_')));
    expect(preview, isNot(contains('192.0.2.1')));
    final events = (jsonDecode(preview) as Map)['events'] as List;
    expect(events.single['values'], {'durationMs': 2000});
  });
}
