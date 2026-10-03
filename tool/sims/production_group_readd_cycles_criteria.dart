import 'production_catalog_case.dart';

const productionMl008Cycles = 20;

String productionMl008RemovedKey(int c) => 'ml008AliceRemovedWindow$c';
String productionMl008AlicePostKey(int c) => 'ml008AlicePostReadd$c';
String productionMl008CharliePostKey(int c) => 'ml008CharliePostReadd$c';

/// The role restarted after cycle [c] (5, 15: Charlie; 10, 20: Bob).
String? productionMl008RestartRole(int c) =>
    c % 5 != 0 ? null : ((c ~/ 5).isOdd ? 'charlie' : 'bob');

/// Texts of catalog `private_readd_cycles` (ML-008), identical to the
/// original harness.
Map<String, ProductionCatalogText> productionMl008Texts(String run) => {
  for (var c = 1; c <= productionMl008Cycles; c++) ...{
    productionMl008RemovedKey(c): (
      role: 'alice',
      text: 'ML-008 Alice removed window cycle $c $run',
    ),
    productionMl008AlicePostKey(c): (
      role: 'alice',
      text: 'ML-008 Alice post re-add cycle $c $run',
    ),
    productionMl008CharliePostKey(c): (
      role: 'charlie',
      text: 'ML-008 Charlie post re-add cycle $c $run',
    ),
  },
};

List<String> productionMl008Flows() => [
  'create',
  'accept-bob',
  'accept-charlie',
  for (var c = 1; c <= productionMl008Cycles; c++) ...[
    'remove-charlie',
    'alice-back-to-chat',
    'alice-removed-$c',
    'readd-charlie',
    'charlie-home',
    'accept-charlie-readd',
    'alice-post-$c',
    'charlie-post-$c',
  ],
];

/// ML-008: twenty UI remove/re-add cycles with kill-and-relaunch restarts
/// (Charlie after cycles 5 and 15, Bob after 10 and 20; the original only
/// restarts the group listener). Counts come from the final snapshots.
List<String> validateProductionGroupReaddCycles(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'private_readd_cycles',
      flows: productionMl008Flows(),
      verdicts: (c) {
        final all = {for (final r in const ['alice', 'bob', 'charlie']) '${c.peers[r]}'};
        final cycles = [for (var i = 1; i <= productionMl008Cycles; i++) i];
        int incoming(String role, String Function(int) key) => cycles
            .where((i) => c.receivedAtEnd(role, key(i)) != null)
            .length;
        int outgoing(String role, String Function(int) key) => cycles
            .where((i) => c.sent(role, key(i))?['accepted'] == true)
            .length;
        var leak = 0;
        for (final i in cycles) {
          leak += c.finalCount('charlie', productionMl008RemovedKey(i));
        }
        final restarts = {
          for (final i in cycles)
            if (productionMl008RestartRole(i) case final r?)
              i: (role: r, ok: proof['restart:$i'] == true),
        };
        int performed(String role) =>
            restarts.values.where((r) => r.role == role && r.ok).length;
        final exactRows = [
          for (final i in cycles)
            if (proof['bobCharlieRows:$i'] == 1) i,
        ].length;
        final selfRemovals = [
          for (final i in cycles)
            if (proof['charlieSelfRemoved:$i'] == true) i,
        ].length;
        Map<String, Object?> proofFor(String role, Map<String, Object?> f) => {
          'ml008CycleProof': {
            'rowId': 'ML-008',
            'cycleCount': proof['completedCycles'],
            'finalMemberListIncludesAliceBobCharlie': c
                .members(c.finalOf(role))
                .containsAll(all),
            ...f,
            'finalEpoch': c.epoch(role),
          },
        };
        return [
          c.verdict(
            'alice',
            extra: proofFor('alice', {
              'removedWindowSendCount': outgoing(
                'alice',
                productionMl008RemovedKey,
              ),
              'sentPostReaddCount': outgoing('alice', productionMl008AlicePostKey),
              'receivedCharliePostReaddCount': incoming(
                'alice',
                productionMl008CharliePostKey,
              ),
              'restartMarkersObserved': restarts.values.where((r) => r.ok).length,
            }),
          ),
          c.verdict(
            'bob',
            extra: proofFor('bob', {
              'receivedRemovedWindowCount': incoming(
                'bob',
                productionMl008RemovedKey,
              ),
              'receivedAlicePostReaddCount': incoming(
                'bob',
                productionMl008AlicePostKey,
              ),
              'receivedCharliePostReaddCount': incoming(
                'bob',
                productionMl008CharliePostKey,
              ),
              'bobCharlieExactMemberRowCountProofs': exactRows,
              'restartMarkersPerformed': performed('bob'),
            }),
          ),
          c.verdict(
            'charlie',
            extra: proofFor('charlie', {
              'selfRemovalCount': selfRemovals,
              'receivedAlicePostReaddCount': incoming(
                'charlie',
                productionMl008AlicePostKey,
              ),
              'postReaddSendCount': outgoing(
                'charlie',
                productionMl008CharliePostKey,
              ),
              'removedWindowPlaintextCount': leak,
              'restartMarkersPerformed': performed('charlie'),
            }),
          ),
        ];
      },
    );
