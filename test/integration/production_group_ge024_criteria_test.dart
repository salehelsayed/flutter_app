import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_ge024_criteria.dart';
import 'support/production_catalog_fixture.dart';

const _before = 'aliceGe024BeforeRemovalParent';
const _removed = 'aliceGe024RemovedWindowParent';
const _replyA = 'bobGe024ReplyAvailable';
const _replyU = 'bobGe024ReplyUnavailable';
const _quotes = {_replyA: 'm-$_before', _replyU: 'm-$_removed'};
final _f = CatalogFixture(
  'ge024',
  productionGe024Texts('run'),
  productionGe024Flows,
);

Map<String, Object?> _row(String key, {required bool incoming}) => {
  ..._f.row(key, incoming: incoming),
  'quotedMessageId': ?_quotes[key],
};

Map<String, dynamic> fixture() {
  final p = _f.base();
  Map<String, Object?> watched(Map<String, bool> keys) => {
    for (final e in keys.entries) e.key: [_row(e.key, incoming: e.value)],
  };
  p['aliceFinal'] = _f.snap(
    'alice',
    watched: watched({
      _before: false,
      _removed: false,
      _replyA: true,
      _replyU: true,
    }),
    extra: {
      'deliveries': [
        _f.delivery(_before, ['bob', 'charlie']),
        _f.delivery(_removed, ['bob']),
      ],
    },
  );
  p['bobFinal'] = _f.snap(
    'bob',
    watched: watched({
      _before: true,
      _removed: true,
      _replyA: false,
      _replyU: false,
    }),
    extra: {
      'deliveries': [
        _f.delivery(_replyA, ['alice', 'charlie']),
        _f.delivery(_replyU, ['alice', 'charlie']),
      ],
    },
  );
  p['charlieFinal'] = _f.snap(
    'charlie',
    watched: watched({_before: true, _replyA: true, _replyU: true}),
  );
  for (final (key, role) in const [
    (_before, 'bob'),
    (_before, 'charlie'),
    (_removed, 'bob'),
    (_replyA, 'alice'),
    (_replyA, 'charlie'),
    (_replyU, 'alice'),
    (_replyU, 'charlie'),
  ]) {
    p['got:$key:$role'] = _f.snap(role, watched: watched({key: true}));
  }
  p['charlieRemovedWindow'] = _f.snap(
    'charlie',
    members: const ['peer-a', 'peer-b'],
    self: false,
  );
  return p;
}

void main() {
  test('observed GE-024 quoted replies pass the original oracle', () {
    expect(validateProductionGroupGe024(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    "Bob's reply quotes the wrong parent": (p) =>
        (p['bobFinal']['watched'][_replyA] as List).single['quotedMessageId'] =
            'm-$_removed',
    "Charlie's copy lost the quote": (p) =>
        (p['got:$_replyU:charlie']['watched'][_replyU] as List).single.remove(
          'quotedMessageId',
        ),
    'Charlie holds the removed-window parent at the end': (p) =>
        p['charlieFinal']['watched'][_removed] = [
          _row(_removed, incoming: true),
        ],
    'Charlie held it during the removed window': (p) =>
        p['charlieRemovedWindow']['watched'] = {
          _removed: [_row(_removed, incoming: true)],
        },
    'Charlie never rendered the unavailable quote': (p) =>
        (p['flows'] as List).remove('charlie-renders-replies'),
    'Charlie was not re-added': (p) =>
        p['aliceFinal']['memberPeerIds'] = ['peer-a', 'peer-b'],
    'Alice never got the second reply': (p) =>
        p['got:$_replyU:alice']['watched'] = <String, Object?>{},
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupGe024(proof), isNotEmpty);
    });
  }
}
