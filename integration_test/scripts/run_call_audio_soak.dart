import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'contact_transfer_native_evidence.dart';

const _scenario = 'production.call.call-audio-soak';
const _minuteMs = 60000.0;
const _mib = 1024 * 1024;
const _postPolicy = 'first-five-idle-minutes-after-owned-recovery';
const _cpuApprovalDate = '2026-11-10';

typedef _ResourceSample = ({
  double atMs,
  double cpuSeconds,
  int rssBytes,
  String? route,
});

/// Evaluates retained measurements, not their capture or whole-call behavior.
Map<String, Object?> evaluateCallAudioSoakResources(
  Map<String, Object?> capture, {
  required String expectedSource,
  required String expectedRunId,
  required String role,
  required Map<String, Object?> target,
  required String canonicalCallId,
}) {
  final failures = <String>[];
  final report = <String, Object?>{
    'resourceCriteria': 'FAIL_RECORDED',
    'nativeExecutedByThisCommand': false,
    'failures': failures,
  };
  try {
    _require(
      capture['schema'] == 'mknoon.call-resource-samples.v1' &&
          capture['candidateSource'] == expectedSource &&
          capture['runId'] == expectedRunId &&
          capture['role'] == role &&
          capture['deviceId'] == target['deviceId'] &&
          capture['artifactSha256'] == target['artifactSha256'] &&
          canonicalCallId.isNotEmpty &&
          capture['canonicalCallId'] == canonicalCallId,
      'resource source, run, endpoint, artifact or call binding mismatch',
    );
    _require(
      capture['executionKind'] == 'device-monotonic' &&
          capture['clockType'] == 'monotonic' &&
          _nonempty(capture['clockId']),
      'device monotonic clock and identity required',
    );
    _require(
      capture['memoryMetric'] == 'rss' &&
          capture['memoryUnit'] == 'bytes' &&
          capture['cpuCounterUnit'] == 'seconds',
      'RSS bytes and cumulative process CPU seconds required',
    );
    final pid = _integer(capture['pid'], 'pid');
    final processStart = capture['processStartId'];
    _require(pid > 0 && _nonempty(processStart), 'process identity required');
    final connected = _number(capture['connectedAtMs'], 'connected time');
    final ended = _number(capture['endedAtMs'], 'ended time');
    final postStart = capture['postObservationStartMs'] == null
        ? ended
        : _number(capture['postObservationStartMs'], 'post-observation start');
    final duration = ended - connected;
    report['durationMs'] = duration;
    report['postObservationStartMs'] = postStart;
    _require(duration >= 30 * _minuteMs, 'call duration is below 1800 seconds');
    _require(
      connected >= 5 * _minuteMs && postStart >= ended,
      'five idle minutes before connection and post-idle after end required',
    );
    _require(
      capture['postObservationPolicy'] == _postPolicy,
      'post-idle selection policy is not fixed',
    );
    _require(
      _number(capture['windowPlanDeclaredAtMs'], 'window declaration') <
          connected,
      'resource windows must be declared before connection',
    );

    final rows = _rows(capture['samples'], 'resource samples');
    _require(rows.length >= 2, 'resource samples missing');
    final samples = <_ResourceSample>[];
    for (final row in rows) {
      final atMs = _number(row['atMs'], 'sample time');
      final cpu = _number(row['processCpuSeconds'], 'process CPU seconds');
      final rss = _integer(row['rssBytes'], 'RSS bytes');
      _require(rss > 0, 'positive resident memory required');
      _require(
        row['pid'] == pid && row['processStartId'] == processStart,
        'process changed during resource observation',
      );
      if (atMs >= connected && atMs <= ended) {
        _require(
          row['canonicalCallId'] == canonicalCallId &&
              row['connectedAtMs'] == connected,
          'canonical call or connected time changed',
        );
      } else if ((atMs >= connected - 5 * _minuteMs && atMs < connected) ||
          (atMs > postStart && atMs <= postStart + 5 * _minuteMs)) {
        _require(
          row['canonicalCallId'] == null,
          'idle CPU period contains an active call',
        );
      }
      _require(
        row['route'] == null || row['route'] is String,
        'invalid route observation',
      );
      if (samples.isNotEmpty) {
        final previous = samples.last;
        _require(
          atMs > previous.atMs && atMs - previous.atMs <= 15000,
          'resource samples are nonmonotonic or have a gap above 15 seconds',
        );
        _require(cpu >= previous.cpuSeconds, 'process CPU counter reset');
      }
      samples.add((
        atMs: atMs,
        cpuSeconds: cpu,
        rssBytes: rss,
        route: row['route'] as String?,
      ));
    }
    _require(
      samples.first.atMs <= connected - 5 * _minuteMs &&
          samples.last.atMs >= postStart + 5 * _minuteMs,
      'complete five-minute idle and post-idle observations required',
    );

    _ResourceSample rssAt(double targetMs) {
      final available = samples.where(
        (sample) =>
            sample.atMs >= targetMs &&
            sample.atMs <= targetMs + 15000 &&
            sample.atMs <= ended,
      );
      _require(
        available.isNotEmpty,
        'required in-call RSS observation missing',
      );
      return available.first;
    }

    final warmRss = rssAt(connected + 5 * _minuteMs);
    final lateRss = rssAt(connected + 30 * _minuteMs);
    final rss5 = warmRss.rssBytes;
    final rss30 = lateRss.rssBytes;
    final rssLimit = math.max(1.20 * rss5, rss5 + 30 * _mib);
    report.addAll({
      'rss5Bytes': rss5,
      'rss30Bytes': rss30,
      'rssLimitBytes': rssLimit,
      'rss5SampleAtMs': warmRss.atMs,
      'rss30SampleAtMs': lateRss.atMs,
      'maximumSampleGapMs': 15000,
    });
    if (rss30 > rssLimit)
      failures.add('minute-30 RSS exceeds its growth bound');

    final idleCpu = _cpuMedian(samples, connected - _minuteMs, connected);
    final postCpu = _cpuMedian(
      samples,
      postStart + 4 * _minuteMs,
      postStart + 5 * _minuteMs,
    );
    report.addAll({
      'cpuScale': 'percent-one-core',
      'idleCpuOneCorePct': idleCpu,
      'postCpuOneCorePct': postCpu,
      'postCpuLimitOneCorePct': idleCpu + 5,
    });
    if (postCpu > idleCpu + 5)
      failures.add('post-idle CPU exceeds idle plus five percentage points');

    final windows = _rows(capture['inCallCpuWindows'], 'in-call CPU windows');
    _require(
      windows.length == 2 &&
          windows.map((window) => window['route']).toSet().containsAll([
            'earpiece',
            'speaker',
          ]),
      'one matched CPU window for earpiece and speaker is required',
    );
    final routes = <String, Object?>{};
    report['inCallCpu'] = routes;
    for (final window in windows) {
      final route = window['route'] as String;
      final warm = _number(window['warmStartMs'], '$route warm start');
      final lateStart = _number(window['lateStartMs'], '$route late start');
      _require(
        warm >= connected + 4 * _minuteMs &&
            warm + _minuteMs <= connected + 8 * _minuteMs &&
            lateStart >= connected + 29 * _minuteMs &&
            lateStart + _minuteMs <= ended,
        '$route requires an early warm window and a late window at or after minute 29',
      );
      final warmCpu = _cpuMedian(samples, warm, warm + _minuteMs, route: route);
      final lateCpu = _cpuMedian(
        samples,
        lateStart,
        lateStart + _minuteMs,
        route: route,
      );
      final limit = math.max(1.20 * warmCpu, warmCpu + 5);
      routes[route] = {
        'warmStartMs': warm,
        'lateStartMs': lateStart,
        'warmCpuOneCorePct': warmCpu,
        'lateCpuOneCorePct': lateCpu,
        'limitCpuOneCorePct': limit,
      };
      if (lateCpu > limit)
        failures.add('$route in-call CPU exceeds its growth bound');
    }
  } on FormatException catch (error) {
    failures.add(error.message);
  }
  report['resourceCriteria'] = failures.isEmpty
      ? 'PASS_RECORDED'
      : 'FAIL_RECORDED';
  return report;
}

double _cpuMedian(
  List<_ResourceSample> samples,
  double start,
  double end, {
  String? route,
}) {
  final values = <({double value, double weight})>[];
  var covered = 0.0;
  for (var index = 1; index < samples.length; index++) {
    final before = samples[index - 1];
    final after = samples[index];
    final overlap = math.min(end, after.atMs) - math.max(start, before.atMs);
    if (overlap <= 0) continue;
    if (route != null) {
      _require(
        before.route == route && after.route == route,
        '$route CPU window has unconfirmed route state',
      );
    }
    final percent =
        100000 *
        (after.cpuSeconds - before.cpuSeconds) /
        (after.atMs - before.atMs);
    _require(percent.isFinite, 'nonfinite derived CPU percentage');
    values.add((value: percent, weight: overlap));
    covered += overlap;
  }
  _require(
    (covered - (end - start)).abs() < 0.001 && values.isNotEmpty,
    'complete 60-second CPU window required',
  );
  values.sort((a, b) => a.value.compareTo(b.value));
  var weight = 0.0;
  for (var index = 0; index < values.length; index++) {
    weight += values[index].weight;
    if (weight >= covered / 2) {
      final value =
          (weight - covered / 2).abs() < 0.001 && index + 1 < values.length
          ? (values[index].value + values[index + 1].value) / 2
          : values[index].value;
      return double.parse(value.toStringAsFixed(9));
    }
  }
  throw const FormatException('CPU median unavailable');
}

bool _nonempty(Object? value) => value is String && value.isNotEmpty;

void _require(bool condition, String message) {
  if (!condition) throw FormatException(message);
}

double _number(Object? value, String name) {
  if (value is! num || !value.isFinite || value < 0)
    throw FormatException('invalid $name');
  return value.toDouble();
}

int _integer(Object? value, String name) {
  if (value is! int || value < 0) throw FormatException('invalid $name');
  return value;
}

List<Map<String, Object?>> _rows(Object? value, String name) {
  _require(
    value is List && value.every((entry) => entry is Map<String, Object?>),
    'invalid $name',
  );
  return (value as List).cast<Map<String, Object?>>();
}

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.writeln(_scenario);
    return;
  }
  if (arguments.isEmpty) {
    _writeResult({
      'status': 'BLOCKED',
      'blocker': 'missingDriver',
      'assertionsAttempted': 0,
      'artifactPresent': false,
      'resourceCriteria': 'NOT RUN',
      'detail':
          'Current sustained-call, scoped audio/route, resource and cleanup evidence has not been collected.',
    }, 78);
    return;
  }
  const options = {'--assert-resource-evidence', '--source', '--run-id'};
  final parsed = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    if (index + 1 >= arguments.length ||
        !options.contains(arguments[index]) ||
        parsed.containsKey(arguments[index])) {
      stderr.writeln(
        'Use --list-scenarios or --assert-resource-evidence FILE --source FULL_SHA --run-id ID.',
      );
      exitCode = 64;
      return;
    }
    parsed[arguments[index]] = arguments[index + 1];
  }
  if (parsed.length != options.length) {
    stderr.writeln(
      'Resource evidence requires --assert-resource-evidence, --source and --run-id.',
    );
    exitCode = 64;
    return;
  }
  final failures = <String>[];
  final endpoints = <String, Object?>{};
  var artifactPresent = false;
  try {
    final evidence = await ContactTransferNativeEvidence.load(
      [
        '--receipt',
        parsed['--assert-resource-evidence']!,
        '--source',
        parsed['--source']!,
        '--run-id',
        parsed['--run-id']!,
      ],
      journeyId: 'VC-024',
      requiredKinds: ['call-resource-samples'],
    );
    artifactPresent = true;
    final targets = journeyGapMap(evidence.receipt['targets']);
    final files = journeyGapMap(evidence.observations['resourceFiles']);
    final callId = evidence.observations['canonicalCallId'];
    _require(
      targets.length >= 2 &&
          files.length == targets.length &&
          targets.keys.every(files.containsKey) &&
          _nonempty(callId),
      'resource files for every pinned endpoint and one canonical call are required',
    );
    for (final target in targets.entries) {
      Map<String, Object?> result;
      try {
        result = evaluateCallAudioSoakResources(
          await evidence.json(files[target.key]),
          expectedSource: parsed['--source']!,
          expectedRunId: parsed['--run-id']!,
          role: target.key,
          target: journeyGapMap(target.value),
          canonicalCallId: callId as String,
        );
      } on FormatException catch (error) {
        result = {
          'resourceCriteria': 'FAIL_RECORDED',
          'failures': [error.message],
          'nativeExecutedByThisCommand': false,
        };
      } on FileSystemException {
        result = {
          'resourceCriteria': 'FAIL_RECORDED',
          'failures': ['resource file unreadable'],
          'nativeExecutedByThisCommand': false,
        };
      }
      endpoints[target.key] = result;
      failures.addAll(
        (result['failures'] as List).map(
          (failure) => '${target.key}: $failure',
        ),
      );
    }
  } on ContactTransferCaptureUnavailable {
    failures.add('recorded resource capture is not complete');
  } on FormatException catch (error) {
    failures.add(error.message);
  } on FileSystemException {
    failures.add('recorded resource evidence is unreadable');
  }
  _writeResult({
    'status': failures.isEmpty ? 'NOT RUN' : 'FAIL',
    'resourceCriteria': failures.isEmpty ? 'PASS_RECORDED' : 'FAIL_RECORDED',
    'assertionsAttempted': endpoints.length,
    'artifactPresent': artifactPresent,
    'endpoints': endpoints,
    'failures': failures,
    'provenanceLimit':
        'Digests bind supplied measurements to retained files; this command does not authenticate their device capture.',
  }, failures.isEmpty ? 78 : 1);
}

void _writeResult(Map<String, Object?> result, int code) {
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode({
      'scenario': _scenario,
      'journeyId': 'VC-024',
      'printOnly': false,
      'exitCode': code,
      'fullSoakStatus': 'NOT RUN',
      'nativeExecutedByThisCommand': false,
      'physicalAudioOutput': 'NOT PROVEN',
      'approvedDuration': 1800000,
      'inCallCpuApprovalDate': _cpuApprovalDate,
      'approvedResourceThresholds': {'rss': 'rss30 <= max(1.20 * rss5, rss5 + 30 MiB)', 'postCpu': 'post idle median <= idle median + 5 percentage points', 'inCallCpu': 'matched-route late median <= max(1.20 * warm median, warm median + 5 percentage points)'},
      ...result,
    })}',
  );
  exitCode = code;
}
