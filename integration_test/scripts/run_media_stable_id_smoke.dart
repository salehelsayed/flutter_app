#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

void _log(String tag, String message) {
  final timestamp = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$timestamp] [$tag] $message');
}

Future<String?> _detectIosSimulator() async {
  if (!Platform.isMacOS) {
    return null;
  }

  final result = await Process.run('xcrun', [
    'simctl',
    'list',
    'devices',
    'available',
    '--json',
  ]);
  if (result.exitCode != 0) {
    _log('ORCH', 'xcrun simctl failed: ${result.stderr}');
    return null;
  }

  final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  final devicesByRuntime =
      decoded['devices'] as Map<String, dynamic>? ?? const {};
  Map<String, dynamic>? firstAvailableIPhone;

  for (final value in devicesByRuntime.values) {
    if (value is! List<dynamic>) {
      continue;
    }
    for (final device in value.cast<Map<String, dynamic>>()) {
      final isAvailable = device['isAvailable'] == true;
      final name = device['name'] as String? ?? '';
      final state = device['state'] as String? ?? '';
      if (!isAvailable || !name.startsWith('iPhone')) {
        continue;
      }
      if (state == 'Booted') {
        return device['udid'] as String;
      }
      firstAvailableIPhone ??= device;
    }
  }

  return firstAvailableIPhone?['udid'] as String?;
}

Future<String?> _detectAndroidEmulator() async {
  final result = await Process.run('flutter', ['devices', '--machine']);
  if (result.exitCode != 0) {
    _log('ORCH', 'flutter devices failed: ${result.stderr}');
    return null;
  }

  final devices = jsonDecode(result.stdout as String) as List<dynamic>;
  for (final entry in devices.cast<Map<String, dynamic>>()) {
    final targetPlatform = entry['targetPlatform'] as String? ?? '';
    final isEmulator = entry['emulator'] as bool? ?? false;
    if (targetPlatform.startsWith('android') && isEmulator) {
      return entry['id'] as String;
    }
  }

  return null;
}

Future<String> _pickDevice(String? requestedDevice, String platform) async {
  if (requestedDevice != null && requestedDevice.isNotEmpty) {
    return requestedDevice;
  }

  final detected = platform == 'ios'
      ? await _detectIosSimulator()
      : await _detectAndroidEmulator();
  if (detected != null) {
    return detected;
  }

  throw StateError('No $platform simulator/emulator found. Start one first.');
}

Future<void> main(List<String> args) async {
  var platform = 'ios';
  String? requestedDevice;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if ((arg == '--device' || arg == '-d') && i + 1 < args.length) {
      requestedDevice = args[i + 1];
      i++;
      continue;
    }
    if ((arg == '--platform' || arg == '-p') && i + 1 < args.length) {
      platform = args[i + 1];
      i++;
    }
  }

  if (platform != 'ios' && platform != 'android') {
    throw ArgumentError(
      'Unsupported platform "$platform". Use ios or android.',
    );
  }

  final deviceId = await _pickDevice(requestedDevice, platform);
  _log('ORCH', 'Running stable-ID smoke on simulator/emulator: $deviceId');

  final relayAddresses = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  final relayDartDefines =
      relayAddresses == null || relayAddresses.trim().isEmpty
      ? const <String>[]
      : ['--dart-define=MKNOON_RELAY_ADDRESSES=${relayAddresses.trim()}'];

  final process = await Process.start('flutter', [
    'test',
    'integration_test/media_stable_id_smoke_test.dart',
    ...relayDartDefines,
    '-d',
    deviceId,
  ], mode: ProcessStartMode.inheritStdio);

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(
      'flutter',
      [
        'test',
        'integration_test/media_stable_id_smoke_test.dart',
        ...relayDartDefines,
        '-d',
        deviceId,
      ],
      'Simulator stable-ID smoke failed',
      exitCode,
    );
  }
}
