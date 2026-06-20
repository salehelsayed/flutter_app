import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/run_group_multi_party_device_real.dart';

void main() {
  group('runGroupMultiPartyScenarioSweep', () {
    test(
      'continues aggregate sweeps and returns nonzero when one fails',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'group_multi_party_sweep_continue_test_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });
        final attempted = <String>[];
        final logs = <String>[];

        final result = await runGroupMultiPartyScenarioSweep(
          scenarios: const <String>['first', 'middle', 'last'],
          devices: const <String>[
            'alice-device',
            'bob-device',
            'charlie-device',
          ],
          relayAddresses: 'relay',
          sweepRunId: 'sweep-001',
          continueOnFailure: true,
          failureArtifactsDir: tempDir,
          log: (tag, message) => logs.add('[$tag] $message'),
          runScenario:
              ({
                required scenario,
                required devices,
                required relayAddresses,
                required sweepRunId,
              }) async {
                attempted.add(scenario);
                if (scenario == 'middle') {
                  throw StateError('injected failure');
                }
                File(
                  '${tempDir.path}/${scenario}_orchestrator_verdict.json',
                ).writeAsStringSync(
                  jsonEncode(<String, Object?>{
                    'scenario': scenario,
                    'ok': true,
                    'detail': 'injected pass',
                  }),
                );
              },
        );

        expect(attempted, const <String>['first', 'middle', 'last']);
        expect(result.exitCode, 1);
        expect(result.hasFailures, isTrue);
        expect(result.failures.single.scenario, 'middle');
        final failureArtifactPath =
            result.failures.single.orchestratorVerdictPath;
        expect(failureArtifactPath, isNotNull);
        final failureArtifact = File(failureArtifactPath!);
        expect(failureArtifact.existsSync(), isTrue);
        final failureJson =
            jsonDecode(failureArtifact.readAsStringSync())
                as Map<String, dynamic>;
        expect(failureJson['scenario'], 'middle');
        expect(failureJson['ok'], isFalse);
        expect(
          failureJson['detail'],
          contains('failed before completing verdict validation'),
        );
        expect(
          logs,
          containsAllInOrder(<String>[
            '[ORCH] SWEEP PASS: first',
            '[ORCH] SWEEP FAIL: middle: Bad state: injected failure',
            '[ORCH] SWEEP PASS: last',
          ]),
        );
        for (final scenario in const <String>['first', 'last']) {
          expect(
            File(
              '${tempDir.path}/${scenario}_orchestrator_verdict.json',
            ).existsSync(),
            isTrue,
            reason: '$scenario should have an orchestrator verdict artifact',
          );
        }
      },
    );

    test('preserves fail-fast behavior for single-scenario runs', () async {
      final attempted = <String>[];

      await expectLater(
        runGroupMultiPartyScenarioSweep(
          scenarios: const <String>['first', 'second'],
          devices: const <String>['alice-device'],
          relayAddresses: 'relay',
          sweepRunId: 'sweep-001',
          runScenario:
              ({
                required scenario,
                required devices,
                required relayAddresses,
                required sweepRunId,
              }) async {
                attempted.add(scenario);
                throw StateError('stop');
              },
        ),
        throwsStateError,
      );

      expect(attempted, const <String>['first']);
    });
  });
}
