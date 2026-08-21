#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'android_notification_recovery_completion_criteria.dart';
import 'run_direct_media_blob_custody_sims.dart';

const String _fixtureProbeEnvironment = 'PLAN393_RELAY_FIXTURE_PROBE_URL';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length == 1 &&
        arguments.single == '--probe-source-extension') {
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'scenario': androidNotificationRecoveryCompletionCapabilityId,
          'executionBoundary': 'ephemeral_production_redis_fixture',
          'pushTokenState': 'encrypted',
          'wakeOutcomeLedger': 'redis',
          'provider': 'fcm',
          'centralPreparation': true,
        }),
      );
      return;
    }
    final options = _Options.parse(arguments);
    exitCode = await _run(options, Platform.environment);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
      'Usage: dart run integration_test/scripts/'
      'run_android_notification_recovery_completion_sims.dart '
      '--mode major --scenario '
      '$androidNotificationRecoveryCompletionCapabilityId',
    );
    exitCode = 64;
  } on Object catch (error, stackTrace) {
    stderr.writeln('Plan 393 recovery Sims wrapper failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

final class _Options {
  const _Options({required this.mode});

  factory _Options.parse(List<String> arguments) {
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
        throw FormatException('Unknown wrapper argument: $argument');
      }
    }
    if (mode != 'major' && mode != 'full') {
      throw const FormatException('--mode must be major or full');
    }
    if (scenario != androidNotificationRecoveryCompletionCapabilityId) {
      throw FormatException(
        '--scenario must be '
        '$androidNotificationRecoveryCompletionCapabilityId',
      );
    }
    return _Options(mode: mode!);
  }

  final String mode;
}

Future<int> _run(_Options options, Map<String, String> environment) async {
  final physical = environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID']?.trim() ?? '';
  final emulator = environment['SIMS_ANDROID_EMULATOR_DEVICE_ID']?.trim() ?? '';
  if (physical.isEmpty || emulator.isEmpty || physical == emulator) {
    throw const FormatException(
      'SIMS_ANDROID_PHYSICAL_DEVICE_ID and '
      'SIMS_ANDROID_EMULATOR_DEVICE_ID must name a distinct Android pair',
    );
  }
  final devices = <String>[physical, emulator];
  final credentialPath =
      environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']?.trim().isNotEmpty ==
          true
      ? environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']!.trim()
      : environment['FIREBASE_SERVICE_ACCOUNT']?.trim() ?? '';
  final credential = File(credentialPath).absolute;
  if (!_serviceAccount(credential)) {
    throw const FormatException(
      'A regular FCM service-account credential is required',
    );
  }

  final requestedReport = File(
    environment['SIMS_REPORT_PATH']?.trim().isNotEmpty == true
        ? environment['SIMS_REPORT_PATH']!.trim()
        : 'build/sims/plan393-recovery-report.json',
  ).absolute;
  requestedReport.parent.createSync(recursive: true);
  final sessionRoot = Directory(
    '${requestedReport.parent.path}${Platform.pathSeparator}'
    '.plan393-recovery-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid',
  )..createSync();
  final stagedReport = File(
    '${sessionRoot.path}${Platform.pathSeparator}report.json',
  );
  final manifest = File(
    '${sessionRoot.path}${Platform.pathSeparator}staging-manifest.json',
  );

  DirectMediaBlobCustodyFixtureLease? fixture;
  var result = 1;
  Object? teardownFailure;
  try {
    final hostIp = await resolveDirectMediaBlobCustodyFixtureHostIp(
      environment,
    );
    fixture = await DirectMediaBlobCustodyFixtureLease.start(
      goExecutable:
          environment['PLAN393_GO_EXECUTABLE']?.trim().isNotEmpty == true
          ? environment['PLAN393_GO_EXECUTABLE']!.trim()
          : 'go',
      hostIp: hostIp,
      environment: <String, String>{
        ...environment,
        'SIMS_PROVIDER_FCM_CREDENTIAL_PATH': credential.path,
      },
      fixedWakeRecovery: true,
    );
    if (!fixture.fixedWakeRecovery) {
      throw StateError('Disposable relay did not enter fixed-wake mode');
    }
    await verifyDirectMediaBlobCustodyAndroidTopologyAndReachability(
      adbExecutable:
          environment['PLAN393_ADB_EXECUTABLE']?.trim().isNotEmpty == true
          ? environment['PLAN393_ADB_EXECUTABLE']!.trim()
          : 'adb',
      devices: devices,
      host: fixture.host,
      port: fixture.port,
    );
    manifest.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schema': 'mknoon.plan257.staging-prerequisites.v1',
        'version': 1,
        'environment': 'staging',
        'relayActive': true,
        'providerConfigured': true,
        'providerProbeSucceeded': true,
        'productionDeploymentPerformed': false,
        'allowAppDataReset': true,
        'candidateRelayRevision': fixture.relayVersion,
        'candidateRelaySha256': fixture.relayBinarySha256,
        'provider': 'fcm',
        'relayAddresses': <String>[fixture.multiaddr],
        'executionBoundary': 'ephemeral_production_redis_fixture',
        'pushTokenState': 'encrypted',
        'wakeOutcomeLedger': 'redis',
      })}\n',
      flush: true,
    );

    final centralEnvironment =
        <String, String>{
            ...environment,
            'RELIABILITY_MULTI_DEVICE_IDS': devices.join(','),
            'SIMS_ANDROID_PHYSICAL_DEVICE_ID': physical,
            'SIMS_ANDROID_EMULATOR_DEVICE_ID': emulator,
            'SIMS_PROVIDER_FCM_CREDENTIAL_PATH': credential.path,
            'FIREBASE_SERVICE_ACCOUNT': credential.path,
            'MKNOON_RELAY_ADDRESSES': fixture.multiaddr,
            'MKNOON_257_STAGING_MANIFEST': manifest.path,
            _fixtureProbeEnvironment: fixture.probeUrl,
            'SIMS_REPORT_PATH': stagedReport.path,
          }
          ..remove('SIMS_NOTIFICATION_RELAY_TARGET')
          ..remove('SIMS_NOTIFICATION_RELAY_KEY')
          ..remove('MKNOON_257_RELAY_TARGET')
          ..remove('MKNOON_257_RELAY_KEY');
    final dartExecutable =
        environment['PLAN393_SIMS_DART_EXECUTABLE']?.trim().isNotEmpty == true
        ? environment['PLAN393_SIMS_DART_EXECUTABLE']!.trim()
        : Platform.resolvedExecutable;

    final prepare = await _runCentralSims(
      dartExecutable: dartExecutable,
      arguments: <String>[
        'run',
        'tool/sims/sims.dart',
        options.mode,
        '--only',
        androidNotificationRecoveryCompletionCapabilityId,
        '--prepare-builds',
      ],
      environment: centralEnvironment,
    );
    result = prepare == 0
        ? await _runCentralSims(
            dartExecutable: dartExecutable,
            arguments: <String>[
              'run',
              'tool/sims/sims.dart',
              options.mode,
              '--only',
              androidNotificationRecoveryCompletionCapabilityId,
            ],
            environment: centralEnvironment,
          )
        : prepare;
  } finally {
    if (fixture != null) {
      try {
        await fixture.stop();
      } on Object catch (error) {
        teardownFailure = error;
      }
    }
  }

  if (teardownFailure != null) {
    stderr.writeln('Disposable relay teardown failed: $teardownFailure');
    result = 1;
  }
  if (stagedReport.existsSync()) {
    stagedReport.copySync(requestedReport.path);
  } else if (result == 0) {
    stderr.writeln('Central Sims completed without its staged report.');
    result = 1;
  }
  if (sessionRoot.existsSync()) {
    sessionRoot.deleteSync(recursive: true);
  }
  return result;
}

Future<int> _runCentralSims({
  required String dartExecutable,
  required List<String> arguments,
  required Map<String, String> environment,
}) async {
  final process = await Process.start(
    dartExecutable,
    arguments,
    workingDirectory: Directory.current.path,
    environment: environment,
    includeParentEnvironment: true,
  );
  final output = process.stdout.listen(stdout.add).asFuture<void>();
  final errors = process.stderr.listen(stderr.add).asFuture<void>();
  final code = await process.exitCode;
  await Future.wait<void>(<Future<void>>[output, errors]);
  return code;
}

bool _serviceAccount(File file) {
  if (FileSystemEntity.typeSync(file.path, followLinks: true) !=
      FileSystemEntityType.file) {
    return false;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map &&
        decoded['type'] == 'service_account' &&
        '${decoded['project_id'] ?? ''}'.trim().isNotEmpty;
  } on Object {
    return false;
  }
}
