import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_online_remove_criteria.dart';

final _relay = expectedMultiPartyRelayAddresses;
final _t = productionOnlineRemoveTexts('run');
const _peers = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};

Map<String, Object?> _row(String key, {required bool incoming, int epoch = 2}) => {
  'messageId': 'm-$key',
  'groupId': 'g',
  'text': _t[key],
  'senderPeerId': key.startsWith('alice') ? 'peer-a' : 'peer-b',
  'timestamp': '2026-09-30T12:00:00.000Z',
  'keyEpoch': epoch,
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
  List<Map<String, Object?>>? media,
}) => {
  'runId': 'run',
  'role': role,
  'scenario': 'private_online_remove',
  'peerId': _peers[role],
  'transportPeerId': _peers[role],
  'relayReady': true,
  'lifecycle': 'resumed',
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': epoch,
  'groupConfigStateHash': role == 'charlie' ? 'stale-hash' : 'hash',
  'memberPeerIds': members,
  'selfMember': self,
  'groupPresent': present,
  'watched': watched,
  'media': ?media,
  'pendingDownloads': 0,
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'relayAddresses': _relay,
  'peers': _peers,
  'flows': [...productionOnlineRemoveFlows],
  'order': {'bobRotatedAtMs': 100, 'aliceSendStartMs': 200},
  'charlieBefore': _snap(
    'charlie',
    epoch: 1,
    members: ['peer-a', 'peer-b', 'peer-c'],
  ),
  'rotationHeld': {'held': true, 'released': false, 'keyEpoch': 1},
  'rotationAtSt006Receive': {'held': true, 'released': false, 'keyEpoch': 1},
  'bobExcluded': _snap('bob', epoch: 1),
  'charlieRemoved': _snap('charlie', epoch: 1, self: false),
  'st006Sent': _snap(
    'bob',
    epoch: 1,
    watched: {
      'st006BobDuringRotation': [
        _row('st006BobDuringRotation', incoming: false, epoch: 1),
      ],
    },
  ),
  'st006Received': _snap(
    'alice',
    epoch: 1,
    watched: {
      'st006BobDuringRotation': [
        _row('st006BobDuringRotation', incoming: true, epoch: 1),
      ],
    },
  ),
  'bobRotated': _snap('bob'),
  'aliceSent': {
    'key': 'aliceAfterCharlieRemove',
    'messageId': 'm-aliceAfterCharlieRemove',
    'text': _t['aliceAfterCharlieRemove'],
    'outcome': 'success',
    'senderPeerId': 'peer-a',
    'keyEpoch': 2,
    'accepted': true,
    'mediaAttachments': [
      {'id': 'pl006-post-removal-media-run', 'mime': 'image/png', 'size': 75},
    ],
    'upload': {
      'blobId': 'pl006-post-removal-media-run',
      'allowedPeers': ['peer-a', 'peer-b'],
      'uploadAllowedPeersExcludeRemoved': true,
      'uploadAllowedPeersIncludeActive': true,
      'uploadAllowedPeersCount': 2,
    },
  },
  'bobReceivedAlice': _snap(
    'bob',
    watched: {
      'aliceAfterCharlieRemove': [
        _row('aliceAfterCharlieRemove', incoming: true),
      ],
    },
  ),
  'bobMedia': {
    'media': [
      {'id': 'pl006-post-removal-media-run', 'downloadStatus': 'done'},
    ],
  },
  'bobSentAfter': _snap(
    'bob',
    watched: {
      'bobAfterCharlieRemove': [_row('bobAfterCharlieRemove', incoming: false)],
    },
  ),
  'aliceReceivedBob': _snap(
    'alice',
    watched: {
      'bobAfterCharlieRemove': [_row('bobAfterCharlieRemove', incoming: true)],
    },
  ),
  'charlieDownload': {
    'ok': false,
    'directDownloadDenied': true,
    'outputBytes': 0,
    'noDirectDownloadPlaintext': true,
    'errorMessage': 'forbidden',
  },
  'charlieLeak': _snap('charlie', epoch: 1, self: false, media: []),
  'charlieRejected': {
    'key': 'charlieAfterCharlieRemove',
    'messageId': 'm-charlie',
    'text': 'GM-004 Charlie after removal run',
    'outcome': 'unauthorized',
    'senderPeerId': 'peer-c',
    'keyEpoch': 1,
    'accepted': false,
  },
  'charlieFinal': _snap('charlie', epoch: 1, self: false),
  'aliceFinal': _snap('alice'),
  'bobFinal': _snap('bob'),
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('observed online removal passes the unchanged original oracle', () {
    expect(validateProductionGroupOnlineRemove(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'rotation never held': (p) => p['rotationHeld']['held'] = false,
    'Bob published after the release': (p) =>
        p['rotationAtSt006Receive']['released'] = true,
    'Alice sent before Bob rotated': (p) =>
        p['order']['aliceSendStartMs'] = 50,
    'Alice sent at the old epoch': (p) => p['aliceSent']['keyEpoch'] = 1,
    'Charlie still receives Alice': (p) =>
        p['charlieLeak']['watched'] = {
          'aliceAfterCharlieRemove': [
            _row('aliceAfterCharlieRemove', incoming: true),
          ],
        },
    'Charlie send accepted': (p) {
      p['charlieRejected']['outcome'] = 'success';
      p['charlieRejected']['accepted'] = true;
    },
    'Charlie downloaded the media': (p) {
      p['charlieDownload']['ok'] = true;
      p['charlieDownload']['directDownloadDenied'] = false;
      p['charlieDownload']['outputBytes'] = 75;
      p['charlieDownload']['noDirectDownloadPlaintext'] = false;
    },
    'Charlie holds the rotated key': (p) =>
        p['charlieFinal']['keyEpoch'] = 2,
    'Charlie lost the retained group': (p) =>
        p['charlieFinal']['groupPresent'] = false,
    'upload allowed Charlie': (p) {
      p['aliceSent']['upload']['allowedPeers'] = ['peer-a', 'peer-b', 'peer-c'];
      p['aliceSent']['upload']['uploadAllowedPeersExcludeRemoved'] = false;
      p['aliceSent']['upload']['uploadAllowedPeersCount'] = 3;
    },
    'Bob media not downloaded': (p) =>
        p['bobMedia']['media'][0]['downloadStatus'] = 'pending',
    'Bob reply never arrived': (p) =>
        p['aliceReceivedBob']['watched'] = <String, Object?>{},
    'Alice still lists Charlie': (p) =>
        p['aliceFinal']['memberPeerIds'] = ['peer-a', 'peer-b', 'peer-c'],
    'Bob lacks rotated epoch': (p) => p['bobFinal']['keyEpoch'] = 1,
    'duplicate received row': (p) =>
        (p['bobReceivedAlice']['watched']['aliceAfterCharlieRemove'] as List)
            .add(_row('aliceAfterCharlieRemove', incoming: true)),
    'skipped verify flow': (p) =>
        (p['flows'] as List).remove('remove-charlie-verify'),
    'wrong device role': (p) => p['bobFinal']['peerId'] = 'peer-a',
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupOnlineRemove(proof), isNotEmpty);
    });
  }
}
