import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/production_direct_journey_controls.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('other-chat fixture belongs only to the production Bob receiver', () {
    for (final (profile, role, accepted) in [
      ('android.production_fcm.journey', 'bob', true),
      ('android.e2e.main', 'alice', false),
      ('android.e2e.main', 'bob', false),
      ('android.production_fcm.journey', 'alice', false),
    ]) {
      final controller = ProductionJourneyController(
        directory: Directory.systemTemp,
        profileId: profile,
        invocation: SimsRuntimeInvocation(
          schema: simsRuntimeConfigSchema,
          profileId: profile,
          scenarioId: notificationOpenJourney,
          role: role,
          runId: 'fixture-run',
          nonce: 'fixture-nonce',
          values: const {'fixtureId': 'fixture-run'},
        ),
      );
      expect(productionNotificationOtherChatOwner(controller), accepted);
      controller.dispose();
    }
  });
  for (final role in ['alice', 'bob', 'sender']) {
    test(
      'notification-open runtime admission binds exact role $role',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'notification-admission-',
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
              scenarioId: notificationOpenJourney,
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
          expect(controller.invocation.scenarioId, notificationOpenJourney);
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
