import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_catalog_case.dart';
import '../../tool/sims/production_group_dana_add_criteria.dart';
import 'support/production_catalog_fixture.dart';

const _four = ['peer-a', 'peer-b', 'peer-c', 'peer-d'];

/// A passing proof: each key's sender holds its outgoing row with a durable
/// delivery to [table]'s receivers; each receiver has a `got:` stage and a
/// final incoming row. [live] message keys are in Dana's live ids.
Map<String, dynamic> _proof(
  String scenario,
  Map<String, ProductionCatalogText> texts,
  List<String> flows,
  Map<String, List<String>> table, {
  List<String> live = const [],
  List<String> order = const [],
  Map<String, Object?> extra = const {},
}) {
  final f = CatalogFixture(scenario, texts, flows, dana: true);
  final p = f.base();
  final watched = <String, Map<String, Object?>>{
    for (final r in const ['alice', 'bob', 'charlie', 'dana']) r: {},
  };
  final deliveries = <String, List<Object?>>{
    for (final r in const ['alice', 'bob', 'charlie', 'dana']) r: [],
  };
  for (final MapEntry(:key, value: receivers) in table.entries) {
    final sender = texts[key]!.role;
    watched[sender]![key] = [f.row(key, incoming: false)];
    deliveries[sender]!.add(f.delivery(key, receivers));
    for (final r in receivers) {
      watched[r]![key] = [f.row(key, incoming: true)];
      p['got:$key:$r'] = f.got(r, key);
    }
  }
  for (final r in const ['alice', 'bob', 'charlie', 'dana']) {
    p['${r}Final'] = f.snap(
      r,
      members: _four,
      watched: watched[r]!,
      extra: {
        'deliveries': deliveries[r],
        if (r == 'dana') 'liveMessageIds': [for (final k in live) 'm-$k'],
      },
    );
  }
  p['danaPending'] = {
    'pending': [
      {'groupId': 'g'},
    ],
  };
  p['danaBeforeAccept'] = f.snap('dana', members: const [], self: false);
  p['aliceAddedDana'] = f.snap('alice', members: _four);
  p['danaAccepted'] = f.snap('dana', members: _four);
  p['order'] = [...order];
  p.addAll(extra);
  return p;
}

final _cases =
    <
      String,
      (
        List<String> Function(Map<String, Object?>),
        Map<String, dynamic> Function(),
      )
    >{
      'gm002': (
        validateProductionGroupGm002,
        () =>
            _proof('gm002', productionGm002Texts('run'), productionGm002Flows, {
              'aliceAfterDanaAdd': ['bob', 'charlie', 'dana'],
              'danaAfterJoin': ['alice', 'bob', 'charlie'],
            }),
      ),
      'ML-002': (
        validateProductionGroupMl002,
        () => _proof(
          'private_online_add',
          productionMl002Texts('run'),
          productionMl002Flows,
          {
            'aliceAfterDanaAdd': ['bob', 'charlie', 'dana'],
            'bobAfterDanaAdd': ['alice', 'charlie', 'dana'],
            'danaAfterJoin': ['alice', 'bob', 'charlie'],
          },
          live: const ['aliceAfterDanaAdd', 'bobAfterDanaAdd'],
          extra: {
            'aliceBeforeAdd': CatalogFixture(
              'private_online_add',
              productionMl002Texts('run'),
              productionMl002Flows,
              dana: true,
            ).snap('alice', members: const ['peer-a', 'peer-b', 'peer-c']),
          },
        ),
      ),
      'gm003': (
        validateProductionGroupGm003,
        () => _proof(
          'gm003',
          productionGm003Texts('run'),
          productionGm003Flows,
          {
            'aliceBeforeDanaAdd': ['bob', 'charlie'],
            'aliceAfterDanaOfflineAdd': ['bob', 'charlie', 'dana'],
            'danaAfterOfflineJoin': ['alice', 'bob', 'charlie'],
          },
          order: const [
            'dana-offline',
            'add-dana',
            'alice-after-add',
            'dana-online',
            'accept-dana',
            'dana-caught-up',
          ],
          extra: {'dana-offline': true},
        ),
      ),
      'ML-003': (
        validateProductionGroupMl003,
        () => _proof(
          'private_offline_add',
          productionMl003Texts('run'),
          productionMl003Flows,
          {
            'aliceAfterDanaOfflineAdd': ['bob', 'charlie', 'dana'],
            'bobAfterDanaOfflineAdd': ['alice', 'charlie', 'dana'],
            'aliceLiveAfterDanaDrain': ['dana'],
          },
          live: const ['aliceLiveAfterDanaDrain'],
          order: const [
            'dana-offline',
            'add-dana',
            'alice-after-add',
            'bob-after-add',
            'dana-online',
            'accept-dana',
            'dana-caught-up',
            'alice-live-after-drain',
          ],
          extra: {
            'dana-offline': true,
            'bobBeforeSend': CatalogFixture(
              'private_offline_add',
              productionMl003Texts('run'),
              productionMl003Flows,
              dana: true,
            ).snap('bob', members: _four),
          },
        ),
      ),
    };

final _mutations = <String, Map<String, void Function(Map<String, dynamic>)>>{
  'gm002': {
    'Dana never got the post-add message': (p) =>
        p['got:aliceAfterDanaAdd:dana']['watched'] = <String, Object?>{},
    'Charlie does not list Dana': (p) =>
        p['charlieFinal']['memberPeerIds'] = ['peer-a', 'peer-b', 'peer-c'],
  },
  'ML-002': {
    'Dana got Alice\'s post from the inbox': (p) =>
        p['danaFinal']['liveMessageIds'] = ['m-bobAfterDanaAdd'],
    'Dana was a member before the add': (p) =>
        p['danaBeforeAccept']['selfMember'] = true,
    'Bob never posted after the join': (p) =>
        p['bobFinal']['watched'].remove('bobAfterDanaAdd'),
  },
  'gm003': {
    'Dana was online during the add': (p) => p['dana-offline'] = false,
    'Dana relaunched before the post-add send': (p) => p['order'] = [
      'dana-offline',
      'add-dana',
      'dana-online',
      'alice-after-add',
      'accept-dana',
      'dana-caught-up',
    ],
    'Dana holds the pre-add message': (p) =>
        p['danaFinal']['watched']['aliceBeforeDanaAdd'] = [
          p['bobFinal']['watched']['aliceBeforeDanaAdd'][0],
        ],
  },
  'ML-003': {
    'Dana got a replay live': (p) => p['danaFinal']['liveMessageIds'] = [
      'm-aliceAfterDanaOfflineAdd',
      'm-aliceLiveAfterDanaDrain',
    ],
    'the post-drain message came from the inbox': (p) =>
        p['danaFinal']['liveMessageIds'] = <String>[],
    'no pending invite was stored': (p) => p['danaPending']['pending'] = [],
    'Bob posted after Dana accepted': (p) => p['order'] = [
      'dana-offline',
      'add-dana',
      'alice-after-add',
      'dana-online',
      'accept-dana',
      'bob-after-add',
      'dana-caught-up',
      'alice-live-after-drain',
    ],
  },
};

void main() {
  for (final MapEntry(key: name, value: (validate, fixture))
      in _cases.entries) {
    test('observed $name passes the original oracle', () {
      expect(validate(fixture()), isEmpty);
    });
    for (final m in _mutations[name]!.entries) {
      test('$name rejects ${m.key}', () {
        final proof = copyProof(fixture());
        m.value(proof);
        expect(validate(proof), isNotEmpty);
      });
    }
  }
}
