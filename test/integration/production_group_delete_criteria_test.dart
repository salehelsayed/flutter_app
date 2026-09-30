import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_delete_criteria.dart';

final _t = productionDeleteTexts('run');

Map<String, dynamic> _bob({required bool deleted}) => {
  'runId': 'run',
  'role': 'bob',
  'selfPeerId': 'b',
  'lifecycle': 'resumed',
  'groupId': 'g',
  'group': deleted
      ? null
      : {
          'id': 'g',
          'name': 'Game Night run',
          'createdBy': 'a',
          'role': 'member',
          'members': ['a', 'b'],
        },
  'groupMessages': deleted
      ? []
      : [
          {'id': 'g1', 'text': _t['groupOne'], 'incoming': true},
          {'id': 'g2', 'text': _t['groupTwo'], 'incoming': true},
        ],
  'contacts': ['a', 'c'],
  'direct': {
    'a': [
      {'id': 'd1', 'text': _t['aliceHello'], 'incoming': true},
      {'id': 'd2', 'text': _t['aliceReply'], 'incoming': false},
    ],
    'c': [
      {'id': 'd3', 'text': _t['charlieHello'], 'incoming': true},
      {'id': 'd4', 'text': _t['charlieReply'], 'incoming': false},
    ],
  },
};

Map<String, dynamic> _alice({required bool left}) => {
  'runId': 'run',
  'role': 'alice',
  'selfPeerId': 'a',
  'lifecycle': 'resumed',
  'groupId': 'g',
  'group': {
    'id': 'g',
    'name': 'Game Night run',
    'createdBy': 'a',
    'role': 'admin',
    'members': left ? ['a'] : ['a', 'b'],
  },
  'groupMessages': [],
  'contacts': ['b', 'c'],
  'direct': {'b': [], 'c': []},
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'groupId': 'g',
  'peers': {'alice': 'a', 'bob': 'b', 'charlie': 'c'},
  'beforeDelete': _bob(deleted: false),
  'afterDelete': _bob(deleted: true),
  'afterUi': _bob(deleted: true),
  'adminBefore': _alice(left: false),
  'adminAfter': _alice(left: true),
  'flows': [...productionDeleteFlowLabels],
  'cases': [
    {'id': 'DELETE_PRESERVES_FRIENDS', 'status': 'PASS'},
  ],
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('delete that keeps both friends and threads passes', () {
    expect(validateProductionGroupDelete(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'group still present after delete': (p) =>
        p['afterDelete']['group'] = p['beforeDelete']['group'],
    'group messages not purged': (p) =>
        p['afterDelete']['groupMessages'] = p['beforeDelete']['groupMessages'],
    'friend contact removed': (p) => p['afterDelete']['contacts'] = ['a'],
    'alice thread lost a message': (p) =>
        (p['afterUi']['direct']['a'] as List).removeLast(),
    'charlie thread rewritten': (p) =>
        ((p['afterDelete']['direct']['c'] as List)[0] as Map)['id'] = 'x',
    'charlie thread missing before delete': (p) =>
        p['beforeDelete']['direct']['c'] = [],
    'one group message never arrived': (p) =>
        (p['beforeDelete']['groupMessages'] as List).removeLast(),
    'bob never a member': (p) =>
        p['beforeDelete']['group']['members'] = ['a'],
    'admin still lists bob': (p) =>
        p['adminAfter']['group']['members'] = ['a', 'b'],
    'admin lost the group': (p) => p['adminAfter']['group'] = null,
    'background lifecycle': (p) => p['afterUi']['lifecycle'] = 'paused',
    'wrong device role': (p) => p['afterDelete']['selfPeerId'] = 'c',
    'duplicate peers': (p) => (p['peers'] as Map)['charlie'] = 'b',
    'skipped render flow': (p) =>
        (p['flows'] as List).remove('bob-render-charlie'),
    'missing case': (p) => (p['cases'] as List).clear(),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupDelete(proof), isNotEmpty);
    });
  }
}
