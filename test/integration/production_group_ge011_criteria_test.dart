import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_ge011_criteria.dart';
import 'support/production_catalog_fixture.dart';

const _k = 'aliceGe011PartialLiveFallback';
final _f = CatalogFixture('ge011', productionGe011Texts('run'), productionGe011Flows);

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['charlieOffline'] = true;
  p['bobBeforeSend'] = _f.snap('bob');
  p['charlieBeforeSend'] = _f.snap('charlie');
  p['charlieRelaunched'] = _f.snap('charlie');
  p['bobDrain'] = {'completedDrainCount': 1};
  p['charlieDrain'] = {'completedDrainCount': 1};
  for (final r in ['bob', 'charlie']) {
    p['got:$_k:$r'] = _f.got(r, _k);
  }
  p['bobFinal'] = _f.snap(
    'bob',
    watched: {
      _k: [_f.row(_k, incoming: true)],
    },
    extra: {
      'liveMessageIds': ['m-$_k'],
    },
  );
  p['charlieFinal'] = _f.snap(
    'charlie',
    watched: {
      _k: [_f.row(_k, incoming: true)],
    },
    extra: {'liveMessageIds': <String>[]},
  );
  p['aliceFinal'] = _f.snap(
    'alice',
    watched: {
      _k: [_f.row(_k, incoming: false)],
    },
    extra: {
      'liveMessageIds': <String>[],
      'deliveries': [
        {
          ..._f.delivery(_k, ['bob', 'charlie']),
          'topicPeers': 1,
          'inboxStored': true,
          'expectedRecipientCount': 2,
        },
      ],
    },
  );
  return p;
}

void main() {
  test('observed GE-011 partial-live fallback passes the original oracle', () {
    expect(validateProductionGroupGe011(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie was alive at the send': (p) => p['charlieOffline'] = false,
    'two live topic peers': (p) =>
        p['aliceFinal']['deliveries'][0]['topicPeers'] = 2,
    'zero live topic peers': (p) =>
        p['aliceFinal']['deliveries'][0]['topicPeers'] = 0,
    'no inbox custody': (p) =>
        p['aliceFinal']['deliveries'][0]['inboxStored'] = false,
    'Bob got it from the inbox': (p) =>
        p['bobFinal']['liveMessageIds'] = <String>[],
    'Charlie got it live': (p) =>
        p['charlieFinal']['liveMessageIds'] = ['m-$_k'],
    'Bob stored it twice after the drain': (p) =>
        (p['bobFinal']['watched'][_k] as List).add(_f.row(_k, incoming: true)),
    'Charlie never recovered it': (p) =>
        p['got:$_k:charlie']['watched'] = <String, Object?>{},
    'no catch-up drain for Charlie': (p) =>
        p['charlieDrain'] = {'completedDrainCount': 0},
    'Charlie held plaintext before rejoining': (p) =>
        p['charlieBeforeSend']['watched'] = {
          _k: [_f.row(_k, incoming: true)],
        },
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupGe011(proof), isNotEmpty);
    });
  }
}
