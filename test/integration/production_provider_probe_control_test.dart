import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/production_provider_probe_control.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('provider-control-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  const receiver = SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: 'android.production_fcm.journey',
    scenarioId: notificationOpenJourney,
    role: 'bob',
    runId: 'provider-run',
    nonce: 'provider-nonce',
    values: {},
  );

  Future<ProductionJourneyController> controller(
    SimsRuntimeInvocation invocation,
    Future<String?> Function() getToken,
  ) async {
    final value = ProductionJourneyController(
      directory: Directory(
        '${directory.path}/${invocation.profileId}-${invocation.role}-${invocation.scenarioId}',
      ),
      profileId: invocation.profileId,
      invocation: invocation,
    );
    bindProductionProviderProbeControl(controller: value, getToken: getToken);
    value.foregroundPush.bind((_) async {});
    value.markRuntimeReady();
    await value.start();
    addTearDown(value.dispose);
    return value;
  }

  Map<String, Object?> command(
    SimsRuntimeInvocation invocation,
    int sequence, {
    Map<String, Object?> arguments = const {},
  }) => {
    'invocation': invocation.toJson(),
    'sequence': sequence,
    'operation': 'provider_token',
    'arguments': arguments,
  };

  test('only the exact Bob invocation can claim its real token once', () async {
    var tokenReads = 0;
    final value = await controller(receiver, () async {
      tokenReads++;
      return 'actual-provider-token';
    });
    await expectLater(
      value.execute(command(receiver.copyWith(nonce: 'stale'), 1)),
      throwsStateError,
    );
    expect(tokenReads, 0);
    expect(await value.execute(command(receiver, 1)), {
      'token': 'actual-provider-token',
    });
    await expectLater(value.execute(command(receiver, 2)), throwsStateError);
    expect(tokenReads, 1);
  });

  for (final invalid in [
    receiver.copyWith(profileId: 'android.e2e.production'),
    receiver.copyWith(role: 'alice'),
    receiver.copyWith(scenarioId: routingSmokeJourney),
  ]) {
    test(
      'provider token action stays inactive for ${invalid.toJson()}',
      () async {
        var tokenReads = 0;
        final value = await controller(invalid, () async {
          tokenReads++;
          return 'token';
        });
        await expectLater(value.execute(command(invalid, 1)), throwsStateError);
        expect(tokenReads, 0);
      },
    );
  }

  test('missing provider registration token fails closed', () async {
    final value = await controller(receiver, () async => null);
    await expectLater(value.execute(command(receiver, 1)), throwsStateError);
  });
}
