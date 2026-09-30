import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_accept_criteria.dart';

Map<String, dynamic> _stage(
  String role, {
  List<Map<String, dynamic>> pending = const [],
  List<Map<String, dynamic>> groups = const [],
  int snackBars = 0,
  int conversations = 0,
}) => {
  'runId': 'run',
  'role': role,
  'selfPeerId': role == 'alice' ? 'a' : 'b',
  'lifecycle': 'resumed',
  'pending': pending,
  'groups': groups,
  'mountedSnackBars': snackBars,
  'mountedGroupConversations': conversations,
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'peers': {'alice': 'a', 'bob': 'b'},
  'invited': _stage(
    'bob',
    pending: [
      {'groupId': 'g', 'inviteId': 'i', 'senderPeerId': 'a'},
    ],
  ),
  'accepted': _stage(
    'bob',
    groups: [
      {'id': 'g', 'createdBy': 'a', 'role': 'member'},
    ],
    conversations: 1,
  ),
  'creator': _stage(
    'alice',
    groups: [
      {'id': 'g', 'createdBy': 'a', 'role': 'admin'},
    ],
    conversations: 1,
  ),
  'flows': [...productionAcceptFlowLabels],
  'cases': [
    {'id': 'INVITE_ACCEPT_SPINNER', 'status': 'PASS'},
  ],
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('accept that opens the joined group passes', () {
    expect(validateProductionGroupAccept(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'pending invite not cleared': (p) =>
        p['accepted']['pending'] = p['invited']['pending'],
    'group never persisted': (p) => p['accepted']['groups'] = [],
    'different group persisted': (p) =>
        (p['accepted']['groups'] as List)[0]['id'] = 'other',
    'confirmation snackbar shown': (p) => p['accepted']['mountedSnackBars'] = 1,
    'group chat not opened': (p) =>
        p['accepted']['mountedGroupConversations'] = 0,
    'invite from another sender': (p) =>
        (p['invited']['pending'] as List)[0]['senderPeerId'] = 'x',
    'group existed before accept': (p) =>
        p['invited']['groups'] = p['accepted']['groups'],
    'bob made admin': (p) =>
        (p['accepted']['groups'] as List)[0]['role'] = 'admin',
    'creator lost the group': (p) => p['creator']['groups'] = [],
    'background lifecycle': (p) => p['accepted']['lifecycle'] = 'paused',
    'wrong role binding': (p) => p['accepted']['selfPeerId'] = 'a',
    'skipped accept flow': (p) => (p['flows'] as List).removeLast(),
    'missing case': (p) => (p['cases'] as List).clear(),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupAccept(proof), isNotEmpty);
    });
  }
}
