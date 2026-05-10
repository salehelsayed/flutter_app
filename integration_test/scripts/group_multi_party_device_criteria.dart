const expectedMultiPartyRelayAddresses =
    '/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,'
    '/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';

class GroupMultiPartyCriterion {
  const GroupMultiPartyCriterion(this.ok, this.detail);

  final bool ok;
  final String detail;
}

class GroupMultiPartyScenarioRequirement {
  const GroupMultiPartyScenarioRequirement({
    required this.scenario,
    required this.roles,
  });

  final String scenario;
  final List<String> roles;

  int get requiredDeviceCount => roles.length;
}

const _gm001Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm001',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm002Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm002',
  roles: <String>['alice', 'bob', 'charlie', 'dana'],
);
const _gm003Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm003',
  roles: <String>['alice', 'bob', 'charlie', 'dana'],
);
const _gm004Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm004',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm005Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm005',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm006Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm006',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm007Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm007',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _allRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'all',
  roles: <String>['alice', 'bob', 'charlie', 'dana'],
);

GroupMultiPartyScenarioRequirement scenarioRequirement(String scenario) {
  final requirement = _tryScenarioRequirement(scenario);
  if (requirement == null) {
    throw ArgumentError.value(
      scenario,
      'scenario',
      'Expected gm001, gm002, gm003, gm004, gm005, gm006, gm007, or all',
    );
  }
  return requirement;
}

GroupMultiPartyCriterion evaluateDeviceSelection({
  required String scenario,
  required List<String> deviceIds,
}) {
  final requirement = _tryScenarioRequirement(scenario);
  if (requirement == null) {
    return GroupMultiPartyCriterion(
      false,
      'Unsupported scenario "$scenario"; expected gm001, gm002, gm003, gm004, gm005, gm006, gm007, or all',
    );
  }

  final cleanDevices = deviceIds
      .map((deviceId) => deviceId.trim())
      .where((deviceId) => deviceId.isNotEmpty)
      .toList(growable: false);
  if (cleanDevices.length < requirement.requiredDeviceCount) {
    return GroupMultiPartyCriterion(
      false,
      '${requirement.scenario} requires ${requirement.requiredDeviceCount} '
      'device IDs for roles ${requirement.roles.join(', ')}; '
      'got ${cleanDevices.length}',
    );
  }

  final selectedDevices = cleanDevices.take(requirement.requiredDeviceCount);
  final uniqueDevices = selectedDevices.toSet();
  if (uniqueDevices.length != requirement.requiredDeviceCount) {
    return GroupMultiPartyCriterion(
      false,
      '${requirement.scenario} requires distinct Flutter app targets for '
      'roles ${requirement.roles.join(', ')}',
    );
  }

  return GroupMultiPartyCriterion(
    true,
    '${requirement.scenario} role devices: '
    '${roleDeviceMapForScenario(scenario: requirement.scenario, deviceIds: cleanDevices).entries.map((entry) => '${entry.key}=${entry.value}').join(', ')}',
  );
}

Map<String, String> roleDeviceMapForScenario({
  required String scenario,
  required List<String> deviceIds,
}) {
  final requirement = scenarioRequirement(scenario);
  final cleanDevices = deviceIds
      .map((deviceId) => deviceId.trim())
      .where((deviceId) => deviceId.isNotEmpty)
      .toList(growable: false);
  if (cleanDevices.length < requirement.requiredDeviceCount) {
    throw ArgumentError(
      '${requirement.scenario} requires ${requirement.requiredDeviceCount} '
      'device IDs',
    );
  }
  return <String, String>{
    for (var i = 0; i < requirement.requiredDeviceCount; i++)
      requirement.roles[i]: cleanDevices[i],
  };
}

GroupMultiPartyCriterion evaluateRelayConfiguration(String? relayAddresses) {
  final normalized = relayAddresses?.trim() ?? '';
  if (normalized.isEmpty) {
    return const GroupMultiPartyCriterion(
      false,
      'MKNOON_RELAY_ADDRESSES is required for multi-party device proof',
    );
  }
  if (normalized != expectedMultiPartyRelayAddresses) {
    return const GroupMultiPartyCriterion(
      false,
      'MKNOON_RELAY_ADDRESSES does not match the required app relay profile',
    );
  }
  return const GroupMultiPartyCriterion(
    true,
    'MKNOON_RELAY_ADDRESSES matches the required app relay profile',
  );
}

GroupMultiPartyCriterion evaluateGroupMultiPartyVerdicts({
  required String scenario,
  required String? relayAddresses,
  required List<Map<String, dynamic>> verdicts,
}) {
  final normalizedScenario = _normalizeScenario(scenario);
  final requirement = _tryScenarioRequirement(normalizedScenario);
  if (requirement == null || normalizedScenario == 'all') {
    return GroupMultiPartyCriterion(
      false,
      'Verdicts must be evaluated for gm001, gm002, gm003, gm004, gm005, gm006, or gm007, got "$scenario"',
    );
  }

  final failures = <String>[];
  final relay = evaluateRelayConfiguration(relayAddresses);
  if (!relay.ok) {
    failures.add(relay.detail);
  }

  final byRole = <String, Map<String, dynamic>>{};
  for (final verdict in verdicts) {
    final role = _stringValue(verdict['role']);
    if (role == null || role.isEmpty) {
      failures.add('verdict missing role');
      continue;
    }
    if (!requirement.roles.contains(role)) {
      failures.add('$role: unexpected role for ${requirement.scenario}');
      continue;
    }
    if (byRole.containsKey(role)) {
      failures.add('$role: duplicate role verdict');
      continue;
    }
    byRole[role] = verdict;
  }

  for (final role in requirement.roles) {
    if (!byRole.containsKey(role)) {
      failures.add('$role: missing role verdict');
    }
  }

  final peerIdByRole = <String, String>{};
  final groupIds = <String>{};
  for (final role in requirement.roles) {
    final verdict = byRole[role];
    if (verdict == null) continue;

    if (_stringValue(verdict['scenario']) != requirement.scenario) {
      failures.add(
        '$role: scenario mismatch ${verdict['scenario']} '
        '!= ${requirement.scenario}',
      );
    }
    if (verdict['relayLifecycleProof'] != true) {
      failures.add('$role: relayLifecycleProof must be true');
    }

    final peerId = _stringValue(verdict['peerId']);
    if (peerId == null || peerId.isEmpty) {
      failures.add('$role: peerId is required');
    } else if (peerIdByRole.containsValue(peerId)) {
      failures.add('$role: peerId duplicates another role');
    } else {
      peerIdByRole[role] = peerId;
    }

    final groupId = _stringValue(verdict['groupId']);
    if (groupId == null || groupId.isEmpty) {
      failures.add('$role: groupId is required');
    } else {
      groupIds.add(groupId);
    }

    final keyEpoch = _intValue(verdict['keyEpoch']);
    if ((requirement.scenario == 'gm004' || requirement.scenario == 'gm005') &&
        role == 'charlie') {
      if (keyEpoch == null || keyEpoch < 0) {
        failures.add('$role: keyEpoch must be zero or a positive integer');
      }
    } else if (keyEpoch == null || keyEpoch < 1) {
      failures.add('$role: keyEpoch must be a positive integer');
    }
  }

  if (groupIds.length > 1) {
    failures.add('role verdicts disagree on groupId: ${groupIds.join(', ')}');
  }

  _validateScenarioProofFields(
    scenario: requirement.scenario,
    byRole: byRole,
    peerIdByRole: peerIdByRole,
    failures: failures,
  );

  final expectedPeerIds = requirement.roles
      .map((role) => peerIdByRole[role])
      .whereType<String>()
      .toSet();
  if (expectedPeerIds.length == requirement.roles.length) {
    if (requirement.scenario == 'gm004' || requirement.scenario == 'gm005') {
      final remainingPeerIds = <String>{
        peerIdByRole['alice']!,
        peerIdByRole['bob']!,
      };
      final removedPeerId = peerIdByRole['charlie']!;
      for (final role in const <String>['alice', 'bob']) {
        final verdict = byRole[role];
        if (verdict == null) continue;
        final members = _stringList(verdict['memberPeerIds']).toSet();
        final missingMembers = remainingPeerIds.difference(members);
        if (missingMembers.isNotEmpty) {
          failures.add(
            '$role: incomplete post-removal membership, missing '
            '${missingMembers.join(', ')}',
          );
        }
        if (members.contains(removedPeerId)) {
          failures.add('$role: post-removal membership still includes charlie');
        }
      }
    } else {
      for (final role in requirement.roles) {
        final verdict = byRole[role];
        if (verdict == null) continue;
        final members = _stringList(verdict['memberPeerIds']).toSet();
        final missingMembers = expectedPeerIds.difference(members);
        if (missingMembers.isNotEmpty) {
          failures.add(
            '$role: incomplete membership convergence, missing '
            '${missingMembers.join(', ')}',
          );
        }
      }
    }
  }

  final expectedMessages = _expectedMessagesForScenario(requirement.scenario);
  final expectedReceivedByRole = <String, Set<String>>{
    for (final role in requirement.roles) role: <String>{},
  };
  for (final message in expectedMessages) {
    for (final receiverRole in message.receiverRoles) {
      expectedReceivedByRole[receiverRole]!.add(message.key);
    }
    final sentMessage = _validateSentMessage(
      message: message,
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    for (final receiverRole in message.receiverRoles) {
      _validateReceivedMessage(
        message: message,
        receiverRole: receiverRole,
        sentMessage: sentMessage,
        byRole: byRole,
        peerIdByRole: peerIdByRole,
        failures: failures,
      );
    }
  }

  for (final role in requirement.roles) {
    final verdict = byRole[role];
    if (verdict == null) continue;
    final receivedKeys = _mapList(
      verdict['receivedMessages'],
    ).map((entry) => _stringValue(entry['key'])).whereType<String>().toSet();
    final expectedKeys = expectedReceivedByRole[role] ?? const <String>{};
    final unexpected = receivedKeys.difference(expectedKeys);
    final missing = expectedKeys.difference(receivedKeys);
    if (unexpected.isNotEmpty) {
      failures.add(
        '$role: unexpected received proof keys ${unexpected.join(', ')}',
      );
    }
    if (missing.isNotEmpty) {
      failures.add('$role: missing received proof keys ${missing.join(', ')}');
    }
  }

  if (failures.isNotEmpty) {
    return GroupMultiPartyCriterion(false, failures.join('; '));
  }

  return GroupMultiPartyCriterion(
    true,
    '${requirement.scenario} verdicts valid for '
    '${requirement.roles.join(', ')}',
  );
}

_SentProofMessage? _validateSentMessage({
  required _ExpectedProofMessage message,
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final senderVerdict = byRole[message.senderRole];
  if (senderVerdict == null) return null;
  final sentEntries = _mapList(senderVerdict['sentMessages'])
      .where((entry) => _stringValue(entry['key']) == message.key)
      .toList(growable: false);
  if (sentEntries.length != 1) {
    failures.add(
      '${message.senderRole}: sent ${message.key} count=${sentEntries.length}; '
      'requires exactly one',
    );
    return null;
  }

  final sent = sentEntries.single;
  final outcome = _stringValue(sent['outcome']);
  if (outcome != 'success' && outcome != 'successNoPeers') {
    failures.add('${message.senderRole}: sent ${message.key} outcome=$outcome');
  }
  final messageId = _stringValue(sent['messageId']);
  if (messageId == null || messageId.isEmpty) {
    failures.add(
      '${message.senderRole}: sent ${message.key} missing messageId',
    );
  }
  final text = _messageText(sent);
  if (text == null || text.isEmpty) {
    failures.add('${message.senderRole}: sent ${message.key} missing text');
  }
  final sentPeerId = _stringValue(sent['senderPeerId']);
  final expectedPeerId = peerIdByRole[message.senderRole];
  if (sentPeerId == null || sentPeerId.isEmpty) {
    failures.add(
      '${message.senderRole}: sent ${message.key} missing senderPeerId',
    );
  } else if (expectedPeerId != null && sentPeerId != expectedPeerId) {
    failures.add(
      '${message.senderRole}: sent ${message.key} senderPeerId mismatch',
    );
  }

  final keyEpoch =
      _intValue(sent['keyEpoch']) ?? _intValue(senderVerdict['keyEpoch']);
  if (messageId == null ||
      messageId.isEmpty ||
      text == null ||
      text.isEmpty ||
      sentPeerId == null ||
      sentPeerId.isEmpty ||
      keyEpoch == null ||
      keyEpoch < 1) {
    return null;
  }

  return _SentProofMessage(
    messageId: messageId,
    text: text,
    senderPeerId: sentPeerId,
    keyEpoch: keyEpoch,
  );
}

void _validateReceivedMessage({
  required _ExpectedProofMessage message,
  required String receiverRole,
  required _SentProofMessage? sentMessage,
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final receiverVerdict = byRole[receiverRole];
  if (receiverVerdict == null) return;
  final receivedEntries = _mapList(receiverVerdict['receivedMessages'])
      .where((entry) => _stringValue(entry['key']) == message.key)
      .toList(growable: false);
  if (receivedEntries.length != 1) {
    failures.add(
      '$receiverRole: received ${message.key} count=${receivedEntries.length}; '
      'requires exactly one receiver persistence',
    );
    return;
  }

  final received = receivedEntries.single;
  if (received['isIncoming'] != true) {
    failures.add('$receiverRole: received ${message.key} is not incoming');
  }
  if (sentMessage != null) {
    if (_stringValue(received['messageId']) != sentMessage.messageId) {
      failures.add('$receiverRole: received ${message.key} messageId mismatch');
    }
    if (_messageText(received) != sentMessage.text) {
      failures.add('$receiverRole: received ${message.key} text mismatch');
    }
    if (_stringValue(received['senderPeerId']) != sentMessage.senderPeerId) {
      failures.add(
        '$receiverRole: received ${message.key} senderPeerId mismatch',
      );
    }
    final receiverKeyEpoch =
        _intValue(received['keyEpoch']) ??
        _intValue(receiverVerdict['keyEpoch']);
    if (receiverKeyEpoch != null && receiverKeyEpoch != sentMessage.keyEpoch) {
      failures.add('$receiverRole: received ${message.key} keyEpoch mismatch');
    }
  } else {
    final expectedSenderPeerId = peerIdByRole[message.senderRole];
    if (expectedSenderPeerId != null &&
        _stringValue(received['senderPeerId']) != expectedSenderPeerId) {
      failures.add('$receiverRole: received ${message.key} sender mismatch');
    }
  }

  final counts = _intMap(receiverVerdict['persistedMessageCounts']);
  final persistedCount = counts[message.key];
  if (persistedCount != 1) {
    failures.add(
      '$receiverRole: persisted ${message.key} count='
      '${persistedCount ?? 'missing'}; requires exactly one',
    );
  }
}

GroupMultiPartyScenarioRequirement? _tryScenarioRequirement(String scenario) {
  switch (_normalizeScenario(scenario)) {
    case 'gm001':
      return _gm001Requirement;
    case 'gm002':
      return _gm002Requirement;
    case 'gm003':
      return _gm003Requirement;
    case 'gm004':
      return _gm004Requirement;
    case 'gm005':
      return _gm005Requirement;
    case 'gm006':
      return _gm006Requirement;
    case 'gm007':
      return _gm007Requirement;
    case 'all':
      return _allRequirement;
    default:
      return null;
  }
}

String _normalizeScenario(String scenario) => scenario.trim().toLowerCase();

List<_ExpectedProofMessage> _expectedMessagesForScenario(String scenario) {
  switch (scenario) {
    case 'gm001':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceInitial',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'gm002':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterDanaAdd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie', 'dana'],
        ),
        _ExpectedProofMessage(
          key: 'danaAfterJoin',
          senderRole: 'dana',
          receiverRoles: <String>['alice', 'bob', 'charlie'],
        ),
      ];
    case 'gm003':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceBeforeDanaAdd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceAfterDanaOfflineAdd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie', 'dana'],
        ),
        _ExpectedProofMessage(
          key: 'danaAfterOfflineJoin',
          senderRole: 'dana',
          receiverRoles: <String>['alice', 'bob', 'charlie'],
        ),
      ];
    case 'gm004':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterCharlieRemove',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'bobAfterCharlieRemove',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
      ];
    case 'gm005':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterCharlieOfflineRemove1',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceAfterCharlieOfflineRemove2',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceAfterCharlieOfflineRemove3',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
      ];
    case 'gm006':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceDuringCharlieRemoval',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'charlieAfterImmediateReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceAfterImmediateReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'gm007':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceBeforeCharlieRemoval',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceDuringCharlieRemoval1',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceDuringCharlieRemoval2',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceDuringCharlieRemoval3',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceAfterCharlieReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    default:
      return const <_ExpectedProofMessage>[];
  }
}

void _validateScenarioProofFields({
  required String scenario,
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  if (scenario == 'gm004') {
    _validateGm004RemovalProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm005') {
    _validateGm005OfflineRemovalProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm006') {
    _validateGm006ImmediateReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm007') {
    _validateGm007HistoryBoundaryProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }

  if (scenario != 'gm003') return;

  final aliceProof = _mapValue(byRole['alice']?['gm003OfflineAddProof']);
  if (aliceProof == null) {
    failures.add('alice: missing GM-003 offline add proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm003OfflineAddProof',
      proof: aliceProof,
      field: 'danaOfflineDuringAdd',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm003OfflineAddProof',
      proof: aliceProof,
      field: 'postAddSentBeforeDanaLaunch',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm003OfflineAddProof',
      proof: aliceProof,
      field: 'danaLaunchedAfterPostAddSend',
      failures: failures,
    );
  }

  final danaProof = _mapValue(byRole['dana']?['gm003OfflineCatchUpProof']);
  if (danaProof == null) {
    failures.add('dana: missing GM-003 offline catch-up proof fields');
  } else {
    _requireTrueProof(
      role: 'dana',
      proofName: 'gm003OfflineCatchUpProof',
      proof: danaProof,
      field: 'startedAfterPostAddSend',
      failures: failures,
    );
    _requireTrueProof(
      role: 'dana',
      proofName: 'gm003OfflineCatchUpProof',
      proof: danaProof,
      field: 'installedGroupConfigBeforeCatchUp',
      failures: failures,
    );
    _requireTrueProof(
      role: 'dana',
      proofName: 'gm003OfflineCatchUpProof',
      proof: danaProof,
      field: 'drainedOfflineInbox',
      failures: failures,
    );
    _requireTrueProof(
      role: 'dana',
      proofName: 'gm003OfflineCatchUpProof',
      proof: danaProof,
      field: 'preAddMessageAbsent',
      failures: failures,
    );
    _requireTrueProof(
      role: 'dana',
      proofName: 'gm003OfflineCatchUpProof',
      proof: danaProof,
      field: 'postAddMessageCaughtUp',
      failures: failures,
    );
  }
}

void _validateGm004RemovalProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final aliceProof = _mapValue(byRole['alice']?['gm004RemovalProof']);
  final bobProof = _mapValue(byRole['bob']?['gm004RemovalProof']);
  final charlieProof = _mapValue(byRole['charlie']?['gm004RemovalProof']);

  if (aliceProof == null) {
    failures.add('alice: missing GM-004 removal proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm004RemovalProof',
      proof: aliceProof,
      field: 'charlieOnlineBeforeRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm004RemovalProof',
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm004RemovalProof',
      proof: aliceProof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: gm004RemovalProof.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GM-004 removal proof fields');
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm004RemovalProof',
      proof: bobProof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm004RemovalProof',
      proof: bobProof,
      field: 'hasRotatedEpoch',
      failures: failures,
    );
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GM-004 removal proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm004RemovalProof',
      proof: charlieProof,
      field: 'onlineBeforeRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm004RemovalProof',
      proof: charlieProof,
      field: 'currentMemberBeforeRemoval',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm004RemovalProof',
      proof: charlieProof,
      field: 'groupPresentAfterRemoval',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm004RemovalProof',
      proof: charlieProof,
      field: 'hasRotatedEpoch',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm004RemovalProof',
      proof: charlieProof,
      field: 'postRemovalPublishAccepted',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm004RemovalProof',
      proof: charlieProof,
      field: 'receivedAliceAfterRemoval',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm004RemovalProof',
      proof: charlieProof,
      field: 'receivedBobAfterRemoval',
      failures: failures,
    );
    final sendOutcome = _stringValue(charlieProof['postRemovalSendOutcome']);
    if (sendOutcome != 'groupNotFound' && sendOutcome != 'unauthorized') {
      failures.add(
        'charlie: gm004RemovalProof.postRemovalSendOutcome must reject send',
      );
    }
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add(
        'charlie: gm004RemovalProof.postRemovalPlaintextCount must be 0',
      );
    }
  }

  final aliceEpoch = _intValue(aliceProof?['rotatedEpoch']);
  final bobEpoch = _intValue(bobProof?['rotatedEpoch']);
  final charlieEpoch = _intValue(charlieProof?['rotatedEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: gm004RemovalProof.rotatedEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: gm004RemovalProof.rotatedEpoch must be >= 2');
  }
  if (aliceEpoch != null && bobEpoch != null && aliceEpoch != bobEpoch) {
    failures.add('alice/bob: GM-004 rotatedEpoch mismatch');
  }
  if (charlieEpoch != null &&
      aliceEpoch != null &&
      charlieEpoch >= aliceEpoch) {
    failures.add('charlie: gm004RemovalProof must not hold rotated epoch');
  }
}

void _validateGm005OfflineRemovalProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final aliceProof = _mapValue(byRole['alice']?['gm005OfflineRemovalProof']);
  final bobProof = _mapValue(byRole['bob']?['gm005OfflineRemovalProof']);
  final charlieProof = _mapValue(
    byRole['charlie']?['gm005OfflineRemovalProof'],
  );

  if (aliceProof == null) {
    failures.add('alice: missing GM-005 offline removal proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm005OfflineRemovalProof',
      proof: aliceProof,
      field: 'charlieOfflineBeforeRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm005OfflineRemovalProof',
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm005OfflineRemovalProof',
      proof: aliceProof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add(
        'alice: gm005OfflineRemovalProof.removedPeerId must be charlie',
      );
    }
    final postRemovalMessageCount = _intValue(
      aliceProof['postRemovalMessageCount'],
    );
    if (postRemovalMessageCount == null || postRemovalMessageCount < 3) {
      failures.add(
        'alice: gm005OfflineRemovalProof.postRemovalMessageCount must be >= 3',
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GM-005 offline removal proof fields');
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm005OfflineRemovalProof',
      proof: bobProof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm005OfflineRemovalProof',
      proof: bobProof,
      field: 'hasRotatedEpoch',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm005OfflineRemovalProof',
      proof: bobProof,
      field: 'receivedAllAlicePostRemovalMessages',
      failures: failures,
    );
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GM-005 offline removal proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm005OfflineRemovalProof',
      proof: charlieProof,
      field: 'hadOldConfigBeforeOffline',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm005OfflineRemovalProof',
      proof: charlieProof,
      field: 'hadOldKeyBeforeOffline',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm005OfflineRemovalProof',
      proof: charlieProof,
      field: 'offlineDuringRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm005OfflineRemovalProof',
      proof: charlieProof,
      field: 'reconnectedWithStaleState',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm005OfflineRemovalProof',
      proof: charlieProof,
      field: 'retrievedInboxAfterReconnect',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm005OfflineRemovalProof',
      proof: charlieProof,
      field: 'convergedRemoved',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm005OfflineRemovalProof',
      proof: charlieProof,
      field: 'groupPresentAfterCatchUp',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm005OfflineRemovalProof',
      proof: charlieProof,
      field: 'hasRotatedEpoch',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm005OfflineRemovalProof',
      proof: charlieProof,
      field: 'postRemovalPublishAccepted',
      failures: failures,
    );
    final sendOutcome = _stringValue(charlieProof['postRemovalSendOutcome']);
    if (sendOutcome != 'groupNotFound' && sendOutcome != 'unauthorized') {
      failures.add(
        'charlie: gm005OfflineRemovalProof.postRemovalSendOutcome must reject send',
      );
    }
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add(
        'charlie: gm005OfflineRemovalProof.postRemovalPlaintextCount must be 0',
      );
    }
  }

  final aliceEpoch = _intValue(aliceProof?['rotatedEpoch']);
  final bobEpoch = _intValue(bobProof?['rotatedEpoch']);
  final charlieEpoch = _intValue(charlieProof?['rotatedEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: gm005OfflineRemovalProof.rotatedEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: gm005OfflineRemovalProof.rotatedEpoch must be >= 2');
  }
  if (aliceEpoch != null && bobEpoch != null && aliceEpoch != bobEpoch) {
    failures.add('alice/bob: GM-005 rotatedEpoch mismatch');
  }
  if (charlieEpoch != null &&
      aliceEpoch != null &&
      charlieEpoch >= aliceEpoch) {
    failures.add(
      'charlie: gm005OfflineRemovalProof must not hold rotated epoch',
    );
  }
}

void _validateGm006ImmediateReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final aliceProof = _mapValue(byRole['alice']?['gm006ImmediateReaddProof']);
  final bobProof = _mapValue(byRole['bob']?['gm006ImmediateReaddProof']);
  final charlieProof = _mapValue(
    byRole['charlie']?['gm006ImmediateReaddProof'],
  );

  if (aliceProof == null) {
    failures.add('alice: missing GM-006 immediate re-add proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm006ImmediateReaddProof',
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm006ImmediateReaddProof',
      proof: aliceProof,
      field: 'readdedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm006ImmediateReaddProof',
      proof: aliceProof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm006ImmediateReaddProof',
      proof: aliceProof,
      field: 'sentRemovedWindowBeforeReadd',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm006ImmediateReaddProof',
      proof: aliceProof,
      field: 'receivedCharliePostReaddMessage',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add(
        'alice: gm006ImmediateReaddProof.removedPeerId must be charlie',
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GM-006 immediate re-add proof fields');
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm006ImmediateReaddProof',
      proof: bobProof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm006ImmediateReaddProof',
      proof: bobProof,
      field: 'receivedRemovedWindowMessage',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm006ImmediateReaddProof',
      proof: bobProof,
      field: 'receivedCharliePostReaddMessage',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm006ImmediateReaddProof',
      proof: bobProof,
      field: 'receivedAlicePostReaddMessage',
      failures: failures,
    );
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GM-006 immediate re-add proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm006ImmediateReaddProof',
      proof: charlieProof,
      field: 'memberListIncludesAliceBob',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm006ImmediateReaddProof',
      proof: charlieProof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm006ImmediateReaddProof',
      proof: charlieProof,
      field: 'hasStaleEpochAfterReadd',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm006ImmediateReaddProof',
      proof: charlieProof,
      field: 'postReaddPublishAccepted',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm006ImmediateReaddProof',
      proof: charlieProof,
      field: 'receivedAlicePostReaddMessage',
      failures: failures,
    );
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add(
        'charlie: gm006ImmediateReaddProof.removedWindowPlaintextCount must be 0',
      );
    }
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: gm006ImmediateReaddProof.finalEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: gm006ImmediateReaddProof.finalEpoch must be >= 2');
  }
  if (charlieEpoch == null || charlieEpoch < 2) {
    failures.add('charlie: gm006ImmediateReaddProof.finalEpoch must be >= 2');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GM-006 finalEpoch mismatch');
  }
}

void _validateGm007HistoryBoundaryProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final aliceProof = _mapValue(byRole['alice']?['gm007HistoryBoundaryProof']);
  final bobProof = _mapValue(byRole['bob']?['gm007HistoryBoundaryProof']);
  final charlieProof = _mapValue(
    byRole['charlie']?['gm007HistoryBoundaryProof'],
  );

  if (aliceProof == null) {
    failures.add('alice: missing GM-007 history-boundary proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm007HistoryBoundaryProof',
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm007HistoryBoundaryProof',
      proof: aliceProof,
      field: 'readdedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm007HistoryBoundaryProof',
      proof: aliceProof,
      field: 'sentPreRemovalBeforeRemove',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm007HistoryBoundaryProof',
      proof: aliceProof,
      field: 'sentRemovedWindowWhileRemoved',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm007HistoryBoundaryProof',
      proof: aliceProof,
      field: 'sentPostReaddAfterReadd',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm007HistoryBoundaryProof',
      proof: aliceProof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add(
        'alice: gm007HistoryBoundaryProof.removedPeerId must be charlie',
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GM-007 history-boundary proof fields');
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm007HistoryBoundaryProof',
      proof: bobProof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm007HistoryBoundaryProof',
      proof: bobProof,
      field: 'receivedPreRemovalMessage',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm007HistoryBoundaryProof',
      proof: bobProof,
      field: 'receivedPostReaddMessage',
      failures: failures,
    );
    final removedWindowCount = _intValue(
      bobProof['receivedRemovedWindowMessageCount'],
    );
    if (removedWindowCount != 3) {
      failures.add(
        'bob: gm007HistoryBoundaryProof.receivedRemovedWindowMessageCount must be 3',
      );
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GM-007 history-boundary proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm007HistoryBoundaryProof',
      proof: charlieProof,
      field: 'memberListIncludesAliceBob',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm007HistoryBoundaryProof',
      proof: charlieProof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm007HistoryBoundaryProof',
      proof: charlieProof,
      field: 'receivedPreRemovalMessage',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm007HistoryBoundaryProof',
      proof: charlieProof,
      field: 'receivedPostReaddMessage',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm007HistoryBoundaryProof',
      proof: charlieProof,
      field: 'hasStaleEpochAfterReadd',
      failures: failures,
    );
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add(
        'charlie: gm007HistoryBoundaryProof.removedWindowPlaintextCount must be 0',
      );
    }
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: gm007HistoryBoundaryProof.finalEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: gm007HistoryBoundaryProof.finalEpoch must be >= 2');
  }
  if (charlieEpoch == null || charlieEpoch < 2) {
    failures.add('charlie: gm007HistoryBoundaryProof.finalEpoch must be >= 2');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GM-007 finalEpoch mismatch');
  }
}

void _requireTrueProof({
  required String role,
  required String proofName,
  required Map<String, dynamic> proof,
  required String field,
  required List<String> failures,
}) {
  if (proof[field] != true) {
    failures.add('$role: $proofName.$field must be true');
  }
}

void _requireFalseProof({
  required String role,
  required String proofName,
  required Map<String, dynamic> proof,
  required String field,
  required List<String> failures,
}) {
  if (proof[field] != false) {
    failures.add('$role: $proofName.$field must be false');
  }
}

class _ExpectedProofMessage {
  const _ExpectedProofMessage({
    required this.key,
    required this.senderRole,
    required this.receiverRoles,
  });

  final String key;
  final String senderRole;
  final List<String> receiverRoles;
}

class _SentProofMessage {
  const _SentProofMessage({
    required this.messageId,
    required this.text,
    required this.senderPeerId,
    required this.keyEpoch,
  });

  final String messageId;
  final String text;
  final String senderPeerId;
  final int keyEpoch;
}

String? _stringValue(Object? value) {
  if (value == null) return null;
  if (value is String) return value.trim();
  return value.toString().trim();
}

String? _messageText(Map<String, dynamic> message) {
  final text = _stringValue(message['text']);
  if (text != null && text.isNotEmpty) return text;
  return _stringValue(message['plaintext']);
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map(_stringValue)
      .whereType<String>()
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

Map<String, int> _intMap(Object? value) {
  if (value is! Map) return const <String, int>{};
  final result = <String, int>{};
  for (final entry in value.entries) {
    final key = _stringValue(entry.key);
    final count = _intValue(entry.value);
    if (key != null && key.isNotEmpty && count != null) {
      result[key] = count;
    }
  }
  return result;
}
