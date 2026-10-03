import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _key = 'aliceGe010ZeroPeerFallback';
const _proof = 'ge010ZeroLivePeersInboxFallbackProof';

/// Texts of catalog `ge010` and `go001` (one original role script), identical
/// to the original harness.
Map<String, ProductionCatalogText> productionGe010Texts(String run) => {
  _key: (role: 'alice', text: 'GE-010 Alice zero live topic peers $run'),
};

const productionGe010Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-zero-peer',
];

/// GE-010 / GO-001. Bob and Charlie leave the live topic by verified process
/// death; Alice sends with zero topic peers (production `successNoPeers`,
/// inbox custody, row stays sent); both relaunch with their own state, run
/// one production catch-up drain and must hold the message once, never
/// received live.
List<String> validateProductionGroupGe010(
  Map<String, Object?> proof, {
  String scenario = 'ge010',
}) => validateProductionCatalogCase(
  proof: proof,
  scenario: scenario,
  flows: productionGe010Flows,
  verdicts: (c) {
    final sent = c.sentFanout('alice', _key);
    final row = productionCatalogRows(c.finalOf('alice'), _key);
    final statusSent = row.length == 1 && row.single['status'] == 'sent';
    final inbox = sent?['inboxStored'] == true;
    bool offline(String r) => proof['${r}Offline'] == true;
    Map<String, Object?> receiver(String r) {
      final before = c.stage('${r}BeforeOffline', r);
      final back = c.stage('${r}Relaunched', r);
      final drain = proof['${r}Drain'] as Map?;
      final got = c.received(r, _key);
      final count = c.finalCount(r, _key);
      return {
        'leftLiveTopicBeforeSend': offline(r),
        'rejoinedLiveTopicAfterSend':
            back['groupPresent'] == true && back['selfMember'] == true,
        'drainedInboxAfterReturn':
            (drain?['completedDrainCount'] as int? ?? 0) > 0 &&
            got != null &&
            !c.live(r, _key),
        'receivedZeroPeerMessage': got != null,
        'noDuplicatePersistence': count == 1,
        'noLiveDeliveryDuringSendWindow': !c.live(r, _key),
        'senderEligibleAtSend':
            before['selfMember'] == true &&
            c.members(before).contains(c.peers['alice']),
        'postDrainPersistedCount': count,
        'receivedKeys': [if (got != null) _key],
        'finalMemberPeerIds': c.finalOf(r)['memberPeerIds'],
        'finalKeyEpoch': c.epoch(r),
      };
    }

    return [
      c.verdict(
        'alice',
        sent: [sent],
        extra: {
          _proof: {
            'bobLeftLiveTopicBeforeSend': offline('bob'),
            'charlieLeftLiveTopicBeforeSend': offline('charlie'),
            'zeroLiveTopicPeersAtSend': sent?['topicPeers'] == 0,
            'successNoPeers': sent?['outcome'] == 'successNoPeers',
            'senderStatusSent': statusSent,
            'inboxStored': inbox,
            'actualDurablePayloadProof':
                sent?['actualDurablePayloadProof'] == true,
            'honestSenderFallbackStatus': statusSent && inbox,
            'noLiveDeliveryDuringSendWindow':
                sent?['topicPeers'] == 0 &&
                !c.live('bob', _key) &&
                !c.live('charlie', _key),
            'topicPeersAtSend': sent?['topicPeers'],
            'sentKeys': [if (sent != null) _key],
            'finalMemberPeerIds': c.finalOf('alice')['memberPeerIds'],
            'finalKeyEpoch': c.epoch('alice'),
          },
        },
      ),
      for (final r in ['bob', 'charlie'])
        c.verdict(
          r,
          received: [c.received(r, _key)],
          extra: {_proof: receiver(r)},
        ),
    ];
  },
);

/// GO-001 runs the GE-010 role scripts under its own scenario id.
List<String> validateProductionGroupGo001(Map<String, Object?> proof) =>
    validateProductionGroupGe010(proof, scenario: 'go001');
