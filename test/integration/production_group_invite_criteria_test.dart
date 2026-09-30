import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_invite_criteria.dart';

Map<String, dynamic> fixture() {
  final result = <String, dynamic>{
    'runId': 'run',
    'groupId': 'group',
    'peers': {'alice': 'a', 'bob': 'b'},
    'metadataRequest': {
      'result': 'success',
      'groupId': 'group',
      'requesterPeerId': 'b',
      'inviterPeerId': 'a',
    },
    'waits': {
      'receivedFirst': 240000,
      'declinedSender': 150000,
      'receivedSecond': 150000,
      'revokedRecipient': 150000,
      'convergedRecipient': 240000,
    },
    'cases': [
      for (final id in ['F', 'C', 'D']) {'id': id, 'status': 'PASS'},
    ],
  };
  for (final entry in {
    'created': 'alice',
    'receivedFirst': 'bob',
    'declinedRecipient': 'bob',
    'declinedSender': 'alice',
    'resent': 'alice',
    'receivedSecond': 'bob',
    'revokedSender': 'alice',
    'revokedRecipient': 'bob',
    'staleRecipient': 'bob',
    'freshSender': 'alice',
    'convergedRecipient': 'bob',
  }.entries) {
    final stage = entry.key;
    final fresh = stage == 'freshSender' || stage == 'convergedRecipient';
    final old =
        stage == 'created' ||
        stage == 'declinedSender' ||
        stage == 'receivedFirst';
    result[stage] = {
      'runId': 'run',
      'role': entry.value,
      'peerId': entry.value == 'bob' ? 'a' : 'b',
      'groupId': 'group',
      'lifecycle': 'resumed',
      'group': {
        'id': 'group',
        'name': 'Invite Reliability run${fresh ? ' (fresh)' : ''}',
        'createdBy': 'a',
        'role': entry.value == 'bob' ? 'member' : 'admin',
        'type': 'chat',
        'metadataAt': fresh
            ? '2026-09-27T12:00:01.000Z'
            : '2026-09-27T12:00:00.000Z',
      },
      'members': [
        {'peerId': 'a', 'role': 'admin'},
        {'peerId': 'b', 'role': 'writer'},
      ],
      'keyGeneration': 1,
      'attempt': {
        'group_id': 'group',
        'peer_id': 'b',
        'invite_id': old ? 'first' : 'second',
        'status': stage == 'declinedSender'
            ? 'declined'
            : stage == 'revokedSender'
            ? 'revoked'
            : 'sent',
      },
      'pending': [
        if (stage == 'receivedFirst' || stage == 'receivedSecond')
          {
            'groupId': 'group',
            'inviteId': old ? 'first' : 'second',
            'senderPeerId': 'a',
            'name': 'Invite Reliability run',
          },
      ],
      'consumed': [
        {'group_id': 'group', 'invite_id': 'first'},
      ],
      'revoked': [
        if (stage == 'revokedRecipient')
          {'group_id': 'group', 'invite_id': 'second', 'revoked_by': 'a'},
      ],
    };
  }
  return jsonDecode(jsonEncode(result)) as Map<String, dynamic>;
}

void main() {
  test(
    'accepts original F C D facts at exact original deadline boundaries',
    () {
      expect(validateProductionGroupInvite(fixture()), isEmpty);
    },
  );
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'missing run': (p) => p.remove('runId'),
    'same peers': (p) => p['peers']['bob'] = 'a',
    'missing intermediate': (p) => p.remove('receivedSecond'),
    'foreign group': (p) => p['declinedSender']['groupId'] = 'foreign',
    'wrong role': (p) => p['receivedFirst']['role'] = 'alice',
    'foreign peer': (p) => p['receivedSecond']['peerId'] = 'foreign',
    'background observation': (p) =>
        p['revokedRecipient']['lifecycle'] = 'paused',
    'wrong creator': (p) => p['created']['group']['createdBy'] = 'b',
    'lost admin': (p) => p['created']['group']['role'] = 'member',
    'wrong group type': (p) => p['created']['group']['type'] = 'announcement',
    'missing member': (p) => p['created']['members'].removeLast(),
    'duplicate member': (p) =>
        p['created']['members'].add(p['created']['members'][0]),
    'unintended key rotation': (p) =>
        p['convergedRecipient']['keyGeneration'] = 2,
    'missing received invite': (p) => p['receivedFirst']['pending'] = [],
    'duplicate received invite': (p) =>
        p['receivedSecond']['pending'].add(p['receivedSecond']['pending'][0]),
    'untrusted inviter': (p) =>
        p['receivedFirst']['pending'][0]['senderPeerId'] = 'foreign',
    'stale resent ID': (p) =>
        p['receivedSecond']['pending'][0]['inviteId'] = 'first',
    'unbound delivery ID': (p) =>
        p['resent']['attempt']['invite_id'] = 'foreign',
    'missing persisted delivery ID': (p) =>
        p['created']['attempt'].remove('invite_id'),
    'decline ack absent': (p) =>
        p['declinedSender']['attempt']['status'] = 'sent',
    'failed send': (p) => p['resent']['attempt']['status'] = 'cannot_send',
    'revocation not committed': (p) =>
        p['revokedSender']['attempt']['status'] = 'sent',
    'declined pending retained': (p) =>
        p['declinedRecipient']['pending'] = [{}],
    'missing decline consumption': (p) =>
        p['declinedRecipient']['consumed'] = [],
    'wrong consumed ID': (p) =>
        p['declinedRecipient']['consumed'][0]['invite_id'] = 'second',
    'missing revocation tombstone': (p) =>
        p['revokedRecipient']['revoked'] = [],
    'revokes old invite': (p) =>
        p['revokedRecipient']['revoked'][0]['invite_id'] = 'first',
    'untrusted revoker': (p) =>
        p['revokedRecipient']['revoked'][0]['revoked_by'] = 'foreign',
    'revoked pending retained': (p) => p['revokedRecipient']['pending'] = [{}],
    'fixture already fresh': (p) =>
        p['staleRecipient']['group']['name'] = 'Invite Reliability run (fresh)',
    'metadata unchanged': (p) => p['freshSender']['group']['metadataAt'] =
        p['staleRecipient']['group']['metadataAt'],
    'metadata timestamp mismatch': (p) =>
        p['convergedRecipient']['group']['metadataAt'] =
            '2026-09-27T12:00:02.000Z',
    'config request failed': (p) =>
        p['metadataRequest']['result'] = 'sendFailed',
    'wrong config requester': (p) =>
        p['metadataRequest']['requesterPeerId'] = 'a',
    'missing deadline evidence': (p) => p['waits'].remove('receivedFirst'),
    'extended first deadline': (p) => p['waits']['receivedFirst'] = 240001,
    'extended decline deadline': (p) => p['waits']['declinedSender'] = 150001,
    'extended resend deadline': (p) => p['waits']['receivedSecond'] = 150001,
    'extended revoke deadline': (p) => p['waits']['revokedRecipient'] = 150001,
    'extended metadata deadline': (p) =>
        p['waits']['convergedRecipient'] = 240001,
    'missing terminal': (p) => p['cases'].removeLast(),
    'duplicate terminal': (p) => p['cases'][2] = p['cases'][1],
    'skipped terminal': (p) => p['cases'][1]['status'] = 'SKIP',
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = fixture();
      entry.value(proof);
      expect(validateProductionGroupInvite(proof), isNotEmpty);
    });
  }
}
