import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_ge010_criteria.dart';
import 'support/production_catalog_fixture.dart';

const _k = 'aliceGe010ZeroPeerFallback';

CatalogFixture _f(String scenario) =>
    CatalogFixture(scenario, productionGe010Texts('run'), productionGe010Flows);

Map<String, dynamic> fixture(String scenario) {
  final f = _f(scenario);
  final p = f.base();
  for (final r in ['bob', 'charlie']) {
    p['${r}Offline'] = true;
    p['${r}BeforeOffline'] = f.snap(r);
    p['${r}Relaunched'] = f.snap(r);
    p['${r}Drain'] = {'completedDrainCount': 1};
    p['got:$_k:$r'] = f.got(r, _k);
    p['${r}Final'] = f.snap(
      r,
      watched: {
        _k: [f.row(_k, incoming: true)],
      },
      extra: {'liveMessageIds': <String>[]},
    );
  }
  p['aliceFinal'] = f.snap(
    'alice',
    watched: {
      _k: [f.row(_k, incoming: false)],
    },
    extra: {
      'liveMessageIds': <String>[],
      'deliveries': [
        {
          ...f.delivery(_k, ['bob', 'charlie']),
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
  final validators = {
    'ge010': validateProductionGroupGe010,
    'go001': validateProductionGroupGo001,
  };
  for (final MapEntry(key: scenario, value: validate) in validators.entries) {
    test('$scenario: observed zero-peer fallback passes the original oracle',
        () {
      expect(validate(fixture(scenario)), isEmpty);
    });
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'Bob was alive at the send': (p) => p['bobOffline'] = false,
      'Alice had a live topic peer': (p) =>
          p['aliceFinal']['deliveries'][0]['topicPeers'] = 1,
      'no inbox custody': (p) =>
          p['aliceFinal']['deliveries'][0]['inboxStored'] = false,
      'no observed delivery': (p) => p['aliceFinal']['deliveries'] = [],
      'durable copy omits Charlie': (p) =>
          p['aliceFinal']['deliveries'][0]['recipientPeerIds'] = ['peer-b'],
      'Alice row left pending': (p) =>
          p['aliceFinal']['watched'][_k][0]['status'] = 'pending',
      'Charlie got it live': (p) =>
          p['charlieFinal']['liveMessageIds'] = ['m-$_k'],
      'Bob stored it twice': (p) => (p['bobFinal']['watched'][_k] as List)
          .add(_f(scenario).row(_k, incoming: true)),
      'Charlie never recovered it': (p) =>
          p['got:$_k:charlie']['watched'] = <String, Object?>{},
      'no catch-up drain': (p) => p['bobDrain'] = {'completedDrainCount': 0},
      'Bob lost the group on relaunch': (p) =>
          p['bobRelaunched']['groupPresent'] = false,
    };
    for (final e in mutations.entries) {
      test('$scenario: rejects ${e.key}', () {
        final proof = copyProof(fixture(scenario));
        e.value(proof);
        expect(validate(proof), isNotEmpty);
      });
    }
  }
}
