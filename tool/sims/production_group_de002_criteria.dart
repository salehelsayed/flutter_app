import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _count = 100;
const _proof = 'de002OrderedDeliveryProof';

String productionDe002Key(int index) =>
    'aliceSeq${(index + 1).toString().padLeft(3, '0')}';

final _keys = [for (var i = 0; i < _count; i++) productionDe002Key(i)];

/// Texts of catalog `de002`, identical to the original harness.
Map<String, ProductionCatalogText> productionDe002Texts(String run) => {
  for (var i = 0; i < _count; i++)
    productionDe002Key(i): (
      role: 'alice',
      text:
          'DE-002 rapid message ${(i + 1).toString().padLeft(3, '0')} $run',
    ),
};

final productionDe002Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  for (var i = 0; i < _count; i++) 'alice-seq-${i + 1}',
];

/// Keys of [role]'s rows ordered by the row timestamps the app persisted.
List<String> _orderedKeys(Map snapshot) {
  final rows = [
    for (final k in _keys)
      for (final r in productionCatalogRows(snapshot, k))
        (k, DateTime.tryParse('${r['timestamp']}') ?? DateTime(0)),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final r in rows) r.$1];
}

bool _strictlyIncreasing(List<Map<String, Object?>?> rows) {
  DateTime? previous;
  for (final r in rows) {
    final t = DateTime.tryParse('${r?['timestamp']}');
    if (t == null || (previous != null && !t.isAfter(previous))) return false;
    previous = t;
  }
  return true;
}

bool _same(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

/// DE-002. Alice sends 100 numbered messages through the composer one after
/// another; she holds them in send order with strictly increasing
/// timestamps, and Bob and Charlie each store all 100 exactly once, from
/// Alice, in the same order.
List<String> validateProductionGroupDe002(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'de002',
      flows: productionDe002Flows,
      verdicts: (c) {
        final sent = [for (final k in _keys) c.sent('alice', k)];
        final aliceOrder = _orderedKeys(c.finalOf('alice'));
        Map<String, Object?> receiver(String r) {
          final rx = [for (final k in _keys) c.receivedAtEnd(r, k)];
          final order = _orderedKeys(c.finalOf(r));
          return {
            'rows': rx,
            'proof': {
              'rowId': 'DE-002',
              'receivedAllMessagesOnce': rx.every((m) => m != null),
              'preservedPerSenderOrder': _same(order, _keys),
              'matchedSenderPeerId': rx.every(
                (m) => m?['senderPeerId'] == c.peers['alice'],
              ),
              'timestampsStrictlyIncreasing': _strictlyIncreasing(rx),
              'receivedCount': rx.whereType<Map>().length,
              'expectedCount': _count,
              'firstKey': order.isEmpty ? null : order.first,
              'lastKey': order.isEmpty ? null : order.last,
              'orderedKeys': order,
            },
          };
        }

        final bob = receiver('bob');
        final charlie = receiver('charlie');
        return [
          c.verdict(
            'alice',
            sent: sent,
            extra: {
              _proof: {
                'rowId': 'DE-002',
                'sentAllMessages': sent.every((s) => s != null),
                'preservedSendOrder': _same(aliceOrder, _keys),
                'timestampsStrictlyIncreasing': _strictlyIncreasing(sent),
                'sentCount': sent.whereType<Map>().length,
                'firstKey': aliceOrder.isEmpty ? null : aliceOrder.first,
                'lastKey': aliceOrder.isEmpty ? null : aliceOrder.last,
                'orderedKeys': aliceOrder,
              },
            },
          ),
          for (final (r, v) in [('bob', bob), ('charlie', charlie)])
            c.verdict(
              r,
              received: (v['rows'] as List).cast<Map<String, Object?>?>(),
              extra: {_proof: v['proof']},
            ),
        ];
      },
    );
