import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final role in ['alice', 'bob', 'sender']) {
    test(
      'group-invite runtime admission binds exact role $role',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'group-invite-admission-',
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
              profileId: 'android.e2e.main',
              scenarioId: groupInviteJourney,
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
              profileId: 'android.e2e.main',
            );
        if (role == 'sender') {
          expect(activate, throwsStateError);
        } else {
          final controller = activate()!;
          expect(controller.invocation.role, role);
          expect(controller.invocation.scenarioId, groupInviteJourney);
          var releaseCount = 0;
          controller.bindDisposer(() => releaseCount++);
          controller.dispose();
          controller.dispose();
          expect(releaseCount, 1);
        }
      },
    );
  }
}
