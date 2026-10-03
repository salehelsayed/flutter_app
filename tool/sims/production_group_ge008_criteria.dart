import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _roles = ['alice', 'bob', 'charlie'];
const _stale = ['charlieGe008RemovedStale0', 'charlieGe008RemovedStale1'];

String _key(String role, String phase, int i) =>
    '${role}Ge008${phase[0].toUpperCase()}${phase.substring(1)}$i';

/// Keys of one phase (`pre`, `removed` or `post`) for the given senders.
List<String> productionGe008Keys(String phase, List<String> senders) => [
  for (final r in senders)
    for (var i = 0; i < 2; i++) _key(r, phase, i),
];

/// Texts of catalog `ge008`, identical to the original harness.
Map<String, ProductionCatalogText> productionGe008Texts(String run) => {
  for (final (phase, senders) in const [
    ('pre', _roles),
    ('removed', ['alice', 'bob']),
    ('post', _roles),
  ])
    for (final k in productionGe008Keys(phase, senders))
      k: (role: k.split('Ge008').first, text: 'GE-008 $phase $k $run'),
  for (final k in _stale)
    k: (role: 'charlie', text: 'GE-008 stale removed-window $k $run'),
};

/// The exact ordered UI flows: one label per send.
List<String> productionGe008Flows() => [
  'create',
  'accept-bob',
  'accept-charlie',
  for (final k in productionGe008Keys('pre', _roles)) 'send-$k',
  'remove-charlie',
  'alice-back-to-chat',
  for (final k in productionGe008Keys('removed', ['alice', 'bob'])) 'send-$k',
  'readd-charlie',
  'charlie-home',
  'accept-charlie-readd',
  for (final k in productionGe008Keys('post', _roles)) 'send-$k',
];

/// GE-008. Each phase's sends are issued back to back through the composers
/// (the original issues them 100 ms apart), then every receiver is observed.
List<String> validateProductionGroupGe008(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'ge008',
      flows: productionGe008Flows(),
      verdicts: (c) {
        final charlie = '${c.peers['charlie']}';
        final epochs = {for (final r in _roles) r: c.epoch(r)};
        final removedSenders = ['alice', 'bob'];
        List<String> own(String role, String phase, List<String> senders) =>
            senders.contains(role) ? productionGe008Keys(phase, [role]) : const [];
        List<String> others(String role, String phase, List<String> senders) =>
            productionGe008Keys(phase, senders.where((r) => r != role).toList());
        final rejected = [
          for (final k in _stale) proof['charlieRejected:$k'] as Map?,
        ];
        final charlieDeliveries =
            (c.finalOf('charlie')['deliveries'] as List?) ?? const [];
        final stalePublishes = charlieDeliveries
            .whereType<Map>()
            .where(
              (d) => rejected.any(
                (r) => r != null && r['messageId'] == d['messageId'],
              ),
            )
            .length;
        final window = c.stage('charlieRemovedWindow', 'charlie');
        var leak = 0;
        for (final k in productionGe008Keys('removed', removedSenders)) {
          leak +=
              productionCatalogRows(window, k).length +
              c.finalCount('charlie', k);
        }
        return [
          for (final role in _roles)
            () {
              final phases = role == 'charlie'
                  ? const ['pre', 'post']
                  : const ['pre', 'removed', 'post'];
              List<String> sendersOf(String phase) =>
                  phase == 'removed' ? removedSenders : _roles;
              final sent = {
                for (final ph in phases)
                  ph: [
                    for (final k in own(role, ph, sendersOf(ph)))
                      c.sent(role, k),
                  ],
              };
              final got = {
                for (final ph in phases)
                  ph: [
                    for (final k in others(role, ph, sendersOf(ph)))
                      c.received(role, k),
                  ],
              };
              List<String> keysOf(List<Map<String, Object?>?> rx) => [
                for (final r in rx)
                  if (r != null) '${r['key']}',
              ];
              final allGot = [for (final l in got.values) ...l];
              final deduped = allGot.every((r) => r?['persistedCount'] == 1);
              final members = c.members(c.finalOf(role));
              final Map<String, Object?> fields;
              if (role == 'charlie') {
                fields = {
                  'selfRemovedDuringStorm':
                      c.stage('charlieRemoved', 'charlie')['selfMember'] == false,
                  'staleRemovedWindowSendsRejected': rejected.every(
                    (r) => r != null && r['accepted'] != true,
                  ),
                  'readdedCharlie': members.contains(charlie),
                  'preStormComplete': got['pre']!.every((r) => r != null),
                  'postReaddStormComplete': got['post']!.every((r) => r != null),
                  'duplicateDeliveryDeduped': deduped,
                  'receivedPostReaddStormMessages':
                      got['post']!.every((r) => r != null),
                  'preStormSentCount': sent['pre']!.whereType<Map>().length,
                  'postReaddSentCount': sent['post']!.whereType<Map>().length,
                  'preStormReceivedCount': keysOf(got['pre']!).length,
                  'postReaddReceivedCount': keysOf(got['post']!).length,
                  'staleRemovedWindowAttemptCount': rejected
                      .whereType<Map>()
                      .length,
                  'staleRemovedWindowAcceptedCount': rejected
                      .where((r) => r?['accepted'] == true)
                      .length,
                  'staleRemovedWindowPublishCount': stalePublishes,
                  'removedWindowPlaintextCount': leak,
                  'receivedPreStormKeys': keysOf(got['pre']!),
                  'receivedPostReaddKeys': keysOf(got['post']!),
                  'rejectedRemovedWindowKeys': [
                    for (final r in rejected)
                      if (r != null && r['accepted'] != true) r['key'],
                  ],
                  'finalEpoch': epochs[role],
                };
              } else {
                final other = role == 'alice' ? 'Bob' : 'Alice';
                final excluded = !c
                    .members(
                      role == 'alice'
                          ? c.stage('aliceRemoved', 'alice')
                          : c.stage('bobExcluded', 'bob'),
                    )
                    .contains(charlie);
                fields = {
                  'removedCharlie': role == 'alice' ? excluded : null,
                  'readdedCharlie': members.contains(charlie),
                  'preStormComplete': got['pre']!.every((r) => r != null),
                  'removedWindowComplete': got['removed']!.every(
                    (r) => r != null,
                  ),
                  'postReaddStormComplete': got['post']!.every((r) => r != null),
                  if (role == 'alice')
                    'charlieExcludedDuringRemovedWindow': excluded
                  else ...{
                    'memberListExcludesCharlieDuringRemovedWindow': excluded,
                    'memberListIncludesAliceCharlie': members.containsAll([
                      '${c.peers['alice']}',
                      charlie,
                    ]),
                  },
                  'duplicateDeliveryDeduped': deduped,
                  'received${other}RemovedWindowMessages': got['removed']!.every(
                    (r) => r != null,
                  ),
                  'receivedCharliePostReaddMessages': keysOf(
                    got['post']!,
                  ).any((k) => k.startsWith('charlie')),
                  for (final ph in phases) ...{
                    '${ph == 'pre' ? 'preStorm' : ph == 'removed' ? 'removedWindow' : 'postReadd'}SentCount':
                        sent[ph]!.whereType<Map>().length,
                    '${ph == 'pre' ? 'preStorm' : ph == 'removed' ? 'removedWindow' : 'postReadd'}ReceivedCount':
                        keysOf(got[ph]!).length,
                  },
                  'receivedPreStormKeys': keysOf(got['pre']!),
                  'receivedRemovedWindowKeys': keysOf(got['removed']!),
                  'receivedPostReaddKeys': keysOf(got['post']!),
                  'removedPeerId': charlie,
                  'finalEpoch': epochs[role],
                }..removeWhere((_, v) => v == null);
              }
              return c.verdict(
                role,
                sent: [for (final l in sent.values) ...l],
                received: allGot,
                extra: {'ge008SendStormProof': fields},
              );
            }(),
        ];
      },
    );
