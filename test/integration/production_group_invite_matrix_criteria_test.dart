import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_invite_matrix_criteria.dart';

const _usernames = {
  'acceptedOne': 'Accepted One',
  'acceptedTwo': 'Accepted Two',
  'sent': 'Sent Member',
  'queued': 'Queued Member',
  'resend': 'Resend Member',
  'cannot': 'Cannot Member',
  'unknown': 'Unknown Member',
};

String _peer(String slot) => slot == 'acceptedOne' ? 'b' : 'matrix-run-$slot';

Map<String, dynamic> _stage(String role, {String lifecycle = 'resumed'}) => {
  'runId': 'run',
  'role': role,
  'selfPeerId': role == 'alice' ? 'a' : 'b',
  'groupId': 'invite-status-matrix-run',
  'lifecycle': lifecycle,
  'group': {
    'id': 'invite-status-matrix-run',
    'name': 'Invite Status Matrix run',
    'createdBy': 'a',
    'role': role == 'alice' ? 'admin' : 'member',
    'type': 'chat',
  },
  'members': [
    {
      'peerId': 'a',
      'username': 'Admin',
      'role': 'admin',
      'joinedEvidenceAt': null,
    },
    for (final slot in _usernames.keys)
      {
        'peerId': _peer(slot),
        'username': _usernames[slot],
        'role': 'writer',
        'joinedEvidenceAt': switch (slot) {
          'acceptedOne' => '2026-09-30T12:10:00.000Z',
          'acceptedTwo' => '2026-09-30T12:11:00.000Z',
          _ => null,
        },
      },
  ],
  'attempts': [
    for (final (slot, status, minute, error) in [
      ('acceptedTwo', 'sent', 8, null),
      ('sent', 'sent', 12, null),
      ('queued', 'queued', 13, null),
      ('resend', 'needsResend', 14, null),
      ('cannot', 'cannotSend', 15, 'missing_secure_key'),
    ])
      {
        'peerId': _peer(slot),
        'status': status,
        'lastError': error,
        'attemptedAt': '2026-09-30T12:${'$minute'.padLeft(2, '0')}:00.000Z',
        'updatedAt': '2026-09-30T12:${'$minute'.padLeft(2, '0')}:00.000Z',
      },
  ],
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'groupId': 'invite-status-matrix-run',
  'peers': {'alice': 'a', 'bob': 'b'},
  'creatorSeeded': _stage('alice', lifecycle: 'inactive'),
  'memberSeeded': _stage('bob', lifecycle: 'inactive'),
  'creatorObserved': _stage('alice'),
  'memberObserved': _stage('bob'),
  'flows': [...productionInviteMatrixFlowLabels],
  'cases': [
    {'id': 'UP-005', 'status': 'PASS'},
    {'id': 'MEMBER-ROLE-ATTACH', 'status': 'PASS'},
  ],
};

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

void main() {
  test('the original matrix over seeded production rows passes', () {
    expect(validateProductionGroupInviteMatrix(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'wrong attempt status': (p) =>
        ((p['creatorObserved']['attempts'] as List)[2] as Map)['status'] =
            'joined',
    'missing cannot-send error': (p) =>
        ((p['creatorSeeded']['attempts'] as List)[4] as Map)['lastError'] =
            null,
    'extra attempt for unknown member': (p) =>
        (p['memberSeeded']['attempts'] as List).add({
          'peerId': 'matrix-run-unknown',
          'status': 'sent',
          'lastError': null,
          'attemptedAt': '2026-09-30T12:16:00.000Z',
          'updatedAt': '2026-09-30T12:16:00.000Z',
        }),
    'missing member': (p) =>
        (p['creatorSeeded']['members'] as List).removeLast(),
    'unknown member has join evidence': (p) =>
        ((p['creatorSeeded']['members'] as List)[7]
                as Map)['joinedEvidenceAt'] =
            '2026-09-30T12:12:00.000Z',
    'accepted-two join before its attempt': (p) {
      for (final stage in [
        'creatorSeeded',
        'creatorObserved',
        'memberSeeded',
        'memberObserved',
      ]) {
        ((p[stage]['members'] as List)[2] as Map)['joinedEvidenceAt'] =
            '2026-09-30T12:07:00.000Z';
      }
    },
    'rows changed after the UI check': (p) =>
        ((p['memberObserved']['attempts'] as List)[1] as Map)['updatedAt'] =
            '2026-09-30T13:00:00.000Z',
    'member device claims admin': (p) =>
        (p['memberObserved']['group'] as Map)['role'] = 'admin',
    'wrong self identity': (p) => p['creatorObserved']['selfPeerId'] = 'b',
    'background lifecycle': (p) =>
        p['creatorObserved']['lifecycle'] = 'paused',
    'foreign group': (p) => p['groupId'] = 'invite-status-matrix-other',
    'same peer twice': (p) => (p['peers'] as Map)['bob'] = 'a',
    'skipped member flow': (p) => (p['flows'] as List).removeLast(),
    'missing member case': (p) => (p['cases'] as List).removeLast(),
    'failed case': (p) => ((p['cases'] as List)[0] as Map)['status'] = 'FAIL',
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupInviteMatrix(proof), isNotEmpty);
    });
  }
}
