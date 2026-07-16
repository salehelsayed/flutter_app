import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_connectivity_restore_campaign.dart';
import '../../integration_test/support/android_transport_campaign.dart';
import '../../integration_test/support/sims_runtime_protocol.dart';

void main() {
  group('Android connectivity-restore endpoint prerequisites', () {
    test(
      'binds the shared main APK digest and physical/emulator role topology',
      () {
        final sender = _invocation(role: simsTransportSenderRole);
        final receiver = _invocation(role: simsTransportReceiverRole);

        expect(validateConnectivityRestoreInvocation(sender), isNull);
        expect(validateConnectivityRestoreInvocation(receiver), isNull);
        expect(
          validateConnectivityRestoreInvocation(
            sender.copyWith(
              values: <String, Object?>{
                ...sender.values,
                'targetKind': 'emulator',
              },
            ),
          ),
          contains('targetKind physical'),
        );
        expect(
          validateConnectivityRestoreInvocation(
            receiver.copyWith(
              values: <String, Object?>{
                ...receiver.values,
                'buildArtifactSha256': 'staged-not-observed',
              },
            ),
          ),
          contains('SHA-256'),
        );
      },
    );

    test('accepts exactly three run-bound production send observations', () {
      final invocation = _invocation(role: simsTransportSenderRole);
      final texts = connectivityRestoreMessageTexts(invocation.runId);
      final result = <String, Object?>{
        'stepId': connectivityRestoreSenderStepId(invocation.runId),
        'status': 'complete',
        'success': true,
        'chatAction': <String, Object?>{
          'sent': <Map<String, Object?>>[
            for (var index = 0; index < texts.length; index += 1)
              <String, Object?>{
                'targetPeerId': 'receiver-peer',
                'text': texts[index],
                'messageId': 'message-${index + 1}',
                'transport': 'inbox',
                'status': 'inboxed',
              },
          ],
        },
      };

      expect(
        validateConnectivityRestoreSendResult(result, invocation: invocation),
        isNull,
      );
      final onlyTwo = Map<String, Object?>.from(result);
      final acceptedSends = (result['chatAction']! as Map)['sent']! as List;
      onlyTwo['chatAction'] = <String, Object?>{
        'sent': acceptedSends.take(2).toList(),
      };
      expect(
        validateConnectivityRestoreSendResult(onlyTwo, invocation: invocation),
        contains('exactly three'),
      );

      final stagedClaim = Map<String, Object?>.from(result)
        ..['chatAction'] = <String, Object?>{
          'sent': <Map<String, Object?>>[
            for (var index = 0; index < 3; index += 1)
              <String, Object?>{
                'targetPeerId': 'receiver-peer',
                'text': 'host-staged-${index + 1}',
                'messageId': 'message-${index + 1}',
                'transport': 'inbox',
                'status': 'inboxed',
              },
          ],
        };
      expect(
        validateConnectivityRestoreSendResult(
          stagedClaim,
          invocation: invocation,
        ),
        contains('run-bound'),
      );
    });

    test('restore window request must attest the exact receiver tuple', () {
      final invocation = _invocation(role: simsTransportReceiverRole);
      final request = <String, Object?>{
        'schema': connectivityRestoreWindowRequestSchema,
        'scenario': invocation.scenarioId,
        'role': invocation.role,
        'runId': invocation.runId,
        'nonce': invocation.nonce,
        'receiverNetwork': 'disconnected',
        'appForeground': true,
      };

      expect(
        validateConnectivityRestoreWindowRequest(
          request,
          invocation: invocation,
        ),
        isNull,
      );
      expect(
        validateConnectivityRestoreWindowRequest(<String, Object?>{
          ...request,
          'nonce': 'stale-nonce',
        }, invocation: invocation),
        contains('runtime tuple'),
      );
      expect(
        validateConnectivityRestoreWindowRequest(<String, Object?>{
          ...request,
          'appForeground': false,
        }, invocation: invocation),
        contains('foreground'),
      );
    });
  });
}

SimsRuntimeInvocation _invocation({required String role}) =>
    SimsRuntimeInvocation(
      schema: simsRuntimeConfigSchema,
      profileId: simsAndroidMainProfileId,
      scenarioId: simsAndroidConnectivityRestoreScenarioId,
      role: role,
      runId: 'run-connectivity-prerequisite',
      nonce: 'nonce-$role',
      values: <String, Object?>{
        'targetId': role == simsTransportSenderRole
            ? 'physical-android'
            : 'emulator-5554',
        'targetKind': role == simsTransportSenderRole ? 'physical' : 'emulator',
        'buildArtifactSha256': List<String>.filled(64, 'a').join(),
      },
    );
