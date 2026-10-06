import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (profile, scenario) in [
    ('android.e2e.production', performanceJourney),
    ('android.e2e.performance_relay', foregroundGroupPushJourney),
  ]) {
    test('rejects profile/scenario mismatch $profile $scenario', () async {
      final directory = await Directory.systemTemp.createTemp(
        'performance-profile-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final config = File(
        '${directory.path}/production-journey/runtime-config.json',
      );
      await config.parent.create();
      await config.writeAsString(
        jsonEncode(
          SimsRuntimeInvocation(
            schema: simsRuntimeConfigSchema,
            profileId: profile,
            scenarioId: scenario,
            role: 'alice',
            runId: 'run',
            nonce: 'nonce',
            values: {'fixtureId': 'run'},
          ).toJson(),
        ),
      );
      expect(
        () => ProductionJourneyController.forInstalledProfile(
          stateDirectory: directory,
          isDebugMode: true,
          e2eTestMode: true,
          profileId: profile,
        ),
        throwsStateError,
      );
    });
  }
  for (final role in ['alice', 'bob', 'sender']) {
    test('performance runtime admission binds exact role $role', () async {
      final directory = await Directory.systemTemp.createTemp(
        'performance-admission-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final config = File(
        '${directory.path}/production-journey/runtime-config.json',
      );
      await config.parent.create();
      await config.writeAsString(
        jsonEncode(
          SimsRuntimeInvocation(
            schema: simsRuntimeConfigSchema,
            profileId: 'android.e2e.performance_relay',
            scenarioId: performanceJourney,
            role: role,
            runId: 'fixture-run',
            nonce: 'fixture-nonce',
            values: {'fixtureId': 'fixture-run'},
          ).toJson(),
        ),
      );
      ProductionJourneyController? activate() =>
          ProductionJourneyController.forInstalledProfile(
            stateDirectory: directory,
            isDebugMode: true,
            e2eTestMode: true,
            profileId: 'android.e2e.performance_relay',
          );
      if (role != 'alice') {
        expect(activate, throwsStateError);
      } else {
        final controller = activate()!;
        expect(controller.invocation.role, role);
        expect(controller.invocation.scenarioId, performanceJourney);
        var releaseCount = 0;
        controller.bindDisposer(() => releaseCount++);
        controller.dispose();
        controller.dispose();
        expect(releaseCount, 1);
      }
    });
  }
}
