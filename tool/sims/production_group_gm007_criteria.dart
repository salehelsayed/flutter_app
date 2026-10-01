import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _before = 'aliceBeforeCharlieRemoval';
const _after = 'aliceAfterCharlieReadd';
const _during = [
  'aliceDuringCharlieRemoval1',
  'aliceDuringCharlieRemoval2',
  'aliceDuringCharlieRemoval3',
];

/// Texts of catalog `gm007`, identical to the original harness.
Map<String, ProductionCatalogText> productionGm007Texts(String run) => {
  _before: (role: 'alice', text: 'GM-007 Alice before Charlie removal $run'),
  for (var i = 1; i <= 3; i++)
    'aliceDuringCharlieRemoval$i': (
      role: 'alice',
      text: 'GM-007 Alice during Charlie removal $i $run',
    ),
  _after: (role: 'alice', text: 'GM-007 Alice after Charlie re-add $run'),
};

const productionGm007Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-before-removal',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-during-1',
  'alice-during-2',
  'alice-during-3',
  'readd-charlie',
  'charlie-home',
  'accept-charlie-readd',
  'alice-after-readd',
];

List<String> validateProductionGroupGm007(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'gm007',
      flows: productionGm007Flows,
      verdicts: (c) {
        final alice = '${c.peers['alice']}';
        final bob = '${c.peers['bob']}';
        final charlie = '${c.peers['charlie']}';
        final removed = !c
            .members(c.stage('aliceRemoved', 'alice'))
            .contains(charlie);
        final aBefore = c.sent('alice', _before);
        final aDuring = [for (final k in _during) c.sent('alice', k)];
        final aAfter = c.sent('alice', _after);
        final bBefore = c.received('bob', _before);
        final bDuring = [for (final k in _during) c.received('bob', k)];
        final bAfter = c.received('bob', _after);
        final cBefore = c.received('charlie', _before);
        final cAfter = c.received('charlie', _after);
        final window = c.stage('charlieRemovedWindow', 'charlie');
        final beforeDrain = c.stage('charlieBeforeDrain', 'charlie');
        final drain = proof['charlieDrain'] as Map?;
        var leak = 0;
        for (final k in _during) {
          leak +=
              productionCatalogRows(window, k).length +
              c.finalCount('charlie', k);
        }
        final countBeforeDrain = productionCatalogRows(
          beforeDrain,
          _after,
        ).length;
        int? ep(Map? m) => m?['keyEpoch'] as int?;
        final sentDuring = aDuring.whereType<Map>().length;
        final gotDuring = bDuring.whereType<Map>().length;
        bool includes(String role, Iterable<String> ids) =>
            c.members(c.finalOf(role)).containsAll(ids);
        final epochs = {for (final r in const ['alice', 'bob', 'charlie']) r: c.epoch(r)};
        return [
          c.verdict(
            'alice',
            sent: [aBefore, ...aDuring, aAfter],
            extra: {
              'gm007HistoryBoundaryProof': {
                'removedCharlie': removed,
                'readdedCharlie': includes('alice', [charlie]),
                'sentPreRemovalBeforeRemove': aBefore != null,
                'sentPostReaddAfterReadd': aAfter != null,
                'removedPeerId': charlie,
                'memberListIncludesCharlie': includes('alice', [charlie]),
                'sentRemovedWindowWhileRemoved': sentDuring == 3,
                'finalEpoch': epochs['alice'],
              },
              for (final (name, row) in const [
                ('ke018HistoryReplayEpochWindowProof', 'KE-018'),
                ('ir005ReaddReplayProof', 'IR-005'),
              ])
                name: {
                  'rowId': row,
                  'sentPreRemovalReplayWindow': ep(aBefore) == 1,
                  'sentRemovedWindowWhileCharlieRemoved': sentDuring == 3,
                  'sentRemovedWindowCount': sentDuring,
                  'sentPostReaddReplayWindow': (ep(aAfter) ?? 0) >= 2,
                  if (row == 'IR-005') 'readdedCharlie': includes('alice', [charlie]),
                  'memberListIncludesCharlie': includes('alice', [charlie]),
                  'finalEpoch': epochs['alice'],
                },
            },
          ),
          c.verdict(
            'bob',
            received: [bBefore, ...bDuring, bAfter],
            extra: {
              'gm007HistoryBoundaryProof': {
                'memberListIncludesCharlie': includes('bob', [charlie]),
                'receivedPreRemovalMessage': bBefore != null,
                'receivedPostReaddMessage': bAfter != null,
                'receivedRemovedWindowMessageCount': gotDuring,
                'finalEpoch': epochs['bob'],
              },
              for (final (name, row) in const [
                ('ke018HistoryReplayEpochWindowProof', 'KE-018'),
                ('ir005ReaddReplayProof', 'IR-005'),
              ])
                name: {
                  'rowId': row,
                  'receivedPreRemovalReplayWindow': ep(bBefore) == 1,
                  'receivedRemovedWindowWhileCharlieRemoved': gotDuring == 3,
                  'receivedRemovedWindowCount': gotDuring,
                  'receivedPostReaddReplayWindow': (ep(bAfter) ?? 0) >= 2,
                  'memberListIncludesCharlie': includes('bob', [charlie]),
                  'finalEpoch': epochs['bob'],
                },
            },
          ),
          c.verdict(
            'charlie',
            received: [cBefore, cAfter],
            extra: {
              'gm007HistoryBoundaryProof': {
                'memberListIncludesAliceBob': includes('charlie', [alice, bob]),
                'memberListIncludesCharlie': includes('charlie', [charlie]),
                'receivedPreRemovalMessage': cBefore != null,
                'receivedPostReaddMessage': cAfter != null,
                'removedWindowPlaintextCount': leak,
                'hasStaleEpochAfterReadd': epochs['charlie']! < 2,
                'finalEpoch': epochs['charlie'],
              },
              for (final (name, row) in const [
                ('ke018HistoryReplayEpochWindowProof', 'KE-018'),
                ('ir005ReaddReplayProof', 'IR-005'),
              ])
                name: {
                  'rowId': row,
                  if (row == 'KE-018')
                    'receivedPreRemovalReplayWindow': ep(cBefore) == 1
                  else
                    'receivedAllowedPreRemovalHistory': ep(cBefore) == 1,
                  'postReaddMissingBeforeDrain': countBeforeDrain == 0,
                  'postReaddLiveBeforeDrain': countBeforeDrain > 0,
                  if (row == 'KE-018')
                    'drainedPostReaddReplayAtCurrentEpoch':
                        drain?['completedDrainCount'] == 1 &&
                        (ep(cAfter) ?? 0) >= 2
                  else
                    'receivedPostReaddReplayAfterDrain':
                        drain?['completedDrainCount'] == 1 &&
                        (ep(cAfter) ?? 0) >= 2,
                  'noRemovedWindowReplayAfterDrain': leak == 0,
                  'memberListIncludesAliceBobCharlie': includes('charlie', [
                    alice,
                    bob,
                    charlie,
                  ]),
                  'removedWindowPlaintextCount': leak,
                  'preRemovalReplayEpoch': ep(cBefore),
                  'postReaddReplayEpoch': ep(cAfter),
                  'finalEpoch': epochs['charlie'],
                },
            },
          ),
        ];
      },
    );
