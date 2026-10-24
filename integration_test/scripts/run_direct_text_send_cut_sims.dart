import 'dart:io';

import '../../tool/sims/production_direct_send_cut_criteria.dart';
import '../support/direct_text_checkpoint_client.dart';
import 'run_direct_media_blob_custody_sims.dart';

/// Reuses the existing ephemeral Redis fixture owner and central build path.
/// The manifest owns the inner device scenario; this wrapper starts the exact
/// relay before preparing its source-bound APK, then tears down only that lease.
Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.writeln(productionDirectSendCut);
    return;
  }
  if (arguments.length != 4 ||
      arguments[0] != '--mode' ||
      !['major', 'full'].contains(arguments[1]) ||
      arguments[2] != '--scenario' ||
      arguments[3] != productionDirectSendCut) {
    stderr.writeln(
      'An exact direct-text cut scenario and major/full mode are required.',
    );
    exitCode = 64;
    return;
  }
  var result = 1;
  DirectMediaBlobCustodyFixtureLease? fixture;
  try {
    final environment = Platform.environment;
    final first = environment['SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID'] ?? '';
    final second = environment['SIMS_ANDROID_EMULATOR_DEVICE_ID'] ?? '';
    if (environment['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] != '1' ||
        !RegExp(r'^emulator-[0-9]+$').hasMatch(first) ||
        !RegExp(r'^emulator-[0-9]+$').hasMatch(second) ||
        first == second) {
      throw StateError(
        'two distinct explicit disposable emulator roles required',
      );
    }
    final goEnvironment = <String, String>{
      ...environment,
      'GOMAXPROCS': '4',
      'GOFLAGS': '${environment['GOFLAGS'] ?? ''} -p=4'.trim(),
      'MKNOON_DIRECT_TEXT_SEND_CHECKPOINT': '1',
    };
    fixture = await DirectMediaBlobCustodyFixtureLease.start(
      goExecutable:
          environment['PLAN347_GO_EXECUTABLE']?.trim().isNotEmpty == true
          ? environment['PLAN347_GO_EXECUTABLE']!.trim()
          : 'go',
      hostIp: await resolveDirectMediaBlobCustodyFixtureHostIp(environment),
      environment: goEnvironment,
    );
    // Uses the existing bounded classification/reachability probe, with its
    // existing emulator-pair branch exposed by the optional public parameter.
    await verifyDirectMediaBlobCustodyAndroidTopologyAndReachability(
      adbExecutable:
          environment['PLAN347_ADB_EXECUTABLE']?.trim().isNotEmpty == true
          ? environment['PLAN347_ADB_EXECUTABLE']!.trim()
          : 'adb',
      devices: [first, second],
      host: fixture.host,
      port: fixture.port,
      emulatorPair: true,
    );
    final checkpoint = DirectTextCheckpointClient(Uri.parse(fixture.probeUrl));
    final status = await checkpoint.status();
    if (status['armed'] != false) {
      throw StateError('new owned checkpoint fixture is not unused');
    }
    final childEnvironment = <String, String>{
      ...environment,
      'MKNOON_DIRECT_TEXT_SEND_CHECKPOINT': '1',
      'MKNOON_RELAY_ADDRESSES': fixture.multiaddr,
      'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_IDENTITY_SHA256':
          fixture.fixtureIdentitySha256,
      'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_PROBE_URL': fixture.probeUrl,
      'RELIABILITY_MULTI_DEVICE_IDS': '$first,$second',
    };
    final dart =
        environment['PLAN347_SIMS_DART_EXECUTABLE']?.trim().isNotEmpty == true
        ? environment['PLAN347_SIMS_DART_EXECUTABLE']!.trim()
        : Platform.resolvedExecutable;
    Future<int> central(List<String> suffix) async {
      final child = await Process.run(dart, [
        'run',
        'tool/sims/sims.dart',
        arguments[1],
        '--only',
        productionDirectSendCut,
        ...suffix,
      ], environment: childEnvironment);
      stdout.write(child.stdout);
      stderr.write(child.stderr);
      return child.exitCode;
    }

    result = await central(['--prepare-builds']);
    if (result == 0) result = await central([]);
  } catch (error, stack) {
    stderr.writeln('Owned direct-text cut fixture incomplete: $error\n$stack');
    result = 1;
  } finally {
    if (fixture != null) {
      try {
        await fixture.stop();
      } catch (error, stack) {
        stderr.writeln(
          'Owned direct-text fixture teardown failed: $error\n$stack',
        );
        if (result == 0) result = 1;
      }
    }
  }
  exitCode = result;
}
