import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_full_mesh_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture(
  'private_full_mesh_online',
  productionFullMeshTexts('run'),
  productionFullMeshFlows,
);
const _roles = ['alice', 'bob', 'charlie'];
String _key(String r) => '${r}FullMesh';

Map<String, dynamic> fixture() {
  final p = _f.base();
  for (final r in _roles) {
    final others = [for (final o in _roles) if (o != r) o];
    for (final o in others) {
      p['got:${_key(o)}:$r'] = _f.got(r, _key(o));
    }
    p['${r}Final'] = _f.snap(
      r,
      watched: {
        _key(r): [_f.row(_key(r), incoming: false)],
        for (final o in others) _key(o): [_f.row(_key(o), incoming: true)],
      },
      extra: {
        'liveMessageIds': [for (final o in others) 'm-${_key(o)}'],
        'deliveries': [
          {
            ..._f.delivery(_key(r), others),
            'topicPeers': 2,
            'inboxStored': true,
            'expectedRecipientCount': 2,
          },
        ],
      },
    );
  }
  return p;
}

void main() {
  test('observed NW-001 full mesh passes the original oracle', () {
    expect(validateProductionGroupFullMesh(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Bob published with one topic peer': (p) =>
        p['bobFinal']['deliveries'][0]['topicPeers'] = 1,
    'Charlie published with no topic peers': (p) =>
        p['charlieFinal']['deliveries'][0]['topicPeers'] = 0,
    'Alice publish not observed': (p) => p['aliceFinal']['deliveries'] = [],
    'Bob got Alice from the inbox': (p) =>
        p['bobFinal']['liveMessageIds'] = ['m-charlieFullMesh'],
    'Charlie stored Bob twice': (p) =>
        (p['charlieFinal']['watched']['bobFullMesh'] as List).add(
          _f.row('bobFullMesh', incoming: true),
        ),
    'Alice never got Charlie': (p) =>
        p['got:charlieFullMesh:alice']['watched'] = <String, Object?>{},
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupFullMesh(proof), isNotEmpty);
    });
  }
}
