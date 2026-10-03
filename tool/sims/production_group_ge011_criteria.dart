import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _key = 'aliceGe011PartialLiveFallback';
const _proof = 'ge011PartialLivePeersInboxFallbackProof';

/// Texts of catalog `ge011`, identical to the original harness.
Map<String, ProductionCatalogText> productionGe011Texts(String run) => {
  _key: (role: 'alice', text: 'GE-011 Alice partial live topic peers $run'),
};

const productionGe011Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-partial-live',
];

/// GE-011. Charlie leaves the live topic by verified process death while Bob
/// stays; Alice sends with exactly one topic peer (production `success`,
/// `partial_peers`, inbox custody); Bob receives live and a later catch-up
/// drain adds no copy; Charlie relaunches with his own state and recovers the
/// message once from the offline inbox.
List<String> validateProductionGroupGe011(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'ge011',
      flows: productionGe011Flows,
      verdicts: (c) {
        final sent = c.sentFanout('alice', _key);
        final row = productionCatalogRows(c.finalOf('alice'), _key);
        final statusSent = row.length == 1 && row.single['status'] == 'sent';
        final inbox = sent?['inboxStored'] == true;
        final charlieOffline = proof['charlieOffline'] == true;
        final bobLive = c.live('bob', _key);
        final charlieLive = c.live('charlie', _key);
        int drained(String r) =>
            ((proof['${r}Drain'] as Map?)?['completedDrainCount'] as int?) ?? 0;
        bool eligible(String r) {
          final before = c.stage('${r}BeforeSend', r);
          return before['selfMember'] == true &&
              c.members(before).contains(c.peers['alice']);
        }

        final bobGot = c.received('bob', _key);
        final charlieGot = c.received('charlie', _key);
        final charlieBack = c.stage('charlieRelaunched', 'charlie');
        return [
          c.verdict(
            'alice',
            sent: [sent],
            extra: {
              _proof: {
                'bobLiveTopicPeerAtSend':
                    sent?['topicPeers'] == 1 && charlieOffline && bobLive,
                'charlieLeftLiveTopicBeforeSend': charlieOffline,
                'partialLiveTopicPeersAtSend':
                    sent?['liveFanoutState'] == 'partial_peers',
                'liveDeliveryToBobDuringSendWindow': bobLive,
                'noLiveDeliveryToCharlieDuringSendWindow': !charlieLive,
                'senderStatusSent': statusSent,
                'inboxStored': inbox,
                'actualDurablePayloadProof':
                    sent?['actualDurablePayloadProof'] == true,
                'honestPartialFallbackStatus':
                    statusSent &&
                    inbox &&
                    sent?['liveFanoutState'] == 'partial_peers',
                'topicPeersAtSend': sent?['topicPeers'],
                'sentKeys': [if (sent != null) _key],
                'finalMemberPeerIds': c.finalOf('alice')['memberPeerIds'],
                'finalKeyEpoch': c.epoch('alice'),
              },
            },
          ),
          c.verdict(
            'bob',
            received: [bobGot],
            extra: {
              _proof: {
                'liveTopicPeerAtSend': sent?['topicPeers'] == 1 && bobLive,
                'receivedLiveDuringSendWindow': bobLive,
                'drainedDuplicateInboxAfterLive':
                    bobLive && drained('bob') > 0,
                'noDuplicatePersistence': c.finalCount('bob', _key) == 1,
                'senderEligibleAtSend': eligible('bob'),
                'postDrainPersistedCount': c.finalCount('bob', _key),
                'receivedKeys': [if (bobGot != null) _key],
                'finalMemberPeerIds': c.finalOf('bob')['memberPeerIds'],
                'finalKeyEpoch': c.epoch('bob'),
              },
            },
          ),
          c.verdict(
            'charlie',
            received: [charlieGot],
            extra: {
              _proof: {
                'leftLiveTopicBeforeSend': charlieOffline,
                'rejoinedLiveTopicAfterSend':
                    charlieBack['groupPresent'] == true &&
                    charlieBack['selfMember'] == true,
                'drainedInboxAfterReturn':
                    drained('charlie') > 0 && charlieGot != null,
                'receivedInboxMessage': charlieGot != null && !charlieLive,
                'noLiveDeliveryDuringSendWindow': !charlieLive,
                'noDuplicatePersistence': c.finalCount('charlie', _key) == 1,
                'senderEligibleAtSend': eligible('charlie'),
                'postDrainPersistedCount': c.finalCount('charlie', _key),
                // Charlie's process was verifiably dead from before the send
                // until relaunch; this is his last snapshot before death.
                'preRejoinPlaintextCount': productionCatalogRows(
                  c.stage('charlieBeforeSend', 'charlie'),
                  _key,
                ).length,
                'receivedKeys': [if (charlieGot != null) _key],
                'finalMemberPeerIds': c.finalOf('charlie')['memberPeerIds'],
                'finalKeyEpoch': c.epoch('charlie'),
              },
            },
          ),
        ];
      },
    );
