import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_ir001_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture('ir001', productionIr001Texts('run'), productionIr001Flows);
const _missed = [
  'aliceMissedWhileBobOffline1',
  'aliceMissedWhileBobOffline2',
  'aliceMissedWhileBobOffline3',
];
const _live = 'aliceLiveAfterBobDrain';

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['bobOffline'] = true;
  p['bobDrain'] = {'completedDrainCount': 1};
  p['bobBeforeOffline'] = _f.snap('bob');
  p['bobRelaunched'] = _f.snap('bob');
  for (final k in [..._missed, _live]) {
    p['got:$k:bob'] = _f.got('bob', k);
    p['got:$k:charlie'] = _f.got('charlie', k);
  }
  p['aliceFinal'] = _f.snap(
    'alice',
    watched: {
      for (final k in [..._missed, _live]) k: [_f.row(k, incoming: false)],
    },
  );
  for (final r in ['bob', 'charlie']) {
    p['${r}Final'] = _f.snap(
      r,
      watched: {
        for (final k in [..._missed, _live]) k: [_f.row(k, incoming: true)],
      },
    );
  }
  return p;
}

void main() {
  test('observed IR-001 offline reconnect passes the original oracle', () {
    expect(validateProductionGroupIr001(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Bob never went offline': (p) => p['bobOffline'] = false,
    'no catch-up drain': (p) => p['bobDrain'] = {'completedDrainCount': 0},
    'Bob lost the group on relaunch': (p) =>
        p['bobRelaunched']['groupPresent'] = false,
    'Bob missed one message': (p) =>
        p['got:${_missed[1]}:bob']['watched'] = <String, Object?>{},
    'Bob persisted one twice': (p) =>
        (p['bobFinal']['watched'][_missed[0]] as List).add(
          _f.row(_missed[0], incoming: true),
        ),
    'Charlie missed the live message': (p) =>
        p['got:$_live:charlie']['watched'] = <String, Object?>{},
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupIr001(proof), isNotEmpty);
    });
  }
}
