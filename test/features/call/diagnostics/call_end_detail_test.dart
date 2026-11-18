import 'dart:io';

import 'package:flutter_app/features/call/diagnostics/call_diagnostic_schema.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_app/features/call/diagnostics/call_end_detail.dart';
import 'package:flutter_test/flutter_test.dart';

const _wait = Duration(seconds: 3);
const _detail = CallEndDetail(
  cause: CallEndCause.recoveryDenied,
  stage: CallEndCauseStage.authority,
  recoveryCheck: CallRecoveryCheck.preferenceEpoch,
  elapsed: Duration(milliseconds: 2499),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp
        .createTemp('typed-call-end-')
        .timeout(_wait);
  });
  tearDown(() async {
    await CallDiagnostics.instance.dispose().timeout(_wait);
    await directory.delete(recursive: true).timeout(_wait);
  });

  Future<CallDiagnostics> install() => CallDiagnostics.installForTesting(
    directory: directory,
    enabled: true,
    upload: (batch) async =>
        batch.map((event) => event['eventId']! as String).toSet(),
  ).timeout(_wait);

  test('typed call-end vocabulary is closed and timing uses whole seconds', () {
    final enums = callDiagnosticSchemaV1['enumValues'] as Map;
    expect(
      CallEndCause.values.map((value) => value.wireValue).toList(),
      enums['endCause'],
    );
    expect(
      CallEndCauseStage.values.map((value) => value.name).toList(),
      enums['endCauseStage'],
    );
    expect(
      CallRecoveryCheck.values.map((value) => value.wireValue).toList(),
      enums['recoveryCheck'],
    );
    for (final entry in {-1: 0, 0: 0, 999: 0, 1000: 1000, 2499: 2000}.entries) {
      final detail = CallEndDetail(
        cause: CallEndCause.localHangup,
        stage: CallEndCauseStage.media,
        elapsed: Duration(milliseconds: entry.key),
      );
      expect(detail.toValues()['durationMs'], entry.value);
      expect(detail.toValues().keys, isNot(contains('recoveryCheck')));
    }
  });

  test('one optional detail follows the unchanged authoritative final', () async {
    final diagnostics = await install();
    final trace = diagnostics.beginAttempt();
    diagnostics.finishAttempt(
      traceId: trace,
      outcome: 'dropped_after_media',
      reason: 'media_stalled',
      values: const {
        'durationMs': 2499,
        'endCause': 'recovery_denied',
        'endCauseStage': 'authority',
        'recoveryCheck': 'preference_epoch',
      },
      detail: _detail,
    );
    diagnostics.finishAttempt(
      traceId: trace,
      outcome: 'completed_after_media',
      reason: 'local_user',
      detail: _detail,
    );
    final terminal = (await diagnostics.eventsForTesting().timeout(_wait))
        .where((event) => event['stage'] == 'terminal')
        .toList();
    expect(terminal, hasLength(2));
    expect(terminal.first['action'], 'finish');
    expect(terminal.first['outcome'], 'dropped_after_media');
    expect(terminal.first['values'], {'durationMs': 2499, 'terminal': true});
    expect(terminal.last['action'], 'snapshot');
    expect(terminal.last['values'], _detail.toValues());
    expect(terminal.last['traceId'], terminal.first['traceId']);
  });

  test('retired consent trace cannot acquire a new end-detail record', () async {
    final diagnostics = await install();
    final trace = diagnostics.beginAttempt();
    await diagnostics.setEnabled(false).timeout(_wait);
    await diagnostics.setEnabled(true).timeout(_wait);
    diagnostics.finishAttempt(
      traceId: trace,
      outcome: 'media_failed',
      reason: 'media_failed',
      detail: _detail,
    );
    final events = await diagnostics.eventsForTesting().timeout(_wait);
    expect(
      events.where((event) =>
          (event['values'] as Map).containsKey('endCause')),
      isEmpty,
    );
  });

  test('detail keys on other events stay out of legacy uploads', () async {
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
      stage: 'media',
      action: 'snapshot',
      outcome: 'failed',
      values: _detail.toValues(),
    );
    await diagnostics.flush().timeout(_wait);
    expect(uploads.single['values'], {'durationMs': 2000});
    final local = (await diagnostics.eventsForTesting().timeout(_wait)).single;
    expect(local['values'], _detail.toValues());
  });

  test('detail pressure cannot evict the authoritative final', () async {
    final diagnostics = await install();
    final trace = diagnostics.beginAttempt();
    diagnostics.finishAttempt(
      traceId: trace,
      outcome: 'dropped_after_media',
      reason: 'media_stalled',
      detail: _detail,
    );
    for (var i = 0; i < 300; i++) {
      diagnostics.record(
        traceId: trace,
        stage: 'terminal',
        action: 'snapshot',
        outcome: 'failed',
        reason: 'authority_rejected',
        values: _detail.toValues(),
      );
    }
    final events = await diagnostics.eventsForTesting().timeout(_wait);
    final original = events.singleWhere(
      (event) => event['stage'] == 'terminal' && event['action'] == 'finish',
    );
    expect(original['outcome'], 'dropped_after_media');
    expect((await diagnostics.status().timeout(_wait))['droppedEvents'],
        greaterThan(0));
  });
}
