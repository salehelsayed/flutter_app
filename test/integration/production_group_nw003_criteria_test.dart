import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_nw003_criteria.dart';
import 'support/production_catalog_fixture.dart';

const _removed = 'aliceRemovedWindow';
const _alicePost = 'alicePostHeal';
const _bobPost = 'bobPostHeal';
const _charliePost = 'charliePostHeal';
final _f = CatalogFixture(
  'private_partition_readd_heal',
  productionNw003Texts('run'),
  productionNw003Flows,
);

Map<String, dynamic> fixture() {
  final p = _f.base();
  const table = {
    _removed: ['bob'],
    _alicePost: ['bob', 'charlie'],
    _bobPost: ['alice', 'charlie'],
    _charliePost: ['alice', 'bob'],
  };
  final watched = <String, Map<String, Object?>>{
    for (final r in const ['alice', 'bob', 'charlie']) r: {},
  };
  final deliveries = <String, List<Object?>>{
    for (final r in const ['alice', 'bob', 'charlie']) r: [],
  };
  for (final MapEntry(:key, value: to) in table.entries) {
    final sender = productionNw003Texts('run')[key]!.role;
    watched[sender]![key] = [_f.row(key, incoming: false)];
    deliveries[sender]!.add(_f.delivery(key, to));
    for (final r in to) {
      watched[r]![key] = [_f.row(key, incoming: true)];
      p['got:$key:$r'] = _f.got(r, key);
    }
  }
  for (final r in const ['alice', 'bob', 'charlie']) {
    p['${r}Final'] = _f.snap(
      r,
      watched: watched[r]!,
      extra: {'deliveries': deliveries[r], 'liveMessageIds': <String>[]},
    );
  }
  p['aliceRemoved'] = _f.snap('alice', members: const ['peer-a', 'peer-b']);
  p['bob-offline'] = true;
  p['charlie-offline'] = true;
  return p;
}

void main() {
  test('observed NW-003 passes the original oracle', () {
    expect(validateProductionGroupNw003(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie was not partitioned': (p) => p['charlie-offline'] = false,
    'Charlie holds the removed-window post': (p) =>
        p['charlieFinal']['watched'][_removed] = [
          _f.row(_removed, incoming: true),
        ],
    'the removed-window post was addressed to Charlie': (p) =>
        p['aliceFinal']['deliveries'][0]['recipientPeerIds'] = [
          'peer-b',
          'peer-c',
        ],
    'Bob got the removed-window post live': (p) =>
        p['bobFinal']['liveMessageIds'] = ['m-$_removed'],
    'the key epoch never rotated': (p) {
      for (final r in const ['alice', 'bob', 'charlie']) {
        p['${r}Final']['keyEpoch'] = 1;
      }
    },
    'Charlie was not re-added': (p) =>
        p['bobFinal']['memberPeerIds'] = ['peer-a', 'peer-b'],
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupNw003(proof), isNotEmpty);
    });
  }
}
