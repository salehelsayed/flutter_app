import 'production_catalog_case.dart';

const _proof = 'h01VoluntaryLeaveConvergenceProof';
const _scenario = 'private_voluntary_leave_convergence';

/// Catalog `private_voluntary_leave_convergence` sends no proof messages.
Map<String, ProductionCatalogText> productionVoluntaryLeaveTexts(String run) =>
    const {};

const productionVoluntaryLeaveFlows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'charlie-leave-delete',
];

int _leaveRows(Map snapshot, String groupId, String leaver) =>
    ((snapshot['memberRemovedTimelineIds'] as List?) ?? const [])
        .where((id) => '$id'.startsWith('sys-member_removed:$groupId:$leaver:'))
        .length;

/// H-01. Charlie leaves through Orbit (Leave, Leave & Delete). His device
/// runs the durable exit once (one notice prepared and attempted, one
/// deferred rotation, one native topic leave) and hard-deletes the group,
/// keeping his identity; Alice re-keys and Alice and Bob each show exactly
/// one leave row, and nothing else, with Charlie off the roster.
List<String> validateProductionGroupVoluntaryLeave(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: _scenario,
      flows: productionVoluntaryLeaveFlows,
      verdicts: (c) {
        final charlie = c.peers['charlie'] as String;
        final before = c.stage('charlieBefore', 'charlie');
        final after = c.finalOf('charlie');
        final groupId = before['groupId'] as String;
        final exitBefore = proof['charlieExitBefore'] as Map;
        final exitAfter = proof['charlieExitAfter'] as Map;
        final exit = ((after['exits'] as Map?)?[groupId] as Map?) ?? const {};
        final counts = (exit['counts'] as Map?) ?? const {};
        final request = (exit['request'] as Map?) ?? const {};
        int count(String step) => (counts[step] as int?) ?? 0;
        final leavesBefore = ((before['topicLeaves'] as Map?)?[groupId] as int?) ?? 0;
        final leavesAfter = ((after['topicLeaves'] as Map?)?[groupId] as int?) ?? 0;
        final pendingId = request['pendingBroadcastId'];
        final deferred = exit['rotationDeferred'];

        Map<String, Object?> remaining(String role) {
          final start = c.stage('${role}Before', role);
          final end = c.finalOf(role);
          final rows = _leaveRows(end, groupId, charlie);
          return {
            'leaveTimelineRendered': rows > 0,
            'leaveTimelineRowCount': rows,
            'keyEpochAdvanced': c.epoch(role) > ((start['keyEpoch'] as int?) ?? 0),
            'initialKeyEpoch': start['keyEpoch'],
            'finalKeyEpoch': c.epoch(role),
            // The leave added its timeline row and no other message.
            'leaveWasSilent':
                (end['messageCount'] as int? ?? -1) -
                    (start['messageCount'] as int? ?? 0) ==
                rows,
            'charlieExcludedFromRoster': !c.members(end).contains(charlie),
          };
        }

        final alice = remaining('alice');
        final bob = remaining('bob');
        Map<String, Object?> labels(String role) => {
          'rowId': 'H-01',
          'scenario': _scenario,
          'proofRole': role,
        };
        return [
          c.verdict('alice', extra: {_proof: {...labels('alice'), ...alice}}),
          c.verdict('bob', extra: {_proof: {...labels('bob'), ...bob}}),
          c.verdict(
            'charlie',
            extra: {
              // Charlie's verdict concerns the group he left; its keys are
              // gone with it (0, as the original reports a missing key).
              'groupId': groupId,
              'keyEpoch': (exitAfter['latestKeyGeneration'] as int?) ?? 0,
              'memberPeerIds': const <String>[],
              'activeMemberPeerIds': const <String>[],
              _proof: {
                ...labels('charlie'),
                'charlieExcludedFromRoster': exitAfter['groupPresent'] == false,
                'leaveWasSilent':
                    alice['leaveWasSilent'] == true &&
                    bob['leaveWasSilent'] == true,
                'leaveTimelineRendered':
                    _leaveRows(exitAfter, groupId, charlie) > 0,
                'leaveTimelineRowCount': _leaveRows(exitAfter, groupId, charlie),
                'keyEpochAdvanced': false,
                'rotationDeferred': deferred == true,
                'groupHardDeletedLocally': exitAfter['groupPresent'] == false,
                'durableExitEvidence': {
                  'coordinatorStatus': request['status'],
                  'actionId': request['intentId'],
                  'sourceEventId': request['sourceEventId'],
                  'pendingBroadcastId': pendingId,
                  'requestCount': count('request_leave'),
                  'retryCount': count('request_retry'),
                  'noticePrepareCount': count('notice_prepare'),
                  'noticeAttemptCount': count('notice_attempt'),
                  'rotationAttemptCount': count('rotation_attempt'),
                  'rotationOutcome': deferred == null
                      ? null
                      : deferred == true
                      ? 'deferred'
                      : 'completed',
                  'nativeLeaveCount': count('native_leave'),
                  'intentPresentAfter': exitAfter['intentPresent'] != false,
                  'pendingBroadcastPresentAfter':
                      ((exitAfter['pendingBroadcastIds'] as List?) ?? const [])
                          .contains(pendingId),
                  'terminalIntentState': exitAfter['intentState'],
                  'bridgeGroupLeaveCountBefore': leavesBefore,
                  'bridgeGroupLeaveCountAfter': leavesAfter,
                  'bridgeGroupLeaveCountDelta': leavesAfter - leavesBefore,
                  'targetGroupPresentBefore': exitBefore['groupPresent'],
                  'targetGroupPresentAfter': exitAfter['groupPresent'],
                  'targetMessageCountAfter': exitAfter['messageCount'],
                  'leaveTimelineRowCountBefore':
                      _leaveRows(exitBefore, groupId, charlie),
                  'leaveTimelineRowCountAfter':
                      _leaveRows(exitAfter, groupId, charlie),
                  // The unrelated marker is Charlie's own identity, which a
                  // group exit must keep.
                  'unrelatedMarkerId': before['peerId'],
                  'unrelatedMarkerPresentBefore': before['peerId'] == charlie,
                  'unrelatedMarkerPresentAfter': after['peerId'] == charlie,
                },
              },
            },
          ),
        ];
      },
    );
