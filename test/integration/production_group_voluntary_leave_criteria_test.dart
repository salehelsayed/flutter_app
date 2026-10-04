import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_voluntary_leave_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture(
  'private_voluntary_leave_convergence',
  productionVoluntaryLeaveTexts('run'),
  productionVoluntaryLeaveFlows,
);
const _leaveRow = 'sys-member_removed:g:peer-c:1';

Map<String, dynamic> fixture() {
  final p = _f.base();
  for (final r in ['alice', 'bob']) {
    p['${r}Before'] = _f.snap(r, epoch: 1, extra: {'messageCount': 4});
    p['${r}Final'] = _f.snap(
      r,
      members: const ['peer-a', 'peer-b'],
      epoch: 2,
      extra: {
        'messageCount': 5,
        'memberRemovedTimelineIds': [_leaveRow],
      },
    );
  }
  p['charlieBefore'] = _f.snap('charlie', epoch: 1, extra: {'topicLeaves': {}});
  p['charlieFinal'] = {
    ..._f.snap('charlie', extra: {
      'topicLeaves': {'g': 1},
      'exits': {
        'g': {
          'counts': {
            'request_leave': 1,
            'notice_prepare': 1,
            'notice_attempt': 1,
            'rotation_attempt': 1,
            'rotation_result': 1,
            'native_leave': 1,
          },
          'request': {
            'status': 'started',
            'intentId': 'intent-1',
            'sourceEventId': 'event-1',
            'pendingBroadcastId': 'pending-1',
          },
          'rotationDeferred': true,
        },
      },
    }),
    'groupPresent': false,
    'groupId': null,
    'memberPeerIds': null,
    'keyEpoch': null,
  };
  p['charlieExitBefore'] = {
    'groupPresent': true,
    'messageCount': 4,
    'memberRemovedTimelineIds': <String>[],
    'intentPresent': false,
    'pendingBroadcastIds': <String>[],
  };
  p['charlieExitAfter'] = {
    'groupPresent': false,
    'messageCount': 0,
    'memberRemovedTimelineIds': <String>[],
    'intentPresent': false,
    'intentState': null,
    'pendingBroadcastIds': <String>[],
  };
  return p;
}

void main() {
  test('observed H-01 voluntary leave passes the original oracle', () {
    expect(validateProductionGroupVoluntaryLeave(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'the leave was blocked': (p) =>
        p['charlieFinal']['exits']['g']['request']['status'] = 'blockedLastAdmin',
    'no exit request observed': (p) => p['charlieFinal']['exits'] = {},
    'the notice was attempted twice': (p) =>
        p['charlieFinal']['exits']['g']['counts']['notice_attempt'] = 2,
    'the rotation completed on the leaver': (p) =>
        p['charlieFinal']['exits']['g']['rotationDeferred'] = false,
    'no native topic leave': (p) => p['charlieFinal']['topicLeaves'] = {},
    'the group survived locally': (p) =>
        p['charlieExitAfter']['groupPresent'] = true,
    'the exit intent was left behind': (p) =>
        p['charlieExitAfter']['intentPresent'] = true,
    'Bob still lists Charlie': (p) =>
        p['bobFinal']['memberPeerIds'] = CatalogFixture.all,
    'Alice never re-keyed': (p) => p['aliceFinal']['keyEpoch'] = 1,
    'Bob shows no leave row': (p) =>
        p['bobFinal']['memberRemovedTimelineIds'] = <String>[],
    'the leave added a visible message': (p) =>
        p['aliceFinal']['messageCount'] = 6,
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupVoluntaryLeave(proof), isNotEmpty);
    });
  }
}
