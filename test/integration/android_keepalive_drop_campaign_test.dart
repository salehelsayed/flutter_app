import 'package:flutter_app/core/debug/keepalive_drop_e2e_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_keepalive_drop_campaign.dart';
import '../../integration_test/support/sims_runtime_protocol.dart';
import '../../tool/sims/device_criteria.dart';

void main() {
  const messageId = 'a1b2c3d4-1111-2222-3333-444455556666';
  final invocation = SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: keepaliveDropProfileId,
    scenarioId: keepaliveDropScenarioId,
    role: 'sender',
    runId: 'run-keepalive',
    nonce: 'nonce-keepalive',
    values: const <String, Object?>{
      'targetId': 'physical-android',
      'targetKind': 'physical',
      'buildArtifactSha256':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    },
  );

  test('send and recovery merge into message-correlated passing evidence', () {
    final send = _send(invocation, messageId);
    final recovery = _recovery(invocation, messageId);
    expect(validateKeepaliveCampaignInvocation(invocation), isNull);
    expect(
      validateKeepaliveDroppedSendResult(
        send,
        invocation: invocation,
        targetPeerId: 'peer-b',
      ),
      isNull,
    );
    expect(
      validateKeepaliveRecoveryResult(
        recovery,
        invocation: invocation,
        messageId: messageId,
      ),
      isNull,
    );
    final artifact = assembleKeepaliveDropArtifact(
      sendResult: send,
      recoveryResult: recovery,
      deviceIds: const <String>['physical-android', 'android-emulator'],
    );
    expect(validateKeepaliveDropArtifact(artifact).ok, isTrue);
  });

  test('wrong-message receipt and a dial in the send window fail closed', () {
    final recovery = _recovery(invocation, messageId);
    (recovery['receiptEvent']! as Map<String, Object?>)['messageIdPrefix'] =
        'deadbeef';
    expect(
      validateKeepaliveRecoveryResult(
        recovery,
        invocation: invocation,
        messageId: messageId,
      ),
      contains('another message'),
    );

    final send = _send(invocation, messageId);
    (send['sendWindowEvents']! as List<String>).add(
      'P2P_SERVICE_DIAL_PEER_BEGIN',
    );
    expect(
      validateKeepaliveDroppedSendResult(
        send,
        invocation: invocation,
        targetPeerId: 'peer-b',
      ),
      contains('direct attempt'),
    );
  });
}

Map<String, Object?> _send(
  SimsRuntimeInvocation invocation,
  String messageId,
) => <String, Object?>{
  'schema': keepaliveDroppedSendResultSchema,
  'profileId': invocation.profileId,
  'scenario': invocation.scenarioId,
  'role': invocation.role,
  'runId': invocation.runId,
  'nonce': invocation.nonce,
  'stepId': keepaliveDroppedSendStepId(invocation.runId),
  'status': 'complete',
  'success': true,
  'messageId': messageId,
  'messageIdPrefix': 'a1b2c3d4',
  'text': keepaliveRunMessageText(invocation.runId),
  'transport': 'inbox',
  'messageStatus': 'inboxed',
  'dropLatchedBeforeSend': true,
  'dropLatchedAfterSend': true,
  'connectedBeforeSend': false,
  'localBeforeSend': false,
  'sendWindowEvents': <String>[
    'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
    'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
    'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP',
  ],
  'messageEvents': <Map<String, Object?>>[
    <String, Object?>{
      'event': 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
      'eventIndex': 0,
      'messageIdPrefix': 'a1b2c3d4',
    },
    <String, Object?>{
      'event': 'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
      'eventIndex': 1,
      'messageIdPrefix': 'a1b2c3d4',
    },
  ],
  'custodyLatencyMs': 180,
};

Map<String, Object?> _recovery(
  SimsRuntimeInvocation invocation,
  String messageId,
) => <String, Object?>{
  'schema': keepaliveRecoveryResultSchema,
  'profileId': invocation.profileId,
  'scenario': invocation.scenarioId,
  'role': invocation.role,
  'runId': invocation.runId,
  'nonce': invocation.nonce,
  'stepId': keepaliveRecoveryStepId(invocation.runId),
  'status': 'complete',
  'success': true,
  'messageIdPrefix': keepaliveMessageIdPrefix(messageId),
  'dropLatchedAfterRecovery': false,
  'messageStatus': 'delivered',
  'events': <String>[
    'DELIVERY_RECEIPT_APPLIED',
    'P2P_SERVICE_PEER_PING_SUCCESS',
  ],
  'receiptEvent': <String, Object?>{
    'event': 'DELIVERY_RECEIPT_APPLIED',
    'eventIndex': 0,
    'messageIdPrefix': 'a1b2c3d4',
  },
  'postDropPeerPingObserved': true,
};
