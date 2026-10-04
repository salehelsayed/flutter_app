import 'production_catalog_case.dart';

const _bob = 'bobAfterBlockedAdminSelfRemoval';
const _charlie = 'charlieAfterBlockedAdminLeave';
const _proof = 'gm015AdminSelfRemovalPolicyProof';

/// Texts of catalog `gm015`, identical to the original harness.
Map<String, ProductionCatalogText> productionGm015Texts(String run) => {
  _bob: (role: 'bob', text: 'GM-015 Bob after blocked admin self-removal $run'),
  _charlie: (
    role: 'charlie',
    text: 'GM-015 Charlie after blocked admin leave $run',
  ),
};

const productionGm015Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-leave-blocked',
  'bob-post-attempt',
  'charlie-post-attempt',
];

/// GM-015. Alice, the only admin, taps Leave Group in Group Info: the app
/// refuses (blockedLastAdmin) without any exit step, membership, role, key
/// or group change on any device; Bob and Charlie then each reach the other
/// two members.
List<String> validateProductionGroupGm015(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'gm015',
      flows: productionGm015Flows,
      verdicts: (c) {
        final before = c.stage('aliceBefore', 'alice');
        final groupId = before['groupId'] as String;
        final after = c.stage('aliceAfterAttempt', 'alice');
        final exit = ((after['exits'] as Map?)?[groupId] as Map?) ?? const {};
        final counts = (exit['counts'] as Map?) ?? const {};
        final request = (exit['request'] as Map?) ?? const {};
        final exitAfter = proof['aliceExitAfter'] as Map;
        int count(String step) => (counts[step] as int?) ?? 0;
        int leaves(Map s) => ((s['topicLeaves'] as Map?)?[groupId] as int?) ?? 0;
        int leaveRows(Map s) =>
            ((s['memberRemovedTimelineIds'] as List?) ?? const [])
                .where(
                  (id) => '$id'.startsWith(
                    'sys-member_removed:$groupId:${c.peers['alice']}:',
                  ),
                )
                .length;

        Map<String, Object?> shared(String role) {
          final start = c.stage('${role}Before', role);
          final end = c.finalOf(role);
          final admins = [
            for (final m in (end['memberDetails'] as List?) ?? const [])
              if ((m as Map)['role'] == 'admin') m['peerId'],
          ];
          return {
            'groupPresent': end['groupPresent'],
            'groupDissolved': end['isDissolved'],
            'creatorPeerId': end['createdBy'],
            'finalMemberPeerIds': end['memberPeerIds'],
            'adminPeerIds': admins,
            'memberListHasActiveAdmin': admins.isNotEmpty,
            'mutationAfterBlockedAttempt':
                c.members(start).length != c.members(end).length ||
                !c.members(start).containsAll(c.members(end)),
            'keyEpochUnchanged': start['keyEpoch'] == c.epoch(role),
            'initialKeyEpoch': start['keyEpoch'],
            'finalKeyEpoch': c.epoch(role),
          };
        }

        final bobSent = c.sent('bob', _bob);
        final charlieSent = c.sent('charlie', _charlie);
        final aliceBob = c.received('alice', _bob);
        final aliceCharlie = c.received('alice', _charlie);
        final bobCharlie = c.received('bob', _charlie);
        final charlieBob = c.received('charlie', _bob);
        return [
          c.verdict(
            'alice',
            received: [aliceBob, aliceCharlie],
            extra: {
              _proof: {
                ...shared('alice'),
                'receivedBobPostAttemptSend': aliceBob != null,
                'receivedCharliePostAttemptSend': aliceCharlie != null,
                'durableExitEvidence': {
                  'coordinatorStatus': request['status'],
                  'actionId': request['intentId'],
                  'sourceEventId': request['sourceEventId'],
                  'pendingBroadcastId': request['pendingBroadcastId'],
                  'requestCount': count('request_leave'),
                  'retryCount': count('request_retry'),
                  'noticePrepareCount': count('notice_prepare'),
                  'noticeAttemptCount': count('notice_attempt'),
                  'rotationAttemptCount': count('rotation_attempt'),
                  'rotationOutcome': exit['rotationDeferred'] == null
                      ? null
                      : exit['rotationDeferred'] == true
                      ? 'deferred'
                      : 'completed',
                  'nativeLeaveCount': count('native_leave'),
                  'intentPresentAfter': exitAfter['intentPresent'] != false,
                  'pendingBroadcastPresentAfter':
                      ((exitAfter['pendingBroadcastIds'] as List?) ?? const [])
                          .isNotEmpty,
                  'terminalIntentState': exitAfter['intentState'],
                  'bridgeGroupLeaveCountBefore': leaves(before),
                  'bridgeGroupLeaveCountAfter': leaves(after),
                  'bridgeGroupLeaveCountDelta': leaves(after) - leaves(before),
                  'targetGroupPresentBefore': before['groupPresent'],
                  'targetGroupPresentAfter': after['groupPresent'],
                  'leaveTimelineRowCountBefore': leaveRows(before),
                  'leaveTimelineRowCountAfter': leaveRows(after),
                },
              },
            },
          ),
          c.verdict(
            'bob',
            sent: [bobSent],
            received: [bobCharlie],
            extra: {
              _proof: {
                ...shared('bob'),
                'sentBobPostAttemptSend': bobSent?['accepted'] == true,
                'receivedCharliePostAttemptSend': bobCharlie != null,
              },
            },
          ),
          c.verdict(
            'charlie',
            sent: [charlieSent],
            received: [charlieBob],
            extra: {
              _proof: {
                ...shared('charlie'),
                'sentCharliePostAttemptSend': charlieSent?['accepted'] == true,
                'receivedBobPostAttemptSend': charlieBob != null,
              },
            },
          ),
        ];
      },
    );
