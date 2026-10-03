import 'production_catalog_case.dart';

const _missed = [
  'aliceMissedWhileBobOffline1',
  'aliceMissedWhileBobOffline2',
  'aliceMissedWhileBobOffline3',
];
const _live = 'aliceLiveAfterBobDrain';

/// Texts of catalog `ir001`, identical to the original harness.
Map<String, ProductionCatalogText> productionIr001Texts(String run) => {
  for (var i = 1; i <= 3; i++)
    'aliceMissedWhileBobOffline$i': (
      role: 'alice',
      text: 'IR-001 missed while Bob offline $i $run',
    ),
  _live: (role: 'alice', text: 'IR-001 live after Bob drain $run'),
};

const productionIr001Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-missed-1',
  'alice-missed-2',
  'alice-missed-3',
  'alice-live',
];

/// IR-001. Bob goes offline by verified process death after joining; Alice
/// sends three messages Charlie receives live; Bob relaunches with his own
/// persisted state, runs one explicit production catch-up drain (mirroring
/// the original) and must hold each missed message once; then Alice's live
/// message reaches Bob and Charlie.
List<String> validateProductionGroupIr001(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'ir001',
      flows: productionIr001Flows,
      verdicts: (c) {
        final offline = proof['bobOffline'] == true;
        final relaunched = c.stage('bobRelaunched', 'bob');
        final drain = proof['bobDrain'] as Map?;
        final drained = (drain?['completedDrainCount'] as int? ?? 0) > 0;
        final aSent = [for (final k in [..._missed, _live]) c.sent('alice', k)];
        final bMissed = [for (final k in _missed) c.received('bob', k)];
        final bLive = c.received('bob', _live);
        final cMissed = [for (final k in _missed) c.received('charlie', k)];
        final cLive = c.received('charlie', _live);
        bool once(List<Map<String, Object?>?> rx) =>
            rx.every((r) => r?['persistedCount'] == 1);
        return [
          c.verdict(
            'alice',
            sent: aSent,
            extra: {
              'ir001OfflineReconnectProof': {
                'rowId': 'IR-001',
                'activeOfflineRecipientRole': 'bob',
                'missedMessageCount': aSent.take(3).whereType<Map>().length,
                'missedKeys': _missed,
                'missedMessageIds': [
                  for (final s in aSent.take(3)) s?['messageId'],
                ],
                'bobWasJoinedBeforeOffline':
                    c.stage('bobBeforeOffline', 'bob')['selfMember'] == true,
                'bobOfflineBeforeMissedSendObserved': offline,
                'bobDrainCompletedBeforeLiveSend': drained,
                'liveKey': _live,
                'liveMessageId': aSent.last?['messageId'],
              },
            },
          ),
          c.verdict(
            'bob',
            received: [...bMissed, bLive],
            extra: {
              'ir001OfflineReconnectProof': {
                'rowId': 'IR-001',
                'restoredActiveMembershipBeforeDrain':
                    relaunched['groupPresent'] == true &&
                    relaunched['selfMember'] == true,
                'drainedMissedCount': bMissed.whereType<Map>().length,
                'missedKeys': _missed,
                'receivedAllMissedExactlyOnce': once(bMissed),
                // Bob's process was verifiably dead during the three sends, so they
                // could reach him only through the offline inbox.
                'usedOfflineDrainForMissed': offline && drained,
                'liveKey': _live,
                'liveAfterDrainReceived': bLive?['persistedCount'] == 1,
                'liveAfterDrainWasLive': bLive != null && drained,
              },
            },
          ),
          c.verdict(
            'charlie',
            received: [...cMissed, cLive],
            extra: {
              'ir001OfflineReconnectProof': {
                'rowId': 'IR-001',
                'onlineControlReceivedMissedLive': once(cMissed),
                'onlineControlMissedCount': cMissed.whereType<Map>().length,
                'onlineControlReceivedLiveAfterReconnect':
                    cLive?['persistedCount'] == 1,
              },
            },
          ),
        ];
      },
    );
