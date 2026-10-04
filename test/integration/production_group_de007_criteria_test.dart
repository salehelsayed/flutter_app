import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_de007_criteria.dart';
import 'support/production_catalog_fixture.dart';

const _k = 'aliceZeroPeer';
final _f = CatalogFixture('de007', productionDe007Texts('run'), productionDe007Flows);

Map<String, dynamic> fixture() {
  final p = _f.base();
  for (final r in ['bob', 'charlie']) {
    p['${r}BeforeSend'] = {
      'pending': [
        {'groupId': 'g'},
      ],
      'group': null,
    };
    p['got:$_k:$r'] = _f.got(r, _k);
    p['${r}Final'] = _f.snap(
      r,
      watched: {
        _k: [_f.row(_k, incoming: true)],
      },
      extra: {'liveMessageIds': <String>[]},
    );
  }
  p['aliceFinal'] = _f.snap(
    'alice',
    watched: {
      _k: [_f.row(_k, incoming: false)],
    },
    extra: {
      'deliveries': [
        {
          ..._f.delivery(_k, ['bob', 'charlie']),
          'topicPeers': 0,
          'inboxStored': true,
          'expectedRecipientCount': 2,
        },
      ],
    },
  );
  return p;
}

void main() {
  test('observed DE-007 zero-peer delivery passes the original oracle', () {
    expect(validateProductionGroupDe007(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Bob had joined before the send': (p) =>
        p['bobBeforeSend']['group'] = {'members': []},
    'Charlie held no invitation': (p) => p['charlieBeforeSend']['pending'] = [],
    'a live topic peer at send': (p) =>
        p['aliceFinal']['deliveries'][0]['topicPeers'] = 1,
    'no inbox custody': (p) =>
        p['aliceFinal']['deliveries'][0]['inboxStored'] = false,
    'custody omits pending Charlie': (p) =>
        p['aliceFinal']['deliveries'][0]['recipientPeerIds'] = ['peer-b'],
    'Bob got it live': (p) => p['bobFinal']['liveMessageIds'] = ['m-$_k'],
    'Charlie stored it twice': (p) => (p['charlieFinal']['watched'][_k] as List)
        .add(_f.row(_k, incoming: true)),
    'Bob never got it': (p) => p['got:$_k:bob']['watched'] = <String, Object?>{},
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupDe007(proof), isNotEmpty);
    });
  }
}
