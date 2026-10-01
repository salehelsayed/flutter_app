import 'production_catalog_send_sequence.dart';

/// GM-001 / DE-001: Alice's one live fanout, original key and text.
List<ProductionSendStep> productionGm001Steps(String run) => [
  ProductionSendStep('alice', 'aliceInitial', 'GM-001 alice fanout $run'),
];

/// GE-001: each member sends one message, original keys and texts.
List<ProductionSendStep> productionGe001Steps(String run) => [
  ProductionSendStep('alice', 'aliceGe001Initial', 'GE-001 alice fanout $run'),
  ProductionSendStep('bob', 'bobGe001Initial', 'GE-001 bob fanout $run'),
  ProductionSendStep(
    'charlie',
    'charlieGe001Initial',
    'GE-001 charlie fanout $run',
  ),
];

/// DE-003: one send whose app-assigned id must survive delivery and replay.
List<ProductionSendStep> productionDe003Steps(String run) => [
  ProductionSendStep('alice', 'aliceExplicit', 'DE-003 explicit id $run'),
];

List<String> validateProductionGroupGm001(Map<String, Object?> proof) =>
    validateProductionSendSequence(
      proof: proof,
      scenario: 'gm001',
      steps: productionGm001Steps(proof['runId'] as String),
      extra: (role, c) {
        final sent = c.sent['aliceInitial'];
        if (role == 'alice') {
          return {
            'de001LiveDeliveryProof': {
              'rowId': 'DE-001',
              'sentLiveText': ['sent', 'delivered'].contains(sent?['status']),
              'sentGroupId': sent?['groupId'],
              'sentMessageId': sent?['messageId'],
              'sentTimestamp': sent?['timestamp'],
              'sentKeyEpoch': sent?['keyEpoch'],
              'bobReceiptSignalObserved': c.received['bob:aliceInitial'] != null,
              'charlieReceiptSignalObserved':
                  c.received['charlie:aliceInitial'] != null,
            },
          };
        }
        final got = c.received['$role:aliceInitial'];
        return {
          'de001LiveDeliveryProof': {
            'rowId': 'DE-001',
            'receivedVisibleMessageOnce': c.finalCounts['$role:aliceInitial'] == 1,
            'matchedGroupId': got != null && got['groupId'] == sent?['groupId'],
            'matchedMessageId':
                got != null && got['messageId'] == sent?['messageId'],
            'matchedSenderPeerId':
                got != null && got['senderPeerId'] == c.peers['alice'],
            'matchedTimestamp':
                got != null && got['timestamp'] == sent?['timestamp'],
            'matchedEpoch': got != null && got['keyEpoch'] == sent?['keyEpoch'],
            'incomingVisible': got?['isIncoming'] == true,
            'receivedTimestamp': got?['timestamp'],
          },
        };
      },
    );

List<String> validateProductionGroupGe001(Map<String, Object?> proof) =>
    validateProductionSendSequence(
      proof: proof,
      scenario: 'ge001',
      steps: productionGe001Steps(proof['runId'] as String),
      extra: (_, _) => const {},
    );

/// DE-003. The receivers' `duplicateReplayDeduped` reads the row count after
/// the production catch-up drain the runner triggers (`deReplay:<role>`).
List<String> validateProductionGroupDe003(Map<String, Object?> proof) =>
    validateProductionSendSequence(
      proof: proof,
      scenario: 'de003',
      steps: productionDe003Steps(proof['runId'] as String),
      extra: (role, c) {
        final sent = c.sent['aliceExplicit'];
        if (role == 'alice') {
          return {
            'de003MessageIdProof': {
              'rowId': 'DE-003',
              'requestedMessageId': sent?['messageId'],
              'returnedMessageId': sent?['messageId'],
              'publishPathMessageIdPreserved': [
                'sent',
                'delivered',
              ].contains(sent?['status']),
              'replayEnvelopeCoveredByHostGate': true,
              'retryPathCoveredByHostGate': true,
            },
          };
        }
        final got = c.received['$role:aliceExplicit'];
        final replay = c.proof['deReplay:$role'] as Map?;
        return {
          'de003MessageIdProof': {
            'rowId': 'DE-003',
            'requestedMessageId': sent?['messageId'],
            'receivedMessageId': got?['messageId'],
            'receivedExplicitMessageOnce':
                c.finalCounts['$role:aliceExplicit'] == 1,
            'matchedRequestedMessageId':
                got != null && got['messageId'] == sent?['messageId'],
            'duplicateReplayDeduped':
                replay != null &&
                (replay['completedDrainCount'] as int? ?? 0) > 0 &&
                c.finalCounts['$role:aliceExplicit'] == 1,
          },
        };
      },
    );
