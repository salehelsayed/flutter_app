import 'package:flutter_app/core/debug/keepalive_drop_e2e_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dropped-send request is exact-profile/run/text bound', () {
    final request = <String, Object?>{
      'schema': keepaliveDroppedSendRequestSchema,
      'profileId': keepaliveDropProfileId,
      'scenario': keepaliveDropScenarioId,
      'role': 'sender',
      'transport_action': keepaliveDroppedSendAction,
      'runId': 'run-keepalive-1',
      'nonce': 'nonce-keepalive-1',
      'stepId': keepaliveDroppedSendStepId('run-keepalive-1'),
      'targetPeerId': 'peer-b',
      'text': keepaliveRunMessageText('run-keepalive-1'),
    };
    expect(
      validateKeepaliveDroppedSendRequest(
        request,
        installedProfileId: keepaliveDropProfileId,
      ),
      isNull,
    );
    request['text'] = 'unbound';
    expect(
      validateKeepaliveDroppedSendRequest(
        request,
        installedProfileId: keepaliveDropProfileId,
      ),
      contains('text'),
    );
    request['text'] = keepaliveRunMessageText('run-keepalive-1');
    expect(
      validateKeepaliveDroppedSendRequest(
        request,
        installedProfileId: 'android.e2e.standard',
      ),
      contains(keepaliveDropProfileId),
    );
  });

  test('recovery request requires the exact returned UUID', () {
    final request = <String, Object?>{
      'schema': keepaliveRecoveryRequestSchema,
      'profileId': keepaliveDropProfileId,
      'scenario': keepaliveDropScenarioId,
      'role': 'sender',
      'transport_action': keepaliveRecoveryObserveAction,
      'runId': 'run-keepalive-2',
      'nonce': 'nonce-keepalive-2',
      'stepId': keepaliveRecoveryStepId('run-keepalive-2'),
      'targetPeerId': 'peer-b',
      'messageId': 'a1b2c3d4-1111-2222-3333-444455556666',
    };
    expect(
      validateKeepaliveRecoveryRequest(
        request,
        installedProfileId: keepaliveDropProfileId,
      ),
      isNull,
    );
    request['messageId'] = 'not-a-message';
    expect(
      validateKeepaliveRecoveryRequest(
        request,
        installedProfileId: keepaliveDropProfileId,
      ),
      contains('messageId'),
    );
  });
}
