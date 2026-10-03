import 'production_catalog_case.dart';

const productionGe005Cycles = 20;

String _tag(int cycle) => cycle.toString().padLeft(2, '0');
String productionGe005RemovedKey(int cycle) => 'aliceGe005Removed${_tag(cycle)}';
String productionGe005ReaddKey(int cycle) => 'bobGe005Readd${_tag(cycle)}';

/// Texts of catalog `ge005`, identical to the original harness.
Map<String, ProductionCatalogText> productionGe005Texts(String run) => {
  for (var c = 1; c <= productionGe005Cycles; c++) ...{
    productionGe005RemovedKey(c): (
      role: 'alice',
      text: 'GE-005 removed window ${_tag(c)} $run',
    ),
    productionGe005ReaddKey(c): (
      role: 'bob',
      text: 'GE-005 readd window ${_tag(c)} $run',
    ),
  },
};

List<String> productionGe005Flows() => [
  'create',
  'accept-bob',
  'accept-charlie',
  for (var c = 1; c <= productionGe005Cycles; c++) ...[
    'remove-charlie',
    'alice-back-to-chat',
    'alice-removed-${_tag(c)}',
    'readd-charlie',
    'charlie-home',
    'accept-charlie-readd',
    'bob-readd-${_tag(c)}',
  ],
];

/// GE-005: twenty UI remove/re-add cycles. Receipts are read from the final
/// snapshots (rows persist), recipients from the delivery observer.
List<String> validateProductionGroupGe005(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'ge005',
      flows: productionGe005Flows(),
      verdicts: (c) {
        final bob = '${c.peers['bob']}';
        final charlie = '${c.peers['charlie']}';
        final all = {for (final r in const ['alice', 'bob', 'charlie']) '${c.peers[r]}'};
        final removedKeys = [
          for (var i = 1; i <= productionGe005Cycles; i++)
            productionGe005RemovedKey(i),
        ];
        final readdKeys = [
          for (var i = 1; i <= productionGe005Cycles; i++)
            productionGe005ReaddKey(i),
        ];
        final completed = proof['completedCycles'] as int? ?? 0;
        final aSent = [for (final k in removedKeys) c.sent('alice', k)];
        final bSent = [for (final k in readdKeys) c.sent('bob', k)];
        final aGot = [for (final k in readdKeys) c.receivedAtEnd('alice', k)];
        final bGot = [for (final k in removedKeys) c.receivedAtEnd('bob', k)];
        final cGot = [for (final k in readdKeys) c.receivedAtEnd('charlie', k)];
        var leak = 0;
        for (final k in removedKeys) {
          leak += c.finalCount('charlie', k);
        }
        List rc(Map? m) => (m?['recipientPeerIds'] as List?) ?? const [];
        List<String> keys(List<Map<String, Object?>?> l) => [
          for (final m in l)
            if (m != null) '${m['key']}',
        ];
        Map<String, Object?> common(String role) {
          final members = c.members(c.finalOf(role));
          return {
            'cycleCount': productionGe005Cycles,
            'completedCycleCount': completed,
            'finalMemberListIncludesAll': members.containsAll(all),
            'finalMemberPeerIds': members.toList()..sort(),
          };
        }

        bool durable(List<Map<String, Object?>?> sent) =>
            sent.isNotEmpty &&
            sent.every((m) => m?['actualDurablePayloadProof'] == true);
        return [
          c.verdict(
            'alice',
            sent: aSent,
            received: aGot,
            extra: {
              'ge005RemoveReaddLoopProof': {
                ...common('alice'),
                'actualDurablePayloadProof': durable(aSent),
                'actualLiveTopicPeerProof': false,
                'removedWindowExcludedCharlie': aSent.every(
                  (m) => m != null && !rc(m).contains(charlie) && rc(m).contains(bob),
                ),
                'removedWindowSentCount': aSent.whereType<Map>().length,
                'readdWindowReceivedCount': keys(aGot).length,
                'removedWindowSentKeys': keys(aSent),
                'readdWindowReceivedKeys': keys(aGot),
              },
            },
          ),
          c.verdict(
            'bob',
            sent: bSent,
            received: bGot,
            extra: {
              'ge005RemoveReaddLoopProof': {
                ...common('bob'),
                'actualDurablePayloadProof': durable(bSent),
                'actualLiveTopicPeerProof': false,
                'readdWindowIncludedCharlie': bSent.every(
                  (m) => m != null && rc(m).contains(charlie),
                ),
                'removedWindowReceivedCount': keys(bGot).length,
                'readdWindowSentCount': bSent.whereType<Map>().length,
                'removedWindowReceivedKeys': keys(bGot),
                'readdWindowSentKeys': keys(bSent),
              },
            },
          ),
          c.verdict(
            'charlie',
            received: cGot,
            extra: {
              'ge005RemoveReaddLoopProof': {
                ...common('charlie'),
                'removedWindowPlaintextCount': leak,
                'readdWindowReceivedCount': keys(cGot).length,
                'removedWindowReceivedKeys': const <String>[],
                'readdWindowReceivedKeys': keys(cGot),
              },
            },
          ),
        ];
      },
    );
