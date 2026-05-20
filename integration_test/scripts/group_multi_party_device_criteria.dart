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
const _de002Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'de002',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _de003Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'de003',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _de007Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'de007',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _de017Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'de017',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ir001Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ir001',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ir015Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ir015',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _ir016Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'ir016',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _pl002Requirement = GroupMultiPartyScenarioRequirement(
  scenario: 'pl002',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateAbcCreateRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_abc_create',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateReactionRoundtripRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_reaction_roundtrip',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateFullMeshOnlineRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_full_mesh_online',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateRelayOnlyDeliveryRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_relay_only_delivery',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privatePartitionReaddHealRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_partition_readd_heal',
      roles: <String>['alice', 'bob', 'charlie'],
    );
const _privateRelayReconnectGroupRecoveryRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_relay_reconnect_group_recovery',
      roles: <String>['alice', 'bob', 'charlie'],
    );
const _privatePeerDisconnectNotRemovalRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_peer_disconnect_not_removal',
      roles: <String>['alice', 'bob', 'charlie'],
    );
const _privateBackgroundResumeGroupDeliveryRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_background_resume_group_delivery',
      roles: <String>['alice', 'bob', 'charlie'],
    );
const _privateLongOfflineEpochChurnRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_long_offline_epoch_churn',
      roles: <String>['alice', 'bob', 'charlie'],
    );
const _privateOnlineAddRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_online_add',
  roles: <String>['alice', 'bob', 'charlie', 'dana'],
);
const _privateOfflineAddRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_offline_add',
  roles: <String>['alice', 'bob', 'charlie', 'dana'],
);
const _privateOnlineRemoveRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_online_remove',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateOfflineRemoveRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_offline_remove',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateOfflineReaddRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_offline_readd',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateReaddCurrentRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_readd_current',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateReaddActiveMembersRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_readd_active_members',
      roles: <String>['alice', 'bob', 'charlie', 'dana'],
    );
const _privateReaddAlternatingChurnRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_readd_alternating_churn',
      roles: <String>['alice', 'bob', 'charlie', 'dana'],
    );
const _privateNetworkChaosInvariantsRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_network_chaos_invariants',
      roles: <String>['alice', 'bob', 'charlie', 'dana'],
    );
const _privateLateLeaveReaddRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_late_leave_readd',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateRotatedDeviceReaddRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_rotated_device_readd',
      roles: <String>['alice', 'bob', 'charlie'],
    );
const _privateSameUserMultiDeviceReaddRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_same_user_multi_device_readd',
      roles: <String>['alice', 'bob', 'charlie', 'dana'],
    );
const _privateReaddCyclesRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_readd_cycles',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateRapidReaddRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_rapid_readd',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateConcurrentAdminMembershipEditsRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_concurrent_admin_membership_edits',
      roles: <String>['alice', 'bob', 'charlie', 'dana'],
    );
const _privateTimelineTruthRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_timeline_truth',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateHistoryRetentionRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_history_retention',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateInviteTerminalStatesRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_invite_terminal_states',
      roles: <String>['alice', 'bob', 'charlie'],
    );
const _privateStaleInviteReaddRequirement = GroupMultiPartyScenarioRequirement(
  scenario: 'private_stale_invite_readd',
  roles: <String>['alice', 'bob', 'charlie'],
);
const _privateStaleLowerKeyUpdateRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_stale_lower_key_update',
      roles: <String>['alice', 'bob', 'charlie'],
    );
const _privateSameEpochKeyConflictRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_same_epoch_key_conflict',
      roles: <String>['alice', 'bob', 'charlie'],
    );
const _privatePartialKeyDistributionRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_partial_key_distribution',
      roles: <String>['alice', 'bob', 'charlie'],
    );
const _privateNonFriendMemberDeliveryRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_non_friend_member_delivery',
      roles: <String>['alice', 'bob', 'dana'],
    );
const _privateAdminRoleTransferDeliveryRequirement =
    GroupMultiPartyScenarioRequirement(
      scenario: 'private_admin_role_transfer_delivery',
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

const _scenarioRequirements = <String, GroupMultiPartyScenarioRequirement>{
  'ge001': _ge001Requirement,
  'ge002': _ge002Requirement,
  'ge003': _ge003Requirement,
  'ge004': _ge004Requirement,
  'ge005': _ge005Requirement,
  'ge006': _ge006Requirement,
  'ge007': _ge007Requirement,
  'ge008': _ge008Requirement,
  'ge009': _ge009Requirement,
  'ge010': _ge010Requirement,
  'go001': _go001Requirement,
  'go002': _go002Requirement,
  'go003': _go003Requirement,
  'ge011': _ge011Requirement,
  'ge012': _ge012Requirement,
  'ge013': _ge013Requirement,
  'ge014': _ge014Requirement,
  'ge015': _ge015Requirement,
  'ge016': _ge016Requirement,
  'ge020': _ge020Requirement,
  'ge021': _ge021Requirement,
  'ge023': _ge023Requirement,
  'ge024': _ge024Requirement,
  'gm001': _gm001Requirement,
  'de002': _de002Requirement,
  'de003': _de003Requirement,
  'de007': _de007Requirement,
  'de017': _de017Requirement,
  'ir001': _ir001Requirement,
  'ir015': _ir015Requirement,
  'ir016': _ir016Requirement,
  'pl002': _pl002Requirement,
  'private_abc_create': _privateAbcCreateRequirement,
  'private_reaction_roundtrip': _privateReactionRoundtripRequirement,
  'private_full_mesh_online': _privateFullMeshOnlineRequirement,
  'private_relay_only_delivery': _privateRelayOnlyDeliveryRequirement,
  'private_partition_readd_heal': _privatePartitionReaddHealRequirement,
  'private_relay_reconnect_group_recovery':
      _privateRelayReconnectGroupRecoveryRequirement,
  'private_peer_disconnect_not_removal':
      _privatePeerDisconnectNotRemovalRequirement,
  'private_background_resume_group_delivery':
      _privateBackgroundResumeGroupDeliveryRequirement,
  'private_long_offline_epoch_churn': _privateLongOfflineEpochChurnRequirement,
  'private_online_add': _privateOnlineAddRequirement,
  'private_offline_add': _privateOfflineAddRequirement,
  'private_online_remove': _privateOnlineRemoveRequirement,
  'private_offline_remove': _privateOfflineRemoveRequirement,
  'private_offline_readd': _privateOfflineReaddRequirement,
  'private_readd_current': _privateReaddCurrentRequirement,
  'private_readd_active_members': _privateReaddActiveMembersRequirement,
  'private_readd_alternating_churn': _privateReaddAlternatingChurnRequirement,
  'private_network_chaos_invariants': _privateNetworkChaosInvariantsRequirement,
  'private_late_leave_readd': _privateLateLeaveReaddRequirement,
  'private_rotated_device_readd': _privateRotatedDeviceReaddRequirement,
  'private_same_user_multi_device_readd':
      _privateSameUserMultiDeviceReaddRequirement,
  'private_readd_cycles': _privateReaddCyclesRequirement,
  'private_rapid_readd': _privateRapidReaddRequirement,
  'private_concurrent_admin_membership_edits':
      _privateConcurrentAdminMembershipEditsRequirement,
  'private_timeline_truth': _privateTimelineTruthRequirement,
  'private_history_retention': _privateHistoryRetentionRequirement,
  'private_invite_terminal_states': _privateInviteTerminalStatesRequirement,
  'private_stale_invite_readd': _privateStaleInviteReaddRequirement,
  'private_stale_lower_key_update': _privateStaleLowerKeyUpdateRequirement,
  'private_same_epoch_key_conflict': _privateSameEpochKeyConflictRequirement,
  'private_partial_key_distribution': _privatePartialKeyDistributionRequirement,
  'private_non_friend_member_delivery':
      _privateNonFriendMemberDeliveryRequirement,
  'private_admin_role_transfer_delivery':
      _privateAdminRoleTransferDeliveryRequirement,
  'gm002': _gm002Requirement,
  'gm003': _gm003Requirement,
  'gm004': _gm004Requirement,
  'gm005': _gm005Requirement,
  'gm006': _gm006Requirement,
  'gm007': _gm007Requirement,
  'gm008': _gm008Requirement,
  'gm009': _gm009Requirement,
  'gm010': _gm010Requirement,
  'gm011': _gm011Requirement,
  'gm012': _gm012Requirement,
  'gm013': _gm013Requirement,
  'gm014': _gm014Requirement,
  'gm015': _gm015Requirement,
  'gm016': _gm016Requirement,
  'gm017': _gm017Requirement,
  'gm018': _gm018Requirement,
  'gm019': _gm019Requirement,
  'gm020': _gm020Requirement,
  'gm021': _gm021Requirement,
  'gm022': _gm022Requirement,
  'gm023': _gm023Requirement,
  'gm024': _gm024Requirement,
  'gm025': _gm025Requirement,
  'gm033': _gm033Requirement,
  'gm034': _gm034Requirement,
  'gm035': _gm035Requirement,
  'all': _allRequirement,
};

final allGroupMultiPartyDeviceScenarioIds = List<String>.unmodifiable(
  _scenarioRequirements.keys.where((scenario) => scenario != 'all'),
);

final _supportedScenarioText =
    '${allGroupMultiPartyDeviceScenarioIds.join(', ')}, or all';

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
            requirement.scenario == 'private_online_remove' ||
            requirement.scenario == 'private_offline_remove' ||
            requirement.scenario ==
                'private_background_resume_group_delivery' ||
            requirement.scenario == 'gm009' ||
            requirement.scenario == 'gm011' ||
            requirement.scenario == 'gm013' ||
            requirement.scenario == 'gm016' ||
            requirement.scenario == 'gm020' ||
            requirement.scenario == 'gm034' ||
            requirement.scenario == 'private_history_retention' ||
            requirement.scenario == 'private_invite_terminal_states' ||
            requirement.scenario == 'de017') &&
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
        requirement.scenario == 'private_online_remove' ||
        requirement.scenario == 'private_offline_remove' ||
        requirement.scenario == 'private_background_resume_group_delivery' ||
        requirement.scenario == 'gm009' ||
        requirement.scenario == 'gm011' ||
        requirement.scenario == 'gm013' ||
        requirement.scenario == 'gm016' ||
        requirement.scenario == 'gm017' ||
        requirement.scenario == 'private_history_retention' ||
        requirement.scenario == 'private_invite_terminal_states' ||
        requirement.scenario == 'de017' ||
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
        final members = _activeMemberPeerIds(verdict).toSet();
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
    } else if (requirement.scenario ==
        'private_concurrent_admin_membership_edits') {
      final remainingPeerIds = <String>{
        peerIdByRole['alice']!,
        peerIdByRole['bob']!,
        peerIdByRole['dana']!,
      };
      final removedPeerId = peerIdByRole['charlie']!;
      for (final role in const <String>['alice', 'bob', 'dana']) {
        final verdict = byRole[role];
        if (verdict == null) continue;
        final members = _activeMemberPeerIds(verdict).toSet();
        final missingMembers = remainingPeerIds.difference(members);
        if (missingMembers.isNotEmpty) {
          failures.add(
            '$role: incomplete ML-012 membership, missing '
            '${missingMembers.join(', ')}',
          );
        }
        if (members.contains(removedPeerId)) {
          failures.add('$role: ML-012 membership still includes charlie');
        }
      }
    } else if (requirement.scenario == 'private_same_user_multi_device_readd') {
      final accountMemberPeerIds = <String>{
        peerIdByRole['alice']!,
        peerIdByRole['bob']!,
        peerIdByRole['charlie']!,
      };
      final danaRolePeerId = peerIdByRole['dana']!;
      for (final role in requirement.roles) {
        final verdict = byRole[role];
        if (verdict == null) continue;
        final members = _activeMemberPeerIds(verdict).toSet();
        final missingMembers = accountMemberPeerIds.difference(members);
        if (missingMembers.isNotEmpty) {
          failures.add(
            '$role: incomplete RA-013 account membership, missing '
            '${missingMembers.join(', ')}',
          );
        }
        if (members.contains(danaRolePeerId)) {
          failures.add('$role: RA-013 membership includes Dana account');
        }
      }
    } else {
      for (final role in requirement.roles) {
        final verdict = byRole[role];
        if (verdict == null) continue;
        final members = _activeMemberPeerIds(verdict).toSet();
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
  if (text == null || (!message.allowEmptyText && text.isEmpty)) {
    failures.add('${message.senderRole}: sent ${message.key} missing text');
  }
  final sentPeerId = _stringValue(sent['senderPeerId']);
  final expectedPeerId =
      peerIdByRole[message.expectedSenderPeerRole ?? message.senderRole];
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
      (!message.allowEmptyText && text.isEmpty) ||
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
    final expectedSenderPeerId =
        peerIdByRole[message.expectedSenderPeerRole ?? message.senderRole];
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
  return _scenarioRequirements[_normalizeScenario(scenario)];
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

String _ra017Key(int cycle, String phase, String senderRole) =>
    'ra017Cycle${cycle}_${phase}_$senderRole';

String _ra018Key(int cycle, String operation, String senderRole) =>
    'ra018Cycle${cycle}_${operation}_$senderRole';

List<_ExpectedProofMessage> _ra017ExpectedMessages() {
  final messages = <_ExpectedProofMessage>[];
  for (var cycle = 1; cycle <= 3; cycle++) {
    messages.addAll(<_ExpectedProofMessage>[
      _ExpectedProofMessage(
        key: _ra017Key(cycle, 'removed', 'alice'),
        senderRole: 'alice',
        receiverRoles: const <String>['bob', 'dana'],
      ),
      _ExpectedProofMessage(
        key: _ra017Key(cycle, 'removed', 'bob'),
        senderRole: 'bob',
        receiverRoles: const <String>['alice', 'dana'],
      ),
      _ExpectedProofMessage(
        key: _ra017Key(cycle, 'removed', 'dana'),
        senderRole: 'dana',
        receiverRoles: const <String>['alice', 'bob'],
      ),
      _ExpectedProofMessage(
        key: _ra017Key(cycle, 'readd', 'alice'),
        senderRole: 'alice',
        receiverRoles: const <String>['bob', 'charlie', 'dana'],
      ),
      _ExpectedProofMessage(
        key: _ra017Key(cycle, 'readd', 'bob'),
        senderRole: 'bob',
        receiverRoles: const <String>['alice', 'charlie', 'dana'],
      ),
      _ExpectedProofMessage(
        key: _ra017Key(cycle, 'readd', 'dana'),
        senderRole: 'dana',
        receiverRoles: const <String>['alice', 'bob', 'charlie'],
      ),
    ]);
  }
  return messages;
}

List<_ExpectedProofMessage> _ra018ExpectedMessages() {
  final messages = <_ExpectedProofMessage>[];
  for (var cycle = 1; cycle <= 3; cycle++) {
    messages.addAll(<_ExpectedProofMessage>[
      _ExpectedProofMessage(
        key: _ra018Key(cycle, 'charlieRemoved', 'alice'),
        senderRole: 'alice',
        receiverRoles: const <String>['bob', 'dana'],
      ),
      _ExpectedProofMessage(
        key: _ra018Key(cycle, 'charlieReadded', 'bob'),
        senderRole: 'bob',
        receiverRoles: const <String>['alice', 'charlie', 'dana'],
      ),
      _ExpectedProofMessage(
        key: _ra018Key(cycle, 'danaRemoved', 'charlie'),
        senderRole: 'charlie',
        receiverRoles: const <String>['alice', 'bob'],
      ),
      _ExpectedProofMessage(
        key: _ra018Key(cycle, 'danaReadded', 'dana'),
        senderRole: 'dana',
        receiverRoles: const <String>['alice', 'bob', 'charlie'],
      ),
    ]);
  }
  return messages;
}

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
    case 'private_abc_create':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceInitial',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'private_reaction_roundtrip':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceReactionTarget',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'private_full_mesh_online':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceFullMesh',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobFullMesh',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieFullMesh',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'private_relay_only_delivery':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceToRelayOnlyBob',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobRelayOnlyPublishBack',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'private_partition_readd_heal':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceRemovedWindow',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'alicePostHeal',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobPostHeal',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charliePostHeal',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'private_relay_reconnect_group_recovery':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceMissedDuringRelayDrop',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'alicePostReconnectLive',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobRecoveredPublishBack',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'private_peer_disconnect_not_removal':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceMissedDuringDisconnect',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'alicePostReconnectLive',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobPublishBackAfterReconnect',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'private_background_resume_group_delivery':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceDuringBackgroundBeforeEdit',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceDuringBackgroundAfterEdit',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'alicePostForegroundLive',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'bobPostForegroundPublishBack',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
      ];
    case 'private_long_offline_epoch_churn':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceFinalActiveOne',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobFinalActiveTwo',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charliePostReconnectLive',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'de002':
      return List<_ExpectedProofMessage>.generate(
        100,
        (index) => _ExpectedProofMessage(
          key: _de002Key(index),
          senderRole: 'alice',
          receiverRoles: const <String>['bob', 'charlie'],
        ),
      );
    case 'de003':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceExplicit',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'de007':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceZeroPeer',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'de017':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'charliePostAddOutOfOrder',
          senderRole: 'charlie',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'charliePreRemovalBeforeEvent',
          senderRole: 'charlie',
          receiverRoles: <String>['bob'],
        ),
      ];
    case 'ir001':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceMissedWhileBobOffline1',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceMissedWhileBobOffline2',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceMissedWhileBobOffline3',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceLiveAfterBobDrain',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'ir015':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceIr015Text',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr015Quote',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr015Image',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr015Video',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr015File',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr015Gif',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr015Voice',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'ir016':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceIr016Expired1',
          senderRole: 'alice',
          receiverRoles: <String>['charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr016Expired2',
          senderRole: 'alice',
          receiverRoles: <String>['charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr016Expired3',
          senderRole: 'alice',
          receiverRoles: <String>['charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr016Expired4',
          senderRole: 'alice',
          receiverRoles: <String>['charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr016Retained1',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr016Retained2',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceIr016Retained3',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'pl002':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'alicePl002MediaOnly',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
          allowEmptyText: true,
        ),
      ];
    case 'private_online_add':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterDanaAdd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie', 'dana'],
        ),
        _ExpectedProofMessage(
          key: 'bobAfterDanaAdd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie', 'dana'],
        ),
        _ExpectedProofMessage(
          key: 'danaAfterJoin',
          senderRole: 'dana',
          receiverRoles: <String>['alice', 'bob', 'charlie'],
        ),
      ];
    case 'private_offline_add':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterDanaOfflineAdd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie', 'dana'],
        ),
        _ExpectedProofMessage(
          key: 'bobAfterDanaOfflineAdd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie', 'dana'],
        ),
        _ExpectedProofMessage(
          key: 'aliceLiveAfterDanaDrain',
          senderRole: 'alice',
          receiverRoles: <String>['dana'],
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
    case 'private_non_friend_member_delivery':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceNonFriendToDana',
          senderRole: 'alice',
          receiverRoles: <String>['dana'],
        ),
        _ExpectedProofMessage(
          key: 'bobNonFriendToDana',
          senderRole: 'bob',
          receiverRoles: <String>['dana'],
        ),
      ];
    case 'private_admin_role_transfer_delivery':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceRemovedWindowAfterDemotion',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'bobRemovedWindowAfterAliceDemotion',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
        _ExpectedProofMessage(
          key: 'aliceAfterCharlieReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobAfterCharlieReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieAfterRoleReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'private_history_retention':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceBeforeHistoryRemoval',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'alicePostHistoryRemoval',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'bobPostHistoryRemoval',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
      ];
    case 'private_invite_terminal_states':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterInviteTerminalStates',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'bobAfterInviteTerminalStates',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
      ];
    case 'private_stale_invite_readd':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceDuringStaleInviteRemoval',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceAfterStaleInviteReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobAfterStaleInviteReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charlieAfterStaleInviteReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'private_stale_lower_key_update':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterStaleLowerUpdate',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'private_same_epoch_key_conflict':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterSameEpochConflict',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'private_partial_key_distribution':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterPartialKeyDistributionFailure',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
      ];
    case 'gm004':
    case 'private_online_remove':
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
    case 'private_offline_remove':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceAfterCharlieOfflineRemove',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'bobAfterCharlieOfflineRemove',
          senderRole: 'bob',
          receiverRoles: <String>['alice'],
        ),
      ];
    case 'gm006':
    case 'private_late_leave_readd':
    case 'private_rotated_device_readd':
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
    case 'private_same_user_multi_device_readd':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceDuringRa013Removal',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'aliceAfterRa013PhoneAccept',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceAfterRa013TabletAccept',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie', 'dana'],
        ),
        _ExpectedProofMessage(
          key: 'charlieTabletAfterRa013Accept',
          senderRole: 'dana',
          expectedSenderPeerRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
        ),
      ];
    case 'private_offline_readd':
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
        _ExpectedProofMessage(
          key: 'bobAfterOfflineReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'private_readd_current':
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
        _ExpectedProofMessage(
          key: 'aliceAfterCharlieRestart',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobAfterReaddCurrent',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'private_readd_active_members':
      return _ra017ExpectedMessages();
    case 'private_readd_alternating_churn':
    case 'private_network_chaos_invariants':
      return _ra018ExpectedMessages();
    case 'private_readd_cycles':
      return const <_ExpectedProofMessage>[];
    case 'private_rapid_readd':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceDuringRapidRemove',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'alicePostRapidReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobPostRapidReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
      ];
    case 'private_timeline_truth':
      return const <_ExpectedProofMessage>[
        _ExpectedProofMessage(
          key: 'aliceBeforeTimelineRemoval',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'aliceDuringTimelineRemoval',
          senderRole: 'alice',
          receiverRoles: <String>['bob'],
        ),
        _ExpectedProofMessage(
          key: 'alicePostTimelineReadd',
          senderRole: 'alice',
          receiverRoles: <String>['bob', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'bobPostTimelineReadd',
          senderRole: 'bob',
          receiverRoles: <String>['alice', 'charlie'],
        ),
        _ExpectedProofMessage(
          key: 'charliePostTimelineReadd',
          senderRole: 'charlie',
          receiverRoles: <String>['alice', 'bob'],
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
  if (scenario == 'gm001') {
    _validateDe001LiveDeliveryProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'de002') {
    _validateDe002OrderedDeliveryProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'de003') {
    _validateDe003MessageIdProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'de007') {
    _validateDe007ZeroPeerDeliveryProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'de017') {
    _validateDe017MembershipOrderingProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'ir001') {
    _validateIr001OfflineReconnectProof(byRole: byRole, failures: failures);
    return;
  }
  if (scenario == 'ir015') {
    _validateIr015VariantReplayProof(byRole: byRole, failures: failures);
    return;
  }
  if (scenario == 'ir016') {
    _validateIr016RetentionCutoffProof(byRole: byRole, failures: failures);
    return;
  }
  if (scenario == 'pl002') {
    _validatePl002MediaOnlyProof(byRole: byRole, failures: failures);
    return;
  }
  if (scenario == 'private_abc_create') {
    _validatePrivateAbcCreateReusableProof(byRole: byRole, failures: failures);
    _validateMl001CreateInviteProofFields(byRole: byRole, failures: failures);
    return;
  }
  if (scenario == 'private_reaction_roundtrip') {
    _validatePl009ReactionRoundtripProof(byRole: byRole, failures: failures);
    return;
  }
  if (scenario == 'private_full_mesh_online') {
    _validateNw001FullMeshProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_relay_only_delivery') {
    _validateNw002RelayOnlyDeliveryProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_partition_readd_heal') {
    _validateNw003PartitionReaddHealProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_relay_reconnect_group_recovery') {
    _validateNw004RelayReconnectRecoveryProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_peer_disconnect_not_removal') {
    _validateNw006DisconnectNotRemovalProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_background_resume_group_delivery') {
    _validateNw010BackgroundResumeDeliveryProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_long_offline_epoch_churn') {
    _validateNw012LongOfflineEpochConvergenceProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_online_add') {
    _validatePrivateReusableProofFields(
      scenario: scenario,
      byRole: byRole,
      failures: failures,
    );
    _validateMl002OnlineAddProofFields(byRole: byRole, failures: failures);
    return;
  }
  if (scenario == 'private_offline_add') {
    _validatePrivateReusableProofFields(
      scenario: scenario,
      byRole: byRole,
      failures: failures,
    );
    _validateMl003OfflineAddProofFields(byRole: byRole, failures: failures);
    return;
  }
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
  if (scenario == 'private_concurrent_admin_membership_edits') {
    _validateMl012ConcurrentAdminMembershipEditsProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_timeline_truth') {
    _validateMl015TimelineTruthProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_non_friend_member_delivery') {
    _validateMl016NonFriendDeliveryProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_admin_role_transfer_delivery') {
    _validateMl020AdminRoleDeliveryProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_history_retention') {
    _validateMl017HistoryRetentionProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_invite_terminal_states') {
    _validateMl018InviteTerminalProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_stale_invite_readd') {
    _validateMl019StaleInviteProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    _validateKe016StaleReinviteProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    _validateRa004StaleInviteBeforeReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_stale_lower_key_update') {
    _validateKe003StaleLowerKeyUpdateProof(byRole: byRole, failures: failures);
    return;
  }
  if (scenario == 'private_same_epoch_key_conflict') {
    _validateKe005SameEpochKeyConflictProof(byRole: byRole, failures: failures);
    return;
  }
  if (scenario == 'private_partial_key_distribution') {
    _validateKe015PartialKeyDistributionProof(
      byRole: byRole,
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
  if (scenario == 'private_online_remove') {
    _validateMl005OnlineRemovalProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    _validateKe006RemovalKeyRotationProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    _validatePl006RemovedMediaProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_offline_remove') {
    _validateMl006OfflineRemovalProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    _validateIr004PostRemovalReplayProof(
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
  if (scenario == 'private_offline_readd') {
    _validateRa003OfflineReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_late_leave_readd') {
    _validateRa011LateLeaveReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_rotated_device_readd') {
    _validateRa012RotatedDeviceReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_same_user_multi_device_readd') {
    _validateRa013SameUserMultiDeviceReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_readd_current') {
    _validateMl007ReaddCurrentProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    _validatePl004QuoteReaddLiveProof(byRole: byRole, failures: failures);
    _validatePl007ReaddMediaProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    _validateRa002OnlineSubscribedReaddProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    _validateKe008ReaddActivationProof(byRole: byRole, failures: failures);
    _validateKe010KeyBeforeConfigProof(byRole: byRole, failures: failures);
    _validateKe011DelayedOldKeyAfterReaddProof(
      byRole: byRole,
      failures: failures,
    );
    _validateRa006DelayedOldKeyAfterReaddProof(
      byRole: byRole,
      failures: failures,
    );
    _validateRa007PartitionedObserverReaddProof(
      byRole: byRole,
      failures: failures,
    );
    _validateRa008PartitionedRemovedReaddProof(
      byRole: byRole,
      failures: failures,
    );
    _validateRa009FirstReaddPublishProof(byRole: byRole, failures: failures);
    _validateRa010ReaddIncomingRestartProof(byRole: byRole, failures: failures);
    _validateRa014OldKeyPublishAfterReaddProof(
      byRole: byRole,
      failures: failures,
    );
    _validateRa015AlreadyJoinedReaddRefreshProof(
      byRole: byRole,
      failures: failures,
    );
    _validateRa016RemovedIntervalReplayProof(
      byRole: byRole,
      failures: failures,
    );
    _validateKe012DelayedOldConfigAfterReaddProof(
      byRole: byRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_readd_active_members') {
    _validateRa017ActiveMemberChurnProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_readd_alternating_churn') {
    _validateRa018AlternatingChurnProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_network_chaos_invariants') {
    _validateNw014ChaosInvariantProof(
      byRole: byRole,
      peerIdByRole: peerIdByRole,
      failures: failures,
    );
    return;
  }
  if (scenario == 'private_readd_cycles') {
    _validateMl008CycleProof(byRole: byRole, failures: failures);
    return;
  }
  if (scenario == 'private_rapid_readd') {
    _validateMl009RapidReaddProof(
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
    _validateKe018HistoryReplayEpochWindowProof(
      byRole: byRole,
      failures: failures,
    );
    _validateIr005ReaddReplayProof(byRole: byRole, failures: failures);
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

void _validateDe001LiveDeliveryProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?['de001LiveDeliveryProof']);
    if (proof == null) {
      failures.add('$role: missing DE-001 live delivery proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'DE-001') {
      failures.add('$role: de001LiveDeliveryProof.rowId must be DE-001');
    }
  }

  final sentEntries = _mapList(byRole['alice']?['sentMessages'])
      .where((entry) => _stringValue(entry['key']) == 'aliceInitial')
      .toList(growable: false);
  final sent = sentEntries.length == 1 ? sentEntries.single : null;
  final sentGroupId = sent == null ? null : _stringValue(sent['groupId']);
  final sentMessageId = sent == null ? null : _stringValue(sent['messageId']);
  final sentTimestamp = sent == null ? null : _stringValue(sent['timestamp']);
  final sentKeyEpoch = sent == null ? null : _intValue(sent['keyEpoch']);

  final aliceProof = _mapValue(byRole['alice']?['de001LiveDeliveryProof']);
  if (aliceProof != null) {
    for (final field in const <String>[
      'sentLiveText',
      'bobReceiptSignalObserved',
      'charlieReceiptSignalObserved',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: 'de001LiveDeliveryProof',
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    if (_stringValue(aliceProof['sentGroupId']) !=
        byRole['alice']?['groupId']) {
      failures.add('alice: de001LiveDeliveryProof.sentGroupId mismatch');
    }
    if (_stringValue(aliceProof['sentMessageId']) != sentMessageId) {
      failures.add('alice: de001LiveDeliveryProof.sentMessageId mismatch');
    }
    if (_stringValue(aliceProof['sentTimestamp']) != sentTimestamp) {
      failures.add('alice: de001LiveDeliveryProof.sentTimestamp mismatch');
    }
    if (_intValue(aliceProof['sentKeyEpoch']) != sentKeyEpoch) {
      failures.add('alice: de001LiveDeliveryProof.sentKeyEpoch mismatch');
    }
  }

  if (sentGroupId == null || sentGroupId.isEmpty) {
    failures.add('alice: sent aliceInitial missing groupId for DE-001');
  }
  if (sentTimestamp == null || sentTimestamp.isEmpty) {
    failures.add('alice: sent aliceInitial missing timestamp for DE-001');
  }

  for (final role in const <String>['bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?['de001LiveDeliveryProof']);
    if (proof != null) {
      for (final field in const <String>[
        'receivedVisibleMessageOnce',
        'matchedGroupId',
        'matchedMessageId',
        'matchedSenderPeerId',
        'matchedTimestamp',
        'matchedEpoch',
        'incomingVisible',
      ]) {
        _requireTrueProof(
          role: role,
          proofName: 'de001LiveDeliveryProof',
          proof: proof,
          field: field,
          failures: failures,
        );
      }
    }

    final receivedEntries = _mapList(byRole[role]?['receivedMessages'])
        .where((entry) => _stringValue(entry['key']) == 'aliceInitial')
        .toList(growable: false);
    if (receivedEntries.length != 1 || sent == null) continue;
    final received = receivedEntries.single;
    if (_stringValue(received['groupId']) != sentGroupId) {
      failures.add('$role: received aliceInitial groupId mismatch');
    }
    if (_stringValue(received['messageId']) != sentMessageId) {
      failures.add('$role: received aliceInitial DE-001 messageId mismatch');
    }
    if (_stringValue(received['senderPeerId']) != peerIdByRole['alice']) {
      failures.add('$role: received aliceInitial DE-001 sender mismatch');
    }
    if (_stringValue(received['timestamp']) != sentTimestamp) {
      failures.add('$role: received aliceInitial timestamp mismatch');
    }
    if (_intValue(received['keyEpoch']) != sentKeyEpoch) {
      failures.add('$role: received aliceInitial DE-001 keyEpoch mismatch');
    }
  }
}

String _de002Key(int index) =>
    'aliceSeq${(index + 1).toString().padLeft(3, '0')}';

List<String> _de002ExpectedKeys() =>
    List<String>.generate(100, (index) => _de002Key(index));

bool _sameStringList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _timestampsStrictlyIncreasing(List<Map<String, dynamic>> messages) {
  DateTime? previous;
  for (final message in messages) {
    final timestamp = DateTime.tryParse(
      _stringValue(message['timestamp']) ?? '',
    );
    if (timestamp == null) return false;
    final utc = timestamp.toUtc();
    if (previous != null && !utc.isAfter(previous)) return false;
    previous = utc;
  }
  return true;
}

void _validateDe002OrderedDeliveryProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final expectedKeys = _de002ExpectedKeys();
  final aliceSent = _mapList(byRole['alice']?['sentMessages']);
  final aliceSentKeys = aliceSent
      .map((entry) => _stringValue(entry['key']))
      .whereType<String>()
      .toList(growable: false);
  final aliceProof = _mapValue(byRole['alice']?['de002OrderedDeliveryProof']);
  if (aliceProof == null) {
    failures.add('alice: missing DE-002 ordered delivery proof fields');
  } else {
    if (_stringValue(aliceProof['rowId']) != 'DE-002') {
      failures.add('alice: de002OrderedDeliveryProof.rowId must be DE-002');
    }
    for (final field in const <String>[
      'sentAllMessages',
      'preservedSendOrder',
      'timestampsStrictlyIncreasing',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: 'de002OrderedDeliveryProof',
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(aliceProof['sentCount']) != expectedKeys.length) {
      failures.add('alice: de002OrderedDeliveryProof.sentCount must be 100');
    }
    if (_stringValue(aliceProof['firstKey']) != expectedKeys.first) {
      failures.add('alice: de002OrderedDeliveryProof.firstKey mismatch');
    }
    if (_stringValue(aliceProof['lastKey']) != expectedKeys.last) {
      failures.add('alice: de002OrderedDeliveryProof.lastKey mismatch');
    }
    if (!_sameStringList(
      _stringList(aliceProof['orderedKeys']),
      expectedKeys,
    )) {
      failures.add('alice: de002OrderedDeliveryProof.orderedKeys mismatch');
    }
  }
  if (!_sameStringList(aliceSentKeys, expectedKeys)) {
    failures.add('alice: sent DE-002 keys are not in sequence order');
  }
  if (!_timestampsStrictlyIncreasing(aliceSent)) {
    failures.add('alice: sent DE-002 timestamps are not strictly increasing');
  }

  for (final role in const <String>['bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?['de002OrderedDeliveryProof']);
    final received = _mapList(byRole[role]?['receivedMessages']);
    final receivedKeys = received
        .map((entry) => _stringValue(entry['key']))
        .whereType<String>()
        .toList(growable: false);
    if (proof == null) {
      failures.add('$role: missing DE-002 ordered delivery proof fields');
    } else {
      if (_stringValue(proof['rowId']) != 'DE-002') {
        failures.add('$role: de002OrderedDeliveryProof.rowId must be DE-002');
      }
      for (final field in const <String>[
        'receivedAllMessagesOnce',
        'preservedPerSenderOrder',
        'matchedSenderPeerId',
        'timestampsStrictlyIncreasing',
      ]) {
        _requireTrueProof(
          role: role,
          proofName: 'de002OrderedDeliveryProof',
          proof: proof,
          field: field,
          failures: failures,
        );
      }
      if (_intValue(proof['receivedCount']) != expectedKeys.length) {
        failures.add(
          '$role: de002OrderedDeliveryProof.receivedCount must be 100',
        );
      }
      if (_intValue(proof['expectedCount']) != expectedKeys.length) {
        failures.add(
          '$role: de002OrderedDeliveryProof.expectedCount must be 100',
        );
      }
      if (_stringValue(proof['firstKey']) != expectedKeys.first) {
        failures.add('$role: de002OrderedDeliveryProof.firstKey mismatch');
      }
      if (_stringValue(proof['lastKey']) != expectedKeys.last) {
        failures.add('$role: de002OrderedDeliveryProof.lastKey mismatch');
      }
      if (!_sameStringList(_stringList(proof['orderedKeys']), expectedKeys)) {
        failures.add('$role: de002OrderedDeliveryProof.orderedKeys mismatch');
      }
    }
    if (!_sameStringList(receivedKeys, expectedKeys)) {
      failures.add('$role: received DE-002 keys are not in sequence order');
    }
    if (!_timestampsStrictlyIncreasing(received)) {
      failures.add(
        '$role: received DE-002 timestamps are not strictly increasing',
      );
    }
    final alicePeerId = peerIdByRole['alice'];
    if (alicePeerId != null &&
        received.any(
          (entry) => _stringValue(entry['senderPeerId']) != alicePeerId,
        )) {
      failures.add('$role: received DE-002 sender mismatch');
    }
  }
}

void _validateDe003MessageIdProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final sentEntries = _mapList(byRole['alice']?['sentMessages'])
      .where((entry) => _stringValue(entry['key']) == 'aliceExplicit')
      .toList(growable: false);
  final sent = sentEntries.length == 1 ? sentEntries.single : null;
  final sentMessageId = sent == null ? null : _stringValue(sent['messageId']);

  final aliceProof = _mapValue(byRole['alice']?['de003MessageIdProof']);
  if (aliceProof == null) {
    failures.add('alice: missing DE-003 message id proof fields');
  } else {
    if (_stringValue(aliceProof['rowId']) != 'DE-003') {
      failures.add('alice: de003MessageIdProof.rowId must be DE-003');
    }
    for (final field in const <String>[
      'publishPathMessageIdPreserved',
      'replayEnvelopeCoveredByHostGate',
      'retryPathCoveredByHostGate',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: 'de003MessageIdProof',
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final requested = _stringValue(aliceProof['requestedMessageId']);
    final returned = _stringValue(aliceProof['returnedMessageId']);
    if (requested == null || requested.isEmpty) {
      failures.add('alice: de003MessageIdProof requestedMessageId missing');
    }
    if (requested != sentMessageId) {
      failures.add('alice: de003MessageIdProof requestedMessageId mismatch');
    }
    if (returned != sentMessageId) {
      failures.add('alice: de003MessageIdProof returnedMessageId mismatch');
    }
  }

  for (final role in const <String>['bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?['de003MessageIdProof']);
    if (proof == null) {
      failures.add('$role: missing DE-003 message id proof fields');
    } else {
      if (_stringValue(proof['rowId']) != 'DE-003') {
        failures.add('$role: de003MessageIdProof.rowId must be DE-003');
      }
      for (final field in const <String>[
        'receivedExplicitMessageOnce',
        'matchedRequestedMessageId',
        'duplicateReplayDeduped',
      ]) {
        _requireTrueProof(
          role: role,
          proofName: 'de003MessageIdProof',
          proof: proof,
          field: field,
          failures: failures,
        );
      }
      if (_stringValue(proof['requestedMessageId']) != sentMessageId) {
        failures.add('$role: de003MessageIdProof requestedMessageId mismatch');
      }
      if (_stringValue(proof['receivedMessageId']) != sentMessageId) {
        failures.add('$role: de003MessageIdProof receivedMessageId mismatch');
      }
    }

    final receivedEntries = _mapList(byRole[role]?['receivedMessages'])
        .where((entry) => _stringValue(entry['key']) == 'aliceExplicit')
        .toList(growable: false);
    if (receivedEntries.length != 1 || sent == null) continue;
    final received = receivedEntries.single;
    if (_stringValue(received['messageId']) != sentMessageId) {
      failures.add('$role: received DE-003 messageId mismatch');
    }
    if (_stringValue(received['senderPeerId']) != peerIdByRole['alice']) {
      failures.add('$role: received DE-003 sender mismatch');
    }
  }
}

void _validateDe007ZeroPeerDeliveryProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  final sentEntries = _mapList(byRole['alice']?['sentMessages'])
      .where((entry) => _stringValue(entry['key']) == 'aliceZeroPeer')
      .toList(growable: false);
  final sent = sentEntries.length == 1 ? sentEntries.single : null;
  final sentMessageId = sent == null ? null : _stringValue(sent['messageId']);

  final aliceProof = _mapValue(byRole['alice']?['de007ZeroPeerProof']);
  if (aliceProof == null) {
    failures.add('alice: missing DE-007 zero-peer proof fields');
  } else {
    if (_stringValue(aliceProof['rowId']) != 'DE-007') {
      failures.add('alice: de007ZeroPeerProof.rowId must be DE-007');
    }
    for (final field in const <String>[
      'sendResultSuccessNoPeers',
      'inboxStored',
      'publishedBeforeReceiversJoined',
      'activeRecipientsCovered',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: 'de007ZeroPeerProof',
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(aliceProof['activeRecipientCount']) != 2) {
      failures.add('alice: de007ZeroPeerProof.activeRecipientCount must be 2');
    }
    if (_stringValue(aliceProof['messageId']) != sentMessageId) {
      failures.add('alice: de007ZeroPeerProof.messageId mismatch');
    }
  }

  for (final role in const <String>['bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?['de007ZeroPeerProof']);
    if (proof == null) {
      failures.add('$role: missing DE-007 zero-peer proof fields');
    } else {
      if (_stringValue(proof['rowId']) != 'DE-007') {
        failures.add('$role: de007ZeroPeerProof.rowId must be DE-007');
      }
      for (final field in const <String>[
        'joinedAfterAliceSend',
        'receivedViaOfflineReplay',
        'receivedVisibleMessageOnce',
        'matchedMessageId',
        'matchedSenderPeerId',
      ]) {
        _requireTrueProof(
          role: role,
          proofName: 'de007ZeroPeerProof',
          proof: proof,
          field: field,
          failures: failures,
        );
      }
      if (_stringValue(proof['messageId']) != sentMessageId) {
        failures.add('$role: de007ZeroPeerProof.messageId mismatch');
      }
    }

    final receivedEntries = _mapList(byRole[role]?['receivedMessages'])
        .where((entry) => _stringValue(entry['key']) == 'aliceZeroPeer')
        .toList(growable: false);
    if (receivedEntries.length != 1) {
      failures.add('$role: expected exactly one DE-007 received message');
      continue;
    }
    final received = receivedEntries.single;
    if (_stringValue(received['messageId']) != sentMessageId) {
      failures.add('$role: received DE-007 message id mismatch');
    }
    final alicePeerId = peerIdByRole['alice'];
    if (alicePeerId != null &&
        _stringValue(received['senderPeerId']) != alicePeerId) {
      failures.add('$role: received DE-007 sender mismatch');
    }
    if (_intValue(received['persistedCount']) != 1) {
      failures.add('$role: DE-007 message must persist exactly once');
    }
  }
}

void _validateDe017MembershipOrderingProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'de017MembershipOrderingProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final expectedCharliePeerId = peerIdByRole['charlie'];

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'DE-017') {
      failures.add('$role: $proofName.rowId must be DE-017');
    }
  }

  void requireRemovedPeerId(String role, Map<String, dynamic> proof) {
    final removedPeerId = _stringValue(proof['removedPeerId']);
    if (expectedCharliePeerId != null &&
        removedPeerId != expectedCharliePeerId) {
      failures.add('$role: $proofName.removedPeerId must be charlie');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing DE-017 membership-ordering proof fields');
  } else {
    requireRowId('alice', aliceProof);
    requireRemovedPeerId('alice', aliceProof);
    for (final field in const <String>[
      'addedCharlieBeforePublishingMemberEvent',
      'publishedMemberEventAfterCharlieContent',
      'removedCharlieAfterPostRemovalContent',
      'bobConfirmedAddRepair',
      'bobConfirmedRemovalRepair',
      'memberListExcludesCharlie',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing DE-017 membership-ordering proof fields');
  } else {
    requireRowId('bob', bobProof);
    requireRemovedPeerId('bob', bobProof);
    for (final field in const <String>[
      'bufferedContentBeforeMemberAdd',
      'deliveredPostAddAfterMembership',
      'retainedPreRemovalContent',
      'repairedPostRemovalContent',
      'memberListExcludesCharlie',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(bobProof['postRemovalPersistedCountAfterRepair']) != 0) {
      failures.add(
        'bob: $proofName.postRemovalPersistedCountAfterRepair must be 0',
      );
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing DE-017 membership-ordering proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    requireRemovedPeerId('charlie', charlieProof);
    for (final field in const <String>[
      'sentPostAddBeforeMemberEvent',
      'sentPreRemovalBeforeRemovalEvent',
      'sentPostRemovalBeforeRemovalEvent',
      'postRemovalAcceptedByLocalSend',
      'selfRemovedAfterRemoval',
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

  final charlieSentKeys = _mapList(byRole['charlie']?['sentMessages'])
      .map((entry) => _stringValue(entry['key']))
      .whereType<String>()
      .toList(growable: false);
  for (final key in const <String>[
    'charliePostAddOutOfOrder',
    'charliePreRemovalBeforeEvent',
    'charliePostRemovalBeforeEvent',
  ]) {
    final count = charlieSentKeys.where((entry) => entry == key).length;
    if (count != 1) {
      failures.add('charlie: sent $key count=$count; requires exactly one');
    }
  }
}

void _validateIr001OfflineReconnectProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ir001OfflineReconnectProof';
  const missedKeys = <String>[
    'aliceMissedWhileBobOffline1',
    'aliceMissedWhileBobOffline2',
    'aliceMissedWhileBobOffline3',
  ];
  const liveKey = 'aliceLiveAfterBobDrain';
  final expectedAllKeys = <String>[...missedKeys, liveKey];

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'IR-001') {
      failures.add('$role: $proofName.rowId must be IR-001');
    }
  }

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  if (aliceProof == null) {
    failures.add('alice: missing IR-001 offline reconnect proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'bobWasJoinedBeforeOffline',
      'bobOfflineBeforeMissedSendObserved',
      'bobDrainCompletedBeforeLiveSend',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(aliceProof['missedMessageCount']) != missedKeys.length) {
      failures.add(
        'alice: $proofName.missedMessageCount must be ${missedKeys.length}',
      );
    }
    if (!_sameStringList(_stringList(aliceProof['missedKeys']), missedKeys)) {
      failures.add('alice: $proofName.missedKeys mismatch');
    }
    if (_stringValue(aliceProof['liveKey']) != liveKey) {
      failures.add('alice: $proofName.liveKey must be $liveKey');
    }
  }

  final bobProof = _mapValue(byRole['bob']?[proofName]);
  if (bobProof == null) {
    failures.add('bob: missing IR-001 offline reconnect proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'restoredActiveMembershipBeforeDrain',
      'receivedAllMissedExactlyOnce',
      'usedOfflineDrainForMissed',
      'liveAfterDrainReceived',
      'liveAfterDrainWasLive',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(bobProof['drainedMissedCount']) != missedKeys.length) {
      failures.add(
        'bob: $proofName.drainedMissedCount must be ${missedKeys.length}',
      );
    }
    if (!_sameStringList(_stringList(bobProof['missedKeys']), missedKeys)) {
      failures.add('bob: $proofName.missedKeys mismatch');
    }
    if (_stringValue(bobProof['liveKey']) != liveKey) {
      failures.add('bob: $proofName.liveKey must be $liveKey');
    }
  }

  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  if (charlieProof == null) {
    failures.add('charlie: missing IR-001 offline reconnect proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'onlineControlReceivedMissedLive',
      'onlineControlReceivedLiveAfterReconnect',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(charlieProof['onlineControlMissedCount']) !=
        missedKeys.length) {
      failures.add(
        'charlie: $proofName.onlineControlMissedCount must be '
        '${missedKeys.length}',
      );
    }
  }

  for (final role in const <String>['bob', 'charlie']) {
    final receivedKeys = _mapList(byRole[role]?['receivedMessages'])
        .map((entry) => _stringValue(entry['key']))
        .whereType<String>()
        .toList(growable: false);
    for (final key in expectedAllKeys) {
      final count = receivedKeys.where((entry) => entry == key).length;
      if (count != 1) {
        failures.add('$role: received $key count=$count; requires exactly one');
      }
    }
  }
}

void _validateIr015VariantReplayProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ir015VariantReplayProof';
  const variantKeys = <String>[
    'aliceIr015Text',
    'aliceIr015Quote',
    'aliceIr015Image',
    'aliceIr015Video',
    'aliceIr015File',
    'aliceIr015Gif',
    'aliceIr015Voice',
  ];
  const mediaKeys = <String>[
    'aliceIr015Image',
    'aliceIr015Video',
    'aliceIr015File',
    'aliceIr015Gif',
    'aliceIr015Voice',
  ];

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'IR-015') {
      failures.add('$role: $proofName.rowId must be IR-015');
    }
  }

  Map<String, dynamic>? receivedEntry(String role, String key) {
    final entries = _mapList(byRole[role]?['receivedMessages'])
        .where((entry) => _stringValue(entry['key']) == key)
        .toList(growable: false);
    return entries.length == 1 ? entries.single : null;
  }

  List<Map<String, dynamic>> receivedMedia(Map<String, dynamic> received) {
    final media = _mapList(received['media']);
    if (media.isNotEmpty) return media;
    return _mapList(received['mediaAttachments']);
  }

  bool mediaOk(Map<String, dynamic>? received, String key) {
    if (received == null) return false;
    final media = receivedMedia(received);
    if (media.length != 1) return false;
    final attachment = media.single;
    switch (key) {
      case 'aliceIr015Image':
        return _stringValue(attachment['mime']) == 'image/jpeg' &&
            _stringValue(attachment['mediaType']) == 'image';
      case 'aliceIr015Video':
        return _stringValue(attachment['mime']) == 'video/mp4' &&
            _stringValue(attachment['mediaType']) == 'video' &&
            _intValue(attachment['durationMs']) == 4200;
      case 'aliceIr015File':
        return _stringValue(attachment['mime']) == 'application/octet-stream' &&
            _stringValue(attachment['mediaType']) == 'file';
      case 'aliceIr015Gif':
        return _stringValue(attachment['mime']) == 'image/gif' &&
            _stringValue(attachment['mediaType']) == 'image';
      case 'aliceIr015Voice':
        return _stringValue(attachment['mime']) == 'audio/mp4' &&
            _stringValue(attachment['mediaType']) == 'audio' &&
            _intValue(attachment['durationMs']) == 3100;
      default:
        return true;
    }
  }

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  if (aliceProof == null) {
    failures.add('alice: missing IR-015 variant replay proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'bobWasJoinedBeforeOffline',
      'bobOfflineBeforeVariantSendObserved',
      'charlieOnlineReceivedAllVariants',
      'bobDrainCompletedAfterAllVariants',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    if (!_sameStringList(_stringList(aliceProof['variantKeys']), variantKeys)) {
      failures.add('alice: $proofName.variantKeys mismatch');
    }
    if (!_sameStringList(
      _stringList(aliceProof['mediaVariantKeys']),
      mediaKeys,
    )) {
      failures.add('alice: $proofName.mediaVariantKeys mismatch');
    }
    if (_stringValue(aliceProof['quoteTargetMessageId']) == null) {
      failures.add('alice: $proofName.quoteTargetMessageId is required');
    }
  }

  final aliceTextSent = _mapList(byRole['alice']?['sentMessages'])
      .where((entry) => _stringValue(entry['key']) == 'aliceIr015Text')
      .toList(growable: false);
  final textMessageId = aliceTextSent.length == 1
      ? _stringValue(aliceTextSent.single['messageId'])
      : null;

  final bobProof = _mapValue(byRole['bob']?[proofName]);
  if (bobProof == null) {
    failures.add('bob: missing IR-015 variant replay proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'restoredActiveMembershipBeforeDrain',
      'receivedAllVariantsExactlyOnce',
      'usedOfflineDrainForAllVariants',
      'quoteRehydrated',
      'mediaVariantsRehydrated',
      'matchedKeyEpochs',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(bobProof['drainedVariantCount']) != variantKeys.length) {
      failures.add(
        'bob: $proofName.drainedVariantCount must be ${variantKeys.length}',
      );
    }
    if (!_sameStringList(_stringList(bobProof['variantKeys']), variantKeys)) {
      failures.add('bob: $proofName.variantKeys mismatch');
    }
  }

  final bobQuote = receivedEntry('bob', 'aliceIr015Quote');
  if (textMessageId != null &&
      _stringValue(bobQuote?['quotedMessageId']) != textMessageId) {
    failures.add('bob: $proofName quote did not reference text variant');
  }
  for (final key in mediaKeys) {
    if (!mediaOk(receivedEntry('bob', key), key)) {
      failures.add('bob: $proofName $key media descriptor mismatch');
    }
  }

  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  if (charlieProof == null) {
    failures.add('charlie: missing IR-015 variant replay proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'onlineControlReceivedAllVariantsLive',
      'quoteRehydrated',
      'mediaVariantsRehydrated',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(charlieProof['onlineControlVariantCount']) !=
        variantKeys.length) {
      failures.add(
        'charlie: $proofName.onlineControlVariantCount must be '
        '${variantKeys.length}',
      );
    }
  }

  final charlieQuote = receivedEntry('charlie', 'aliceIr015Quote');
  if (textMessageId != null &&
      _stringValue(charlieQuote?['quotedMessageId']) != textMessageId) {
    failures.add('charlie: $proofName quote did not reference text variant');
  }
  for (final key in mediaKeys) {
    if (!mediaOk(receivedEntry('charlie', key), key)) {
      failures.add('charlie: $proofName $key media descriptor mismatch');
    }
  }
}

void _validateIr016RetentionCutoffProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ir016RetentionCutoffProof';
  const expiredKeys = <String>[
    'aliceIr016Expired1',
    'aliceIr016Expired2',
    'aliceIr016Expired3',
    'aliceIr016Expired4',
  ];
  const retainedKeys = <String>[
    'aliceIr016Retained1',
    'aliceIr016Retained2',
    'aliceIr016Retained3',
  ];

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'IR-016') {
      failures.add('$role: $proofName.rowId must be IR-016');
    }
  }

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  if (aliceProof == null) {
    failures.add('alice: missing IR-016 retention cutoff proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'bobWasJoinedBeforeOffline',
      'bobOfflineBeforeExpiredSendObserved',
      'sentExpiredBeyondRetention',
      'sentRetainedWithinRetention',
      'bobDrainCompletedAfterRetained',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    if (_stringValue(aliceProof['activeOfflineRecipientRole']) != 'bob') {
      failures.add('alice: $proofName.activeOfflineRecipientRole must be bob');
    }
    if (!_sameStringList(_stringList(aliceProof['expiredKeys']), expiredKeys)) {
      failures.add('alice: $proofName.expiredKeys mismatch');
    }
    if (!_sameStringList(
      _stringList(aliceProof['retainedKeys']),
      retainedKeys,
    )) {
      failures.add('alice: $proofName.retainedKeys mismatch');
    }
    final sentCount = _intValue(aliceProof['manyMessagesSentCount']);
    if (sentCount != expiredKeys.length + retainedKeys.length) {
      failures.add(
        'alice: $proofName.manyMessagesSentCount must be '
        '${expiredKeys.length + retainedKeys.length}',
      );
    }
  }

  final bobProof = _mapValue(byRole['bob']?[proofName]);
  if (bobProof == null) {
    failures.add('bob: missing IR-016 retention cutoff proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'restoredActiveMembershipBeforeDrain',
      'receivedRetainedExactlyOnce',
      'usedOfflineDrainForRetained',
      'expiredBacklogSkipped',
      'lastBacklogExpiredAtRecorded',
      'lastBacklogRetainedAtRecorded',
      'explicitRetentionStateRecorded',
      'noSilentCompleteState',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(bobProof['retentionWindowDays']) != 7) {
      failures.add('bob: $proofName.retentionWindowDays must be 7');
    }
    if (_intValue(bobProof['expiredVisibleCount']) != 0) {
      failures.add('bob: $proofName.expiredVisibleCount must be 0');
    }
    if (_intValue(bobProof['drainedRetainedCount']) != retainedKeys.length) {
      failures.add(
        'bob: $proofName.drainedRetainedCount must be ${retainedKeys.length}',
      );
    }
    if (!_sameStringList(_stringList(bobProof['expiredKeys']), expiredKeys)) {
      failures.add('bob: $proofName.expiredKeys mismatch');
    }
    if (!_sameStringList(_stringList(bobProof['retainedKeys']), retainedKeys)) {
      failures.add('bob: $proofName.retainedKeys mismatch');
    }
  }

  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  if (charlieProof == null) {
    failures.add('charlie: missing IR-016 retention cutoff proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    _requireTrueProof(
      role: 'charlie',
      proofName: proofName,
      proof: charlieProof,
      field: 'onlineControlReceivedAllMessagesLive',
      failures: failures,
    );
    if (_intValue(charlieProof['onlineControlMessageCount']) !=
        expiredKeys.length + retainedKeys.length) {
      failures.add(
        'charlie: $proofName.onlineControlMessageCount must be '
        '${expiredKeys.length + retainedKeys.length}',
      );
    }
    if (_intValue(charlieProof['onlineControlExpiredCount']) !=
        expiredKeys.length) {
      failures.add(
        'charlie: $proofName.onlineControlExpiredCount must be '
        '${expiredKeys.length}',
      );
    }
    if (_intValue(charlieProof['onlineControlRetainedCount']) !=
        retainedKeys.length) {
      failures.add(
        'charlie: $proofName.onlineControlRetainedCount must be '
        '${retainedKeys.length}',
      );
    }
  }
}

void _validatePl002MediaOnlyProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'pl002MediaOnlyProof';
  const key = 'alicePl002MediaOnly';

  bool mediaOk(Map<String, dynamic>? entry) {
    if (entry == null) return false;
    if (_messageText(entry) != '') return false;
    final media = _mapList(entry['media']).isNotEmpty
        ? _mapList(entry['media'])
        : _mapList(entry['mediaAttachments']);
    if (media.length != 1) return false;
    final attachment = media.single;
    return _stringValue(attachment['mime']) == 'audio/mp4' &&
        _stringValue(attachment['mediaType']) == 'audio' &&
        _intValue(attachment['durationMs']) == 2200;
  }

  Map<String, dynamic>? entryFor(String role, String collectionName) {
    final entries = _mapList(byRole[role]?[collectionName])
        .where((entry) => _stringValue(entry['key']) == key)
        .toList(growable: false);
    return entries.length == 1 ? entries.single : null;
  }

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'PL-002') {
      failures.add('$role: $proofName.rowId must be PL-002');
    }
  }

  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  if (aliceProof == null) {
    failures.add('alice: missing PL-002 media-only proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'acceptedMediaOnly',
      'emptyTextPreserved',
      'mediaDescriptorPublished',
      'bobReceiptSignalObserved',
      'charlieReceiptSignalObserved',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (!mediaOk(entryFor('alice', 'sentMessages'))) {
    failures.add('alice: $proofName sent media-only descriptor mismatch');
  }

  for (final role in const <String>['bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing PL-002 media-only proof fields');
    } else {
      requireRowId(role, proof);
      for (final field in const <String>[
        'receivedVisibleMessageOnce',
        'emptyTextPreserved',
        'mediaDescriptorPersisted',
      ]) {
        _requireTrueProof(
          role: role,
          proofName: proofName,
          proof: proof,
          field: field,
          failures: failures,
        );
      }
      if (_intValue(proof['mediaCount']) != 1) {
        failures.add('$role: $proofName.mediaCount must be 1');
      }
    }

    if (!mediaOk(entryFor(role, 'receivedMessages'))) {
      failures.add('$role: $proofName received media-only descriptor mismatch');
    }
  }
}

void _validatePl009ReactionRoundtripProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  final aliceSent = _mapList(byRole['alice']?['sentMessages'])
      .where((entry) => _stringValue(entry['key']) == 'aliceReactionTarget')
      .toList(growable: false);
  final targetMessageId = aliceSent.length == 1
      ? _stringValue(aliceSent.single['messageId'])
      : null;
  if (targetMessageId == null || targetMessageId.isEmpty) {
    failures.add('alice: missing PL-009 aliceReactionTarget sent message');
  }

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?['pl009ReactionRoundtripProof']);
    if (proof == null) {
      failures.add('$role: missing pl009ReactionRoundtripProof');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'PL-009') {
      failures.add('$role: pl009ReactionRoundtripProof.rowId must be PL-009');
    }
    final activeRoles = _stringList(proof['activeRoles']).toSet();
    for (final expectedRole in const <String>['alice', 'bob', 'charlie']) {
      if (!activeRoles.contains(expectedRole)) {
        failures.add(
          '$role: pl009ReactionRoundtripProof.activeRoles missing $expectedRole',
        );
      }
    }
    if (targetMessageId != null &&
        _stringValue(proof['targetMessageId']) != targetMessageId) {
      failures.add(
        '$role: pl009ReactionRoundtripProof targetMessageId mismatch',
      );
    }
    if (_stringValue(proof['reactorRole']) != 'bob') {
      failures.add(
        '$role: pl009ReactionRoundtripProof.reactorRole must be bob',
      );
    }
    if (_stringValue(proof['reactionEmoji']) == null ||
        _stringValue(proof['reactionEmoji'])!.isEmpty) {
      failures.add('$role: pl009ReactionRoundtripProof missing reactionEmoji');
    }
    if (_stringValue(proof['reactionOutcome']) != 'success' ||
        proof['reactionAccepted'] != true) {
      failures.add('$role: PL-009 Bob reaction must publish successfully');
    }
    if (_stringValue(proof['observedByRole']) != role) {
      failures.add(
        '$role: pl009ReactionRoundtripProof observedByRole mismatch',
      );
    }
    if (proof['appliedOnceToTarget'] != true ||
        _intValue(proof['persistedReactionCount']) != 1) {
      failures.add(
        '$role: PL-009 reaction must apply exactly once to the target message',
      );
    }
    if ((role == 'alice' || role == 'charlie') &&
        proof['receivedViaGroupReactionStream'] != true) {
      failures.add(
        '$role: PL-009 reaction must arrive through group reaction stream',
      );
    }
    if (proof['aliceObservedSignal'] != true ||
        proof['charlieObservedSignal'] != true) {
      failures.add(
        '$role: PL-009 must prove Alice and Charlie observed Bob reaction',
      );
    }
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

void _validateMl012ConcurrentAdminMembershipEditsProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ml012ConcurrentAdminEditsProof';
  final expectedActivePeerIds = <String>{
    for (final role in const <String>['alice', 'bob', 'dana'])
      if (peerIdByRole[role] != null) peerIdByRole[role]!,
  };
  final configHashes = <String>{};

  bool hasSameMembers(Object? value, Set<String> expected) {
    final actual = _stringList(value).toSet();
    return actual.length == expected.length && actual.containsAll(expected);
  }

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'ML-012') {
      failures.add('$role: $proofName.rowId must be ML-012');
    }
  }

  void requireDeliveryOrders(String role, Map<String, dynamic> proof) {
    final orders = _stringList(proof['deliveryOrdersTested']).toSet();
    if (!orders.contains('add_then_remove') ||
        !orders.contains('remove_then_add')) {
      failures.add(
        '$role: $proofName.deliveryOrdersTested must include '
        'add_then_remove and remove_then_add',
      );
    }
  }

  void requireLiveProofMetadata(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['appPeerPlatform']) != 'ios_26_2_core_simulator') {
      failures.add(
        '$role: $proofName.appPeerPlatform must be ios_26_2_core_simulator',
      );
    }
    if (_stringValue(proof['concurrentAdminProofSource']) !=
        'app_peer_core_simulator') {
      failures.add(
        '$role: $proofName.concurrentAdminProofSource must be '
        'app_peer_core_simulator',
      );
    }
  }

  void requireExpectedMembers(String role, Map<String, dynamic> proof) {
    if (!hasSameMembers(proof['finalMemberPeerIds'], expectedActivePeerIds)) {
      failures.add(
        '$role: $proofName.finalMemberPeerIds must converge to alice/bob/dana',
      );
    }
    final activeMembers = _stringList(byRole[role]?['memberPeerIds']).toSet();
    if (activeMembers.contains(peerIdByRole['charlie'])) {
      failures.add('$role: active members must exclude removed Charlie');
    }
  }

  for (final role in const <String>['alice', 'bob', 'dana']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing ML-012 concurrent-admin proof fields');
      continue;
    }
    requireRowId(role, proof);
    requireDeliveryOrders(role, proof);
    requireLiveProofMetadata(role, proof);
    requireExpectedMembers(role, proof);
    for (final field in const <String>[
      'memberSetsConverged',
      'configHashesConverged',
      'independentAddPreserved',
      'removedCharlieExcluded',
      'sameTargetNewerReaddWins',
      'sameTargetTieRemoveWins',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final hash = _stringValue(proof['finalConfigStateHash']);
    if (hash == null || hash.isEmpty) {
      failures.add('$role: $proofName.finalConfigStateHash is required');
    } else {
      configHashes.add(hash);
    }
  }

  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  if (charlieProof == null) {
    failures.add('charlie: missing ML-012 concurrent-admin proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    requireDeliveryOrders('charlie', charlieProof);
    requireLiveProofMetadata('charlie', charlieProof);
    for (final field in const <String>[
      'charlieRemoved',
      'postRemovalGroupAbsent',
      'removedCharlieExcluded',
      'sameTargetTieRemoveWins',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
  }

  if (configHashes.length > 1) {
    failures.add('alice/bob/dana: ML-012 finalConfigStateHash mismatch');
  }
}

void _validateMl015TimelineTruthProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ml015TimelineTruthProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireSharedFields(String role, Map<String, dynamic>? proof) {
    if (proof == null) {
      failures.add('$role: missing ML-015 timeline-truth proof fields');
      return;
    }
    if (_stringValue(proof['rowId']) != 'ML-015') {
      failures.add('$role: $proofName.rowId must be ML-015');
    }
    for (final field in const <String>[
      'timelineOrderMatchesMembershipIntervals',
      'timelineContainsReadd',
      'memberListIncludesCharlie',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
  }

  requireSharedFields('alice', aliceProof);
  requireSharedFields('bob', bobProof);
  requireSharedFields('charlie', charlieProof);

  if (aliceProof != null) {
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlie',
      'sentBeforeRemovalMessage',
      'sentRemovedWindowBeforeReadd',
      'sentAlicePostReaddMessage',
      'receivedBobPostReaddMessage',
      'receivedCharliePostReaddMessage',
      'timelineContainsRemoval',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof != null) {
    for (final field in const <String>[
      'receivedBeforeRemovalMessage',
      'receivedRemovedWindowMessage',
      'receivedAlicePostReaddMessage',
      'sentBobPostReaddMessage',
      'receivedCharliePostReaddMessage',
      'timelineContainsRemoval',
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

  if (charlieProof != null) {
    for (final field in const <String>[
      'receivedBeforeRemovalMessage',
      'receivedAlicePostReaddMessage',
      'receivedBobPostReaddMessage',
      'sentCharliePostReaddMessage',
      'memberListIncludesAliceBob',
      'selfRemovalCleanupObserved',
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
      field: 'hasStaleEpochAfterReadd',
      failures: failures,
    );
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
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
    failures.add('alice/bob/charlie: ML-015 finalEpoch mismatch');
  }
}

void _validateMl016NonFriendDeliveryProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ml016NonFriendDeliveryProof';
  final expectedMembers = <String>{
    ?peerIdByRole['alice'],
    ?peerIdByRole['bob'],
    ?peerIdByRole['dana'],
  };

  for (final role in const <String>['alice', 'bob', 'dana']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing $proofName');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'ML-016') {
      failures.add('$role: $proofName.rowId must be ML-016');
    }
    if (_stringValue(proof['scenario']) !=
        'private_non_friend_member_delivery') {
      failures.add('$role: $proofName.scenario mismatch');
    }
    if (_stringValue(proof['proofRole']) != role) {
      failures.add('$role: $proofName.proofRole mismatch');
    }
    if (_stringValue(proof['appPeerPlatform']) != 'ios_26_2_core_simulator') {
      failures.add('$role: $proofName.appPeerPlatform must be iOS 26.2');
    }
    if (_stringValue(proof['nonFriendProofSource']) !=
        'app_peer_core_simulator') {
      failures.add(
        '$role: $proofName.nonFriendProofSource must be app_peer_core_simulator',
      );
    }
    for (final field in const <String>[
      'danaExplicitlyInvitedOrAdmitted',
      'aliceMessageReceived',
      'bobMessageReceived',
      'alicePersistedExactlyOnce',
      'bobPersistedExactlyOnce',
      'senderLabelsNonBlank',
      'finalMemberConvergence',
      'finalKeyConvergence',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'danaHasSavedAliceContact',
      'danaHasSavedBobContact',
      'messagesHiddenByContactGate',
    ]) {
      _requireFalseProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }

    final members = _stringList(byRole[role]?['memberPeerIds']).toSet();
    final missingMembers = expectedMembers.difference(members);
    if (missingMembers.isNotEmpty) {
      failures.add(
        '$role: $proofName active members missing ${missingMembers.join(', ')}',
      );
    }
  }

  final danaProof = _mapValue(byRole['dana']?[proofName]);
  if (danaProof == null) {
    return;
  }
  for (final field in const <String>[
    'aliceStableSenderLabel',
    'bobStableSenderLabel',
  ]) {
    final label = _stringValue(danaProof[field]);
    if (label == null || label.isEmpty || label == 'Unknown') {
      failures.add('dana: $proofName.$field must be stable and non-blank');
    }
  }
}

void _validateMl020AdminRoleDeliveryProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ml020AdminRoleDeliveryProof';
  const expectedRoleNames = <String, String>{
    'alice': 'writer',
    'bob': 'admin',
    'charlie': 'writer',
  };
  final expectedMembers = <String>{
    ?peerIdByRole['alice'],
    ?peerIdByRole['bob'],
    ?peerIdByRole['charlie'],
  };

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing $proofName');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'ML-020') {
      failures.add('$role: $proofName.rowId must be ML-020');
    }
    if (_stringValue(proof['scenario']) !=
        'private_admin_role_transfer_delivery') {
      failures.add('$role: $proofName.scenario mismatch');
    }
    if (_stringValue(proof['proofRole']) != role) {
      failures.add('$role: $proofName.proofRole mismatch');
    }
    if (_stringValue(proof['appPeerPlatform']) != 'ios_26_2_core_simulator') {
      failures.add('$role: $proofName.appPeerPlatform must be iOS 26.2');
    }
    if (_stringValue(proof['roleChangeProofSource']) !=
        'app_peer_core_simulator') {
      failures.add(
        '$role: $proofName.roleChangeProofSource must be app_peer_core_simulator',
      );
    }

    for (final field in const <String>[
      'bobPromotedToAdmin',
      'aliceDemotedButActive',
      'charlieRemovedBeforeReadd',
      'charlieReaddedAfterRemoval',
      'removedWindowDeliveryExcludedCharlie',
      'postReaddDeliveryToAllActiveMembers',
      'roleStateConverged',
      'memberStateConverged',
      'finalKeyConverged',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'creatorRequiredForDelivery',
      'adminOnlyDelivery',
      'charlieReceivedRemovedWindow',
    ]) {
      _requireFalseProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(proof['removedWindowPlaintextCount']) != 0) {
      failures.add('$role: $proofName.removedWindowPlaintextCount must be 0');
    }
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 1) {
      failures.add('$role: $proofName.finalEpoch must be positive');
    }

    final activeMembers = _stringList(byRole[role]?['activeMemberPeerIds']);
    final members =
        (activeMembers.isEmpty
                ? _stringList(byRole[role]?['memberPeerIds'])
                : activeMembers)
            .toSet();
    final missingMembers = expectedMembers.difference(members);
    if (missingMembers.isNotEmpty) {
      failures.add(
        '$role: $proofName active members missing ${missingMembers.join(', ')}',
      );
    }

    final finalRoles = _mapValue(proof['finalMemberRoles']);
    if (finalRoles == null) {
      failures.add('$role: $proofName.finalMemberRoles is required');
    } else {
      for (final expected in expectedRoleNames.entries) {
        if (_stringValue(finalRoles[expected.key]) != expected.value) {
          failures.add(
            '$role: $proofName.finalMemberRoles.${expected.key} must be ${expected.value}',
          );
        }
      }
    }
  }

  final charlieReceived = _mapList(
    byRole['charlie']?['receivedMessages'],
  ).map((message) => _stringValue(message['key'])).whereType<String>().toSet();
  for (final removedWindowKey in const <String>[
    'aliceRemovedWindowAfterDemotion',
    'bobRemovedWindowAfterAliceDemotion',
  ]) {
    if (charlieReceived.contains(removedWindowKey)) {
      failures.add('charlie: ML-020 must not receive $removedWindowKey');
    }
  }
}

void _validateMl017HistoryRetentionProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ml017HistoryRetentionProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'ML-017') {
      failures.add('$role: $proofName.rowId must be ML-017');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing ML-017 history-retention proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlie',
      'sentPreRemovalHistory',
      'sentPostRemovalMessage',
      'receivedBobPostRemovalMessage',
      'memberListExcludesCharlie',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing ML-017 history-retention proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'receivedPreRemovalHistory',
      'receivedAlicePostRemovalMessage',
      'sentBobPostRemovalMessage',
      'memberListExcludesCharlie',
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
    failures.add('charlie: missing ML-017 history-retention proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'retainedLocalGroup',
      'retainedPreRemovalHistory',
      'composeDisabled',
      'postRemovalSendRejected',
      'selfMemberRemoved',
      'noCurrentKey',
      'selfRemovalCleanupObserved',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'receivedAlicePostRemovalMessage',
      'receivedBobPostRemovalMessage',
      'postRemovalPublishAccepted',
    ]) {
      _requireFalseProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.postRemovalPlaintextCount must be 0');
    }
    final sendOutcome = _stringValue(charlieProof['postRemovalSendOutcome']);
    if (sendOutcome != 'unauthorized') {
      failures.add(
        'charlie: $proofName.postRemovalSendOutcome must be unauthorized',
      );
    }
  }
}

void _validateMl018InviteTerminalProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ml018InviteTerminalProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'ML-018') {
      failures.add('$role: $proofName.rowId must be ML-018');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing ML-018 invite-terminal proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'sentDeclineInvite',
      'sentExpiryInvite',
      'sentCancellationInvite',
      'sentCancellationRevocation',
      'sentPostTerminalMessage',
      'receivedBobPostTerminalMessage',
      'memberListExcludesCharlie',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final terminalPeerId = _stringValue(aliceProof['terminalInviteePeerId']);
    final expectedPeerId = peerIdByRole['charlie'];
    if (expectedPeerId != null && terminalPeerId != expectedPeerId) {
      failures.add('alice: $proofName.terminalInviteePeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing ML-018 invite-terminal proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'receivedAlicePostTerminalMessage',
      'sentBobPostTerminalMessage',
      'memberListExcludesCharlie',
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
    failures.add('charlie: missing ML-018 invite-terminal proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'receivedDeclineInvite',
      'declinedInvite',
      'declinePendingCleared',
      'declineTombstoneRecorded',
      'declinedDelayedCopyRejected',
      'receivedExpiryInvite',
      'expiredInviteRejected',
      'receivedCancellationInvite',
      'cancelledInviteRejected',
      'noLocalGroup',
      'noUsableKey',
      'postTerminalSendRejected',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'receivedAlicePostTerminalMessage',
      'receivedBobPostTerminalMessage',
      'postTerminalPublishAccepted',
    ]) {
      _requireFalseProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final plaintextCount = _intValue(
      charlieProof['postTerminalPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.postTerminalPlaintextCount must be 0');
    }
    final sendOutcome = _stringValue(charlieProof['postTerminalSendOutcome']);
    if (sendOutcome != 'groupNotFound' && sendOutcome != 'unauthorized') {
      failures.add(
        'charlie: $proofName.postTerminalSendOutcome must be groupNotFound '
        'or unauthorized',
      );
    }
  }
}

void _validateMl019StaleInviteProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ml019StaleInviteProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'ML-019') {
      failures.add('$role: $proofName.rowId must be ML-019');
    }
  }

  void requireFinalEpoch(String role, Map<String, dynamic> proof) {
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing ML-019 stale-invite proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'sentOldInvite',
      'removedCharlieAfterOldInvite',
      'rotatedAfterRemoval',
      'sentRemovedWindowMessage',
      'sentLatestInvite',
      'sentPostReaddMessage',
      'receivedBobPostReaddMessage',
      'receivedCharliePostReaddMessage',
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
    final stalePeerId = _stringValue(aliceProof['staleInviteePeerId']);
    final expectedPeerId = peerIdByRole['charlie'];
    if (expectedPeerId != null && stalePeerId != expectedPeerId) {
      failures.add('alice: $proofName.staleInviteePeerId must be charlie');
    }
    requireFinalEpoch('alice', aliceProof);
  }

  if (bobProof == null) {
    failures.add('bob: missing ML-019 stale-invite proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'observedOldAdd',
      'observedRemovalBeforeReadd',
      'receivedRemovedWindowMessage',
      'memberListIncludesCharlie',
      'hasCurrentEpoch',
      'receivedAlicePostReaddMessage',
      'sentBobPostReaddMessage',
      'receivedCharliePostReaddMessage',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireFinalEpoch('bob', bobProof);
  }

  if (charlieProof == null) {
    failures.add('charlie: missing ML-019 stale-invite proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'receivedOldInvite',
      'receivedLatestInvite',
      'delayedOldInviteRejected',
      'pendingRemainedLatestBeforeAccept',
      'acceptedLatestInvite',
      'staleAcceptRejected',
      'noKeyDowngradeAfterStaleAccept',
      'memberListIncludesAliceBobCharlie',
      'receivedAlicePostReaddMessage',
      'receivedBobPostReaddMessage',
      'sentCharliePostReaddMessage',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final oldEpoch = _intValue(charlieProof['oldInviteEpoch']);
    final latestEpoch = _intValue(charlieProof['latestInviteEpoch']);
    final acceptedEpoch = _intValue(charlieProof['acceptedEpoch']);
    if (oldEpoch == null || oldEpoch < 1) {
      failures.add('charlie: $proofName.oldInviteEpoch must be positive');
    }
    if (latestEpoch == null || latestEpoch < 2) {
      failures.add('charlie: $proofName.latestInviteEpoch must be >= 2');
    }
    if (oldEpoch != null && latestEpoch != null && oldEpoch >= latestEpoch) {
      failures.add('charlie: $proofName.oldInviteEpoch must be stale');
    }
    if (acceptedEpoch != null &&
        latestEpoch != null &&
        acceptedEpoch != latestEpoch) {
      failures.add(
        'charlie: $proofName.acceptedEpoch must match latestInviteEpoch',
      );
    }
    final delayedStoreResult = _stringValue(charlieProof['delayedStoreResult']);
    if (delayedStoreResult != 'invalidPayload' &&
        delayedStoreResult != 'revoked') {
      failures.add(
        'charlie: $proofName.delayedStoreResult must be invalidPayload or revoked',
      );
    }
    final staleAcceptResult = _stringValue(charlieProof['staleAcceptResult']);
    if (staleAcceptResult != 'invalidPayload' &&
        staleAcceptResult != 'revoked') {
      failures.add(
        'charlie: $proofName.staleAcceptResult must be invalidPayload or revoked',
      );
    }
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
    requireFinalEpoch('charlie', charlieProof);
  }
}

void _validateKe016StaleReinviteProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ke016StaleReinviteProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'KE-016') {
      failures.add('$role: $proofName.rowId must be KE-016');
    }
  }

  void requireFinalEpoch(String role, Map<String, dynamic> proof) {
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing KE-016 stale re-invite proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'sentEpochNInvite',
      'rotatedToNextEpochBeforeAccept',
      'sentCurrentEpochInvite',
      'sentPostAcceptAtCurrentEpoch',
      'receivedBobPostAcceptAtCurrentEpoch',
      'receivedCharliePostAcceptAtCurrentEpoch',
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
    final stalePeerId = _stringValue(aliceProof['staleInviteePeerId']);
    final expectedPeerId = peerIdByRole['charlie'];
    if (expectedPeerId != null && stalePeerId != expectedPeerId) {
      failures.add('alice: $proofName.staleInviteePeerId must be charlie');
    }
    requireFinalEpoch('alice', aliceProof);
  }

  if (bobProof == null) {
    failures.add('bob: missing KE-016 stale re-invite proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'observedEpochNInviteMemberState',
      'observedRemovalBeforeCurrentInvite',
      'receivedRemovedWindowMessage',
      'memberListIncludesCharlie',
      'hasCurrentEpoch',
      'receivedAlicePostAcceptAtCurrentEpoch',
      'sentBobPostAcceptAtCurrentEpoch',
      'receivedCharliePostAcceptAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireFinalEpoch('bob', bobProof);
  }

  if (charlieProof == null) {
    failures.add('charlie: missing KE-016 stale re-invite proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'receivedEpochNInvite',
      'receivedCurrentEpochInvite',
      'delayedEpochNInviteRejected',
      'pendingRemainedCurrentBeforeAccept',
      'acceptedCurrentEpochInvite',
      'staleEpochNAcceptRejected',
      'noKeyDowngradeAfterStaleAccept',
      'memberListIncludesAliceBobCharlie',
      'receivedAlicePostAcceptAtCurrentEpoch',
      'receivedBobPostAcceptAtCurrentEpoch',
      'sentCharliePostAcceptAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final epochN = _intValue(charlieProof['epochNInviteEpoch']);
    final currentEpoch = _intValue(charlieProof['currentInviteEpoch']);
    final acceptedEpoch = _intValue(charlieProof['acceptedEpoch']);
    if (epochN == null || epochN < 1) {
      failures.add('charlie: $proofName.epochNInviteEpoch must be positive');
    }
    if (currentEpoch == null || currentEpoch < 2) {
      failures.add('charlie: $proofName.currentInviteEpoch must be >= 2');
    }
    if (epochN != null && currentEpoch != null && epochN >= currentEpoch) {
      failures.add('charlie: $proofName.epochNInviteEpoch must be stale');
    }
    if (acceptedEpoch != null &&
        currentEpoch != null &&
        acceptedEpoch != currentEpoch) {
      failures.add(
        'charlie: $proofName.acceptedEpoch must match currentInviteEpoch',
      );
    }
    final delayedStoreResult = _stringValue(charlieProof['delayedStoreResult']);
    if (delayedStoreResult != 'invalidPayload' &&
        delayedStoreResult != 'revoked') {
      failures.add(
        'charlie: $proofName.delayedStoreResult must be invalidPayload or revoked',
      );
    }
    final staleAcceptResult = _stringValue(charlieProof['staleAcceptResult']);
    if (staleAcceptResult != 'invalidPayload' &&
        staleAcceptResult != 'revoked') {
      failures.add(
        'charlie: $proofName.staleAcceptResult must be invalidPayload or revoked',
      );
    }
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
    requireFinalEpoch('charlie', charlieProof);
  }
}

void _validateRa004StaleInviteBeforeReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ra004StaleInviteBeforeReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-004') {
      failures.add('$role: $proofName.rowId must be RA-004');
    }
  }

  void requireFinalEpoch(String role, Map<String, dynamic> proof) {
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-004 stale invite proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'sentOldInvite',
      'removedCharlieBeforeOldAccept',
      'rotatedAfterRemoval',
      'revokedOldInviteBeforeCurrentInvite',
      'sentCurrentInviteAfterOldAcceptBlocked',
      'sentPostCurrentInviteMessage',
      'receivedBobPostCurrentInviteMessage',
      'receivedCharliePostCurrentInviteMessage',
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
    final stalePeerId = _stringValue(aliceProof['staleInviteePeerId']);
    final expectedPeerId = peerIdByRole['charlie'];
    if (expectedPeerId != null && stalePeerId != expectedPeerId) {
      failures.add('alice: $proofName.staleInviteePeerId must be charlie');
    }
    if ((_stringValue(aliceProof['oldInviteId']) ?? '').isEmpty) {
      failures.add('alice: $proofName.oldInviteId is required');
    }
    requireFinalEpoch('alice', aliceProof);
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-004 stale invite proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'observedOldInviteMemberState',
      'observedRemovalBeforeCurrentInvite',
      'receivedRemovedWindowMessage',
      'memberListIncludesCharlie',
      'hasCurrentEpoch',
      'receivedAlicePostCurrentInviteMessage',
      'sentBobPostCurrentInviteMessage',
      'receivedCharliePostCurrentInviteMessage',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireFinalEpoch('bob', bobProof);
  }

  if (charlieProof == null) {
    failures.add('charlie: missing RA-004 stale invite proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'receivedOldInvite',
      'oldAcceptAttemptedBeforeCurrentInvite',
      'oldAcceptBeforeCurrentRejected',
      'noGroupAfterOldAccept',
      'noKeyAfterOldAccept',
      'receivedCurrentInvite',
      'acceptedCurrentInvite',
      'staleAcceptRejected',
      'noKeyDowngradeAfterStaleAccept',
      'memberListIncludesAliceBobCharlie',
      'receivedAlicePostCurrentInviteMessage',
      'receivedBobPostCurrentInviteMessage',
      'sentCharliePostCurrentInviteMessage',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final oldAcceptResult = _stringValue(
      charlieProof['oldAcceptResultBeforeCurrent'],
    );
    if (oldAcceptResult != 'revoked' && oldAcceptResult != 'notFound') {
      failures.add(
        'charlie: $proofName.oldAcceptResultBeforeCurrent must be revoked or notFound',
      );
    }
    final staleAcceptResult = _stringValue(charlieProof['staleAcceptResult']);
    if (staleAcceptResult != 'invalidPayload' &&
        staleAcceptResult != 'revoked') {
      failures.add(
        'charlie: $proofName.staleAcceptResult must be invalidPayload or revoked',
      );
    }
    final oldEpoch = _intValue(charlieProof['oldInviteEpoch']);
    final currentEpoch = _intValue(charlieProof['currentInviteEpoch']);
    final acceptedEpoch = _intValue(charlieProof['acceptedEpoch']);
    if (oldEpoch == null || oldEpoch < 1) {
      failures.add('charlie: $proofName.oldInviteEpoch must be positive');
    }
    if (currentEpoch == null || currentEpoch < 2) {
      failures.add('charlie: $proofName.currentInviteEpoch must be >= 2');
    }
    if (oldEpoch != null && currentEpoch != null && oldEpoch >= currentEpoch) {
      failures.add('charlie: $proofName.oldInviteEpoch must be stale');
    }
    if (acceptedEpoch != null &&
        currentEpoch != null &&
        acceptedEpoch != currentEpoch) {
      failures.add(
        'charlie: $proofName.acceptedEpoch must match currentInviteEpoch',
      );
    }
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
    requireFinalEpoch('charlie', charlieProof);
  }
}

void _validateKe003StaleLowerKeyUpdateProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ke003StaleLowerKeyUpdateProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'KE-003') {
      failures.add('$role: $proofName.rowId must be KE-003');
    }
  }

  void requireEpochs({
    required String role,
    required Map<String, dynamic> proof,
    required bool requireBeforeAfter,
  }) {
    final staleEpoch = _intValue(proof['staleEpoch']);
    final currentEpoch = _intValue(proof['currentEpoch']);
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (staleEpoch != 4) {
      failures.add('$role: $proofName.staleEpoch must be 4');
    }
    if (currentEpoch != 5) {
      failures.add('$role: $proofName.currentEpoch must be 5');
    }
    if (finalEpoch != 5) {
      failures.add('$role: $proofName.finalEpoch must be 5');
    }
    if (requireBeforeAfter) {
      if (_intValue(proof['epochBeforeStale']) != 5) {
        failures.add('$role: $proofName.epochBeforeStale must be 5');
      }
      if (_intValue(proof['epochAfterStale']) != 5) {
        failures.add('$role: $proofName.epochAfterStale must be 5');
      }
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing KE-003 stale lower key update proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'heldLowerEpochForBob',
      'deliveredEpochFiveBeforeStale',
      'deliveredStaleEpochAfterEpochFive',
      'sentEpochFiveAfterStale',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    requireEpochs(role: 'alice', proof: aliceProof, requireBeforeAfter: false);
  }

  if (bobProof == null) {
    failures.add('bob: missing KE-003 stale lower key update proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'acceptedEpochFiveBeforeStale',
      'storedStaleEpochAsHistorical',
      'keptEpochFiveAfterStale',
      'receivedEpochFiveAfterStale',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireEpochs(role: 'bob', proof: bobProof, requireBeforeAfter: true);
  }

  if (charlieProof == null) {
    failures.add('charlie: missing KE-003 stale lower key update proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'notTargetedByStaleUpdate',
      'receivedEpochFiveAfterStale',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    requireEpochs(
      role: 'charlie',
      proof: charlieProof,
      requireBeforeAfter: false,
    );
  }
}

void _validateKe005SameEpochKeyConflictProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ke005SameEpochKeyConflictProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'KE-005') {
      failures.add('$role: $proofName.rowId must be KE-005');
    }
  }

  void requireEpochs({
    required String role,
    required Map<String, dynamic> proof,
    required bool requireBeforeAfter,
  }) {
    final conflictEpoch = _intValue(proof['conflictEpoch']);
    final currentEpoch = _intValue(proof['currentEpoch']);
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (conflictEpoch != 5) {
      failures.add('$role: $proofName.conflictEpoch must be 5');
    }
    if (currentEpoch != 5) {
      failures.add('$role: $proofName.currentEpoch must be 5');
    }
    if (finalEpoch != 5) {
      failures.add('$role: $proofName.finalEpoch must be 5');
    }
    if (requireBeforeAfter) {
      if (_intValue(proof['epochBeforeConflict']) != 5) {
        failures.add('$role: $proofName.epochBeforeConflict must be 5');
      }
      if (_intValue(proof['epochAfterConflict']) != 5) {
        failures.add('$role: $proofName.epochAfterConflict must be 5');
      }
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing KE-005 same epoch conflict proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'generatedOriginalEpochFive',
      'deliveredOriginalEpochFiveToBob',
      'deliveredSameEpochConflictToBob',
      'sentEpochFiveAfterConflict',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    requireEpochs(role: 'alice', proof: aliceProof, requireBeforeAfter: false);
  }

  if (bobProof == null) {
    failures.add('bob: missing KE-005 same epoch conflict proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'acceptedOriginalEpochFive',
      'observedSameEpochConflict',
      'rejectedConflictingMaterial',
      'keptOriginalEpochFiveAfterConflict',
      'receivedEpochFiveAfterConflict',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireEpochs(role: 'bob', proof: bobProof, requireBeforeAfter: true);
  }

  if (charlieProof == null) {
    failures.add('charlie: missing KE-005 same epoch conflict proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'notTargetedByConflict',
      'receivedEpochFiveAfterConflict',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    requireEpochs(
      role: 'charlie',
      proof: charlieProof,
      requireBeforeAfter: false,
    );
  }
}

void _validateKe015PartialKeyDistributionProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ke015PartialKeyDistributionProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'KE-015') {
      failures.add('$role: $proofName.rowId must be KE-015');
    }
  }

  void requireFinalEpochOne(String role, Map<String, dynamic> proof) {
    if (_intValue(proof['finalEpoch']) != 1) {
      failures.add('$role: $proofName.finalEpoch must remain 1');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing KE-015 partial-key-distribution proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'attemptedMixedDistribution',
      'bobKeyUpdateSucceeded',
      'charlieKeyUpdateFailed',
      'rotationBlocked',
      'keptSenderEpochAfterFailure',
      'blockedKeyRotatedPublish',
      'sentPostFailureAtPreviousEpoch',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    requireFinalEpochOne('alice', aliceProof);
    if (_intValue(aliceProof['attemptedEpoch']) != 2) {
      failures.add('alice: $proofName.attemptedEpoch must be 2');
    }
    if (_intValue(aliceProof['postFailureMessageEpoch']) != 1) {
      failures.add('alice: $proofName.postFailureMessageEpoch must be 1');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing KE-015 partial-key-distribution proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'receivedSuccessfulKeyUpdate',
      'successfulRecipientStillReceivesPostFailure',
      'receivedPostFailureAtPreviousEpoch',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    final finalEpoch = _intValue(bobProof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 1) {
      failures.add('bob: $proofName.finalEpoch must be >= 1');
    }
  }

  if (charlieProof == null) {
    failures.add(
      'charlie: missing KE-015 partial-key-distribution proof fields',
    );
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'failedRecipientDidNotAdvance',
      'receivedPostFailureAtPreviousEpoch',
      'notDeafAfterFailedKeyUpdate',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    requireFinalEpochOne('charlie', charlieProof);
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

void _validateNw001FullMeshProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'nw001FullMeshProof';
  const roles = <String>['alice', 'bob', 'charlie'];
  const keysBySender = <String, String>{
    'alice': 'aliceFullMesh',
    'bob': 'bobFullMesh',
    'charlie': 'charlieFullMesh',
  };

  for (final role in roles) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing NW-001 full-mesh proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'NW-001') {
      failures.add('$role: $proofName.rowId must be NW-001');
    }
    if (!_sameStringList(_stringList(proof['activeRoles']), roles)) {
      failures.add('$role: $proofName.activeRoles mismatch');
    }
    if (!_sameStringList(_stringList(proof['senderRoles']), roles)) {
      failures.add('$role: $proofName.senderRoles mismatch');
    }
    if (_intValue(proof['expectedReceiversPerMessage']) != 2) {
      failures.add('$role: $proofName.expectedReceiversPerMessage must be 2');
    }
    for (final field in const <String>[
      'allRolePublishesCovered',
      'allActiveReceiversCovered',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'duplicateVisibleMessageCount',
      'successNoPeersCount',
      'partialPeerPublishCount',
    ]) {
      final count = _intValue(proof[field]);
      if (count != 0) {
        failures.add('$role: $proofName.$field must be 0');
      }
    }

    final topicPeerCounts = _intMap(proof['topicPeerCountsBySender']);
    for (final senderRole in roles) {
      final count = topicPeerCounts[senderRole];
      if (count == null || count < 2) {
        failures.add(
          '$role: $proofName.topicPeerCountsBySender.$senderRole must be >= 2',
        );
      }
    }
  }

  for (final entry in keysBySender.entries) {
    final senderRole = entry.key;
    final key = entry.value;
    final sentEntries = _mapList(
      byRole[senderRole]?['sentMessages'],
    ).where((sent) => _stringValue(sent['key']) == key).toList(growable: false);
    if (sentEntries.length != 1) {
      continue;
    }
    final sent = sentEntries.single;
    if (_stringValue(sent['outcome']) != 'success') {
      failures.add('$senderRole: NW-001 $key must publish with success');
    }
    final topicPeers = _intValue(sent['topicPeers']);
    if (topicPeers == null || topicPeers < 2) {
      failures.add('$senderRole: NW-001 $key topicPeers must be >= 2');
    }
    if (_stringValue(sent['liveFanoutState']) != 'full_peers') {
      failures.add(
        '$senderRole: NW-001 $key liveFanoutState must be full_peers',
      );
    }

    final proof = _mapValue(byRole[senderRole]?[proofName]);
    final topicPeerCounts = proof == null
        ? const <String, int>{}
        : _intMap(proof['topicPeerCountsBySender']);
    if (topicPeers != null && topicPeerCounts[senderRole] != topicPeers) {
      failures.add(
        '$senderRole: NW-001 proof topic peer count does not match sent proof',
      );
    }
  }

  for (final role in roles) {
    for (final message in _expectedMessagesForScenario(
      'private_full_mesh_online',
    )) {
      if (!message.receiverRoles.contains(role)) continue;
      final receivedEntries = _mapList(byRole[role]?['receivedMessages'])
          .where((received) => _stringValue(received['key']) == message.key)
          .toList(growable: false);
      if (receivedEntries.length != 1) continue;
      final received = receivedEntries.single;
      if (received['liveOnly'] != true) {
        failures.add('$role: NW-001 ${message.key} must be marked liveOnly');
      }
      if (received['usedOfflineDrain'] != false) {
        failures.add('$role: NW-001 ${message.key} must not use offline drain');
      }
      final expectedSenderPeerId = peerIdByRole[message.senderRole];
      if (expectedSenderPeerId != null &&
          _stringValue(received['senderPeerId']) != expectedSenderPeerId) {
        failures.add('$role: NW-001 ${message.key} sender mismatch');
      }
    }
  }
}

void _validateNw002RelayOnlyDeliveryProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'nw002RelayOnlyDeliveryProof';
  const roles = <String>['alice', 'bob', 'charlie'];
  var totalSuccessNoPeers = 0;
  var anyReplayCovered = false;
  var anyCircuitOrRelayRouteProven = false;
  var anyDirectPathSuppressed = false;

  for (final role in roles) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing NW-002 relay-only delivery proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'NW-002') {
      failures.add('$role: $proofName.rowId must be NW-002');
    }
    final relayOnlyRoles = _stringList(proof['relayOnlyRoles']);
    if (!relayOnlyRoles.contains('bob')) {
      failures.add('$role: $proofName.relayOnlyRoles must include bob');
    }
    final routeDiagnostics = _mapList(proof['routeDiagnostics']);
    final circuitOrRelayBacked = routeDiagnostics.any(
      (diagnostic) => _nw002DiagnosticBacksCircuitOrRelayRoute(
        diagnostic,
        peerIdByRole['bob'],
      ),
    );
    final directSuppressedBacked = routeDiagnostics.any(
      (diagnostic) => _nw002DiagnosticBacksDirectPathSuppression(
        diagnostic,
        peerIdByRole['bob'],
      ),
    );
    if (proof['circuitOrRelayRouteProven'] == true) {
      if (!circuitOrRelayBacked) {
        failures.add(
          '$role: $proofName.circuitOrRelayRouteProven must be backed by '
          'a Bob route diagnostic',
        );
      }
      anyCircuitOrRelayRouteProven =
          anyCircuitOrRelayRouteProven || circuitOrRelayBacked;
    }
    if (proof['directPathSuppressed'] == true) {
      if (!directSuppressedBacked) {
        failures.add(
          '$role: $proofName.directPathSuppressed must be backed by a Bob '
          'route diagnostic with relay path, attemptedDirect=false, and '
          'directAddrCount=0',
        );
      }
      anyDirectPathSuppressed =
          anyDirectPathSuppressed || directSuppressedBacked;
    }
    for (final field in const <String>[
      'activeMembershipPreserved',
      'allRoutedReceiversCovered',
      'routedSenderPublishBackCovered',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'duplicateVisibleMessageCount',
      'membershipMutationCount',
    ]) {
      final count = _intValue(proof[field]);
      if (count != 0) {
        failures.add('$role: $proofName.$field must be 0');
      }
    }

    final successNoPeers = _intValue(proof['successNoPeersCount']) ?? 0;
    if (successNoPeers < 0) {
      failures.add('$role: $proofName.successNoPeersCount must be >= 0');
    } else {
      totalSuccessNoPeers += successNoPeers;
    }
    anyReplayCovered =
        anyReplayCovered || proof['replayDeliveryCovered'] == true;

    final deliveryModeByMessage = _mapValue(proof['deliveryModeByMessage']);
    if (deliveryModeByMessage == null) {
      failures.add('$role: $proofName.deliveryModeByMessage is required');
    } else {
      _validateNw002DeliveryMode(
        role: role,
        proofName: proofName,
        deliveryModeByMessage: deliveryModeByMessage,
        key: 'aliceToRelayOnlyBob',
        senderRole: 'alice',
        routedReceiverRoles: const <String>['bob'],
        failures: failures,
      );
      _validateNw002DeliveryMode(
        role: role,
        proofName: proofName,
        deliveryModeByMessage: deliveryModeByMessage,
        key: 'bobRelayOnlyPublishBack',
        senderRole: 'bob',
        routedReceiverRoles: const <String>['alice', 'charlie'],
        failures: failures,
      );
    }
  }

  if (totalSuccessNoPeers > 0 && !anyReplayCovered) {
    failures.add(
      'NW-002 successNoPeers proof requires replayDeliveryCovered=true',
    );
  }
  if (!anyCircuitOrRelayRouteProven) {
    failures.add(
      'NW-002 circuitOrRelayRouteProven must be true for at least one role',
    );
  }
  if (!anyDirectPathSuppressed) {
    failures.add(
      'NW-002 directPathSuppressed must be true for at least one role',
    );
  }

  for (final entry in const <String, String>{
    'alice': 'aliceToRelayOnlyBob',
    'bob': 'bobRelayOnlyPublishBack',
  }.entries) {
    final senderRole = entry.key;
    final key = entry.value;
    final sentEntries = _mapList(
      byRole[senderRole]?['sentMessages'],
    ).where((sent) => _stringValue(sent['key']) == key).toList(growable: false);
    if (sentEntries.length != 1) {
      continue;
    }
    final sent = sentEntries.single;
    final outcome = _stringValue(sent['outcome']);
    if (outcome != 'success' && outcome != 'successNoPeers') {
      failures.add('$senderRole: NW-002 $key must publish successfully');
    }
    if (outcome == 'successNoPeers' && !anyReplayCovered) {
      failures.add(
        '$senderRole: NW-002 $key successNoPeers needs replay proof',
      );
    }
  }

  for (final role in roles) {
    for (final message in _expectedMessagesForScenario(
      'private_relay_only_delivery',
    )) {
      if (!message.receiverRoles.contains(role)) continue;
      final receivedEntries = _mapList(byRole[role]?['receivedMessages'])
          .where((received) => _stringValue(received['key']) == message.key)
          .toList(growable: false);
      if (receivedEntries.length != 1) continue;
      final received = receivedEntries.single;
      final expectedSenderPeerId = peerIdByRole[message.senderRole];
      if (expectedSenderPeerId != null &&
          _stringValue(received['senderPeerId']) != expectedSenderPeerId) {
        failures.add('$role: NW-002 ${message.key} sender mismatch');
      }
      if (received['usedOfflineDrain'] == true) {
        final proof = _mapValue(byRole[role]?[proofName]);
        if (proof?['replayDeliveryCovered'] != true) {
          failures.add(
            '$role: NW-002 ${message.key} used offline drain without replay proof',
          );
        }
      }
    }
  }
}

void _validateNw002DeliveryMode({
  required String role,
  required String proofName,
  required Map<String, dynamic> deliveryModeByMessage,
  required String key,
  required String senderRole,
  required List<String> routedReceiverRoles,
  required List<String> failures,
}) {
  final mode = _mapValue(deliveryModeByMessage[key]);
  if (mode == null) {
    failures.add('$role: $proofName.deliveryModeByMessage.$key is required');
    return;
  }
  if (_stringValue(mode['senderRole']) != senderRole) {
    failures.add(
      '$role: $proofName.deliveryModeByMessage.$key senderRole mismatch',
    );
  }
  final receivers = _stringList(mode['routedReceiverRoles']);
  for (final receiverRole in routedReceiverRoles) {
    if (!receivers.contains(receiverRole)) {
      failures.add(
        '$role: $proofName.deliveryModeByMessage.$key missing routed receiver $receiverRole',
      );
    }
  }
  final deliveryMode = _stringValue(mode['deliveryMode']);
  if (deliveryMode != 'live_pubsub' && deliveryMode != 'durable_replay') {
    failures.add(
      '$role: $proofName.deliveryModeByMessage.$key deliveryMode must be live_pubsub or durable_replay',
    );
  }
}

bool _nw002DiagnosticBacksCircuitOrRelayRoute(
  Map<String, dynamic> diagnostic,
  String? bobPeerId,
) {
  if (!_nw002DiagnosticTargetsBob(diagnostic, bobPeerId)) return false;
  final path = _stringValue(diagnostic['path']);
  return path == 'relay' ||
      path == 'relay_fallback' ||
      diagnostic['usedRelayFallback'] == true;
}

bool _nw002DiagnosticBacksDirectPathSuppression(
  Map<String, dynamic> diagnostic,
  String? bobPeerId,
) {
  if (!_nw002DiagnosticTargetsBob(diagnostic, bobPeerId)) return false;
  return _stringValue(diagnostic['path']) == 'relay' &&
      diagnostic['attemptedDirect'] == false &&
      _intValue(diagnostic['directAddrCount']) == 0;
}

bool _nw002DiagnosticTargetsBob(
  Map<String, dynamic> diagnostic,
  String? bobPeerId,
) {
  if (bobPeerId == null || bobPeerId.isEmpty) return false;
  final prefix =
      _stringValue(diagnostic['peerIdPrefix']) ??
      _stringValue(diagnostic['targetPeerPrefix']);
  if (prefix == null || prefix.isEmpty || prefix.length > 12) return false;
  if (prefix.contains('/')) return false;
  return bobPeerId.startsWith(prefix);
}

void _validateNw003PartitionReaddHealProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'nw003PartitionReaddHealProof';
  const roles = <String>['alice', 'bob', 'charlie'];

  for (final role in roles) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing NW-003 partition re-add proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'NW-003') {
      failures.add('$role: $proofName.rowId must be NW-003');
    }
    if (_stringValue(proof['scenario']) != 'private_partition_readd_heal') {
      failures.add(
        '$role: $proofName.scenario must be private_partition_readd_heal',
      );
    }
    if (_stringValue(proof['appPeerPlatform']) != 'ios_26_2_core_simulator') {
      failures.add(
        '$role: $proofName.appPeerPlatform must be ios_26_2_core_simulator',
      );
    }
    if (_stringValue(proof['partitionProofSource']) !=
        'app_peer_core_simulator') {
      failures.add(
        '$role: $proofName.partitionProofSource must be app_peer_core_simulator',
      );
    }
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'fakeNetworkOnly',
      failures: failures,
    );
    for (final field in const <String>[
      'alicePartitionedFromBob',
      'alicePartitionedFromCharlie',
      'bobAndCharliePartitionedFromAlice',
      'removedWindowSentWhileCharlieRemoved',
      'removedWindowLiveDeliveryBlockedDuringPartition',
      'bobReceivedRemovedWindowAfterHeal',
      'charlieDidNotReceiveRemovedWindow',
      'finalMembershipConvergedForAliceBobCharlie',
      'finalKeyEpochConvergedForAliceBobCharlie',
      'postHealAliceToBobCharlieDelivery',
      'postHealBobToAliceCharlieDelivery',
      'postHealCharlieToAliceBobDelivery',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }

    final routeDiagnostics = _mapList(proof['routeDiagnostics']);
    if (routeDiagnostics.isEmpty) {
      failures.add('$role: $proofName.routeDiagnostics is required');
    }
    for (final diagnostic in routeDiagnostics) {
      for (final peerId in peerIdByRole.values) {
        if (peerId.isEmpty) continue;
        final containsFullPeerId = diagnostic.values.any((value) {
          return value is String && value.contains(peerId);
        });
        if (containsFullPeerId) {
          failures.add(
            '$role: $proofName.routeDiagnostics must not contain full peer IDs',
          );
        }
      }
    }
  }

  final aliceSent = _mapList(byRole['alice']?['sentMessages']);
  final removedWindow = aliceSent.where(
    (sent) => _stringValue(sent['key']) == 'aliceRemovedWindow',
  );
  if (removedWindow.length == 1) {
    final sent = removedWindow.single;
    final outcome = _stringValue(sent['outcome']);
    if (outcome != 'success' && outcome != 'successNoPeers') {
      failures.add('alice: NW-003 removed-window send must be durable success');
    }
    final recipientPeerIds = _stringList(sent['recipientPeerIds']).toSet();
    final bobPeerId = peerIdByRole['bob'];
    final charliePeerId = peerIdByRole['charlie'];
    if (bobPeerId != null && !recipientPeerIds.contains(bobPeerId)) {
      failures.add('alice: NW-003 removed-window recipients must include Bob');
    }
    if (charliePeerId != null && recipientPeerIds.contains(charliePeerId)) {
      failures.add(
        'alice: NW-003 removed-window recipients must exclude Charlie',
      );
    }
  }

  final charlieReceivedKeys = _mapList(byRole['charlie']?['receivedMessages'])
      .map((received) => _stringValue(received['key']))
      .whereType<String>()
      .toSet();
  if (charlieReceivedKeys.contains('aliceRemovedWindow')) {
    failures.add('charlie: NW-003 must not receive aliceRemovedWindow');
  }
}

void _validateNw004RelayReconnectRecoveryProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'nw004RelayReconnectRecoveryProof';
  const roles = <String>['alice', 'bob', 'charlie'];
  var anyRejoinOrPreserved = false;
  var anyReplayRecovered = false;
  var anyNeedsGroupRecoveryObserved = false;

  for (final role in roles) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add(
        '$role: missing NW-004 relay reconnect recovery proof fields',
      );
      continue;
    }
    if (_stringValue(proof['rowId']) != 'NW-004') {
      failures.add('$role: $proofName.rowId must be NW-004');
    }
    if (_stringValue(proof['scenario']) !=
        'private_relay_reconnect_group_recovery') {
      failures.add(
        '$role: $proofName.scenario must be private_relay_reconnect_group_recovery',
      );
    }
    if (_stringValue(proof['appPeerPlatform']) != 'ios_26_2_core_simulator') {
      failures.add(
        '$role: $proofName.appPeerPlatform must be ios_26_2_core_simulator',
      );
    }
    if (_stringValue(proof['recoveryMode']) == null ||
        _stringValue(proof['recoveryMode'])!.isEmpty) {
      failures.add('$role: $proofName.recoveryMode is required');
    }

    for (final field in const <String>[
      'relayDropForced',
      'relayReconnectCalled',
      'groupReplayDrainCompleted',
      'missedDuringDropRecoveredByReplay',
      'postReconnectLiveDeliveryToRecoveredPeer',
      'recoveredPeerPublishBackLive',
      'membershipUnchangedByReconnect',
      'finalMembershipConvergedForAliceBobCharlie',
      'finalKeyEpochConvergedForAliceBobCharlie',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }

    final groupTopicsRejoined =
        proof['groupTopicsRejoinedAfterReconnect'] == true;
    final topicsPreserved = proof['topicsPreservedInPlace'] == true;
    if (!groupTopicsRejoined && !topicsPreserved) {
      failures.add(
        '$role: $proofName requires group topic rejoin or preserved topics',
      );
    }
    anyRejoinOrPreserved =
        anyRejoinOrPreserved || groupTopicsRejoined || topicsPreserved;
    anyReplayRecovered =
        anyReplayRecovered ||
        proof['missedDuringDropRecoveredByReplay'] == true;
    anyNeedsGroupRecoveryObserved =
        anyNeedsGroupRecoveryObserved ||
        proof['needsGroupRecoveryObserved'] == true;

    if (proof['needsGroupRecoveryObserved'] == true &&
        proof['recoveryAckSentAfterRejoinAndDrain'] != true) {
      failures.add(
        '$role: $proofName.recoveryAckSentAfterRejoinAndDrain must be true when needsGroupRecoveryObserved is true',
      );
    }

    final duplicateCount = _intValue(proof['duplicateVisibleMessageCount']);
    if (duplicateCount != 0) {
      failures.add('$role: $proofName.duplicateVisibleMessageCount must be 0');
    }

    final routeDiagnostics = _mapList(proof['routeDiagnostics']);
    final reconnectDiagnostics = _mapList(proof['reconnectDiagnostics']);
    if (routeDiagnostics.isEmpty && reconnectDiagnostics.isEmpty) {
      failures.add(
        '$role: $proofName routeDiagnostics or reconnectDiagnostics is required',
      );
    }
    for (final diagnostic in <Map<String, dynamic>>[
      ...routeDiagnostics,
      ...reconnectDiagnostics,
    ]) {
      for (final peerId in peerIdByRole.values) {
        if (peerId.isEmpty) continue;
        final containsFullPeerId = diagnostic.values.any((value) {
          return value is String && value.contains(peerId);
        });
        if (containsFullPeerId) {
          failures.add(
            '$role: $proofName diagnostics must not contain full peer IDs',
          );
        }
      }
    }
  }

  if (!anyRejoinOrPreserved) {
    failures.add(
      'NW-004 requires at least one topic rejoin or preservation proof',
    );
  }
  if (!anyReplayRecovered) {
    failures.add('NW-004 requires replay recovery for the dropped publish');
  }
  if (!anyNeedsGroupRecoveryObserved) {
    failures.add('NW-004 requires needsGroupRecovery observability');
  }

  final bobReceived = _mapList(byRole['bob']?['receivedMessages']);
  final bobMissed = bobReceived.where(
    (entry) => _stringValue(entry['key']) == 'aliceMissedDuringRelayDrop',
  );
  if (bobMissed.length == 1 && bobMissed.single['usedOfflineDrain'] != true) {
    failures.add(
      'bob: NW-004 aliceMissedDuringRelayDrop must be recovered by offline drain',
    );
  }

  for (final expected in const <(String, String)>[
    ('bob', 'alicePostReconnectLive'),
    ('charlie', 'alicePostReconnectLive'),
    ('alice', 'bobRecoveredPublishBack'),
    ('charlie', 'bobRecoveredPublishBack'),
  ]) {
    final received = _mapList(
      byRole[expected.$1]?['receivedMessages'],
    ).where((message) => _stringValue(message['key']) == expected.$2);
    if (received.length == 1 && received.single['usedOfflineDrain'] != false) {
      failures.add(
        '${expected.$1}: NW-004 ${expected.$2} must be live after reconnect',
      );
    }
  }

  final charlieReceivedKeys = _mapList(byRole['charlie']?['receivedMessages'])
      .map((received) => _stringValue(received['key']))
      .whereType<String>()
      .toSet();
  if (charlieReceivedKeys.contains('aliceMissedDuringRelayDrop')) {
    failures.add(
      'charlie: NW-004 must not receive the Bob-only relay-drop replay',
    );
  }
}

void _validateNw006DisconnectNotRemovalProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'nw006DisconnectNotRemovalProof';
  const roles = <String>['alice', 'bob', 'charlie'];

  for (final role in roles) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing NW-006 disconnect-not-removal proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'NW-006') {
      failures.add('$role: $proofName.rowId must be NW-006');
    }
    if (_stringValue(proof['scenario']) !=
        'private_peer_disconnect_not_removal') {
      failures.add(
        '$role: $proofName.scenario must be private_peer_disconnect_not_removal',
      );
    }
    if (_stringValue(proof['appPeerPlatform']) != 'ios_26_2_core_simulator') {
      failures.add(
        '$role: $proofName.appPeerPlatform must be ios_26_2_core_simulator',
      );
    }
    if (_stringValue(proof['disconnectProofSource']) !=
        'app_peer_core_simulator') {
      failures.add(
        '$role: $proofName.disconnectProofSource must be app_peer_core_simulator',
      );
    }
    for (final field in const <String>[
      'bobDisconnected',
      'bobGroupPresentDuringDisconnect',
      'bobSelfMemberActiveDuringDisconnect',
      'durableRecipientIncludedDisconnectedBob',
      'missedDuringDisconnectRecoveredByReplay',
      'postReconnectLiveDeliveryToBob',
      'bobPublishBackAfterReconnect',
      'finalMembershipConvergedForAliceBobCharlie',
      'finalKeyEpochConvergedForAliceBobCharlie',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'bobRemovedSignalCount',
      'membershipMutationCount',
      'duplicateVisibleMessageCount',
    ]) {
      final count = _intValue(proof[field]);
      if (count != 0) {
        failures.add('$role: $proofName.$field must be 0');
      }
    }

    final diagnostics = _mapList(proof['disconnectDiagnostics']);
    if (diagnostics.isEmpty) {
      failures.add('$role: $proofName.disconnectDiagnostics is required');
    }
    for (final diagnostic in diagnostics) {
      for (final peerId in peerIdByRole.values) {
        if (peerId.isEmpty) continue;
        final containsFullPeerId = diagnostic.values.any((value) {
          return value is String && value.contains(peerId);
        });
        if (containsFullPeerId) {
          failures.add(
            '$role: $proofName.disconnectDiagnostics must not contain full peer IDs',
          );
        }
      }
    }
  }

  final aliceMissedSent = _mapList(
    byRole['alice']?['sentMessages'],
  ).where((sent) => _stringValue(sent['key']) == 'aliceMissedDuringDisconnect');
  if (aliceMissedSent.length == 1) {
    final recipientPeerIds = _stringList(
      aliceMissedSent.single['recipientPeerIds'],
    ).toSet();
    final bobPeerId = peerIdByRole['bob'];
    if (bobPeerId != null && !recipientPeerIds.contains(bobPeerId)) {
      failures.add(
        'alice: NW-006 disconnected Bob must remain in durable recipients',
      );
    }
  }

  final bobMissed = _mapList(byRole['bob']?['receivedMessages']).where(
    (entry) => _stringValue(entry['key']) == 'aliceMissedDuringDisconnect',
  );
  if (bobMissed.length == 1 && bobMissed.single['usedOfflineDrain'] != true) {
    failures.add(
      'bob: NW-006 aliceMissedDuringDisconnect must be recovered by offline drain',
    );
  }

  final charlieMissed = _mapList(byRole['charlie']?['receivedMessages']).where(
    (entry) => _stringValue(entry['key']) == 'aliceMissedDuringDisconnect',
  );
  if (charlieMissed.length == 1 &&
      charlieMissed.single['usedOfflineDrain'] != false) {
    failures.add(
      'charlie: NW-006 aliceMissedDuringDisconnect must remain live while Bob is disconnected',
    );
  }

  for (final expected in const <(String, String)>[
    ('bob', 'alicePostReconnectLive'),
    ('charlie', 'alicePostReconnectLive'),
    ('alice', 'bobPublishBackAfterReconnect'),
    ('charlie', 'bobPublishBackAfterReconnect'),
  ]) {
    final received = _mapList(
      byRole[expected.$1]?['receivedMessages'],
    ).where((message) => _stringValue(message['key']) == expected.$2);
    if (received.length == 1 && received.single['usedOfflineDrain'] != false) {
      failures.add(
        '${expected.$1}: NW-006 ${expected.$2} must be live after reconnect',
      );
    }
  }
}

void _validateNw010BackgroundResumeDeliveryProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'nw010BackgroundResumeDeliveryProof';
  const roles = <String>['alice', 'bob', 'charlie'];

  for (final role in roles) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing NW-010 background resume proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'NW-010') {
      failures.add('$role: $proofName.rowId must be NW-010');
    }
    if (_stringValue(proof['scenario']) !=
        'private_background_resume_group_delivery') {
      failures.add(
        '$role: $proofName.scenario must be private_background_resume_group_delivery',
      );
    }
    if (_stringValue(proof['appPeerPlatform']) != 'ios_26_2_core_simulator') {
      failures.add(
        '$role: $proofName.appPeerPlatform must be ios_26_2_core_simulator',
      );
    }
    if (_stringValue(proof['backgroundProofSource']) !=
        'app_peer_core_simulator_lifecycle_pause_resume') {
      failures.add(
        '$role: $proofName.backgroundProofSource must be app_peer_core_simulator_lifecycle_pause_resume',
      );
    }
    for (final field in const <String>[
      'bobBackgroundedDuringAliceActivity',
      'bobForegroundedAfterMembershipEdit',
      'bobReceivedNoLiveCopyWhileBackgrounded',
      'groupTopicsRejoinedAfterForeground',
      'groupReplayDrainCompleted',
      'recoveryAckSentAfterRejoinAndDrain',
      'orderedDrainIncludesContentAndMembership',
      'entitlementFilteringPreserved',
      'postForegroundLiveDeliveryToBob',
      'bobPublishBackAfterForeground',
      'finalMembershipConvergedForAliceBob',
      'finalKeyEpochConvergedForAliceBob',
      'charlieRemovedBeforeSecondBackgroundMessage',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final duplicateCount = _intValue(proof['duplicateVisibleMessageCount']);
    if (duplicateCount != 0) {
      failures.add('$role: $proofName.duplicateVisibleMessageCount must be 0');
    }
    final orderedDrainKeys = _stringList(proof['orderedDrainKeys']);
    var cursor = -1;
    for (final expectedKey in const <String>[
      'aliceDuringBackgroundBeforeEdit',
      'memberRemovedCharlie',
      'aliceDuringBackgroundAfterEdit',
    ]) {
      final next = orderedDrainKeys.indexWhere(
        (key) => key == expectedKey,
        cursor + 1,
      );
      if (next == -1) {
        failures.add('$role: $proofName.orderedDrainKeys missing $expectedKey');
        break;
      }
      cursor = next;
    }
    final diagnostics = _mapList(proof['lifecycleDiagnostics']);
    if (diagnostics.isEmpty) {
      failures.add('$role: $proofName.lifecycleDiagnostics is required');
    }
    for (final diagnostic in diagnostics) {
      for (final peerId in peerIdByRole.values) {
        if (peerId.isEmpty) continue;
        final containsFullPeerId = diagnostic.values.any((value) {
          return value is String && value.contains(peerId);
        });
        if (containsFullPeerId) {
          failures.add(
            '$role: $proofName.lifecycleDiagnostics must not contain full peer IDs',
          );
        }
      }
    }
  }

  final aliceSentBefore = _mapList(byRole['alice']?['sentMessages']).where(
    (sent) => _stringValue(sent['key']) == 'aliceDuringBackgroundBeforeEdit',
  );
  if (aliceSentBefore.length == 1) {
    final recipientPeerIds = _stringList(
      aliceSentBefore.single['recipientPeerIds'],
    ).toSet();
    final bobPeerId = peerIdByRole['bob'];
    final charliePeerId = peerIdByRole['charlie'];
    if (bobPeerId != null && !recipientPeerIds.contains(bobPeerId)) {
      failures.add('alice: NW-010 first background send must include Bob');
    }
    if (charliePeerId != null && !recipientPeerIds.contains(charliePeerId)) {
      failures.add('alice: NW-010 first background send must include Charlie');
    }
  }

  final aliceSentAfter = _mapList(byRole['alice']?['sentMessages']).where(
    (sent) => _stringValue(sent['key']) == 'aliceDuringBackgroundAfterEdit',
  );
  if (aliceSentAfter.length == 1) {
    final recipientPeerIds = _stringList(
      aliceSentAfter.single['recipientPeerIds'],
    ).toSet();
    final bobPeerId = peerIdByRole['bob'];
    final charliePeerId = peerIdByRole['charlie'];
    if (bobPeerId != null && !recipientPeerIds.contains(bobPeerId)) {
      failures.add('alice: NW-010 second background send must include Bob');
    }
    if (charliePeerId != null && recipientPeerIds.contains(charliePeerId)) {
      failures.add(
        'alice: NW-010 second background send must exclude removed Charlie',
      );
    }
  }

  for (final expected in const <(String, String, bool)>[
    ('bob', 'aliceDuringBackgroundBeforeEdit', true),
    ('bob', 'aliceDuringBackgroundAfterEdit', true),
    ('bob', 'alicePostForegroundLive', false),
    ('alice', 'bobPostForegroundPublishBack', false),
    ('charlie', 'aliceDuringBackgroundBeforeEdit', false),
  ]) {
    final received = _mapList(
      byRole[expected.$1]?['receivedMessages'],
    ).where((message) => _stringValue(message['key']) == expected.$2);
    if (received.length == 1 &&
        received.single['usedOfflineDrain'] != expected.$3) {
      failures.add(
        '${expected.$1}: NW-010 ${expected.$2} drain/live classification mismatch',
      );
    }
  }

  final charlieAfterEdit = _mapList(byRole['charlie']?['receivedMessages'])
      .where(
        (message) =>
            _stringValue(message['key']) == 'aliceDuringBackgroundAfterEdit',
      );
  if (charlieAfterEdit.isNotEmpty) {
    failures.add(
      'charlie: NW-010 removed member must not receive post-removal background send',
    );
  }
}

void _validateNw012LongOfflineEpochConvergenceProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'nw012LongOfflineEpochConvergenceProof';
  const roles = <String>['alice', 'bob', 'charlie'];

  for (final role in roles) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add(
        '$role: missing NW-012 long-offline epoch convergence proof fields',
      );
      continue;
    }
    if (_stringValue(proof['rowId']) != 'NW-012') {
      failures.add('$role: $proofName.rowId must be NW-012');
    }
    if (_stringValue(proof['scenario']) != 'private_long_offline_epoch_churn') {
      failures.add(
        '$role: $proofName.scenario must be private_long_offline_epoch_churn',
      );
    }
    if (_stringValue(proof['appPeerPlatform']) != 'ios_26_2_core_simulator') {
      failures.add(
        '$role: $proofName.appPeerPlatform must be ios_26_2_core_simulator',
      );
    }
    if (_stringValue(proof['offlineProofSource']) !=
        'app_peer_core_simulator_long_offline_reconnect') {
      failures.add(
        '$role: $proofName.offlineProofSource must be app_peer_core_simulator_long_offline_reconnect',
      );
    }
    for (final field in const <String>[
      'charlieOfflineThroughEpochChurn',
      'groupTopicsRejoinedAfterReconnect',
      'groupReplayDrainCompleted',
      'entitlementFilteringPreserved',
      'finalActiveMessagesDelivered',
      'charlieReceivedOnlyFinalActiveInterval',
      'postReconnectLiveDelivery',
      'finalMembershipConverged',
      'finalKeyEpochConverged',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }

    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 4) {
      failures.add('$role: $proofName.finalEpoch must be at least 4');
    }
    final finalRoles = _stringList(proof['finalMemberRoles']).toSet();
    if (!finalRoles.containsAll(const <String>['alice', 'bob', 'charlie']) ||
        finalRoles.length != 3) {
      failures.add(
        '$role: $proofName.finalMemberRoles must converge to alice,bob,charlie',
      );
    }
    for (final counter in const <String>[
      'duplicateVisibleMessageCount',
      'removedWindowPlaintextCount',
      'staleFirstIntervalPlaintextCount',
      'staleEpochPlaintextCount',
    ]) {
      if (_intValue(proof[counter]) != 0) {
        failures.add('$role: $proofName.$counter must be 0');
      }
    }

    final finalKeys = _stringList(proof['finalActiveMessageKeys']).toSet();
    if (!finalKeys.containsAll(const <String>[
      'aliceFinalActiveOne',
      'bobFinalActiveTwo',
    ])) {
      failures.add(
        '$role: $proofName.finalActiveMessageKeys missing final active messages',
      );
    }

    final orderedDrainKeys = _stringList(proof['orderedDrainKeys']);
    var cursor = -1;
    for (final expectedKey in const <String>[
      'memberRemovedCharlie',
      'memberReaddedCharlie',
      'aliceFinalActiveOne',
      'bobFinalActiveTwo',
    ]) {
      final next = orderedDrainKeys.indexWhere(
        (key) => key == expectedKey,
        cursor + 1,
      );
      if (next == -1) {
        failures.add('$role: $proofName.orderedDrainKeys missing $expectedKey');
        break;
      }
      cursor = next;
    }
  }

  final aliceRemovedWindow = _mapList(
    byRole['alice']?['sentMessages'],
  ).where((sent) => _stringValue(sent['key']) == 'aliceRemovedWindow');
  if (aliceRemovedWindow.length != 1) {
    failures.add(
      'alice: sent aliceRemovedWindow count=${aliceRemovedWindow.length}',
    );
  } else {
    final recipientPeerIds = _stringList(
      aliceRemovedWindow.single['recipientPeerIds'],
    ).toSet();
    final bobPeerId = peerIdByRole['bob'];
    final charliePeerId = peerIdByRole['charlie'];
    if (bobPeerId != null && !recipientPeerIds.contains(bobPeerId)) {
      failures.add('alice: NW-012 removed-window send must include Bob');
    }
    if (charliePeerId != null && recipientPeerIds.contains(charliePeerId)) {
      failures.add('alice: NW-012 removed-window send must exclude Charlie');
    }
  }

  for (final unexpectedKey in const <String>[
    'aliceRemovedWindow',
    'aliceStaleFirstInterval',
    'aliceStaleEpochAfterReadd',
  ]) {
    final charlieReceived = _mapList(
      byRole['charlie']?['receivedMessages'],
    ).where((message) => _stringValue(message['key']) == unexpectedKey);
    if (charlieReceived.isNotEmpty) {
      failures.add('charlie: NW-012 must not receive $unexpectedKey');
    }
  }

  for (final expected in const <(String, String, bool)>[
    ('bob', 'aliceFinalActiveOne', false),
    ('charlie', 'aliceFinalActiveOne', true),
    ('alice', 'bobFinalActiveTwo', false),
    ('charlie', 'bobFinalActiveTwo', true),
    ('alice', 'charliePostReconnectLive', false),
    ('bob', 'charliePostReconnectLive', false),
  ]) {
    final received = _mapList(
      byRole[expected.$1]?['receivedMessages'],
    ).where((message) => _stringValue(message['key']) == expected.$2);
    if (received.length == 1 &&
        received.single['usedOfflineDrain'] != expected.$3) {
      failures.add(
        '${expected.$1}: NW-012 ${expected.$2} drain/live classification mismatch',
      );
    }
  }
}

void _validatePrivateAbcCreateReusableProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  final topicNames = <String>{};
  final groupConfigStateHashes = <String>{};
  final keyEpochs = <int>{};

  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final verdict = byRole[role];
    if (verdict == null) continue;

    final deviceId = _stringValue(verdict['deviceId']);
    if (deviceId == null || deviceId.isEmpty) {
      failures.add('$role: deviceId is required for private_abc_create');
    }

    final topicName = _stringValue(verdict['topicName']);
    if (topicName == null || topicName.isEmpty) {
      failures.add('$role: topicName is required for private_abc_create');
    } else {
      topicNames.add(topicName);
    }

    final groupConfigStateHash = _stringValue(verdict['groupConfigStateHash']);
    if (groupConfigStateHash == null || groupConfigStateHash.isEmpty) {
      failures.add(
        '$role: groupConfigStateHash is required for private_abc_create',
      );
    } else {
      groupConfigStateHashes.add(groupConfigStateHash);
    }

    final keyEpoch = _intValue(verdict['keyEpoch']);
    if (keyEpoch == null || keyEpoch != 1) {
      failures.add(
        '$role: keyEpoch must be exactly 1 for KE-001 initial epoch proof',
      );
    } else {
      keyEpochs.add(keyEpoch);
    }

    final activeMemberPeerIds = _stringList(verdict['activeMemberPeerIds']);
    if (activeMemberPeerIds.isEmpty) {
      failures.add(
        '$role: activeMemberPeerIds is required for private_abc_create',
      );
    }

    for (final sent in _mapList(verdict['sentMessages'])) {
      final sentKey = _stringValue(sent['key']) ?? 'unknown';
      final sentEpoch = _intValue(sent['keyEpoch']);
      if (sentEpoch != null && sentEpoch != 1) {
        failures.add(
          '$role: sent $sentKey keyEpoch must be exactly 1 for KE-001',
        );
      }
    }
    for (final received in _mapList(verdict['receivedMessages'])) {
      final receivedKey = _stringValue(received['key']) ?? 'unknown';
      final receivedEpoch = _intValue(received['keyEpoch']);
      if (receivedEpoch != null && receivedEpoch != 1) {
        failures.add(
          '$role: received $receivedKey keyEpoch must be exactly 1 for KE-001',
        );
      }
    }
  }

  if (topicNames.length > 1) {
    failures.add(
      'role verdicts disagree on topicName: ${topicNames.join(', ')}',
    );
  }
  if (groupConfigStateHashes.length > 1) {
    failures.add(
      'role verdicts disagree on groupConfigStateHash: '
      '${groupConfigStateHashes.join(', ')}',
    );
  }
  if (keyEpochs.length > 1) {
    failures.add('role verdicts disagree on keyEpoch: ${keyEpochs.join(', ')}');
  }
}

void _validatePrivateReusableProofFields({
  required String scenario,
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  final topicNames = <String>{};
  final groupConfigStateHashes = <String>{};
  final keyEpochs = <int>{};

  for (final entry in byRole.entries) {
    final role = entry.key;
    final verdict = entry.value;

    final deviceId = _stringValue(verdict['deviceId']);
    if (deviceId == null || deviceId.isEmpty) {
      failures.add('$role: deviceId is required for $scenario');
    }

    final topicName = _stringValue(verdict['topicName']);
    if (topicName == null || topicName.isEmpty) {
      failures.add('$role: topicName is required for $scenario');
    } else {
      topicNames.add(topicName);
    }

    final groupConfigStateHash = _stringValue(verdict['groupConfigStateHash']);
    if (groupConfigStateHash == null || groupConfigStateHash.isEmpty) {
      failures.add('$role: groupConfigStateHash is required for $scenario');
    } else {
      groupConfigStateHashes.add(groupConfigStateHash);
    }

    final keyEpoch = _intValue(verdict['keyEpoch']);
    if (keyEpoch == null || keyEpoch < 1) {
      failures.add('$role: keyEpoch must be a positive integer for $scenario');
    } else {
      keyEpochs.add(keyEpoch);
    }

    final activeMemberPeerIds = _stringList(verdict['activeMemberPeerIds']);
    if (activeMemberPeerIds.isEmpty) {
      failures.add('$role: activeMemberPeerIds is required for $scenario');
    }
  }

  if (topicNames.length > 1) {
    failures.add(
      'role verdicts disagree on topicName: ${topicNames.join(', ')}',
    );
  }
  if (groupConfigStateHashes.length > 1) {
    failures.add(
      'role verdicts disagree on groupConfigStateHash: '
      '${groupConfigStateHashes.join(', ')}',
    );
  }
  if (keyEpochs.length > 1) {
    failures.add('role verdicts disagree on keyEpoch: ${keyEpochs.join(', ')}');
  }
}

void _validateMl001CreateInviteProofFields({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  for (final role in const <String>['alice', 'bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?['ml001CreateInviteProof']);
    if (proof == null) {
      failures.add('$role: missing ML-001 create/invite proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'ML-001') {
      failures.add('$role: ml001CreateInviteProof.rowId must be ML-001');
    }
    if (_stringValue(proof['invitePath']) != 'supported_pending_invite') {
      failures.add(
        '$role: ml001CreateInviteProof.invitePath must be supported_pending_invite',
      );
    }
  }

  final aliceProof = _mapValue(byRole['alice']?['ml001CreateInviteProof']);
  if (aliceProof != null) {
    for (final field in const <String>[
      'createdViaCreateGroupWithMembers',
      'bobInviteSent',
      'charlieInviteSent',
      'bobAcceptedSignal',
      'charlieAcceptedSignal',
      'readableJoinTimelineObserved',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: 'ml001CreateInviteProof',
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  for (final role in const <String>['bob', 'charlie']) {
    final proof = _mapValue(byRole[role]?['ml001CreateInviteProof']);
    if (proof == null) continue;
    for (final field in const <String>[
      'storedPendingInvite',
      'acceptedPendingInvite',
      'joinedViaGroupJoin',
      'readableSelfJoinTimeline',
      'receivedAliceInitialAfterInviteAccept',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: 'ml001CreateInviteProof',
        proof: proof,
        field: field,
        failures: failures,
      );
    }
  }
}

void _validateMl002OnlineAddProofFields({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  for (final role in const <String>['alice', 'bob', 'charlie', 'dana']) {
    final proof = _mapValue(byRole[role]?['ml002OnlineAddProof']);
    if (proof == null) {
      failures.add('$role: missing ML-002 online-add proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'ML-002') {
      failures.add('$role: ml002OnlineAddProof.rowId must be ML-002');
    }
  }

  final aliceProof = _mapValue(byRole['alice']?['ml002OnlineAddProof']);
  if (aliceProof != null) {
    for (final field in const <String>[
      'danaOnlineBeforeAdd',
      'danaNotActiveBeforeAdd',
      'aliceAddedDana',
      'danaJoinedAfterAdd',
      'allRolesSeeDanaActiveAfterJoin',
      'aliceSentPostJoin',
      'bobSentPostJoin',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: 'ml002OnlineAddProof',
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  final bobProof = _mapValue(byRole['bob']?['ml002OnlineAddProof']);
  if (bobProof != null) {
    for (final field in const <String>[
      'danaActiveAfterJoin',
      'bobSentPostJoin',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: 'ml002OnlineAddProof',
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
  }

  final charlieProof = _mapValue(byRole['charlie']?['ml002OnlineAddProof']);
  if (charlieProof != null) {
    _requireTrueProof(
      role: 'charlie',
      proofName: 'ml002OnlineAddProof',
      proof: charlieProof,
      field: 'danaActiveAfterJoin',
      failures: failures,
    );
  }

  final danaProof = _mapValue(byRole['dana']?['ml002OnlineAddProof']);
  if (danaProof != null) {
    for (final field in const <String>[
      'danaOnlineBeforeAdd',
      'danaNotActiveBeforeAdd',
      'joinedViaGroupJoinWithConfig',
      'currentKeyEpochInstalledBeforeLiveReceive',
      'receivedAlicePostJoinLiveNoDrain',
      'receivedBobPostJoinLiveNoDrain',
      'noOfflineDrainBeforeLiveReceipts',
    ]) {
      _requireTrueProof(
        role: 'dana',
        proofName: 'ml002OnlineAddProof',
        proof: danaProof,
        field: field,
        failures: failures,
      );
    }
  }

  final danaVerdict = byRole['dana'];
  if (danaVerdict == null) return;
  for (final key in const <String>['aliceAfterDanaAdd', 'bobAfterDanaAdd']) {
    final entries = _mapList(danaVerdict['receivedMessages'])
        .where((entry) => _stringValue(entry['key']) == key)
        .toList(growable: false);
    if (entries.length != 1) continue;
    final entry = entries.single;
    if (entry['liveOnly'] != true) {
      failures.add('dana: received $key liveOnly must be true');
    }
    if (entry['usedOfflineDrain'] != false) {
      failures.add('dana: received $key usedOfflineDrain must be false');
    }
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

void _validateMl005OnlineRemovalProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ml005OnlineRemovalProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'ML-005') {
      failures.add('$role: $proofName.rowId must be ML-005');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing ML-005 online-removal proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'charlieOnlineBeforeRemoval',
      'removedCharlie',
      'memberListExcludesCharlie',
      'receivedBobAfterRemoval',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing ML-005 online-removal proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'memberListExcludesCharlie',
      'hasRotatedEpoch',
      'receivedAliceAfterRemoval',
      'sentPostRemovalAccepted',
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
    failures.add('charlie: missing ML-005 online-removal proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'onlineBeforeRemoval',
      'currentMemberBeforeRemoval',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'groupPresentAfterRemoval',
      'hasRotatedEpoch',
      'postRemovalPublishAccepted',
      'receivedAliceAfterRemoval',
      'receivedBobAfterRemoval',
    ]) {
      _requireFalseProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final sendOutcome = _stringValue(charlieProof['postRemovalSendOutcome']);
    if (sendOutcome != 'groupNotFound' && sendOutcome != 'unauthorized') {
      failures.add(
        'charlie: $proofName.postRemovalSendOutcome must reject send',
      );
    }
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.postRemovalPlaintextCount must be 0');
    }
  }

  final aliceEpoch = _intValue(aliceProof?['rotatedEpoch']);
  final bobEpoch = _intValue(bobProof?['rotatedEpoch']);
  final charlieEpoch = _intValue(charlieProof?['rotatedEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: $proofName.rotatedEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: $proofName.rotatedEpoch must be >= 2');
  }
  if (aliceEpoch != null && bobEpoch != null && aliceEpoch != bobEpoch) {
    failures.add('alice/bob: ML-005 rotatedEpoch mismatch');
  }
  if (charlieEpoch != null &&
      aliceEpoch != null &&
      charlieEpoch >= aliceEpoch) {
    failures.add('charlie: $proofName must not hold rotated epoch');
  }
}

void _validateKe006RemovalKeyRotationProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ke006RemovalKeyRotationProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final expectedRotatedEpoch = _intValue(byRole['alice']?['keyEpoch']);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'KE-006') {
      failures.add('$role: $proofName.rowId must be KE-006');
    }
  }

  void requireRotatedEpoch(
    String role,
    Map<String, dynamic> proof, {
    required String field,
  }) {
    final value = _intValue(proof[field]);
    if (value == null || value <= 1) {
      failures.add('$role: $proofName.$field must be a rotated epoch > 1');
    }
    if (expectedRotatedEpoch != null && value != expectedRotatedEpoch) {
      failures.add('$role: $proofName.$field must match Alice rotated epoch');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing KE-006 removal-key proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlie',
      'memberListExcludesCharlie',
      'rotatedKeyGenerated',
      'distributedRotatedKeyToBob',
      'sentPostRemovalAtRotatedEpoch',
      'receivedBobAfterRemoval',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
    requireRotatedEpoch('alice', aliceProof, field: 'rotatedEpoch');
  }

  if (bobProof == null) {
    failures.add('bob: missing KE-006 removal-key proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'memberListExcludesCharlie',
      'receivedRotatedKey',
      'hasRotatedEpoch',
      'receivedAliceAfterRemoval',
      'sentPostRemovalAtRotatedEpoch',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireRotatedEpoch('bob', bobProof, field: 'rotatedEpoch');
  }

  if (charlieProof == null) {
    failures.add('charlie: missing KE-006 removal-key proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'onlineBeforeRemoval',
      'currentMemberBeforeRemoval',
      'excludedFromRotatedKeyDistribution',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'hasRotatedEpoch',
      'postRemovalPublishAccepted',
      'receivedAliceAfterRemoval',
      'receivedBobAfterRemoval',
    ]) {
      _requireFalseProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final excludedEpoch = _intValue(charlieProof['excludedRotatedEpoch']);
    final retainedEpoch = _intValue(charlieProof['retainedEpochAfterRemoval']);
    if (excludedEpoch == null || excludedEpoch <= 1) {
      failures.add(
        'charlie: $proofName.excludedRotatedEpoch must be a rotated epoch > 1',
      );
    }
    if (expectedRotatedEpoch != null && excludedEpoch != expectedRotatedEpoch) {
      failures.add(
        'charlie: $proofName.excludedRotatedEpoch must match Alice rotated epoch',
      );
    }
    if (retainedEpoch == null ||
        (excludedEpoch != null && retainedEpoch >= excludedEpoch)) {
      failures.add(
        'charlie: $proofName.retainedEpochAfterRemoval must stay below rotated epoch',
      );
    }
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.postRemovalPlaintextCount must be 0');
    }
  }
}

void _validatePl006RemovedMediaProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'pl006RemovedMediaProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final expectedRemovedPeerId = peerIdByRole['charlie'];
  final expectedAlicePeerId = peerIdByRole['alice'];
  final expectedBobPeerId = peerIdByRole['bob'];
  final expectedBlobId = _stringValue(aliceProof?['mediaBlobId']);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'PL-006') {
      failures.add('$role: $proofName.rowId must be PL-006');
    }
  }

  void requireMatchingBlobId(String role, Map<String, dynamic> proof) {
    final blobId = _stringValue(proof['mediaBlobId']);
    if (blobId == null || blobId.isEmpty) {
      failures.add('$role: $proofName.mediaBlobId is required');
      return;
    }
    if (expectedBlobId != null &&
        expectedBlobId.isNotEmpty &&
        blobId != expectedBlobId) {
      failures.add('$role: $proofName.mediaBlobId must match Alice upload');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing PL-006 removed-media proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlie',
      'memberListExcludesCharlie',
      'mediaUploadedAfterRemoval',
      'uploadAllowedPeersExcludeRemoved',
      'uploadAllowedPeersIncludeActive',
      'sentPostRemovalMediaAtRotatedEpoch',
      'bobReceiptSignalObserved',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
    requireMatchingBlobId('alice', aliceProof);
    final allowedPeers = _stringList(aliceProof['uploadAllowedPeers']).toSet();
    if (expectedAlicePeerId != null &&
        !allowedPeers.contains(expectedAlicePeerId)) {
      failures.add('alice: $proofName.uploadAllowedPeers missing Alice');
    }
    if (expectedBobPeerId != null &&
        !allowedPeers.contains(expectedBobPeerId)) {
      failures.add('alice: $proofName.uploadAllowedPeers missing Bob');
    }
    if (expectedRemovedPeerId != null &&
        allowedPeers.contains(expectedRemovedPeerId)) {
      failures.add('alice: $proofName.uploadAllowedPeers must exclude Charlie');
    }
    if (_intValue(aliceProof['uploadAllowedPeersCount']) != 2) {
      failures.add('alice: $proofName.uploadAllowedPeersCount must be 2');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing PL-006 removed-media proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'memberListExcludesCharlie',
      'receivedAliceAfterRemoval',
      'receivedAliceAfterRemovalAtRotatedEpoch',
      'bobReceivedMediaDescriptor',
      'bobMediaDownloaded',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(bobProof['removedPeerId']);
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('bob: $proofName.removedPeerId must be charlie');
    }
    if (_intValue(bobProof['mediaCount']) != 1) {
      failures.add('bob: $proofName.mediaCount must be 1');
    }
    requireMatchingBlobId('bob', bobProof);
  }

  if (charlieProof == null) {
    failures.add('charlie: missing PL-006 removed-media proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'onlineBeforeRemoval',
      'currentMemberBeforeRemoval',
      'directDownloadAttempted',
      'directDownloadDenied',
      'noDirectDownloadPlaintext',
      'noPostRemovalMessage',
      'replayMediaRowsAbsent',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'groupPresentAfterRemoval',
      'directDownloadOk',
    ]) {
      _requireFalseProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    requireMatchingBlobId('charlie', charlieProof);
    if (_intValue(charlieProof['directDownloadOutputBytes']) != 0) {
      failures.add('charlie: $proofName.directDownloadOutputBytes must be 0');
    }
    if (_intValue(charlieProof['postRemovalPlaintextCount']) != 0) {
      failures.add('charlie: $proofName.postRemovalPlaintextCount must be 0');
    }
    if (_intValue(charlieProof['mediaRowsAfterRemoval']) != 0) {
      failures.add('charlie: $proofName.mediaRowsAfterRemoval must be 0');
    }
    if (_intValue(charlieProof['pendingDownloadsAfterRemoval']) != 0) {
      failures.add(
        'charlie: $proofName.pendingDownloadsAfterRemoval must be 0',
      );
    }
  }
}

void _validateMl006OfflineRemovalProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ml006OfflineRemovalProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'ML-006') {
      failures.add('$role: $proofName.rowId must be ML-006');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing ML-006 offline removal proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'charlieOfflineBeforeRemoval',
      'removedCharlie',
      'memberListExcludesCharlie',
      'sentPostRemovalAccepted',
      'receivedBobAfterRemoval',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing ML-006 offline removal proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'memberListExcludesCharlie',
      'hasRotatedEpoch',
      'receivedAliceAfterRemoval',
      'sentPostRemovalAccepted',
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
    failures.add('charlie: missing ML-006 offline removal proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'hadOldConfigBeforeOffline',
      'hadOldKeyBeforeOffline',
      'offlineDuringRemoval',
      'reconnectedWithStaleState',
      'retrievedInboxAfterReconnect',
      'convergedRemoved',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'groupPresentAfterCatchUp',
      'hasRotatedEpoch',
      'postRemovalPublishAccepted',
      'receivedAliceAfterRemoval',
      'receivedBobAfterRemoval',
    ]) {
      _requireFalseProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final sendOutcome = _stringValue(charlieProof['postRemovalSendOutcome']);
    if (sendOutcome != 'groupNotFound' && sendOutcome != 'unauthorized') {
      failures.add(
        'charlie: $proofName.postRemovalSendOutcome must reject send',
      );
    }
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.postRemovalPlaintextCount must be 0');
    }
  }

  final aliceEpoch = _intValue(aliceProof?['rotatedEpoch']);
  final bobEpoch = _intValue(bobProof?['rotatedEpoch']);
  final charlieEpoch = _intValue(charlieProof?['rotatedEpoch']);
  if (aliceEpoch == null || aliceEpoch < 2) {
    failures.add('alice: $proofName.rotatedEpoch must be >= 2');
  }
  if (bobEpoch == null || bobEpoch < 2) {
    failures.add('bob: $proofName.rotatedEpoch must be >= 2');
  }
  if (aliceEpoch != null && bobEpoch != null && aliceEpoch != bobEpoch) {
    failures.add('alice/bob: ML-006 rotatedEpoch mismatch');
  }
  if (charlieEpoch != null &&
      aliceEpoch != null &&
      charlieEpoch >= aliceEpoch) {
    failures.add('charlie: $proofName must not hold rotated epoch');
  }
}

void _validateIr004PostRemovalReplayProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ir004PostRemovalReplayProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'IR-004') {
      failures.add('$role: $proofName.rowId must be IR-004');
    }
  }

  void requireRotatedEpoch(String role, Map<String, dynamic> proof) {
    final epoch = _intValue(proof['rotatedEpoch']);
    if (epoch == null || epoch < 2) {
      failures.add('$role: $proofName.rotatedEpoch must be >= 2');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing IR-004 post-removal replay proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'charlieOfflineBeforeRemoval',
      'removedCharlie',
      'memberListExcludesCharlie',
      'sentAlicePostRemoval',
      'receivedBobPostRemoval',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
    requireRotatedEpoch('alice', aliceProof);
  }

  if (bobProof == null) {
    failures.add('bob: missing IR-004 post-removal replay proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'memberListExcludesCharlie',
      'hasRotatedEpoch',
      'receivedAlicePostRemoval',
      'sentBobPostRemoval',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireRotatedEpoch('bob', bobProof);
  }

  if (charlieProof == null) {
    failures.add('charlie: missing IR-004 post-removal replay proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'hadOldConfigBeforeOffline',
      'hadOldKeyBeforeOffline',
      'offlineDuringRemoval',
      'reconnectedWithStaleState',
      'retrievedInboxAfterReconnect',
      'convergedRemoved',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    for (final field in const <String>[
      'groupPresentAfterCatchUp',
      'retainedRotatedEpoch',
      'postRemovalPublishAccepted',
      'receivedAlicePostRemoval',
      'receivedBobPostRemoval',
    ]) {
      _requireFalseProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final sendOutcome = _stringValue(charlieProof['postRemovalSendOutcome']);
    if (sendOutcome != 'groupNotFound' && sendOutcome != 'unauthorized') {
      failures.add(
        'charlie: $proofName.postRemovalSendOutcome must reject send',
      );
    }
    final plaintextCount = _intValue(charlieProof['postRemovalPlaintextCount']);
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.postRemovalPlaintextCount must be 0');
    }
    final staleEpoch = _intValue(charlieProof['staleKeyEpochBeforeDrain']);
    if (staleEpoch == null || staleEpoch < 1) {
      failures.add(
        'charlie: $proofName.staleKeyEpochBeforeDrain must be present',
      );
    }
    final rotatedAfterDrain = _intValue(charlieProof['rotatedEpochAfterDrain']);
    if (rotatedAfterDrain != null && rotatedAfterDrain >= 2) {
      failures.add(
        'charlie: $proofName.rotatedEpochAfterDrain must stay below removal epoch',
      );
    }
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

void _validateMl007ReaddCurrentProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ml007ReaddCurrentProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'ML-007') {
      failures.add('$role: $proofName.rowId must be ML-007');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing ML-007 re-add current proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlie',
      'memberListIncludesCharlie',
      'sentRemovedWindowBeforeReadd',
      'sentAlicePostReaddMessage',
      'receivedBobPostReaddMessage',
      'receivedCharliePostReaddMessage',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing ML-007 re-add current proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'memberListIncludesCharlie',
      'receivedRemovedWindowMessage',
      'sentBobPostReaddMessage',
      'receivedAlicePostReaddMessage',
      'receivedCharliePostReaddMessage',
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
    failures.add('charlie: missing ML-007 re-add current proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'memberListIncludesAliceBob',
      'memberListIncludesCharlie',
      'postReaddPublishAccepted',
      'receivedAlicePostReaddMessage',
      'receivedBobPostReaddMessage',
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
      field: 'hasStaleEpochAfterReadd',
      failures: failures,
    );
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
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
    failures.add('alice/bob/charlie: ML-007 finalEpoch mismatch');
  }
}

void _validatePl004QuoteReaddLiveProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'pl004QuoteReaddLiveProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  Map<String, dynamic>? sentEntry(String role, String key) {
    final entries = _mapList(
      byRole[role]?['sentMessages'],
    ).where((entry) => _stringValue(entry['key']) == key).toList();
    return entries.length == 1 ? entries.single : null;
  }

  Map<String, dynamic>? receivedEntry(String role, String key) {
    final entries = _mapList(
      byRole[role]?['receivedMessages'],
    ).where((entry) => _stringValue(entry['key']) == key).toList();
    return entries.length == 1 ? entries.single : null;
  }

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'PL-004') {
      failures.add('$role: $proofName.rowId must be PL-004');
    }
  }

  void requireQuoteTarget(
    String role,
    Map<String, dynamic> proof,
    String? expectedTarget,
  ) {
    if (_stringValue(proof['quoteTargetMessageId']) != expectedTarget) {
      failures.add('$role: $proofName.quoteTargetMessageId mismatch');
    }
  }

  final targetMessageId = _stringValue(
    sentEntry('alice', 'aliceAfterImmediateReadd')?['messageId'],
  );
  if (targetMessageId == null) {
    failures.add('alice: PL-004 target message is missing');
  }

  final bobSentQuoteId = _stringValue(
    sentEntry('bob', 'bobAfterReaddCurrent')?['quotedMessageId'],
  );
  final aliceReceivedQuoteId = _stringValue(
    receivedEntry('alice', 'bobAfterReaddCurrent')?['quotedMessageId'],
  );
  final charlieReceivedQuoteId = _stringValue(
    receivedEntry('charlie', 'bobAfterReaddCurrent')?['quotedMessageId'],
  );

  if (targetMessageId != null && bobSentQuoteId != targetMessageId) {
    failures.add(
      'bob: $proofName sent quote did not reference Alice post-readd target',
    );
  }
  if (targetMessageId != null && aliceReceivedQuoteId != targetMessageId) {
    failures.add(
      'alice: $proofName received quote did not reference Alice post-readd target',
    );
  }
  if (targetMessageId != null && charlieReceivedQuoteId != targetMessageId) {
    failures.add(
      'charlie: $proofName received quote did not reference Alice post-readd target',
    );
  }

  if (aliceProof == null) {
    failures.add('alice: missing PL-004 quote re-add proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'readdedCharlieBeforeQuote',
      'receivedQuotedPostReaddLive',
      'quoteTargetVisibleBeforeQuotedDelivery',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    requireQuoteTarget('alice', aliceProof, targetMessageId);
    if (_stringValue(aliceProof['receivedQuotedMessageId']) !=
        targetMessageId) {
      failures.add('alice: $proofName.receivedQuotedMessageId mismatch');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing PL-004 quote re-add proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieReaddedBeforeQuote',
      'sentQuotedPostReaddLive',
      'quoteTargetVisibleBeforeSend',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireQuoteTarget('bob', bobProof, targetMessageId);
    if (_stringValue(bobProof['sentQuotedMessageId']) != targetMessageId) {
      failures.add('bob: $proofName.sentQuotedMessageId mismatch');
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing PL-004 quote re-add proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'readdedBeforeQuotedDelivery',
      'receivedQuotedPostReaddLive',
      'quoteTargetVisibleBeforeQuotedDelivery',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    requireQuoteTarget('charlie', charlieProof, targetMessageId);
    if (_stringValue(charlieProof['receivedQuotedMessageId']) !=
        targetMessageId) {
      failures.add('charlie: $proofName.receivedQuotedMessageId mismatch');
    }
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
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
    failures.add('alice/bob/charlie: PL-004 finalEpoch mismatch');
  }
}

void _validateRa002OnlineSubscribedReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ra002OnlineSubscribedReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-002') {
      failures.add('$role: $proofName.rowId must be RA-002');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-002 online re-add proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlieWhileOnline',
      'sentRemovedWindowWhileCharlieOnline',
      'readdedCharlieWithoutRestart',
      'sentPostReaddWithoutCharlieRestart',
      'receivedCharliePostReaddWithoutRestart',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-002 online re-add proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieRemovedWhileOnline',
      'receivedRemovedWindowWhileCharlieOnline',
      'observedCharlieReaddedWithoutRestart',
      'receivedAlicePostReaddWithoutCharlieRestart',
      'sentBobPostReaddWithoutCharlieRestart',
      'receivedCharliePostReaddWithoutRestart',
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
    failures.add('charlie: missing RA-002 online re-add proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'onlineBeforeRemoval',
      'remainedProcessAliveDuringRemoval',
      'staleSubscriptionWindowCovered',
      'rejoinedWithoutRestart',
      'receivedAlicePostReaddWithoutRestart',
      'receivedBobPostReaddWithoutRestart',
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
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
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
    failures.add('alice/bob/charlie: RA-002 finalEpoch mismatch');
  }
}

void _validateRa003OfflineReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ra003OfflineReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-003') {
      failures.add('$role: $proofName.rowId must be RA-003');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-003 offline re-add proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlieWhileOffline',
      'sentRemovedWindowWhileCharlieOffline',
      'waitedForCharlieRemovalResolutionBeforeReadd',
      'readdedCharlieAfterReconnect',
      'sentPostReaddAfterOfflineReconnect',
      'receivedCharliePostReaddAfterOfflineReconnect',
      'receivedBobPostReaddAfterOfflineReconnect',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-003 offline re-add proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieRemovedWhileOffline',
      'receivedRemovedWindowWhileCharlieOffline',
      'observedCharlieReaddedAfterReconnect',
      'receivedAlicePostReaddAfterOfflineReconnect',
      'sentBobPostReaddAfterOfflineReconnect',
      'receivedCharliePostReaddAfterOfflineReconnect',
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
    failures.add('charlie: missing RA-003 offline re-add proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'offlineDuringRemoval',
      'reconnectedBeforeReadd',
      'resolvedRemovalBeforeReadd',
      'rejoinedAfterOfflineRemoval',
      'receivedAlicePostReaddAfterOfflineReconnect',
      'receivedBobPostReaddAfterOfflineReconnect',
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
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
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
    failures.add('alice/bob/charlie: RA-003 finalEpoch mismatch');
  }
}

void _validateRa017ActiveMemberChurnProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ra017ActiveMemberChurnProof';
  final expectedActiveRoles = const <String>{'alice', 'bob', 'dana'};
  final expectedFinalRoles = const <String>{'alice', 'bob', 'charlie', 'dana'};
  final finalEpochs = <int>{};

  for (final role in expectedFinalRoles) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing RA-017 active-member churn proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'RA-017') {
      failures.add('$role: $proofName.rowId must be RA-017');
    }
    final churnCycles = _intValue(proof['churnCycles']);
    if (churnCycles == null || churnCycles < 3) {
      failures.add('$role: $proofName.churnCycles must be >= 3');
    }
    for (final field in const <String>[
      'danaActiveMemberCovered',
      'finalMemberListConverged',
      'finalEpochConverged',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final activeSenders = _stringList(proof['activeSenders']).toSet();
    final activeReceivers = _stringList(proof['activeReceivers']).toSet();
    if (!activeSenders.containsAll(expectedActiveRoles)) {
      failures.add(
        '$role: $proofName.activeSenders must include alice, bob, dana',
      );
    }
    if (!activeReceivers.containsAll(expectedActiveRoles)) {
      failures.add(
        '$role: $proofName.activeReceivers must include alice, bob, dana',
      );
    }
    if (activeSenders.contains('charlie')) {
      failures.add('$role: $proofName.activeSenders must not use RA-018 churn');
    }
    final removedLeak = _intValue(proof['charlieRemovedWindowPlaintextCount']);
    if (removedLeak != 0) {
      failures.add(
        '$role: $proofName.charlieRemovedWindowPlaintextCount must be 0',
      );
    }
    final finalMembers = _stringList(proof['finalRoles']).toSet();
    if (!finalMembers.containsAll(expectedFinalRoles)) {
      failures.add(
        '$role: $proofName.finalRoles must include alice, bob, charlie, dana',
      );
    }
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 7) {
      failures.add('$role: $proofName.finalEpoch must be >= 7');
    } else {
      finalEpochs.add(finalEpoch);
    }
  }

  if (finalEpochs.length > 1) {
    failures.add('alice/bob/charlie/dana: RA-017 finalEpoch mismatch');
  }

  final danaVerdict = byRole['dana'];
  if (danaVerdict != null) {
    final danaSentKeys = _mapList(
      danaVerdict['sentMessages'],
    ).map((entry) => _stringValue(entry['key'])).whereType<String>().toSet();
    for (var cycle = 1; cycle <= 3; cycle++) {
      for (final phase in const <String>['removed', 'readd']) {
        final key = _ra017Key(cycle, phase, 'dana');
        if (!danaSentKeys.contains(key)) {
          failures.add('dana: sent $key missing from RA-017 proof');
        }
      }
    }
  }

  final charlieVerdict = byRole['charlie'];
  if (charlieVerdict != null) {
    final charlieReceivedKeys = _mapList(
      charlieVerdict['receivedMessages'],
    ).map((entry) => _stringValue(entry['key'])).whereType<String>().toSet();
    for (var cycle = 1; cycle <= 3; cycle++) {
      for (final sender in const <String>['alice', 'bob', 'dana']) {
        final removedKey = _ra017Key(cycle, 'removed', sender);
        if (charlieReceivedKeys.contains(removedKey)) {
          failures.add('charlie: removed-window RA-017 plaintext leaked');
        }
      }
    }
  }

  final expectedDanaPeerId = peerIdByRole['dana'];
  if (expectedDanaPeerId == null || expectedDanaPeerId.isEmpty) {
    failures.add('dana: RA-017 requires explicit D/Dana peer id coverage');
  }
}

void _validateRa018AlternatingChurnProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ra018AlternatingChurnProof';
  final expectedRoles = const <String>{'alice', 'bob', 'charlie', 'dana'};
  final expectedTargets = const <String>{'charlie', 'dana'};
  final finalEpochs = <int>{};

  for (final role in expectedRoles) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing RA-018 alternating churn proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'RA-018') {
      failures.add('$role: $proofName.rowId must be RA-018');
    }
    final churnCycles = _intValue(proof['churnCycles']);
    if (churnCycles == null || churnCycles < 3) {
      failures.add('$role: $proofName.churnCycles must be >= 3');
    }
    final churnTargets = _stringList(proof['churnTargets']).toSet();
    if (!churnTargets.containsAll(expectedTargets)) {
      failures.add('$role: $proofName.churnTargets must include charlie, dana');
    }
    final activeSenders = _stringList(proof['activeSenders']).toSet();
    if (!activeSenders.containsAll(expectedRoles)) {
      failures.add(
        '$role: $proofName.activeSenders must include alice, bob, charlie, dana',
      );
    }
    final activeReceivers = _stringList(proof['activeReceivers']).toSet();
    if (!activeReceivers.containsAll(expectedRoles)) {
      failures.add(
        '$role: $proofName.activeReceivers must include alice, bob, charlie, dana',
      );
    }
    for (final field in const <String>[
      'finalMemberListConverged',
      'finalEpochConverged',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final charlieLeak = _intValue(proof['charlieRemovedWindowPlaintextCount']);
    if (charlieLeak != 0) {
      failures.add(
        '$role: $proofName.charlieRemovedWindowPlaintextCount must be 0',
      );
    }
    final danaLeak = _intValue(proof['danaRemovedWindowPlaintextCount']);
    if (danaLeak != 0) {
      failures.add(
        '$role: $proofName.danaRemovedWindowPlaintextCount must be 0',
      );
    }
    final duplicateCount = _intValue(proof['duplicateVisibleMessageCount']);
    if (duplicateCount != 0) {
      failures.add('$role: $proofName.duplicateVisibleMessageCount must be 0');
    }
    final inactiveSenderAttempts = _intValue(
      proof['inactiveSenderAttemptCount'],
    );
    if (inactiveSenderAttempts != 0) {
      failures.add('$role: $proofName.inactiveSenderAttemptCount must be 0');
    }
    final finalMembers = _stringList(proof['finalRoles']).toSet();
    if (!finalMembers.containsAll(expectedRoles)) {
      failures.add(
        '$role: $proofName.finalRoles must include alice, bob, charlie, dana',
      );
    }
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 13) {
      failures.add('$role: $proofName.finalEpoch must be >= 13');
    } else {
      finalEpochs.add(finalEpoch);
    }
    _validateRa018ProofIntervals(
      role: role,
      proofName: proofName,
      proof: proof,
      failures: failures,
    );
  }

  if (finalEpochs.length > 1) {
    failures.add('alice/bob/charlie/dana: RA-018 finalEpoch mismatch');
  }

  final expectedPeerIds = <String>{
    for (final role in const <String>['alice', 'bob', 'charlie', 'dana'])
      ?peerIdByRole[role],
  };
  if (expectedPeerIds.length != 4) {
    failures.add('alice/bob/charlie/dana: RA-018 requires four peer ids');
  }

  final charlieVerdict = byRole['charlie'];
  if (charlieVerdict != null) {
    final charlieReceivedKeys = _mapList(
      charlieVerdict['receivedMessages'],
    ).map((entry) => _stringValue(entry['key'])).whereType<String>().toSet();
    for (var cycle = 1; cycle <= 3; cycle++) {
      final removedKey = _ra018Key(cycle, 'charlieRemoved', 'alice');
      if (charlieReceivedKeys.contains(removedKey)) {
        failures.add('charlie: removed-window RA-018 plaintext leaked');
      }
      final sentWhileActive = _mapList(charlieVerdict['sentMessages']).any(
        (entry) =>
            _stringValue(entry['key']) ==
            _ra018Key(cycle, 'danaRemoved', 'charlie'),
      );
      if (!sentWhileActive) {
        failures.add(
          'charlie: sent ${_ra018Key(cycle, 'danaRemoved', 'charlie')} missing from RA-018 proof',
        );
      }
    }
  }

  final danaVerdict = byRole['dana'];
  if (danaVerdict != null) {
    final danaReceivedKeys = _mapList(
      danaVerdict['receivedMessages'],
    ).map((entry) => _stringValue(entry['key'])).whereType<String>().toSet();
    final danaSentKeys = _mapList(
      danaVerdict['sentMessages'],
    ).map((entry) => _stringValue(entry['key'])).whereType<String>().toSet();
    for (var cycle = 1; cycle <= 3; cycle++) {
      final removedKey = _ra018Key(cycle, 'danaRemoved', 'charlie');
      if (danaReceivedKeys.contains(removedKey)) {
        failures.add('dana: removed-window RA-018 plaintext leaked');
      }
      final readdKey = _ra018Key(cycle, 'danaReadded', 'dana');
      if (!danaSentKeys.contains(readdKey)) {
        failures.add('dana: sent $readdKey missing from RA-018 proof');
      }
    }
  }
}

void _validateNw014ChaosInvariantProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'nw014ChaosInvariantProof';
  final expectedRoles = const <String>{'alice', 'bob', 'charlie', 'dana'};
  final expectedTargets = const <String>{'charlie', 'dana'};
  final finalEpochs = <int>{};

  for (final role in expectedRoles) {
    final proof = _mapValue(byRole[role]?[proofName]);
    if (proof == null) {
      failures.add('$role: missing NW-014 chaos invariant proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'NW-014') {
      failures.add('$role: $proofName.rowId must be NW-014');
    }
    if (_stringValue(proof['scenario']) != 'private_network_chaos_invariants') {
      failures.add('$role: $proofName.scenario mismatch');
    }
    if (_stringValue(proof['appPeerPlatform']) != 'ios_26_2_core_simulator') {
      failures.add('$role: $proofName.appPeerPlatform must be iOS 26.2');
    }
    if (_stringValue(proof['chaosProofSource']) !=
        'app_peer_core_simulator_churn_invariant_subset') {
      failures.add('$role: $proofName.chaosProofSource mismatch');
    }
    if (_intValue(proof['fixedSeed']) != 14014) {
      failures.add('$role: $proofName.fixedSeed must be 14014');
    }
    if (_stringValue(proof['modelInvariant']) !=
        'active_entitled_exactly_once') {
      failures.add('$role: $proofName.modelInvariant mismatch');
    }
    final messageOperationCount = _intValue(proof['messageOperationCount']);
    if (messageOperationCount == null || messageOperationCount < 12) {
      failures.add('$role: $proofName.messageOperationCount must be >= 12');
    }
    final membershipOperationCount = _intValue(
      proof['membershipOperationCount'],
    );
    if (membershipOperationCount == null || membershipOperationCount < 12) {
      failures.add('$role: $proofName.membershipOperationCount must be >= 12');
    }
    final churnCycles = _intValue(proof['churnCycles']);
    if (churnCycles == null || churnCycles < 3) {
      failures.add('$role: $proofName.churnCycles must be >= 3');
    }
    final churnTargets = _stringList(proof['churnTargets']).toSet();
    if (!churnTargets.containsAll(expectedTargets)) {
      failures.add('$role: $proofName.churnTargets must include charlie, dana');
    }
    final activeSenders = _stringList(proof['activeSenders']).toSet();
    if (!activeSenders.containsAll(expectedRoles)) {
      failures.add(
        '$role: $proofName.activeSenders must include alice, bob, charlie, dana',
      );
    }
    final activeReceivers = _stringList(proof['activeReceivers']).toSet();
    if (!activeReceivers.containsAll(expectedRoles)) {
      failures.add(
        '$role: $proofName.activeReceivers must include alice, bob, charlie, dana',
      );
    }
    for (final field in const <String>[
      'finalMemberListConverged',
      'finalEpochConverged',
      'fakeNetworkChaosProofRequired',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final charlieLeak = _intValue(proof['charlieRemovedWindowPlaintextCount']);
    if (charlieLeak != 0) {
      failures.add(
        '$role: $proofName.charlieRemovedWindowPlaintextCount must be 0',
      );
    }
    final danaLeak = _intValue(proof['danaRemovedWindowPlaintextCount']);
    if (danaLeak != 0) {
      failures.add(
        '$role: $proofName.danaRemovedWindowPlaintextCount must be 0',
      );
    }
    final duplicateCount = _intValue(proof['duplicateVisibleMessageCount']);
    if (duplicateCount != 0) {
      failures.add('$role: $proofName.duplicateVisibleMessageCount must be 0');
    }
    final inactiveSenderAttempts = _intValue(
      proof['inactiveSenderAttemptCount'],
    );
    if (inactiveSenderAttempts != 0) {
      failures.add('$role: $proofName.inactiveSenderAttemptCount must be 0');
    }
    final finalMembers = _stringList(proof['finalRoles']).toSet();
    if (!finalMembers.containsAll(expectedRoles)) {
      failures.add(
        '$role: $proofName.finalRoles must include alice, bob, charlie, dana',
      );
    }
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 13) {
      failures.add('$role: $proofName.finalEpoch must be >= 13');
    } else {
      finalEpochs.add(finalEpoch);
    }
    _validateRa018ProofIntervals(
      role: role,
      proofName: proofName,
      proof: proof,
      failures: failures,
    );
  }

  if (finalEpochs.length > 1) {
    failures.add('alice/bob/charlie/dana: NW-014 finalEpoch mismatch');
  }

  final expectedPeerIds = <String>{
    for (final role in const <String>['alice', 'bob', 'charlie', 'dana'])
      ?peerIdByRole[role],
  };
  if (expectedPeerIds.length != 4) {
    failures.add('alice/bob/charlie/dana: NW-014 requires four peer ids');
  }
}

void _validateRa018ProofIntervals({
  required String role,
  required String proofName,
  required Map<String, dynamic> proof,
  required List<String> failures,
}) {
  final intervals = _mapList(proof['activeIntervals']);
  for (var cycle = 1; cycle <= 3; cycle++) {
    for (final expected in _ra018ExpectedIntervalsForCycle(cycle)) {
      final matches = intervals
          .where((interval) {
            return _intValue(interval['cycle']) == cycle &&
                _stringValue(interval['operation']) == expected['operation'] &&
                _stringValue(interval['churnTarget']) ==
                    expected['churnTarget'] &&
                _stringValue(interval['sender']) == expected['sender'];
          })
          .toList(growable: false);
      if (matches.length != 1) {
        failures.add(
          '$role: $proofName.activeIntervals missing cycle $cycle '
          '${expected['operation']}',
        );
        continue;
      }
      final interval = matches.single;
      final activeRoles = _stringList(interval['activeRoles']).toSet();
      final receiverRoles = _stringList(interval['receiverRoles']).toSet();
      if (!activeRoles.containsAll(expected['activeRoles'] as Set<String>)) {
        failures.add(
          '$role: $proofName.activeIntervals cycle $cycle '
          '${expected['operation']} activeRoles mismatch',
        );
      }
      if (!receiverRoles.containsAll(
        expected['receiverRoles'] as Set<String>,
      )) {
        failures.add(
          '$role: $proofName.activeIntervals cycle $cycle '
          '${expected['operation']} receiverRoles mismatch',
        );
      }
    }
  }
}

List<Map<String, Object>> _ra018ExpectedIntervalsForCycle(int cycle) {
  return <Map<String, Object>>[
    <String, Object>{
      'cycle': cycle,
      'operation': 'charlieRemoved',
      'churnTarget': 'charlie',
      'sender': 'alice',
      'activeRoles': const <String>{'alice', 'bob', 'dana'},
      'receiverRoles': const <String>{'bob', 'dana'},
    },
    <String, Object>{
      'cycle': cycle,
      'operation': 'charlieReadded',
      'churnTarget': 'charlie',
      'sender': 'bob',
      'activeRoles': const <String>{'alice', 'bob', 'charlie', 'dana'},
      'receiverRoles': const <String>{'alice', 'charlie', 'dana'},
    },
    <String, Object>{
      'cycle': cycle,
      'operation': 'danaRemoved',
      'churnTarget': 'dana',
      'sender': 'charlie',
      'activeRoles': const <String>{'alice', 'bob', 'charlie'},
      'receiverRoles': const <String>{'alice', 'bob'},
    },
    <String, Object>{
      'cycle': cycle,
      'operation': 'danaReadded',
      'churnTarget': 'dana',
      'sender': 'dana',
      'activeRoles': const <String>{'alice', 'bob', 'charlie', 'dana'},
      'receiverRoles': const <String>{'alice', 'bob', 'charlie'},
    },
  ];
}

void _validateMl008CycleProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ml008CycleProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'ML-008') {
      failures.add('$role: $proofName.rowId must be ML-008');
    }
  }

  void requireCycleCount(String role, Map<String, dynamic> proof) {
    final count = _intValue(proof['cycleCount']);
    if (count != 20) {
      failures.add('$role: $proofName.cycleCount must be 20');
    }
  }

  void requireMinCount(
    String role,
    Map<String, dynamic> proof,
    String field,
    int minimum,
  ) {
    final count = _intValue(proof[field]);
    if (count == null || count < minimum) {
      failures.add('$role: $proofName.$field must be >= $minimum');
    }
  }

  void requireFinalConvergence(String role, Map<String, dynamic> proof) {
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'finalMemberListIncludesAliceBobCharlie',
      failures: failures,
    );
  }

  if (aliceProof == null) {
    failures.add('alice: missing ML-008 cycle proof fields');
  } else {
    requireRowId('alice', aliceProof);
    requireCycleCount('alice', aliceProof);
    requireFinalConvergence('alice', aliceProof);
    requireMinCount('alice', aliceProof, 'removedWindowSendCount', 20);
    requireMinCount('alice', aliceProof, 'sentPostReaddCount', 20);
    requireMinCount('alice', aliceProof, 'receivedCharliePostReaddCount', 20);
    requireMinCount('alice', aliceProof, 'restartMarkersObserved', 4);
  }

  if (bobProof == null) {
    failures.add('bob: missing ML-008 cycle proof fields');
  } else {
    requireRowId('bob', bobProof);
    requireCycleCount('bob', bobProof);
    requireFinalConvergence('bob', bobProof);
    requireMinCount('bob', bobProof, 'receivedRemovedWindowCount', 20);
    requireMinCount('bob', bobProof, 'receivedAlicePostReaddCount', 20);
    requireMinCount('bob', bobProof, 'receivedCharliePostReaddCount', 20);
    requireMinCount('bob', bobProof, 'bobCharlieExactMemberRowCountProofs', 20);
  }

  if (charlieProof == null) {
    failures.add('charlie: missing ML-008 cycle proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    requireCycleCount('charlie', charlieProof);
    requireFinalConvergence('charlie', charlieProof);
    requireMinCount('charlie', charlieProof, 'selfRemovalCount', 20);
    requireMinCount('charlie', charlieProof, 'receivedAlicePostReaddCount', 20);
    requireMinCount('charlie', charlieProof, 'postReaddSendCount', 20);
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
  }

  final restartTotal =
      (_intValue(bobProof?['restartMarkersPerformed']) ?? 0) +
      (_intValue(charlieProof?['restartMarkersPerformed']) ?? 0);
  if (restartTotal < 4) {
    failures.add(
      'bob/charlie: ML-008 restartMarkersPerformed total must be >= 4',
    );
  }

  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch == null || aliceEpoch < 20) {
    failures.add('alice: $proofName.finalEpoch must be >= 20');
  }
  if (bobEpoch == null || bobEpoch < 20) {
    failures.add('bob: $proofName.finalEpoch must be >= 20');
  }
  if (charlieEpoch == null || charlieEpoch < 20) {
    failures.add('charlie: $proofName.finalEpoch must be >= 20');
  }
  final epochs = <int>{};
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: ML-008 finalEpoch mismatch');
  }
}

void _validateMl009RapidReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ml009RapidReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'ML-009') {
      failures.add('$role: $proofName.rowId must be ML-009');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing ML-009 rapid re-add proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlie',
      'readdIssuedBeforeRemovalAcks',
      'sentRemovedWindowBeforeReadd',
      'sentAlicePostReaddMessage',
      'receivedBobPostReaddMessage',
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
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing ML-009 rapid re-add proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'memberListIncludesCharlie',
      'receivedRemovedWindowMessage',
      'receivedAlicePostReaddMessage',
      'sentBobPostReaddMessage',
      'staleRemoveIgnored',
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
    failures.add('charlie: missing ML-009 rapid re-add proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'memberListIncludesAliceBob',
      'memberListIncludesCharlie',
      'receivedAlicePostReaddMessage',
      'receivedBobPostReaddMessage',
      'staleRemoveIgnored',
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
      field: 'hasStaleEpochAfterReadd',
      failures: failures,
    );
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
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
    failures.add('alice/bob/charlie: ML-009 finalEpoch mismatch');
  }
}

void _validatePl007ReaddMediaProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'pl007ReaddMediaProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);
  final expectedAlicePeerId = peerIdByRole['alice'];
  final expectedBobPeerId = peerIdByRole['bob'];
  final expectedCharliePeerId = peerIdByRole['charlie'];
  final expectedRemovedBlobId = _stringValue(
    aliceProof?['removedWindowMediaBlobId'],
  );
  final expectedPostReaddBlobId = _stringValue(
    aliceProof?['postReaddMediaBlobId'],
  );

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'PL-007') {
      failures.add('$role: $proofName.rowId must be PL-007');
    }
  }

  void requireMessageKeys(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['removedWindowMessageKey']) !=
        'aliceDuringCharlieRemoval') {
      failures.add(
        '$role: $proofName.removedWindowMessageKey must be aliceDuringCharlieRemoval',
      );
    }
    if (_stringValue(proof['postReaddMessageKey']) !=
        'aliceAfterImmediateReadd') {
      failures.add(
        '$role: $proofName.postReaddMessageKey must be aliceAfterImmediateReadd',
      );
    }
  }

  void requireBlobIds(String role, Map<String, dynamic> proof) {
    final removedBlobId = _stringValue(proof['removedWindowMediaBlobId']);
    final postReaddBlobId = _stringValue(proof['postReaddMediaBlobId']);
    if (removedBlobId == null || removedBlobId.isEmpty) {
      failures.add('$role: $proofName.removedWindowMediaBlobId is required');
    }
    if (postReaddBlobId == null || postReaddBlobId.isEmpty) {
      failures.add('$role: $proofName.postReaddMediaBlobId is required');
    }
    if (removedBlobId != null &&
        postReaddBlobId != null &&
        removedBlobId == postReaddBlobId) {
      failures.add(
        '$role: $proofName removed-window and post-readd media blob ids must differ',
      );
    }
    if (expectedRemovedBlobId != null &&
        expectedRemovedBlobId.isNotEmpty &&
        removedBlobId != expectedRemovedBlobId) {
      failures.add(
        '$role: $proofName.removedWindowMediaBlobId must match Alice removed-window media',
      );
    }
    if (expectedPostReaddBlobId != null &&
        expectedPostReaddBlobId.isNotEmpty &&
        postReaddBlobId != expectedPostReaddBlobId) {
      failures.add(
        '$role: $proofName.postReaddMediaBlobId must match Alice post-readd media',
      );
    }
  }

  void requireFinalEpoch(String role, Map<String, dynamic> proof) {
    final epoch = _intValue(proof['finalEpoch']);
    if (epoch == null || epoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing PL-007 re-add media proof fields');
  } else {
    requireRowId('alice', aliceProof);
    requireBlobIds('alice', aliceProof);
    requireMessageKeys('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlie',
      'removedWindowSentWhileCharlieRemoved',
      'postReaddMediaSentAfterReadd',
      'removedWindowMediaSentAtCurrentEpoch',
      'postReaddMediaSentAtCurrentEpoch',
      'removedWindowAllowedPeersExcludeCharlie',
      'removedWindowAllowedPeersIncludeActive',
      'postReaddAllowedPeersIncludeAll',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    if (expectedCharliePeerId != null &&
        removedPeerId != expectedCharliePeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
    final removedAllowedPeers = _stringList(
      aliceProof['removedWindowAllowedPeers'],
    ).toSet();
    if (expectedAlicePeerId != null &&
        !removedAllowedPeers.contains(expectedAlicePeerId)) {
      failures.add('alice: $proofName.removedWindowAllowedPeers missing Alice');
    }
    if (expectedBobPeerId != null &&
        !removedAllowedPeers.contains(expectedBobPeerId)) {
      failures.add('alice: $proofName.removedWindowAllowedPeers missing Bob');
    }
    if (expectedCharliePeerId != null &&
        removedAllowedPeers.contains(expectedCharliePeerId)) {
      failures.add(
        'alice: $proofName.removedWindowAllowedPeers must exclude Charlie',
      );
    }
    if (_intValue(aliceProof['removedWindowAllowedPeersCount']) != 2) {
      failures.add(
        'alice: $proofName.removedWindowAllowedPeersCount must be 2',
      );
    }
    final postAllowedPeers = _stringList(
      aliceProof['postReaddAllowedPeers'],
    ).toSet();
    for (final entry in <String, String?>{
      'Alice': expectedAlicePeerId,
      'Bob': expectedBobPeerId,
      'Charlie': expectedCharliePeerId,
    }.entries) {
      final peerId = entry.value;
      if (peerId != null && !postAllowedPeers.contains(peerId)) {
        failures.add(
          'alice: $proofName.postReaddAllowedPeers missing ${entry.key}',
        );
      }
    }
    if (_intValue(aliceProof['postReaddAllowedPeersCount']) != 3) {
      failures.add('alice: $proofName.postReaddAllowedPeersCount must be 3');
    }
    requireFinalEpoch('alice', aliceProof);
  }

  if (bobProof == null) {
    failures.add('bob: missing PL-007 re-add media proof fields');
  } else {
    requireRowId('bob', bobProof);
    requireBlobIds('bob', bobProof);
    requireMessageKeys('bob', bobProof);
    for (final field in const <String>[
      'retainedActiveMembershipDuringRemovedWindow',
      'removedWindowMediaMessageReceived',
      'removedWindowMediaDownloaded',
      'removedWindowMediaPersisted',
      'postReaddMediaMessageReceived',
      'postReaddMediaDownloaded',
      'postReaddMediaPersisted',
      'postReaddMediaDecrypted',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireFinalEpoch('bob', bobProof);
  }

  if (charlieProof == null) {
    failures.add('charlie: missing PL-007 re-add media proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    requireBlobIds('charlie', charlieProof);
    requireMessageKeys('charlie', charlieProof);
    for (final field in const <String>[
      'memberListIncludesAliceBob',
      'memberListIncludesCharlie',
      'removedWindowDirectDownloadAttempted',
      'removedWindowDirectDownloadDenied',
      'noRemovedWindowMediaPlaintext',
      'postReaddMediaMessageReceived',
      'postReaddMediaDownloaded',
      'postReaddMediaPersisted',
      'postReaddMediaDecrypted',
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
      field: 'removedWindowDirectDownloadOk',
      failures: failures,
    );
    for (final field in const <String>[
      'removedWindowMediaMessageCount',
      'removedWindowMediaRowsBeforeReadd',
      'removedWindowMediaRowsAfterReadd',
      'removedWindowPendingDownloadsBeforeReadd',
      'pendingDownloadsAfterPostReadd',
      'removedWindowDirectDownloadOutputBytes',
    ]) {
      if (_intValue(charlieProof[field]) != 0) {
        failures.add('charlie: $proofName.$field must be 0');
      }
    }
    if (_intValue(charlieProof['postReaddMediaRows']) != 1) {
      failures.add('charlie: $proofName.postReaddMediaRows must be 1');
    }
    final postReaddEpoch = _intValue(charlieProof['postReaddMediaEpoch']);
    if (postReaddEpoch == null || postReaddEpoch < 2) {
      failures.add('charlie: $proofName.postReaddMediaEpoch must be >= 2');
    }
    requireFinalEpoch('charlie', charlieProof);
  }
}

void _validateKe008ReaddActivationProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ke008ReaddActivationProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'KE-008') {
      failures.add('$role: $proofName.rowId must be KE-008');
    }
  }

  void requireEpochAtLeastTwo(
    String role,
    Map<String, dynamic> proof,
    String field,
  ) {
    final epoch = _intValue(proof[field]);
    if (epoch == null || epoch < 2) {
      failures.add('$role: $proofName.$field must be >= 2');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing KE-008 re-add activation proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'readdCurrentKeyAvailableBeforeFixture',
      'wroteReaddFixtureWithCurrentKey',
      'waitedForCharlieCurrentKeyRejoinBeforePostReaddSends',
      'charlieAcknowledgedRejoinAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    requireEpochAtLeastTwo('alice', aliceProof, 'readdEpoch');
    requireEpochAtLeastTwo('alice', aliceProof, 'finalEpoch');
  }

  if (bobProof == null) {
    failures.add('bob: missing KE-008 re-add activation proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieReadded',
      'receivedCharliePostReaddAtCurrentEpoch',
      'sentBobPostReaddAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireEpochAtLeastTwo('bob', bobProof, 'finalEpoch');
  }

  if (charlieProof == null) {
    failures.add('charlie: missing KE-008 re-add activation proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'importedCurrentEpochBeforeRejoinAck',
      'rejoinAcknowledgedAfterCurrentKey',
      'memberListIncludesAliceBob',
      'memberListIncludesCharlie',
      'hasCurrentEpochBeforePostReaddPublish',
      'postReaddPublishAccepted',
      'receivedAlicePostReaddAtCurrentEpoch',
      'receivedBobPostReaddAtCurrentEpoch',
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
      field: 'hasStaleEpochAfterReadd',
      failures: failures,
    );
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
    requireEpochAtLeastTwo('charlie', charlieProof, 'epochBeforeRejoinAck');
    requireEpochAtLeastTwo('charlie', charlieProof, 'postReaddPublishEpoch');
    requireEpochAtLeastTwo('charlie', charlieProof, 'finalEpoch');
  }

  final epochs = <int>{};
  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: KE-008 finalEpoch mismatch');
  }
}

void _validateKe010KeyBeforeConfigProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ke010KeyBeforeConfigProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'KE-010') {
      failures.add('$role: $proofName.rowId must be KE-010');
    }
  }

  void requireEpochAtLeastTwo(
    String role,
    Map<String, dynamic> proof,
    String field,
  ) {
    final epoch = _intValue(proof[field]);
    if (epoch == null || epoch < 2) {
      failures.add('$role: $proofName.$field must be >= 2');
    }
  }

  void requireSharedFields(String role, Map<String, dynamic> proof) {
    requireRowId(role, proof);
    for (final field in const <String>[
      'keyBeforeConfigOrderingCoveredByFakeNetwork',
      'liveAuthorizedDeliveryCovered',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    requireEpochAtLeastTwo(role, proof, 'finalEpoch');
  }

  if (aliceProof == null) {
    failures.add('alice: missing KE-010 key-before-config proof fields');
  } else {
    requireSharedFields('alice', aliceProof);
    _requireTrueProof(
      role: 'alice',
      proofName: proofName,
      proof: aliceProof,
      field: 'sentPostConfigAuthorizedAtCurrentEpoch',
      failures: failures,
    );
  }

  if (bobProof == null) {
    failures.add('bob: missing KE-010 key-before-config proof fields');
  } else {
    requireSharedFields('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieAuthorized',
      'receivedCharliePostConfigAtCurrentEpoch',
      'sentBobPostConfigAtCurrentEpoch',
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
    failures.add('charlie: missing KE-010 key-before-config proof fields');
  } else {
    requireSharedFields('charlie', charlieProof);
    for (final field in const <String>[
      'noPreConfigPlaintextDespiteKey',
      'receivedAlicePostConfigAtCurrentEpoch',
      'receivedBobPostConfigAtCurrentEpoch',
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

  final epochs = <int>{};
  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: KE-010 finalEpoch mismatch');
  }
}

void _validateKe011DelayedOldKeyAfterReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  _validateDelayedOldKeyAfterReaddProof(
    byRole: byRole,
    failures: failures,
    proofName: 'ke011DelayedOldKeyAfterReaddProof',
    rowId: 'KE-011',
    label: 'KE-011',
  );
}

void _validateRa006DelayedOldKeyAfterReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  _validateDelayedOldKeyAfterReaddProof(
    byRole: byRole,
    failures: failures,
    proofName: 'ra006DelayedOldKeyAfterReaddProof',
    rowId: 'RA-006',
    label: 'RA-006',
  );
}

void _validateDelayedOldKeyAfterReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
  required String proofName,
  required String rowId,
  required String label,
}) {
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != rowId) {
      failures.add('$role: $proofName.rowId must be $rowId');
    }
  }

  void requireEpochAtLeastTwo(
    String role,
    Map<String, dynamic> proof,
    String field,
  ) {
    final epoch = _intValue(proof[field]);
    if (epoch == null || epoch < 2) {
      failures.add('$role: $proofName.$field must be >= 2');
    }
  }

  void requireSharedFields(String role, Map<String, dynamic> proof) {
    requireRowId(role, proof);
    for (final field in const <String>[
      'delayedOldKeyOrderingCoveredByFakeNetwork',
      'livePostStaleDeliveryCovered',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final staleEpoch = _intValue(proof['staleEpoch']);
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (staleEpoch == null || staleEpoch >= 2) {
      failures.add('$role: $proofName.staleEpoch must be lower than 2');
    }
    requireEpochAtLeastTwo(role, proof, 'finalEpoch');
    if (staleEpoch != null && finalEpoch != null && staleEpoch >= finalEpoch) {
      failures.add(
        '$role: $proofName.staleEpoch must be lower than finalEpoch',
      );
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing $label delayed old key proof fields');
  } else {
    requireSharedFields('alice', aliceProof);
    for (final field in const <String>[
      'deliveredDelayedOldKeyAfterReadd',
      'sentAlicePostStaleAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing $label delayed old key proof fields');
  } else {
    requireSharedFields('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieReadded',
      'receivedCharliePostStaleAtCurrentEpoch',
      'sentBobPostStaleAtCurrentEpoch',
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
    failures.add('charlie: missing $label delayed old key proof fields');
  } else {
    requireSharedFields('charlie', charlieProof);
    for (final field in const <String>[
      'keptCurrentEpochAfterDelayedOldKey',
      'storedDelayedOldKeyAsHistorical',
      'postStalePublishAccepted',
      'receivedAlicePostStaleAtCurrentEpoch',
      'receivedBobPostStaleAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final before = _intValue(charlieProof['epochBeforeDelayedOldKey']);
    final after = _intValue(charlieProof['epochAfterDelayedOldKey']);
    if (before == null || before < 2) {
      failures.add('charlie: $proofName.epochBeforeDelayedOldKey must be >= 2');
    }
    if (after == null || after < 2) {
      failures.add('charlie: $proofName.epochAfterDelayedOldKey must be >= 2');
    }
    if (before != null && after != null && before != after) {
      failures.add(
        'charlie: $proofName epochAfterDelayedOldKey must equal epochBeforeDelayedOldKey',
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
    failures.add('alice/bob/charlie: $label finalEpoch mismatch');
  }
}

void _validateRa007PartitionedObserverReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ra007PartitionedObserverReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-007') {
      failures.add('$role: $proofName.rowId must be RA-007');
    }
  }

  void requireSharedFields(String role, Map<String, dynamic> proof) {
    requireRowId(role, proof);
    for (final field in const <String>[
      'partitionedObserverOrderingCoveredByFakeNetwork',
      'livePostHealDeliveryCovered',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-007 partitioned observer proof fields');
  } else {
    requireSharedFields('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlie',
      'sentRemovedWindowWhileBobPartitionedCoveredByFakeNetwork',
      'sentAlicePostHealAtCurrentEpoch',
      'receivedBobPostHealAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-007 partitioned observer proof fields');
  } else {
    requireSharedFields('bob', bobProof);
    for (final field in const <String>[
      'activeObserverPartitionCoveredByFakeNetwork',
      'retainedEntitledRemovedWindowCoveredByFakeNetwork',
      'observedCharlieReadded',
      'receivedAlicePostHealAtCurrentEpoch',
      'receivedCharliePostHealAtCurrentEpoch',
      'sentBobPostHealAtCurrentEpoch',
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
    failures.add('charlie: missing RA-007 partitioned observer proof fields');
  } else {
    requireSharedFields('charlie', charlieProof);
    for (final field in const <String>[
      'bobPartitionDoesNotLeakRemovedWindowCoveredByFakeNetwork',
      'postHealPublishAccepted',
      'receivedAlicePostHealAtCurrentEpoch',
      'receivedBobPostHealAtCurrentEpoch',
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
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
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
    failures.add('alice/bob/charlie: RA-007 finalEpoch mismatch');
  }
}

void _validateRa008PartitionedRemovedReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ra008PartitionedRemovedReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-008') {
      failures.add('$role: $proofName.rowId must be RA-008');
    }
  }

  void requireSharedFields(String role, Map<String, dynamic> proof) {
    requireRowId(role, proof);
    for (final field in const <String>[
      'removedPeerPartitionOrderingCoveredByFakeNetwork',
      'livePostHealDeliveryCovered',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-008 removed peer partition proof fields');
  } else {
    requireSharedFields('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlie',
      'sentRemovedWindowWhileCharliePartitionedCoveredByFakeNetwork',
      'sentAlicePostHealAtCurrentEpoch',
      'receivedBobPostHealAtCurrentEpoch',
      'receivedCharliePostHealAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-008 removed peer partition proof fields');
  } else {
    requireSharedFields('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieRemoved',
      'receivedRemovedWindowWhileCharliePartitionedCoveredByFakeNetwork',
      'observedCharlieReadded',
      'receivedAlicePostHealAtCurrentEpoch',
      'receivedCharliePostHealAtCurrentEpoch',
      'sentBobPostHealAtCurrentEpoch',
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
    failures.add('charlie: missing RA-008 removed peer partition proof fields');
  } else {
    requireSharedFields('charlie', charlieProof);
    for (final field in const <String>[
      'missedRemovalBeforeReaddCoveredByFakeNetwork',
      'postHealPublishAccepted',
      'receivedAlicePostHealAtCurrentEpoch',
      'receivedBobPostHealAtCurrentEpoch',
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
    final plaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (plaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
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
    failures.add('alice/bob/charlie: RA-008 finalEpoch mismatch');
  }
}

void _validateRa009FirstReaddPublishProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ra009FirstReaddPublishProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-009') {
      failures.add('$role: $proofName.rowId must be RA-009');
    }
  }

  void requireSharedFields(String role, Map<String, dynamic> proof) {
    requireRowId(role, proof);
    for (final field in const <String>[
      'firstReaddPublishOrderingCoveredByFakeNetwork',
      'liveFirstReaddPublishCovered',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  void requireMessageKey(
    String role,
    Map<String, dynamic> proof,
    String field,
  ) {
    if (_stringValue(proof[field]) != 'charlieAfterImmediateReadd') {
      failures.add(
        '$role: $proofName.$field must be charlieAfterImmediateReadd',
      );
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-009 first re-add publish proof fields');
  } else {
    requireSharedFields('alice', aliceProof);
    for (final field in const <String>[
      'readdedCharlie',
      'receivedCharlieFirstPostReaddAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    requireMessageKey('alice', aliceProof, 'firstCharliePostReaddMessageKey');
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-009 first re-add publish proof fields');
  } else {
    requireSharedFields('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieReadded',
      'receivedCharlieFirstPostReaddAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireMessageKey('bob', bobProof, 'firstCharliePostReaddMessageKey');
  }

  if (charlieProof == null) {
    failures.add('charlie: missing RA-009 first re-add publish proof fields');
  } else {
    requireSharedFields('charlie', charlieProof);
    for (final field in const <String>[
      'sentFirstPostReaddAtCurrentEpoch',
      'firstPostReaddPublishAccepted',
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
    requireMessageKey('charlie', charlieProof, 'firstPostReaddMessageKey');
  }

  final epochs = <int>{};
  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: RA-009 finalEpoch mismatch');
  }
}

void _validateRa010ReaddIncomingRestartProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ra010ReaddIncomingRestartProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-010') {
      failures.add('$role: $proofName.rowId must be RA-010');
    }
  }

  void requireSharedFields(String role, Map<String, dynamic> proof) {
    requireRowId(role, proof);
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'liveIncomingBeforeAndAfterRestartCovered',
      failures: failures,
    );
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  void requireMessageKey(
    String role,
    Map<String, dynamic> proof,
    String field,
    String expected,
  ) {
    if (_stringValue(proof[field]) != expected) {
      failures.add('$role: $proofName.$field must be $expected');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-010 incoming restart proof fields');
  } else {
    requireSharedFields('alice', aliceProof);
    for (final field in const <String>[
      'readdedCharlie',
      'sentFirstIncomingBeforeCharlieRestartAtCurrentEpoch',
      'sentSecondIncomingAfterCharlieRestartAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    requireMessageKey(
      'alice',
      aliceProof,
      'firstIncomingMessageKey',
      'aliceAfterImmediateReadd',
    );
    requireMessageKey(
      'alice',
      aliceProof,
      'postRestartIncomingMessageKey',
      'aliceAfterCharlieRestart',
    );
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-010 incoming restart proof fields');
  } else {
    requireSharedFields('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieReadded',
      'receivedAlicePostRestartAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: proofName,
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
    requireMessageKey(
      'bob',
      bobProof,
      'postRestartIncomingMessageKey',
      'aliceAfterCharlieRestart',
    );
  }

  if (charlieProof == null) {
    failures.add('charlie: missing RA-010 incoming restart proof fields');
  } else {
    requireSharedFields('charlie', charlieProof);
    for (final field in const <String>[
      'receivedFirstIncomingBeforeRestartAtCurrentEpoch',
      'restartPreservedCurrentGroupKeyConfig',
      'receivedSecondIncomingAfterRestartAtCurrentEpoch',
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
    requireMessageKey(
      'charlie',
      charlieProof,
      'firstIncomingMessageKey',
      'aliceAfterImmediateReadd',
    );
    requireMessageKey(
      'charlie',
      charlieProof,
      'postRestartIncomingMessageKey',
      'aliceAfterCharlieRestart',
    );
  }

  final epochs = <int>{};
  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: RA-010 finalEpoch mismatch');
  }
}

void _validateRa014OldKeyPublishAfterReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ra014OldKeyPublishAfterReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-014') {
      failures.add('$role: $proofName.rowId must be RA-014');
    }
  }

  void requireSharedFields(String role, Map<String, dynamic> proof) {
    requireRowId(role, proof);
    for (final field in const <String>[
      'staleOldPublishRejectionCoveredByFakeNetwork',
      'nativeOldKeyPublishRejectionCovered',
      'livePostRejectDeliveryCovered',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final staleEpoch = _intValue(proof['staleEpoch']);
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (staleEpoch == null || staleEpoch >= 2) {
      failures.add('$role: $proofName.staleEpoch must be lower than 2');
    }
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
    if (staleEpoch != null && finalEpoch != null && staleEpoch >= finalEpoch) {
      failures.add(
        '$role: $proofName.staleEpoch must be lower than finalEpoch',
      );
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-014 old-key publish proof fields');
  } else {
    requireSharedFields('alice', aliceProof);
    for (final field in const <String>[
      'rejectedCharlieOldKeyPublish',
      'sentAliceCurrentAfterReject',
      'receivedCharlieCurrentAfterReject',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-014 old-key publish proof fields');
  } else {
    requireSharedFields('bob', bobProof);
    for (final field in const <String>[
      'rejectedCharlieOldKeyPublish',
      'receivedAliceCurrentAfterReject',
      'receivedCharlieCurrentAfterReject',
      'sentBobCurrentAfterReject',
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
    failures.add('charlie: missing RA-014 old-key publish proof fields');
  } else {
    requireSharedFields('charlie', charlieProof);
    for (final field in const <String>[
      'oldKeyPublishRejected',
      'postRejectPublishAccepted',
      'receivedAlicePostRejectAtCurrentEpoch',
      'receivedBobPostRejectAtCurrentEpoch',
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
  }

  final epochs = <int>{};
  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: RA-014 finalEpoch mismatch');
  }
}

void _validateRa015AlreadyJoinedReaddRefreshProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ra015AlreadyJoinedReaddRefreshProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-015') {
      failures.add('$role: $proofName.rowId must be RA-015');
    }
  }

  void requireSharedFields(String role, Map<String, dynamic> proof) {
    requireRowId(role, proof);
    for (final field in const <String>[
      'flutterAlreadyJoinedPayloadCoveredByHost',
      'nativeAlreadyJoinedRefreshCovered',
      'fakeNetworkAlreadyJoinedReaddCovered',
      'livePostRefreshDeliveryCovered',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-015 already-joined re-add proof fields');
  } else {
    requireSharedFields('alice', aliceProof);
    for (final field in const <String>[
      'readdedCharlie',
      'sentAliceCurrentAfterRefresh',
      'receivedCharlieCurrentAfterRefresh',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-015 already-joined re-add proof fields');
  } else {
    requireSharedFields('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieReadded',
      'receivedAliceCurrentAfterRefresh',
      'receivedCharlieCurrentAfterRefresh',
      'sentBobCurrentAfterRefresh',
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
    failures.add('charlie: missing RA-015 already-joined re-add proof fields');
  } else {
    requireSharedFields('charlie', charlieProof);
    for (final field in const <String>[
      'alreadyJoinedReaddRefreshAccepted',
      'importedCurrentConfigBeforeRejoinAck',
      'postRefreshPublishAccepted',
      'receivedAlicePostRefreshAtCurrentEpoch',
      'receivedBobPostRefreshAtCurrentEpoch',
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
  }

  final epochs = <int>{};
  final aliceEpoch = _intValue(aliceProof?['finalEpoch']);
  final bobEpoch = _intValue(bobProof?['finalEpoch']);
  final charlieEpoch = _intValue(charlieProof?['finalEpoch']);
  if (aliceEpoch != null) epochs.add(aliceEpoch);
  if (bobEpoch != null) epochs.add(bobEpoch);
  if (charlieEpoch != null) epochs.add(charlieEpoch);
  if (epochs.length > 1) {
    failures.add('alice/bob/charlie: RA-015 finalEpoch mismatch');
  }
}

void _validateRa016RemovedIntervalReplayProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ra016RemovedIntervalReplayProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireSharedFields(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-016') {
      failures.add('$role: $proofName.rowId must be RA-016');
    }
    for (final field in const <String>[
      'hostDirectRemovedIntervalReplayCovered',
      'hostFakeNetworkRemovedIntervalReplayCovered',
      'removedIntervalReplayRejectedByRecipientInterval',
      'livePostReaddCurrentDeliveryCovered',
      'memberListIncludesAliceBob',
      'memberListIncludesCharlie',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-016 removed-interval replay proof fields');
  } else {
    requireSharedFields('alice', aliceProof);
    for (final field in const <String>[
      'sentAlicePostReaddCurrent',
      'receivedBobPostReaddCurrent',
      'receivedCharliePostReaddCurrent',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-016 removed-interval replay proof fields');
  } else {
    requireSharedFields('bob', bobProof);
    for (final field in const <String>[
      'receivedAlicePostReaddCurrent',
      'sentBobPostReaddCurrent',
      'receivedCharliePostReaddCurrent',
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
      'charlie: missing RA-016 removed-interval replay proof fields',
    );
  } else {
    requireSharedFields('charlie', charlieProof);
    for (final field in const <String>[
      'postReaddPublishAccepted',
      'receivedAlicePostReaddCurrent',
      'receivedBobPostReaddCurrent',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final removedWindowPlaintextCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (removedWindowPlaintextCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
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
    failures.add('alice/bob/charlie: RA-016 finalEpoch mismatch');
  }
}

void _validateRa011LateLeaveReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ra011LateLeaveReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-011') {
      failures.add('$role: $proofName.rowId must be RA-011');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-011 late leave re-add proof fields');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlie',
      'observedCharlieLeaveStartedBeforeReadd',
      'readdedCharlieBeforeLateLeaveCompleted',
      'receivedCharliePostLateLeaveRepair',
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
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-011 late leave re-add proof fields');
  } else {
    requireRowId('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieRemoved',
      'observedCharlieReadded',
      'receivedAlicePostLateLeaveRepair',
      'receivedCharliePostLateLeaveRepair',
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
    failures.add('charlie: missing RA-011 late leave re-add proof fields');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in const <String>[
      'leaveStartedBeforeReadd',
      'importedReaddBeforeLateLeaveCompleted',
      'lateLeaveRepairJoinCompleted',
      'postReaddPublishAccepted',
      'receivedAlicePostLateLeaveRepair',
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
    failures.add('alice/bob/charlie: RA-011 finalEpoch mismatch');
  }
}

void _validateRa012RotatedDeviceReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ra012RotatedDeviceReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireCommonMaterial(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-012') {
      failures.add('$role: $proofName.rowId must be RA-012');
    }
    for (final field in const <String>[
      'samePeerIdReadded',
      'memberConfigUsesRotatedDeviceMaterial',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    _requireFalseProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'oldDeviceMaterialRetained',
      failures: failures,
    );

    final oldMlKem = _stringValue(proof['oldMlKemPublicKey']);
    final rotatedMlKem = _stringValue(proof['rotatedMlKemPublicKey']);
    final oldKeyPackage = _stringValue(proof['oldKeyPackageId']);
    final rotatedKeyPackage = _stringValue(proof['rotatedKeyPackageId']);
    if (oldMlKem == null || oldMlKem.isEmpty) {
      failures.add('$role: $proofName.oldMlKemPublicKey is required');
    }
    if (rotatedMlKem == null || rotatedMlKem.isEmpty) {
      failures.add('$role: $proofName.rotatedMlKemPublicKey is required');
    }
    if (oldMlKem != null && rotatedMlKem != null && oldMlKem == rotatedMlKem) {
      failures.add('$role: RA-012 ML-KEM material must rotate');
    }
    if (oldKeyPackage == null || oldKeyPackage.isEmpty) {
      failures.add('$role: $proofName.oldKeyPackageId is required');
    }
    if (rotatedKeyPackage == null || rotatedKeyPackage.isEmpty) {
      failures.add('$role: $proofName.rotatedKeyPackageId is required');
    }
    if (oldKeyPackage != null &&
        rotatedKeyPackage != null &&
        oldKeyPackage == rotatedKeyPackage) {
      failures.add('$role: RA-012 key package must rotate');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing RA-012 rotated device re-add proof fields');
  } else {
    requireCommonMaterial('alice', aliceProof);
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlieWithRotatedMaterial',
      'receivedCharliePostRotatedReadd',
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
    final removedPeerId = _stringValue(aliceProof['removedPeerId']);
    final expectedRemovedPeerId = peerIdByRole['charlie'];
    if (expectedRemovedPeerId != null &&
        removedPeerId != expectedRemovedPeerId) {
      failures.add('alice: $proofName.removedPeerId must be charlie');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing RA-012 rotated device re-add proof fields');
  } else {
    requireCommonMaterial('bob', bobProof);
    for (final field in const <String>[
      'observedCharlieRemoved',
      'observedCharlieReaddedWithRotatedMaterial',
      'receivedAlicePostRotatedReadd',
      'receivedCharliePostRotatedReadd',
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
    failures.add('charlie: missing RA-012 rotated device re-add proof fields');
  } else {
    requireCommonMaterial('charlie', charlieProof);
    for (final field in const <String>[
      'importedRotatedMaterial',
      'postRotatedReaddPublishAccepted',
      'receivedAlicePostRotatedReadd',
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
    failures.add('alice/bob/charlie: RA-012 finalEpoch mismatch');
  }

  final rotatedMlKems = <String>{};
  final rotatedKeyPackages = <String>{};
  for (final proof in <Map<String, dynamic>?>[
    aliceProof,
    bobProof,
    charlieProof,
  ]) {
    final mlKem = _stringValue(proof?['rotatedMlKemPublicKey']);
    final keyPackage = _stringValue(proof?['rotatedKeyPackageId']);
    if (mlKem != null && mlKem.isNotEmpty) rotatedMlKems.add(mlKem);
    if (keyPackage != null && keyPackage.isNotEmpty) {
      rotatedKeyPackages.add(keyPackage);
    }
  }
  if (rotatedMlKems.length > 1) {
    failures.add('alice/bob/charlie: RA-012 rotated ML-KEM mismatch');
  }
  if (rotatedKeyPackages.length > 1) {
    failures.add('alice/bob/charlie: RA-012 rotated key package mismatch');
  }
}

void _validateRa013SameUserMultiDeviceReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required Map<String, String> peerIdByRole,
  required List<String> failures,
}) {
  const proofName = 'ra013SameUserMultiDeviceReaddProof';
  final proofs = <String, Map<String, dynamic>?>{
    for (final role in const <String>['alice', 'bob', 'charlie', 'dana'])
      role: _mapValue(byRole[role]?[proofName]),
  };
  final charliePeerId = peerIdByRole['charlie'];
  final danaPeerId = peerIdByRole['dana'];

  void requireCommon(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'RA-013') {
      failures.add('$role: $proofName.rowId must be RA-013');
    }
    if (charliePeerId != null &&
        _stringValue(proof['sameAccountPeerId']) != charliePeerId) {
      failures.add('$role: $proofName.sameAccountPeerId must be charlie');
    }
    final phoneDeviceId = _stringValue(proof['phoneDeviceId']);
    final tabletDeviceId = _stringValue(proof['tabletDeviceId']);
    if (phoneDeviceId == null || phoneDeviceId.isEmpty) {
      failures.add('$role: $proofName.phoneDeviceId is required');
    }
    if (tabletDeviceId == null || tabletDeviceId.isEmpty) {
      failures.add('$role: $proofName.tabletDeviceId is required');
    }
    if (phoneDeviceId != null &&
        tabletDeviceId != null &&
        phoneDeviceId == tabletDeviceId) {
      failures.add('$role: RA-013 phone/tablet device ids must differ');
    }
    _requireTrueProof(
      role: role,
      proofName: proofName,
      proof: proof,
      field: 'distinctDeviceIds',
      failures: failures,
    );
    final finalEpoch = _intValue(proof['finalEpoch']);
    if (finalEpoch == null || finalEpoch < 2) {
      failures.add('$role: $proofName.finalEpoch must be >= 2');
    }
  }

  for (final entry in proofs.entries) {
    final proof = entry.value;
    if (proof == null) {
      failures.add(
        '${entry.key}: missing RA-013 same-user device proof fields',
      );
    } else {
      requireCommon(entry.key, proof);
    }
  }

  final aliceProof = proofs['alice'];
  if (aliceProof != null) {
    for (final field in const <String>[
      'removedCharlie',
      'readdedCharlieWithTwoDevices',
      'phoneAcceptedBeforeTablet',
      'tabletPendingWhilePhoneJoined',
      'sentRemovedWindowMessage',
      'sentPostPhoneAcceptMessage',
      'sentPostTabletAcceptMessage',
      'receivedTabletPostAcceptMessage',
      'removedWindowRecipientExcludedTablet',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  final bobProof = proofs['bob'];
  if (bobProof != null) {
    for (final field in const <String>[
      'observedCharlieRemoved',
      'observedCharlieReaddedWithTwoDevices',
      'receivedRemovedWindowAsActiveMember',
      'receivedPostPhoneAccept',
      'receivedPostTabletAccept',
      'receivedTabletDevicePostAccept',
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
    _requireFalseProof(
      role: 'bob',
      proofName: proofName,
      proof: bobProof,
      field: 'memberListIncludesDanaAccount',
      failures: failures,
    );
  }

  final charlieProof = proofs['charlie'];
  if (charlieProof != null) {
    for (final field in const <String>[
      'phoneAcceptedOwnInvite',
      'tabletDeviceInMemberConfig',
      'receivedPostPhoneAccept',
      'receivedPostTabletAccept',
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
    final removedWindowCount = _intValue(
      charlieProof['removedWindowPlaintextCount'],
    );
    if (removedWindowCount != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
  }

  final danaProof = proofs['dana'];
  if (danaProof != null) {
    for (final field in const <String>[
      'tabletPendingBeforeOwnAccept',
      'groupAbsentBeforeOwnAccept',
      'tabletAcceptedAfterPhone',
      'receivedPostTabletAccept',
      'sentTabletDevicePostAccept',
      'tabletDeviceInMemberConfig',
    ]) {
      _requireTrueProof(
        role: 'dana',
        proofName: proofName,
        proof: danaProof,
        field: field,
        failures: failures,
      );
    }
    _requireFalseProof(
      role: 'dana',
      proofName: proofName,
      proof: danaProof,
      field: 'memberListIncludesDanaAccount',
      failures: failures,
    );
    if (danaPeerId != null &&
        _stringValue(danaProof['actualRolePeerId']) != danaPeerId) {
      failures.add('dana: $proofName.actualRolePeerId must be dana');
    }
    final preAcceptPlaintextCount = _intValue(
      danaProof['preAcceptPlaintextCount'],
    );
    if (preAcceptPlaintextCount != 0) {
      failures.add('dana: $proofName.preAcceptPlaintextCount must be 0');
    }
  }
}

void _validateKe012DelayedOldConfigAfterReaddProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ke012DelayedOldConfigAfterReaddProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'KE-012') {
      failures.add('$role: $proofName.rowId must be KE-012');
    }
  }

  void requireEpochAtLeastTwo(
    String role,
    Map<String, dynamic> proof,
    String field,
  ) {
    final epoch = _intValue(proof[field]);
    if (epoch == null || epoch < 2) {
      failures.add('$role: $proofName.$field must be >= 2');
    }
  }

  void requireSharedFields(String role, Map<String, dynamic> proof) {
    requireRowId(role, proof);
    for (final field in const <String>[
      'delayedOldConfigOrderingCoveredByFakeNetwork',
      'livePostStaleConfigDeliveryCovered',
    ]) {
      _requireTrueProof(
        role: role,
        proofName: proofName,
        proof: proof,
        field: field,
        failures: failures,
      );
    }
    requireEpochAtLeastTwo(role, proof, 'finalEpoch');
  }

  if (aliceProof == null) {
    failures.add('alice: missing KE-012 delayed old config proof fields');
  } else {
    requireSharedFields('alice', aliceProof);
    for (final field in const <String>[
      'deliveredDelayedOldConfigAfterReadd',
      'sentAlicePostStaleConfigAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: proofName,
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing KE-012 delayed old config proof fields');
  } else {
    requireSharedFields('bob', bobProof);
    for (final field in const <String>[
      'keptActiveAfterDelayedOldConfig',
      'observedCharlieReadded',
      'receivedCharliePostStaleConfigAtCurrentEpoch',
      'sentBobPostStaleConfigAtCurrentEpoch',
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
    failures.add('charlie: missing KE-012 delayed old config proof fields');
  } else {
    requireSharedFields('charlie', charlieProof);
    for (final field in const <String>[
      'keptFinalMembersAfterDelayedOldConfig',
      'keptCurrentEpochAfterDelayedOldConfig',
      'postStaleConfigPublishAccepted',
      'receivedAlicePostStaleConfigAtCurrentEpoch',
      'receivedBobPostStaleConfigAtCurrentEpoch',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    final before = _intValue(charlieProof['epochBeforeDelayedOldConfig']);
    final after = _intValue(charlieProof['epochAfterDelayedOldConfig']);
    if (before == null || before < 2) {
      failures.add(
        'charlie: $proofName.epochBeforeDelayedOldConfig must be >= 2',
      );
    }
    if (after == null || after < 2) {
      failures.add(
        'charlie: $proofName.epochAfterDelayedOldConfig must be >= 2',
      );
    }
    if (before != null && after != null && before != after) {
      failures.add(
        'charlie: $proofName epochAfterDelayedOldConfig must equal epochBeforeDelayedOldConfig',
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
    failures.add('alice/bob/charlie: KE-012 finalEpoch mismatch');
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

void _validateKe018HistoryReplayEpochWindowProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ke018HistoryReplayEpochWindowProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'KE-018') {
      failures.add('$role: $proofName.rowId must be KE-018');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing KE-018 history replay epoch-window proof');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in <String>[
      'sentPreRemovalReplayWindow',
      'sentRemovedWindowWhileCharlieRemoved',
      'sentPostReaddReplayWindow',
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
    if (_intValue(aliceProof['sentRemovedWindowCount']) != 3) {
      failures.add('alice: $proofName.sentRemovedWindowCount must be 3');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing KE-018 history replay epoch-window proof');
  } else {
    requireRowId('bob', bobProof);
    for (final field in <String>[
      'receivedPreRemovalReplayWindow',
      'receivedRemovedWindowWhileCharlieRemoved',
      'receivedPostReaddReplayWindow',
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
    if (_intValue(bobProof['receivedRemovedWindowCount']) != 3) {
      failures.add('bob: $proofName.receivedRemovedWindowCount must be 3');
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing KE-018 history replay epoch-window proof');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in <String>[
      'receivedPreRemovalReplayWindow',
      'postReaddMissingBeforeDrain',
      'drainedPostReaddReplayAtCurrentEpoch',
      'noRemovedWindowReplayAfterDrain',
      'memberListIncludesAliceBobCharlie',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(charlieProof['removedWindowPlaintextCount']) != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
    if (_intValue(charlieProof['preRemovalReplayEpoch']) != 1) {
      failures.add('charlie: $proofName.preRemovalReplayEpoch must be 1');
    }
    final postReaddEpoch = _intValue(charlieProof['postReaddReplayEpoch']);
    if (postReaddEpoch == null || postReaddEpoch < 2) {
      failures.add('charlie: $proofName.postReaddReplayEpoch must be >= 2');
    }
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
}

void _validateIr005ReaddReplayProof({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  const proofName = 'ir005ReaddReplayProof';
  final aliceProof = _mapValue(byRole['alice']?[proofName]);
  final bobProof = _mapValue(byRole['bob']?[proofName]);
  final charlieProof = _mapValue(byRole['charlie']?[proofName]);

  void requireRowId(String role, Map<String, dynamic> proof) {
    if (_stringValue(proof['rowId']) != 'IR-005') {
      failures.add('$role: $proofName.rowId must be IR-005');
    }
  }

  if (aliceProof == null) {
    failures.add('alice: missing IR-005 re-add replay proof');
  } else {
    requireRowId('alice', aliceProof);
    for (final field in <String>[
      'sentPreRemovalReplayWindow',
      'sentRemovedWindowWhileCharlieRemoved',
      'sentPostReaddReplayWindow',
      'readdedCharlie',
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
    if (_intValue(aliceProof['sentRemovedWindowCount']) != 3) {
      failures.add('alice: $proofName.sentRemovedWindowCount must be 3');
    }
  }

  if (bobProof == null) {
    failures.add('bob: missing IR-005 re-add replay proof');
  } else {
    requireRowId('bob', bobProof);
    for (final field in <String>[
      'receivedPreRemovalReplayWindow',
      'receivedRemovedWindowWhileCharlieRemoved',
      'receivedPostReaddReplayWindow',
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
    if (_intValue(bobProof['receivedRemovedWindowCount']) != 3) {
      failures.add('bob: $proofName.receivedRemovedWindowCount must be 3');
    }
  }

  if (charlieProof == null) {
    failures.add('charlie: missing IR-005 re-add replay proof');
  } else {
    requireRowId('charlie', charlieProof);
    for (final field in <String>[
      'receivedAllowedPreRemovalHistory',
      'postReaddMissingBeforeDrain',
      'receivedPostReaddReplayAfterDrain',
      'noRemovedWindowReplayAfterDrain',
      'memberListIncludesAliceBobCharlie',
    ]) {
      _requireTrueProof(
        role: 'charlie',
        proofName: proofName,
        proof: charlieProof,
        field: field,
        failures: failures,
      );
    }
    if (_intValue(charlieProof['removedWindowPlaintextCount']) != 0) {
      failures.add('charlie: $proofName.removedWindowPlaintextCount must be 0');
    }
    if (_intValue(charlieProof['preRemovalReplayEpoch']) != 1) {
      failures.add('charlie: $proofName.preRemovalReplayEpoch must be 1');
    }
    final postReaddEpoch = _intValue(charlieProof['postReaddReplayEpoch']);
    if (postReaddEpoch == null || postReaddEpoch < 2) {
      failures.add('charlie: $proofName.postReaddReplayEpoch must be >= 2');
    }
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
    failures.add('alice/bob/charlie: IR-005 finalEpoch mismatch');
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

void _validateMl003OfflineAddProofFields({
  required Map<String, Map<String, dynamic>> byRole,
  required List<String> failures,
}) {
  for (final role in const <String>['alice', 'bob', 'dana']) {
    final proof = _mapValue(byRole[role]?['ml003OfflineAddProof']);
    if (proof == null) {
      failures.add('$role: missing ML-003 offline-add proof fields');
      continue;
    }
    if (_stringValue(proof['rowId']) != 'ML-003') {
      failures.add('$role: ml003OfflineAddProof.rowId must be ML-003');
    }
  }

  final aliceProof = _mapValue(byRole['alice']?['ml003OfflineAddProof']);
  if (aliceProof != null) {
    for (final field in const <String>[
      'danaOfflineDuringAdd',
      'danaNotSubscribedDuringAdd',
      'danaNotActiveBeforeAccept',
      'aliceAddedDana',
      'aliceSentPostAddBeforeDanaAccept',
      'bobSentPostAddBeforeDanaAccept',
      'liveSentAfterDanaDrain',
    ]) {
      _requireTrueProof(
        role: 'alice',
        proofName: 'ml003OfflineAddProof',
        proof: aliceProof,
        field: field,
        failures: failures,
      );
    }
    if (_stringValue(aliceProof['invitePath']) != 'supported_pending_invite') {
      failures.add(
        'alice: ml003OfflineAddProof.invitePath must be supported_pending_invite',
      );
    }
  }

  final bobProof = _mapValue(byRole['bob']?['ml003OfflineAddProof']);
  if (bobProof != null) {
    for (final field in const <String>[
      'danaActiveInConfigBeforeBobSend',
      'bobSentPostAddBeforeDanaAccept',
    ]) {
      _requireTrueProof(
        role: 'bob',
        proofName: 'ml003OfflineAddProof',
        proof: bobProof,
        field: field,
        failures: failures,
      );
    }
  }

  final danaProof = _mapValue(byRole['dana']?['ml003OfflineAddProof']);
  if (danaProof != null) {
    for (final field in const <String>[
      'startedAfterPostAddSends',
      'storedPendingInvite',
      'acceptedPendingInvite',
      'joinedViaGroupJoinWithConfig',
      'drainedOfflineInbox',
      'preAddMessageAbsent',
      'receivedAlicePostAddReplay',
      'receivedBobPostAddReplay',
      'replayPersistedExactlyOnce',
      'liveAfterDrainWithoutRestart',
    ]) {
      _requireTrueProof(
        role: 'dana',
        proofName: 'ml003OfflineAddProof',
        proof: danaProof,
        field: field,
        failures: failures,
      );
    }
    if (_stringValue(danaProof['invitePath']) != 'supported_pending_invite') {
      failures.add(
        'dana: ml003OfflineAddProof.invitePath must be supported_pending_invite',
      );
    }
  }

  final danaVerdict = byRole['dana'];
  if (danaVerdict == null) return;
  for (final key in const <String>[
    'aliceAfterDanaOfflineAdd',
    'bobAfterDanaOfflineAdd',
  ]) {
    final entries = _mapList(danaVerdict['receivedMessages'])
        .where((entry) => _stringValue(entry['key']) == key)
        .toList(growable: false);
    if (entries.length != 1) continue;
    final entry = entries.single;
    if (entry['usedOfflineDrain'] != true) {
      failures.add('dana: received $key usedOfflineDrain must be true');
    }
    if (entry['liveOnly'] == true) {
      failures.add('dana: received $key liveOnly must be false');
    }
  }

  final liveEntries = _mapList(danaVerdict['receivedMessages'])
      .where((entry) => _stringValue(entry['key']) == 'aliceLiveAfterDanaDrain')
      .toList(growable: false);
  if (liveEntries.length == 1) {
    final liveEntry = liveEntries.single;
    if (liveEntry['liveOnly'] != true) {
      failures.add(
        'dana: received aliceLiveAfterDanaDrain liveOnly must be true',
      );
    }
    if (liveEntry['usedOfflineDrain'] != false) {
      failures.add(
        'dana: received aliceLiveAfterDanaDrain usedOfflineDrain must be false',
      );
    }
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
    this.expectedSenderPeerRole,
    this.allowEmptyText = false,
  });

  final String key;
  final String senderRole;
  final List<String> receiverRoles;
  final String? expectedSenderPeerRole;
  final bool allowEmptyText;
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
  final rawText = message['text'];
  if (rawText is String && rawText.isEmpty) return '';
  final text = _stringValue(rawText);
  if (text != null && text.isNotEmpty) return text;
  final rawPlaintext = message['plaintext'];
  if (rawPlaintext is String && rawPlaintext.isEmpty) return '';
  return _stringValue(rawPlaintext);
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

List<String> _activeMemberPeerIds(Map<String, dynamic> verdict) {
  final activeMemberPeerIds = _stringList(verdict['activeMemberPeerIds']);
  if (activeMemberPeerIds.isNotEmpty) return activeMemberPeerIds;
  return _stringList(verdict['memberPeerIds']);
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
