import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/production_introduction_mutual_criteria.dart';
import '../../../tool/sims/production_introduction_offline_criteria.dart';

const _run = 'introduction-offline-fixture';

Map<String, Object?> _lifecycleProof() {
  const roles = ['alice', 'bob', 'charlie'];
  final peers = {for (final role in roles) role: '$role-account'};
  final names = {for (final role in roles) role: 'Journey$role'};
  final nonces = {
    for (final role in roles)
      role: ['$role-first', '$role-second', if (role != 'alice') '$role-third'],
  };
  final ui = <String, Object?>{};
  void receipt(String label, String flow, Map<String, String> args) {
    ui[label] = {
      'path': '$label.json',
      'flow': flow,
      'values': args,
      'receipt': {
        'status': 'PASS',
        'exit_status': 0,
        'flows': [flow],
      },
    };
  }

  receipt('introduce', 'production_intro_send_one', {
    'RECIPIENT_PATTERN': 'Journeybob',
    'FRIEND_PATTERN': 'Journeycharlie',
  });
  final text = introductionMutualText(_run), pattern = RegExp.escape(text);
  for (final role in ['bob', 'charlie']) {
    final other = role == 'bob' ? 'charlie' : 'bob';
    receipt('natural-pending-$role', 'production_intro_review_pending', {
      'OTHER_PATTERN': names[other]!,
      'INTRODUCER_PATTERN': names['alice']!,
    });
    receipt('accept-$role', 'production_intro_decide', {
      'OTHER_PATTERN': names[other]!,
      'DECISION_PATTERN': 'Accept',
      'EXPECTED_STATE_PATTERN': role == 'bob'
          ? 'Waiting for Journeycharlie'
          : 'No introductions yet',
    });
    receipt('$role-ready', 'production_direct_open', {
      'PEER_ID': peers[other]!,
    });
    receipt('reopen-$role', 'production_direct_open', {
      'PEER_ID': peers[other]!,
    });
    receipt('replayed-$role', 'production_intro_read_chat', {
      'MESSAGE_PATTERN': pattern,
    });
  }
  receipt('send-bob', 'production_direct_send', {
    'MESSAGE': text,
    'MESSAGE_PATTERN': pattern,
  });
  receipt('received-charlie', 'production_intro_read_chat', {
    'MESSAGE_PATTERN': pattern,
  });
  Map<String, Object?> snapshot(String role, String phase) {
    final connected = phase == 'mutual' || phase == 'restarted';
    final other = role == 'bob' ? 'charlie' : 'bob';
    return {
      'identity': {'peerId': peers[role], 'username': names[role]},
      'contacts': <Map<String, Object?>>[
        if (role == 'alice') ...[
          for (final peer in ['bob', 'charlie'])
            {
              'peerId': peers[peer],
              'username': names[peer],
              'introducedByPeerId': null,
            },
        ] else ...[
          {
            'peerId': peers['alice'],
            'username': names['alice'],
            'introducedByPeerId': null,
          },
          if (connected)
            {
              'peerId': peers[other],
              'username': names[other],
              'introducedByPeerId': peers['alice'],
            },
        ],
      ],
      'introductions': <Map<String, Object?>>[
        if (phase != 'before')
          {
            'id': 'one-owned-introduction',
            'introducerId': peers['alice'],
            'recipientId': peers['bob'],
            'introducedId': peers['charlie'],
            'recipientStatus': connected ? 'accepted' : 'pending',
            'introducedStatus': connected ? 'accepted' : 'pending',
            'overallStatus': connected ? 'mutual_accepted' : 'pending',
          },
      ],
      'chatMessages': <Map<String, Object?>>[
        if (connected && role != 'alice')
          {
            'contactPeerId': peers[other],
            'messages': <Map<String, Object?>>[
              {
                'id': 'one-owned-chat',
                'text': text,
                'timestamp': role == 'charlie'
                    ? '2026-10-23T16:00:00.000+02:00'
                    : '2026-10-23T14:00:00.000Z',
                'isIncoming': role == 'charlie',
                'status': 'delivered',
                'transport': 'inbox',
              },
            ],
          },
      ],
      'introOutboxDeliveries': [],
    };
  }

  return {
    'runId': _run,
    'runtimeScenario': introductionMutualRuntime,
    'offlineOutbox': true,
    'emulatorTopology': true,
    'prepareContactMesh': false,
    'peers': peers,
    'names': names,
    'nonces': nonces,
    'ui': ui,
    'manualEdges': [
      for (final (actor, peer) in [
        ('alice', 'bob'),
        ('bob', 'alice'),
        ('alice', 'charlie'),
        ('charlie', 'alice'),
      ])
        {'actor': actor, 'peer': peer},
    ],
    'ownedKills': {
      for (final role in ['bob', 'charlie']) role: {'verifiedUidKill': true},
      for (final role in roles) '$role-offline': {'verifiedUidKill': true},
    },
    'trace': [
      for (final role in roles) 'probe-before-$role',
      'introduce',
      'offers-offline-snapshot',
      'kill-offline-alice',
      'restart-offline-alice',
      'natural-pending-bob',
      'natural-pending-charlie',
      for (final role in roles) 'probe-pending-$role',
      'accept-bob',
      'probe-first-accept-charlie',
      'response-offline-window',
      'accept-charlie',
      'response-ready-charlie',
      'probe-response-committed-charlie',
      'kill-offline-charlie',
      'response-offline-snapshot',
      'kill-offline-bob',
      'restart-offline-charlie',
      'restart-offline-bob',
      'bob-ready',
      'charlie-ready',
      'send-bob',
      'received-charlie',
      for (final role in roles) 'probe-mutual-$role',
      'kill-bob',
      'kill-charlie',
      'reopen-bob',
      'replayed-bob',
      'reopen-charlie',
      'replayed-charlie',
      for (final role in roles) 'probe-restarted-$role',
    ],
    'phases': {
      for (final phase in ['before', 'pending', 'mutual', 'restarted'])
        phase: {
          for (final role in roles)
            role: {
              'stepId': 'probe-$phase-$role',
              'status': 'complete',
              'success': true,
              'observedRunId': _run,
              'observedRole': role,
              'observedNonce':
                  nonces[role]![phase == 'before'
                      ? 0
                      : role == 'alice'
                      ? 1
                      : phase == 'pending'
                      ? 0
                      : phase == 'restarted'
                      ? 2
                      : 1],
              'probePreambleDrainsInbox': true,
              'snapshot': snapshot(role, phase),
            },
        },
    },
  };
}

Map _snapshot(Map proof, String phase, String role) =>
    (proof['phases'] as Map)[phase][role]['snapshot'] as Map;

Map<String, Object?> _clone(Object? value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

Map<String, Object?> _proof() {
  final proof = _lifecycleProof();
  final ui = proof['ui'] as Map;
  ui['response-ready-charlie'] = {
    'path': 'response-ready-charlie.json',
    'flow': 'production_intro_ready_chat',
    'values': {'OTHER_PATTERN': 'Journeybob', 'PEER_ID': 'bob-account'},
    'receipt': {
      'status': 'PASS',
      'exit_status': 0,
      'flows': ['production_intro_ready_chat'],
    },
  };
  Map<String, Object?> envelope(
    String role,
    String step,
    Map<String, Object?> snapshot, {
    bool stopped = false,
    int settleDelayMs = 120000,
  }) => {
    'stepId': step,
    'status': 'complete',
    'success': true,
    'observedRunId': _run,
    'observedRole': role,
    'observedNonce': '$role-first',
    'probePreambleDrainsInbox': true,
    'snapshot': snapshot,
    if (stopped) ...{
      'nodeAction': {'action': 'stop_node', 'stopped': true},
      'offlineWindow': {
        'freshOwnedPidStopEvent': {
          'event': 'P2P_SERVICE_STOP_NODE_SUCCESS',
          'ts': '2026-10-23T14:00:00.000Z',
        },
        'onlineBeforeProbe': true,
        'onlineBeforeAction': false,
        'onlineAfterAction': false,
        'actionStartedAt': '2026-10-23T14:00:01.000Z',
        'actionCompletedAt': '2026-10-23T14:00:30.000Z',
        'actionFinishedBeforeSnapshot': true,
        'settleDelayMs': settleDelayMs,
        'flowBeforePath': '$step-before.txt',
        'flowStoppedPath': '$step-stopped.txt',
      },
    },
  };
  final offers = _clone(_snapshot(proof, 'pending', 'alice'));
  offers['introOutboxDeliveries'] = <Map<String, Object?>>[
    for (final role in ['bob', 'charlie'])
      {
        'deliveryId': 'offer-$role',
        'introductionId': 'one-owned-introduction',
        'targetPeerId': '$role-account',
        'status': 'failed',
        'path': 'pending',
      },
  ];
  proof['offlineOffers'] = envelope(
    'alice',
    'offline-offers',
    offers,
    stopped: true,
  );
  final receiver = _clone(_snapshot(proof, 'pending', 'bob'));
  ((receiver['introductions'] as List).single as Map)['recipientStatus'] =
      'accepted';
  proof['offlineResponseReceiver'] = envelope(
    'bob',
    'offline-response-receiver',
    receiver,
    stopped: true,
    settleDelayMs: 240000,
  );
  ((proof['offlineResponseReceiver'] as Map)['offlineWindow']
          as Map)['actionCompletedAt'] =
      '2026-10-23T14:03:00.000Z';
  final responder = _clone(_snapshot(proof, 'mutual', 'charlie'));
  responder['chatMessages'] = <Map<String, Object?>>[];
  responder['introOutboxDeliveries'] = <Map<String, Object?>>[
    for (final role in ['alice', 'bob'])
      {
        'deliveryId': 'acceptance-$role',
        'introductionId': 'one-owned-introduction',
        'targetPeerId': '$role-account',
        'status': 'failed',
        'path': 'pending',
      },
  ];
  proof['offlineResponseCommitted'] = envelope(
    'charlie',
    'offline-response-committed',
    responder,
    stopped: true,
  );
  final precondition = _clone(_snapshot(proof, 'pending', 'charlie'));
  ((precondition['introductions'] as List).single as Map)['recipientStatus'] =
      'accepted';
  proof['responsePrecondition'] = envelope(
    'charlie',
    'response-precondition',
    precondition,
  );
  return proof;
}

void main() {
  test(
    'stopping both nodes before the first actual response arrives cannot prove mutual acceptance',
    () {
      final proof = _proof();
      final precondition =
          (proof['responsePrecondition'] as Map)['snapshot'] as Map;
      ((precondition['introductions'] as List).single
              as Map)['recipientStatus'] =
          'pending';
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'offline offers and acceptance carrier survive actual role cuts and natural replay',
    () {
      expect(validateProductionIntroductionOffline(_proof()), isEmpty);
    },
  );
  test(
    'an offline badge without a fresh owned native-stop fence is insufficient',
    () {
      final proof = _proof();
      ((proof['offlineOffers'] as Map)['offlineWindow']
              as Map)['freshOwnedPidStopEvent'] =
          <String, Object?>{};
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'an action outside the existing settle window cannot prove an offline cut',
    () {
      final proof = _proof();
      ((proof['offlineResponseReceiver'] as Map)['offlineWindow']
              as Map)['actionCompletedAt'] =
          '2026-10-23T14:05:30.000Z';
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'separate offline observations do not prove the participant was offline during second acceptance',
    () {
      final proof = _proof();
      ((proof['offlineResponseReceiver'] as Map)['offlineWindow']
              as Map)['actionCompletedAt'] =
          '2026-10-23T14:00:20.000Z';
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'both offline offer carriers must be durably present before sender crash',
    () {
      final proof = _proof();
      (((proof['offlineOffers'] as Map)['snapshot']
                  as Map)['introOutboxDeliveries']
              as List)
          .removeLast();
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'natural arrival must keep the original offline-committed introduction identity',
    () {
      final proof = _proof();
      ((((proof['offlineOffers'] as Map)['snapshot'] as Map)['introductions']
                      as List)
                  .single
              as Map)['id'] =
          'different-offline-intro';
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'committed consent without its carrier to the offline party is stranded',
    () {
      final proof = _proof();
      ((proof['offlineResponseCommitted'] as Map)['snapshot']
              as Map)['introOutboxDeliveries'] =
          <Map<String, Object?>>[];
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'claimed inbox custody cannot substitute a witnessed failed offline carrier',
    () {
      final proof = _proof();
      ((((proof['offlineResponseCommitted'] as Map)['snapshot']
                          as Map)['introOutboxDeliveries']
                      as List)
                  .first
              as Map)['status'] =
          'delivered';
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'the stopped recipient cannot already have received second acceptance',
    () {
      final proof = _proof();
      ((((proof['offlineResponseReceiver'] as Map)['snapshot']
                          as Map)['introductions']
                      as List)
                  .single
              as Map)['introducedStatus'] =
          'accepted';
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'a missing responder process cut does not establish acceptance crash durability',
    () {
      final proof = _proof();
      (proof['ownedKills'] as Map).remove('charlie-offline');
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'active inbox probing cannot replace natural restarted-recipient UI',
    () {
      final proof = _proof();
      final trace = proof['trace'] as List;
      trace.remove('probe-mutual-bob');
      trace.insert(trace.indexOf('restart-offline-bob'), 'probe-mutual-bob');
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'a stale intermediate account invocation invalidates the stopped-node witness',
    () {
      final proof = _proof();
      (proof['offlineResponseReceiver'] as Map)['observedNonce'] = 'bob-second';
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
  test(
    'the second acceptance needs its actual post-decision UI before observation',
    () {
      final proof = _proof();
      (proof['ui'] as Map).remove('response-ready-charlie');
      expect(validateProductionIntroductionOffline(proof), isNotEmpty);
    },
  );
}
