import '../../integration_test/scripts/group_multi_party_device_criteria.dart';

/// Converts independently observed UI/repository stages into the preserved
/// original oracle only after exact intermediate identity checks succeed.
List<String> validateProductionGroupCreate(Map<String, Object?> proof) {
  final observed = observeProductionCatalogMessage(
    proof,
    scenario: 'private_abc_create',
  );
  final failures = [...observed.failures];
  if (failures.isEmpty) {
    final original = evaluateGroupMultiPartyVerdicts(
      scenario: 'private_abc_create',
      relayAddresses: observed.relayAddresses,
      verdicts: observed.verdicts,
    );
    if (!original.ok) failures.add(original.detail);
  }
  return failures;
}

/// Exact shared create/accept/message observations for the specified cases.
/// Scenario identity is preserved all the way into the unchanged original oracle.
({
  List<String> failures,
  List<Map<String, dynamic>> verdicts,
  String relayAddresses,
})
observeProductionCatalogMessage(
  Map<String, Object?> proof, {
  required String scenario,
}) {
  final verdicts = <Map<String, dynamic>>[];
  var relayAddresses = '';
  final failures = <String>[];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  try {
    if (!const {
      'private_abc_create',
      'private_reaction_roundtrip',
      'private_reaction_toggle_convergence',
      'private_removed_reaction_rejected',
    }.contains(scenario)) {
      throw StateError('unsupported catalog case');
    }
    final run = proof['runId'] as String;
    require(run.isNotEmpty, 'missing run identity');
    final finals = proof['final'] as Map;
    const roles = ['alice', 'bob', 'charlie'];
    require(
      finals.length == roles.length,
      'exact three role observations required',
    );
    final ui = proof['ui'] as Map;
    final paths = <String>{};
    for (final entry in const {
      'create': 'production_catalog_group_create',
      'accept-bob': 'production_catalog_invite_accept',
      'accept-charlie': 'production_catalog_invite_accept',
      'send': 'production_catalog_group_send',
    }.entries) {
      final receipt = ui[entry.key] as Map;
      require(
        receipt['status'] == 'PASS' &&
            receipt['exit_status'] == 0 &&
            receipt['flows'] is List &&
            (receipt['flows'] as List).length == 1 &&
            (receipt['flows'] as List).single == entry.value,
        '${entry.key}: exact UI receipt required',
      );
      final path = receipt['path'] as String;
      require(
        path.isNotEmpty && paths.add(path),
        '${entry.key}: independent receipt required',
      );
    }
    Map snapshot(Object? raw, String role) {
      final s = raw as Map;
      require(
        s['runId'] == run && s['role'] == role && s['scenario'] == scenario,
        '$role: observation identity mismatch',
      );
      return s;
    }

    final created = snapshot(proof['created'], 'alice');
    final initialGroup = created['group'] as Map;
    final groupId = initialGroup['id'] as String;
    final alice = finals['alice'] as Map;
    final alicePeer = alice['peerId'] as String;
    require(
      initialGroup['createdBy'] == alicePeer &&
          initialGroup['name'] == 'Catalog $scenario $run' &&
          initialGroup['type'] == 'chat',
      'wrong production-created group',
    );
    require(
      (initialGroup['members'] as List).length == 3,
      'creation must add exactly two members',
    );
    final attempts = initialGroup['deliveryAttempts'] as List;
    require(
      attempts.length == 2,
      'creation must produce exactly two invitations',
    );
    final accepted = proof['accepted'] as Map;
    final pending = proof['pending'] as Map;
    final beforeSend = proof['beforeSend'] as Map;
    final (messageKey, textPrefix) = switch (scenario) {
      'private_abc_create' => ('aliceInitial', 'ML-001 private ABC hello'),
      'private_reaction_roundtrip' => (
        'aliceReactionTarget',
        'PL-009 Alice reaction target',
      ),
      'private_reaction_toggle_convergence' => (
        'aliceToggleTarget',
        'RT-001 Alice reaction toggle target',
      ),
      'private_removed_reaction_rejected' => (
        'aliceReactionTargetBeforeRemoval',
        'PL-010 Alice pre-removal reaction target',
      ),
      _ => throw StateError('unsupported catalog case'),
    };
    final expectedText = '$textPrefix $run';
    for (final role in roles) {
      final s = snapshot(finals[role], role);
      final group = s['group'] as Map;
      require(
        group['id'] == groupId && group['name'] == initialGroup['name'],
        '$role: changed group',
      );
      require(
        group['keyEpoch'] == 1 &&
            group['groupConfigStateHash'] is String &&
            (group['groupConfigStateHash'] as String).isNotEmpty &&
            group['groupConfigStateHash'] ==
                (alice['group'] as Map)['groupConfigStateHash'],
        '$role: initial epoch or converged group configuration changed',
      );
      final members = (group['members'] as List)
          .map((m) => (m as Map)['peerId'])
          .toList();
      final messages = group['messages'] as List;
      final ready = snapshot(beforeSend[role], role);
      final readyGroup = ready['group'] as Map;
      require(
        readyGroup['id'] == groupId &&
            !(readyGroup['messages'] as List).any(
              (m) => (m as Map)['text'] == expectedText,
            ),
        '$role: message existed before UI send',
      );
      final rows = messages
          .where((m) => (m as Map)['text'] == expectedText)
          .cast<Map>()
          .toList();
      require(rows.length == 1, '$role: exact persisted message count');
      final message = rows.single;
      final joinNames = role == 'alice' ? ['bob', 'charlie'] : [role];
      final joins = joinNames.every(
        (r) => messages.any(
          (m) =>
              (m as Map)['text'] ==
              '${(finals[r] as Map)['username']} joined the group',
        ),
      );
      require(joins, '$role: readable join timeline missing');
      final ml = <String, Object?>{
        'rowId': 'ML-001',
        'invitePath': 'supported_pending_invite',
      };
      if (role == 'alice') {
        require(
          message['isIncoming'] == false &&
              ['sent', 'delivered'].contains(message['status']),
          'outgoing send did not complete',
        );
        ml.addAll({
          'createdViaCreateGroupWithMembers': true,
          'bobInviteSent': true,
          'charlieInviteSent': true,
          'bobAcceptedSignal': true,
          'charlieAcceptedSignal': true,
          'readableJoinTimelineObserved': joins,
        });
      } else {
        final before = pending[role] as Map;
        final after = accepted[role] as Map;
        require(
          before['runId'] == run &&
              before['role'] == role &&
              after['runId'] == run &&
              after['role'] == role,
          '$role: invite observation identity mismatch',
        );
        final invitations = before['pending'] as List;
        require(
          invitations.length == 1,
          '$role: exact pending invitation missing',
        );
        final invite = invitations.single as Map;
        require(
          invite['groupId'] == groupId &&
              invite['senderPeerId'] == alicePeer &&
              invite['name'] == initialGroup['name'],
          '$role: pending invitation mismatch',
        );
        final attempt =
            attempts.where((a) => (a as Map)['peer_id'] == s['peerId']).single
                as Map;
        require(
          attempt['status'] == 'sent' &&
              attempt['invite_id'] == invite['inviteId'],
          '$role: exact delivered invitation missing',
        );
        require(
          (after['pending'] as List).isEmpty &&
              after['consumed'] is Map &&
              (after['consumed'] as Map)['invite_id'] == invite['inviteId'],
          '$role: original pending invitation was not consumed',
        );
        ml.addAll({
          'storedPendingInvite': true,
          'acceptedPendingInvite': true,
          'joinedViaGroupJoin': true,
          'readableSelfJoinTimeline': joins,
          'receivedAliceInitialAfterInviteAccept': true,
        });
      }
      final observedMessage = <String, Object?>{
        ...Map<String, Object?>.from(message),
        'key': messageKey,
        if (role == 'alice') 'outcome': 'success',
      };
      verdicts.add({
        'scenario': scenario,
        'role': role,
        'runId': run,
        'peerId': s['peerId'],
        'deviceId': s['transportPeerId'],
        'groupId': groupId,
        'topicName': group['topicName'],
        'keyEpoch': group['keyEpoch'],
        'groupConfigStateHash': group['groupConfigStateHash'],
        'memberPeerIds': members,
        'activeMemberPeerIds': members,
        'relayLifecycleProof': s['relayReady'] == true,
        'sentMessages': role == 'alice' ? [observedMessage] : [],
        'receivedMessages': role == 'alice' ? [] : [observedMessage],
        'persistedMessageCounts': role == 'alice'
            ? {}
            : {messageKey: rows.length},
        'ml001CreateInviteProof': ml,
      });
      require(
        s['relayAddresses'] == created['relayAddresses'],
        '$role: relay configuration changed',
      );
    }
    relayAddresses = created['relayAddresses'] as String;
  } catch (error) {
    failures.add(
      'malformed or incomplete create/invite proof: ${error.runtimeType}',
    );
  }
  return (
    failures: failures,
    verdicts: verdicts,
    relayAddresses: relayAddresses,
  );
}
