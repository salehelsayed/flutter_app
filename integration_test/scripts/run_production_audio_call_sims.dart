#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../support/android_production_audio_call_evidence.dart';
import 'android_production_audio_call_campaign.dart';
import 'production_audio_call_local_fixture.dart';

const String _turnUrlsEnvironment = 'TURN_CREDENTIAL_URLS';
const String _turnSecretEnvironment = 'TURN_CREDENTIAL_PRIMARY_SECRET_B64';
const String _fixtureIdentityEnvironment =
    'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_IDENTITY_SHA256';
const String _turnAuthorityDigestEnvironment =
    'PLAN399_LOCAL_TURN_AUTHORITY_SHA256';
const String _coturnInstanceDigestEnvironment =
    'PLAN399_LOCAL_COTURN_INSTANCE_SHA256';
const String androidProductionAudioCallGoToolchain = 'go1.25.0';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length == 1 &&
        arguments.single == '--probe-source-extension') {
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'scenario': androidProductionAudioCallScenarioId,
          'executionBoundary': 'ephemeral_production_relay_coturn_fixture',
          'coturn': 'digest-pinned',
          'mediaOracle': 'pion-known-opus',
          'centralPreparation': true,
          'goToolchain': androidProductionAudioCallGoToolchain,
        }),
      );
      return;
    }
    final options = _ProductionAudioCallAdapterOptions.parse(arguments);
    exitCode = await runAndroidProductionAudioCallSimsAdapter(
      mode: options.mode,
      environment: Platform.environment,
      dependencies: AndroidProductionAudioCallSimsAdapterDependencies.system(),
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
      'Usage: dart run '
      'integration_test/scripts/run_production_audio_call_sims.dart '
      '--mode major --scenario $androidProductionAudioCallScenarioId',
    );
    exitCode = 64;
  } on Object catch (error, stackTrace) {
    stderr.writeln('Production audio-call Sims adapter failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

typedef AndroidProductionAudioCallFixtureHostResolver =
    Future<String> Function(Map<String, String> environment);
typedef AndroidProductionAudioCallFixtureStarter =
    Future<AndroidProductionAudioCallFixtureLease> Function({
      required String goExecutable,
      required String hostIp,
      required Map<String, String> environment,
    });
typedef AndroidProductionAudioCallCentralSimsRunner =
    Future<int> Function({
      required String dartExecutable,
      required List<String> arguments,
      required Map<String, String> environment,
    });

final class AndroidProductionAudioCallFixtureLease {
  AndroidProductionAudioCallFixtureLease({
    required this.multiaddr,
    required this.fixtureIdentitySha256,
    required this.turnAuthoritySha256,
    required this.coturnInstanceIdentitySha256,
    required Map<String, Object?> pionOracleResult,
    required Future<void> Function() stop,
  }) : pionOracleResult = Map<String, Object?>.unmodifiable(pionOracleResult),
       _stop = stop;

  final String multiaddr;
  final String fixtureIdentitySha256;
  final String turnAuthoritySha256;
  final String coturnInstanceIdentitySha256;
  final Map<String, Object?> pionOracleResult;
  final Future<void> Function() _stop;

  Future<void> stop() => _stop();
}

final class AndroidProductionAudioCallSimsAdapterDependencies {
  const AndroidProductionAudioCallSimsAdapterDependencies({
    required this.resolveFixtureHostIp,
    required this.startFixture,
    required this.runCentralSims,
  });

  factory AndroidProductionAudioCallSimsAdapterDependencies.system() =>
      AndroidProductionAudioCallSimsAdapterDependencies(
        resolveFixtureHostIp: resolveProductionAudioCallLocalFixtureHostIp,
        startFixture:
            ({
              required String goExecutable,
              required String hostIp,
              required Map<String, String> environment,
            }) async {
              _requirePinnedGoToolchain(environment);
              final devices = _explicitAndroidPair(environment);
              final fixture = await ProductionAudioCallLocalFixtureLease.start(
                goExecutable: goExecutable,
                hostIp: hostIp,
                environment: environment,
              );
              try {
                await fixture.verifyAndroidPairAndReachability(
                  adbExecutable:
                      environment['PLAN399_ADB_EXECUTABLE']
                              ?.trim()
                              .isNotEmpty ==
                          true
                      ? environment['PLAN399_ADB_EXECUTABLE']!.trim()
                      : 'adb',
                  devices: devices,
                );
                final oracle = await fixture.runAudioOracle(
                  goExecutable: goExecutable,
                );
                final oracleResult = oracle.toSanitizedJson();
                AndroidProductionAudioCallPionOracleEvidence.fromResult(
                  oracleResult,
                );
                return AndroidProductionAudioCallFixtureLease(
                  multiaddr: fixture.multiaddr,
                  fixtureIdentitySha256: fixture.fixtureIdentitySha256,
                  turnAuthoritySha256: sha256
                      .convert(utf8.encode(fixture.turnUrl))
                      .toString(),
                  coturnInstanceIdentitySha256:
                      fixture.coturnContainerIdentitySha256,
                  pionOracleResult: oracleResult,
                  stop: fixture.stop,
                );
              } on Object catch (error, stackTrace) {
                try {
                  await fixture.stop();
                } on Object catch (cleanupError) {
                  Error.throwWithStackTrace(
                    StateError(
                      'Production fixture setup failed and cleanup failed: '
                      '$cleanupError',
                    ),
                    stackTrace,
                  );
                }
                Error.throwWithStackTrace(error, stackTrace);
              }
            },
        runCentralSims: _runCentralSims,
      );

  final AndroidProductionAudioCallFixtureHostResolver resolveFixtureHostIp;
  final AndroidProductionAudioCallFixtureStarter startFixture;
  final AndroidProductionAudioCallCentralSimsRunner runCentralSims;
}

/// Runs the production-call adapter through injectable process boundaries.
/// Both boundaries receive the exact Go 1.25.0 pin in their effective child
/// environment, including the central Sims process that owns APK build work.
Future<int> runAndroidProductionAudioCallSimsAdapter({
  required String mode,
  required Map<String, String> environment,
  required AndroidProductionAudioCallSimsAdapterDependencies dependencies,
}) async {
  if (mode != 'major' && mode != 'full') {
    throw const FormatException('Production audio-call mode is invalid.');
  }
  final devices = _explicitAndroidPair(environment);
  final hostIp = await dependencies.resolveFixtureHostIp(environment);
  final goEnvironment =
      <String, String>{
          ...environment,
          'GOTOOLCHAIN': androidProductionAudioCallGoToolchain,
        }
        ..remove('TURN_CREDENTIALS_ENABLED')
        ..remove(_turnUrlsEnvironment)
        ..remove(_turnSecretEnvironment)
        ..remove('TURN_CREDENTIAL_VERIFICATION_SECRETS_B64');
  final fixture = await dependencies.startFixture(
    goExecutable:
        environment['PLAN399_GO_EXECUTABLE']?.trim().isNotEmpty == true
        ? environment['PLAN399_GO_EXECUTABLE']!.trim()
        : 'go',
    hostIp: hostIp,
    environment: goEnvironment,
  );

  var result = 1;
  Object? teardownFailure;
  try {
    if (!_isSha256(fixture.fixtureIdentitySha256) ||
        !_isSha256(fixture.turnAuthoritySha256) ||
        !_isSha256(fixture.coturnInstanceIdentitySha256)) {
      throw const FormatException(
        'Combined production-call fixture hashes are not canonical.',
      );
    }
    final oracle = AndroidProductionAudioCallPionOracleEvidence.fromResult(
      fixture.pionOracleResult,
    );
    if (oracle.turnAuthoritySha256 != fixture.turnAuthoritySha256 ||
        oracle.fixtureInstanceSha256 != fixture.coturnInstanceIdentitySha256) {
      throw const FormatException(
        'Pion oracle attestation belongs to another coturn fixture instance.',
      );
    }
    final centralEnvironment = <String, String>{
      ...environment,
      'GOTOOLCHAIN': androidProductionAudioCallGoToolchain,
      'RELIABILITY_MULTI_DEVICE_IDS': devices.join(','),
      'SIMS_ANDROID_PHYSICAL_DEVICE_ID': devices.first,
      'SIMS_ANDROID_EMULATOR_DEVICE_ID': devices.last,
      'MKNOON_RELAY_ADDRESSES': fixture.multiaddr,
      _fixtureIdentityEnvironment: fixture.fixtureIdentitySha256,
      _turnAuthorityDigestEnvironment: fixture.turnAuthoritySha256,
      _coturnInstanceDigestEnvironment: fixture.coturnInstanceIdentitySha256,
      androidProductionAudioCallPionOracleEnvironment: base64Encode(
        utf8.encode(jsonEncode(fixture.pionOracleResult)),
      ),
    };
    // TURN authority material belongs only to the disposable relay child. It
    // must not reach Flutter build, the application process, or Sims logs.
    centralEnvironment
      ..remove('TURN_CREDENTIALS_ENABLED')
      ..remove(_turnUrlsEnvironment)
      ..remove(_turnSecretEnvironment)
      ..remove('TURN_CREDENTIAL_VERIFICATION_SECRETS_B64');
    final dartExecutable =
        environment['PLAN399_SIMS_DART_EXECUTABLE']?.trim().isNotEmpty == true
        ? environment['PLAN399_SIMS_DART_EXECUTABLE']!.trim()
        : Platform.resolvedExecutable;
    final prepare = await dependencies.runCentralSims(
      dartExecutable: dartExecutable,
      arguments: <String>[
        'run',
        'tool/sims/sims.dart',
        mode,
        '--only',
        androidProductionAudioCallScenarioId,
        '--prepare-builds',
      ],
      environment: centralEnvironment,
    );
    result = prepare == 0
        ? await dependencies.runCentralSims(
            dartExecutable: dartExecutable,
            arguments: <String>[
              'run',
              'tool/sims/sims.dart',
              mode,
              '--only',
              androidProductionAudioCallScenarioId,
            ],
            environment: centralEnvironment,
          )
        : prepare;
  } finally {
    try {
      await fixture.stop();
    } on Object catch (error) {
      teardownFailure = error;
    }
  }
  if (teardownFailure != null) {
    stderr.writeln('Disposable production-call fixture teardown failed.');
    return 1;
  }
  return result;
}

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

Future<int> _runCentralSims({
  required String dartExecutable,
  required List<String> arguments,
  required Map<String, String> environment,
}) async {
  _requirePinnedGoToolchain(environment);
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

void _requirePinnedGoToolchain(Map<String, String> environment) {
  if (environment['GOTOOLCHAIN'] != androidProductionAudioCallGoToolchain) {
    throw StateError(
      'Every production audio-call child requires GOTOOLCHAIN=go1.25.0.',
    );
  }
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
      'by one distinct Android emulator.',
    );
  }
  return devices;
}

final class _ProductionAudioCallAdapterOptions {
  const _ProductionAudioCallAdapterOptions({required this.mode});

  factory _ProductionAudioCallAdapterOptions.parse(List<String> arguments) {
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
      throw const FormatException('--mode must be major or full.');
    }
    if (scenario != androidProductionAudioCallScenarioId) {
      throw FormatException(
        '--scenario must be $androidProductionAudioCallScenarioId.',
      );
    }
    return _ProductionAudioCallAdapterOptions(mode: mode!);
  }

  final String mode;
}
