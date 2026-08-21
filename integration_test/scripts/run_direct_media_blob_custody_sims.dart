#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../support/android_direct_media_blob_custody_evidence.dart';

const String _fixtureProcessMode = 'MKNOON_DIRECT_MEDIA_DEVICE_FIXTURE_PROCESS';
const String _fixtureHostIpEnvironment =
    'MKNOON_DIRECT_MEDIA_DEVICE_FIXTURE_HOST_IP';
const String _fixtureReadyPrefix = 'MKNOON_DIRECT_MEDIA_FIXTURE_READY=';
const String _fixtureIdentityEnvironment =
    'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_IDENTITY_SHA256';
const String _fixtureProbeEnvironment =
    'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_PROBE_URL';
const String _fixtureStopExecutableEnvironment =
    'PLAN347_FIXTURE_STOP_EXECUTABLE';
const String _plan393FixedWakeFixtureMode = 'MKNOON_PLAN393_FIXED_WAKE_FIXTURE';

Future<void> main(List<String> arguments) async {
  try {
    final options = _AdapterOptions.parse(arguments);
    exitCode = await _runDirectMediaBlobCustodySimsAdapter(options);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
      'Usage: dart run '
      'integration_test/scripts/run_direct_media_blob_custody_sims.dart '
      '--mode major --scenario $androidDirectMediaBlobCustodyScenarioId',
    );
    exitCode = 64;
  } on Object catch (error, stackTrace) {
    stderr.writeln('Direct-media custody Sims adapter failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

Future<int> _runDirectMediaBlobCustodySimsAdapter(
  _AdapterOptions options,
) async {
  final environment = Platform.environment;
  final devices = _explicitAndroidPair(environment);
  final hostIp = await _resolveReachableHostIp(environment);
  final fixture = await _FixtureSession.start(
    goExecutable:
        environment['PLAN347_GO_EXECUTABLE']?.trim().isNotEmpty == true
        ? environment['PLAN347_GO_EXECUTABLE']!.trim()
        : 'go',
    hostIp: hostIp,
    environment: environment,
  );

  var result = 1;
  Object? teardownFailure;
  try {
    await _verifyAndroidTopologyAndReachability(
      adbExecutable:
          environment['PLAN347_ADB_EXECUTABLE']?.trim().isNotEmpty == true
          ? environment['PLAN347_ADB_EXECUTABLE']!.trim()
          : 'adb',
      devices: devices,
      host: fixture.host,
      port: fixture.port,
    );

    final centralEnvironment = <String, String>{
      ...environment,
      'RELIABILITY_MULTI_DEVICE_IDS': devices.join(','),
      'SIMS_ANDROID_PHYSICAL_DEVICE_ID': devices.first,
      'SIMS_ANDROID_EMULATOR_DEVICE_ID': devices.last,
      'MKNOON_RELAY_ADDRESSES': fixture.multiaddr,
      _fixtureIdentityEnvironment: fixture.fixtureIdentitySha256,
      _fixtureProbeEnvironment: fixture.probeUrl,
    };
    final dartExecutable =
        environment['PLAN347_SIMS_DART_EXECUTABLE']?.trim().isNotEmpty == true
        ? environment['PLAN347_SIMS_DART_EXECUTABLE']!.trim()
        : Platform.resolvedExecutable;

    final prepare = await _runCentralSims(
      dartExecutable: dartExecutable,
      arguments: <String>[
        'run',
        'tool/sims/sims.dart',
        options.mode,
        '--only',
        androidDirectMediaBlobCustodyScenarioId,
        '--prepare-builds',
      ],
      environment: centralEnvironment,
    );
    if (prepare != 0) {
      result = prepare;
    } else {
      result = await _runCentralSims(
        dartExecutable: dartExecutable,
        arguments: <String>[
          'run',
          'tool/sims/sims.dart',
          options.mode,
          '--only',
          androidDirectMediaBlobCustodyScenarioId,
        ],
        environment: centralEnvironment,
      );
    }
  } finally {
    try {
      await fixture.stop();
    } on Object catch (error) {
      teardownFailure = error;
    }
  }
  if (teardownFailure != null) {
    stderr.writeln('Disposable relay teardown failed: $teardownFailure');
    return 1;
  }
  return result;
}

final class _AdapterOptions {
  const _AdapterOptions({required this.mode});

  factory _AdapterOptions.parse(List<String> arguments) {
    String? mode;
    String? scenario;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (argument == '--mode' && index + 1 < arguments.length) {
        mode = arguments[++index].trim();
      } else if (argument.startsWith('--mode=')) {
        mode = argument.substring('--mode='.length).trim();
      } else if (argument == '--scenario' && index + 1 < arguments.length) {
        scenario = arguments[++index].trim();
      } else if (argument.startsWith('--scenario=')) {
        scenario = argument.substring('--scenario='.length).trim();
      } else {
        throw FormatException('Unknown adapter argument: $argument');
      }
    }
    if (mode != 'major' && mode != 'full') {
      throw const FormatException('--mode must be major or full');
    }
    if (scenario != androidDirectMediaBlobCustodyScenarioId) {
      throw FormatException(
        '--scenario must be $androidDirectMediaBlobCustodyScenarioId',
      );
    }
    return _AdapterOptions(mode: mode!);
  }

  final String mode;
}

List<String> _explicitAndroidPair(Map<String, String> environment) {
  final devices = (environment['RELIABILITY_MULTI_DEVICE_IDS'] ?? '')
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (devices.length != 2 || devices.first == devices.last) {
    throw const FormatException(
      'RELIABILITY_MULTI_DEVICE_IDS must name one physical Android followed '
      'by one distinct Android emulator',
    );
  }
  return devices;
}

Future<String> _resolveReachableHostIp(Map<String, String> environment) async {
  final configured = environment['PLAN347_FIXTURE_HOST_IP']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final parsed = InternetAddress.tryParse(configured);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
      throw const FormatException('PLAN347_FIXTURE_HOST_IP must be IPv4');
    }
    return parsed.address;
  }
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (!address.isLoopback && !address.isLinkLocal) return address.address;
    }
  }
  throw const FormatException(
    'No non-loopback IPv4 address is available for the disposable relay',
  );
}

/// Shared Plan-347 fixture host resolution for registered device-pair proofs.
///
/// The aggregate Plan-362 scenario deliberately leases this exact disposable
/// relay instead of growing a second fixture owner.
Future<String> resolveDirectMediaBlobCustodyFixtureHostIp(
  Map<String, String> environment,
) => _resolveReachableHostIp(environment);

Future<void> _verifyAndroidTopologyAndReachability({
  required String adbExecutable,
  required List<String> devices,
  required String host,
  required int port,
}) async {
  final qemuValues = <String>[];
  for (final device in devices) {
    final result = await Process.run(adbExecutable, <String>[
      '-s',
      device,
      'shell',
      'getprop',
      'ro.kernel.qemu',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Unable to classify Android target $device');
    }
    qemuValues.add('${result.stdout}'.trim());
  }
  if (qemuValues.first == '1' || qemuValues.last != '1') {
    throw StateError(
      'Target order must be physical Android then Android emulator',
    );
  }

  for (final device in devices) {
    final probe = await Process.run(adbExecutable, <String>[
      '-s',
      device,
      'shell',
      'toybox',
      'nc',
      '-z',
      '-w',
      '5',
      host,
      '$port',
    ]);
    if (probe.exitCode != 0) {
      throw StateError(
        'Disposable relay $host:$port is unreachable from Android target '
        '$device',
      );
    }
  }
}

/// Proves the selected targets are a physical-Android/emulator pair and that
/// both can reach the leased disposable relay before either APK is built.
Future<void> verifyDirectMediaBlobCustodyAndroidTopologyAndReachability({
  required String adbExecutable,
  required List<String> devices,
  required String host,
  required int port,
}) => _verifyAndroidTopologyAndReachability(
  adbExecutable: adbExecutable,
  devices: devices,
  host: host,
  port: port,
);

Future<int> _runCentralSims({
  required String dartExecutable,
  required List<String> arguments,
  required Map<String, String> environment,
}) async {
  final result = await Process.run(
    dartExecutable,
    arguments,
    workingDirectory: Directory.current.path,
    environment: environment,
  );
  final output = '${result.stdout}';
  final errors = '${result.stderr}';
  if (output.isNotEmpty) stdout.write(output);
  if (errors.isNotEmpty) stderr.write(errors);
  return result.exitCode;
}

final class _FixtureSession {
  _FixtureSession._({
    required this.process,
    required this.multiaddr,
    required this.host,
    required this.port,
    required this.fixtureIdentitySha256,
    required this.probeUrl,
    required this.fixedWakeRecovery,
    required this.relayVersion,
    required this.relayBinarySha256,
    required this.stopExecutable,
    required StreamSubscription<String> stdoutSubscription,
    required StreamSubscription<String> stderrSubscription,
  }) : _stdoutSubscription = stdoutSubscription,
       _stderrSubscription = stderrSubscription;

  static Future<_FixtureSession> start({
    required String goExecutable,
    required String hostIp,
    required Map<String, String> environment,
    bool fixedWakeRecovery = false,
  }) async {
    final process = await Process.start(
      goExecutable,
      const <String>[
        'test',
        '-tags',
        'integration',
        '.',
        '-run',
        r'^TestDirectMediaBlobCustodyDeviceFixtureContract$',
        '-count=1',
        '-v',
        '-timeout=45m',
      ],
      workingDirectory: 'go-relay-server',
      environment: <String, String>{
        ...environment,
        _fixtureProcessMode: '1',
        _fixtureHostIpEnvironment: hostIp,
        'DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED': 'true',
        'DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED': 'true',
        if (fixedWakeRecovery) _plan393FixedWakeFixtureMode: '1',
      },
    );
    final ready = Completer<Map<String, Object?>>();
    late final StreamSubscription<String> stdoutSubscription;
    stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final marker = line.indexOf(_fixtureReadyPrefix);
          if (marker < 0) {
            stderr.writeln('[plan347-fixture] $line');
            return;
          }
          if (ready.isCompleted) return;
          try {
            final decoded = jsonDecode(
              line.substring(marker + _fixtureReadyPrefix.length),
            );
            if (decoded is! Map) {
              throw const FormatException('fixture readiness is not an object');
            }
            ready.complete(
              decoded.map<String, Object?>(
                (key, value) => MapEntry('$key', value),
              ),
            );
          } on Object catch (error, stackTrace) {
            ready.completeError(error, stackTrace);
          }
        });
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => stderr.writeln('[plan347-fixture] $line'));
    unawaited(
      process.exitCode.then((code) {
        if (!ready.isCompleted) {
          ready.completeError(
            StateError('Disposable relay exited $code before readiness'),
          );
        }
      }),
    );

    late final Map<String, Object?> payload;
    late final ({
      String multiaddr,
      String host,
      int port,
      String fixtureIdentitySha256,
      String probeUrl,
      bool fixedWakeRecovery,
      String relayVersion,
      String relayBinarySha256,
    })
    parsed;
    try {
      payload = await ready.future.timeout(const Duration(minutes: 5));
      parsed = _validateFixtureReadiness(
        payload,
        expectedHost: hostIp,
        requireFixedWakeRecovery: fixedWakeRecovery,
      );
    } on Object {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 10));
      } on Object {
        process.kill(ProcessSignal.sigkill);
      }
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      rethrow;
    }
    return _FixtureSession._(
      process: process,
      multiaddr: parsed.multiaddr,
      host: parsed.host,
      port: parsed.port,
      fixtureIdentitySha256: parsed.fixtureIdentitySha256,
      probeUrl: parsed.probeUrl,
      fixedWakeRecovery: parsed.fixedWakeRecovery,
      relayVersion: parsed.relayVersion,
      relayBinarySha256: parsed.relayBinarySha256,
      stopExecutable:
          environment[_fixtureStopExecutableEnvironment]?.trim().isNotEmpty ==
              true
          ? environment[_fixtureStopExecutableEnvironment]!.trim()
          : null,
      stdoutSubscription: stdoutSubscription,
      stderrSubscription: stderrSubscription,
    );
  }

  final Process process;
  final String multiaddr;
  final String host;
  final int port;
  final String fixtureIdentitySha256;
  final String probeUrl;
  final bool fixedWakeRecovery;
  final String relayVersion;
  final String relayBinarySha256;
  final String? stopExecutable;
  final StreamSubscription<String> _stdoutSubscription;
  final StreamSubscription<String> _stderrSubscription;
  bool _stopped = false;

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _requestStop();
    } on Object catch (error) {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 10));
      } on Object {
        process.kill(ProcessSignal.sigkill);
      }
      await _stdoutSubscription.cancel();
      await _stderrSubscription.cancel();
      throw StateError('Disposable relay stop request failed: $error');
    }
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 20));
      if (code != 0) {
        throw StateError('Disposable relay exited $code during teardown');
      }
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      final code = await process.exitCode.timeout(const Duration(seconds: 10));
      if (code != 0) {
        throw StateError(
          'Disposable relay required termination and exited $code',
        );
      }
    } finally {
      await _stdoutSubscription.cancel();
      await _stderrSubscription.cancel();
    }
  }

  Future<void> _requestStop() async {
    final injectedExecutable = stopExecutable;
    if (injectedExecutable != null) {
      final result = await Process.run(injectedExecutable, <String>[
        probeUrl,
      ]).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) {
        throw StateError(
          'Injected fixture stop exited ${result.exitCode}: ${result.stderr}',
        );
      }
      return;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .postUrl(Uri.parse(probeUrl))
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final statusCode = response.statusCode;
      await response.drain<void>().timeout(const Duration(seconds: 5));
      if (statusCode != HttpStatus.noContent) {
        throw StateError('Disposable relay stop returned HTTP $statusCode');
      }
    } finally {
      client.close(force: true);
    }
  }
}

/// Public lease over the one Plan-347 disposable relay fixture owner.
///
/// Keeping [_FixtureSession] private preserves its existing adapter contract;
/// this bounded wrapper lets another registered scenario reuse the same
/// readiness validation and exact teardown path without copying it.
final class DirectMediaBlobCustodyFixtureLease {
  DirectMediaBlobCustodyFixtureLease._(this._session);

  static Future<DirectMediaBlobCustodyFixtureLease> start({
    required String goExecutable,
    required String hostIp,
    required Map<String, String> environment,
    bool fixedWakeRecovery = false,
  }) async => DirectMediaBlobCustodyFixtureLease._(
    await _FixtureSession.start(
      goExecutable: goExecutable,
      hostIp: hostIp,
      environment: environment,
      fixedWakeRecovery: fixedWakeRecovery,
    ),
  );

  final _FixtureSession _session;

  String get multiaddr => _session.multiaddr;
  String get host => _session.host;
  int get port => _session.port;
  String get fixtureIdentitySha256 => _session.fixtureIdentitySha256;
  String get probeUrl => _session.probeUrl;
  bool get fixedWakeRecovery => _session.fixedWakeRecovery;
  String get relayVersion => _session.relayVersion;
  String get relayBinarySha256 => _session.relayBinarySha256;

  Future<void> stop() => _session.stop();
}

({
  String multiaddr,
  String host,
  int port,
  String fixtureIdentitySha256,
  String probeUrl,
  bool fixedWakeRecovery,
  String relayVersion,
  String relayBinarySha256,
})
_validateFixtureReadiness(
  Map<String, Object?> payload, {
  required String expectedHost,
  bool requireFixedWakeRecovery = false,
}) {
  final multiaddr = payload['multiaddr'];
  final fixtureIdentitySha256 = payload['fixtureIdentitySha256'];
  final probeUrl = payload['probeUrl'];
  final fixedWakeRecovery = payload['fixedWakeRecovery'];
  final relayVersion = payload['relayVersion'];
  final relayBinarySha256 = payload['relayBinarySha256'];
  if (payload['schema'] != 'mknoon.plan347.direct-media-fixture.v1' ||
      payload['backend'] != 'redis' ||
      payload['ephemeral'] != true ||
      payload['ackCustodyAdmissionEnabled'] != true ||
      payload['mediaCustodyAdmissionEnabled'] != true ||
      multiaddr is! String ||
      probeUrl is! String ||
      fixtureIdentitySha256 is! String ||
      fixedWakeRecovery is! bool ||
      relayVersion is! String ||
      relayBinarySha256 is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(relayBinarySha256) ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(fixtureIdentitySha256)) {
    throw const FormatException(
      'Disposable relay readiness omitted its backend/admission attestation',
    );
  }
  if (requireFixedWakeRecovery &&
      (fixedWakeRecovery != true ||
          payload['pushTokenState'] != 'encrypted' ||
          payload['wakeOutcomeAdmissionEnabled'] != true ||
          payload['wakeOutcomeCoordinatorStarted'] != true ||
          payload['directReactionPushEnabled'] != true ||
          payload['realFcmConfigured'] != true)) {
    throw const FormatException(
      'Disposable relay omitted the Plan 393 encrypted fixed-wake attestation',
    );
  }
  final match = RegExp(
    r'^/ip4/([^/]+)/tcp/([1-9][0-9]*)/p2p/[A-Za-z0-9]+$',
  ).firstMatch(multiaddr);
  final port = match == null ? null : int.tryParse(match.group(2)!);
  if (match == null || match.group(1) != expectedHost || port == null) {
    throw const FormatException(
      'Disposable relay did not announce the exact reachable host address',
    );
  }
  final parsedProbe = Uri.tryParse(probeUrl);
  if (parsedProbe == null ||
      parsedProbe.scheme != 'http' ||
      parsedProbe.host != expectedHost ||
      parsedProbe.port <= 0 ||
      !RegExp(r'^/[0-9a-f]{64}$').hasMatch(parsedProbe.path) ||
      parsedProbe.hasQuery ||
      parsedProbe.hasFragment) {
    throw const FormatException(
      'Disposable relay did not announce an exact capability-bound probe',
    );
  }
  return (
    multiaddr: multiaddr,
    host: match.group(1)!,
    port: port,
    fixtureIdentitySha256: fixtureIdentitySha256,
    probeUrl: probeUrl,
    fixedWakeRecovery: fixedWakeRecovery,
    relayVersion: relayVersion,
    relayBinarySha256: relayBinarySha256,
  );
}
