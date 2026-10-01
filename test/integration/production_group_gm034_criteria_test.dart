import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_gm034_criteria.dart';

final _t = productionGm034Texts('run');
const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};
const _pair = ['peer-a', 'peer-b'];
const _removedAt = '2026-10-01T12:00:05.000Z';
final _removalId =
    'sys-member_removed:g:peer-c:peer-a:'
    '${DateTime.parse(_removedAt).microsecondsSinceEpoch}';

Map<String, Object?> _row(String key, bool incoming) => {
  'messageId': 'm-$key',
  'groupId': 'g',
  'text': _t[key],
  'senderPeerId': 'peer-a',
  'timestamp': key == productionGm034BeforeKey
      ? '2026-10-01T12:00:01.000Z'
      : '2026-10-01T12:00:09.000Z',
  'keyEpoch': 2,
  'isIncoming': incoming,
  'status': incoming ? 'received' : 'sent',
};

Map<String, Object?> _snap(
  String role, {
  List<String> members = _pair,
  bool self = true,
  Map<String, Object?> watched = const {},
  Map<String, Object?> extra = const {},
}) => {
  'runId': 'run',
  'role': role,
  'scenario': 'gm034',
  'peerId': _p[role],
  'transportPeerId': _p[role],
  'lifecycle': 'resumed',
  'groupPresent': true,
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': 2,
  'groupConfigStateHash': 'hash',
  'memberPeerIds': members,
  'selfMember': self,
  'watched': watched,
  ...extra,
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'relayAddresses': expectedMultiPartyRelayAddresses,
  'peers': _p,
  'flows': [...productionGm034Flows],
  'aliceRemoved': _snap('alice', extra: {'lastMembershipEventAt': _removedAt}),
  for (final k in [productionGm034BeforeKey, productionGm034AfterKey])
    'got:$k:bob': _snap(
      'bob',
      watched: {
        k: [_row(k, true)],
      },
    ),
  'aliceFinal': _snap(
    'alice',
    watched: {
      for (final k in [productionGm034BeforeKey, productionGm034AfterKey])
        k: [_row(k, false)],
    },
    extra: {
      'deliveries': [
        {
          'messageId': 'm-$productionGm034BeforeKey',
          'ok': true,
          'recipientPeerIds': ['peer-b', 'peer-c'],
        },
        {
          'messageId': 'm-$productionGm034AfterKey',
          'ok': true,
          'recipientPeerIds': ['peer-b'],
        },
      ],
    },
  ),
  'bobFinal': _snap(
    'bob',
    watched: {
      for (final k in [productionGm034BeforeKey, productionGm034AfterKey])
        k: [_row(k, true)],
    },
    extra: {
      'configMemberPeerIds': _pair,
      'lastMembershipEventAt': _removedAt,
      'memberRemovedTimelineIds': [_removalId],
    },
  ),
  'charlieFinal': _snap('charlie', self: false),
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('observed GM-034 receive order passes the original oracle', () {
    expect(validateProductionGroupGm034(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'first message after the removal': (p) =>
        p['aliceRemoved']['lastMembershipEventAt'] = '2026-10-01T12:00:00.000Z',
    'second message before the removal': (p) =>
        p['aliceRemoved']['lastMembershipEventAt'] = '2026-10-01T12:00:10.000Z',
    'Bob config still lists Charlie': (p) =>
        p['bobFinal']['configMemberPeerIds'] = [..._pair, 'peer-c'],
    'no removal timeline row': (p) =>
        p['bobFinal']['memberRemovedTimelineIds'] = <String>[],
    'duplicate removal timeline row': (p) =>
        p['bobFinal']['memberRemovedTimelineIds'] = [_removalId, _removalId],
    'second copy addressed to Charlie': (p) =>
        p['aliceFinal']['deliveries'][1]['recipientPeerIds'] = [
          'peer-b',
          'peer-c',
        ],
    'first copy not addressed to Charlie': (p) =>
        p['aliceFinal']['deliveries'][0]['recipientPeerIds'] = ['peer-b'],
    'Bob persisted the first message twice': (p) =>
        (p['bobFinal']['watched'][productionGm034BeforeKey] as List).add(
          _row(productionGm034BeforeKey, true),
        ),
    'Charlie not self-removed': (p) => p['charlieFinal']['selfMember'] = true,
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupGm034(proof), isNotEmpty);
    });
  }
}
