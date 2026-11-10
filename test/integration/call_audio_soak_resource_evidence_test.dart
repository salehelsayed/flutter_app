import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/run_call_audio_soak.dart' as soak;

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

  test('VC-024 keeps no-argument execution blocked', () async {
    final result = await _runCli([
      'run',
      'integration_test/scripts/run_call_audio_soak.dart',
    ]);
    expect(result.exitCode, 78);
    final report = _resultJson(result);
    expect(report['status'], 'BLOCKED');
    expect(report['assertionsAttempted'], 0);
    expect(report['approvedDuration'], 1800000);
    expect(report['nativeExecutedByThisCommand'], false);
    expect(report['fullSoakStatus'], 'NOT RUN');
  }, timeout: _cliTestTimeout);

  test('VC-024 preserves scenario listing without running a soak', () async {
    final result = await _runCli([
      'run',
      'integration_test/scripts/run_call_audio_soak.dart',
      '--list-scenarios',
    ]);
    expect(result.exitCode, 0);
    expect(result.stdout, 'production.call.call-audio-soak\n');
  }, timeout: _cliTestTimeout);

  for (final binding in ['source', 'run']) {
    test('VC-024 CLI rejects a replayed $binding binding', () async {
      final report = await _evaluate(
        expectedExit: 1,
        expectedSource: binding == 'source' ? 'c' * 40 : _source,
        expectedRun: binding == 'run' ? 'other-run' : _runId,
      );
      expect(report['resourceCriteria'], 'FAIL_RECORDED');
      expect(report['nativeExecutedByThisCommand'], false);
    }, timeout: _cliTestTimeout);
  }

  test('VC-024 CLI rejects a changed raw file after hashing', () async {
    final report = await _evaluate(expectedExit: 1, changeHashedFile: true);
    expect(report['resourceCriteria'], 'FAIL_RECORDED');
    expect(report['failures'], isNotEmpty);
  }, timeout: _cliTestTimeout);

  for (final boundary in [
    (warm: 100 * _mib, limit: 130 * _mib),
    (warm: 200 * _mib, limit: 240 * _mib),
  ]) {
    test('VC-024 RSS accepts ${boundary.limit} bytes and rejects one more', () {
      final capture = _samples('caller');
      for (final lateRssBytes in [boundary.limit, boundary.limit + 1]) {
        for (final sample in _rows(capture)) {
          sample['rssBytes'] = (sample['atMs'] as int) >= 2100000
              ? lateRssBytes
              : boundary.warm;
        }
        final result = _resources(capture);
        expect(result['rss5Bytes'], boundary.warm);
        expect(result['rssLimitBytes'], boundary.limit);
        expect(result['rss30Bytes'], lateRssBytes);
        expect(
          result['resourceCriteria'],
          lateRssBytes == boundary.limit ? 'PASS_RECORDED' : 'FAIL_RECORDED',
        );
      }
    });
  }

  test('VC-024 CPU is on the one-core scale and can exceed 100 percent', () {
    final result = _resources(_samples('caller', idleCpu: 120, postCpu: 125));
    expect(result['resourceCriteria'], 'PASS_RECORDED');
    expect(result['idleCpuOneCorePct'], 120);
    expect(result['postCpuOneCorePct'], 125);
    expect(result['postCpuLimitOneCorePct'], 125);
  });

  test('VC-024 rejects post-call CPU above idle plus five points', () {
    final result = _resources(_samples('caller', postCpu: 15.01));
    expect(result['resourceCriteria'], 'FAIL_RECORDED');
    expect(result['postCpuOneCorePct'], closeTo(15.01, 1e-8));
    expect(result['postCpuLimitOneCorePct'], 15);
  });

  test('VC-024 rejects the relative in-call CPU branch above its limit', () {
    final result = _resources(_samples('caller', lateSpeakerCpu: 48.01));
    expect(result['resourceCriteria'], 'FAIL_RECORDED');
    final speaker = (result['inCallCpu'] as Map)['speaker'] as Map;
    expect(speaker['limitCpuOneCorePct'], 48);
    expect(speaker['lateCpuOneCorePct'], closeTo(48.01, 1e-8));
  });

  final invalid = <String, void Function(Map<String, Object?>)>{
    'duration of 1799.999 seconds': (c) => c['endedAtMs'] = 2099999,
    'host-only observations': (c) => c['executionKind'] = 'host-fake-clock',
    'wall-clock measurements': (c) => c['clockType'] = 'wall',
    'missing clock identity': (c) => c.remove('clockId'),
    'raw source replay': (c) => c['candidateSource'] = 'c' * 40,
    'raw run replay': (c) => c['runId'] = 'other-run',
    'wrong endpoint': (c) => c['deviceId'] = 'other-device',
    'wrong artifact': (c) => c['artifactSha256'] = 'c' * 64,
    'PSS instead of RSS': (c) => c['memoryMetric'] = 'pss',
    'physical footprint instead of RSS': (c) =>
        c['memoryMetric'] = 'physical-footprint',
    'megabytes instead of bytes': (c) => c['memoryUnit'] = 'MB',
    'mixed CPU scale': (c) => c['cpuCounterUnit'] = 'whole-device-percent',
    'process restart': (c) => _rows(c)[120]['pid'] = 102,
    'PID reuse': (c) => _rows(c)[120]['processStartId'] = 'restarted',
    'replaced canonical call': (c) =>
        _rows(c)[120]['canonicalCallId'] = 'other-call',
    'changed connected time': (c) => _rows(c)[120]['connectedAtMs'] = 300001,
    'negative resident bytes': (c) => _rows(c)[120]['rssBytes'] = -1,
    'nonfinite CPU counter': (c) =>
        _rows(c)[120]['processCpuSeconds'] = double.nan,
    'reset CPU counter': (c) => _rows(c)[120]['processCpuSeconds'] = 0,
    'nonmonotonic sample time': (c) => _rows(c)[120]['atMs'] = 1190000,
    'missing warm sample interval': (c) => (c['samples'] as List).removeAt(60),
    'post-idle before the call ends': (c) =>
        c['postObservationStartMs'] = 2219999,
    'unknown post-idle selection policy': (c) =>
        c['postObservationPolicy'] = 'lowest-five-minutes',
    'window plan declared after connection': (c) =>
        c['windowPlanDeclaredAtMs'] = 300001,
    'late window chosen before minute 29': (c) =>
        (c['inCallCpuWindows'] as List).first['lateStartMs'] = 1500000,
    'unconfirmed actual speaker route': (c) =>
        _rows(c)[217]['route'] = 'earpiece',
  };
  for (final entry in invalid.entries) {
    test('VC-024 rejects ${entry.key}', () {
      final capture = _samples('caller');
      entry.value(capture);
      final result = _resources(capture);
      expect(result['resourceCriteria'], 'FAIL_RECORDED');
      expect(result['failures'], isNotEmpty);
      expect(result['nativeExecutedByThisCommand'], false);
    });
  }
}

List<Map<String, Object?>> _rows(Map<String, Object?> capture) =>
    (capture['samples'] as List).cast<Map<String, Object?>>();

Map<String, Object?> _resources(Map<String, Object?> capture) =>
    soak.evaluateCallAudioSoakResources(
      capture,
      expectedSource: _source,
      expectedRunId: _runId,
      role: 'caller',
      target: _target('caller'),
      canonicalCallId: _callId,
    );

Future<Map> _evaluate({
  int expectedExit = 78,
  Map<String, Object?>? callerCapture,
  void Function(Map<String, Object?>)? changeCaller,
  String expectedSource = _source,
  String expectedRun = _runId,
  bool changeHashedFile = false,
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
  if (changeHashedFile) {
    await File('${directory.path}/caller-resources.json').writeAsString('{}');
  }
  final result = await _runCli([
    'run',
    'integration_test/scripts/run_call_audio_soak.dart',
    '--assert-resource-evidence',
    input.path,
    '--source',
    expectedSource,
    '--run-id',
    expectedRun,
  ]);
  expect(
    result.exitCode,
    expectedExit,
    reason: '${result.stderr}\n${result.stdout}',
  );
  return _resultJson(result);
}

Map _resultJson(ProcessResult result) {
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
  double lateSpeakerCpu = 48,
  double idleCpu = 10,
  double postCpu = 15,
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
          ? idleCpu
          : atMs > postStart
          ? postCpu
          : atMs > ended
          ? 80.0
          : relative > 360000 && relative <= 420000
          ? 40.0
          : relative > 1740000 && relative <= 1800000
          ? lateEarpieceCpu
          : relative > 1860000 && relative <= 1920000
          ? lateSpeakerCpu
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
