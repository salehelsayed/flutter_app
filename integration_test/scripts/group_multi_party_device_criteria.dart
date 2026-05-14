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
const _ge001Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge001',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge002Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge002',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge003Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge003',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge004Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge004',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge005Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge005',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge006Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge006',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge007Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge007',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge008Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge008',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge009Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge009',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge010Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge010',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _go001Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'go001',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _go002Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'go002',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _go003Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'go003',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge011Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge011',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge012Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge012',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge013Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge013',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge014Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge014',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge015Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge015',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge016Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge016',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge020Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge020',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge021Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge021',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge023Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge023',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ge024Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ge024',
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
const _gm008Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm008',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm009Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm009',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm010Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm010',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm011Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm011',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm012Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm012',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm013Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm013',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm014Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm014',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm015Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm015',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm016Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm016',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm017Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm017',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm018Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm018',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm019Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm019',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm020Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm020',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm021Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm021',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm022Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm022',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm023Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm023',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm024Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm024',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm025Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm025',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm033Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm033',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm034Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm034',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _gm035Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'gm035',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _allRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'all',
  roles: <String>['alice', 'bob', 'charlie', 'dana'],
);

const _supportedScenarioText =
    'ge001, ge002, ge003, ge004, ge005, ge006, ge007, ge008, ge009, ge010, go001, go002, go003, ge011, ge012, ge013, ge014, ge015, ge016, ge020, ge021, ge023, ge024, gm001, gm002, gm003, gm004, gm005, gm006, gm007, gm008, gm009, gm010, gm011, gm012, gm013, gm014, gm015, gm016, gm017, gm018, gm019, gm020, gm021, gm022, gm023, gm024, gm025, gm033, gm034, gm035, or all';

GroupMultiPartyScenarioRequirement scenarioRequirement(String scenario) {
  final requirement = _tryScenarioRequirement(scenario);
  if (requirement == null) {
    throw ArgumentError.value(
      scenario,
      'scenario',
      'Expected $_supportedScenarioText',
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
      'Unsupported scenario "$scenario"; expected $_supportedScenarioText',
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
      'Verdicts must be evaluated for $_supportedScenarioText, got "$scenario"',
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
    } else if (peerIdByRole.containsValue(peerId) &&
        requirement.scenario != 'ge012' &&
        requirement.scenario != 'ge013') {
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
    if ((requirement.scenario == 'ge002' ||
            requirement.scenario == 'ge003' ||
            requirement.scenario == 'gm004' ||
            requirement.scenario == 'gm005' ||
            requirement.scenario == 'gm009' ||
            requirement.scenario == 'gm011' ||
            requirement.scenario == 'gm013' ||
            requirement.scenario == 'gm016' ||
            requirement.scenario == 'gm020' ||
            requirement.scenario == 'gm034') &&
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

  if (requirement.scenario == 'ge012' || requirement.scenario == 'ge013') {
    if (failures.isNotEmpty) {
      return GroupMultiPartyCriterion(false, failures.join('; '));
    }
    return GroupMultiPartyCriterion(
      true,
      '${requirement.scenario} verdicts valid for '
      '${requirement.roles.join(', ')}',
    );
  }

  final expectedPeerIds = requirement.roles
      .map((role) => peerIdByRole[role])
      .whereType<String>()
      .toSet();
  if (expectedPeerIds.length == requirement.roles.length) {
    if (requirement.scenario == 'ge002' ||
        requirement.scenario == 'ge003' ||
        requirement.scenario == 'gm004' ||
        requirement.scenario == 'gm005' ||
        requirement.scenario == 'gm009' ||
        requirement.scenario == 'gm011' ||
        requirement.scenario == 'gm013' ||
        requirement.scenario == 'gm016' ||
        requirement.scenario == 'gm017' ||
        requirement.scenario == 'go003' ||
        requirement.scenario == 'gm018' ||
        requirement.scenario == 'gm020' ||
        requirement.scenario == 'gm034') {
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
    case 'ge001':
      return _ge001Requirement;
    case 'ge002':
      return _ge002Requirement;
    case 'ge003':
      return _ge003Requirement;
    case 'ge004':
      return _ge004Requirement;
    case 'ge005':
      return _ge005Requirement;
    case 'ge006':
      return _ge006Requirement;
    case 'ge007':
      return _ge007Requirement;
    case 'ge008':
      return _ge008Requirement;
    case 'ge009':
      return _ge009Requirement;
    case 'ge010':
      return _ge010Requirement;
    case 'go001':
      return _go001Requirement;
    case 'go002':
      return _go002Requirement;
    case 'go003':
      return _go003Requirement;
    case 'ge011':
      return _ge011Requirement;
    case 'ge012':
      return _ge012Requirement;
    case 'ge013':
      return _ge013Requirement;
    case 'ge014':
      return _ge014Requirement;
    case 'ge015':
      return _ge015Requirement;
    case 'ge016':
      return _ge016Requirement;
    case 'ge020':
      return _ge020Requirement;
    case 'ge021':
      return _ge021Requirement;
    case 'ge023':
      return _ge023Requirement;
    case 'ge024':
      return _ge024Requirement;
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
    case 'gm008':
      return _gm008Requirement;
    case 'gm009':
      return _gm009Requirement;
    case 'gm010':
      return _gm010Requirement;
    case 'gm011':
      return _gm011Requirement;
    case 'gm012':
      return _gm012Requirement;
    case 'gm013':
      return _gm013Requirement;
    case 'gm014':
      return _gm014Requirement;
    case 'gm015':
      return _gm015Requirement;
    case 'gm016':
      return _gm016Requirement;
    case 'gm017':
      return _gm017Requirement;
    case 'gm018':
      return _gm018Requirement;
    case 'gm019':
      return _gm019Requirement;
    case 'gm020':
      return _gm020Requirement;
    case 'gm021':
      return _gm021Requirement;
    case 'gm022':
      return _gm022Requirement;
    case 'gm023':
      return _gm023Requirement;
    case 'gm024':
      return _gm024Requirement;
    case 'gm025':
      return _gm025Requirement;
    case 'gm033':
      return _gm033Requirement;
    case 'gm034':
      return _gm034Requirement;
    case 'gm035':
      return _gm035Requirement;
    case 'all':
      return _allRequirement;
    default:
      return null;
  }
}

String _normalizeScenario(String scenario) => scenario.trim().toLowerCase();

String _ge005RemovedKey(int cycle) =>
    'aliceGe005Removed${cycle.toString().padLeft(2, '0')}';

String _ge005ReaddKey(int cycle) =>
    'bobGe005Readd${cycle.toString().padLeft(2, '0')}';

const _ge008AlicePreKeys = <String>['aliceGe008Pre0', 'aliceGe008Pre1'];
const _ge008BobPreKeys = <String>['bobGe008Pre0', 'bobGe008Pre1'];
const _ge008CharliePreKeys = <String>['charlieGe008Pre0', 'charlieGe008Pre1'];
const _ge008AliceRemovedKeys = <String>[
  'aliceGe008Removed0',
  'aliceGe008Removed1',
];
const _ge008BobRemovedKeys = <String>['bobGe008Removed0', 'bobGe008Removed1'];
const _ge008AlicePostKeys = <String>['aliceGe008Post0', 'aliceGe008Post1'];
const _ge008BobPostKeys = <String>['bobGe008Post0', 'bobGe008Post1'];
const _ge008CharliePostKeys = <String>[
  'charlieGe008Post0',
  'charlieGe008Post1',
];
const _ge009PreKeys = <String>[
  'aliceGe009BeforePartition',
  'bobGe009BeforePartition',
  'charlieGe009BeforePartition',
];
const _ge009ReplayKeys = <String>['aliceGe009PostReadd', 'bobGe009PostReadd'];
const _ge009FinalKeys = <String>[
  ..._ge009PreKeys,
  ..._ge009ReplayKeys,
  'charlieGe009AfterHeal',
];
const _ge010ZeroPeerKey = 'aliceGe010ZeroPeerFallback';
const _ge011PartialLiveKey = 'aliceGe011PartialLiveFallback';
const _ge012AliceKey = 'aliceGe012ToBobDevices';
const _ge012BobPrimaryKey = 'bobGe012PrimarySend';
const _ge012BobSiblingKey = 'bobGe012SiblingSend';
const _ge013BobSiblingBeforeKey = 'bobGe013SiblingBeforeRevoke';
const _ge013BobSiblingAfterKey = 'bobGe013SiblingAfterRevoke';
const _ge013BobPrimaryAfterKey = 'bobGe013PrimaryAfterRevoke';
const _ge013AliceAfterKey = 'aliceGe013AfterRevoke';
const _ge014AliceRemovedWindowKey = 'aliceGe014RemovedWindow';
const _ge014AlicePostReaddKey = 'aliceGe014PostReadd';
const _ge014BobPostReaddKey = 'bobGe014PostReadd';
const _ge014CharlieAfterRestartKey = 'charlieGe014AfterRestart';
const _ge014CharliePostReaddKeys = <String>[
  _ge014AlicePostReaddKey,
  _ge014BobPostReaddKey,
];
const _ge015AliceRemovedWindowKey = 'aliceGe015RemovedWindow';
const _ge015BobAfterRemoveRepairKey = 'bobGe015AfterRemoveRepair';
const _ge015CharlieAfterInviteRepairKey = 'charlieGe015AfterInviteRepair';
const _ge020AliceInitialKey = 'aliceGe020Initial';
const _ge020BobHeldKey = 'bobGe020OfflineHeld';
const _ge020AliceAfterRejoinKey = 'aliceGe020AfterRejoin';
const _ge020AliceRemovedWindowKey = 'aliceGe020RemovedWindow';
const _ge020CharlieAfterReaddKey = 'charlieGe020AfterReadd';
const _ge021AliceInitialKey = 'aliceGe021Initial';
const _ge021BobWhileFlakyKey = 'bobGe021WhileFlaky';
const _ge021AliceAfterOnlineKey = 'aliceGe021AfterOnline';
const _ge021AliceRemovedWindowKey = 'aliceGe021RemovedWindow';
const _ge021CharlieAfterReaddKey = 'charlieGe021AfterReadd';
const _ge023AliceBeforeRemovalKey = 'aliceGe023BeforeRemoval';
const _ge023AliceRemovedWindowKey = 'aliceGe023RemovedWindow';
const _ge023CharlieAfterReaddKey = 'charlieGe023AfterReadd';
const _ge023ContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _ge024AliceBeforeRemovalParentKey = 'aliceGe024BeforeRemovalParent';
const _ge024AliceRemovedWindowParentKey = 'aliceGe024RemovedWindowParent';
const _ge024BobReplyAvailableKey = 'bobGe024ReplyAvailable';
const _ge024BobReplyUnavailableKey = 'bobGe024ReplyUnavailable';
const _go002InboxFailureKey = 'aliceGo002InboxStoreFailure';

List<_ExpectedProofMessage> _expectedMessagesForScenario(String scenario) {
  switch (scenario) {
    case 'ge001':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGe001Initial',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe001Initial',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieGe001Initial',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'ge002':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGe002PostRemoval01',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe002PostRemoval02',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe002PostRemoval03',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe002PostRemoval04',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe002PostRemoval05',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe002PostRemoval06',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe002PostRemoval07',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe002PostRemoval08',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe002PostRemoval09',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe002PostRemoval10',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
      ];
    case 'ge003':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'bobGe003PostRemoval01',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe003PostRemoval02',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe003PostRemoval03',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe003PostRemoval04',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe003PostRemoval05',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe003PostRemoval06',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe003PostRemoval07',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe003PostRemoval08',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe003PostRemoval09',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe003PostRemoval10',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
      ];
    case 'ge004':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGe004PostReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe004PostReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieGe004PostReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'ge005':
      return <_ExpectedProofMessage>[
        for (var cycle = 1; cycle <= 20; cycle++) ...[
          _ExpectedProofMessage(
            key: _ge005RemovedKey(cycle),
            senderRole: 'alice',
            receiverRoles: const <String>['bob'],
          ),
          _ExpectedProofMessage(
            key: _ge005ReaddKey(cycle),
            senderRole: 'bob',
            receiverRoles: const <String>['alice', 'charlie'],
          ),
        ],
      ];
    case 'ge006':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGe006RemovedWindow',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe006PostReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe006PostReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieGe006PostCatchUp',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'ge007':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGe007RemovedWindow',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe007PostReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieGe007PostReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe007PostCatchUp',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'ge008':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGe008Pre0',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe008Pre1',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe008Pre0',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe008Pre1',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieGe008Pre0',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'charlieGe008Pre1',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe008Removed0',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe008Removed1',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe008Removed0',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe008Removed1',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe008Post0',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe008Post1',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe008Post0',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe008Post1',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieGe008Post0',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'charlieGe008Post1',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'ge009':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGe009BeforePartition',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe009BeforePartition',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieGe009BeforePartition',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGe009PostReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGe009PostReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieGe009AfterHeal',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'ge010':
    case 'go001':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: _ge010ZeroPeerKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'go002':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: _go002InboxFailureKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'ge011':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: _ge011PartialLiveKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'ge014':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: _ge014AliceRemovedWindowKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: _ge014AlicePostReaddKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: _ge014BobPostReaddKey,
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: _ge014CharlieAfterRestartKey,
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'ge015':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: _ge015AliceRemovedWindowKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: _ge015BobAfterRemoveRepairKey,
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: _ge015CharlieAfterInviteRepairKey,
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'ge020':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: _ge020AliceInitialKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: _ge020BobHeldKey,
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: _ge020AliceAfterRejoinKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: _ge020AliceRemovedWindowKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: _ge020CharlieAfterReaddKey,
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'ge021':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: _ge021AliceInitialKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: _ge021BobWhileFlakyKey,
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: _ge021AliceAfterOnlineKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: _ge021AliceRemovedWindowKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: _ge021CharlieAfterReaddKey,
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'ge023':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: _ge023AliceBeforeRemovalKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: _ge023AliceRemovedWindowKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: _ge023CharlieAfterReaddKey,
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'ge024':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: _ge024AliceBeforeRemovalParentKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: _ge024AliceRemovedWindowParentKey,
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: _ge024BobReplyAvailableKey,
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: _ge024BobReplyUnavailableKey,
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
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
    case 'gm008':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceDuringCharlieRestartedRemoval',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'charlieAfterRestartReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceAfterRestartReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'gm009':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterDuplicateRemove',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'bobAfterDuplicateRemove',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
      ];
    case 'gm010':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'charlieAfterDuplicateReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceAfterDuplicateReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'gm011':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterStaleAdd',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'bobAfterStaleAdd',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
      ];
    case 'gm012':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterStaleRemove',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieAfterStaleRemove',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'bobAfterStaleRemove',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'gm013':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'charlieBeforeCutoff',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
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
    case 'gm014':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'gm015':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'bobAfterBlockedAdminSelfRemoval',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieAfterBlockedAdminLeave',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'gm016':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterCharlieUnsubscribe',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
      ];
    case 'gm017':
    case 'go003':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterStaleCharlieReject',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
      ];
    case 'gm018':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGm018Live1',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm018Live2',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm018Live3',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm018Inbox1',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm018Inbox2',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm018Inbox3',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm018AfterCharlieOffline',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
      ];
    case 'gm019':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGm019RemovedWindow',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm019AfterReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGm019AfterReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'gm020':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGm020ImmediatePostRemoval',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm020OfflinePostRemoval',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
      ];
    case 'gm021':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'charlieGm021FreshAfterReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'gm022':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'charlieGm022AfterReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm022AfterReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGm022AfterReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'gm023':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'charlieGm023AfterInactiveShadow',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm023AfterInactiveShadow',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGm023AfterInactiveShadow',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'gm024':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'charlieGm024AfterReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm024AfterReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGm024AfterReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'gm025':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'charlieGm025AfterReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm025AfterReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGm025AfterReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'gm033':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGm033BeforeRemoval',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm033RemovedWindow',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm033AfterReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobGm033AfterReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'gm034':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceGm034MessageThenConfig',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceGm034ConfigThenMessage',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
      ];
    case 'gm035':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'charlieGm035FirstAfterReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
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
  if (scenario == 'ge002') {
    _validateGe002RemovalContinuityProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge003') {
    _validateGe003RemainingPairProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge004') {
    _validateGe004ReaddExchangeProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge005') {
    _validateGe005RemoveReaddLoopProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge006') {
    _validateGe006OfflineReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge007') {
    _validateGe007OfflineObserverProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge008') {
    _validateGe008SendStormProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge009') {
    _validateGe009PartitionHealProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge010' || scenario == 'go001') {
    _validateGe010ZeroLivePeersInboxFallbackProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'go002') {
    _validateGo002InboxStoreFailureSenderStatusProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge011') {
    _validateGe011PartialLivePeersInboxFallbackProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge012') {
    _validateGe012SameUserMultiDeviceProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge013') {
    _validateGe013DeviceRevocationProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge014') {
    _validateGe014RestartBeforeTopicJoinProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge015') {
    _validateGe015AdminRestartMutationProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge016') {
    _validateGe016ConcurrentAdminMutationProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge020') {
    _validateGe020LongSoakChurnProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge021') {
    _validateGe021LargeGroupFlakyMemberProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge023') {
    _validateGe023MediaReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ge024') {
    _validateGe024QuotedReplyProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
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
  if (scenario == 'gm008') {
    _validateGm008RestartReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm009') {
    _validateGm009DuplicateRemovalProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm010') {
    _validateGm010DuplicateReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm011') {
    _validateGm011StaleAddRemovalProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm012') {
    _validateGm012StaleRemoveReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm013') {
    _validateGm013SimultaneousRemoveSendProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm014') {
    _validateGm014SimultaneousReaddSendProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm015') {
    _validateGm015AdminSelfRemovalPolicyProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm016') {
    _validateGm016RemovedUnsubscribeProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm017') {
    _validateGm017StaleSubscriptionValidationProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'go003') {
    _validateGm017StaleSubscriptionValidationProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
      proofName: 'go003SenderValidationFeedbackProof',
      label: 'GO-003',
      requireSenderFeedback: true,
    );
    return;
  }
  if (scenario == 'gm018') {
    _validateGm018RemainingDeliveryContinuityProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm019') {
    _validateGm019DurableRecipientWindowProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm020') {
    _validateGm020ImmediateRemovedRecipientExclusionProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm021') {
    _validateGm021FreshReaddPackageProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm022') {
    _validateGm022RepeatedReaddDedupProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm023') {
    _validateGm023InactiveShadowProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm024') {
    _validateGm024MemberDisplayStateProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm025') {
    _validateGm025RolePermissionReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm033') {
    _validateGm033ReplayDuringMembershipUpdateProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm034') {
    _validateGm034ConfigUpdateReceiveOrderProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'gm035') {
    _validateGm035ZeroPeerReaddFirstSendProof(
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

Map<String, dynamic>? _singleSentEntry(
  Map<String, dynamic>? verdict,
  String key,
  String role,
  List<String> failures,
) {
  final entries = _mapList(
    verdict?['sentMessages'],
  ).where((entry) => _stringValue(entry['key']) == key).toList(growable: false);
  if (entries.length != 1) {
    failures.add(
      '$role: sent $key count=${entries.length}; requires exactly one',
    );
    return null;
  }
  return entries.single;
}

Map<String, dynamic>? _singleReceivedEntry(
  Map<String, dynamic>? verdict,
  String key,
  String role,
  List<String> failures,
) {
  final entries = _mapList(
    verdict?['receivedMessages'],
  ).where((entry) => _stringValue(entry['key']) == key).toList(growable: false);
  if (entries.length != 1) {
    failures.add(
      '$role: received $key count=${entries.length}; requires exactly one',
    );
    return null;
  }
  return entries.single;
}

void _validateGe012SameUserMultiDeviceProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final alice = byRole['alice'];
  final bob = byRole['bob'];
  final sibling = byRole['charlie'];
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final siblingPeerId = peerIdByRole['charlie'];
  final bobTransport = _stringValue(bob?['transportPeerId']);
  final siblingTransport = _stringValue(sibling?['transportPeerId']);

  if (alicePeerId == null || bobPeerId == null || siblingPeerId == null) {
    failures.add('ge012: missing role peer ids');
    return;
  }
  if (bobPeerId != siblingPeerId) {
    failures.add('ge012: bob and charlie roles must share one logical peer id');
  }
  if (alicePeerId == bobPeerId) {
    failures.add('ge012: alice and logical bob peer ids must differ');
  }
  if (bobTransport == null ||
      siblingTransport == null ||
      bobTransport.isEmpty ||
      siblingTransport.isEmpty ||
      bobTransport == siblingTransport) {
    failures.add('ge012: bob primary and sibling transports must be distinct');
  }

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?['ge012SameUserDeviceProof']);
    if (proof == null) {
      failures.add('$role: missing ge012SameUserDeviceProof');
      continue;
    }
    final members = _stringList(proof['memberPeerIds']).toSet();
    if (!members.contains(alicePeerId) || !members.contains(bobPeerId)) {
      failures.add('$role: ge012 membership missing Alice or logical Bob');
    }
    if (_intValue(proof['logicalBobMembershipCount']) != 1) {
      failures.add('$role: logical Bob membership count must be exactly one');
    }
    final deviceIds = _stringList(proof['logicalBobDeviceIds']).toSet();
    if (bobTransport != null &&
        siblingTransport != null &&
        (!deviceIds.contains(bobTransport) ||
            !deviceIds.contains(siblingTransport))) {
      failures.add('$role: logical Bob devices missing primary or sibling');
    }
  }

  final aliceSent = _singleSentEntry(alice, _ge012AliceKey, 'alice', failures);
  final bobSent = _singleSentEntry(bob, _ge012BobPrimaryKey, 'bob', failures);
  final siblingSent = _singleSentEntry(
    sibling,
    _ge012BobSiblingKey,
    'charlie',
    failures,
  );

  void validateSent(
    Map<String, dynamic>? sent, {
    required String role,
    required String key,
    required String expectedPeerId,
    required String? expectedTransport,
  }) {
    if (sent == null) return;
    final outcome = _stringValue(sent['outcome']);
    if (outcome != 'success' && outcome != 'successNoPeers') {
      failures.add('$role: sent $key outcome=$outcome');
    }
    if (_stringValue(sent['senderPeerId']) != expectedPeerId) {
      failures.add('$role: sent $key senderPeerId mismatch');
    }
    if (expectedTransport != null &&
        _stringValue(sent['senderDeviceId']) != expectedTransport) {
      failures.add('$role: sent $key senderDeviceId mismatch');
    }
    if (expectedTransport != null &&
        _stringValue(sent['transportPeerId']) != expectedTransport) {
      failures.add('$role: sent $key transportPeerId mismatch');
    }
    if (_stringValue(sent['messageId']) == null ||
        _messageText(sent) == null ||
        (_intValue(sent['keyEpoch']) ?? 0) < 1) {
      failures.add('$role: sent $key missing message id/text/key epoch');
    }
  }

  validateSent(
    aliceSent,
    role: 'alice',
    key: _ge012AliceKey,
    expectedPeerId: alicePeerId,
    expectedTransport: _stringValue(alice?['transportPeerId']),
  );
  validateSent(
    bobSent,
    role: 'bob',
    key: _ge012BobPrimaryKey,
    expectedPeerId: bobPeerId,
    expectedTransport: bobTransport,
  );
  validateSent(
    siblingSent,
    role: 'charlie',
    key: _ge012BobSiblingKey,
    expectedPeerId: bobPeerId,
    expectedTransport: siblingTransport,
  );

  void validateReceived({
    required Map<String, dynamic>? verdict,
    required String role,
    required String key,
    required Map<String, dynamic>? sent,
    required bool expectedIncoming,
  }) {
    final received = _singleReceivedEntry(verdict, key, role, failures);
    if (received == null || sent == null) return;
    if (_stringValue(received['messageId']) !=
        _stringValue(sent['messageId'])) {
      failures.add('$role: received $key messageId mismatch');
    }
    if (_messageText(received) != _messageText(sent)) {
      failures.add('$role: received $key text mismatch');
    }
    if (_stringValue(received['senderPeerId']) !=
        _stringValue(sent['senderPeerId'])) {
      failures.add('$role: received $key senderPeerId mismatch');
    }
    if (received['isIncoming'] != expectedIncoming) {
      failures.add('$role: received $key isIncoming=${received['isIncoming']}');
    }
    if ((_intValue(received['persistedCount']) ?? 0) != 1) {
      failures.add('$role: received $key persistedCount must be exactly one');
    }
  }

  validateReceived(
    verdict: bob,
    role: 'bob',
    key: _ge012AliceKey,
    sent: aliceSent,
    expectedIncoming: true,
  );
  validateReceived(
    verdict: sibling,
    role: 'charlie',
    key: _ge012AliceKey,
    sent: aliceSent,
    expectedIncoming: true,
  );
  validateReceived(
    verdict: alice,
    role: 'alice',
    key: _ge012BobPrimaryKey,
    sent: bobSent,
    expectedIncoming: true,
  );
  validateReceived(
    verdict: sibling,
    role: 'charlie',
    key: _ge012BobPrimaryKey,
    sent: bobSent,
    expectedIncoming: false,
  );
  validateReceived(
    verdict: alice,
    role: 'alice',
    key: _ge012BobSiblingKey,
    sent: siblingSent,
    expectedIncoming: true,
  );
  validateReceived(
    verdict: bob,
    role: 'bob',
    key: _ge012BobSiblingKey,
    sent: siblingSent,
    expectedIncoming: false,
  );
}

void _validateGe013DeviceRevocationProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge013DeviceRevocationProof';
  final alice = byRole['alice'];
  final bob = byRole['bob'];
  final sibling = byRole['charlie'];
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final siblingPeerId = peerIdByRole['charlie'];
  final aliceTransport = _stringValue(alice?['transportPeerId']);
  final bobTransport = _stringValue(bob?['transportPeerId']);
  final siblingTransport = _stringValue(sibling?['transportPeerId']);

  if (alicePeerId == null || bobPeerId == null || siblingPeerId == null) {
    failures.add('ge013: missing role peer ids');
    return;
  }
  if (bobPeerId != siblingPeerId) {
    failures.add('ge013: bob and charlie roles must share one logical peer id');
  }
  if (alicePeerId == bobPeerId) {
    failures.add('ge013: alice and logical bob peer ids must differ');
  }
  if (bobTransport == null ||
      siblingTransport == null ||
      bobTransport.isEmpty ||
      siblingTransport.isEmpty ||
      bobTransport == siblingTransport) {
    failures.add('ge013: bob primary and sibling transports must be distinct');
  }

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing $proofName');
      continue;
    }
    final members = _stringList(proof['memberPeerIds']).toSet();
    if (!members.contains(alicePeerId) || !members.contains(bobPeerId)) {
      failures.add('$role: ge013 membership missing Alice or logical Bob');
    }
    if (_intValue(proof['logicalBobMembershipCount']) != 1) {
      failures.add('$role: logical Bob membership count must be exactly one');
    }
    final activeDevices = _stringList(
      proof['activeLogicalBobDeviceIds'],
    ).toSet();
    final revokedDevices = _stringList(
      proof['revokedLogicalBobDeviceIds'],
    ).toSet();
    if (bobTransport != null && !activeDevices.contains(bobTransport)) {
      failures.add('$role: active logical Bob devices missing B1');
    }
    if (siblingTransport != null && activeDevices.contains(siblingTransport)) {
      failures.add('$role: revoked sibling still appears active');
    }
    if (siblingTransport != null &&
        !revokedDevices.contains(siblingTransport)) {
      failures.add('$role: revoked logical Bob devices missing B2');
    }
    if (siblingTransport != null &&
        _stringValue(proof['revokedSiblingDeviceId']) != siblingTransport) {
      failures.add('$role: revokedSiblingDeviceId must be B2 transport');
    }
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'revocationApplied',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'b1RemainedActive',
      failures: failures,
    );
  }

  for (final role in const <String>['alice', 'bob']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) continue;
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'noPostRevokeB2Plaintext',
      failures: failures,
    );
  }
  final siblingProof = _mapValue(sibling?[proofName]);
  if (siblingProof != null) {
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: siblingProof,
      field: 'b2PostRevokeAccepted',
      failures: failures,
    );
    if (_stringValue(siblingProof['b2PostRevokeOutcome']) != 'unauthorized') {
      failures.add(
        'charlie: $proofName.b2PostRevokeOutcome must be unauthorized',
      );
    }
  }

  final siblingBeforeSent = _singleSentEntry(
    sibling,
    _ge013BobSiblingBeforeKey,
    'charlie',
    failures,
  );
  final siblingAfterSent = _singleSentEntry(
    sibling,
    _ge013BobSiblingAfterKey,
    'charlie',
    failures,
  );
  final bobAfterSent = _singleSentEntry(
    bob,
    _ge013BobPrimaryAfterKey,
    'bob',
    failures,
  );
  final aliceAfterSent = _singleSentEntry(
    alice,
    _ge013AliceAfterKey,
    'alice',
    failures,
  );

  void validateSuccessfulSent(
    Map<String, dynamic>? sent, {
    required String role,
    required String key,
    required String expectedPeerId,
    required String? expectedTransport,
  }) {
    if (sent == null) return;
    final outcome = _stringValue(sent['outcome']);
    if (outcome != 'success' && outcome != 'successNoPeers') {
      failures.add('$role: sent $key outcome=$outcome');
    }
    if (_stringValue(sent['senderPeerId']) != expectedPeerId) {
      failures.add('$role: sent $key senderPeerId mismatch');
    }
    if (expectedTransport != null &&
        _stringValue(sent['senderDeviceId']) != expectedTransport) {
      failures.add('$role: sent $key senderDeviceId mismatch');
    }
    if (expectedTransport != null &&
        _stringValue(sent['transportPeerId']) != expectedTransport) {
      failures.add('$role: sent $key transportPeerId mismatch');
    }
    if (_stringValue(sent['messageId']) == null ||
        _messageText(sent) == null ||
        (_intValue(sent['keyEpoch']) ?? 0) < 1) {
      failures.add('$role: sent $key missing message id/text/key epoch');
    }
  }

  validateSuccessfulSent(
    siblingBeforeSent,
    role: 'charlie',
    key: _ge013BobSiblingBeforeKey,
    expectedPeerId: bobPeerId,
    expectedTransport: siblingTransport,
  );
  validateSuccessfulSent(
    bobAfterSent,
    role: 'bob',
    key: _ge013BobPrimaryAfterKey,
    expectedPeerId: bobPeerId,
    expectedTransport: bobTransport,
  );
  validateSuccessfulSent(
    aliceAfterSent,
    role: 'alice',
    key: _ge013AliceAfterKey,
    expectedPeerId: alicePeerId,
    expectedTransport: aliceTransport,
  );

  if (siblingAfterSent != null) {
    final outcome = _stringValue(siblingAfterSent['outcome']);
    if (outcome != 'unauthorized') {
      failures.add('charlie: sent $_ge013BobSiblingAfterKey outcome=$outcome');
    }
    if (siblingAfterSent['accepted'] != false) {
      failures.add(
        'charlie: sent $_ge013BobSiblingAfterKey accepted must be false',
      );
    }
    if (_stringValue(siblingAfterSent['senderPeerId']) != bobPeerId) {
      failures.add(
        'charlie: sent $_ge013BobSiblingAfterKey senderPeerId mismatch',
      );
    }
    if (siblingTransport != null &&
        _stringValue(siblingAfterSent['senderDeviceId']) != siblingTransport) {
      failures.add(
        'charlie: sent $_ge013BobSiblingAfterKey senderDeviceId mismatch',
      );
    }
  }

  void validateReceived({
    required Map<String, dynamic>? verdict,
    required String role,
    required String key,
    required Map<String, dynamic>? sent,
    required bool expectedIncoming,
  }) {
    final received = _singleReceivedEntry(verdict, key, role, failures);
    if (received == null || sent == null) return;
    if (_stringValue(received['messageId']) !=
        _stringValue(sent['messageId'])) {
      failures.add('$role: received $key messageId mismatch');
    }
    if (_messageText(received) != _messageText(sent)) {
      failures.add('$role: received $key text mismatch');
    }
    if (_stringValue(received['senderPeerId']) !=
        _stringValue(sent['senderPeerId'])) {
      failures.add('$role: received $key senderPeerId mismatch');
    }
    if (received['isIncoming'] != expectedIncoming) {
      failures.add('$role: received $key isIncoming=${received['isIncoming']}');
    }
    if ((_intValue(received['persistedCount']) ?? 0) != 1) {
      failures.add('$role: received $key persistedCount must be exactly one');
    }
  }

  validateReceived(
    verdict: alice,
    role: 'alice',
    key: _ge013BobSiblingBeforeKey,
    sent: siblingBeforeSent,
    expectedIncoming: true,
  );
  validateReceived(
    verdict: bob,
    role: 'bob',
    key: _ge013BobSiblingBeforeKey,
    sent: siblingBeforeSent,
    expectedIncoming: false,
  );
  validateReceived(
    verdict: alice,
    role: 'alice',
    key: _ge013BobPrimaryAfterKey,
    sent: bobAfterSent,
    expectedIncoming: true,
  );
  validateReceived(
    verdict: bob,
    role: 'bob',
    key: _ge013AliceAfterKey,
    sent: aliceAfterSent,
    expectedIncoming: true,
  );

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final hasPostRevokeB2Plaintext = _mapList(
      byRole[role]?['receivedMessages'],
    ).any((entry) => _stringValue(entry['key']) == _ge013BobSiblingAfterKey);
    if (hasPostRevokeB2Plaintext) {
      failures.add('$role: received post-revoke B2 plaintext');
    }
  }
}

void _validateGe014RestartBeforeTopicJoinProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge014RestartBeforeTopicJoinProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMembers = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};

  if (aliceProof == null) {
    failures.add(
      'alice: missing GE-014 restart before topic join proof fields',
    );
  } else {
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlie',
      'charlieReceivedInviteBeforeRestart',
      'charliePersistedInviteBeforeRestart',
      'charliePersistedKeyBeforeRestart',
      'charlieNotJoinedTopicBeforeRestart',
      'charlieRestartedBeforeTopicJoin',
      'sentPostReaddMessages',
      'receivedCharliePostRestartMessage',
      'memberListIncludesCharlie',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    _requireFalseProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'charlieJoinedTopicBeforeRestart',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GE-014 restart before topic join proof fields');
  } else {
    for (final field in const <String>[
      'observedCharlieRestartBoundary',
      'receivedRemovedWindowMessage',
      'receivedAlicePostReaddMessage',
      'receivedCharliePostRestartMessage',
      'memberListIncludesCharlie',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (charlieProof == null) {
    failures.add(
      'charlie: missing GE-014 restart before topic join proof fields',
    );
  } else {
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlie',
      'charlieReceivedInviteBeforeRestart',
      'charliePersistedInviteBeforeRestart',
      'charliePersistedKeyBeforeRestart',
      'charlieNotJoinedTopicBeforeRestart',
      'charlieRestartedBeforeTopicJoin',
      'charlieRecoveredInviteAfterRestart',
      'charlieRecoveredKeyAfterRestart',
      'charlieJoinedTopicAfterRestart',
      'retrievedPostReaddMessages',
      'postReaddPublishAccepted',
      'memberListIncludesAliceBob',
      'memberListIncludesCharlie',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'charlieJoinedTopicBeforeRestart',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'hasStaleEpochAfterRestart',
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postReaddReceivedKeys',
      expected: _ge014CharliePostReaddKeys,
      failures: failures,
    );
  }

  for (final entry in <String, Map<String, dynamic>?>{
    'alice': aliceProof,
    'bob': bobProof,
    'charlie': charlieProof,
  }.entries) {
    final proof = entry.value;
    if (proof == null) continue;
    _requireIntAtLeastProof(
      role: entry.key,
      proofName: proofName,
      proof: proof,
      field: 'finalEpoch',
      minimum: 2,
      failures: failures,
    );
    if (expectedMembers.length == 3 && proof.containsKey('memberPeerIds')) {
      _requireProofPeerSet(
        role: entry.key,
        proofName: proofName,
        proof: proof,
        field: 'memberPeerIds',
        expected: expectedMembers,
        failures: failures,
      );
    }
  }

  final epochs = <int>{};
  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GE-014 finalEpoch mismatch');
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: _ge014AliceRemovedWindowKey,
      expectedPeerIds: <String>{bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: _ge014AlicePostReaddKey,
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: _ge014BobPostReaddKey,
      expectedPeerIds: <String>{alicePeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: _ge014CharlieAfterRestartKey,
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGe015AdminRestartMutationProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge015AdminRestartMutationProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMembers = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};

  if (aliceProof == null) {
    failures.add('alice: missing GE-015 admin restart mutation proof fields');
  } else {
    for (final field in const <String>[
      'adminPersistedLocalMutationBeforeRestart',
      'adminRestartedBeforeFanoutComplete',
      'removeFanoutInterruptedBeforeRestart',
      'removeFanoutRepairCompletedAfterRestart',
      'addInviteStatusDurableBeforeRestart',
      'addInviteRepairCompletedAfterRestart',
      'allActivePeersConverged',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'strandedPeerCount',
      expected: 0,
      failures: failures,
    );
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedWindowPlaintextLeakCount',
      expected: 0,
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'finalEpoch',
      minimum: 3,
      failures: failures,
    );
    final pendingStatus = _stringValue(
      aliceProof['pendingFanoutStatusBeforeRestart'],
    );
    if (pendingStatus != 'needs_resend' && pendingStatus != 'pending_repair') {
      failures.add(
        'alice: $proofName.pendingFanoutStatusBeforeRestart must be '
        'needs_resend or pending_repair',
      );
    }
    final finalStatus = _stringValue(aliceProof['finalFanoutStatus']);
    if (finalStatus != 'sent' && finalStatus != 'complete') {
      failures.add('alice: $proofName.finalFanoutStatus must be sent/complete');
    }
    if ((finalStatus == 'sent' || finalStatus == 'complete') &&
        aliceProof['addInviteRepairCompletedAfterRestart'] != true) {
      failures.add(
        'alice: $proofName.finalFanoutStatus cannot be sent before repair',
      );
    }
    if (expectedMembers.length == 3 &&
        aliceProof.containsKey('memberPeerIds')) {
      _requireProofPeerSet(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: 'memberPeerIds',
        expected: expectedMembers,
        failures: failures,
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GE-015 admin restart mutation proof fields');
  } else {
    for (final field in const <String>[
      'observedAdminRestartBoundary',
      'receivedRemoveRepairKey',
      'receivedRemovedWindowMessage',
      'receivedCharlieAfterInviteRepair',
      'allActivePeersConverged',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'strandedPeerCount',
      expected: 0,
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'finalEpoch',
      minimum: 3,
      failures: failures,
    );
    if (expectedMembers.length == 3 && bobProof.containsKey('memberPeerIds')) {
      _requireProofPeerSet(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: 'memberPeerIds',
        expected: expectedMembers,
        failures: failures,
      );
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GE-015 admin restart mutation proof fields');
  } else {
    for (final field in const <String>[
      'removedBeforeAdminRestart',
      'notEntitledDuringRemovedWindow',
      'joinedAfterInviteRepair',
      'sentAfterInviteRepair',
      'allActivePeersConverged',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'hasStaleEpochAfterRepair',
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'finalEpoch',
      minimum: 3,
      failures: failures,
    );
    if (expectedMembers.length == 3 &&
        charlieProof.containsKey('memberPeerIds')) {
      _requireProofPeerSet(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: 'memberPeerIds',
        expected: expectedMembers,
        failures: failures,
      );
    }
  }

  final epochs = <int>{};
  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GE-015 finalEpoch mismatch');
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: _ge015AliceRemovedWindowKey,
      expectedPeerIds: <String>{bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: _ge015BobAfterRemoveRepairKey,
      expectedPeerIds: <String>{alicePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: _ge015CharlieAfterInviteRepairKey,
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGe016ConcurrentAdminMutationProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge016ConcurrentAdminMutationProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedActivePeers = <String>{
    ?alicePeerId,
    ?bobPeerId,
    ?charliePeerId,
  };
  final danaPeerIds = <String>{};

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add(
        '$role: missing GE-016 concurrent admin mutation proof fields',
      );
      continue;
    }

    for (final field in const <String>[
      'bobPromotedToAdmin',
      'aliceRemoveCharliePrepared',
      'bobAddDanaApplied',
      'staleRemovePublishedAfterAdd',
      'allActivePeersConverged',
      'finalMembershipConverged',
      'charliePresentAfterConflict',
      'danaPresentAfterConflict',
      'addWinsByVersion',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }

    final winner = _stringValue(proof['deterministicConflictWinner']);
    if (winner != 'bob_add_dana') {
      failures.add(
        '$role: $proofName.deterministicConflictWinner must be bob_add_dana',
      );
    }

    final finalMembers = _stringList(proof['finalMemberPeerIds']).toSet();
    final missingActivePeers = expectedActivePeers.difference(finalMembers);
    if (missingActivePeers.isNotEmpty) {
      failures.add(
        '$role: GE-016 final membership missing '
        '${missingActivePeers.join(', ')}',
      );
    }
    final danaCandidates = finalMembers.difference(expectedActivePeers);
    if (danaCandidates.length != 1) {
      failures.add(
        '$role: GE-016 final membership must include exactly one Dana',
      );
    } else {
      danaPeerIds.add(danaCandidates.single);
    }

    final finalRoles = _mapValue(proof['finalRolesByPeerId']);
    if (finalRoles == null) {
      failures.add('$role: $proofName.finalRolesByPeerId is required');
    } else {
      if (alicePeerId != null &&
          _stringValue(finalRoles[alicePeerId]) != 'admin') {
        failures.add('$role: GE-016 Alice final role must be admin');
      }
      if (bobPeerId != null && _stringValue(finalRoles[bobPeerId]) != 'admin') {
        failures.add('$role: GE-016 Bob final role must be admin');
      }
      if (charliePeerId != null &&
          _stringValue(finalRoles[charliePeerId]) != 'writer') {
        failures.add('$role: GE-016 Charlie final role must be writer');
      }
      if (danaCandidates.length == 1 &&
          _stringValue(finalRoles[danaCandidates.single]) != 'writer') {
        failures.add('$role: GE-016 Dana final role must be writer');
      }
    }

    final addDanaAt = _dateTimeValue(proof['addDanaAt']);
    final lastMembershipEventAt = _dateTimeValue(
      proof['lastMembershipEventAt'],
    );
    if (addDanaAt == null || lastMembershipEventAt == null) {
      failures.add(
        '$role: GE-016 addDanaAt and lastMembershipEventAt are required',
      );
    } else if (!lastMembershipEventAt.isAtSameMomentAs(addDanaAt)) {
      failures.add('$role: GE-016 lastMembershipEventAt must match addDanaAt');
    }
  }

  if (danaPeerIds.length > 1) {
    failures.add('alice/bob/charlie: GE-016 Dana peer mismatch');
  }
}

void _validateGe020LongSoakChurnProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge020LongSoakChurnProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMembers = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};
  final epochs = <int>{};

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing GE-020 long soak churn proof fields');
      continue;
    }

    for (final field in const <String>[
      'noPermanentDeafMember',
      'allActivePeersConverged',
      'heldDeliveryQueuesDrained',
      'noStrandedRetryQueues',
      'noRemovedWindowPlaintext',
      'duplicateDeliveryDeduped',
      'keyEpochConverged',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'strandedQueueCount',
      expected: 0,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'finalEpoch',
      minimum: 2,
      failures: failures,
    );
    final epoch = _intValue(proof['finalEpoch']);
    if (epoch != null) epochs.add(epoch);
    if (expectedMembers.length == 3 && proof.containsKey('memberPeerIds')) {
      _requireProofPeerSet(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'memberPeerIds',
        expected: expectedMembers,
        failures: failures,
      );
    }
  }

  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  if (charlieProof != null) {
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postRemovalSendAccepted',
      failures: failures,
    );
  }

  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GE-020 finalEpoch mismatch');
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: _ge020AliceInitialKey,
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: _ge020BobHeldKey,
      expectedPeerIds: <String>{alicePeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: _ge020AliceAfterRejoinKey,
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: _ge020AliceRemovedWindowKey,
      expectedPeerIds: <String>{bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: _ge020CharlieAfterReaddKey,
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGe021LargeGroupFlakyMemberProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge021LargeGroupFlakyMemberProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final actualPeerIds = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};
  final stableDevicePeerIds = <String>{?alicePeerId, ?bobPeerId};
  final finalRosters = <Set<String>>[];
  final epochs = <int>{};

  void requireSentRecipientsInclude({
    required String role,
    required String key,
    required Set<String> requiredPeerIds,
    Set<String> forbiddenPeerIds = const <String>{},
  }) {
    final verdict = byRole[role];
    if (verdict == null) return;
    final sentEntries = _mapList(verdict['sentMessages'])
        .where((entry) => _stringValue(entry['key']) == key)
        .toList(growable: false);
    if (sentEntries.length != 1) return;

    final recipientPeerIds = _stringList(
      sentEntries.single['recipientPeerIds'],
    );
    if (recipientPeerIds.isEmpty) {
      failures.add('$role: sent $key missing recipientPeerIds');
      return;
    }
    final uniqueRecipientPeerIds = recipientPeerIds.toSet();
    if (recipientPeerIds.length != uniqueRecipientPeerIds.length) {
      failures.add('$role: sent $key recipientPeerIds contain duplicates');
    }
    final missing = requiredPeerIds.difference(uniqueRecipientPeerIds);
    if (missing.isNotEmpty) {
      failures.add(
        '$role: sent $key recipientPeerIds missing ${missing.join(', ')}',
      );
    }
    final forbidden = uniqueRecipientPeerIds.intersection(forbiddenPeerIds);
    if (forbidden.isNotEmpty) {
      failures.add(
        '$role: sent $key recipientPeerIds included forbidden '
        '${forbidden.join(', ')}',
      );
    }
  }

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing GE-021 large group flaky member proof');
      continue;
    }

    for (final field in const <String>[
      'allStableDevicesConverged',
      'stableMemberDeliveryConverged',
      'noStableMemberMisses',
      'flakyLiveLeaveRejoinCompleted',
      'flakyRemovedAndReadded',
      'finalRosterConverged',
      'finalIncludesFlaky',
      'noRemovedWindowPlaintext',
      'keyEpochConverged',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    _requireIntAtLeastProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'largeGroupRosterSize',
      minimum: 10,
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'syntheticStableMemberCount',
      minimum: 7,
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'flakyChurnCycles',
      minimum: 2,
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'finalEpoch',
      minimum: 2,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'stableMessageMissCount',
      expected: 0,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'strandedQueueCount',
      expected: 0,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );

    final epoch = _intValue(proof['finalEpoch']);
    if (epoch != null) epochs.add(epoch);
    if (role == 'charlie') {
      _requireFalseProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'postRemovalSendAccepted',
        failures: failures,
      );
    }
    if (charliePeerId != null &&
        _stringValue(proof['flakyPeerId']) != charliePeerId) {
      failures.add('$role: $proofName.flakyPeerId must be Charlie');
    }

    final stableDevices = _stringList(proof['stableDevicePeerIds']).toSet();
    final missingStableDevices = stableDevicePeerIds.difference(stableDevices);
    if (missingStableDevices.isNotEmpty) {
      failures.add(
        '$role: $proofName.stableDevicePeerIds missing '
        '${missingStableDevices.join(', ')}',
      );
    }
    if (charliePeerId != null && stableDevices.contains(charliePeerId)) {
      failures.add('$role: $proofName.stableDevicePeerIds must exclude flaky');
    }

    final syntheticStableMembers = _stringList(
      proof['syntheticStableMemberPeerIds'],
    );
    if (syntheticStableMembers.length !=
        syntheticStableMembers.toSet().length) {
      failures.add(
        '$role: $proofName.syntheticStableMemberPeerIds must not contain duplicates',
      );
    }
    final syntheticActualOverlap = syntheticStableMembers.toSet().intersection(
      actualPeerIds,
    );
    if (syntheticActualOverlap.isNotEmpty) {
      failures.add(
        '$role: $proofName.syntheticStableMemberPeerIds included actual peers',
      );
    }

    final finalMembers = _stringList(proof['finalMemberPeerIds']);
    if (finalMembers.isEmpty) {
      failures.add('$role: $proofName.finalMemberPeerIds is required');
    } else {
      if (finalMembers.length != finalMembers.toSet().length) {
        failures.add('$role: $proofName.finalMemberPeerIds has duplicates');
      }
      if (finalMembers.length < 10) {
        failures.add(
          '$role: GE-021 final roster must include >= 10 unique members',
        );
      }
      final missingActual = actualPeerIds.difference(finalMembers.toSet());
      if (missingActual.isNotEmpty) {
        failures.add(
          '$role: GE-021 final roster missing ${missingActual.join(', ')}',
        );
      }
      finalRosters.add(finalMembers.toSet());
    }

    final verdictMembers = _stringList(byRole[role]?['memberPeerIds']).toSet();
    final finalMemberSet = finalMembers.toSet();
    if (finalMembers.isNotEmpty &&
        (finalMemberSet.length != verdictMembers.length ||
            finalMemberSet.difference(verdictMembers).isNotEmpty ||
            verdictMembers.difference(finalMemberSet).isNotEmpty)) {
      failures.add(
        '$role: $proofName.finalMemberPeerIds must match verdict memberPeerIds',
      );
    }
  }

  if (finalRosters.length > 1) {
    final expectedRoster = finalRosters.first;
    final rostersDisagree = finalRosters
        .skip(1)
        .any(
          (roster) =>
              roster.length != expectedRoster.length ||
              roster.difference(expectedRoster).isNotEmpty ||
              expectedRoster.difference(roster).isNotEmpty,
        );
    if (rostersDisagree) {
      failures.add('alice/bob/charlie: GE-021 final roster mismatch');
    }
  }
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GE-021 finalEpoch mismatch');
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentActualDurablePayloadProof(
      role: 'alice',
      key: _ge021AliceInitialKey,
      byRole: byRole,
      failures: failures,
    );
    _requireSentActualDurablePayloadProof(
      role: 'bob',
      key: _ge021BobWhileFlakyKey,
      byRole: byRole,
      failures: failures,
    );
    _requireSentActualDurablePayloadProof(
      role: 'alice',
      key: _ge021AliceAfterOnlineKey,
      byRole: byRole,
      failures: failures,
    );
    _requireSentActualDurablePayloadProof(
      role: 'alice',
      key: _ge021AliceRemovedWindowKey,
      byRole: byRole,
      failures: failures,
    );
    _requireSentActualDurablePayloadProof(
      role: 'charlie',
      key: _ge021CharlieAfterReaddKey,
      byRole: byRole,
      failures: failures,
    );
    requireSentRecipientsInclude(
      role: 'alice',
      key: _ge021AliceInitialKey,
      requiredPeerIds: <String>{bobPeerId, charliePeerId},
      forbiddenPeerIds: <String>{alicePeerId},
    );
    requireSentRecipientsInclude(
      role: 'bob',
      key: _ge021BobWhileFlakyKey,
      requiredPeerIds: <String>{alicePeerId, charliePeerId},
      forbiddenPeerIds: <String>{bobPeerId},
    );
    requireSentRecipientsInclude(
      role: 'alice',
      key: _ge021AliceAfterOnlineKey,
      requiredPeerIds: <String>{bobPeerId, charliePeerId},
      forbiddenPeerIds: <String>{alicePeerId},
    );
    requireSentRecipientsInclude(
      role: 'alice',
      key: _ge021AliceRemovedWindowKey,
      requiredPeerIds: <String>{bobPeerId},
      forbiddenPeerIds: <String>{alicePeerId, charliePeerId},
    );
    requireSentRecipientsInclude(
      role: 'charlie',
      key: _ge021CharlieAfterReaddKey,
      requiredPeerIds: <String>{alicePeerId, bobPeerId},
      forbiddenPeerIds: <String>{charliePeerId},
    );
  }
}

void _validateGe023MediaReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge023MediaReaddProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final actualPeerIds = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};

  String? requireMediaEntry({
    required String role,
    required String key,
    required Map<String, dynamic>? entry,
    required String collection,
    String? expectedAttachmentId,
    bool requireSenderPayloadProof = false,
    bool requireLocalPath = false,
  }) {
    if (entry == null) return null;
    final mediaCount = _intValue(entry['mediaAttachmentCount']);
    final attachments = _mapList(entry['mediaAttachments']);
    if (mediaCount != 1 || attachments.length != 1) {
      failures.add(
        '$role: $collection $key must carry exactly one media attachment',
      );
      return null;
    }

    final attachment = attachments.single;
    final attachmentId = _stringValue(attachment['id']);
    if (attachmentId == null || attachmentId.isEmpty) {
      failures.add('$role: $collection $key media attachment missing id');
    } else if (expectedAttachmentId != null &&
        attachmentId != expectedAttachmentId) {
      failures.add('$role: $collection $key media attachment id mismatch');
    }
    if (_stringValue(attachment['contentHash']) != _ge023ContentHash) {
      failures.add('$role: $collection $key media contentHash mismatch');
    }
    if (attachment['hasEncryptionMetadata'] != true) {
      failures.add(
        '$role: $collection $key media must include encryption metadata',
      );
    }
    if (_stringValue(attachment['encryptionScheme']) != 'blob_aes_256_gcm_v1') {
      failures.add('$role: $collection $key media encryption scheme mismatch');
    }
    if (_stringValue(attachment['mime']) != 'image/jpeg') {
      failures.add('$role: $collection $key media mime mismatch');
    }
    if (_stringValue(attachment['mediaType']) != 'image') {
      failures.add('$role: $collection $key media type mismatch');
    }
    final size = _intValue(attachment['size']);
    if (size == null || size <= 0) {
      failures.add('$role: $collection $key media size must be positive');
    }
    if (requireLocalPath && attachment['localPathPresent'] != true) {
      failures.add('$role: $collection $key sender media missing local path');
    }

    final ids = _stringList(entry['mediaAttachmentIds']);
    if (attachmentId != null && !ids.contains(attachmentId)) {
      failures.add('$role: $collection $key mediaAttachmentIds missing id');
    }
    if (!_stringList(entry['mediaContentHashes']).contains(_ge023ContentHash)) {
      failures.add(
        '$role: $collection $key mediaContentHashes missing expected hash',
      );
    }
    if (requireSenderPayloadProof) {
      if (_intValue(entry['wireMediaCount']) != 1) {
        failures.add('$role: sent $key must include media in live payload');
      }
      if (_intValue(entry['durableMediaCount']) != 1) {
        failures.add('$role: sent $key must include media in durable payload');
      }
      if (entry['actualDurablePayloadProof'] != true) {
        failures.add('$role: sent $key must prove durable payload');
      }
    }
    return attachmentId;
  }

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing GE-023 media readd proof');
      continue;
    }
    for (final field in const <String>[
      'actualMediaPayloadProof',
      'renderReadyMetadataProof',
      'finalIncludesRemovedPeer',
      'removedWindowMediaInaccessible',
      'noRemovedWindowPlaintext',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    if (_stringValue(proof['contentHash']) != _ge023ContentHash) {
      failures.add('$role: $proofName.contentHash mismatch');
    }
    if (charliePeerId != null &&
        _stringValue(proof['removedPeerId']) != charliePeerId) {
      failures.add('$role: $proofName.removedPeerId must be Charlie');
    }
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'removedWindowAttachmentCount',
      expected: 0,
      failures: failures,
    );

    final finalMembers = _stringList(proof['finalMemberPeerIds']).toSet();
    final missingActual = actualPeerIds.difference(finalMembers);
    if (missingActual.isNotEmpty) {
      failures.add(
        '$role: $proofName.finalMemberPeerIds missing '
        '${missingActual.join(', ')}',
      );
    }
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: _ge023AliceBeforeRemovalKey,
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: _ge023AliceRemovedWindowKey,
      expectedPeerIds: <String>{bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: _ge023CharlieAfterReaddKey,
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }

  final beforeSent = _singleSentEntry(
    byRole['alice'],
    _ge023AliceBeforeRemovalKey,
    'alice',
    failures,
  );
  final removedSent = _singleSentEntry(
    byRole['alice'],
    _ge023AliceRemovedWindowKey,
    'alice',
    failures,
  );
  final afterSent = _singleSentEntry(
    byRole['charlie'],
    _ge023CharlieAfterReaddKey,
    'charlie',
    failures,
  );
  final beforeMediaId = requireMediaEntry(
    role: 'alice',
    key: _ge023AliceBeforeRemovalKey,
    entry: beforeSent,
    collection: 'sent',
    requireSenderPayloadProof: true,
    requireLocalPath: true,
  );
  final removedMediaId = requireMediaEntry(
    role: 'alice',
    key: _ge023AliceRemovedWindowKey,
    entry: removedSent,
    collection: 'sent',
    requireSenderPayloadProof: true,
    requireLocalPath: true,
  );
  final afterMediaId = requireMediaEntry(
    role: 'charlie',
    key: _ge023CharlieAfterReaddKey,
    entry: afterSent,
    collection: 'sent',
    requireSenderPayloadProof: true,
    requireLocalPath: true,
  );

  requireMediaEntry(
    role: 'bob',
    key: _ge023AliceBeforeRemovalKey,
    entry: _singleReceivedEntry(
      byRole['bob'],
      _ge023AliceBeforeRemovalKey,
      'bob',
      failures,
    ),
    collection: 'received',
    expectedAttachmentId: beforeMediaId,
  );
  requireMediaEntry(
    role: 'charlie',
    key: _ge023AliceBeforeRemovalKey,
    entry: _singleReceivedEntry(
      byRole['charlie'],
      _ge023AliceBeforeRemovalKey,
      'charlie',
      failures,
    ),
    collection: 'received',
    expectedAttachmentId: beforeMediaId,
  );
  requireMediaEntry(
    role: 'bob',
    key: _ge023AliceRemovedWindowKey,
    entry: _singleReceivedEntry(
      byRole['bob'],
      _ge023AliceRemovedWindowKey,
      'bob',
      failures,
    ),
    collection: 'received',
    expectedAttachmentId: removedMediaId,
  );
  requireMediaEntry(
    role: 'alice',
    key: _ge023CharlieAfterReaddKey,
    entry: _singleReceivedEntry(
      byRole['alice'],
      _ge023CharlieAfterReaddKey,
      'alice',
      failures,
    ),
    collection: 'received',
    expectedAttachmentId: afterMediaId,
  );
  requireMediaEntry(
    role: 'bob',
    key: _ge023CharlieAfterReaddKey,
    entry: _singleReceivedEntry(
      byRole['bob'],
      _ge023CharlieAfterReaddKey,
      'bob',
      failures,
    ),
    collection: 'received',
    expectedAttachmentId: afterMediaId,
  );

  final charlieRemovedWindow = _mapList(
    byRole['charlie']?['receivedMessages'],
  ).where((entry) => _stringValue(entry['key']) == _ge023AliceRemovedWindowKey);
  if (charlieRemovedWindow.isNotEmpty) {
    failures.add('charlie: removed-window media must not be received');
  }
}

void _validateGe024QuotedReplyProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge024QuotedReplyProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final actualPeerIds = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};

  void requireQuote({
    required String role,
    required String collection,
    required String key,
    required Map<String, dynamic>? entry,
    required String expectedQuotedMessageId,
  }) {
    if (entry == null) return;
    final quotedMessageId = _stringValue(entry['quotedMessageId']);
    if (quotedMessageId != expectedQuotedMessageId) {
      failures.add(
        '$role: $collection $key quotedMessageId must be '
        '$expectedQuotedMessageId',
      );
    }
  }

  final beforeParent = _singleSentEntry(
    byRole['alice'],
    _ge024AliceBeforeRemovalParentKey,
    'alice',
    failures,
  );
  final removedParent = _singleSentEntry(
    byRole['alice'],
    _ge024AliceRemovedWindowParentKey,
    'alice',
    failures,
  );
  final availableReply = _singleSentEntry(
    byRole['bob'],
    _ge024BobReplyAvailableKey,
    'bob',
    failures,
  );
  final unavailableReply = _singleSentEntry(
    byRole['bob'],
    _ge024BobReplyUnavailableKey,
    'bob',
    failures,
  );
  final beforeParentId = _stringValue(beforeParent?['messageId']);
  final removedParentId = _stringValue(removedParent?['messageId']);
  final availableReplyId = _stringValue(availableReply?['messageId']);
  final unavailableReplyId = _stringValue(unavailableReply?['messageId']);

  if (beforeParentId != null) {
    requireQuote(
      role: 'bob',
      collection: 'sent',
      key: _ge024BobReplyAvailableKey,
      entry: availableReply,
      expectedQuotedMessageId: beforeParentId,
    );
    requireQuote(
      role: 'alice',
      collection: 'received',
      key: _ge024BobReplyAvailableKey,
      entry: _singleReceivedEntry(
        byRole['alice'],
        _ge024BobReplyAvailableKey,
        'alice',
        failures,
      ),
      expectedQuotedMessageId: beforeParentId,
    );
    requireQuote(
      role: 'charlie',
      collection: 'received',
      key: _ge024BobReplyAvailableKey,
      entry: _singleReceivedEntry(
        byRole['charlie'],
        _ge024BobReplyAvailableKey,
        'charlie',
        failures,
      ),
      expectedQuotedMessageId: beforeParentId,
    );
  }

  if (removedParentId != null) {
    requireQuote(
      role: 'bob',
      collection: 'sent',
      key: _ge024BobReplyUnavailableKey,
      entry: unavailableReply,
      expectedQuotedMessageId: removedParentId,
    );
    requireQuote(
      role: 'alice',
      collection: 'received',
      key: _ge024BobReplyUnavailableKey,
      entry: _singleReceivedEntry(
        byRole['alice'],
        _ge024BobReplyUnavailableKey,
        'alice',
        failures,
      ),
      expectedQuotedMessageId: removedParentId,
    );
    requireQuote(
      role: 'charlie',
      collection: 'received',
      key: _ge024BobReplyUnavailableKey,
      entry: _singleReceivedEntry(
        byRole['charlie'],
        _ge024BobReplyUnavailableKey,
        'charlie',
        failures,
      ),
      expectedQuotedMessageId: removedParentId,
    );
  }

  final charlieRemovedParent = _mapList(byRole['charlie']?['receivedMessages'])
      .where(
        (entry) =>
            _stringValue(entry['key']) == _ge024AliceRemovedWindowParentKey,
      );
  if (charlieRemovedParent.isNotEmpty) {
    failures.add('charlie: removed-window quote parent must not be received');
  }

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing GE-024 quoted reply proof');
      continue;
    }
    for (final field in const <String>[
      'quotePropagationProof',
      'availableReplyHasExpectedQuote',
      'unavailableReplyHasExpectedQuote',
      'finalIncludesRemovedPeer',
      'noCrashRenderingUnavailableQuote',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    if (beforeParentId != null &&
        _stringValue(proof['availableParentMessageId']) != beforeParentId) {
      failures.add('$role: $proofName.availableParentMessageId mismatch');
    }
    if (removedParentId != null &&
        _stringValue(proof['removedWindowParentMessageId']) !=
            removedParentId) {
      failures.add('$role: $proofName.removedWindowParentMessageId mismatch');
    }
    if (availableReplyId != null &&
        _stringValue(proof['availableReplyMessageId']) != availableReplyId) {
      failures.add('$role: $proofName.availableReplyMessageId mismatch');
    }
    if (unavailableReplyId != null &&
        _stringValue(proof['unavailableReplyMessageId']) !=
            unavailableReplyId) {
      failures.add('$role: $proofName.unavailableReplyMessageId mismatch');
    }
    if (charliePeerId != null &&
        _stringValue(proof['removedPeerId']) != charliePeerId) {
      failures.add('$role: $proofName.removedPeerId must be Charlie');
    }
    final finalMembers = _stringList(proof['finalMemberPeerIds']).toSet();
    final missingActual = actualPeerIds.difference(finalMembers);
    if (missingActual.isNotEmpty) {
      failures.add(
        '$role: $proofName.finalMemberPeerIds missing '
        '${missingActual.join(', ')}',
      );
    }
  }

  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  if (charlieProof != null) {
    for (final field in const <String>[
      'availableParentPresent',
      'unavailableParentMissing',
      'noUnavailableParentPlaintext',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );
  }
}

void _validateGe002RemovalContinuityProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final aliceProof = _mapValue(byRole['alice']?['ge002RemovalContinuityProof']);
  final bobProof = _mapValue(byRole['bob']?['ge002RemovalContinuityProof']);
  final charlieProof = _mapValue(
    byRole['charlie']?['ge002RemovalContinuityProof'],
  );
  const expectedCount = 10;

  List<String> keysFor(Map<String, dynamic>? proof) =>
      _stringList(proof?['postRemovalMessageKeys']);

  if (aliceProof == null) {
    failures.add('alice: missing GE-002 removal continuity proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: 'ge002RemovalContinuityProof',
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'ge002RemovalContinuityProof',
      proof: aliceProof,
      field: 'actualDurablePayloadProof',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'ge002RemovalContinuityProof',
      proof: aliceProof,
      field: 'everyPostRemovalExcludedCharlie',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add(
        'alice: ge002RemovalContinuityProof.removedPeerId must be charlie',
      );
    }
    final count = _intValue(aliceProof['postRemovalMessageCount']);
    if (count != expectedCount) {
      failures.add(
        'alice: ge002RemovalContinuityProof.postRemovalMessageCount must be $expectedCount',
      );
    }
    if (keysFor(aliceProof).length != expectedCount) {
      failures.add(
        'alice: ge002RemovalContinuityProof.postRemovalMessageKeys must list $expectedCount keys',
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GE-002 removal continuity proof fields');
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: 'ge002RemovalContinuityProof',
      proof: bobProof,
      field: 'receivedEveryPostRemovalMessage',
      failures: failures,
    );
    final count = _intValue(bobProof['postRemovalReceiptCount']);
    if (count != expectedCount) {
      failures.add(
        'bob: ge002RemovalContinuityProof.postRemovalReceiptCount must be $expectedCount',
      );
    }
    if (keysFor(bobProof).length != expectedCount) {
      failures.add(
        'bob: ge002RemovalContinuityProof.postRemovalMessageKeys must list $expectedCount keys',
      );
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GE-002 removal continuity proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: 'ge002RemovalContinuityProof',
      proof: charlieProof,
      field: 'selfRemoved',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'ge002RemovalContinuityProof',
      proof: charlieProof,
      field: 'groupPresentAfterRemoval',
      failures: failures,
    );
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add(
        'charlie: ge002RemovalContinuityProof.postRemovalPlaintextCount must be 0',
      );
    }
    final checkedCount = _intValue(
      charlieProof['checkedPostRemovalMessageCount'],
    );
    if (checkedCount != expectedCount) {
      failures.add(
        'charlie: ge002RemovalContinuityProof.checkedPostRemovalMessageCount must be $expectedCount',
      );
    }
    if (keysFor(charlieProof).length != expectedCount) {
      failures.add(
        'charlie: ge002RemovalContinuityProof.postRemovalMessageKeys must list $expectedCount keys',
      );
    }
  }

  final aliceKeys = keysFor(aliceProof).toSet();
  final bobKeys = keysFor(bobProof).toSet();
  final charlieKeys = keysFor(charlieProof).toSet();
  if (aliceKeys.length == expectedCount &&
      bobKeys.length == expectedCount &&
      aliceKeys.difference(bobKeys).isNotEmpty) {
    failures.add('alice/bob: GE-002 post-removal key sets mismatch');
  }
  if (aliceKeys.length == expectedCount &&
      charlieKeys.length == expectedCount &&
      aliceKeys.difference(charlieKeys).isNotEmpty) {
    failures.add('alice/charlie: GE-002 checked key sets mismatch');
  }
}

void _validateGe003RemainingPairProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final aliceProof = _mapValue(byRole['alice']?['ge003RemainingPairProof']);
  final bobProof = _mapValue(byRole['bob']?['ge003RemainingPairProof']);
  final charlieProof = _mapValue(byRole['charlie']?['ge003RemainingPairProof']);
  const expectedCount = 10;

  List<String> keysFor(Map<String, dynamic>? proof) =>
      _stringList(proof?['postRemovalMessageKeys']);

  if (aliceProof == null) {
    failures.add('alice: missing GE-003 remaining pair proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: 'ge003RemainingPairProof',
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'ge003RemainingPairProof',
      proof: aliceProof,
      field: 'receivedEveryPostRemovalMessage',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add(
        'alice: ge003RemainingPairProof.removedPeerId must be charlie',
      );
    }
    final count = _intValue(aliceProof['postRemovalReceiptCount']);
    if (count != expectedCount) {
      failures.add(
        'alice: ge003RemainingPairProof.postRemovalReceiptCount must be $expectedCount',
      );
    }
    if (keysFor(aliceProof).length != expectedCount) {
      failures.add(
        'alice: ge003RemainingPairProof.postRemovalMessageKeys must list $expectedCount keys',
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GE-003 remaining pair proof fields');
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: 'ge003RemainingPairProof',
      proof: bobProof,
      field: 'actualDurablePayloadProof',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'ge003RemainingPairProof',
      proof: bobProof,
      field: 'everyPostRemovalExcludedCharlie',
      failures: failures,
    );
    final count = _intValue(bobProof['postRemovalMessageCount']);
    if (count != expectedCount) {
      failures.add(
        'bob: ge003RemainingPairProof.postRemovalMessageCount must be $expectedCount',
      );
    }
    if (keysFor(bobProof).length != expectedCount) {
      failures.add(
        'bob: ge003RemainingPairProof.postRemovalMessageKeys must list $expectedCount keys',
      );
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GE-003 remaining pair proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: 'ge003RemainingPairProof',
      proof: charlieProof,
      field: 'selfRemoved',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'ge003RemainingPairProof',
      proof: charlieProof,
      field: 'groupPresentAfterRemoval',
      failures: failures,
    );
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add(
        'charlie: ge003RemainingPairProof.postRemovalPlaintextCount must be 0',
      );
    }
    final checkedCount = _intValue(
      charlieProof['checkedPostRemovalMessageCount'],
    );
    if (checkedCount != expectedCount) {
      failures.add(
        'charlie: ge003RemainingPairProof.checkedPostRemovalMessageCount must be $expectedCount',
      );
    }
    if (keysFor(charlieProof).length != expectedCount) {
      failures.add(
        'charlie: ge003RemainingPairProof.postRemovalMessageKeys must list $expectedCount keys',
      );
    }
  }

  final aliceKeys = keysFor(aliceProof).toSet();
  final bobKeys = keysFor(bobProof).toSet();
  final charlieKeys = keysFor(charlieProof).toSet();
  if (aliceKeys.length == expectedCount &&
      bobKeys.length == expectedCount &&
      aliceKeys.difference(bobKeys).isNotEmpty) {
    failures.add('alice/bob: GE-003 post-removal key sets mismatch');
  }
  if (bobKeys.length == expectedCount &&
      charlieKeys.length == expectedCount &&
      bobKeys.difference(charlieKeys).isNotEmpty) {
    failures.add('bob/charlie: GE-003 checked key sets mismatch');
  }
}

void _validateGe004ReaddExchangeProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge004ReaddExchangeProof';
  const sentKeyByRole = <String, String>{
    'alice': 'aliceGe004PostReadd',
    'bob': 'bobGe004PostReadd',
    'charlie': 'charlieGe004PostReadd',
  };
  final expectedMembers = <String>{
    for (final role in const <String>['alice', 'bob', 'charlie'])
      if (peerIdByRole[role] != null) peerIdByRole[role]!,
  };
  final charliePeerId = peerIdByRole['charlie'];

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing GE-004 re-add exchange proof fields');
      continue;
    }

    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'readdedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'memberListIncludesAll',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'actualDurablePayloadProof',
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'postReaddSentCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'postReaddReceivedCount',
      expected: 2,
      failures: failures,
    );
    if (expectedMembers.length == 3) {
      _requireProofPeerSet(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'finalMemberPeerIds',
        expected: expectedMembers,
        failures: failures,
      );
    }

    final sentKey = sentKeyByRole[role]!;
    final sentKeys = _stringList(proof['postReaddSentKeys']).toSet();
    if (sentKeys.length != 1 || !sentKeys.contains(sentKey)) {
      failures.add('$role: $proofName.postReaddSentKeys must contain $sentKey');
    }
    final expectedReceivedKeys = sentKeyByRole.entries
        .where((entry) => entry.key != role)
        .map((entry) => entry.value)
        .toSet();
    final receivedKeys = _stringList(proof['postReaddReceivedKeys']).toSet();
    if (receivedKeys.length != expectedReceivedKeys.length ||
        receivedKeys.difference(expectedReceivedKeys).isNotEmpty ||
        expectedReceivedKeys.difference(receivedKeys).isNotEmpty) {
      failures.add(
        '$role: $proofName.postReaddReceivedKeys must contain '
        '${expectedReceivedKeys.join(', ')}',
      );
    }

    _requireSentActualDurablePayloadProof(
      role: role,
      key: sentKey,
      byRole: byRole,
      failures: failures,
    );
    final senderPeerId = peerIdByRole[role];
    if (senderPeerId != null && expectedMembers.length == 3) {
      _requireSentRecipientPeerIds(
        role: role,
        key: sentKey,
        expectedPeerIds: expectedMembers.difference(<String>{senderPeerId}),
        byRole: byRole,
        failures: failures,
      );
    }
  }

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  if (aliceProof != null) {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
    final readdedPeerId = _stringValue(aliceProof['readdedPeerId']);
    if (charliePeerId != null && readdedPeerId != charliePeerId) {
      failures.add('alice: $proofName.readdedPeerId must be charlie');
    }
  }
}

void _validateGe005RemoveReaddLoopProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge005RemoveReaddLoopProof';
  const cycleCount = 20;
  final expectedMembers = <String>{
    for (final role in const <String>['alice', 'bob', 'charlie'])
      if (peerIdByRole[role] != null) peerIdByRole[role]!,
  };
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final removedKeys = <String>[
    for (var cycle = 1; cycle <= cycleCount; cycle++) _ge005RemovedKey(cycle),
  ];
  final readdKeys = <String>[
    for (var cycle = 1; cycle <= cycleCount; cycle++) _ge005ReaddKey(cycle),
  ];

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing GE-005 remove/re-add loop proof fields');
      continue;
    }

    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'cycleCount',
      expected: cycleCount,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'completedCycleCount',
      expected: cycleCount,
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'finalMemberListIncludesAll',
      failures: failures,
    );
    if (expectedMembers.length == 3) {
      _requireProofPeerSet(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'finalMemberPeerIds',
        expected: expectedMembers,
        failures: failures,
      );
    }
  }

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  if (aliceProof != null) {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'actualDurablePayloadProof',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedWindowExcludedCharlie',
      failures: failures,
    );
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedWindowSentCount',
      expected: cycleCount,
      failures: failures,
    );
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'readdWindowReceivedCount',
      expected: cycleCount,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedWindowSentKeys',
      expected: removedKeys,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'readdWindowReceivedKeys',
      expected: readdKeys,
      failures: failures,
    );
  }

  final bobProof = _mapValue(byRole['bob']?[proofName]);
  if (bobProof != null) {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'actualDurablePayloadProof',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'readdWindowIncludedCharlie',
      failures: failures,
    );
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'removedWindowReceivedCount',
      expected: cycleCount,
      failures: failures,
    );
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'readdWindowSentCount',
      expected: cycleCount,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'removedWindowReceivedKeys',
      expected: removedKeys,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'readdWindowSentKeys',
      expected: readdKeys,
      failures: failures,
    );
  }

  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  if (charlieProof != null) {
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'readdWindowReceivedCount',
      expected: cycleCount,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'removedWindowReceivedKeys',
      expected: const <String>[],
      failures: failures,
    );
    _requireKeySetProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'readdWindowReceivedKeys',
      expected: readdKeys,
      failures: failures,
    );
  }

  if (bobPeerId != null) {
    for (final key in removedKeys) {
      _requireSentActualDurablePayloadProof(
        role: 'alice',
        key: key,
        byRole: byRole,
        failures: failures,
      );
      _requireSentRecipientPeerIds(
        role: 'alice',
        key: key,
        expectedPeerIds: <String>{bobPeerId},
        byRole: byRole,
        failures: failures,
      );
    }
  }
  if (alicePeerId != null && charliePeerId != null) {
    for (final key in readdKeys) {
      _requireSentActualDurablePayloadProof(
        role: 'bob',
        key: key,
        byRole: byRole,
        failures: failures,
      );
      _requireSentRecipientPeerIds(
        role: 'bob',
        key: key,
        expectedPeerIds: <String>{alicePeerId, charliePeerId},
        byRole: byRole,
        failures: failures,
      );
    }
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

void _validateGe006OfflineReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge006OfflineReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final charliePeerId = peerIdByRole['charlie'];

  if (aliceProof == null) {
    failures.add('alice: missing GE-006 offline re-add proof fields');
  } else {
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlie',
      'charlieOfflineDuringMutation',
      'removedWindowExcludedCharlie',
      'postReaddDurableIncludesCharlie',
      'receivedBobPostReaddMessage',
      'receivedCharliePostCatchUpMessage',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    if (charliePeerId != null &&
        _stringValue(aliceProof['removedPeerId']) != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GE-006 offline re-add proof fields');
  } else {
    for (final field in const <String>[
      'memberListIncludesCharlie',
      'receivedRemovedWindowMessage',
      'receivedAlicePostReaddMessage',
      'receivedCharliePostCatchUpMessage',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GE-006 offline re-add proof fields');
  } else {
    for (final field in const <String>[
      'offlineDuringRemovalAndReadd',
      'retrievedInboxAfterReconnect',
      'memberListIncludesAliceBob',
      'memberListIncludesCharlie',
      'postCatchUpPublishAccepted',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final removedPlaintext = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (removedPlaintext != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
    final postReaddCount = _intValue(charlieProof['postReaddReceivedCount']);
    if (postReaddCount != 2) {
      failures.add('charlie: $proofName.postReaddReceivedCount must be 2');
    }
    _requireKeySetProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postReaddReceivedKeys',
      expected: const <String>['aliceGe006PostReadd', 'bobGe006PostReadd'],
      failures: failures,
    );
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: $proofName.finalEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: $proofName.finalEpoch must be >= 2');
  }
  if (charlieEpoch == null || charlieEpoch < 2) {
    failures.add('charlie: $proofName.finalEpoch must be >= 2');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GE-006 finalEpoch mismatch');
  }
}

void _validateGe007OfflineObserverProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge007OfflineObserverProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final bobPeerId = peerIdByRole['bob'];

  if (aliceProof == null) {
    failures.add('alice: missing GE-007 offline observer proof fields');
  } else {
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlie',
      'bobOfflineDuringMutation',
      'removedWindowDurableIncludesBob',
      'postReaddDurableIncludesBob',
      'receivedCharliePostReaddMessage',
      'receivedBobPostCatchUpMessage',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    if (bobPeerId != null &&
        _stringValue(aliceProof['offlinePeerId']) != bobPeerId) {
      failures.add('alice: $proofName.offlinePeerId must be bob');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GE-007 offline observer proof fields');
  } else {
    for (final field in const <String>[
      'offlineDuringMutation',
      'retrievedInboxAfterReconnect',
      'memberListIncludesAliceCharlie',
      'memberListIncludesBob',
      'receivedRemovedWindowMessage',
      'receivedAlicePostReaddMessage',
      'receivedCharliePostReaddMessage',
      'postCatchUpPublishAccepted',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    final entitledCount = _intValue(bobProof['entitledReceivedCount']);
    if (entitledCount != 3) {
      failures.add('bob: $proofName.entitledReceivedCount must be 3');
    }
    _requireKeySetProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'entitledReceivedKeys',
      expected: const <String>[
        'aliceGe007RemovedWindow',
        'aliceGe007PostReadd',
        'charlieGe007PostReadd',
      ],
      failures: failures,
    );
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GE-007 offline observer proof fields');
  } else {
    for (final field in const <String>[
      'selfRemovedDuringMutation',
      'readdedCharlie',
      'memberListIncludesBob',
      'receivedAlicePostReaddMessage',
      'receivedBobPostCatchUpMessage',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 1) {
    failures.add('alice: $proofName.finalEpoch must be >= 1');
  }
  if (bobEpoch == null || bobEpoch < 1) {
    failures.add('bob: $proofName.finalEpoch must be >= 1');
  }
  if (charlieEpoch == null || charlieEpoch < 1) {
    failures.add('charlie: $proofName.finalEpoch must be >= 1');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GE-007 finalEpoch mismatch');
  }
}

void _validateGe008SendStormProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge008SendStormProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  if (aliceProof == null) {
    failures.add('alice: missing GE-008 send storm proof fields');
  } else {
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlie',
      'preStormComplete',
      'removedWindowComplete',
      'postReaddStormComplete',
      'charlieExcludedDuringRemovedWindow',
      'duplicateDeliveryDeduped',
      'receivedBobRemovedWindowMessages',
      'receivedCharliePostReaddMessages',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'preStormSentCount',
      expected: 2,
      failures: failures,
    );
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedWindowSentCount',
      expected: 2,
      failures: failures,
    );
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'postReaddSentCount',
      expected: 2,
      failures: failures,
    );
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'preStormReceivedCount',
      expected: 4,
      failures: failures,
    );
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedWindowReceivedCount',
      expected: 2,
      failures: failures,
    );
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'postReaddReceivedCount',
      expected: 4,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedPreStormKeys',
      expected: const <String>[..._ge008BobPreKeys, ..._ge008CharliePreKeys],
      failures: failures,
    );
    _requireKeySetProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedRemovedWindowKeys',
      expected: _ge008BobRemovedKeys,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedPostReaddKeys',
      expected: const <String>[..._ge008BobPostKeys, ..._ge008CharliePostKeys],
      failures: failures,
    );
    if (charliePeerId != null &&
        _stringValue(aliceProof['removedPeerId']) != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GE-008 send storm proof fields');
  } else {
    for (final field in const <String>[
      'preStormComplete',
      'removedWindowComplete',
      'postReaddStormComplete',
      'memberListExcludesCharlieDuringRemovedWindow',
      'memberListIncludesAliceCharlie',
      'duplicateDeliveryDeduped',
      'receivedAliceRemovedWindowMessages',
      'receivedCharliePostReaddMessages',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'preStormSentCount',
      expected: 2,
      failures: failures,
    );
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'removedWindowSentCount',
      expected: 2,
      failures: failures,
    );
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'postReaddSentCount',
      expected: 2,
      failures: failures,
    );
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'preStormReceivedCount',
      expected: 4,
      failures: failures,
    );
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'removedWindowReceivedCount',
      expected: 2,
      failures: failures,
    );
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'postReaddReceivedCount',
      expected: 4,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedPreStormKeys',
      expected: const <String>[..._ge008AlicePreKeys, ..._ge008CharliePreKeys],
      failures: failures,
    );
    _requireKeySetProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedRemovedWindowKeys',
      expected: _ge008AliceRemovedKeys,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedPostReaddKeys',
      expected: const <String>[
        ..._ge008AlicePostKeys,
        ..._ge008CharliePostKeys,
      ],
      failures: failures,
    );
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GE-008 send storm proof fields');
  } else {
    for (final field in const <String>[
      'selfRemovedDuringStorm',
      'staleRemovedWindowSendsRejected',
      'readdedCharlie',
      'preStormComplete',
      'postReaddStormComplete',
      'duplicateDeliveryDeduped',
      'receivedPostReaddStormMessages',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'preStormSentCount',
      expected: 2,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postReaddSentCount',
      expected: 2,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'preStormReceivedCount',
      expected: 4,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postReaddReceivedCount',
      expected: 4,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'staleRemovedWindowAttemptCount',
      expected: 2,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'staleRemovedWindowAcceptedCount',
      expected: 0,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'staleRemovedWindowPublishCount',
      expected: 0,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedPreStormKeys',
      expected: const <String>[..._ge008AlicePreKeys, ..._ge008BobPreKeys],
      failures: failures,
    );
    _requireKeySetProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedPostReaddKeys',
      expected: const <String>[..._ge008AlicePostKeys, ..._ge008BobPostKeys],
      failures: failures,
    );
    _requireKeySetProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'rejectedRemovedWindowKeys',
      expected: const <String>[
        'charlieGe008RemovedStale0',
        'charlieGe008RemovedStale1',
      ],
      failures: failures,
    );
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 1) {
    failures.add('alice: $proofName.finalEpoch must be >= 1');
  }
  if (bobEpoch == null || bobEpoch < 1) {
    failures.add('bob: $proofName.finalEpoch must be >= 1');
  }
  if (charlieEpoch == null || charlieEpoch < 1) {
    failures.add('charlie: $proofName.finalEpoch must be >= 1');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GE-008 finalEpoch mismatch');
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    for (final key in <String>[..._ge008AlicePreKeys, ..._ge008AlicePostKeys]) {
      _requireSentRecipientPeerIds(
        role: 'alice',
        key: key,
        expectedPeerIds: <String>{bobPeerId, charliePeerId},
        byRole: byRole,
        failures: failures,
      );
    }
    for (final key in _ge008AliceRemovedKeys) {
      _requireSentRecipientPeerIds(
        role: 'alice',
        key: key,
        expectedPeerIds: <String>{bobPeerId},
        byRole: byRole,
        failures: failures,
      );
    }
    for (final key in <String>[..._ge008BobPreKeys, ..._ge008BobPostKeys]) {
      _requireSentRecipientPeerIds(
        role: 'bob',
        key: key,
        expectedPeerIds: <String>{alicePeerId, charliePeerId},
        byRole: byRole,
        failures: failures,
      );
    }
    for (final key in _ge008BobRemovedKeys) {
      _requireSentRecipientPeerIds(
        role: 'bob',
        key: key,
        expectedPeerIds: <String>{alicePeerId},
        byRole: byRole,
        failures: failures,
      );
    }
    for (final key in <String>[
      ..._ge008CharliePreKeys,
      ..._ge008CharliePostKeys,
    ]) {
      _requireSentRecipientPeerIds(
        role: 'charlie',
        key: key,
        expectedPeerIds: <String>{alicePeerId, bobPeerId},
        byRole: byRole,
        failures: failures,
      );
    }
  }

  for (final entry in const <String, List<String>>{
    'alice': <String>[
      ..._ge008AlicePreKeys,
      ..._ge008AliceRemovedKeys,
      ..._ge008AlicePostKeys,
    ],
    'bob': <String>[
      ..._ge008BobPreKeys,
      ..._ge008BobRemovedKeys,
      ..._ge008BobPostKeys,
    ],
    'charlie': <String>[..._ge008CharliePreKeys, ..._ge008CharliePostKeys],
  }.entries) {
    for (final key in entry.value) {
      _requireSentActualDurablePayloadProof(
        role: entry.key,
        key: key,
        byRole: byRole,
        failures: failures,
      );
    }
  }
}

void _validateGe009PartitionHealProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge009PartitionHealProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  void requireCommonProof(String role, Map<String, dynamic>? proof) {
    if (proof == null) {
      failures.add('$role: missing GE-009 partition-heal proof fields');
      return;
    }
    for (final field in const <String>[
      'partitionedDuringMembershipMutation',
      'removedAndReaddedCharlie',
      'partitionHealed',
      'finalMembershipConverged',
      'finalTimelineConverged',
      'duplicateDeliveryDeduped',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'finalMessageCount',
      expected: _ge009FinalKeys.length,
      failures: failures,
    );
    _requireKeySetProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'finalTimelineKeys',
      expected: _ge009FinalKeys,
      failures: failures,
    );
    if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
      _requireProofPeerSet(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'finalMemberPeerIds',
        expected: <String>{alicePeerId, bobPeerId, charliePeerId},
        failures: failures,
      );
    }
  }

  requireCommonProof('alice', aliceProof);
  requireCommonProof('bob', bobProof);
  requireCommonProof('charlie', charlieProof);

  if (aliceProof != null) {
    for (final field in const <String>[
      'charlieExcludedDuringPartition',
      'postReaddDurableIncludedCharlie',
      'receivedBobPostReaddReplay',
      'receivedCharlieAfterHeal',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    _requireKeySetProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedPrePartitionKeys',
      expected: const <String>[
        'bobGe009BeforePartition',
        'charlieGe009BeforePartition',
      ],
      failures: failures,
    );
    _requireKeySetProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedPostHealKeys',
      expected: const <String>['bobGe009PostReadd', 'charlieGe009AfterHeal'],
      failures: failures,
    );
  }

  if (bobProof != null) {
    for (final field in const <String>[
      'charlieExcludedDuringPartition',
      'postReaddDurableIncludedCharlie',
      'receivedAlicePostReaddReplay',
      'receivedCharlieAfterHeal',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    _requireKeySetProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedPrePartitionKeys',
      expected: const <String>[
        'aliceGe009BeforePartition',
        'charlieGe009BeforePartition',
      ],
      failures: failures,
    );
    _requireKeySetProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedPostHealKeys',
      expected: const <String>['aliceGe009PostReadd', 'charlieGe009AfterHeal'],
      failures: failures,
    );
  }

  if (charlieProof != null) {
    for (final field in const <String>[
      'isolatedFromLiveTopicDuringMutation',
      'drainedReplayAfterHeal',
      'receivedAliceBobReplayAfterHeal',
      'postHealPublishAccepted',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedPrePartitionKeys',
      expected: const <String>[
        'aliceGe009BeforePartition',
        'bobGe009BeforePartition',
      ],
      failures: failures,
    );
    _requireKeySetProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postReaddReplayKeys',
      expected: _ge009ReplayKeys,
      failures: failures,
    );
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 1) {
    failures.add('alice: $proofName.finalEpoch must be >= 1');
  }
  if (bobEpoch == null || bobEpoch < 1) {
    failures.add('bob: $proofName.finalEpoch must be >= 1');
  }
  if (charlieEpoch == null || charlieEpoch < 1) {
    failures.add('charlie: $proofName.finalEpoch must be >= 1');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GE-009 finalEpoch mismatch');
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    for (final key in const <String>[
      'aliceGe009BeforePartition',
      'aliceGe009PostReadd',
    ]) {
      _requireSentRecipientPeerIds(
        role: 'alice',
        key: key,
        expectedPeerIds: <String>{bobPeerId, charliePeerId},
        byRole: byRole,
        failures: failures,
      );
    }
    for (final key in const <String>[
      'bobGe009BeforePartition',
      'bobGe009PostReadd',
    ]) {
      _requireSentRecipientPeerIds(
        role: 'bob',
        key: key,
        expectedPeerIds: <String>{alicePeerId, charliePeerId},
        byRole: byRole,
        failures: failures,
      );
    }
    for (final key in const <String>[
      'charlieGe009BeforePartition',
      'charlieGe009AfterHeal',
    ]) {
      _requireSentRecipientPeerIds(
        role: 'charlie',
        key: key,
        expectedPeerIds: <String>{alicePeerId, bobPeerId},
        byRole: byRole,
        failures: failures,
      );
    }
  }

  for (final entry in const <String, List<String>>{
    'alice': <String>['aliceGe009BeforePartition', 'aliceGe009PostReadd'],
    'bob': <String>['bobGe009BeforePartition', 'bobGe009PostReadd'],
    'charlie': <String>['charlieGe009BeforePartition', 'charlieGe009AfterHeal'],
  }.entries) {
    for (final key in entry.value) {
      _requireSentActualDurablePayloadProof(
        role: entry.key,
        key: key,
        byRole: byRole,
        failures: failures,
      );
    }
  }
}

void _validateGe010ZeroLivePeersInboxFallbackProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge010ZeroLivePeersInboxFallbackProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMemberPeers =
      alicePeerId == null || bobPeerId == null || charliePeerId == null
      ? null
      : <String>{alicePeerId, bobPeerId, charliePeerId};

  if (aliceProof == null) {
    failures.add('alice: missing GE-010 zero-live-peer fallback proof fields');
  } else {
    for (final field in const <String>[
      'bobLeftLiveTopicBeforeSend',
      'charlieLeftLiveTopicBeforeSend',
      'zeroLiveTopicPeersAtSend',
      'successNoPeers',
      'senderStatusSent',
      'inboxStored',
      'actualDurablePayloadProof',
      'honestSenderFallbackStatus',
      'noLiveDeliveryDuringSendWindow',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'topicPeersAtSend',
      expected: 0,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'sentKeys',
      expected: const <String>[_ge010ZeroPeerKey],
      failures: failures,
    );
    if (expectedMemberPeers != null) {
      _requireProofPeerSet(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: 'finalMemberPeerIds',
        expected: expectedMemberPeers,
        failures: failures,
      );
    }
  }

  void requireReceiverProof({
    required String role,
    required Map<String, dynamic>? proof,
  }) {
    if (proof == null) {
      failures.add(
        '$role: missing GE-010 zero-live-peer fallback proof fields',
      );
      return;
    }
    for (final field in const <String>[
      'leftLiveTopicBeforeSend',
      'rejoinedLiveTopicAfterSend',
      'drainedInboxAfterReturn',
      'receivedZeroPeerMessage',
      'noDuplicatePersistence',
      'noLiveDeliveryDuringSendWindow',
      'senderEligibleAtSend',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'postDrainPersistedCount',
      expected: 1,
      failures: failures,
    );
    _requireKeySetProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'receivedKeys',
      expected: const <String>[_ge010ZeroPeerKey],
      failures: failures,
    );
    if (expectedMemberPeers != null) {
      _requireProofPeerSet(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'finalMemberPeerIds',
        expected: expectedMemberPeers,
        failures: failures,
      );
    }
  }

  requireReceiverProof(role: 'bob', proof: bobProof);
  requireReceiverProof(role: 'charlie', proof: charlieProof);

  final aliceEpoch = _intValue(aliceProof?['finalKeyEpoch']);
  final bobEpoch = _intValue(bobProof?['finalKeyEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalKeyEpoch']);
  if (aliceEpoch == null || aliceEpoch < 1) {
    failures.add('alice: $proofName.finalKeyEpoch must be >= 1');
  }
  if (bobEpoch == null || bobEpoch < 1) {
    failures.add('bob: $proofName.finalKeyEpoch must be >= 1');
  }
  if (charlieEpoch == null || charlieEpoch < 1) {
    failures.add('charlie: $proofName.finalKeyEpoch must be >= 1');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GE-010 finalKeyEpoch mismatch');
  }

  final aliceVerdict = byRole['alice'];
  final sentEntries = aliceVerdict == null
      ? const <Map<String, dynamic>>[]
      : _mapList(aliceVerdict['sentMessages'])
            .where((entry) => _stringValue(entry['key']) == _ge010ZeroPeerKey)
            .toList(growable: false);
  if (sentEntries.length == 1) {
    final sent = sentEntries.single;
    if (_stringValue(sent['outcome']) != 'successNoPeers') {
      failures.add(
        'alice: sent $_ge010ZeroPeerKey outcome must be successNoPeers',
      );
    }
    if (_intValue(sent['topicPeers']) != 0) {
      failures.add('alice: sent $_ge010ZeroPeerKey topicPeers must be 0');
    }
    if (sent['actualTopicPeerProof'] != true) {
      failures.add(
        'alice: sent $_ge010ZeroPeerKey must report actual topic peer proof',
      );
    }
  }

  if (bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: _ge010ZeroPeerKey,
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  _requireSentActualDurablePayloadProof(
    role: 'alice',
    key: _ge010ZeroPeerKey,
    byRole: byRole,
    failures: failures,
  );
}

void _validateGo002InboxStoreFailureSenderStatusProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'go002InboxStoreFailureSenderStatusProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMemberPeers =
      alicePeerId == null || bobPeerId == null || charliePeerId == null
      ? null
      : <String>{alicePeerId, bobPeerId, charliePeerId};
  final expectedRecipients = <String>{?bobPeerId, ?charliePeerId};

  if (aliceProof == null) {
    failures.add('alice: missing GO-002 inbox failure proof fields');
  } else {
    for (final field in const <String>[
      'publishSucceeded',
      'actualTopicPeerProof',
      'topicPeersPositive',
      'forcedInboxStoreFailure',
      'senderStatusPendingBeforeRetry',
      'inboxStoredFalseBeforeRetry',
      'retryPayloadPresentBeforeRetry',
      'notSilentlyReliableBeforeRetry',
      'retryRanOnce',
      'retryPromotedToSent',
      'inboxStoredTrueAfterRetry',
      'retryPayloadClearedAfterRetry',
      'actualDurablePayloadProof',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntAtLeastProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'topicPeersAtSend',
      minimum: 1,
      failures: failures,
    );
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'retryCount',
      expected: 1,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'sentKeys',
      expected: const <String>[_go002InboxFailureKey],
      failures: failures,
    );
    if (expectedRecipients.length == 2) {
      _requireProofPeerSet(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: 'recipientPeerIds',
        expected: expectedRecipients,
        failures: failures,
      );
      _requireProofPeerSet(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: 'failedInboxRecipientPeerIds',
        expected: expectedRecipients,
        failures: failures,
      );
    }
    if (expectedMemberPeers != null) {
      _requireProofPeerSet(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: 'finalMemberPeerIds',
        expected: expectedMemberPeers,
        failures: failures,
      );
    }
  }

  void requireReceiverProof({
    required String role,
    required Map<String, dynamic>? proof,
  }) {
    if (proof == null) {
      failures.add('$role: missing GO-002 inbox failure proof fields');
      return;
    }
    for (final field in const <String>[
      'receivedLivePublish',
      'noDuplicatePersistence',
      'senderEligibleAtSend',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'postRetryPersistedCount',
      expected: 1,
      failures: failures,
    );
    _requireKeySetProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'receivedKeys',
      expected: const <String>[_go002InboxFailureKey],
      failures: failures,
    );
    if (expectedMemberPeers != null) {
      _requireProofPeerSet(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'finalMemberPeerIds',
        expected: expectedMemberPeers,
        failures: failures,
      );
    }
  }

  requireReceiverProof(role: 'bob', proof: bobProof);
  requireReceiverProof(role: 'charlie', proof: charlieProof);

  final aliceVerdict = byRole['alice'];
  final sentEntries = aliceVerdict == null
      ? const <Map<String, dynamic>>[]
      : _mapList(aliceVerdict['sentMessages'])
            .where(
              (entry) => _stringValue(entry['key']) == _go002InboxFailureKey,
            )
            .toList(growable: false);
  if (sentEntries.length == 1) {
    final sent = sentEntries.single;
    if (_stringValue(sent['outcome']) != 'success') {
      failures.add(
        'alice: sent $_go002InboxFailureKey outcome must be success',
      );
    }
    if (_stringValue(sent['senderStatusBeforeRetry']) != 'pending') {
      failures.add(
        'alice: sent $_go002InboxFailureKey senderStatusBeforeRetry '
        'must be pending',
      );
    }
    if (sent['inboxStoredBeforeRetry'] != false) {
      failures.add(
        'alice: sent $_go002InboxFailureKey inboxStoredBeforeRetry '
        'must be false',
      );
    }
    if (sent['retryPayloadBeforeRetry'] != true) {
      failures.add(
        'alice: sent $_go002InboxFailureKey retryPayloadBeforeRetry '
        'must be true',
      );
    }
    if (_stringValue(sent['senderStatusAfterRetry']) != 'sent') {
      failures.add(
        'alice: sent $_go002InboxFailureKey senderStatusAfterRetry '
        'must be sent',
      );
    }
    if (sent['inboxStoredAfterRetry'] != true) {
      failures.add(
        'alice: sent $_go002InboxFailureKey inboxStoredAfterRetry '
        'must be true',
      );
    }
    if (sent['retryPayloadAfterRetry'] != false) {
      failures.add(
        'alice: sent $_go002InboxFailureKey retryPayloadAfterRetry '
        'must be false',
      );
    }
    if (_intValue(sent['topicPeers']) == null ||
        _intValue(sent['topicPeers'])! < 1) {
      failures.add(
        'alice: sent $_go002InboxFailureKey topicPeers must be >= 1',
      );
    }
  }

  if (bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: _go002InboxFailureKey,
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  _requireSentActualDurablePayloadProof(
    role: 'alice',
    key: _go002InboxFailureKey,
    byRole: byRole,
    failures: failures,
  );
}

void _validateGe011PartialLivePeersInboxFallbackProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ge011PartialLivePeersInboxFallbackProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMemberPeers =
      alicePeerId == null || bobPeerId == null || charliePeerId == null
      ? null
      : <String>{alicePeerId, bobPeerId, charliePeerId};

  if (aliceProof == null) {
    failures.add('alice: missing GE-011 partial-live fallback proof fields');
  } else {
    for (final field in const <String>[
      'bobLiveTopicPeerAtSend',
      'charlieLeftLiveTopicBeforeSend',
      'partialLiveTopicPeersAtSend',
      'liveDeliveryToBobDuringSendWindow',
      'noLiveDeliveryToCharlieDuringSendWindow',
      'senderStatusSent',
      'inboxStored',
      'actualDurablePayloadProof',
      'honestPartialFallbackStatus',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'topicPeersAtSend',
      expected: 1,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'sentKeys',
      expected: const <String>[_ge011PartialLiveKey],
      failures: failures,
    );
    if (expectedMemberPeers != null) {
      _requireProofPeerSet(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: 'finalMemberPeerIds',
        expected: expectedMemberPeers,
        failures: failures,
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GE-011 partial-live fallback proof fields');
  } else {
    for (final field in const <String>[
      'liveTopicPeerAtSend',
      'receivedLiveDuringSendWindow',
      'drainedDuplicateInboxAfterLive',
      'noDuplicatePersistence',
      'senderEligibleAtSend',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'postDrainPersistedCount',
      expected: 1,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedKeys',
      expected: const <String>[_ge011PartialLiveKey],
      failures: failures,
    );
    if (expectedMemberPeers != null) {
      _requireProofPeerSet(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: 'finalMemberPeerIds',
        expected: expectedMemberPeers,
        failures: failures,
      );
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GE-011 partial-live fallback proof fields');
  } else {
    for (final field in const <String>[
      'leftLiveTopicBeforeSend',
      'rejoinedLiveTopicAfterSend',
      'drainedInboxAfterReturn',
      'receivedInboxMessage',
      'noLiveDeliveryDuringSendWindow',
      'noDuplicatePersistence',
      'senderEligibleAtSend',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postDrainPersistedCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'preRejoinPlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireKeySetProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedKeys',
      expected: const <String>[_ge011PartialLiveKey],
      failures: failures,
    );
    if (expectedMemberPeers != null) {
      _requireProofPeerSet(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: 'finalMemberPeerIds',
        expected: expectedMemberPeers,
        failures: failures,
      );
    }
  }

  final aliceEpoch = _intValue(aliceProof?['finalKeyEpoch']);
  final bobEpoch = _intValue(bobProof?['finalKeyEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalKeyEpoch']);
  if (aliceEpoch == null || aliceEpoch < 1) {
    failures.add('alice: $proofName.finalKeyEpoch must be >= 1');
  }
  if (bobEpoch == null || bobEpoch < 1) {
    failures.add('bob: $proofName.finalKeyEpoch must be >= 1');
  }
  if (charlieEpoch == null || charlieEpoch < 1) {
    failures.add('charlie: $proofName.finalKeyEpoch must be >= 1');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GE-011 finalKeyEpoch mismatch');
  }

  final aliceVerdict = byRole['alice'];
  final sentEntries = aliceVerdict == null
      ? const <Map<String, dynamic>>[]
      : _mapList(aliceVerdict['sentMessages'])
            .where(
              (entry) => _stringValue(entry['key']) == _ge011PartialLiveKey,
            )
            .toList(growable: false);
  if (sentEntries.length == 1) {
    final sent = sentEntries.single;
    if (_stringValue(sent['outcome']) != 'success') {
      failures.add('alice: sent $_ge011PartialLiveKey outcome must be success');
    }
    if (_intValue(sent['topicPeers']) != 1) {
      failures.add('alice: sent $_ge011PartialLiveKey topicPeers must be 1');
    }
    if (sent['actualTopicPeerProof'] != true) {
      failures.add(
        'alice: sent $_ge011PartialLiveKey must report actual topic peer proof',
      );
    }
  }

  if (bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: _ge011PartialLiveKey,
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  _requireSentActualDurablePayloadProof(
    role: 'alice',
    key: _ge011PartialLiveKey,
    byRole: byRole,
    failures: failures,
  );
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

void _validateGm008RestartReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final aliceProof = _mapValue(byRole['alice']?['gm008RestartReaddProof']);
  final bobProof = _mapValue(byRole['bob']?['gm008RestartReaddProof']);
  final charlieProof = _mapValue(byRole['charlie']?['gm008RestartReaddProof']);

  if (aliceProof == null) {
    failures.add('alice: missing GM-008 restart re-add proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm008RestartReaddProof',
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm008RestartReaddProof',
      proof: aliceProof,
      field: 'charlieRestartedBeforeReadd',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm008RestartReaddProof',
      proof: aliceProof,
      field: 'distributedCurrentEpochToRemainingOnly',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm008RestartReaddProof',
      proof: aliceProof,
      field: 'sentRemovedWindowAfterRestartBeforeReadd',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm008RestartReaddProof',
      proof: aliceProof,
      field: 'readdedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm008RestartReaddProof',
      proof: aliceProof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm008RestartReaddProof',
      proof: aliceProof,
      field: 'receivedCharliePostReaddMessage',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add(
        'alice: gm008RestartReaddProof.removedPeerId must be charlie',
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GM-008 restart re-add proof fields');
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm008RestartReaddProof',
      proof: bobProof,
      field: 'observedCharlieRestartBoundary',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm008RestartReaddProof',
      proof: bobProof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm008RestartReaddProof',
      proof: bobProof,
      field: 'receivedRemovedWindowMessage',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm008RestartReaddProof',
      proof: bobProof,
      field: 'receivedCharliePostReaddMessage',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm008RestartReaddProof',
      proof: bobProof,
      field: 'receivedAlicePostReaddMessage',
      failures: failures,
    );
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GM-008 restart re-add proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm008RestartReaddProof',
      proof: charlieProof,
      field: 'runtimeRestartedAfterRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm008RestartReaddProof',
      proof: charlieProof,
      field: 'preReaddSendRejected',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm008RestartReaddProof',
      proof: charlieProof,
      field: 'rejoinedFromCurrentPersistedEpoch',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm008RestartReaddProof',
      proof: charlieProof,
      field: 'memberListIncludesAliceBob',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm008RestartReaddProof',
      proof: charlieProof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm008RestartReaddProof',
      proof: charlieProof,
      field: 'hasStaleEpochAfterRestartReadd',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm008RestartReaddProof',
      proof: charlieProof,
      field: 'postReaddPublishAccepted',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm008RestartReaddProof',
      proof: charlieProof,
      field: 'receivedAlicePostReaddMessage',
      failures: failures,
    );
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add(
        'charlie: gm008RestartReaddProof.removedWindowPlaintextCount must be 0',
      );
    }
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: gm008RestartReaddProof.finalEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: gm008RestartReaddProof.finalEpoch must be >= 2');
  }
  if (charlieEpoch == null || charlieEpoch < 2) {
    failures.add('charlie: gm008RestartReaddProof.finalEpoch must be >= 2');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GM-008 finalEpoch mismatch');
  }
}

void _validateGm009DuplicateRemovalProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final aliceProof = _mapValue(byRole['alice']?['gm009DuplicateRemovalProof']);
  final bobProof = _mapValue(byRole['bob']?['gm009DuplicateRemovalProof']);
  final charlieProof = _mapValue(
    byRole['charlie']?['gm009DuplicateRemovalProof'],
  );

  if (aliceProof == null) {
    failures.add('alice: missing GM-009 duplicate removal proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm009DuplicateRemovalProof',
      proof: aliceProof,
      field: 'removedCharlieOnce',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm009DuplicateRemovalProof',
      proof: aliceProof,
      field: 'duplicateRemoveIgnored',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: 'gm009DuplicateRemovalProof',
      proof: aliceProof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    _requireFalseProof(
      role: 'alice',
      proofName: 'gm009DuplicateRemovalProof',
      proof: aliceProof,
      field: 'distributedKeyToCharlie',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add(
        'alice: gm009DuplicateRemovalProof.removedPeerId must be charlie',
      );
    }
    final timelineCount = _intValue(aliceProof['removalTimelineCount']);
    if (timelineCount != 1) {
      failures.add(
        'alice: gm009DuplicateRemovalProof.removalTimelineCount must be 1',
      );
    }
    final rotationCount = _intValue(aliceProof['rotationCount']);
    if (rotationCount != 1) {
      failures.add('alice: gm009DuplicateRemovalProof.rotationCount must be 1');
    }
    final distributionCount = _intValue(aliceProof['keyDistributionCount']);
    if (distributionCount != 1) {
      failures.add(
        'alice: gm009DuplicateRemovalProof.keyDistributionCount must be 1',
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GM-009 duplicate removal proof fields');
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm009DuplicateRemovalProof',
      proof: bobProof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm009DuplicateRemovalProof',
      proof: bobProof,
      field: 'receivedAlicePostDuplicateRemove',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: 'gm009DuplicateRemovalProof',
      proof: bobProof,
      field: 'sentBobPostDuplicateRemove',
      failures: failures,
    );
    final timelineCount = _intValue(bobProof['removalTimelineCount']);
    if (timelineCount != 1) {
      failures.add(
        'bob: gm009DuplicateRemovalProof.removalTimelineCount must be 1',
      );
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GM-009 duplicate removal proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: 'gm009DuplicateRemovalProof',
      proof: charlieProof,
      field: 'currentMemberBeforeRemoval',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm009DuplicateRemovalProof',
      proof: charlieProof,
      field: 'groupPresentAfterDuplicateRemoval',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm009DuplicateRemovalProof',
      proof: charlieProof,
      field: 'hasRotatedEpoch',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm009DuplicateRemovalProof',
      proof: charlieProof,
      field: 'postRemovalPublishAccepted',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm009DuplicateRemovalProof',
      proof: charlieProof,
      field: 'receivedAlicePostDuplicateRemove',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: 'gm009DuplicateRemovalProof',
      proof: charlieProof,
      field: 'receivedBobPostDuplicateRemove',
      failures: failures,
    );
    final sendOutcome = _stringValue(charlieProof['postRemovalSendOutcome']);
    if (sendOutcome != 'groupNotFound' && sendOutcome != 'unauthorized') {
      failures.add(
        'charlie: gm009DuplicateRemovalProof.postRemovalSendOutcome must reject send',
      );
    }
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add(
        'charlie: gm009DuplicateRemovalProof.postRemovalPlaintextCount must be 0',
      );
    }
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: gm009DuplicateRemovalProof.finalEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: gm009DuplicateRemovalProof.finalEpoch must be >= 2');
  }
  if (charlieEpoch != null &&
      aliceEpoch != null &&
      charlieEpoch >= aliceEpoch) {
    failures.add(
      'charlie: gm009DuplicateRemovalProof must not hold final epoch',
    );
  }
  if (aliceEpoch != null && bobEpoch != null && aliceEpoch != bobEpoch) {
    failures.add('alice/bob: GM-009 finalEpoch mismatch');
  }
}

void _validateGm010DuplicateReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm010DuplicateReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final charliePeerId = peerIdByRole['charlie'];

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final verdict = byRole[role];
    if (verdict == null || charliePeerId == null) continue;
    final charlieRows = _stringList(
      verdict['memberPeerIds'],
    ).where((peerId) => peerId == charliePeerId).length;
    if (charlieRows != 1) {
      failures.add(
        '$role: GM-010 final memberPeerIds must contain Charlie exactly once',
      );
    }
  }

  void validateSharedProof(String role, Map<String, dynamic>? proof) {
    if (proof == null) {
      failures.add('$role: missing GM-010 duplicate re-add proof fields');
      return;
    }
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'charlieMemberRowCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'charlieActiveDeviceBindingCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'charlieGroupConfigJoinCountAfterReadd',
      expected: 1,
      failures: failures,
    );
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'duplicateReaddTriggeredCharlieGroupConfigJoin',
      failures: failures,
    );
    final measurementSource = _stringValue(
      proof['charlieJoinMeasurementSource'],
    );
    if (measurementSource == null || measurementSource.isEmpty) {
      failures.add(
        '$role: $proofName.charlieJoinMeasurementSource must describe the harness-observed join measurement',
      );
    }
  }

  validateSharedProof('alice', aliceProof);
  validateSharedProof('bob', bobProof);
  validateSharedProof('charlie', charlieProof);

  if (aliceProof != null) {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'readdedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'duplicateReaddApplied',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'duplicateReaddIgnored',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedCharliePostReaddMessage',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof != null) {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedCharliePostReaddMessage',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedAlicePostReaddMessage',
      failures: failures,
    );
  }

  if (charlieProof != null) {
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'memberListIncludesAliceBob',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postReaddPublishAccepted',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedAlicePostReaddMessage',
      failures: failures,
    );
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
  }

  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceAfterDuplicateReadd',
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: 'charlieAfterDuplicateReadd',
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: $proofName.finalEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: $proofName.finalEpoch must be >= 2');
  }
  if (charlieEpoch == null || charlieEpoch < 2) {
    failures.add('charlie: $proofName.finalEpoch must be >= 2');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GM-010 finalEpoch mismatch');
  }
}

void _validateGm011StaleAddRemovalProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm011StaleAddRemovalProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  for (final role in const <String>['alice', 'bob']) {
    final verdict = byRole[role];
    if (verdict == null || charliePeerId == null) continue;
    final members = _stringList(verdict['memberPeerIds']).toSet();
    if (members.contains(charliePeerId)) {
      failures.add('$role: GM-011 final memberPeerIds must exclude Charlie');
    }
  }

  void validateRemainingProof(String role, Map<String, dynamic>? proof) {
    if (proof == null) {
      failures.add('$role: missing GM-011 stale add removal proof fields');
      return;
    }
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'appliedRemoveVersion3',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'deliveredStaleAddVersion2',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'staleAddIgnored',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'staleConfigIncludedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'validatorConfigExcludesCharlie',
      failures: failures,
    );
  }

  validateRemainingProof('alice', aliceProof);
  validateRemainingProof('bob', bobProof);

  if (aliceProof != null) {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'sentAlicePostStaleAdd',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedBobPostStaleAdd',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof != null) {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'sentBobPostStaleAdd',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedAlicePostStaleAdd',
      failures: failures,
    );
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GM-011 stale add removal proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'deliveredStaleAddVersion2',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'groupPresentAfterStaleAdd',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'currentMemberAfterStaleAdd',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'hasOldKeyAfterStaleAdd',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'hasRotatedEpoch',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postRemovalPublishAccepted',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedAlicePostStaleAdd',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedBobPostStaleAdd',
      failures: failures,
    );
    final sendOutcome = _stringValue(charlieProof['postRemovalSendOutcome']);
    if (sendOutcome == null ||
        sendOutcome == 'success' ||
        sendOutcome == 'successNoPeers') {
      failures.add(
        'charlie: $proofName.postRemovalSendOutcome must be rejected',
      );
    }
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.postRemovalPlaintextCount must be 0');
    }
  }

  if (alicePeerId != null && bobPeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceAfterStaleAdd',
      expectedPeerIds: <String>{bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: 'bobAfterStaleAdd',
      expectedPeerIds: <String>{alicePeerId},
      byRole: byRole,
      failures: failures,
    );
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: $proofName.finalEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: $proofName.finalEpoch must be >= 2');
  }
  if (charlieEpoch != 0) {
    failures.add('charlie: $proofName.finalEpoch must be 0');
  }
  if (aliceEpoch != null && bobEpoch != null && aliceEpoch != bobEpoch) {
    failures.add('alice/bob: GM-011 finalEpoch mismatch');
  }
}

void _validateGm012StaleRemoveReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm012StaleRemoveReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final verdict = byRole[role];
    if (verdict == null || charliePeerId == null) continue;
    final charlieRows = _stringList(
      verdict['memberPeerIds'],
    ).where((peerId) => peerId == charliePeerId).length;
    if (charlieRows != 1) {
      failures.add(
        '$role: GM-012 final memberPeerIds must contain Charlie exactly once',
      );
    }
  }

  void validateSharedProof(String role, Map<String, dynamic>? proof) {
    if (proof == null) {
      failures.add('$role: missing GM-012 stale remove re-add proof fields');
      return;
    }
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'deliveredStaleRemoveVersion2',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'staleRemoveIgnored',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'validatorConfigIncludesCharlie',
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'charlieMemberRowCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'charlieActiveDeviceBindingCount',
      expected: 1,
      failures: failures,
    );
  }

  validateSharedProof('alice', aliceProof);
  validateSharedProof('bob', bobProof);
  validateSharedProof('charlie', charlieProof);

  if (aliceProof != null) {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'appliedRemoveVersion2',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'appliedReaddVersion3',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'sentAlicePostStaleRemove',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedCharliePostStaleRemove',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedBobPostStaleRemove',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof != null) {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'sentBobPostStaleRemove',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedAlicePostStaleRemove',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedCharliePostStaleRemove',
      failures: failures,
    );
  }

  if (charlieProof != null) {
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'groupPresentAfterStaleRemove',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'currentMemberAfterStaleRemove',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postReaddPublishAccepted',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'sentCharliePostStaleRemove',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedAlicePostStaleRemove',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedBobPostStaleRemove',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'hasStaleEpochAfterStaleRemove',
      failures: failures,
    );
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceAfterStaleRemove',
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: 'charlieAfterStaleRemove',
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: 'bobAfterStaleRemove',
      expectedPeerIds: <String>{alicePeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: $proofName.finalEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: $proofName.finalEpoch must be >= 2');
  }
  if (charlieEpoch == null || charlieEpoch < 2) {
    failures.add('charlie: $proofName.finalEpoch must be >= 2');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: GM-012 finalEpoch mismatch');
  }
}

void _validateGm013SimultaneousRemoveSendProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm013SimultaneousRemoveSendProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  for (final role in const <String>['alice', 'bob']) {
    final verdict = byRole[role];
    if (verdict == null || charliePeerId == null) continue;
    final members = _stringList(verdict['memberPeerIds']).toSet();
    if (members.contains(charliePeerId)) {
      failures.add('$role: GM-013 final memberPeerIds must exclude Charlie');
    }
  }

  DateTime? parseProofTime(
    String role,
    Map<String, dynamic> proof,
    String field,
  ) {
    final raw = _stringValue(proof[field]);
    final parsed = raw == null ? null : DateTime.tryParse(raw)?.toUtc();
    if (parsed == null) {
      failures.add('$role: $proofName.$field must be a parseable timestamp');
    }
    return parsed;
  }

  final cutoffByRole = <String, DateTime>{};
  void validateRemainingProof(String role, Map<String, dynamic>? proof) {
    if (proof == null) {
      failures.add(
        '$role: missing GM-013 simultaneous remove/send proof fields',
      );
      return;
    }

    final cutoff = parseProofTime(role, proof, 'removalCutoffAt');
    final before = parseProofTime(role, proof, 'beforeSentAt');
    final after = parseProofTime(role, proof, 'afterSentAt');
    if (cutoff != null) {
      cutoffByRole[role] = cutoff;
    }
    if (cutoff != null && before != null && !before.isBefore(cutoff)) {
      failures.add(
        '$role: $proofName.beforeSentAt must be before removalCutoffAt',
      );
    }
    if (cutoff != null && after != null && after.isBefore(cutoff)) {
      failures.add(
        '$role: $proofName.afterSentAt must be at or after removalCutoffAt',
      );
    }

    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'acceptedBeforeCutoff',
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'beforeCutoffPersistedCount',
      expected: 1,
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'rejectedAfterCutoff',
      failures: failures,
    );
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'afterCutoffAccepted',
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'afterCutoffPersistedCount',
      expected: 0,
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'clearAfterCutoffRejectionEvent',
      failures: failures,
    );
    final reason = _stringValue(proof['afterCutoffRejectionReason']);
    const allowedReasons = <String>{
      'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
      'removed_after_cutoff',
      'non_member',
      'bad_epoch',
    };
    if (reason == null || !allowedReasons.contains(reason)) {
      failures.add(
        '$role: $proofName.afterCutoffRejectionReason must be a clear removal rejection reason',
      );
    }
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'validatorConfigExcludesCharlie',
      failures: failures,
    );
  }

  validateRemainingProof('alice', aliceProof);
  validateRemainingProof('bob', bobProof);

  if (cutoffByRole.length == 2 &&
      !cutoffByRole['alice']!.isAtSameMomentAs(cutoffByRole['bob']!)) {
    failures.add('alice/bob: GM-013 removalCutoffAt mismatch');
  }

  if (aliceProof != null) {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'sentAlicePostRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedBobPostRemoval',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof != null) {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedAlicePostRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'sentBobPostRemoval',
      failures: failures,
    );
  }

  if (charlieProof == null) {
    failures.add(
      'charlie: missing GM-013 simultaneous remove/send proof fields',
    );
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'currentMemberBeforeRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'startedOldEpochPublishBeforeRemoval',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'groupPresentAfterRemoval',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'currentMemberAfterRemoval',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'hasRotatedEpoch',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postRemovalPublishAccepted',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedAlicePostRemoval',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedBobPostRemoval',
      failures: failures,
    );
    final sendOutcome = _stringValue(charlieProof['postRemovalSendOutcome']);
    if (sendOutcome == null ||
        sendOutcome == 'success' ||
        sendOutcome == 'successNoPeers') {
      failures.add(
        'charlie: $proofName.postRemovalSendOutcome must be rejected',
      );
    }
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.postRemovalPlaintextCount must be 0');
    }
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: 'charlieBeforeCutoff',
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceAfterCharlieRemove',
      expectedPeerIds: <String>{bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: 'bobAfterCharlieRemove',
      expectedPeerIds: <String>{alicePeerId},
      byRole: byRole,
      failures: failures,
    );
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: $proofName.finalEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: $proofName.finalEpoch must be >= 2');
  }
  if (charlieEpoch != 0) {
    failures.add('charlie: $proofName.finalEpoch must be 0');
  }
  if (aliceEpoch != null && bobEpoch != null && aliceEpoch != bobEpoch) {
    failures.add('alice/bob: GM-013 finalEpoch mismatch');
  }
}

void _validateGm014SimultaneousReaddSendProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm014SimultaneousReaddSendProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  DateTime? parseProofTime(
    String role,
    Map<String, dynamic> proof,
    String field,
  ) {
    final raw = _stringValue(proof[field]);
    final parsed = raw == null ? null : DateTime.tryParse(raw)?.toUtc();
    if (parsed == null) {
      failures.add('$role: $proofName.$field must be a parseable timestamp');
    }
    return parsed;
  }

  final readdAtByRole = <String, DateTime>{};
  final charlieJoinedAtByRole = <String, DateTime>{};

  void requireSharedReaddTimestamp(
    String field,
    Map<String, DateTime> timestampsByRole,
  ) {
    final uniqueInstants = timestampsByRole.values
        .map((timestamp) => timestamp.microsecondsSinceEpoch)
        .toSet();
    if (uniqueInstants.length <= 1) return;

    final roles = timestampsByRole.keys.toList(growable: false)..sort();
    failures.add(
      '$proofName.$field must match one shared re-add timestamp across '
      '${roles.join(', ')}',
    );
  }

  void validateSharedProof(String role, Map<String, dynamic>? proof) {
    if (proof == null) {
      failures.add(
        '$role: missing GM-014 simultaneous re-add/send proof fields',
      );
      return;
    }
    final readdAt = parseProofTime(role, proof, 'readdAt');
    final joinedAt = parseProofTime(role, proof, 'charlieJoinedAt');
    final sendAt = parseProofTime(role, proof, 'alicePostReaddSentAt');
    if (readdAt != null) {
      readdAtByRole[role] = readdAt;
    }
    if (joinedAt != null) {
      charlieJoinedAtByRole[role] = joinedAt;
    }
    if (readdAt != null &&
        joinedAt != null &&
        !readdAt.isAtSameMomentAs(joinedAt)) {
      failures.add('$role: $proofName.charlieJoinedAt must equal readdAt');
    }
    if (readdAt != null && sendAt != null && !sendAt.isAfter(readdAt)) {
      failures.add(
        '$role: $proofName.alicePostReaddSentAt must be after readdAt',
      );
    }
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'memberListIncludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'validatorConfigIncludesCharlie',
      failures: failures,
    );
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'hasStaleEpochAfterCatchUp',
      failures: failures,
    );
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  validateSharedProof('alice', aliceProof);
  validateSharedProof('bob', bobProof);
  validateSharedProof('charlie', charlieProof);
  requireSharedReaddTimestamp('readdAt', readdAtByRole);
  requireSharedReaddTimestamp('charlieJoinedAt', charlieJoinedAtByRole);

  if (aliceProof != null) {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'readdedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'sentAlicePostReadd',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedBobPostReadd',
      failures: failures,
    );
    final readdedPeerId = _stringValue(aliceProof['readdedPeerId']);
    if (charliePeerId != null && readdedPeerId != charliePeerId) {
      failures.add('alice: $proofName.readdedPeerId must be charlie');
    }
  }

  if (bobProof != null) {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedAlicePostReadd',
      failures: failures,
    );
  }

  if (charlieProof != null) {
    final repaired = charlieProof['repairSignalRecorded'] == true;
    final direct = charlieProof['directPostReaddDecrypt'] == true;
    if (!repaired && !direct) {
      failures.add(
        'charlie: $proofName requires repairSignalRecorded or directPostReaddDecrypt',
      );
    }
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'delayedKeyOrConfig',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'caughtUpPostReaddMessage',
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postReaddPersistedCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'charlieMemberRowCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'charlieActiveDeviceBindingCount',
      expected: 1,
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'duplicateTopicJoins',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'duplicateDurableRecipients',
      failures: failures,
    );
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceAfterReadd',
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGm015AdminSelfRemovalPolicyProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm015AdminSelfRemovalPolicyProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedPeerIds = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};

  bool hasExactMembers(List<String> values) {
    final unique = values.toSet();
    return expectedPeerIds.length == 3 &&
        values.length == expectedPeerIds.length &&
        unique.length == expectedPeerIds.length &&
        unique.containsAll(expectedPeerIds);
  }

  void validateSharedProof(String role, Map<String, dynamic>? proof) {
    if (proof == null) {
      failures.add(
        '$role: missing GM-015 admin self-removal policy proof fields',
      );
      return;
    }

    if (proof['groupPresent'] != true) {
      failures.add('$role: GM-015 silent group disappearance after block');
    }
    if (proof['groupDissolved'] != false) {
      failures.add('$role: GM-015 unexpected dissolution after block');
    }
    if (proof['mutationAfterBlockedAttempt'] != false) {
      failures.add('$role: GM-015 membership mutated after blocked operation');
    }
    if (proof['keyEpochUnchanged'] != true) {
      failures.add('$role: GM-015 key epoch changed after blocked operation');
    }

    final proofMembers = _stringList(proof['finalMemberPeerIds']);
    final verdictMembers = _stringList(byRole[role]?['memberPeerIds']);
    if (!hasExactMembers(proofMembers) || !hasExactMembers(verdictMembers)) {
      failures.add('$role: GM-015 membership mutated after blocked operation');
    }

    final creatorPeerId = _stringValue(proof['creatorPeerId']);
    if (alicePeerId != null && creatorPeerId != alicePeerId) {
      failures.add('$role: GM-015 createdBy must remain Alice');
    }

    final adminPeerIds = _stringList(proof['adminPeerIds']);
    if (adminPeerIds.isEmpty || proof['memberListHasActiveAdmin'] != true) {
      failures.add('$role: GM-015 writerless zombie group has no active admin');
    }
    if (alicePeerId != null &&
        (adminPeerIds.length != 1 || adminPeerIds.single != alicePeerId)) {
      failures.add(
        '$role: GM-015 stale admin role; Alice must remain sole admin',
      );
    }

    final initialKeyEpoch = _intValue(proof['initialKeyEpoch']);
    final finalKeyEpoch = _intValue(proof['finalKeyEpoch']);
    if (initialKeyEpoch != null &&
        finalKeyEpoch != null &&
        initialKeyEpoch != finalKeyEpoch) {
      failures.add('$role: GM-015 key epoch changed after blocked operation');
    }
  }

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  validateSharedProof('alice', aliceProof);
  validateSharedProof('bob', bobProof);
  validateSharedProof('charlie', charlieProof);

  if (aliceProof != null) {
    if (_stringValue(aliceProof['selfRemovalOutcome']) != 'blocked') {
      failures.add('alice: $proofName.selfRemovalOutcome must be blocked');
    }
    final selfRemovalReason = _stringValue(aliceProof['selfRemovalReason']);
    if (selfRemovalReason == null ||
        !selfRemovalReason.contains(
          "You can't remove the last admin from this group.",
        )) {
      failures.add('alice: missing GM-015 clear self-removal block reason');
    }
    if (_stringValue(aliceProof['voluntaryLeaveBroadcastOutcome']) !=
        'skipped') {
      failures.add(
        'alice: $proofName.voluntaryLeaveBroadcastOutcome must be skipped',
      );
    }
    if (_stringValue(aliceProof['voluntaryLeaveBroadcastSkipReason']) !=
        'lastAdmin') {
      failures.add(
        'alice: $proofName.voluntaryLeaveBroadcastSkipReason must be lastAdmin',
      );
    }
    if (_stringValue(aliceProof['leaveOutcome']) != 'blocked') {
      failures.add('alice: $proofName.leaveOutcome must be blocked');
    }
    final leaveReason = _stringValue(aliceProof['leaveReason']);
    if (leaveReason == null ||
        !leaveReason.contains(
          "You can't leave this group because you're the only admin.",
        )) {
      failures.add('alice: missing GM-015 clear leave block reason');
    }
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedBobPostAttemptSend',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'receivedCharliePostAttemptSend',
      failures: failures,
    );
  }

  if (bobProof != null) {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'sentBobPostAttemptSend',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedCharliePostAttemptSend',
      failures: failures,
    );
  }

  if (charlieProof != null) {
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedBobPostAttemptSend',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'sentCharliePostAttemptSend',
      failures: failures,
    );
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: 'bobAfterBlockedAdminSelfRemoval',
      expectedPeerIds: <String>{alicePeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: 'charlieAfterBlockedAdminLeave',
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGm016RemovedUnsubscribeProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm016RemovedUnsubscribeProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  if (aliceProof == null) {
    failures.add('alice: missing GM-016 removed unsubscribe proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'charlieOnlineBeforeRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'sentAlicePostRemoval',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GM-016 removed unsubscribe proof fields');
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedAlicePostRemoval',
      failures: failures,
    );
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GM-016 removed unsubscribe proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'activeMemberBeforeRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'leaveRequested',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'leaveResponseOk',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'groupPresentAfterRemoval',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'groupRecreatedAfterQuietWindow',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedAlicePostRemoval',
      failures: failures,
    );
    for (final field in const <String>[
      'memberRowsAfterRemoval',
      'keyEpochAfterRemoval',
      'postLeaveGroupJoinCount',
      'postLeaveInboundEventCount',
      'postLeaveReactionEventCount',
      'postLeaveDiscoveryEventCount',
      'postLeavePayloadParseFailedCount',
      'postLeaveDecryptionFailedCount',
      'postRemovalPlaintextCount',
    ]) {
      _requireIntProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        expected: 0,
        failures: failures,
      );
    }
    final quietWindowMs = _intValue(charlieProof['postLeaveQuietWindowMs']);
    final hasStaleStimulus =
        charlieProof['staleDiscoveryRegisterStimulus'] == true;
    if (!hasStaleStimulus && (quietWindowMs == null || quietWindowMs < 3000)) {
      failures.add(
        'charlie: $proofName requires staleDiscoveryRegisterStimulus or '
        'postLeaveQuietWindowMs >= 3000',
      );
    }
  }

  if (bobPeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceAfterCharlieUnsubscribe',
      expectedPeerIds: <String>{bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    final charlieMembers = _stringList(byRole['charlie']?['memberPeerIds']);
    if (charlieMembers.contains(alicePeerId) ||
        charlieMembers.contains(bobPeerId) ||
        charlieMembers.contains(charliePeerId)) {
      failures.add('charlie: GM-016 removed member retained group members');
    }
  }
}

void _validateGm017StaleSubscriptionValidationProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
  String proofName = 'gm017StaleSubscriptionValidationProof',
  String label = 'GM-017',
  bool requireSenderFeedback = false,
}) {
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  for (final role in const <String>['alice', 'bob']) {
    final proof = role == 'alice' ? aliceProof : bobProof;
    if (proof == null) {
      failures.add('$role: missing $label stale subscription proof fields');
      continue;
    }
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'validationRejected',
      failures: failures,
    );
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'receivedStaleCharliePlaintext',
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'stalePlaintextCount',
      expected: 0,
      failures: failures,
    );
    final rejectCount = _intValue(proof['validationRejectCount']);
    if (rejectCount == null || rejectCount < 1) {
      failures.add('$role: $proofName.validationRejectCount must be >= 1');
    }
    final reason = _stringValue(proof['validationRejectReason']);
    if (reason != 'non_member' && reason != 'bad_signature_or_epoch') {
      failures.add(
        '$role: $proofName.validationRejectReason must be non_member or '
        'bad_signature_or_epoch',
      );
    }
  }

  if (aliceProof != null) {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedCharlieFromLocalConfig',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'sentAliceHealthyAfterReject',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof != null) {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'installedConfigWithoutCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedAliceHealthyAfterReject',
      failures: failures,
    );
  }

  if (charlieProof == null) {
    failures.add('charlie: missing $label stale subscription proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'groupPresentAfterRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'keyPresentAfterRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'memberListStillIncludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'staleSubscriptionPresent',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'sentStaleMarker',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'stalePublishAccepted',
      failures: failures,
    );
    if (requireSenderFeedback) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: 'senderValidationFeedbackReceived',
        failures: failures,
      );
      final feedbackReason = _stringValue(
        charlieProof['senderValidationFeedbackReason'],
      );
      if (feedbackReason != 'non_member' &&
          feedbackReason != 'bad_signature_or_epoch') {
        failures.add(
          'charlie: $proofName.senderValidationFeedbackReason must be '
          'non_member or bad_signature_or_epoch',
        );
      }
      final status = _stringValue(charlieProof['senderStatusAfterFeedback']);
      if (status != 'failed') {
        failures.add(
          'charlie: $proofName.senderStatusAfterFeedback must be failed',
        );
      }
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: 'senderWireEnvelopeRetryableAfterFeedback',
        failures: failures,
      );
    }
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'leaveRequested',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'leaveResponseOk',
      failures: failures,
    );
    if (charliePeerId != null) {
      final charlieMembers = _stringList(byRole['charlie']?['memberPeerIds']);
      if (!charlieMembers.contains(charliePeerId)) {
        failures.add(
          'charlie: $label stale memberPeerIds must include Charlie',
        );
      }
    }
  }

  if (bobPeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceAfterStaleCharlieReject',
      expectedPeerIds: <String>{bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    for (final role in const <String>['alice', 'bob']) {
      final members = _stringList(byRole[role]?['memberPeerIds']).toSet();
      if (members.contains(charliePeerId)) {
        failures.add('$role: $label final memberPeerIds must exclude Charlie');
      }
    }
  }
}

void _validateGm018RemainingDeliveryContinuityProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm018RemainingDeliveryContinuityProof';
  const liveKeys = <String>[
    'aliceGm018Live1',
    'aliceGm018Live2',
    'aliceGm018Live3',
  ];
  const inboxKeys = <String>[
    'aliceGm018Inbox1',
    'aliceGm018Inbox2',
    'aliceGm018Inbox3',
  ];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  if (aliceProof == null) {
    failures.add('alice: missing GM-018 remaining delivery proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedCharlieFromLocalConfig',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'staleOnlinePressureObserved',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'charlieOfflinePressureObserved',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'bobOfflineProofObserved',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'inboxSentAfterBobOffline',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'allDurableRecipientsBobOnly',
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'liveSequenceSentCount',
      minimum: 3,
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'inboxSequenceSentCount',
      minimum: 3,
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
    _requireProofStringListEquals(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'liveSequenceMessageIds',
      expected: _messageIdsForKeys(
        verdict: byRole['alice'],
        collection: 'sentMessages',
        keys: liveKeys,
      ),
      failures: failures,
    );
    _requireProofStringListEquals(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'inboxSequenceMessageIds',
      expected: _messageIdsForKeys(
        verdict: byRole['alice'],
        collection: 'sentMessages',
        keys: inboxKeys,
      ),
      failures: failures,
    );
  }

  if (bobProof == null) {
    failures.add('bob: missing GM-018 remaining delivery proof fields');
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'memberListExcludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'staleOnlinePressureRejected',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'staleOfflinePressureSurvived',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'exactOnceDelivery',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'bobOfflineBeforeInboxSend',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'bobRestartedBeforeInboxDrain',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'inboxReplayDrainedFromDurableInbox',
      failures: failures,
    );
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'inboxLiveLeakCountBeforeReplay',
      expected: 0,
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'inboxReplayDrainMessageCount',
      minimum: 3,
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'liveBobReceiptCount',
      minimum: 3,
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'inboxReplayReceiptCount',
      minimum: 3,
      failures: failures,
    );
    final liveReceivedMessageIds = _messageIdsForKeys(
      verdict: byRole['bob'],
      collection: 'receivedMessages',
      keys: liveKeys,
    );
    final inboxReplayMessageIds = _messageIdsForKeys(
      verdict: byRole['bob'],
      collection: 'receivedMessages',
      keys: inboxKeys,
    );
    _requireProofStringListEquals(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'liveBobReceiptMessageIds',
      expected: liveReceivedMessageIds,
      failures: failures,
    );
    _requireProofStringListEquals(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'inboxReplayMessageIds',
      expected: inboxReplayMessageIds,
      failures: failures,
    );
    _requireProofStringListEquals(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'inboxReplayReceiptKeys',
      expected: inboxKeys,
      description: 'replay receipt keys',
      failures: failures,
    );
    if (_intValue(bobProof['liveBobReceiptCount']) !=
        liveReceivedMessageIds.length) {
      failures.add(
        'bob: $proofName.liveBobReceiptCount must equal actual live receipt messageIds',
      );
    }
    if (_intValue(bobProof['inboxReplayReceiptCount']) !=
        inboxReplayMessageIds.length) {
      failures.add(
        'bob: $proofName.inboxReplayReceiptCount must equal actual replay messageIds',
      );
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GM-018 remaining delivery proof fields');
  } else {
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'groupPresentAfterRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'keyPresentAfterRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'memberListStillIncludesCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'staleOnlinePressureSent',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'staleOfflineOrRestartPressure',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedPostRemovalPlaintext',
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postRemovalPlaintextCount',
      expected: 0,
      failures: failures,
    );
  }

  if (bobPeerId != null) {
    for (final key in const <String>[
      ...liveKeys,
      ...inboxKeys,
      'aliceGm018AfterCharlieOffline',
    ]) {
      _requireSentRecipientPeerIds(
        role: 'alice',
        key: key,
        expectedPeerIds: <String>{bobPeerId},
        byRole: byRole,
        failures: failures,
      );
    }
  }
  if (charliePeerId != null) {
    for (final role in const <String>['alice', 'bob']) {
      final members = _stringList(byRole[role]?['memberPeerIds']).toSet();
      if (members.contains(charliePeerId)) {
        failures.add('$role: GM-018 final memberPeerIds must exclude Charlie');
      }
    }
  }
}

void _validateGm019DurableRecipientWindowProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm019DurableRecipientWindowProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  if (aliceProof == null) {
    failures.add('alice: missing GM-019 durable recipient window proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'actualDurablePayloadProof',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedWindowExcludedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'postReaddIncludedCharlie',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
    final removedAt = DateTime.tryParse(
      _stringValue(aliceProof['removedAt']) ?? '',
    )?.toUtc();
    final removedWindowSentAt = DateTime.tryParse(
      _stringValue(aliceProof['removedWindowSentAt']) ?? '',
    )?.toUtc();
    final readdAt = DateTime.tryParse(
      _stringValue(aliceProof['readdAt']) ?? '',
    )?.toUtc();
    final postReaddSentAt = DateTime.tryParse(
      _stringValue(aliceProof['postReaddSentAt']) ?? '',
    )?.toUtc();
    if (removedAt == null ||
        removedWindowSentAt == null ||
        readdAt == null ||
        postReaddSentAt == null ||
        !removedAt.isBefore(removedWindowSentAt) ||
        !removedWindowSentAt.isBefore(readdAt) ||
        !readdAt.isBefore(postReaddSentAt)) {
      failures.add(
        'alice: $proofName timestamps must satisfy removedAt < removedWindowSentAt < readdAt < postReaddSentAt',
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GM-019 durable recipient window proof fields');
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'actualDurablePayloadProof',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'bobPostReaddSent',
      failures: failures,
    );
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedAliceRemovedWindow',
      failures: failures,
    );
  }

  if (charlieProof == null) {
    failures.add(
      'charlie: missing GM-019 durable recipient window proof fields',
    );
  } else {
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedRemovedWindowMessage',
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedAlicePostReadd',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedBobPostReadd',
      failures: failures,
    );
  }

  if (bobPeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceGm019RemovedWindow',
      expectedPeerIds: <String>{bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  if (bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceGm019AfterReadd',
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  if (alicePeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: 'bobGm019AfterReadd',
      expectedPeerIds: <String>{alicePeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  for (final entry in const <({String role, String key})>[
    (role: 'alice', key: 'aliceGm019RemovedWindow'),
    (role: 'alice', key: 'aliceGm019AfterReadd'),
    (role: 'bob', key: 'bobGm019AfterReadd'),
  ]) {
    _requireSentActualDurablePayloadProof(
      role: entry.role,
      key: entry.key,
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGm020ImmediateRemovedRecipientExclusionProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm020ImmediateRecipientExclusionProof';
  const postRemovalKeys = <String>[
    'aliceGm020ImmediatePostRemoval',
    'aliceGm020OfflinePostRemoval',
  ];
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  if (aliceProof == null) {
    failures.add(
      'alice: missing GM-020 immediate recipient exclusion proof fields',
    );
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'actualDurablePayloadProof',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'everyPostRemovalExcludedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'charlieUnavailableBeforeOfflinePostRemoval',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
    _requireIntAtLeastProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'postRemovalMessageCount',
      minimum: 2,
      failures: failures,
    );
    _requireProofStringListEquals(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'postRemovalMessageKeys',
      expected: postRemovalKeys,
      failures: failures,
      description: 'post-removal proof keys',
    );

    final removedAt = DateTime.tryParse(
      _stringValue(aliceProof['removedAt']) ?? '',
    )?.toUtc();
    final firstPostRemovalSentAt = DateTime.tryParse(
      _stringValue(aliceProof['firstPostRemovalSentAt']) ?? '',
    )?.toUtc();
    final offlinePostRemovalSentAt = DateTime.tryParse(
      _stringValue(aliceProof['offlinePostRemovalSentAt']) ?? '',
    )?.toUtc();
    if (removedAt == null ||
        firstPostRemovalSentAt == null ||
        offlinePostRemovalSentAt == null ||
        !removedAt.isBefore(firstPostRemovalSentAt) ||
        !firstPostRemovalSentAt.isBefore(offlinePostRemovalSentAt)) {
      failures.add(
        'alice: $proofName timestamps must satisfy removedAt < firstPostRemovalSentAt < offlinePostRemovalSentAt',
      );
    }
  }

  if (bobProof == null) {
    failures.add(
      'bob: missing GM-020 immediate recipient exclusion proof fields',
    );
  } else {
    _requireTrueProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedEveryPostRemovalMessage',
      failures: failures,
    );
    _requireIntAtLeastProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'postRemovalReceiptCount',
      minimum: postRemovalKeys.length,
      failures: failures,
    );
    _requireProofStringListEquals(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'postRemovalMessageKeys',
      expected: postRemovalKeys,
      failures: failures,
      description: 'post-removal receipt keys',
    );
  }

  if (charlieProof == null) {
    failures.add(
      'charlie: missing GM-020 immediate recipient exclusion proof fields',
    );
  } else {
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedPostRemovalPlaintext',
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'postRemovalPlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'unavailableBeforeOfflinePostRemoval',
      failures: failures,
    );
    _requireProofStringListEquals(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'checkedPostRemovalMessageKeys',
      expected: postRemovalKeys,
      failures: failures,
      description: 'checked post-removal keys',
    );
  }

  if (bobPeerId != null) {
    for (final key in postRemovalKeys) {
      _requireSentRecipientPeerIds(
        role: 'alice',
        key: key,
        expectedPeerIds: <String>{bobPeerId},
        byRole: byRole,
        failures: failures,
      );
      _requireSentActualDurablePayloadProof(
        role: 'alice',
        key: key,
        byRole: byRole,
        failures: failures,
      );
    }
  }
  if (alicePeerId != null && charliePeerId != null) {
    final charlieReceivedKeys = _mapList(
      byRole['charlie']?['receivedMessages'],
    ).map((entry) => _stringValue(entry['key'])).whereType<String>().toSet();
    for (final key in postRemovalKeys) {
      if (charlieReceivedKeys.contains(key)) {
        failures.add('charlie: must not receive $key after removal');
      }
    }
  }
}

void _validateGm021FreshReaddPackageProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm021FreshReaddPackageProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMembers = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};
  final proofs = <String, Map<String, dynamic>?>{
    for (final role in const <String>['alice', 'bob', 'charlie'])
      role: _mapValue(byRole[role]?[proofName]),
  };

  String? sharedOldKeyPackageId;
  String? sharedFreshKeyPackageId;
  String? sharedOldDeviceId;
  String? sharedFreshDeviceId;

  for (final entry in proofs.entries) {
    final role = entry.key;
    final proof = entry.value;
    if (proof == null) {
      failures.add('$role: missing GM-021 fresh re-add package proof fields');
      continue;
    }

    final members = _stringList(byRole[role]?['memberPeerIds']).toSet();
    final missingMembers = expectedMembers.difference(members);
    if (expectedMembers.length == 3 && missingMembers.isNotEmpty) {
      failures.add(
        '$role: GM-021 final memberPeerIds must include '
        '${missingMembers.join(', ')}',
      );
    }

    final oldKeyPackageId = _stringValue(proof['oldKeyPackageId']);
    final freshKeyPackageId = _stringValue(proof['freshKeyPackageId']);
    final oldDeviceId = _stringValue(proof['oldDeviceId']);
    final freshDeviceId = _stringValue(proof['freshDeviceId']);
    if (oldKeyPackageId == null || oldKeyPackageId.isEmpty) {
      failures.add('$role: $proofName.oldKeyPackageId is required');
    }
    if (freshKeyPackageId == null || freshKeyPackageId.isEmpty) {
      failures.add('$role: $proofName.freshKeyPackageId is required');
    }
    if (oldDeviceId == null || oldDeviceId.isEmpty) {
      failures.add('$role: $proofName.oldDeviceId is required');
    }
    if (freshDeviceId == null || freshDeviceId.isEmpty) {
      failures.add('$role: $proofName.freshDeviceId is required');
    }
    if (oldKeyPackageId != null &&
        freshKeyPackageId != null &&
        oldKeyPackageId == freshKeyPackageId) {
      failures.add(
        '$role: $proofName.oldKeyPackageId and freshKeyPackageId must differ',
      );
    }

    sharedOldKeyPackageId ??= oldKeyPackageId;
    sharedFreshKeyPackageId ??= freshKeyPackageId;
    sharedOldDeviceId ??= oldDeviceId;
    sharedFreshDeviceId ??= freshDeviceId;
    if (sharedOldKeyPackageId != null &&
        oldKeyPackageId != null &&
        sharedOldKeyPackageId != oldKeyPackageId) {
      failures.add('$role: $proofName.oldKeyPackageId disagrees across roles');
    }
    if (sharedFreshKeyPackageId != null &&
        freshKeyPackageId != null &&
        sharedFreshKeyPackageId != freshKeyPackageId) {
      failures.add(
        '$role: $proofName.freshKeyPackageId disagrees across roles',
      );
    }
    if (sharedOldDeviceId != null &&
        oldDeviceId != null &&
        sharedOldDeviceId != oldDeviceId) {
      failures.add('$role: $proofName.oldDeviceId disagrees across roles');
    }
    if (sharedFreshDeviceId != null &&
        freshDeviceId != null &&
        sharedFreshDeviceId != freshDeviceId) {
      failures.add('$role: $proofName.freshDeviceId disagrees across roles');
    }

    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'activeConfigContainsFreshPackage',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'oldRemovedPackageAbsentFromActiveConfig',
      failures: failures,
    );

    final activeKeyPackageIds = _stringList(proof['activeConfigKeyPackageIds']);
    if (freshKeyPackageId != null &&
        !activeKeyPackageIds.contains(freshKeyPackageId)) {
      failures.add(
        '$role: $proofName.activeConfigKeyPackageIds must include fresh package',
      );
    }
    if (oldKeyPackageId != null &&
        activeKeyPackageIds.contains(oldKeyPackageId)) {
      failures.add(
        '$role: $proofName.activeConfigKeyPackageIds must not include old removed package',
      );
    }
  }

  final aliceProof = proofs['alice'];
  if (aliceProof != null) {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'readdedCharlie',
      failures: failures,
    );
    final removedAt = DateTime.tryParse(
      _stringValue(aliceProof['removedAt']) ?? '',
    )?.toUtc();
    final readdAt = DateTime.tryParse(
      _stringValue(aliceProof['readdAt']) ?? '',
    )?.toUtc();
    if (removedAt == null || readdAt == null || !removedAt.isBefore(readdAt)) {
      failures.add(
        'alice: $proofName timestamps must satisfy removedAt < readdAt',
      );
    }
  }

  final charlieProof = proofs['charlie'];
  if (charlieProof != null) {
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'freshPostReaddPublishAccepted',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'freshSendUsedFreshKeyPackage',
      failures: failures,
    );
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'sameActiveDeviceStaleKeyPackageRejected',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'sameActiveDeviceStaleKeyPackageAccepted',
      failures: failures,
    );
    final reason = _stringValue(
      charlieProof['sameActiveDeviceStaleKeyPackageRejectionReason'],
    );
    if (reason != 'unbound_device') {
      failures.add(
        'charlie: $proofName.sameActiveDeviceStaleKeyPackageRejectionReason must be unbound_device',
      );
    }
    final oldDeviceId = _stringValue(charlieProof['oldDeviceId']);
    final freshDeviceId = _stringValue(charlieProof['freshDeviceId']);
    if (oldDeviceId != null &&
        freshDeviceId != null &&
        oldDeviceId != freshDeviceId) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: 'fullOldDevicePackageRejected',
        failures: failures,
      );
    }
  }

  for (final role in const <String>['alice', 'bob']) {
    final proof = proofs[role];
    if (proof == null) continue;
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'receivedFreshCharlieMessage',
      failures: failures,
    );
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'receivedStaleSameActiveDevicePlaintext',
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'staleSameActiveDevicePlaintextCount',
      expected: 0,
      failures: failures,
    );
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'receivedStaleFullOldDevicePlaintext',
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'staleFullOldDevicePlaintextCount',
      expected: 0,
      failures: failures,
    );
  }

  if (alicePeerId != null && bobPeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: 'charlieGm021FreshAfterReadd',
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  if (sharedFreshKeyPackageId != null) {
    final sent = _mapList(byRole['charlie']?['sentMessages'])
        .where(
          (entry) =>
              _stringValue(entry['key']) == 'charlieGm021FreshAfterReadd',
        )
        .toList(growable: false);
    if (sent.length == 1 &&
        _stringValue(sent.single['senderKeyPackageId']) !=
            sharedFreshKeyPackageId) {
      failures.add(
        'charlie: sent charlieGm021FreshAfterReadd senderKeyPackageId must be fresh',
      );
    }
  }
}

void _validateGm022RepeatedReaddDedupProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm022RepeatedReaddDedupProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMembers = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing GM-022 repeated re-add dedupe proof fields');
      continue;
    }

    final memberPeerIds = _stringList(byRole[role]?['memberPeerIds']);
    if (memberPeerIds.length != memberPeerIds.toSet().length) {
      failures.add(
        '$role: GM-022 final memberPeerIds must not contain duplicates',
      );
    }
    if (expectedMembers.length == 3) {
      final missing = expectedMembers.difference(memberPeerIds.toSet());
      if (missing.isNotEmpty) {
        failures.add(
          '$role: GM-022 final memberPeerIds must include ${missing.join(', ')}',
        );
      }
    }

    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'removeReaddCycleCount',
      expected: 20,
      failures: failures,
    );
    _requireGm022PeerList(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'rawMemberPeerIds',
      expectedMembers: expectedMembers,
      charliePeerId: charliePeerId,
      failures: failures,
    );
    _requireGm022PeerList(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'configMemberPeerIds',
      expectedMembers: expectedMembers,
      charliePeerId: charliePeerId,
      failures: failures,
    );

    final duplicates = _stringList(proof['duplicateMemberPeerIds']);
    if (duplicates.isNotEmpty) {
      failures.add('$role: $proofName.duplicateMemberPeerIds must be empty');
    }
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'charlieMemberEntryCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'activeCharlieEntryCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'activeCharlieDeviceCount',
      expected: 1,
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'validatorUsedActiveEntry',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'freshCharlieSendAccepted',
      failures: failures,
    );
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'staleShadowSendAccepted',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'postCycleDeliveryStable',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'durableRecipientsUnique',
      failures: failures,
    );
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: 'charlieGm022AfterReadd',
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceGm022AfterReadd',
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: 'bobGm022AfterReadd',
      expectedPeerIds: <String>{alicePeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  for (final (role, key) in const <(String, String)>[
    ('charlie', 'charlieGm022AfterReadd'),
    ('alice', 'aliceGm022AfterReadd'),
    ('bob', 'bobGm022AfterReadd'),
  ]) {
    _requireSentActualDurablePayloadProof(
      role: role,
      key: key,
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGm023InactiveShadowProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm023InactiveShadowProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMembers = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing GM-023 inactive shadow proof fields');
      continue;
    }

    final memberPeerIds = _stringList(byRole[role]?['memberPeerIds']);
    if (memberPeerIds.length != memberPeerIds.toSet().length) {
      failures.add(
        '$role: GM-023 final memberPeerIds must not contain duplicates',
      );
    }
    if (expectedMembers.length == 3) {
      final missing = expectedMembers.difference(memberPeerIds.toSet());
      if (missing.isNotEmpty) {
        failures.add(
          '$role: GM-023 final memberPeerIds must include ${missing.join(', ')}',
        );
      }
    }

    _requireGm022PeerList(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'rawMemberPeerIds',
      expectedMembers: expectedMembers,
      charliePeerId: charliePeerId,
      failures: failures,
    );
    _requireGm022PeerList(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'configMemberPeerIds',
      expectedMembers: expectedMembers,
      charliePeerId: charliePeerId,
      failures: failures,
    );

    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'inactiveShadowBeforeActive',
      failures: failures,
    );
    final duplicateConfigRejected = proof['duplicateConfigRejected'] == true;
    if (!duplicateConfigRejected) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'activeEntrySelected',
        failures: failures,
      );
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'freshCharlieSendAccepted',
        failures: failures,
      );
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'discoveryUsedActiveEntry',
        failures: failures,
      );
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'postShadowDeliveryStable',
        failures: failures,
      );
      _requireIntProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'charlieMemberEntryCount',
        expected: 1,
        failures: failures,
      );
      _requireIntProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'activeCharlieEntryCount',
        expected: 1,
        failures: failures,
      );
      _requireIntProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'activeCharlieDeviceCount',
        expected: 1,
        failures: failures,
      );
    }
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'staleInactiveShadowSendAccepted',
      failures: failures,
    );
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'inactiveShadowDialedOrCounted',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'durableRecipientsUnique',
      failures: failures,
    );
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: 'charlieGm023AfterInactiveShadow',
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceGm023AfterInactiveShadow',
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: 'bobGm023AfterInactiveShadow',
      expectedPeerIds: <String>{alicePeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  for (final (role, key) in const <(String, String)>[
    ('charlie', 'charlieGm023AfterInactiveShadow'),
    ('alice', 'aliceGm023AfterInactiveShadow'),
    ('bob', 'bobGm023AfterInactiveShadow'),
  ]) {
    _requireSentActualDurablePayloadProof(
      role: role,
      key: key,
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGm024MemberDisplayStateProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm024MemberDisplayStateProof';
  const expectedSendKeys = <String>{
    'aliceGm024AfterReadd',
    'bobGm024AfterReadd',
    'charlieGm024AfterReadd',
  };
  const expectedSendKeyByRole = <String, String>{
    'alice': 'aliceGm024AfterReadd',
    'bob': 'bobGm024AfterReadd',
    'charlie': 'charlieGm024AfterReadd',
  };
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMembers = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};
  String? sharedCharlieTransportPeerId;

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing GM-024 member display state proof fields');
      continue;
    }

    final memberPeerIds = _stringList(byRole[role]?['memberPeerIds']);
    if (memberPeerIds.length != memberPeerIds.toSet().length) {
      failures.add(
        '$role: GM-024 final memberPeerIds must not contain duplicates',
      );
    }
    if (expectedMembers.length == 3) {
      final missing = expectedMembers.difference(memberPeerIds.toSet());
      if (missing.isNotEmpty) {
        failures.add(
          '$role: GM-024 final memberPeerIds must include ${missing.join(', ')}',
        );
      }
    }

    _requireGm022PeerList(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'rawMemberPeerIds',
      expectedMembers: expectedMembers,
      charliePeerId: charliePeerId,
      failures: failures,
    );
    _requireGm022PeerList(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'configMemberPeerIds',
      expectedMembers: expectedMembers,
      charliePeerId: charliePeerId,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'charlieMemberEntryCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'activeCharlieEntryCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'activeCharlieDeviceCount',
      expected: 1,
      failures: failures,
    );

    if (_stringValue(proof['charlieRole']) != 'writer') {
      failures.add('$role: $proofName.charlieRole must be writer');
    }
    if (_stringValue(proof['charlieJoinedStatus']) != 'joined') {
      failures.add('$role: $proofName.charlieJoinedStatus must be joined');
    }
    if (_stringValue(proof['charlieCurrentStatus']) != 'current') {
      failures.add('$role: $proofName.charlieCurrentStatus must be current');
    }

    final transportPeerId = _stringValue(proof['activeTransportIdentity']);
    if (transportPeerId == null || transportPeerId.isEmpty) {
      failures.add('$role: $proofName.activeTransportIdentity is required');
    } else {
      sharedCharlieTransportPeerId ??= transportPeerId;
      if (sharedCharlieTransportPeerId != transportPeerId) {
        failures.add(
          '$role: $proofName.activeTransportIdentity disagrees across roles',
        );
      }
      final activeTransportPeerIds = _stringList(
        proof['activeTransportPeerIds'],
      );
      if (!activeTransportPeerIds.contains(transportPeerId)) {
        failures.add(
          '$role: $proofName.activeTransportPeerIds must include active identity',
        );
      }
      if (activeTransportPeerIds.length !=
          activeTransportPeerIds.toSet().length) {
        failures.add(
          '$role: $proofName.activeTransportPeerIds must not contain duplicates',
        );
      }
    }

    final proofKeyEpoch = _intValue(proof['keyEpoch']);
    final verdictKeyEpoch = _intValue(byRole[role]?['keyEpoch']);
    if (proofKeyEpoch == null ||
        proofKeyEpoch < 1 ||
        (verdictKeyEpoch != null && proofKeyEpoch != verdictKeyEpoch)) {
      failures.add('$role: $proofName.keyEpoch must match verdict keyEpoch');
    }

    final sentKey = expectedSendKeyByRole[role]!;
    final sentTopicPeerCount = _requireSentLiveTopicPeerEvidence(
      role: role,
      key: sentKey,
      byRole: byRole,
      failures: failures,
    );

    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'composeSendPermission',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'topicJoined',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'livePublishAccepted',
      failures: failures,
    );
    if (_stringValue(proof['liveTopicPeerState']) != 'joined_with_peers') {
      failures.add(
        '$role: $proofName.liveTopicPeerState must be joined_with_peers',
      );
    }
    _requireIntAtLeastProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'liveTopicPeerCount',
      minimum: 2,
      failures: failures,
    );
    final proofLiveTopicPeerCount = _intValue(proof['liveTopicPeerCount']);
    if (sentTopicPeerCount != null &&
        proofLiveTopicPeerCount != null &&
        proofLiveTopicPeerCount != sentTopicPeerCount) {
      failures.add(
        '$role: $proofName.liveTopicPeerCount must match sent '
        '$sentKey topicPeers',
      );
    }
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'exactOnceDelivery',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'durableRecipientsUnique',
      failures: failures,
    );

    final actualSendKeys = _stringList(proof['actualSendKeys']).toSet();
    final missingSendKeys = expectedSendKeys.difference(actualSendKeys);
    if (missingSendKeys.isNotEmpty) {
      failures.add(
        '$role: $proofName.actualSendKeys missing ${missingSendKeys.join(', ')}',
      );
    }
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: 'charlieGm024AfterReadd',
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceGm024AfterReadd',
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: 'bobGm024AfterReadd',
      expectedPeerIds: <String>{alicePeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  for (final (role, key) in const <(String, String)>[
    ('charlie', 'charlieGm024AfterReadd'),
    ('alice', 'aliceGm024AfterReadd'),
    ('bob', 'bobGm024AfterReadd'),
  ]) {
    _requireSentActualDurablePayloadProof(
      role: role,
      key: key,
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGm025RolePermissionReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm025RolePermissionReaddProof';
  const expectedSendKeys = <String>{
    'aliceGm025AfterReadd',
    'bobGm025AfterReadd',
    'charlieGm025AfterReadd',
  };
  const expectedSendKeyByRole = <String, String>{
    'alice': 'aliceGm025AfterReadd',
    'bob': 'bobGm025AfterReadd',
    'charlie': 'charlieGm025AfterReadd',
  };
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMembers = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing GM-025 role permission re-add proof fields');
      continue;
    }

    final memberPeerIds = _stringList(byRole[role]?['memberPeerIds']);
    if (memberPeerIds.length != memberPeerIds.toSet().length) {
      failures.add(
        '$role: GM-025 final memberPeerIds must not contain duplicates',
      );
    }
    if (expectedMembers.length == 3) {
      final missing = expectedMembers.difference(memberPeerIds.toSet());
      if (missing.isNotEmpty) {
        failures.add(
          '$role: GM-025 final memberPeerIds must include ${missing.join(', ')}',
        );
      }
    }

    _requireGm022PeerList(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'rawMemberPeerIds',
      expectedMembers: expectedMembers,
      charliePeerId: charliePeerId,
      failures: failures,
    );
    _requireGm022PeerList(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'configMemberPeerIds',
      expectedMembers: expectedMembers,
      charliePeerId: charliePeerId,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'charlieMemberEntryCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'configCharlieMemberEntryCount',
      expected: 1,
      failures: failures,
    );

    if (_stringValue(proof['oldCharlieRole']) != 'writer') {
      failures.add('$role: $proofName.oldCharlieRole must be writer');
    }
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'oldRemoveMembersAllowed',
      failures: failures,
    );
    if (_stringValue(proof['readdedCharlieRole']) != 'writer') {
      failures.add('$role: $proofName.readdedCharlieRole must be writer');
    }
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'readdedRemoveMembersAllowed',
      failures: failures,
    );
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'staleRemoveMembersAllowedAfterReadd',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'bridgeConfigCurrentRoleProof',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'bridgeConfigCurrentPermissionProof',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'staleActionAttempted',
      failures: failures,
    );
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'staleActionAccepted',
      failures: failures,
    );
    if (_stringValue(proof['actualActionOutcome']) != 'denied') {
      failures.add('$role: $proofName.actualActionOutcome must be denied');
    }
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'bobStillMemberAfterAction',
      failures: failures,
    );
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'aliceStillSeesBobAfterAction',
      failures: failures,
    );
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'actionTombstonePersisted',
      failures: failures,
    );

    final sentKey = expectedSendKeyByRole[role]!;
    final sentTopicPeerCount = _requireSentLiveTopicPeerEvidence(
      role: role,
      key: sentKey,
      byRole: byRole,
      failures: failures,
    );
    final proofLiveTopicPeerCount = _intValue(proof['liveTopicPeerCount']);
    if (sentTopicPeerCount != null &&
        proofLiveTopicPeerCount != null &&
        proofLiveTopicPeerCount != sentTopicPeerCount) {
      failures.add(
        '$role: $proofName.liveTopicPeerCount must match sent '
        '$sentKey topicPeers',
      );
    }

    final actualSendKeys = _stringList(proof['actualSendKeys']).toSet();
    final missingSendKeys = expectedSendKeys.difference(actualSendKeys);
    if (missingSendKeys.isNotEmpty) {
      failures.add(
        '$role: $proofName.actualSendKeys missing ${missingSendKeys.join(', ')}',
      );
    }
  }

  if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: 'charlieGm025AfterReadd',
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceGm025AfterReadd',
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: 'bobGm025AfterReadd',
      expectedPeerIds: <String>{alicePeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  for (final (role, key) in const <(String, String)>[
    ('charlie', 'charlieGm025AfterReadd'),
    ('alice', 'aliceGm025AfterReadd'),
    ('bob', 'bobGm025AfterReadd'),
  ]) {
    _requireSentActualDurablePayloadProof(
      role: role,
      key: key,
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGm033ReplayDuringMembershipUpdateProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm033ReplayDuringMembershipUpdateProof';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  if (aliceProof == null) {
    failures.add('alice: missing GM-033 replay membership update proof fields');
  } else {
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'actualDurablePayloadProof',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'replayStartedBeforeRemoval',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'staleRemovedWindowStoredForCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'removedWindowNormalRecipientsExcludedCharlie',
      failures: failures,
    );
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'postReaddIncludedCharlie',
      failures: failures,
    );
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }

    final replayStartedAt = DateTime.tryParse(
      _stringValue(aliceProof['replayStartedAt']) ?? '',
    )?.toUtc();
    final removedAt = DateTime.tryParse(
      _stringValue(aliceProof['removedAt']) ?? '',
    )?.toUtc();
    final removedWindowSentAt = DateTime.tryParse(
      _stringValue(aliceProof['removedWindowSentAt']) ?? '',
    )?.toUtc();
    final staleStoredAt = DateTime.tryParse(
      _stringValue(aliceProof['staleStoredAt']) ?? '',
    )?.toUtc();
    final readdAt = DateTime.tryParse(
      _stringValue(aliceProof['readdAt']) ?? '',
    )?.toUtc();
    final postReaddSentAt = DateTime.tryParse(
      _stringValue(aliceProof['postReaddSentAt']) ?? '',
    )?.toUtc();
    if (replayStartedAt == null ||
        removedAt == null ||
        removedWindowSentAt == null ||
        staleStoredAt == null ||
        readdAt == null ||
        postReaddSentAt == null ||
        !replayStartedAt.isBefore(removedAt) ||
        !removedAt.isBefore(removedWindowSentAt) ||
        staleStoredAt.isBefore(removedWindowSentAt) ||
        !staleStoredAt.isBefore(readdAt) ||
        !readdAt.isBefore(postReaddSentAt)) {
      failures.add(
        'alice: $proofName timestamps must satisfy replayStartedAt < removedAt < removedWindowSentAt <= staleStoredAt < readdAt < postReaddSentAt',
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing GM-033 replay membership update proof fields');
  } else {
    for (final field in const <String>[
      'receivedBeforeRemoval',
      'receivedRemovedWindow',
      'receivedAlicePostReadd',
      'bobPostReaddSent',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (charlieProof == null) {
    failures.add(
      'charlie: missing GM-033 replay membership update proof fields',
    );
  } else {
    for (final field in const <String>[
      'replayStarted',
      'replayResumed',
      'receivedBeforeRemoval',
      'receivedAlicePostReadd',
      'receivedBobPostReadd',
      'postReaddExactOnce',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'receivedRemovedWindowMessage',
      failures: failures,
    );
    _requireFalseProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'removedWindowMessageIdPersisted',
      failures: failures,
    );
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'removedWindowPlaintextCount',
      expected: 0,
      failures: failures,
    );
  }

  if (bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceGm033BeforeRemoval',
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceGm033AfterReadd',
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  if (bobPeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: 'aliceGm033RemovedWindow',
      expectedPeerIds: <String>{bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  if (alicePeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'bob',
      key: 'bobGm033AfterReadd',
      expectedPeerIds: <String>{alicePeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  for (final entry in const <({String role, String key})>[
    (role: 'alice', key: 'aliceGm033BeforeRemoval'),
    (role: 'alice', key: 'aliceGm033RemovedWindow'),
    (role: 'alice', key: 'aliceGm033AfterReadd'),
    (role: 'bob', key: 'bobGm033AfterReadd'),
  ]) {
    _requireSentActualDurablePayloadProof(
      role: entry.role,
      key: entry.key,
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGm034ConfigUpdateReceiveOrderProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm034ConfigUpdateReceiveOrderProof';
  const messageThenConfigKey = 'aliceGm034MessageThenConfig';
  const configThenMessageKey = 'aliceGm034ConfigThenMessage';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final bobProof = _mapValue(byRole['bob']?[proofName]);

  if (bobProof == null) {
    failures.add(
      'bob: missing GM-034 config update receive order proof fields',
    );
  } else {
    for (final field in const <String>[
      'messageThenConfigBeforeRemoval',
      'configThenMessageAfterRemoval',
      'messageThenConfigExactOnce',
      'configThenMessageExactOnce',
      'noDuplicateMessageIds',
      'deterministicMembershipTimeline',
      'deterministicConfigState',
      'validAliceMessagesSurvived',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'messageThenConfigPersistedCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'configThenMessagePersistedCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'membershipTimelineRemovedCount',
      expected: 1,
      failures: failures,
    );
    _requireProofStringListEquals(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'orderCases',
      expected: const <String>['message_then_config', 'config_then_message'],
      failures: failures,
      description: 'GM-034 delivery order cases',
    );

    final receivedMessageIds = _messageIdsForKeys(
      verdict: byRole['bob'],
      collection: 'receivedMessages',
      keys: const <String>[messageThenConfigKey, configThenMessageKey],
    );
    _requireProofStringListEquals(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedMessageIds',
      expected: receivedMessageIds,
      failures: failures,
      description: 'Bob received message IDs',
    );

    final receivedTexts = _mapList(byRole['bob']?['receivedMessages'])
        .where(
          (entry) =>
              _stringValue(entry['key']) == messageThenConfigKey ||
              _stringValue(entry['key']) == configThenMessageKey,
        )
        .map(_messageText)
        .whereType<String>()
        .toList(growable: false);
    _requireProofStringListEquals(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'receivedTexts',
      expected: receivedTexts,
      failures: failures,
      description: 'Bob received message texts',
    );

    final removedPeerId = _stringValue(bobProof['removedPeerId']);
    if (charliePeerId != null && removedPeerId != charliePeerId) {
      failures.add('bob: $proofName.removedPeerId must be charlie');
    }
    if (alicePeerId != null && bobPeerId != null && charliePeerId != null) {
      _requireProofPeerSet(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: 'finalMemberPeerIds',
        expected: <String>{alicePeerId, bobPeerId},
        failures: failures,
      );
      _requireProofPeerSet(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: 'finalConfigMemberPeerIds',
        expected: <String>{alicePeerId, bobPeerId},
        failures: failures,
      );
    }

    final messageThenConfigAt = DateTime.tryParse(
      _stringValue(bobProof['messageThenConfigReceivedAt']) ?? '',
    )?.toUtc();
    final removedAt = DateTime.tryParse(
      _stringValue(bobProof['removedAt']) ?? '',
    )?.toUtc();
    final configThenMessageAt = DateTime.tryParse(
      _stringValue(bobProof['configThenMessageReceivedAt']) ?? '',
    )?.toUtc();
    final lastMembershipEventAt = DateTime.tryParse(
      _stringValue(bobProof['lastMembershipEventAt']) ?? '',
    )?.toUtc();
    if (messageThenConfigAt == null ||
        removedAt == null ||
        configThenMessageAt == null ||
        lastMembershipEventAt == null ||
        !messageThenConfigAt.isBefore(removedAt) ||
        !removedAt.isBefore(configThenMessageAt) ||
        !lastMembershipEventAt.isAtSameMomentAs(removedAt)) {
      failures.add(
        'bob: $proofName timestamps must satisfy messageThenConfigReceivedAt < removedAt < configThenMessageReceivedAt and lastMembershipEventAt == removedAt',
      );
    }
  }

  if (bobPeerId != null && charliePeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: messageThenConfigKey,
      expectedPeerIds: <String>{bobPeerId, charliePeerId},
      byRole: byRole,
      failures: failures,
    );
    _requireSentRecipientPeerIds(
      role: 'alice',
      key: configThenMessageKey,
      expectedPeerIds: <String>{bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  for (final key in const <String>[
    messageThenConfigKey,
    configThenMessageKey,
  ]) {
    _requireSentActualDurablePayloadProof(
      role: 'alice',
      key: key,
      byRole: byRole,
      failures: failures,
    );
  }
}

void _validateGm035ZeroPeerReaddFirstSendProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'gm035ZeroPeerReaddFirstSendProof';
  const messageKey = 'charlieGm035FirstAfterReadd';
  final alicePeerId = peerIdByRole['alice'];
  final bobPeerId = peerIdByRole['bob'];
  final charliePeerId = peerIdByRole['charlie'];
  final expectedMembers = <String>{?alicePeerId, ?bobPeerId, ?charliePeerId};
  final expectedRecipients = <String>{?alicePeerId, ?bobPeerId};
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  final sentEntries = _mapList(
    byRole['charlie']?['sentMessages'],
  ).where((entry) => _stringValue(entry['key']) == messageKey).toList();
  Map<String, dynamic>? sentMessage;
  if (sentEntries.length == 1) {
    sentMessage = sentEntries.single;
    if (_stringValue(sentMessage['outcome']) != 'successNoPeers') {
      failures.add('charlie: sent $messageKey outcome must be successNoPeers');
    }
    if (sentMessage['actualTopicPeerProof'] != true) {
      failures.add(
        'charlie: sent $messageKey must report actual topic peer proof',
      );
    }
    if (_intValue(sentMessage['topicPeers']) != 0) {
      failures.add('charlie: sent $messageKey topicPeers must be 0');
    }
    final sentInitialTopicPeers = _intValue(sentMessage['initialTopicPeers']);
    if (sentInitialTopicPeers != null && sentInitialTopicPeers != 0) {
      failures.add('charlie: sent $messageKey initialTopicPeers must be 0');
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing GM-035 zero-peer re-add proof fields');
  } else {
    for (final field in const <String>[
      'readdedCharlie',
      'aliceBobEligibleAtSend',
      'sentBeforeLiveDiscoveryCompleted',
      'successNoPeers',
      'actualDurablePayloadProof',
      'durableRecipientsUnique',
      'replayEnvelopeMessageIdMatches',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'initialTopicPeers',
      expected: 0,
      failures: failures,
    );
    final proofKeyEpoch = _intValue(charlieProof['keyEpoch']);
    final verdictKeyEpoch = _intValue(byRole['charlie']?['keyEpoch']);
    if (proofKeyEpoch == null ||
        proofKeyEpoch < 2 ||
        (verdictKeyEpoch != null && proofKeyEpoch != verdictKeyEpoch)) {
      failures.add(
        'charlie: $proofName.keyEpoch must match current verdict epoch >= 2',
      );
    }
    final sentMessageId = _stringValue(sentMessage?['messageId']);
    final proofMessageId = _stringValue(charlieProof['messageId']);
    if (sentMessageId != null &&
        sentMessageId.isNotEmpty &&
        proofMessageId != sentMessageId) {
      failures.add('charlie: $proofName.messageId must match sent $messageKey');
    }
    if (expectedRecipients.length == 2) {
      _requireProofPeerSet(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: 'recipientPeerIds',
        expected: expectedRecipients,
        failures: failures,
      );
    }
    if (expectedMembers.length == 3) {
      _requireProofPeerSet(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: 'currentMemberPeerIds',
        expected: expectedMembers,
        failures: failures,
      );
    }
  }

  for (final role in const <String>['alice', 'bob']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing GM-035 zero-peer re-add proof fields');
      continue;
    }
    for (final field in const <String>[
      'durableDrainCompleted',
      'receivedCharlieFirstSend',
      'liveDuplicateDelivered',
      'noDuplicatePersistence',
      'senderEligibleAtSend',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'postDrainPersistedCount',
      expected: 1,
      failures: failures,
    );
    _requireIntProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'postLiveDuplicatePersistedCount',
      expected: 1,
      failures: failures,
    );
    final sentMessageId = _stringValue(sentMessage?['messageId']);
    final receivedMessageId = _stringValue(proof['receivedMessageId']);
    if (sentMessageId != null &&
        sentMessageId.isNotEmpty &&
        receivedMessageId != sentMessageId) {
      failures.add(
        '$role: $proofName.receivedMessageId must match Charlie send',
      );
    }
    if (expectedMembers.length == 3) {
      _requireProofPeerSet(
        role: role,
        proofName: proofName,
        proof: proof,
        field: 'currentMemberPeerIds',
        expected: expectedMembers,
        failures: failures,
      );
    }
  }

  if (alicePeerId != null && bobPeerId != null) {
    _requireSentRecipientPeerIds(
      role: 'charlie',
      key: messageKey,
      expectedPeerIds: <String>{alicePeerId, bobPeerId},
      byRole: byRole,
      failures: failures,
    );
  }
  _requireSentActualDurablePayloadProof(
    role: 'charlie',
    key: messageKey,
    byRole: byRole,
    failures: failures,
  );
}

void _requireProofPeerSet({
  required String role,
  required String proofName,
  required Map<String, dynamic> proof,
  required String field,
  required Set<String> expected,
  required List<String> failures,
}) {
  final values = _stringList(proof[field]);
  if (values.isEmpty) {
    failures.add('$role: $proofName.$field must include peer IDs');
    return;
  }
  if (values.length != values.toSet().length) {
    failures.add('$role: $proofName.$field must not contain duplicates');
  }
  final actual = values.toSet();
  final missing = expected.difference(actual);
  final unexpected = actual.difference(expected);
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    failures.add(
      '$role: $proofName.$field mismatch'
      '${missing.isNotEmpty ? ', missing ${missing.join(', ')}' : ''}'
      '${unexpected.isNotEmpty ? ', unexpected ${unexpected.join(', ')}' : ''}',
    );
  }
}

void _requireKeySetProof({
  required String role,
  required String proofName,
  required Map<String, dynamic> proof,
  required String field,
  required List<String> expected,
  required List<String> failures,
}) {
  final actual = _stringList(proof[field]).toSet();
  final expectedSet = expected.toSet();
  if (actual.length != _stringList(proof[field]).length) {
    failures.add('$role: $proofName.$field must not contain duplicates');
  }
  final missing = expectedSet.difference(actual);
  final unexpected = actual.difference(expectedSet);
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    failures.add(
      '$role: $proofName.$field mismatch'
      '${missing.isNotEmpty ? ', missing ${missing.join(', ')}' : ''}'
      '${unexpected.isNotEmpty ? ', unexpected ${unexpected.join(', ')}' : ''}',
    );
  }
}

void _requireGm022PeerList({
  required String role,
  required String proofName,
  required Map<String, dynamic> proof,
  required String field,
  required Set<String> expectedMembers,
  required String? charliePeerId,
  required List<String> failures,
}) {
  final values = _stringList(proof[field]);
  if (values.isEmpty) {
    failures.add('$role: $proofName.$field must include final peer IDs');
    return;
  }
  if (values.length != values.toSet().length) {
    failures.add('$role: $proofName.$field must not contain duplicates');
  }
  if (expectedMembers.length == 3) {
    final missing = expectedMembers.difference(values.toSet());
    final unexpected = values.toSet().difference(expectedMembers);
    if (missing.isNotEmpty || unexpected.isNotEmpty) {
      failures.add('$role: $proofName.$field must match final A/B/C members');
    }
  }
  if (charliePeerId != null &&
      values.where((peerId) => peerId == charliePeerId).length != 1) {
    failures.add('$role: $proofName.$field must contain Charlie exactly once');
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

void _requireIntProof({
  required String role,
  required String proofName,
  required Map<String, dynamic> proof,
  required String field,
  required int expected,
  required List<String> failures,
}) {
  final value = _intValue(proof[field]);
  if (value != expected) {
    failures.add('$role: $proofName.$field must be $expected');
  }
}

void _requireIntAtLeastProof({
  required String role,
  required String proofName,
  required Map<String, dynamic> proof,
  required String field,
  required int minimum,
  required List<String> failures,
}) {
  final value = _intValue(proof[field]);
  if (value == null || value < minimum) {
    failures.add('$role: $proofName.$field must be >= $minimum');
  }
}

void _requireSentRecipientPeerIds({
  required String role,
  required String key,
  required Set<String> expectedPeerIds,
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  final verdict = byRole[role];
  if (verdict == null) return;
  final sentEntries = _mapList(
    verdict['sentMessages'],
  ).where((entry) => _stringValue(entry['key']) == key).toList(growable: false);
  if (sentEntries.length != 1) return;

  final recipientPeerIds = _stringList(sentEntries.single['recipientPeerIds']);
  if (recipientPeerIds.isEmpty) {
    failures.add('$role: sent $key missing recipientPeerIds');
    return;
  }
  final uniqueRecipientPeerIds = recipientPeerIds.toSet();
  if (recipientPeerIds.length != uniqueRecipientPeerIds.length) {
    failures.add('$role: sent $key recipientPeerIds contain duplicates');
  }
  final missing = expectedPeerIds.difference(uniqueRecipientPeerIds);
  final unexpected = uniqueRecipientPeerIds.difference(expectedPeerIds);
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    failures.add(
      '$role: sent $key recipientPeerIds mismatch'
      '${missing.isNotEmpty ? ', missing ${missing.join(', ')}' : ''}'
      '${unexpected.isNotEmpty ? ', unexpected ${unexpected.join(', ')}' : ''}',
    );
  }
}

void _requireSentActualDurablePayloadProof({
  required String role,
  required String key,
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  final verdict = byRole[role];
  if (verdict == null) return;
  final sentEntries = _mapList(
    verdict['sentMessages'],
  ).where((entry) => _stringValue(entry['key']) == key).toList(growable: false);
  if (sentEntries.length != 1) return;
  if (sentEntries.single['actualDurablePayloadProof'] != true) {
    failures.add('$role: sent $key must report actual durable payload proof');
  }
}

int? _requireSentLiveTopicPeerEvidence({
  required String role,
  required String key,
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  final verdict = byRole[role];
  if (verdict == null) return null;
  final sentEntries = _mapList(
    verdict['sentMessages'],
  ).where((entry) => _stringValue(entry['key']) == key).toList(growable: false);
  if (sentEntries.length != 1) return null;

  final sent = sentEntries.single;
  if (sent['actualTopicPeerProof'] != true) {
    failures.add('$role: sent $key must report actual topic peer proof');
  }
  final outcome = _stringValue(sent['outcome']);
  if (outcome != 'success') {
    failures.add('$role: sent $key must be a live publish success');
  }
  final topicPeers = _intValue(sent['topicPeers']);
  if (topicPeers == null) {
    failures.add('$role: sent $key missing topicPeers');
    return null;
  }
  if (topicPeers < 2) {
    failures.add('$role: sent $key topicPeers must be >= 2');
  }
  return topicPeers;
}

List<String> _messageIdsForKeys({
  required Map<String, dynamic>? verdict,
  required String collection,
  required List<String> keys,
}) {
  if (verdict == null) return const <String>[];
  final entries = _mapList(verdict[collection]);
  final messageIds = <String>[];
  for (final key in keys) {
    for (final entry in entries) {
      if (_stringValue(entry['key']) != key) continue;
      final messageId = _stringValue(entry['messageId']);
      if (messageId != null && messageId.isNotEmpty) {
        messageIds.add(messageId);
      }
    }
  }
  return messageIds;
}

void _requireProofStringListEquals({
  required String role,
  required String proofName,
  required Map<String, dynamic> proof,
  required String field,
  required List<String> expected,
  required List<String> failures,
  String description = 'actual message IDs',
}) {
  final actual = _stringList(proof[field]);
  if (actual.isEmpty) {
    failures.add('$role: $proofName.$field must include exact $description');
    return;
  }
  if (actual.length != actual.toSet().length) {
    failures.add('$role: $proofName.$field must not contain duplicates');
  }
  if (actual.length != expected.length) {
    failures.add('$role: $proofName.$field must match $description');
    return;
  }
  for (var i = 0; i < expected.length; i++) {
    if (actual[i] != expected[i]) {
      failures.add('$role: $proofName.$field must match $description');
      return;
    }
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

DateTime? _dateTimeValue(Object? value) {
  final text = _stringValue(value);
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text)?.toUtc();
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
