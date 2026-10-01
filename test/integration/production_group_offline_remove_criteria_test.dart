import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_offline_remove_criteria.dart';

final _t = productionOfflineRemoveTexts('run');
const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};

Map<String, Object?> _row(String key, {required bool incoming}) => {
  'messageId': 'm-$key',
  'groupId': 'g',
  'text': _t[key],
  'senderPeerId': key.startsWith('alice') ? 'peer-a' : 'peer-b',
  'timestamp': '2026-10-01T12:00:00.000Z',
  'keyEpoch': 2,
  'isIncoming': incoming,
  'status': incoming ? 'received' : 'sent',
};

Map<String, Object?> _snap(
  String role, {
  int epoch = 2,
  List<String> members = const ['peer-a', 'peer-b'],
  bool self = true,
  bool present = true,
  Map<String, List<Map<String, Object?>>> watched = const {},
}) => {
  'runId': 'run',
  'role': role,
  'scenario': 'private_offline_remove',
  'peerId': _p[role],
  'transportPeerId': _p[role],
  'lifecycle': 'resumed',
  'groupPresent': present,
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': epoch,
  'groupConfigStateHash': role == 'charlie' ? 'old' : 'hash',
  'memberPeerIds': members,
  'selfMember': self,
  'watched': watched,
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'relayAddresses': expectedMultiPartyRelayAddresses,
  'peers': _p,
  'flows': [...productionOfflineRemoveFlows],
  'charlieStale': _snap(
    'charlie',
    epoch: 1,
    members: ['peer-a', 'peer-b', 'peer-c'],
  ),
  'charlieOffline': true,
  'aliceSentAfter': _snap(
    'alice',
    watched: {
      'aliceAfterCharlieOfflineRemove': [
        _row('aliceAfterCharlieOfflineRemove', incoming: false),
      ],
    },
  ),
  'bobGotAlice': _snap(
    'bob',
    watched: {
      'aliceAfterCharlieOfflineRemove': [
        _row('aliceAfterCharlieOfflineRemove', incoming: true),
      ],
    },
  ),
  'bobSentAfter': _snap(
    'bob',
    watched: {
      'bobAfterCharlieOfflineRemove': [
        _row('bobAfterCharlieOfflineRemove', incoming: false),
      ],
    },
  ),
  'aliceGotBob': _snap(
    'alice',
    watched: {
      'bobAfterCharlieOfflineRemove': [
        _row('bobAfterCharlieOfflineRemove', incoming: true),
      ],
    },
  ),
  'charlieDrain': {
    'drainAttemptCount': 3,
    'completedDrainCount': 3,
    'drainErrorCount': 0,
    'drainRetrieveCounts': [2, 0, 0],
    'drainRetrievedMessageCount': 2,
    'drainGroupDoneMessageCounts': [2],
    'drainSawRemovalStop': true,
    'drainRecipientSkippedCount': 0,
    'drainSignatureRejectedCount': 0,
    'drainDecodeSkippedCount': 0,
  },
  'charlieRejected': {
    'key': 'charlieAfterOfflineRemove',
    'messageId': 'm-c',
    'text': 'ML-006 Charlie after offline removal run',
    'outcome': 'groupNotFound',
    'senderPeerId': 'peer-c',
    'keyEpoch': 1,
    'accepted': false,
  },
  'aliceFinal': _snap('alice'),
  'bobFinal': _snap('bob'),
  'charlieFinal': _snap('charlie', epoch: 1, self: false),
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('observed ML-006/IR-004 offline removal passes the unchanged original oracle', () {
    expect(validateProductionGroupOfflineRemove(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie never went offline': (p) => p['charlieOffline'] = false,
    'Charlie had no old key': (p) => p['charlieStale']['keyEpoch'] = 2,
    'no drain after reconnect': (p) =>
        p['charlieDrain']['completedDrainCount'] = 0,
    'Charlie still a member after catch-up': (p) =>
        p['charlieFinal']['selfMember'] = true,
    'Charlie lost the retained group': (p) =>
        p['charlieFinal']['groupPresent'] = false,
    'Charlie got the rotated key': (p) => p['charlieFinal']['keyEpoch'] = 2,
    'Charlie leaked a post-removal message': (p) =>
        p['charlieFinal']['watched'] = {
          'bobAfterCharlieOfflineRemove': [
            _row('bobAfterCharlieOfflineRemove', incoming: true),
          ],
        },
    'Bob missed Alice': (p) =>
        p['bobGotAlice']['watched'] = <String, Object?>{},
    'Alice missed Bob': (p) =>
        p['aliceGotBob']['watched'] = <String, Object?>{},
    'Charlie send accepted': (p) {
      p['charlieRejected']['outcome'] = 'success';
      p['charlieRejected']['accepted'] = true;
    },
    'skipped a send flow': (p) =>
        (p['flows'] as List).remove('bob-after-remove'),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupOfflineRemove(proof), isNotEmpty);
    });
  }
}
