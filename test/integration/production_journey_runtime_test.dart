import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_request_observation.dart';
import 'package:flutter_app/debug/production_journeys/foreground_group_push_control.dart';
import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';

void main() {
  late Directory directory;
  late ProductionJourneyController controller;
  const invocation = SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: 'android.e2e.production',
    scenarioId: foregroundGroupPushJourney,
    role: 'bob',
    runId: 'run-1',
    nonce: 'nonce-1',
    values: {},
  );
  Map<String, Object?> command(
    int sequence,
    String operation, {
    SimsRuntimeInvocation? identity,
  }) => {
    'invocation': (identity ?? invocation).toJson(),
    'sequence': sequence,
    'operation': operation,
    'arguments': <String, Object?>{},
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'production-journey-test-',
    );
    controller = ProductionJourneyController(
      directory: directory,
      profileId: invocation.profileId,
      invocation: invocation,
    );
  });
  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'readiness acknowledgement does not complete a scenario or permit early actions',
    () async {
      var calls = 0;
      controller.bindAction('action', (_) async {
        calls++;
        return {'observed': true};
      });
      await controller.start();
      final ready = await controller.execute(command(1, 'readiness'));
      expect(ready['fixtureAccepted'], isTrue);
      expect(ready['productionRuntimeReady'], isFalse);
      expect(ready['scenarioComplete'], isFalse);
      await expectLater(
        controller.execute(command(2, 'action')),
        throwsStateError,
      );
      expect(calls, 0);
      controller.foregroundPush.bind((_) async {});
      controller.markRuntimeReady();
      expect(await controller.execute(command(3, 'action')), {
        'observed': true,
      });
      expect(calls, 1);
    },
  );

  for (final wrong in [
    invocation.copyWith(profileId: 'ios.simulator.app'),
    invocation.copyWith(role: 'alice'),
    invocation.copyWith(nonce: 'stale'),
    invocation.copyWith(runId: 'another-run'),
    invocation.copyWith(scenarioId: 'another-scenario'),
  ]) {
    test('command identity is exact: ${wrong.toJson()}', () async {
      await controller.start();
      await expectLater(
        controller.execute(command(1, 'readiness', identity: wrong)),
        throwsStateError,
      );
      expect(
        (await controller.execute(command(1, 'readiness')))['fixtureAccepted'],
        isTrue,
      );
    });
  }

  test(
    'duplicate command and restarted invocation cannot reuse previous success',
    () async {
      await controller.start();
      await controller.execute(command(1, 'readiness'));
      await expectLater(
        controller.execute(command(1, 'readiness')),
        throwsStateError,
      );
      controller.dispose();
      controller = ProductionJourneyController(
        directory: directory,
        profileId: invocation.profileId,
        invocation: invocation,
      );
      await expectLater(controller.start(), throwsStateError);
      final ack =
          jsonDecode(
                await File('${directory.path}/runtime-ack.json').readAsString(),
              )
              as Map;
      expect(ack['accepted'], isFalse);
    },
  );

  test(
    'normal builds and missing configuration retain no controller',
    () async {
      ProductionJourneyController? create({
        bool debug = true,
        bool e2e = true,
        String profile = 'android.e2e.production',
      }) => ProductionJourneyController.forInstalledProfile(
        stateDirectory: directory,
        isDebugMode: debug,
        e2eTestMode: e2e,
        profileId: profile,
      );
      expect(create(), isNull);
      final config = File(
        '${directory.path}/production-journey/runtime-config.json',
      );
      await config.parent.create();
      await config.writeAsString(jsonEncode(invocation.toJson()));
      expect(create(debug: false), isNull);
      expect(create(e2e: false), isNull);
      expect(create(profile: 'ios.device.production'), isNull);
      final accepted = create();
      expect(accepted, isNotNull);
      accepted!.dispose();
      await config.writeAsString(
        jsonEncode(invocation.copyWith(role: 'unexpected').toJson()),
      );
      expect(create, throwsStateError);
    },
  );

  test(
    'provider receiver activates only for Bob in notification journeys',
    () async {
      final config = File(
        '${directory.path}/production-journey/runtime-config.json',
      );
      await config.parent.create(recursive: true);
      final valid = invocation.copyWith(
        profileId: 'android.production_fcm.journey',
        scenarioId: 'production.notification_open',
      );
      ProductionJourneyController? activate() =>
          ProductionJourneyController.forInstalledProfile(
            stateDirectory: directory,
            isDebugMode: true,
            e2eTestMode: true,
            profileId: 'android.production_fcm.journey',
          );
      await config.writeAsString(jsonEncode(valid.toJson()));
      final accepted = activate();
      expect(accepted, isNotNull);
      accepted!.dispose();
      await config.writeAsString(
        jsonEncode(valid.copyWith(role: 'alice').toJson()),
      );
      expect(activate, throwsStateError);
      await config.writeAsString(
        jsonEncode(
          valid.copyWith(scenarioId: 'production.routing_smoke').toJson(),
        ),
      );
      expect(activate, throwsStateError);
      expect(
        ProductionJourneyController.forInstalledProfile(
          stateDirectory: directory,
          isDebugMode: false,
          e2eTestMode: true,
          profileId: 'android.production_fcm.journey',
        ),
        isNull,
      );
    },
  );

  test('failed action cannot produce an ok command receipt', () async {
    controller.bindAction(
      'fail',
      (_) async => throw StateError('controlled failure'),
    );
    controller.foregroundPush.bind((_) async {});
    controller.markRuntimeReady();
    await controller.start();
    await File(
      '${directory.path}/command.json',
    ).writeAsString(jsonEncode(command(1, 'fail')));
    await controller.poll();
    final receipt =
        jsonDecode(
              await File(
                '${directory.path}/command-result.json',
              ).readAsString(),
            )
            as Map;
    expect(receipt['ok'], isFalse);
    expect(receipt.containsKey('result'), isFalse);
  });

  test(
    'fault hits the actual foreground router once and is cleared for the next operation',
    () async {
      final control = ForegroundGroupPushControl();
      addTearDown(control.dispose);
      var drains = 0;
      control.bind((message) async {
        final result = await handleForegroundRemoteMessage(
          data: message.data,
          messageId: message.messageId,
          drainOfflineInbox: () async {},
          drainGroupOfflineInboxForGroup: (groupId) async {
            control.beforeGroupDrain(groupId);
            drains++;
          },
        );
        control.observePushResult(result: result.name, fallbackShown: false);
      });
      final failed = await control.inject(
        groupId: 'missing-run-1',
        messageId: 's3',
        failMissingGroupDrain: true,
      );
      expect(failed['result'], 'notificationNeededAfterDrainFailure');
      expect(failed['drainAttempts'], 1);
      expect(drains, 0);
      final next = await control.inject(
        groupId: 'missing-run-1',
        messageId: 'next',
      );
      expect(next['result'], isNot('notificationNeededAfterDrainFailure'));
      expect(drains, 1);
    },
  );

  test(
    'incomplete production callback and overflow fail the observation oracle',
    () async {
      final control = ForegroundGroupPushControl();
      addTearDown(control.dispose);
      control.bind((_) async {});
      await expectLater(
        control.inject(groupId: 'group', messageId: 's1'),
        throwsStateError,
      );
      for (var i = 0; i < 257; i++) {
        control.observeNotification(
          NotificationRequestObservation(
            kind: 'message',
            notificationId: i,
            routePayload: 'group:g|message:m',
            silent: false,
          ),
        );
      }
      expect(control.snapshotNotifications, throwsStateError);
    },
  );

  test('notification observer failure cannot escape into publication', () {
    expect(
      () => observeNotificationRequest(
        (_) => throw StateError('observer failed'),
        const NotificationRequestObservation(
          kind: 'message',
          notificationId: 1,
          routePayload: 'group:g|message:m',
          silent: false,
        ),
      ),
      returnsNormally,
    );
  });
}
