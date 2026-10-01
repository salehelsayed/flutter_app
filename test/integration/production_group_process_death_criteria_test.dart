import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_process_death_criteria.dart';

final _t = productionProcessDeathTexts('run');
const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};
const _all = ['peer-a', 'peer-b', 'peer-c'];

Map<String, Object?> _row(String key, {required bool incoming, int epoch = 2}) => {
  'messageId': 'm-$key',
  'groupId': 'g',
  'text': _t[key],
  'senderPeerId': key.startsWith('alice') ? 'peer-a' : 'peer-c',
  'timestamp': '2026-10-01T12:00:00.000Z',
  'keyEpoch': epoch,
  'isIncoming': incoming,
  'status': incoming ? 'received' : 'sent',
};

Map<String, Object?> _snap(
  String role, {
  List<String> members = _all,
  bool self = true,
  int epoch = 2,
  Map<String, List<Map<String, Object?>>> watched = const {},
}) => {
  'runId': 'run',
  'role': role,
  'scenario': 'private_process_death_matrix',
  'peerId': _p[role],
  'transportPeerId': _p[role],
  'lifecycle': 'resumed',
  'groupPresent': true,
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': epoch,
  'groupConfigStateHash': 'hash',
  'memberPeerIds': members,
  'selfMember': self,
  'watched': watched,
};

Map<String, dynamic> fixture() {
  final receipts = <String, Object?>{
    for (final (name, role, key) in productionProcessDeathReceipts)
      name: _snap(
        role,
        epoch: key == 'aliceAfterAddCrash' ? 1 : 2,
        watched: {
          key: [
            _row(key, incoming: true, epoch: key == 'aliceAfterAddCrash' ? 1 : 2),
          ],
        },
      ),
  };
  return {
    'runId': 'run',
    'relayAddresses': expectedMultiPartyRelayAddresses,
    'flows': [...productionProcessDeathFlows],
    'kills': {'charlie:add': true, 'bob:remove': true, 'charlie:readd': true},
    'addPersisted': _snap('charlie', epoch: 1),
    'addRecovered': _snap('charlie', epoch: 1),
    'removePersisted': _snap('bob', members: ['peer-a', 'peer-b'], epoch: 1),
    'removeRecovered': _snap('bob', members: ['peer-a', 'peer-b']),
    'charlieRemovedWindow': _snap('charlie', members: _all, self: false, epoch: 1),
    'readdPersisted': _snap('charlie'),
    'readdRecovered': _snap('charlie'),
    ...receipts,
    'final': {
      'alice': _snap(
        'alice',
        watched: {
          'aliceAfterAddCrash': [_row('aliceAfterAddCrash', incoming: false, epoch: 1)],
          'aliceAfterRemoveCrash': [_row('aliceAfterRemoveCrash', incoming: false)],
          'aliceAfterReaddCrash': [_row('aliceAfterReaddCrash', incoming: false)],
        },
      ),
      'bob': _snap('bob'),
      'charlie': _snap(
        'charlie',
        watched: {
          'charlieAfterReaddCrash': [_row('charlieAfterReaddCrash', incoming: false)],
        },
      ),
    },
  };
}

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('three recovered process deaths pass the unchanged original oracle', () {
    expect(validateProductionGroupProcessDeath(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Bob kill not verified': (p) => p['kills']['bob:remove'] = false,
    'Charlie add lost after restart': (p) =>
        p['addRecovered']['selfMember'] = false,
    'Bob restored Charlie after restart': (p) =>
        p['removeRecovered']['memberPeerIds'] = _all,
    'Charlie re-add lost after restart': (p) =>
        p['readdRecovered']['memberPeerIds'] = ['peer-a', 'peer-b'],
    'removed window leaked to Charlie': (p) =>
        p['charlieRemovedWindow']['watched'] = {
          'aliceAfterRemoveCrash': [
            _row('aliceAfterRemoveCrash', incoming: true),
          ],
        },
    'Charlie never got the post-readd message': (p) =>
        p['charlieGotReadd']['watched'] = <String, Object?>{},
    'duplicate at Bob': (p) =>
        (p['bobGotAdd']['watched']['aliceAfterAddCrash'] as List).add(
          _row('aliceAfterAddCrash', incoming: true, epoch: 1),
        ),
    'final epoch never rotated': (p) {
      for (final r in ['alice', 'bob', 'charlie']) {
        p['final'][r]['keyEpoch'] = 1;
      }
    },
    'final ghost membership': (p) =>
        p['final']['bob']['memberPeerIds'] = ['peer-a', 'peer-b'],
    'skipped kill flow order': (p) => (p['flows'] as List).removeAt(3),
    'background lifecycle': (p) => p['readdRecovered']['lifecycle'] = 'paused',
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupProcessDeath(proof), isNotEmpty);
    });
  }
}
