import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_de002_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture('de002', productionDe002Texts('run'), productionDe002Flows);
final _keys = [for (var i = 0; i < 100; i++) productionDe002Key(i)];

String _at(int i) => DateTime.utc(2026, 10, 2, 12).add(Duration(seconds: i)).toIso8601String();

Map<String, dynamic> fixture() {
  final p = _f.base();
  for (final r in ['alice', 'bob', 'charlie']) {
    p['${r}Final'] = _f.snap(
      r,
      watched: {
        for (var i = 0; i < 100; i++)
          _keys[i]: [_f.row(_keys[i], incoming: r != 'alice', timestamp: _at(i))],
      },
    );
  }
  return p;
}

void main() {
  test('observed DE-002 ordered delivery passes the original oracle', () {
    expect(validateProductionGroupDe002(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Alice sent 99': (p) => p['aliceFinal']['watched'][_keys[42]] = [],
    'Bob missed one': (p) => p['bobFinal']['watched'][_keys[99]] = [],
    'Charlie stored one twice': (p) =>
        (p['charlieFinal']['watched'][_keys[7]] as List).add(
          _f.row(_keys[7], incoming: true, timestamp: _at(7)),
        ),
    'Bob holds two out of order': (p) {
      p['bobFinal']['watched'][_keys[10]][0]['timestamp'] = _at(11);
      p['bobFinal']['watched'][_keys[11]][0]['timestamp'] = _at(10);
    },
    'Alice timestamps not strictly increasing': (p) =>
        p['aliceFinal']['watched'][_keys[50]][0]['timestamp'] = _at(49),
    'Charlie got one from another sender': (p) =>
        p['charlieFinal']['watched'][_keys[3]][0]['senderPeerId'] = 'peer-b',
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupDe002(proof), isNotEmpty);
    });
  }
}
