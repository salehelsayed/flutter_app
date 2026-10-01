import '../../integration_test/scripts/group_multi_party_device_criteria.dart';

/// Texts of catalog `private_process_death_matrix` (ST-007), identical to the
/// original harness.
Map<String, String> productionProcessDeathTexts(String run) => {
  'aliceAfterAddCrash': 'ST-007 Alice after Charlie add crash $run',
  'aliceAfterRemoveCrash': 'ST-007 Alice after Bob remove crash $run',
  'aliceAfterReaddCrash': 'ST-007 Alice after Charlie readd crash $run',
  'charlieAfterReaddCrash': 'ST-007 Charlie after readd crash $run',
};

const productionProcessDeathFlows = [
  'create',
  'accept-bob',
  'add-charlie',
  'accept-charlie-add',
  'alice-after-add',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-after-remove',
  'readd-charlie',
  'accept-charlie-readd',
  'alice-after-readd',
  'charlie-after-readd',
];

/// Receipt-time stages: (stage name, receiving role, proof key).
const productionProcessDeathReceipts = [
  ('bobGotAdd', 'bob', 'aliceAfterAddCrash'),
  ('charlieGotAdd', 'charlie', 'aliceAfterAddCrash'),
  ('bobGotRemove', 'bob', 'aliceAfterRemoveCrash'),
  ('bobGotReadd', 'bob', 'aliceAfterReaddCrash'),
  ('charlieGotReadd', 'charlie', 'aliceAfterReaddCrash'),
  ('aliceGotCharlie', 'alice', 'charlieAfterReaddCrash'),
  ('bobGotCharlie', 'bob', 'charlieAfterReaddCrash'),
];

List<String> validateProductionGroupProcessDeath(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  try {
    final run = proof['runId'] as String;
    final finals = proof['final'] as Map;
    final peers = {
      for (final role in const ['alice', 'bob', 'charlie'])
        role: (finals[role] as Map)['peerId'] as String,
    };
    require(peers.values.toSet().length == 3, 'three distinct peers');
    require(
      (proof['flows'] as List).join(',') ==
          productionProcessDeathFlows.join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = (name == 'final' ? finals[role] : proof[name]) as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == 'private_process_death_matrix' &&
            s['lifecycle'] == 'resumed',
        '$name: observation identity',
      );
      return s;
    }

    List rows(Map s, String key) =>
        ((s['watched'] as Map?)?[key] as List?) ?? const [];
    Set members(Map s) => ((s['memberPeerIds'] as List?) ?? const []).toSet();

    // The three verified owned-process kills and their recoveries.
    final kills = proof['kills'] as Map;
    for (final kill in const ['charlie:add', 'bob:remove', 'charlie:readd']) {
      require(kills[kill] == true, '$kill: verified owned-process kill');
    }
    final addPersisted = stage('addPersisted', 'charlie');
    final addRecovered = stage('addRecovered', 'charlie');
    final removePersisted = stage('removePersisted', 'bob');
    final removeRecovered = stage('removeRecovered', 'bob');
    final readdPersisted = stage('readdPersisted', 'charlie');
    final readdRecovered = stage('readdRecovered', 'charlie');
    final all = peers.values.toSet();
    final addOk =
        addPersisted['selfMember'] == true &&
        addRecovered['selfMember'] == true &&
        members(addRecovered).containsAll(all);
    final removeOk =
        !members(removePersisted).contains(peers['charlie']) &&
        !members(removeRecovered).contains(peers['charlie']) &&
        members(removeRecovered).containsAll({peers['alice'], peers['bob']});
    final readdOk =
        readdPersisted['selfMember'] == true &&
        readdRecovered['selfMember'] == true &&
        members(readdRecovered).containsAll(all);
    require(addOk, 'Charlie recovers the add after process death');
    require(removeOk, 'Bob recovers the removal after process death');
    require(readdOk, 'Charlie recovers the re-add after process death');
    final removedWindow = rows(
      stage('charlieRemovedWindow', 'charlie'),
      'aliceAfterRemoveCrash',
    ).length;

    Map<String, Object?> received(Map row, String key, int count) => {
      'key': key,
      'messageId': row['messageId'],
      'groupId': row['groupId'],
      'text': row['text'],
      'senderPeerId': row['senderPeerId'],
      if (row['senderUsername'] != null) 'senderUsername': row['senderUsername'],
      'timestamp': row['timestamp'],
      'keyEpoch': row['keyEpoch'],
      'isIncoming': row['isIncoming'],
      'persistedCount': count,
    };
    Map<String, Object?> sent(Map row, String key) {
      final ok = ['sent', 'delivered'].contains(row['status']);
      return {
        'key': key,
        'messageId': row['messageId'],
        'groupId': row['groupId'],
        'text': row['text'],
        'outcome': ok ? 'success' : 'status:${row['status']}',
        'senderPeerId': row['senderPeerId'],
        'keyEpoch': row['keyEpoch'],
        'timestamp': row['timestamp'],
        'accepted': ok,
      };
    }

    final receivedByRole = {
      for (final role in const ['alice', 'bob', 'charlie'])
        role: <Map<String, Object?>>[],
    };
    for (final (name, role, key) in productionProcessDeathReceipts) {
      final matches = rows(stage(name, role), key);
      require(
        matches.length == 1 && (matches.first as Map)['isIncoming'] == true,
        '$name: exactly one incoming $key row',
      );
      if (matches.isNotEmpty) {
        receivedByRole[role]!.add(
          received(matches.first as Map, key, matches.length),
        );
      }
    }
    Map sentRow(String role, String key) {
      final matches = rows(finals[role] as Map, key);
      require(
        matches.length == 1 && (matches.first as Map)['isIncoming'] == false,
        '$role: own outgoing $key row',
      );
      return matches.isEmpty ? const {} : matches.first as Map;
    }

    final sentByRole = {
      'alice': [
        for (final key in const [
          'aliceAfterAddCrash',
          'aliceAfterRemoveCrash',
          'aliceAfterReaddCrash',
        ])
          sent(sentRow('alice', key), key),
      ],
      'bob': <Map<String, Object?>>[],
      'charlie': [
        sent(sentRow('charlie', 'charlieAfterReaddCrash'), 'charlieAfterReaddCrash'),
      ],
    };

    final verdicts = <Map<String, dynamic>>[];
    for (final role in const ['alice', 'bob', 'charlie']) {
      final s = stage('final', role);
      final finalMembers = members(s);
      final finalEpoch = s['keyEpoch'] as int;
      verdicts.add({
        'scenario': 'private_process_death_matrix',
        'role': role,
        'runId': run,
        'deviceId': s['transportPeerId'],
        'peerId': s['peerId'],
        'transportPeerId': s['transportPeerId'],
        'groupId': s['groupId'],
        'topicName': s['topicName'],
        'keyEpoch': finalEpoch,
        'relayLifecycleProof': true,
        'memberPeerIds': s['memberPeerIds'],
        'activeMemberPeerIds': s['memberPeerIds'],
        'groupConfigStateHash': s['groupConfigStateHash'],
        'sentMessages': sentByRole[role],
        'receivedMessages': receivedByRole[role],
        'persistedMessageCounts': {
          for (final r in receivedByRole[role]!) '${r['key']}': r['persistedCount'],
        },
        'st007ProcessDeathMatrixProof': {
          'rowId': 'ST-007',
          // The original's checkpoint and killed-role catalog, verbatim.
          'checkpoints': const [
            'local_db_write',
            'bridge_update',
            'key_generation',
            'invite_send',
            'inbox_store',
            'ack',
          ],
          'killedRoles': const ['charlie:add', 'bob:remove', 'charlie:readd'],
          'role': role,
          'addRecovered': addOk,
          'removeRecovered': removeOk,
          'readdRecovered': readdOk,
          'noGhostMembership':
              finalMembers.length == 3 && finalMembers.containsAll(all),
          'activeMemberDeliveryAfterRestart':
              finalMembers.contains(peers['bob']) &&
              finalMembers.contains(peers['charlie']),
          'removedWindowPlaintextCount': removedWindow,
          'finalEpoch': finalEpoch,
        },
      });
    }
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_process_death_matrix',
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: verdicts,
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add('malformed process-death proof: ${error.runtimeType} $error');
  }
  return failures;
}
