import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('shared harness media repository wires the ordinary-group CAS '
      'callbacks production wires', () {
    final harness = _read(
      'integration_test/group_multi_device_real_harness.dart',
    );
    final start = harness.indexOf('MediaAttachmentRepositoryImpl(');
    expect(start, isNonNegative);
    final block = harness.substring(
      start,
      harness.indexOf('secureKeyStore:', start),
    );
    for (final callback in const [
      'dbBeginOrdinaryGroupAutomaticMediaDownloadExact',
      'dbBeginOrdinaryGroupExplicitMediaDownloadExact',
      'dbCommitOrdinaryGroupAutomaticMediaDownloadLocalPathExact',
      'dbCommitOrdinaryGroupExplicitMediaDownloadLocalPathExact',
      'dbRecordOrdinaryGroupMediaDownloadFailureExact',
    ]) {
      expect(block, contains('$callback:'), reason: callback);
    }
  });

  test('multi-party harness never reports a P2P send as delivered without '
      'its result', () {
    final harness = _read(
      'integration_test/group_multi_party_device_real_harness.dart',
    );
    final discarded = RegExp(
      r'await [\w.]+\.sendMessage\([^;]*\);\s*return true;',
    ).allMatches(harness);
    expect(discarded, isEmpty);
    final rotationAdapters = RegExp(
      r'sendP2PMessage: groupKeyTransport\(stack\.p2pService\)\.send,\s*'
      r'storeP2PMessageInInbox: groupKeyTransport\(stack\.p2pService\)\.inbox,',
    ).allMatches(harness);
    expect(rotationAdapters.length, greaterThanOrEqualTo(7));
  });

  test('process-death orchestration fails at an active role exit instead of '
      'waiting out a downstream checkpoint', () {
    final orchestrator = _read(
      'integration_test/scripts/run_group_multi_party_device_real.dart',
    );
    final start = orchestrator.indexOf(
      'Future<T> untilActiveRoleExits<T>(Future<T> wait)',
    );
    expect(start, isNonNegative);
    final body = orchestrator.substring(
      start,
      orchestrator.indexOf('final verdicts = await Future.wait', start),
    );
    expect(body, contains('processes[label]!.exitCode'));
    final waits = RegExp(r'signals\.waitFor(Signal|Json)\(').allMatches(body);
    final guarded = RegExp(
      r'untilActiveRoleExits\(\s*signals\.waitFor(Signal|Json)\(',
    ).allMatches(body);
    expect(waits.length, 6);
    expect(guarded.length, waits.length);
  });
}
