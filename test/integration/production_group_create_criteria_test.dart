import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_create_criteria.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';

Map<String, Object?> groupCreateProofFixture() {
  const roles = ['alice', 'bob', 'charlie'];
  Map<String, Object?> observation(String role, {bool message = false}) => {
    'runId': 'run',
    'scenario': 'private_abc_create',
    'role': role,
    'peerId': '$role-peer',
    'username': 'Journey$role',
    'transportPeerId': '$role-transport',
    'relayReady': true,
    'relayAddresses': expectedMultiPartyRelayAddresses,
    'group': {
      'id': 'group',
      'name': 'Catalog private_abc_create run',
      'createdBy': 'alice-peer',
      'type': 'chat',
      'topicName': 'topic',
      'keyEpoch': 1,
      'groupConfigStateHash': 'state',
      'members': [
        for (final r in roles)
          {'peerId': '$r-peer', 'role': r == 'alice' ? 'admin' : 'member'},
      ],
      'deliveryAttempts': [
        for (final r in ['bob', 'charlie'])
          {'peer_id': '$r-peer', 'status': 'sent', 'invite_id': 'invite-$r'},
      ],
      'messages': [
        for (final r in ['bob', 'charlie'])
          {'text': 'Journey$r joined the group'},
        if (message)
          {
            'messageId': 'message',
            'groupId': 'group',
            'senderPeerId': 'alice-peer',
            'text': 'ML-001 private ABC hello run',
            'keyEpoch': 1,
            'isIncoming': role != 'alice',
            'status': 'sent',
          },
      ],
    },
  };
  return {
    'runId': 'run',
    'created': observation('alice'),
    'beforeSend': {for (final r in roles) r: observation(r)},
    'final': {for (final r in roles) r: observation(r, message: true)},
    'pending': {
      for (final r in ['bob', 'charlie'])
        r: {
          'runId': 'run',
          'role': r,
          'pending': [
            {
              'inviteId': 'invite-$r',
              'groupId': 'group',
              'senderPeerId': 'alice-peer',
              'name': 'Catalog private_abc_create run',
            },
          ],
          'consumed': null,
        },
    },
    'accepted': {
      for (final r in ['bob', 'charlie'])
        r: {
          'runId': 'run',
          'role': r,
          'pending': [],
          'consumed': {'invite_id': 'invite-$r'},
        },
    },
    'ui': {
      for (final entry in {
        'create': 'production_catalog_group_create',
        'accept-bob': 'production_catalog_invite_accept',
        'accept-charlie': 'production_catalog_invite_accept',
        'send': 'production_catalog_group_send',
      }.entries)
        entry.key: {
          'status': 'PASS',
          'exit_status': 0,
          'flows': [entry.value],
          'path': entry.key,
        },
    },
  };
}

void main() {
  test(
    'retains original ML-001 terminal oracle and exact intermediate observations',
    () {
      expect(validateProductionGroupCreate(groupCreateProofFixture()), isEmpty);
    },
  );
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'missing role': (p) => (p['final'] as Map).remove('charlie'),
    'wrong role': (p) => p['final']['bob']['role'] = 'alice',
    'foreign run': (p) => p['final']['bob']['runId'] = 'foreign',
    'changed identity': (p) => p['final']['bob']['peerId'] = 'other',
    'wrong creator': (p) => p['created']['group']['createdBy'] = 'bob-peer',
    'two members only': (p) =>
        (p['created']['group']['members'] as List).removeLast(),
    'missing pending invite': (p) => p['pending']['bob']['pending'] = [],
    'wrong invitation sender': (p) =>
        p['pending']['bob']['pending'][0]['senderPeerId'] = 'charlie-peer',
    'wrong pending invitation': (p) =>
        p['pending']['bob']['pending'][0]['inviteId'] = 'stale',
    'undelivered invitation': (p) =>
        p['created']['group']['deliveryAttempts'][0]['status'] = 'queued',
    'unconsumed invitation': (p) => p['accepted']['bob']['consumed'] = null,
    'wrong consumed invitation': (p) =>
        p['accepted']['bob']['consumed']['invite_id'] = 'stale',
    'pending survives accept': (p) =>
        p['accepted']['bob']['pending'] = p['pending']['bob']['pending'],
    'missing join timeline': (p) =>
        (p['final']['bob']['group']['messages'] as List).removeAt(0),
    'changed epoch': (p) => p['final']['charlie']['group']['keyEpoch'] = 2,
    'changed state hash': (p) =>
        p['final']['charlie']['group']['groupConfigStateHash'] = 'diverged',
    'duplicate message': (p) => (p['final']['bob']['group']['messages'] as List)
        .add(p['final']['bob']['group']['messages'].last),
    'wrong message identity': (p) =>
        p['final']['bob']['group']['messages'].last['messageId'] = 'other',
    'wrong message epoch': (p) =>
        p['final']['bob']['group']['messages'].last['keyEpoch'] = 2,
    'message before send': (p) => p['beforeSend']['bob'] = p['final']['bob'],
    'send did not complete': (p) =>
        p['final']['alice']['group']['messages'].last['status'] = 'sending',
    'relay unavailable': (p) => p['final']['bob']['relayReady'] = false,
    'different relay': (p) => p['final']['bob']['relayAddresses'] = 'other',
    'failed UI': (p) => p['ui']['create']['status'] = 'FAIL',
    'wrong UI flow': (p) => p['ui']['send']['flows'] = ['other'],
    'reused UI receipt': (p) =>
        p['ui']['accept-charlie']['path'] = p['ui']['accept-bob']['path'],
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof =
          jsonDecode(jsonEncode(groupCreateProofFixture()))
              as Map<String, dynamic>;
      entry.value(proof);
      expect(validateProductionGroupCreate(proof), isNotEmpty);
    });
  }
}
