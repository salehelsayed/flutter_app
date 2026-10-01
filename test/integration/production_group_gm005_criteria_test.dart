import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_gm005_criteria.dart';

final _t = productionGm005Texts('run');
const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};

Map<String, Object?> _row(String key, {required bool incoming}) => {
  'messageId': 'm-$key',
  'groupId': 'g',
  'text': _t[key],
  'senderPeerId': 'peer-a',
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
  'scenario': 'gm005',
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
  'flows': [...productionGm005Flows],
  'charlieStale': _snap(
    'charlie',
    epoch: 1,
    members: ['peer-a', 'peer-b', 'peer-c'],
  ),
  'charlieOffline': true,
  for (var i = 1; i <= 3; i++) ...{
    'aliceSent$i': _snap(
      'alice',
      watched: {
        'aliceAfterCharlieOfflineRemove$i': [
          _row('aliceAfterCharlieOfflineRemove$i', incoming: false),
        ],
      },
    ),
    'bobGot$i': _snap(
      'bob',
      watched: {
        'aliceAfterCharlieOfflineRemove$i': [
          _row('aliceAfterCharlieOfflineRemove$i', incoming: true),
        ],
      },
    ),
  },
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
    'text': 'GM-005 Charlie after offline removal run',
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
  test('observed GM-005 offline removal passes the unchanged original oracle', () {
    expect(validateProductionGroupGm005(fixture()), isEmpty);
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
          'aliceAfterCharlieOfflineRemove2': [
            _row('aliceAfterCharlieOfflineRemove2', incoming: true),
          ],
        },
    'Bob missed one message': (p) => p['bobGot3']['watched'] = <String, Object?>{},
    'Charlie send accepted': (p) {
      p['charlieRejected']['outcome'] = 'success';
      p['charlieRejected']['accepted'] = true;
    },
    'skipped a send flow': (p) =>
        (p['flows'] as List).remove('alice-after-remove-2'),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupGm005(proof), isNotEmpty);
    });
  }
}
