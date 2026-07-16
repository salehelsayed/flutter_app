/// Universal prebuilt-APK entrypoint for runtime-dispatched sims scenarios.
///
/// The host stages a private-app JSON invocation containing a build profile,
/// scenario, role, run ID, and nonce. This target fails closed when that config
/// is absent or invalid, writes an acknowledgement with the exact tuple, and
/// only then invokes a registered scenario. It has no default scenario.
@Tags(<String>['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'support/android_critical_performance_campaign.dart';
import 'support/android_critical_performance_evidence.dart';
import 'support/android_voice_recorder_smoke.dart';
import 'support/sims_runtime_protocol.dart';

const String _installedProfileId = String.fromEnvironment(
  'SIMS_BUILD_PROFILE_ID',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('sims runtime dispatcher', () {
    testWidgets(
      'acknowledges a staged invocation before executing its scenario',
      (tester) async {
        final supportDirectory = await getApplicationSupportDirectory();
        final runtimeDirectory = Directory(
          '${supportDirectory.path}/$simsRuntimeDirectory',
        );
        await runtimeDirectory.create(recursive: true);
        final configFile = File(
          '${runtimeDirectory.path}/$simsRuntimeConfigFileName',
        );
        final ackFile = File(
          '${runtimeDirectory.path}/$simsRuntimeAckFileName',
        );
        final resultFile = File(
          '${runtimeDirectory.path}/$simsRuntimeResultFileName',
        );
        if (await ackFile.exists()) await ackFile.delete();
        if (await resultFile.exists()) await resultFile.delete();

        String? encodedConfig;
        if (await configFile.exists()) {
          try {
            encodedConfig = await configFile.readAsString();
          } finally {
            await configFile.delete();
          }
        }

        await dispatchSimsRuntimeEncodedConfig(
          encodedConfig: encodedConfig,
          installedProfileId: _installedProfileId,
          supportedRole: simsPrimaryRole,
          scenarioHandlers: <String, SimsRuntimeScenarioHandler>{
            simsAndroidVoiceRecorderScenarioId: (_) async {
              final proof = await runAndroidVoiceRecorderSmoke();
              await _writeJsonAtomically(resultFile, proof);
            },
            simsAndroidCriticalPerformanceScenarioId: (invocation) async {
              final proof = await runAndroidCriticalPerformanceCampaign(
                tester,
                invocation,
              );
              await _writeJsonAtomically(resultFile, proof);
            },
          },
          scenarioValidators: <String, SimsRuntimeScenarioValidator>{
            simsAndroidVoiceRecorderScenarioId: (invocation) =>
                invocation.values['permissionPregranted'] == true
                ? null
                : 'voice recorder invocation must attest permission pregrant',
            simsAndroidCriticalPerformanceScenarioId: (invocation) {
              final validation = validateAndroidCriticalPerformanceInvocation(
                invocation,
              );
              return validation.ok ? null : validation.detail;
            },
          },
          writeAck: (ack) => _writeAckAtomically(ackFile, ack),
        );
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}

Future<void> _writeAckAtomically(File ackFile, SimsRuntimeAck ack) =>
    _writeJsonAtomically(ackFile, ack.toJson());

Future<void> _writeJsonAtomically(File file, Map<String, Object?> json) async {
  final temporary = File('${file.path}.tmp');
  if (await temporary.exists()) await temporary.delete();
  await temporary.writeAsString('${jsonEncode(json)}\n', flush: true);
  if (await file.exists()) await file.delete();
  await temporary.rename(file.path);
}
