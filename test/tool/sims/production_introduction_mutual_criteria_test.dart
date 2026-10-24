import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';

import '../../../tool/sims/production_introduction_mutual_criteria.dart';

const _run = 'introduction-mutual-fixture';

Map<String, Object?> _proof() {
  const roles = ['alice', 'bob', 'charlie'];
  final peers = {for (final role in roles) role: '$role-account'};
  final names = {for (final role in roles) role: 'Journey$role'};
  final nonces = {
    for (final role in roles)
      role: ['$role-first', if (role != 'alice') '$role-second'],
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
    receipt('$role-ready', 'production_intro_ready_chat', {
      'PEER_ID': peers[other]!,
      'OTHER_PATTERN': names[other]!,
    });
    receipt('open-chat-$role', 'production_intro_open_chat', {
      'PEER_ID': peers[other]!,
      'OTHER_PATTERN': names[other]!,
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
    },
    'trace': [
      for (final role in roles) 'probe-before-$role',
      'introduce',
      'natural-pending-bob',
      'natural-pending-charlie',
      for (final role in roles) 'probe-pending-$role',
      'accept-bob',
      'accept-charlie',
      'bob-ready',
      'charlie-ready',
      'open-chat-bob',
      'open-chat-charlie',
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
                  nonces[role]![phase == 'restarted' && role != 'alice'
                      ? 1
                      : 0],
              'probePreambleDrainsInbox': true,
              'snapshot': snapshot(role, phase),
            },
        },
    },
  };
}

Map _snapshot(Map proof, String phase, String role) =>
    (proof['phases'] as Map)[phase][role]['snapshot'] as Map;
List _messages(Map proof, String phase, String role) =>
    ((_snapshot(proof, phase, role)['chatMessages'] as List).single
            as Map)['messages']
        as List;

void main() {
  test(
    'selective fixture, real decisions and same-ID private chat survive participant restart',
    () {
      expect(validateProductionIntroductionMutual(_proof()), isEmpty);
    },
  );
  test('a preconnected full mesh cannot stand in for introductions', () {
    final proof = _proof();
    (_snapshot(proof, 'before', 'bob')['contacts'] as List).add(
      <String, Object?>{'peerId': 'charlie-account'},
    );
    expect(validateProductionIntroductionMutual(proof), isNotEmpty);
  });
  test(
    'accepted model rows without both actual UI decisions are incomplete',
    () {
      final proof = _proof();
      (proof['ui'] as Map).remove('accept-charlie');
      expect(validateProductionIntroductionMutual(proof), isNotEmpty);
    },
  );
  test(
    'an inbox-draining probe before natural incoming UI cannot certify automatic delivery',
    () {
      final proof = _proof();
      final trace = proof['trace'] as List;
      trace.remove('probe-pending-bob');
      trace.insert(0, 'probe-pending-bob');
      expect(validateProductionIntroductionMutual(proof), isNotEmpty);
    },
  );
  test('a different introduction or introducer tag is rejected', () {
    final proof = _proof();
    ((_snapshot(proof, 'mutual', 'charlie')['introductions'] as List).single
            as Map)['id'] =
        'different-intro';
    expect(validateProductionIntroductionMutual(proof), isNotEmpty);
    final synthetic = _proof();
    ((_snapshot(synthetic, 'mutual', 'bob')['contacts'] as List).last
            as Map)['introducedByPeerId'] =
        null;
    expect(validateProductionIntroductionMutual(synthetic), isNotEmpty);
  });
  test(
    'participant chat leaked to the introducer is not private direct delivery',
    () {
      final proof = _proof();
      _snapshot(proof, 'mutual', 'alice')['chatMessages'] = _snapshot(
        proof,
        'mutual',
        'bob',
      )['chatMessages'];
      expect(validateProductionIntroductionMutual(proof), isNotEmpty);
    },
  );
  test('duplicate replay or replacement logical chat identity fails', () {
    final proof = _proof();
    final rows = _messages(proof, 'restarted', 'charlie');
    rows.add(Map<String, Object?>.from(rows.single as Map));
    expect(validateProductionIntroductionMutual(proof), isNotEmpty);
    final replacement = _proof();
    (_messages(replacement, 'restarted', 'bob').single as Map)['id'] =
        'replacement';
    expect(validateProductionIntroductionMutual(replacement), isNotEmpty);
  });
  test('a stale restart nonce or changed instant cannot prove persistence', () {
    final proof = _proof();
    ((proof['phases'] as Map)['restarted']['bob'] as Map)['observedNonce'] =
        'bob-first';
    expect(validateProductionIntroductionMutual(proof), isNotEmpty);
    final changed = _proof();
    (_messages(changed, 'restarted', 'charlie').single as Map)['timestamp'] =
        '2026-10-23T14:00:01.000Z';
    expect(validateProductionIntroductionMutual(changed), isNotEmpty);
  });
  test(
    'production review excludes mutual rows and uses the actual empty-state copy',
    () {
      final english =
          jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
      expect(english['intro_empty'], 'No introductions yet');
      expect(english['intro_accept'], 'Accept');
      expect(english['intro_pass'], 'Pass');
      final pending = IntroductionModel(
        id: 'fixture-introduction',
        introducerId: 'alice-account',
        recipientId: 'bob-account',
        introducedId: 'charlie-account',
        createdAt: '2026-10-23T00:00:00Z',
      );
      expect(
        foldIntroductionsForReview(
          introductions: [pending],
          ownPeerId: 'bob-account',
        ),
        hasLength(1),
      );
      expect(
        foldIntroductionsForReview(
          introductions: [
            pending.copyWith(
              recipientStatus: IntroductionStatus.accepted,
              introducedStatus: IntroductionStatus.accepted,
              status: IntroductionOverallStatus.mutualAccepted,
            ),
          ],
          ownPeerId: 'bob-account',
        ),
        isEmpty,
      );
    },
  );
  test(
    'an unreachable review Message CTA or unbound contact cannot satisfy mutual UI',
    () {
      final oldCta = _proof();
      final oldValues =
          ((oldCta['ui'] as Map)['accept-charlie'] as Map)['values'] as Map;
      oldValues['EXPECTED_STATE_PATTERN'] = 'Message';
      expect(validateProductionIntroductionMutual(oldCta), isNotEmpty);
      final foreign = _proof();
      final foreignValues =
          ((foreign['ui'] as Map)['bob-ready'] as Map)['values'] as Map;
      foreignValues['PEER_ID'] = 'another-account';
      expect(validateProductionIntroductionMutual(foreign), isNotEmpty);
    },
  );
}
