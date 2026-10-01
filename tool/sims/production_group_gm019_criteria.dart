import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _window = 'aliceGm019RemovedWindow';
const _aliceAfter = 'aliceGm019AfterReadd';
const _bobAfter = 'bobGm019AfterReadd';

/// Texts of catalog `gm019`, identical to the original harness.
Map<String, ProductionCatalogText> productionGm019Texts(String run) => {
  _window: (role: 'alice', text: 'GM-019 Alice while Charlie removed $run'),
  _aliceAfter: (role: 'alice', text: 'GM-019 Alice after Charlie re-add $run'),
  _bobAfter: (role: 'bob', text: 'GM-019 Bob after Charlie re-add $run'),
};

const productionGm019Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-removed-window',
  'readd-charlie',
  'charlie-home',
  'accept-charlie-readd',
  'alice-after-readd',
  'bob-after-readd',
];

/// GM-019. The original forces send timestamps one second after its own
/// removal and re-add times; production stamps sends itself, so the adapter
/// reports the real removal and re-add event times (Alice's
/// `lastMembershipEventAt`) and the real send timestamps, and the original's
/// ordering rule is checked against those.
List<String> validateProductionGroupGm019(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'gm019',
      flows: productionGm019Flows,
      verdicts: (c) {
        final charlie = '${c.peers['charlie']}';
        final removedAt = c.stage('aliceRemoved', 'alice')['lastMembershipEventAt'];
        final readdAt = c.finalOf('alice')['lastMembershipEventAt'];
        final window = c.sent('alice', _window);
        final aliceAfter = c.sent('alice', _aliceAfter);
        final bobAfter = c.sent('bob', _bobAfter);
        List rc(Map? m) => (m?['recipientPeerIds'] as List?) ?? const [];
        final leak =
            productionCatalogRows(
              c.stage('charlieRemovedWindow', 'charlie'),
              _window,
            ).length +
            c.finalCount('charlie', _window);
        final charlieGotAlice = c.received('charlie', _aliceAfter);
        final charlieGotBob = c.received('charlie', _bobAfter);
        return [
          c.verdict(
            'alice',
            sent: [window, aliceAfter],
            received: [c.received('alice', _bobAfter)],
            extra: {
              'gm019DurableRecipientWindowProof': {
                'actualDurablePayloadProof':
                    window?['actualDurablePayloadProof'] == true &&
                    aliceAfter?['actualDurablePayloadProof'] == true,
                'removedPeerId': charlie,
                'removedAt': removedAt,
                'removedWindowSentAt': window?['timestamp'],
                'readdAt': readdAt,
                'postReaddSentAt': aliceAfter?['timestamp'],
                'removedWindowExcludedCharlie':
                    window != null && !rc(window).contains(charlie),
                'postReaddIncludedCharlie': rc(aliceAfter).contains(charlie),
              },
            },
          ),
          c.verdict(
            'bob',
            sent: [bobAfter],
            received: [
              c.received('bob', _window),
              c.received('bob', _aliceAfter),
            ],
            extra: {
              'gm019DurableRecipientWindowProof': {
                'actualDurablePayloadProof':
                    bobAfter?['actualDurablePayloadProof'] == true,
                'bobPostReaddSent': bobAfter?['outcome'] == 'success',
                'receivedAliceRemovedWindow': true,
              },
            },
          ),
          c.verdict(
            'charlie',
            received: [charlieGotAlice, charlieGotBob],
            extra: {
              'gm019DurableRecipientWindowProof': {
                'receivedRemovedWindowMessage': leak > 0,
                'removedWindowPlaintextCount': leak,
                'receivedAlicePostReadd': charlieGotAlice != null,
                'receivedBobPostReadd': charlieGotBob != null,
              },
            },
          ),
        ];
      },
    );
