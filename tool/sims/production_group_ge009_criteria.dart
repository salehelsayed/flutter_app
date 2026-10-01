import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _aBefore = 'aliceGe009BeforePartition';
const _bBefore = 'bobGe009BeforePartition';
const _cBefore = 'charlieGe009BeforePartition';
const _aPost = 'aliceGe009PostReadd';
const _bPost = 'bobGe009PostReadd';
const _cHeal = 'charlieGe009AfterHeal';
const _all = [_aBefore, _bBefore, _cBefore, _aPost, _bPost, _cHeal];

/// Texts of catalog `ge009`, identical to the original harness.
Map<String, ProductionCatalogText> productionGe009Texts(String run) => {
  _aBefore: (role: 'alice', text: 'GE-009 Alice before partition $run'),
  _bBefore: (role: 'bob', text: 'GE-009 Bob before partition $run'),
  _cBefore: (role: 'charlie', text: 'GE-009 Charlie before partition $run'),
  _aPost: (
    role: 'alice',
    text: 'GE-009 Alice post re-add while Charlie partitioned $run',
  ),
  _bPost: (
    role: 'bob',
    text: 'GE-009 Bob post re-add while Charlie partitioned $run',
  ),
  _cHeal: (role: 'charlie', text: 'GE-009 Charlie after partition heal $run'),
};

const productionGe009Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-before',
  'bob-before',
  'charlie-before',
  'remove-charlie',
  'alice-back-to-chat',
  'readd-charlie',
  'alice-post-readd',
  'bob-post-readd',
  'charlie-home',
  'accept-charlie-readd',
  'charlie-after-heal',
];

/// GE-009. The original's partition is Charlie delaying the import of his
/// re-add; in production Charlie delays accepting the re-add invitation
/// while Alice and Bob exchange their post-re-add messages, then accepts and
/// catches up through the app's own replay.
List<String> validateProductionGroupGe009(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'ge009',
      flows: productionGe009Flows,
      verdicts: (c) {
        final charlie = '${c.peers['charlie']}';
        final allPeers = {for (final r in const ['alice', 'bob', 'charlie']) '${c.peers[r]}'};
        final partitioned = c.stage('charliePartitioned', 'charlie');
        final partitionLeak =
            productionCatalogRows(partitioned, _aPost).length +
            productionCatalogRows(partitioned, _bPost).length;
        final removed = !c
            .members(c.stage('aliceRemoved', 'alice'))
            .contains(charlie);
        final sentKeys = {
          'alice': [_aBefore, _aPost],
          'bob': [_bBefore, _bPost],
          'charlie': [_cBefore, _cHeal],
        };
        final gotKeys = {
          'alice': [_bBefore, _cBefore, _bPost, _cHeal],
          'bob': [_aBefore, _cBefore, _aPost, _cHeal],
          'charlie': [_aBefore, _bBefore, _aPost, _bPost],
        };
        final epochs = {for (final r in const ['alice', 'bob', 'charlie']) r: c.epoch(r)};
        return [
          for (final role in const ['alice', 'bob', 'charlie'])
            () {
              final sent = [for (final k in sentKeys[role]!) c.sent(role, k)];
              final got = [for (final k in gotKeys[role]!) c.received(role, k)];
              final members = c.members(c.finalOf(role));
              final timeline = [
                for (final k in _all)
                  if (c.finalCount(role, k) == 1) k,
              ];
              bool has(String k) => got.any((g) => g?['key'] == k);
              final common = {
                'partitionedDuringMembershipMutation': partitionLeak == 0,
                'removedAndReaddedCharlie': removed && members.contains(charlie),
                'partitionHealed': c.finalOf('charlie')['selfMember'] == true,
                'finalMembershipConverged': members.containsAll(allPeers),
                'finalTimelineConverged': timeline.length == 6,
                'finalTimelineKeys': timeline,
                'duplicateDeliveryDeduped': got.every(
                  (g) => g?['persistedCount'] == 1,
                ),
                'finalMessageCount': timeline.length,
                'finalMemberPeerIds': members.toList()..sort(),
                'finalEpoch': epochs[role],
              };
              final Map<String, Object?> specific;
              if (role == 'charlie') {
                specific = {
                  'isolatedFromLiveTopicDuringMutation': partitionLeak == 0,
                  'drainedReplayAfterHeal': has(_aPost) && has(_bPost),
                  'receivedAliceBobReplayAfterHeal': has(_aPost) && has(_bPost),
                  'postHealPublishAccepted': sent.last?['accepted'] == true,
                  'removedWindowPlaintextCount': partitionLeak,
                  'receivedPrePartitionKeys': [
                    for (final k in const [_aBefore, _bBefore])
                      if (has(k)) k,
                  ],
                  'postReaddReplayKeys': [
                    for (final k in const [_aPost, _bPost])
                      if (has(k)) k,
                  ],
                };
              } else {
                final other = role == 'alice' ? 'bob' : 'alice';
                final afterRemoval = role == 'alice'
                    ? c.stage('aliceRemoved', 'alice')
                    : c.stage('bobExcluded', 'bob');
                final otherPost = other == 'bob' ? _bPost : _aPost;
                specific = {
                  'charlieExcludedDuringPartition': !c
                      .members(afterRemoval)
                      .contains(charlie),
                  'postReaddDurableIncludedCharlie':
                      ((sent.last?['recipientPeerIds'] as List?) ?? const [])
                          .contains(charlie),
                  role == 'alice'
                      ? 'receivedBobPostReaddReplay'
                      : 'receivedAlicePostReaddReplay': has(otherPost),
                  'receivedCharlieAfterHeal': has(_cHeal),
                  'receivedPrePartitionKeys': [
                    for (final k in gotKeys[role]!.take(2))
                      if (has(k)) k,
                  ],
                  'receivedPostHealKeys': [
                    for (final k in gotKeys[role]!.skip(2))
                      if (has(k)) k,
                  ],
                };
              }
              return c.verdict(
                role,
                sent: sent,
                received: got,
                extra: {
                  'ge009PartitionHealProof': {...common, ...specific},
                },
              );
            }(),
        ];
      },
    );
