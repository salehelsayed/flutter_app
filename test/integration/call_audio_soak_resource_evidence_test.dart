import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _runId = 'resource-parser-fixture';
const _callId = 'canonical-call-fixture';
const _mib = 1024 * 1024;
const _cliTestTimeout = Timeout(Duration(minutes: 4));

void main() {
  test(
    'VC-024 CLI records resource bounds without claiming a native soak',
    () async {
      final report = await _evaluate();
      expect(report['status'], 'NOT RUN');
      expect(report['resourceCriteria'], 'PASS_RECORDED');
      expect(report['fullSoakStatus'], 'NOT RUN');
      expect(report['nativeExecutedByThisCommand'], false);
      expect(report['inCallCpuApprovalDate'], '2026-11-10');
      expect(report['failures'], isEmpty);
      final endpoints = report['endpoints'] as Map;
      expect(endpoints.keys, unorderedEquals(['caller', 'callee']));
      for (final endpoint in endpoints.values.cast<Map>()) {
        expect(endpoint['durationMs'], 1920000);
        expect(endpoint['rss30Bytes'], 130 * _mib);
        expect(endpoint['rssLimitBytes'], 130 * _mib);
        expect(endpoint['idleCpuOneCorePct'], 10);
        expect(endpoint['postCpuOneCorePct'], 15);
        expect(endpoint['postCpuLimitOneCorePct'], 15);
        final routes = endpoint['inCallCpu'] as Map;
        expect(routes.keys, unorderedEquals(['earpiece', 'speaker']));
        expect(routes['earpiece']['warmCpuOneCorePct'], 20);
        expect(routes['earpiece']['lateCpuOneCorePct'], 25);
        expect(routes['earpiece']['limitCpuOneCorePct'], 25);
        expect(routes['speaker']['warmCpuOneCorePct'], 40);
        expect(routes['speaker']['lateCpuOneCorePct'], closeTo(48, 1e-8));
        expect(routes['speaker']['limitCpuOneCorePct'], 48);
      }
    },
    timeout: _cliTestTimeout,
  );
  test('VC-024 rejects a missing required matched-route window', () async {
    final report = await _evaluate(
      expectedExit: 1,
      changeCaller: (capture) {
        (capture['inCallCpuWindows'] as List).removeWhere(
          (window) => window['route'] == 'speaker',
        );
      },
    );
    expect(report['resourceCriteria'], 'FAIL_RECORDED');
    expect(report['failures'], isNotEmpty);
    expect(report['endpoints']['callee']['resourceCriteria'], 'PASS_RECORDED');
    expect(report['fullSoakStatus'], 'NOT RUN');
  }, timeout: _cliTestTimeout);
  test('VC-024 rejects in-call CPU above its approved growth bound', () async {
    final report = await _evaluate(
      expectedExit: 1,
      callerCapture: _samples('caller', lateEarpieceCpu: 25.01),
    );
    expect(report['resourceCriteria'], 'FAIL_RECORDED');
    final caller = report['endpoints']['caller'] as Map;
    expect(
      caller['inCallCpu']['earpiece']['lateCpuOneCorePct'],
      closeTo(25.01, 1e-8),
    );
    expect(caller['inCallCpu']['earpiece']['limitCpuOneCorePct'], 25);
    expect(caller['failures'], isNotEmpty);
    expect(report['nativeExecutedByThisCommand'], false);
  }, timeout: _cliTestTimeout);
  test('VC-024 observes post-call idle after owned recovery', () async {
    final report = await _evaluate(
      callerCapture: _samples('caller', postDelayMs: 360000),
    );
    final caller = report['endpoints']['caller'] as Map;
    expect(caller['resourceCriteria'], 'PASS_RECORDED');
    expect(caller['postObservationStartMs'], 2580000);
    expect(caller['postCpuOneCorePct'], 15);
    expect(caller['postCpuLimitOneCorePct'], 15);
  }, timeout: _cliTestTimeout);
  test('VC-024 rejects an incomplete declared post-idle period', () async {
    final report = await _evaluate(
      expectedExit: 1,
      changeCaller: (capture) {
        (capture['samples'] as List).removeLast();
      },
    );
    expect(report['resourceCriteria'], 'FAIL_RECORDED');
    expect(report['endpoints']['caller']['failures'], isNotEmpty);
  }, timeout: _cliTestTimeout);
}

Future<Map> _evaluate({
  int expectedExit = 78,
  Map<String, Object?>? callerCapture,
  void Function(Map<String, Object?>)? changeCaller,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'vc024-resource-evidence-',
  );
  addTearDown(() => directory.delete(recursive: true));
  final receipt = _receipt();
  final evidence = <Map<String, Object?>>[];
  for (final role in ['caller', 'callee']) {
    final capture = role == 'caller' && callerCapture != null
        ? callerCapture
        : _samples(role);
    if (role == 'caller') changeCaller?.call(capture);
    final bytes = utf8.encode(jsonEncode(capture));
    final path = '$role-resources.json';
    await File('${directory.path}/$path').writeAsBytes(bytes);
    evidence.add({
      'path': path,
      'sha256': sha256.convert(bytes).toString(),
      'kind': 'call-resource-samples',
    });
  }
  receipt['evidence'] = evidence;
  final input = File('${directory.path}/receipt.json');
  await input.writeAsString(jsonEncode(receipt));
  final result = await _runCli([
    'run',
    'integration_test/scripts/run_call_audio_soak.dart',
    '--assert-resource-evidence',
    input.path,
    '--source',
    _source,
    '--run-id',
    _runId,
  ]);
  expect(
    result.exitCode,
    expectedExit,
    reason: '${result.stderr}\n${result.stdout}',
  );
  final line = const LineSplitter()
      .convert(result.stdout as String)
      .singleWhere((line) => line.startsWith('SIMS_RESULT_JSON='));
  return jsonDecode(line.substring('SIMS_RESULT_JSON='.length)) as Map;
}

Future<ProcessResult> _runCli(List<String> arguments) async {
  final process = await Process.start('dart', arguments);
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  var exited = false;
  final completion = process.exitCode.then((code) {
    exited = true;
    return code;
  });
  Future<void> stopOwnedChild() async {
    if (!exited) {
      process.kill(ProcessSignal.sigkill);
      await completion.timeout(const Duration(seconds: 5));
    }
  }

  addTearDown(stopOwnedChild);
  try {
    final code = await completion.timeout(const Duration(minutes: 3));
    return ProcessResult(process.pid, code, await output, await errors);
  } on TimeoutException {
    await stopOwnedChild();
    rethrow;
  }
}

Map<String, Object?> _receipt() => {
  'schema': 'mknoon.production-journey-gap.v1',
  'journeyId': 'VC-024',
  'runId': _runId,
  'candidateSource': _source,
  'executionStatus': 'complete',
  'targets': {
    for (final role in ['caller', 'callee']) role: _target(role),
  },
  'observations': {
    'canonicalCallId': _callId,
    'resourceFiles': {
      'caller': 'caller-resources.json',
      'callee': 'callee-resources.json',
    },
  },
};

Map<String, Object?> _target(String role) => {
  'deviceId': 'fixture-$role',
  'platform': 'android',
  'kind': role == 'caller' ? 'usb_physical' : 'android_emulator',
  'artifactSha256': 'b' * 64,
};

// Synthetic measurements exercise the recorded-evidence parser, not devices.
Map<String, Object?> _samples(
  String role, {
  double lateEarpieceCpu = 25,
  int postDelayMs = 0,
}) {
  const connected = 300000;
  const ended = connected + 1920000;
  final postStart = ended + postDelayMs;
  final samples = <Map<String, Object?>>[];
  var cpuSeconds = 0.0;
  for (var atMs = 0; atMs <= postStart + 300000; atMs += 10000) {
    if (atMs > 0) {
      final relative = atMs - connected;
      final cpuPercent = atMs <= connected
          ? 10.0
          : atMs > postStart
          ? 15.0
          : atMs > ended
          ? 80.0
          : relative > 360000 && relative <= 420000
          ? 40.0
          : relative > 1740000 && relative <= 1800000
          ? lateEarpieceCpu
          : relative > 1860000 && relative <= 1920000
          ? 48.0
          : 20.0;
      cpuSeconds += cpuPercent / 100 * 10;
    }
    final inCall = atMs >= connected && atMs <= ended;
    samples.add({
      'atMs': atMs,
      'pid': 101,
      'processStartId': 'same-process-$role',
      'processCpuSeconds': cpuSeconds,
      'rssBytes': atMs >= connected + 1800000 ? 130 * _mib : 100 * _mib,
      'canonicalCallId': inCall ? _callId : null,
      'connectedAtMs': inCall ? connected : null,
      'route': !inCall
          ? null
          : (atMs >= connected + 350000 && atMs <= connected + 430000) ||
                atMs >= connected + 1850000
          ? 'speaker'
          : 'earpiece',
    });
  }
  return {
    'schema': 'mknoon.call-resource-samples.v1',
    'runId': _runId,
    'candidateSource': _source,
    'role': role,
    'deviceId': 'fixture-$role',
    'artifactSha256': 'b' * 64,
    'executionKind': 'device-monotonic',
    'clockId': 'fixture-boot-$role',
    'clockType': 'monotonic',
    'memoryMetric': 'rss',
    'memoryUnit': 'bytes',
    'cpuCounterUnit': 'seconds',
    'canonicalCallId': _callId,
    'pid': 101,
    'processStartId': 'same-process-$role',
    'connectedAtMs': connected,
    'endedAtMs': ended,
    'postObservationStartMs': postStart,
    'postObservationPolicy': 'first-five-idle-minutes-after-owned-recovery',
    'windowPlanDeclaredAtMs': 0,
    'inCallCpuWindows': [
      {
        'route': 'earpiece',
        'warmStartMs': connected + 240000,
        'lateStartMs': connected + 1740000,
      },
      {
        'route': 'speaker',
        'warmStartMs': connected + 360000,
        'lateStartMs': connected + 1860000,
      },
    ],
    'samples': samples,
  };
}
