import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/production_group_ordered_recovery_criteria.dart';

const _run = 'group-order-fixture';
const _roles = ['alice', 'bob', 'charlie'];

Map<String, Object?> _proof() {
  final texts = groupOrderedRecoveryTexts(_run);
  final peers = {for (final role in _roles) role: '$role-account'};
  Map<String, Object?> row(String role, String key) {
    final author = texts[key]!.role;
    final index = texts.keys.toList().indexOf(key);
    return {
      'messageId': 'logical-$index',
      'text': texts[key]!.text,
      'groupId': 'fixture-group',
      'senderPeerId': peers[author],
      'isIncoming': role != author,
      'status': 'sent',
      'timestamp': DateTime.utc(
        2026,
        10,
        23,
      ).add(Duration(milliseconds: index * 20)).toIso8601String(),
      'keyEpoch': 1,
    };
  }

  Map<String, Object?> snapshot(String role, Iterable<String> keys) => {
    'runId': _run,
    'role': role,
    'scenario': 'de002',
    'peerId': peers[role],
    'groupId': 'fixture-group',
    'lifecycle': 'resumed',
    'memberPeerIds': peers.values.toList(),
    'watched': {
      for (final key in keys) key: [row(role, key)],
    },
  };
  final accepted = snapshot('alice', ['accepted']);
  accepted['deliveries'] = [
    {
      'messageId': 'logical-102',
      'recipientPeerIds': [peers['bob'], peers['charlie']],
      'ok': true,
      'inboxStored': true,
    },
  ];
  return {
    'runId': _run,
    'runtimeScenario': groupOrderedRecoveryRuntime,
    'emulatorTriple': true,
    'peers': peers,
    'beforeCrash': {
      for (final role in _roles)
        role: snapshot(role, texts.keys.where((key) => key != 'accepted')),
    },
    'acceptedSource': accepted,
    'afterRestart': {
      for (final role in _roles) role: snapshot(role, texts.keys),
    },
    'ownedKills': {
      for (final role in _roles) role: {'verifiedUidKill': true},
    },
    'initialNonces': {for (final role in _roles) role: '$role-first'},
    'finalNonces': {for (final role in _roles) role: '$role-second'},
    'offlineRecipients': {'bob': true, 'charlie': true},
    'flows': [
      'create',
      'accept-bob',
      'accept-charlie',
      for (var i = 0; i < 100; i++) 'ordered-seq-$i',
      'ordered-bob',
      'ordered-charlie',
      'ordered-accepted',
    ],
  };
}

Map _snapshot(Map proof, String phase, String role) =>
    (proof[phase] as Map)[role] as Map;

List _rows(Map proof, String phase, String role, String key) =>
    (_snapshot(proof, phase, role)['watched'] as Map)[key] as List;

void main() {
  test(
    'complete three-author burst and accepted-text recovery satisfy the oracle',
    () {
      expect(validateProductionGroupOrderedRecovery(_proof()), isEmpty);
    },
  );

  test('one missing burst message is rejected before any process cut', () {
    final proof = _proof();
    _rows(proof, 'beforeCrash', 'bob', 'seq99').clear();
    expect(validateProductionGroupOrderedRecovery(proof), isNotEmpty);
  });

  test('replayed duplicate cannot be hidden by having every expected text', () {
    final proof = _proof();
    final rows = _rows(proof, 'afterRestart', 'charlie', 'accepted');
    rows.add(Map<String, Object?>.from(rows.single as Map));
    expect(validateProductionGroupOrderedRecovery(proof), isNotEmpty);
  });

  test('same text under a replacement logical identity is rejected', () {
    final proof = _proof();
    (_rows(proof, 'afterRestart', 'bob', 'accepted').single
            as Map)['messageId'] =
        'replacement';
    expect(validateProductionGroupOrderedRecovery(proof), isNotEmpty);
  });

  test(
    'a received row cannot change author, direction or epoch after restart',
    () {
      for (final change in <String, Object?>{
        'senderPeerId': 'charlie-account',
        'isIncoming': false,
        'keyEpoch': 2,
      }.entries) {
        final proof = _proof();
        (_rows(proof, 'afterRestart', 'bob', 'seq0').single
                as Map)[change.key] =
            change.value;
        expect(
          validateProductionGroupOrderedRecovery(proof),
          isNotEmpty,
          reason: change.key,
        );
      }
    },
  );

  test('canonical timestamps must preserve the sender order', () {
    final proof = _proof();
    final first = _rows(proof, 'beforeCrash', 'alice', 'seq0').single as Map;
    final next = _rows(proof, 'beforeCrash', 'alice', 'seq1').single as Map;
    next['timestamp'] = first['timestamp'];
    expect(validateProductionGroupOrderedRecovery(proof), isNotEmpty);
  });

  test(
    'a successful publish without custody for both offline recipients fails',
    () {
      for (final change in <String, Object?>{
        'inboxStored': false,
        'recipientPeerIds': ['bob-account'],
      }.entries) {
        final proof = _proof();
        final accepted = proof['acceptedSource'] as Map;
        ((accepted['deliveries'] as List).single as Map)[change.key] =
            change.value;
        expect(
          validateProductionGroupOrderedRecovery(proof),
          isNotEmpty,
          reason: change.key,
        );
      }
    },
  );

  test(
    'a recipient that restarted before the sender cut invalidates the case',
    () {
      final proof = _proof();
      (proof['offlineRecipients'] as Map)['bob'] = false;
      expect(validateProductionGroupOrderedRecovery(proof), isNotEmpty);
    },
  );

  test(
    'old invocation, stale run and changed membership cannot certify recovery',
    () {
      final oldNonce = _proof();
      (oldNonce['finalNonces'] as Map)['charlie'] = 'charlie-first';
      expect(validateProductionGroupOrderedRecovery(oldNonce), isNotEmpty);
      final stale = _proof();
      _snapshot(stale, 'afterRestart', 'bob')['runId'] = 'another-run';
      expect(validateProductionGroupOrderedRecovery(stale), isNotEmpty);
      final membership = _proof();
      _snapshot(membership, 'afterRestart', 'bob')['memberPeerIds'] = [
        'alice-account',
        'bob-account',
      ];
      expect(validateProductionGroupOrderedRecovery(membership), isNotEmpty);
    },
  );

  test(
    'missing UI submissions and text accepted only in local pending state fail',
    () {
      final missingFlow = _proof();
      (missingFlow['flows'] as List).removeLast();
      expect(validateProductionGroupOrderedRecovery(missingFlow), isNotEmpty);
      final pending = _proof();
      final source = pending['acceptedSource'] as Map;
      (((source['watched'] as Map)['accepted'] as List).single
              as Map)['status'] =
          'sending';
      expect(validateProductionGroupOrderedRecovery(pending), isNotEmpty);
    },
  );
}
