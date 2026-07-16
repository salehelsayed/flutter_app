import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/sims_runtime_protocol.dart';
import '../../tool/sims/runtime_dispatch.dart' as host_model;

void main() {
  const invocation = SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: simsAndroidStandardProfileId,
    scenarioId: simsAndroidVoiceRecorderScenarioId,
    role: simsPrimaryRole,
    runId: 'run-contract-1',
    nonce: 'nonce-contract-1',
    values: <String, Object?>{'permissionPregranted': true},
  );

  test('host model and runnable dispatcher share the config schema', () {
    expect(host_model.simsRuntimeConfigSchema, simsRuntimeConfigSchema);
  });

  test(
    'accepted tuple is acknowledged before its registered proof runs',
    () async {
      final events = <String>[];
      SimsRuntimeAck? writtenAck;

      await dispatchSimsRuntimeEncodedConfig(
        encodedConfig: jsonEncode(invocation.toJson()),
        installedProfileId: simsAndroidStandardProfileId,
        supportedRole: simsPrimaryRole,
        scenarioHandlers: <String, SimsRuntimeScenarioHandler>{
          simsAndroidVoiceRecorderScenarioId: (received) async {
            events.add('proof:${received.scenarioId}');
          },
        },
        writeAck: (ack) async {
          writtenAck = ack;
          events.add('ack:${ack.accepted}');
        },
      );

      expect(events, <String>[
        'ack:true',
        'proof:android.voice_recorder_native_smoke',
      ]);
      expect(writtenAck, isNotNull);
      expect(
        validateSimsRuntimeAck(writtenAck!.toJson(), invocation).accepted,
        isTrue,
      );
    },
  );

  test(
    'missing corrupt wrong-profile role or scenario config has no fallback',
    () async {
      final cases = <String?>[
        null,
        '{not-json',
        jsonEncode(
          invocation.copyWith(profileId: 'android.e2e.wake_token').toJson(),
        ),
        jsonEncode(invocation.copyWith(role: 'receiver').toJson()),
        jsonEncode(
          invocation.copyWith(scenarioId: 'missing.scenario').toJson(),
        ),
        jsonEncode(invocation.copyWith(nonce: 'contains whitespace').toJson()),
      ];

      for (final encoded in cases) {
        final events = <String>[];
        await expectLater(
          () => dispatchSimsRuntimeEncodedConfig(
            encodedConfig: encoded,
            installedProfileId: simsAndroidStandardProfileId,
            supportedRole: simsPrimaryRole,
            scenarioHandlers: <String, SimsRuntimeScenarioHandler>{
              simsAndroidVoiceRecorderScenarioId: (_) async {
                events.add('proof');
              },
            },
            writeAck: (ack) async {
              events.add('ack:${ack.accepted}');
            },
          ),
          throwsStateError,
        );
        expect(events, <String>['ack:false']);
      }
    },
  );

  test(
    'host acknowledgement validation binds profile scenario role run and nonce',
    () {
      final accepted = SimsRuntimeAck.accept(invocation);
      expect(
        validateSimsRuntimeAck(accepted.toJson(), invocation).accepted,
        isTrue,
      );

      final mismatches = <SimsRuntimeAck>[
        accepted.copyWith(profileId: 'android.e2e.wake_token'),
        accepted.copyWith(scenarioId: 'android.keepalive_drop_skip_direct'),
        accepted.copyWith(role: 'receiver'),
        accepted.copyWith(runId: 'run-stale'),
        accepted.copyWith(nonce: 'nonce-stale'),
        accepted.copyWith(accepted: false, detail: 'app rejected config'),
      ];
      for (final mismatch in mismatches) {
        expect(
          validateSimsRuntimeAck(mismatch.toJson(), invocation).accepted,
          isFalse,
        );
      }
      expect(
        validateSimsRuntimeAck(<String, Object?>{}, invocation).accepted,
        isFalse,
      );
    },
  );

  test(
    'multi-peer roles must be explicitly enabled by the dispatcher',
    () async {
      final senderInvocation = invocation.copyWith(
        scenarioId: simsAndroidVoiceMessageScenarioId,
        role: simsVoiceMessageSenderRole,
      );
      final events = <String>[];

      await expectLater(
        () => dispatchSimsRuntimeEncodedConfig(
          encodedConfig: jsonEncode(senderInvocation.toJson()),
          installedProfileId: simsAndroidStandardProfileId,
          supportedRole: simsPrimaryRole,
          scenarioHandlers: <String, SimsRuntimeScenarioHandler>{
            simsAndroidVoiceMessageScenarioId: (_) async => events.add('proof'),
          },
          writeAck: (ack) async => events.add('ack:${ack.accepted}'),
        ),
        throwsStateError,
      );
      expect(events, <String>['ack:false']);

      events.clear();
      await dispatchSimsRuntimeEncodedConfig(
        encodedConfig: jsonEncode(senderInvocation.toJson()),
        installedProfileId: simsAndroidStandardProfileId,
        supportedRole: simsPrimaryRole,
        additionalSupportedRoles: const <String>{
          simsVoiceMessageSenderRole,
          simsVoiceMessageReceiverRole,
        },
        scenarioHandlers: <String, SimsRuntimeScenarioHandler>{
          simsAndroidVoiceMessageScenarioId: (_) async => events.add('proof'),
        },
        writeAck: (ack) async => events.add('ack:${ack.accepted}'),
      );
      expect(events, <String>['ack:true', 'proof']);
    },
  );
}
