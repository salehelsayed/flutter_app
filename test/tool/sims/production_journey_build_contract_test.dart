import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/build_orchestrator.dart';
import '../../../tool/sims/executor.dart';
import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/verdict.dart';

void main() {
  test(
    'relay performance has a separate attested production build variant',
    () {
      final manifest = SimsManifest.loadSync(
        File('tool/sims/critical_features.json'),
      );
      final performance = manifest.buildProfileById(
        'android.e2e.performance_relay',
      )!;
      final ordinary = manifest.buildProfileById('android.e2e.main')!;
      const environment = {'SIMS_APP_ID': 'com.mknoon.sims.connectivity'};
      expect(
        effectiveSimsBuildArguments(performance, environment: environment),
        containsAll([
          '--target=lib/main.dart',
          '--dart-define=DISABLE_LOCAL_DISCOVERY=true',
          '--dart-define=SIMS_BUILD_PROFILE_ID=android.e2e.performance_relay',
          '--android-project-arg=disableGoogleServicesForDisposableProof=true',
        ]),
      );
      expect(
        effectiveSimsCompileDefines(ordinary),
        isNot(contains('DISABLE_LOCAL_DISCOVERY')),
      );
      final route = manifest.capabilities.singleWhere(
        (c) => c.id == 'production.startup_resume_performance',
      );
      expect(route.buildProfileId, performance.id);
      expect(
        route.dependencies,
        contains('build.android.e2e.performance_relay'),
      );
    },
  );

  test(
    'production simulator profile preserves the original harness profile',
    () {
      final manifest = SimsManifest.loadSync(
        File('tool/sims/critical_features.json'),
      );
      final app = manifest.buildProfileById('ios.simulator.app')!;
      final original = manifest.buildProfileById('ios.simulator.e2e')!;
      const environment = {'MKNOON_RELAY_ADDRESSES': '/fixture/relay'};
      final arguments = effectiveSimsBuildArguments(
        app,
        environment: environment,
      );
      expect(
        arguments,
        containsAll([
          'ios',
          '--simulator',
          '--debug',
          '--no-codesign',
          '--target=lib/main.dart',
        ]),
      );
      expect(arguments, isNot(contains('--release')));
      expect(
        effectiveSimsCompileDefines(app, environment: environment),
        containsPair('MKNOON_RELAY_ADDRESSES', '/fixture/relay'),
      );
      expect(
        effectiveSimsCompileDefines(app, environment: environment),
        isNot(contains('MKNOON_KEY_ROTATION_GRACE_PERIOD_MS')),
      );
      expect(
        effectiveSimsBuildArguments(original, environment: environment),
        contains(
          '--target=integration_test/group_multi_party_device_real_harness.dart',
        ),
      );
      expect(
        effectiveSimsCompileDefines(original, environment: environment),
        containsPair('MKNOON_KEY_ROTATION_GRACE_PERIOD_MS', '1500'),
      );
    },
  );

  for (final prepared in [false, true]) {
    test(
      'child digest provenance rejects ambient values: prepared=$prepared',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'journey-build-contract-',
        );
        addTearDown(() => temporary.delete(recursive: true));
        const profile = 'android.e2e.main';
        const row = CapabilitySpec(
          id: 'fixture.production-digest-handoff',
          owner: 'test',
          proofBoundaryId: 'fixture.process-environment',
          assertionIds: ['fixture.digest'],
          lane: 'reliability',
          modes: {SimsMode.major},
          families: {'test'},
          required: true,
          command: [
            'bash',
            '-c',
            r'''printf 'input=%s\nartifact=%s\npath=%s\n' "${SIMS_ARTIFACT_INPUT_DIGEST-unset}" "${SIMS_ARTIFACT_SHA256-unset}" "${SIMS_ARTIFACT_ANDROID_E2E_MAIN-unset}"
printf 'SIMS_RESULT_JSON={"status":"PASS","assertionsAttempted":1,"artifactPresent":false,"printOnly":false}\n' ''',
          ],
          buildProfileId: profile,
          dependencies: [],
          resources: [],
          targetCapabilities: [],
          allowedNaReason: null,
          artifactRequired: false,
          artifactValidator: null,
          active: true,
          declaredBuildException: false,
        );
        final result = await SimsProcessExecutor(
          logDirectory: temporary,
          environment: {
            ...Platform.environment,
            'SIMS_ARTIFACT_INPUT_DIGEST': 'ambient-input',
            'SIMS_ARTIFACT_SHA256': 'ambient-artifact',
            'SIMS_ARTIFACT_ANDROID_E2E_MAIN': 'ambient-path',
          },
          environmentByCapabilityId: {
            row.id: {'SIMS_ARTIFACT_SHA256': 'row-contamination'},
          },
          preparedInputDigests: prepared
              ? {
                  profile: 'verified-input',
                  'ios.simulator.app': 'unrelated-input',
                }
              : {},
          preparedArtifactDigests: prepared
              ? {
                  profile: 'verified-artifact',
                  'ios.simulator.app': 'unrelated-artifact',
                }
              : {},
          preparedArtifacts: prepared ? {profile: '/fixture/prepared.apk'} : {},
        ).execute(row);
        expect(result.verdict.status, SimsVerdictStatus.pass);
        expect(
          result.stdoutText,
          contains(
            prepared
                ? 'input=verified-input\nartifact=verified-artifact\npath=/fixture/prepared.apk'
                : 'input=unset\nartifact=unset\npath=unset',
          ),
        );
        expect(result.stdoutText, isNot(contains('ambient')));
        expect(result.stdoutText, isNot(contains('contamination')));
        expect(result.stdoutText, isNot(contains('unrelated')));
      },
    );
  }

  test('mixed receiver is not handed a partial or ambient companion', () async {
    final temporary = await Directory.systemTemp.createTemp('mixed-build-env-');
    addTearDown(() => temporary.delete(recursive: true));
    const receiver = 'android.production_fcm.journey';
    final receiverFile = File('${temporary.path}/receiver.apk')
      ..writeAsBytesSync([1, 2, 3]);
    final base = SimsManifest.loadSync(File('tool/sims/critical_features.json'))
        .capabilities
        .singleWhere((row) => row.id == 'production.notification_open');
    final row = CapabilitySpec.fromJson({
      ...base.toJson(),
      'command': [
        'bash',
        '-c',
        r'''printf 'receiver=%s\ninput=%s\nsha=%s\n' "${SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM_JOURNEY-unset}" "${SIMS_ARTIFACT_INPUT_DIGEST_ANDROID_PRODUCTION_FCM_JOURNEY-unset}" "${SIMS_ARTIFACT_SHA256_ANDROID_PRODUCTION_FCM_JOURNEY-unset}"
printf 'SIMS_RESULT_JSON={"status":"PASS","assertionsAttempted":1,"artifactPresent":false,"printOnly":false}\n' ''',
      ],
      'artifactRequired': false,
      'artifactValidator': null,
    });
    for (final companion in [
      (path: receiverFile.path, input: null, sha: 'digest'),
      (path: '${temporary.path}/missing.apk', input: 'input', sha: 'digest'),
    ]) {
      final execution = await SimsProcessExecutor(
        logDirectory: Directory('${temporary.path}/logs'),
        environment: {
          ...Platform.environment,
          'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM_JOURNEY': 'ambient.apk',
        },
        preparedArtifacts: {receiver: companion.path},
        preparedInputDigests: {
          if (companion.input != null) receiver: companion.input!,
        },
        preparedArtifactDigests: {receiver: companion.sha},
      ).execute(row);
      expect(execution.verdict.status, SimsVerdictStatus.blocked);
      expect(execution.stdoutText, isEmpty);
      expect(
        execution.stderrText,
        contains('companion artifact is incomplete'),
      );
    }
  });
  for (final query in ['-version', '-version build', 'build', '']) {
    test('Maestro toolchain query guard: "$query"', () async {
      final temporary = await Directory.systemTemp.createTemp(
        'maestro-build-guard-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final executable = File('${temporary.path}/xcodebuild')
        ..writeAsStringSync('#!/bin/sh\necho fixture-xcode-version\n');
      expect(Process.runSync('chmod', ['700', executable.path]).exitCode, 0);
      final base =
          SimsManifest.loadSync(
            File('tool/sims/critical_features.json'),
          ).capabilities.singleWhere(
            (row) => row.id == 'production.foreground_group_push',
          );
      final row = CapabilitySpec.fromJson({
        ...base.toJson(),
        'command': [
          'bash',
          '-c',
          'xcodebuild $query || true; '
              r"""printf 'SIMS_RESULT_JSON={"status":"PASS","assertionsAttempted":1,"artifactPresent":false,"printOnly":false}\n' """,
        ],
        'artifactRequired': false,
        'artifactValidator': null,
      });
      final execution = await SimsProcessExecutor(
        logDirectory: Directory('${temporary.path}/logs'),
        environment: {
          ...Platform.environment,
          'PATH': '${temporary.path}:${Platform.environment['PATH']}',
        },
      ).execute(row);
      expect(
        execution.verdict.status,
        query == '-version' ? SimsVerdictStatus.pass : SimsVerdictStatus.fail,
      );
      expect(
        execution.stdoutText.contains('fixture-xcode-version'),
        query == '-version',
      );
    });
  }
}
