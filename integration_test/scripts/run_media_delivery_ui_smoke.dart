#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

class _DeviceTarget {
  final String name;
  final String id;
  final String platform;

  const _DeviceTarget({
    required this.name,
    required this.id,
    required this.platform,
  });

  bool get isMobile => platform == 'ios' || platform.startsWith('android');
}

void _log(String tag, String message) {
  final timestamp = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$timestamp] [$tag] $message');
}

Future<List<_DeviceTarget>> _loadFlutterDevices() async {
  final result = await Process.run('flutter', ['devices', '--machine']);
  if (result.exitCode != 0) {
    throw StateError('flutter devices failed: ${result.stderr}');
  }

  final decoded = jsonDecode(result.stdout as String) as List<dynamic>;
  return decoded
      .cast<Map<String, dynamic>>()
      .map(
        (entry) => _DeviceTarget(
          name: entry['name'] as String? ?? 'unknown',
          id: entry['id'] as String? ?? '',
          platform: entry['targetPlatform'] as String? ?? '',
        ),
      )
      .where((device) => device.id.isNotEmpty)
      .toList(growable: false);
}

Set<String>? _parseRequestedIds(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if ((arg == '--device' || arg == '-d') && i + 1 < args.length) {
      return args[i + 1]
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    }
  }
  return null;
}

String _parsePlatform(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if ((arg == '--platform' || arg == '-p') && i + 1 < args.length) {
      return args[i + 1].trim().toLowerCase();
    }
  }
  return 'all';
}

List<_DeviceTarget> _selectTargets(
  List<_DeviceTarget> devices, {
  required String platform,
  required Set<String>? requestedIds,
}) {
  final mobile = devices.where((device) => device.isMobile);
  final filteredByPlatform = switch (platform) {
    'all' => mobile,
    'ios' => mobile.where((device) => device.platform == 'ios'),
    'android' => mobile.where(
      (device) => device.platform.startsWith('android'),
    ),
    _ => throw ArgumentError(
      'Unsupported platform "$platform". Use all, ios, or android.',
    ),
  };

  if (requestedIds == null || requestedIds.isEmpty) {
    return filteredByPlatform.toList(growable: false);
  }

  return filteredByPlatform
      .where((device) => requestedIds.contains(device.id))
      .toList(growable: false);
}

Future<int> _runSmokeForDevice(_DeviceTarget device) async {
  _log(
    'RUN',
    'Starting media delivery UI smoke on ${device.name} (${device.id})',
  );
  final process = await Process.start('flutter', [
    'test',
    'integration_test/media_stable_id_smoke_test.dart',
    '-d',
    device.id,
  ], mode: ProcessStartMode.inheritStdio);
  final exitCode = await process.exitCode;
  if (exitCode == 0) {
    _log('PASS', '${device.name} (${device.id})');
  } else {
    _log('FAIL', '${device.name} (${device.id}) exit=$exitCode');
  }
  return exitCode;
}

Future<void> main(List<String> args) async {
  final requestedIds = _parseRequestedIds(args);
  final platform = _parsePlatform(args);
  final devices = await _loadFlutterDevices();
  final targets = _selectTargets(
    devices,
    platform: platform,
    requestedIds: requestedIds,
  );

  final androidVisible = devices.any(
    (device) => device.platform.startsWith('android'),
  );
  if (!androidVisible && (platform == 'all' || platform == 'android')) {
    _log(
      'INFO',
      'No Android device or emulator detected. iOS-only execution is expected for this run.',
    );
  }

  if (targets.isEmpty) {
    throw StateError(
      requestedIds == null || requestedIds.isEmpty
          ? 'No matching mobile devices found for platform=$platform.'
          : 'Requested devices were not available: ${requestedIds.join(', ')}',
    );
  }

  _log(
    'ORCH',
    'Running media delivery UI smoke on ${targets.length} device(s): '
        '${targets.map((device) => '${device.name}:${device.id}').join(', ')}',
  );

  var failures = 0;
  for (final device in targets) {
    final exitCode = await _runSmokeForDevice(device);
    if (exitCode != 0) {
      failures += 1;
    }
  }

  if (failures > 0) {
    throw ProcessException(
      'flutter',
      const <String>[
        'test',
        'integration_test/media_stable_id_smoke_test.dart',
      ],
      '$failures device run(s) failed',
      failures,
    );
  }

  _log('DONE', 'Media delivery UI smoke passed on all selected devices.');
}
