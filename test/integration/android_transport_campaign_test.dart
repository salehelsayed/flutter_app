import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_transport_campaign.dart';
import '../../integration_test/support/sims_runtime_protocol.dart';

void main() {
  group('Plan 258 Android transport runtime protocol', () {
    test('scenario profile and two-peer roles fail closed', () {
      const cases = <SimsRuntimeInvocation>[
        SimsRuntimeInvocation(
          schema: simsRuntimeConfigSchema,
          profileId: simsAndroidMainProfileId,
          scenarioId: simsAndroidConnectivityRestoreScenarioId,
          role: simsTransportReceiverRole,
          runId: 'run-connectivity',
          nonce: 'nonce-connectivity',
          values: <String, Object?>{},
        ),
        SimsRuntimeInvocation(
          schema: simsRuntimeConfigSchema,
          profileId: simsAndroidMainProfileId,
          scenarioId: simsAndroidKeepaliveDropScenarioId,
          role: simsTransportSenderRole,
          runId: 'run-keepalive',
          nonce: 'nonce-keepalive',
          values: <String, Object?>{},
        ),
        SimsRuntimeInvocation(
          schema: simsRuntimeConfigSchema,
          profileId: simsAndroidWakeTokenProfileId,
          scenarioId: simsAndroidWakeTokenDirectionalityScenarioId,
          role: simsWakeTokenPresenterRole,
          runId: 'run-wake',
          nonce: 'nonce-wake',
          values: <String, Object?>{},
        ),
      ];

      for (final invocation in cases) {
        expect(validateAndroidTransportInvocation(invocation), isNull);
      }

      expect(
        validateAndroidTransportInvocation(
          cases[0].copyWith(role: simsPrimaryRole),
        ),
        contains('does not support role'),
      );
      expect(
        validateAndroidTransportInvocation(
          cases[2].copyWith(profileId: simsAndroidStandardProfileId),
        ),
        contains('requires profile'),
      );
      expect(
        validateAndroidTransportInvocation(
          cases[1].copyWith(profileId: simsAndroidStandardProfileId),
        ),
        contains(simsAndroidMainProfileId),
      );
      expect(
        validateAndroidTransportInvocation(
          cases[0].copyWith(scenarioId: 'android.unknown'),
        ),
        contains('unsupported'),
      );
    });

    test(
      'connectivity evidence derives no-resume state from sanitized production events',
      () {
        final flow = AndroidTransportFlowCapture()..start();
        addTearDown(flow.stop);
        expect(AndroidTransportFlowCapture().start, throwsStateError);

        final sender =
            ConnectivitySenderEvidenceBuilder(
                _invocation(
                  scenario: simsAndroidConnectivityRestoreScenarioId,
                  role: simsTransportSenderRole,
                  runId: 'run-connectivity-evidence',
                ),
              )
              ..recordQueuedMessage()
              ..recordQueuedMessage()
              ..recordQueuedMessage();
        final receiver = ConnectivityReceiverEvidenceBuilder(
          invocation: _invocation(
            scenario: simsAndroidConnectivityRestoreScenarioId,
            role: simsTransportReceiverRole,
            runId: 'run-connectivity-evidence',
          ),
          flow: flow,
        );
        receiver
          ..recordRenderedMessage()
          ..recordRenderedMessage()
          ..recordRenderedMessage()
          ..beginForegroundRestoreWindow();

        _event(flow, 'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN');
        _event(flow, 'P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM');
        _event(flow, 'P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS');

        final senderLocal = sender.completeLocal();
        final receiverLocal = receiver.completeLocal();
        expect(senderLocal['status'], 'observed');
        expect(receiverLocal['status'], 'observed');
        final artifact = finalizeConnectivityRestoreEvidence(
          senderEvidence: senderLocal,
          receiverEvidence: receiverLocal,
          deviceIds: const <String>['physical-android', 'android-emulator'],
        );
        expect(artifact['resumeEventsDuringWindow'], 0);
        expect(artifact['messagesRendered'], 3);

        expect(
          () => finalizeConnectivityRestoreEvidence(
            senderEvidence: senderLocal,
            receiverEvidence: <String, Object?>{
              ...receiverLocal,
              'runId': 'stale-run',
            },
            deviceIds: const <String>['physical-android', 'android-emulator'],
          ),
          throwsStateError,
        );
      },
    );

    test(
      'keepalive evidence times real custody and rejects a real dial begin',
      () {
        final flow = AndroidTransportFlowCapture()..start();
        addTearDown(flow.stop);
        final evidence = KeepaliveDropEvidenceBuilder(
          invocation: _invocation(
            scenario: simsAndroidKeepaliveDropScenarioId,
            role: simsTransportSenderRole,
            runId: 'run-keepalive-evidence',
          ),
          flow: flow,
        );

        _event(flow, 'P2P_SERVICE_PEER_PING_SUCCESS');
        _event(flow, 'KEEPALIVE_PEER_DROP');
        evidence.beginDroppedPeerSendWindow();
        _event(
          flow,
          'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
          messageIdPrefix: 'a1b2c3d4',
        );
        _event(flow, 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP');
        _event(
          flow,
          'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
          messageIdPrefix: 'a1b2c3d4',
        );
        evidence.endDroppedPeerSendWindow(
          messageId: 'a1b2c3d4-1111-2222-3333-444455556666',
        );
        _event(flow, 'DELIVERY_RECEIPT_APPLIED', messageIdPrefix: 'a1b2c3d4');
        _event(flow, 'P2P_SERVICE_PEER_PING_SUCCESS');

        final artifact = finalizeKeepaliveDropEvidence(
          senderEvidence: evidence.completeLocal(),
          deviceIds: const <String>['physical-android', 'android-emulator'],
        );
        expect(artifact['custodyLatencyMs'], lessThan(1000));
        flow.stop();

        final secondFlow = AndroidTransportFlowCapture()..start();
        try {
          final invalid = KeepaliveDropEvidenceBuilder(
            invocation: _invocation(
              scenario: simsAndroidKeepaliveDropScenarioId,
              role: simsTransportSenderRole,
              runId: 'run-keepalive-invalid',
            ),
            flow: secondFlow,
          );
          _event(secondFlow, 'KEEPALIVE_PEER_DROP');
          invalid.beginDroppedPeerSendWindow();
          _event(
            secondFlow,
            'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
            messageIdPrefix: 'b1c2d3e4',
          );
          _event(secondFlow, 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP');
          _event(secondFlow, 'P2P_SERVICE_DIAL_PEER_BEGIN');
          _event(
            secondFlow,
            'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
            messageIdPrefix: 'b1c2d3e4',
          );
          invalid.endDroppedPeerSendWindow(
            messageId: 'b1c2d3e4-1111-2222-3333-444455556666',
          );
          _event(
            secondFlow,
            'DELIVERY_RECEIPT_APPLIED',
            messageIdPrefix: 'b1c2d3e4',
          );
          _event(secondFlow, 'P2P_SERVICE_PEER_PING_SUCCESS');
          final local = invalid.completeLocal();
          expect(
            () => finalizeKeepaliveDropEvidence(
              senderEvidence: local,
              deviceIds: const <String>['physical-android', 'android-emulator'],
            ),
            throwsStateError,
          );
        } finally {
          secondFlow.stop();
        }
      },
    );

    test('keepalive receipt must match the real send message id', () {
      final flow = AndroidTransportFlowCapture()..start();
      addTearDown(flow.stop);
      final evidence = KeepaliveDropEvidenceBuilder(
        invocation: _invocation(
          scenario: simsAndroidKeepaliveDropScenarioId,
          role: simsTransportSenderRole,
          runId: 'run-keepalive-correlation',
        ),
        flow: flow,
      );

      _event(flow, 'KEEPALIVE_PEER_DROP');
      evidence.beginDroppedPeerSendWindow();
      _event(
        flow,
        'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
        messageIdPrefix: 'c1d2e3f4',
      );
      _event(flow, 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP');
      _event(
        flow,
        'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
        messageIdPrefix: 'c1d2e3f4',
      );
      evidence.endDroppedPeerSendWindow(
        messageId: 'c1d2e3f4-1111-2222-3333-444455556666',
      );
      _event(flow, 'DELIVERY_RECEIPT_APPLIED', messageIdPrefix: 'deadbeef');
      _event(flow, 'P2P_SERVICE_PEER_PING_SUCCESS');

      expect(evidence.completeLocal, throwsStateError);
    });

    test(
      'wake evidence retains hashes only and rejects direction inversion',
      () {
        const token = 'opaque-wake-token-that-must-not-enter-the-artifact';
        final issuer = WakeTokenIssuerEvidenceBuilder(
          _invocation(
            scenario: simsAndroidWakeTokenDirectionalityScenarioId,
            role: simsWakeTokenIssuerRole,
            runId: 'run-wake-evidence',
          ),
        )..observeNativeRegistration(token);
        final presenter =
            WakeTokenPresenterEvidenceBuilder(
                _invocation(
                  scenario: simsAndroidWakeTokenDirectionalityScenarioId,
                  role: simsWakeTokenPresenterRole,
                  runId: 'run-wake-evidence',
                ),
              )
              ..observeReceivedTokenStore(token)
              ..observeInboxStoreAttachment(token);

        final artifact = finalizeWakeTokenDirectionalityEvidence(
          issuerEvidence: issuer.completeLocal(),
          presenterEvidence: presenter.completeLocal(),
          deviceIds: const <String>['physical-android', 'android-emulator'],
        );
        final encoded = jsonEncode(artifact);
        expect(encoded, isNot(contains(token)));
        expect(encoded, isNot(contains('rawWakeToken')));
        expect(artifact['registeredTokenSha256'], hasLength(64));
        expect(
          artifact['registeredTokenSha256'],
          artifact['attachedTokenSha256'],
        );

        final invertedPresenter =
            WakeTokenPresenterEvidenceBuilder(
                _invocation(
                  scenario: simsAndroidWakeTokenDirectionalityScenarioId,
                  role: simsWakeTokenPresenterRole,
                  runId: 'run-wake-evidence',
                ),
              )
              ..observeReceivedTokenStore('wrong-direction-token')
              ..observeInboxStoreAttachment(token);
        expect(
          () => finalizeWakeTokenDirectionalityEvidence(
            issuerEvidence: issuer.completeLocal(),
            presenterEvidence: invertedPresenter.completeLocal(),
            deviceIds: const <String>['physical-android', 'android-emulator'],
          ),
          throwsStateError,
        );
      },
    );

    test('wake evidence cannot complete from a partial boundary', () {
      final issuer = WakeTokenIssuerEvidenceBuilder(
        _invocation(
          scenario: simsAndroidWakeTokenDirectionalityScenarioId,
          role: simsWakeTokenIssuerRole,
          runId: 'run-wake-partial',
        ),
      );
      expect(issuer.completeLocal, throwsStateError);

      final storeOnly = WakeTokenPresenterEvidenceBuilder(
        _invocation(
          scenario: simsAndroidWakeTokenDirectionalityScenarioId,
          role: simsWakeTokenPresenterRole,
          runId: 'run-wake-partial',
        ),
      )..observeReceivedTokenStore('store-boundary-token');
      expect(storeOnly.completeLocal, throwsStateError);

      final attachmentOnly = WakeTokenPresenterEvidenceBuilder(
        _invocation(
          scenario: simsAndroidWakeTokenDirectionalityScenarioId,
          role: simsWakeTokenPresenterRole,
          runId: 'run-wake-partial',
        ),
      )..observeInboxStoreAttachment('attachment-boundary-token');
      expect(attachmentOnly.completeLocal, throwsStateError);
    });
  });
}

SimsRuntimeInvocation _invocation({
  required String scenario,
  required String role,
  required String runId,
}) => SimsRuntimeInvocation(
  schema: simsRuntimeConfigSchema,
  profileId: switch (scenario) {
    simsAndroidConnectivityRestoreScenarioId ||
    simsAndroidKeepaliveDropScenarioId => simsAndroidMainProfileId,
    simsAndroidWakeTokenDirectionalityScenarioId =>
      simsAndroidWakeTokenProfileId,
    _ => simsAndroidStandardProfileId,
  },
  scenarioId: scenario,
  role: role,
  runId: runId,
  nonce: 'nonce-$role',
  values: const <String, Object?>{},
);

void _event(
  AndroidTransportFlowCapture capture,
  String name, {
  String? messageIdPrefix,
}) {
  capture.recordSanitizedFlowEvent(<String, dynamic>{
    'event': name,
    'details': <String, Object?>{
      // Evidence capture must ignore even a mistakenly supplied secret detail.
      'wakeToken': 'must-not-be-retained',
      'id': ?messageIdPrefix,
    },
  });
}
