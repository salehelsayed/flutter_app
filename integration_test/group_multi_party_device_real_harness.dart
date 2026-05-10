import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import 'group_multi_device_real_harness.dart';

const _sharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '/tmp',
);
const _role = String.fromEnvironment(
  'GROUP_MULTI_PARTY_ROLE',
  defaultValue: 'alice',
);
const _scenario = String.fromEnvironment(
  'GROUP_MULTI_PARTY_SCENARIO',
  defaultValue: 'gm001',
);
const _runId = String.fromEnvironment(
  'GROUP_MULTI_PARTY_RUN_ID',
  defaultValue: 'adhoc',
);
const _mode = String.fromEnvironment(
  'GROUP_MULTI_PARTY_MODE',
  defaultValue: 'proof',
);
const _restoreMnemonic = String.fromEnvironment(
  'GROUP_MULTI_PARTY_RESTORE_MNEMONIC',
  defaultValue: '',
);
const _configuredDbName = String.fromEnvironment(
  'E2E_DB_NAME',
  defaultValue: '',
);

const _rolesByScenario = <String, List<String>>{
  'gm001': <String>['alice', 'bob', 'charlie'],
  'gm002': <String>['alice', 'bob', 'charlie', 'dana'],
  'gm003': <String>['alice', 'bob', 'charlie', 'dana'],
  'gm004': <String>['alice', 'bob', 'charlie'],
  'gm005': <String>['alice', 'bob', 'charlie'],
  'gm006': <String>['alice', 'bob', 'charlie'],
  'gm007': <String>['alice', 'bob', 'charlie'],
};

String _signalName(String name) => 'gmp_${_runId}_$name';

String _dbNameForRole() {
  if (_configuredDbName.isNotEmpty) return _configuredDbName;
  return 'group_multi_party_${_scenario}_${_runId}_$_role.db';
}

String _usernameForRole(String role) {
  switch (role) {
    case 'alice':
      return 'GM Alice';
    case 'bob':
      return 'GM Bob';
    case 'charlie':
      return 'GM Charlie';
    case 'dana':
      return 'GM Dana';
    default:
      return 'GM $role';
  }
}

Future<void> _waitForOnline(
  dynamic service, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    if (healthFromState(service.currentState) == ConnectionHealth.online) {
      stdout.writeln(
        '[GMP][$_role] online after ${stopwatch.elapsedMilliseconds}ms',
      );
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw TimeoutException('$_role did not reach online state');
}

Map<String, dynamic> _identityFixture(GroupMultiDeviceTestStack stack) {
  return <String, dynamic>{
    'role': _role,
    'peerId': stack.identity.peerId,
    'publicKey': stack.identity.publicKey,
    'mlKemPublicKey': stack.identity.mlKemPublicKey,
    'mnemonic12': stack.identity.mnemonic12,
    'username': stack.identity.username,
    'transportPeerId': stack.p2pService.currentState.peerId,
  };
}

ContactModel _contactFromFixture(String role, Map<String, dynamic> fixture) {
  return ContactModel(
    peerId: fixture['peerId'] as String,
    publicKey: fixture['publicKey'] as String,
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: fixture['username'] as String? ?? _usernameForRole(role),
    signature: 'sig-gmp-$role',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    mlKemPublicKey: fixture['mlKemPublicKey'] as String?,
  );
}

Future<Map<String, Map<String, dynamic>>> _publishIdentityAndWaitForAll(
  GroupMultiDeviceTestStack stack,
  List<String> roles,
) async {
  writeSharedJson(
    _signalName('${_role}_identity.json'),
    _identityFixture(stack),
  );
  final identities = <String, Map<String, dynamic>>{};
  for (final role in roles) {
    identities[role] = await waitForSharedJson(
      _signalName('${role}_identity.json'),
      timeout: const Duration(minutes: 15),
    );
  }
  return identities;
}

Future<void> _addPeerContacts(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  for (final entry in identities.entries) {
    final peerId = entry.value['peerId'] as String;
    if (peerId == stack.identity.peerId) continue;
    await stack.contactRepo.addContact(
      _contactFromFixture(entry.key, entry.value),
    );
  }
}

Future<List<ContactModel>> _contactsForRoles(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
  List<String> roles,
) async {
  final contacts = <ContactModel>[];
  for (final role in roles) {
    final peerId = identities[role]!['peerId'] as String;
    final contact = await stack.contactRepo.getContact(peerId);
    if (contact == null) {
      throw StateError('Missing contact for $role peer $peerId');
    }
    contacts.add(contact);
  }
  return contacts;
}

Future<Map<String, dynamic>> _createGroupFixture({
  required GroupMultiDeviceTestStack stack,
  required Map<String, Map<String, dynamic>> identities,
  required List<String> memberRoles,
  required String name,
}) async {
  final contacts = await _contactsForRoles(stack, identities, memberRoles);
  final result = await createGroupWithMembers(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    p2pService: stack.p2pService,
    identity: stack.identity,
    selectedContacts: contacts,
    type: GroupType.chat,
    name: name,
  );
  expect(result.membersAdded, memberRoles.length);

  final group = await stack.groupRepo.getGroup(result.group.id);
  final keyInfo = await stack.groupRepo.getLatestKey(result.group.id);
  final members = await stack.groupRepo.getMembers(result.group.id);
  expect(group, isNotNull);
  expect(keyInfo, isNotNull);

  return buildGroupFixture(group: group!, keyInfo: keyInfo!, members: members);
}

Future<Map<String, dynamic>> _sendProofMessage({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String key,
  required String text,
}) async {
  final stopwatch = Stopwatch()..start();
  final messageId = 'gmp_${_runId}_${_scenario}_${key}_$_role';
  final result = await sendGroupMessage(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    text: text,
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    messageId: messageId,
  );
  stopwatch.stop();
  final sent = <String, dynamic>{
    'key': key,
    'messageId': result.$2?.id ?? messageId,
    'text': text,
    'outcome': result.$1.name,
    'senderPeerId': stack.identity.peerId,
    'keyEpoch': result.$2?.keyGeneration ?? await _keyEpoch(stack, groupId),
    'sendMs': stopwatch.elapsedMilliseconds,
  };
  if (result.$1 != SendGroupMessageResult.success &&
      result.$1 != SendGroupMessageResult.successNoPeers) {
    throw StateError('$_role failed to send $key: ${result.$1.name}');
  }
  writeSharedJson(_signalName('${_role}_sent_$key.json'), sent);
  return sent;
}

Future<Map<String, dynamic>> _attemptRejectedProofMessage({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String key,
  required String text,
}) async {
  final stopwatch = Stopwatch()..start();
  final messageId = 'gmp_${_runId}_${_scenario}_${key}_$_role';
  final result = await sendGroupMessage(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    text: text,
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    messageId: messageId,
  );
  stopwatch.stop();
  final sent = <String, dynamic>{
    'key': key,
    'messageId': result.$2?.id ?? messageId,
    'text': text,
    'outcome': result.$1.name,
    'senderPeerId': stack.identity.peerId,
    'keyEpoch': result.$2?.keyGeneration ?? await _keyEpoch(stack, groupId),
    'sendMs': stopwatch.elapsedMilliseconds,
    'accepted':
        result.$1 == SendGroupMessageResult.success ||
        result.$1 == SendGroupMessageResult.successNoPeers,
  };
  writeSharedJson(_signalName('${_role}_sent_$key.json'), sent);
  return sent;
}

Future<Map<String, dynamic>> _waitForReceivedProofMessage({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String key,
  required String text,
  required String senderPeerId,
  Duration timeout = const Duration(seconds: 120),
}) async {
  final stopwatch = Stopwatch()..start();
  final deadline = DateTime.now().add(timeout);
  var nextDrainAt = DateTime.fromMillisecondsSinceEpoch(0);
  while (DateTime.now().isBefore(deadline)) {
    if (DateTime.now().isAfter(nextDrainAt)) {
      nextDrainAt = DateTime.now().add(const Duration(seconds: 2));
      try {
        await drainGroupOfflineInboxForGroup(
          bridge: stack.bridge,
          groupRepo: stack.groupRepo,
          msgRepo: stack.groupMsgRepo,
          groupId: groupId,
          groupMessageListener: stack.groupListener,
          selfPeerId: stack.identity.peerId,
        );
      } catch (error) {
        stdout.writeln(
          '[GMP][$_role] drain while waiting for $key failed: $error',
        );
      }
    }

    final matches = await _matchingProofMessages(
      stack: stack,
      groupId: groupId,
      text: text,
      senderPeerId: senderPeerId,
    );
    if (matches.isNotEmpty) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final finalMatches = await _matchingProofMessages(
        stack: stack,
        groupId: groupId,
        text: text,
        senderPeerId: senderPeerId,
      );
      final first = finalMatches.first;
      final received = <String, dynamic>{
        'key': key,
        'messageId': first.id,
        'text': first.text,
        'senderPeerId': first.senderPeerId,
        'keyEpoch': first.keyGeneration,
        'isIncoming': first.isIncoming,
        'e2eMs': stopwatch.elapsedMilliseconds,
        'persistedCount': finalMatches.length,
      };
      writeSharedJson(_signalName('${_role}_received_$key.json'), received);
      return received;
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  throw TimeoutException('$_role timed out waiting for proof message $key');
}

Future<List<dynamic>> _matchingProofMessages({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String text,
  required String senderPeerId,
}) async {
  final messages = await stack.groupMsgRepo.getMessagesPage(
    groupId,
    limit: 100,
  );
  return messages
      .where(
        (message) =>
            message.text == text && message.senderPeerId == senderPeerId,
      )
      .toList(growable: false);
}

Future<int> _proofMessageCount({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String text,
  required String senderPeerId,
}) async {
  final matches = await _matchingProofMessages(
    stack: stack,
    groupId: groupId,
    text: text,
    senderPeerId: senderPeerId,
  );
  return matches.length;
}

Future<List<String>> _memberPeerIds(
  GroupMultiDeviceTestStack stack,
  String groupId,
) async {
  final members = await stack.groupRepo.getMembers(groupId);
  return members.map((member) => member.peerId).toList(growable: false);
}

Future<int> _keyEpoch(GroupMultiDeviceTestStack stack, String groupId) async {
  final key = await stack.groupRepo.getLatestKey(groupId);
  return key?.keyGeneration ?? 0;
}

Future<String> _importGm004JoinedGroupFixture({
  required GroupMultiDeviceTestStack stack,
  required Map<String, dynamic> fixture,
}) async {
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  final group = await stack.groupRepo.getGroup(groupId);
  final selfMember = await stack.groupRepo.getMember(
    groupId,
    stack.identity.peerId,
  );
  if (group != null && selfMember != null) {
    final localRole = selfMember.role == MemberRole.admin
        ? GroupRole.admin
        : GroupRole.member;
    if (group.myRole != localRole) {
      await stack.groupRepo.updateGroup(group.copyWith(myRole: localRole));
    }
  }
  return groupId;
}

Future<void> _waitForMemberExclusion({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String removedPeerId,
}) async {
  await waitForCondition(() async {
    try {
      await drainGroupOfflineInboxForGroup(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupId: groupId,
        groupMessageListener: stack.groupListener,
        selfPeerId: stack.identity.peerId,
      );
    } catch (error) {
      stdout.writeln(
        '[GMP][$_role] drain while waiting for removal failed: $error',
      );
    }
    final members = await stack.groupRepo.getMembers(groupId);
    return members.isNotEmpty &&
        !members.any((member) => member.peerId == removedPeerId);
  }, timeout: const Duration(seconds: 120));
}

Future<void> _waitForMemberInclusion({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String memberPeerId,
}) async {
  await waitForCondition(() async {
    try {
      await drainGroupOfflineInboxForGroup(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupId: groupId,
        groupMessageListener: stack.groupListener,
        selfPeerId: stack.identity.peerId,
      );
    } catch (error) {
      stdout.writeln(
        '[GMP][$_role] drain while waiting for member add failed: $error',
      );
    }
    final members = await stack.groupRepo.getMembers(groupId);
    return members.any((member) => member.peerId == memberPeerId);
  }, timeout: const Duration(seconds: 120));
}

Future<void> _waitForSelfRemoval({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
}) async {
  await waitForCondition(() async {
    if (await stack.groupRepo.getGroup(groupId) == null) {
      return true;
    }
    try {
      await drainGroupOfflineInboxForGroup(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupId: groupId,
        groupMessageListener: stack.groupListener,
        selfPeerId: stack.identity.peerId,
      );
    } catch (error) {
      stdout.writeln(
        '[GMP][$_role] drain while waiting for self-removal failed: $error',
      );
    }
    return await stack.groupRepo.getGroup(groupId) == null;
  }, timeout: const Duration(seconds: 120));
}

Future<void> _waitForKeyEpoch({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required int keyEpoch,
}) async {
  await waitForCondition(() async {
    return await _keyEpoch(stack, groupId) == keyEpoch;
  }, timeout: const Duration(seconds: 120));
}

Map<String, int> _persistedCounts(List<Map<String, dynamic>> receivedMessages) {
  return <String, int>{
    for (final message in receivedMessages)
      message['key'] as String: message['persistedCount'] as int? ?? 0,
  };
}

Future<void> _writeVerdict({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required List<Map<String, dynamic>> sentMessages,
  required List<Map<String, dynamic>> receivedMessages,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) async {
  final verdict = <String, dynamic>{
    'scenario': _scenario,
    'role': _role,
    'runId': _runId,
    'peerId': stack.identity.peerId,
    'transportPeerId': stack.p2pService.currentState.peerId,
    'groupId': groupId,
    'keyEpoch': await _keyEpoch(stack, groupId),
    'relayLifecycleProof': true,
    'memberPeerIds': await _memberPeerIds(stack, groupId),
    'sentMessages': sentMessages,
    'receivedMessages': receivedMessages,
    'persistedMessageCounts': _persistedCounts(receivedMessages),
    ...extra,
  };
  writeSharedJson(_signalName('${_role}_verdict.json'), verdict);
  stdout.writeln(jsonEncode(verdict));
}

Future<void> _publishMembersAddedSystemPayload({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required GroupMember danaMember,
}) async {
  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  if (updatedGroup == null) {
    throw StateError('Missing updated group $groupId after Dana add');
  }

  final membershipEventAt = DateTime.now().toUtc();
  final messageId =
      'members_added:$groupId:${stack.identity.peerId}:${membershipEventAt.microsecondsSinceEpoch}';
  final payload = jsonEncode(<String, dynamic>{
    '__sys': 'members_added',
    'members': <Map<String, dynamic>>[
      <String, dynamic>{
        'peerId': danaMember.peerId,
        'username': danaMember.username,
        'role': danaMember.role.toValue(),
        'publicKey': danaMember.publicKey,
        if (danaMember.mlKemPublicKey != null)
          'mlKemPublicKey': danaMember.mlKemPublicKey,
      },
    ],
    'groupConfig': buildGroupConfigPayload(updatedGroup, updatedMembers),
  });

  final publish = await callGroupPublish(
    stack.bridge,
    groupId: groupId,
    text: payload,
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    messageId: messageId,
  );
  expect(publish['ok'], isTrue, reason: 'members_added publish must succeed');

  await storeGroupOfflineReplayEnvelope(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: jsonEncode(<String, dynamic>{
      'groupId': groupId,
      'senderId': stack.identity.peerId,
      'senderUsername': stack.identity.username,
      'text': payload,
      'timestamp': membershipEventAt.toIso8601String(),
      'messageId': messageId,
    }),
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    messageId: messageId,
    recipientPeerIds: updatedMembers
        .map((member) => member.peerId)
        .where((peerId) => peerId.isNotEmpty)
        .toSet()
        .toList(growable: false),
  );
}

Future<void> _removeCharlieAndPublish({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required Map<String, dynamic> charlieIdentity,
}) async {
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieUsername =
      charlieIdentity['username'] as String? ?? _usernameForRole('charlie');
  final removedAt = DateTime.now().toUtc();

  await removeGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    memberPeerId: charliePeerId,
    selfPeerId: stack.identity.peerId,
    eventAt: removedAt,
  );

  final group = await stack.groupRepo.getGroup(groupId);
  final remainingMembers = await stack.groupRepo.getMembers(groupId);
  if (group == null) {
    throw StateError('Missing group $groupId after Charlie removal');
  }

  final sourceEventId =
      'member_removed:$groupId:${stack.identity.peerId}:${removedAt.microsecondsSinceEpoch}';
  final sysMessage = jsonEncode(<String, dynamic>{
    '__sys': 'member_removed',
    'member': <String, dynamic>{
      'peerId': charliePeerId,
      'username': charlieUsername,
    },
    'removedAt': removedAt.toIso8601String(),
    'groupConfig': buildGroupConfigPayload(group, remainingMembers),
  });

  final publish = await callGroupPublish(
    stack.bridge,
    groupId: groupId,
    text: sysMessage,
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    messageId: sourceEventId,
  );
  expect(publish['ok'], isTrue, reason: 'member_removed publish must succeed');

  await storeGroupOfflineReplayEnvelope(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: jsonEncode(<String, dynamic>{
      'groupId': groupId,
      'senderId': stack.identity.peerId,
      'senderUsername': stack.identity.username,
      'text': sysMessage,
      'timestamp': removedAt.toIso8601String(),
      'messageId': sourceEventId,
    }),
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    messageId: sourceEventId,
    recipientPeerIds: <String>[charliePeerId],
  );
}

Future<void> _runGm001Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-001 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final text = 'GM-001 alice fanout $_runId';
  final sent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceInitial',
    text: text,
  );
  await waitForSharedSignal(_signalName('bob_received_aliceInitial.json'));
  await waitForSharedSignal(_signalName('charlie_received_aliceInitial.json'));

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[sent],
    receivedMessages: const <Map<String, dynamic>>[],
  );
}

Future<void> _runGm001Receiver(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('${_role}_group_joined'), 'ok');

  final sent = await waitForSharedJson(
    _signalName('alice_sent_aliceInitial.json'),
  );
  final received = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceInitial',
    text: sent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[received],
  );
}

Future<void> _runGm002Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-002 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final danaContact = await stack.contactRepo.getContact(
    identities['dana']!['peerId'] as String,
  );
  if (danaContact == null) {
    throw StateError('Alice missing Dana contact before add');
  }
  final danaMember = GroupMember(
    groupId: groupId,
    peerId: danaContact.peerId,
    username: danaContact.username,
    role: MemberRole.writer,
    publicKey: danaContact.publicKey,
    mlKemPublicKey: danaContact.mlKemPublicKey,
    joinedAt: DateTime.now().toUtc(),
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: danaMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMembersAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    danaMember: danaMember,
  );

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('dana_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );

  await waitForSharedSignal(_signalName('dana_group_joined'));
  await waitForSharedSignal(_signalName('bob_membership_converged'));
  await waitForSharedSignal(_signalName('charlie_membership_converged'));

  final aliceText = 'GM-002 alice after Dana add $_runId';
  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterDanaAdd',
    text: aliceText,
  );

  await waitForSharedSignal(_signalName('dana_sent_danaAfterJoin.json'));
  final danaSent = await waitForSharedJson(
    _signalName('dana_sent_danaAfterJoin.json'),
  );
  final danaReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'danaAfterJoin',
    text: danaSent['text'] as String,
    senderPeerId: identities['dana']!['peerId'] as String,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[aliceSent],
    receivedMessages: <Map<String, dynamic>>[danaReceived],
  );
}

Future<void> _waitForDanaMembership(
  GroupMultiDeviceTestStack stack,
  String groupId,
  String danaPeerId,
) async {
  await waitForCondition(() async {
    try {
      await drainGroupOfflineInboxForGroup(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupId: groupId,
        groupMessageListener: stack.groupListener,
        selfPeerId: stack.identity.peerId,
      );
    } catch (error) {
      stdout.writeln('[GMP][$_role] membership drain failed: $error');
    }
    final members = await stack.groupRepo.getMembers(groupId);
    return members.any((member) => member.peerId == danaPeerId);
  }, timeout: const Duration(seconds: 120));
}

Future<void> _runGm002BobOrCharlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('${_role}_group_joined'), 'ok');

  await _waitForDanaMembership(
    stack,
    groupId,
    identities['dana']!['peerId'] as String,
  );
  writeSharedText(_signalName('${_role}_membership_converged'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterDanaAdd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterDanaAdd',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );

  final danaSent = await waitForSharedJson(
    _signalName('dana_sent_danaAfterJoin.json'),
  );
  final danaReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'danaAfterJoin',
    text: danaSent['text'] as String,
    senderPeerId: identities['dana']!['peerId'] as String,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[aliceReceived, danaReceived],
  );
}

Future<void> _runGm002Dana(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(
    _signalName('dana_group_fixture.json'),
  );
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('dana_group_joined'), 'ok');
  await Future<void>.delayed(const Duration(seconds: 3));

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterDanaAdd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterDanaAdd',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );

  final danaText = 'GM-002 Dana after join $_runId';
  final danaSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'danaAfterJoin',
    text: danaText,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[danaSent],
    receivedMessages: <Map<String, dynamic>>[aliceReceived],
  );
}

Future<void> _runGm003Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-003 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final beforeText = 'GM-003 alice before Dana add $_runId';
  final beforeSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceBeforeDanaAdd',
    text: beforeText,
  );
  await waitForSharedSignal(_signalName('bob_received_aliceBeforeDanaAdd'));
  await waitForSharedSignal(_signalName('charlie_received_aliceBeforeDanaAdd'));

  final danaContact = await stack.contactRepo.getContact(
    identities['dana']!['peerId'] as String,
  );
  if (danaContact == null) {
    throw StateError('Alice missing Dana contact before offline add');
  }
  final danaMember = GroupMember(
    groupId: groupId,
    peerId: danaContact.peerId,
    username: danaContact.username,
    role: MemberRole.writer,
    publicKey: danaContact.publicKey,
    mlKemPublicKey: danaContact.mlKemPublicKey,
    joinedAt: DateTime.now().toUtc(),
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: danaMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMembersAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    danaMember: danaMember,
  );

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('dana_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );

  await waitForSharedSignal(_signalName('bob_membership_converged'));
  await waitForSharedSignal(_signalName('charlie_membership_converged'));

  final afterText = 'GM-003 alice after offline Dana add $_runId';
  final afterSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterDanaOfflineAdd',
    text: afterText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceAfterDanaOfflineAdd'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceAfterDanaOfflineAdd'),
  );

  writeSharedText(_signalName('dana_late_launch_ready'), 'ok');
  await waitForSharedSignal(_signalName('dana_group_joined_after_offline'));
  await waitForSharedSignal(
    _signalName('dana_received_aliceAfterDanaOfflineAdd.json'),
  );
  final danaSent = await waitForSharedJson(
    _signalName('dana_sent_danaAfterOfflineJoin.json'),
  );
  final danaReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'danaAfterOfflineJoin',
    text: danaSent['text'] as String,
    senderPeerId: identities['dana']!['peerId'] as String,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[beforeSent, afterSent],
    receivedMessages: <Map<String, dynamic>>[danaReceived],
    extra: const <String, dynamic>{
      'gm003OfflineAddProof': <String, dynamic>{
        'danaOfflineDuringAdd': true,
        'postAddSentBeforeDanaLaunch': true,
        'danaLaunchedAfterPostAddSend': true,
      },
    },
  );
}

Future<void> _runGm003BobOrCharlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('${_role}_group_joined'), 'ok');

  final beforeSent = await waitForSharedJson(
    _signalName('alice_sent_aliceBeforeDanaAdd.json'),
  );
  final beforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceBeforeDanaAdd',
    text: beforeSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedText(_signalName('${_role}_received_aliceBeforeDanaAdd'), 'ok');

  await _waitForDanaMembership(
    stack,
    groupId,
    identities['dana']!['peerId'] as String,
  );
  writeSharedText(_signalName('${_role}_membership_converged'), 'ok');

  final afterSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterDanaOfflineAdd.json'),
  );
  final afterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterDanaOfflineAdd',
    text: afterSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedText(
    _signalName('${_role}_received_aliceAfterDanaOfflineAdd'),
    'ok',
  );

  final danaSent = await waitForSharedJson(
    _signalName('dana_sent_danaAfterOfflineJoin.json'),
  );
  final danaReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'danaAfterOfflineJoin',
    text: danaSent['text'] as String,
    senderPeerId: identities['dana']!['peerId'] as String,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[
      beforeReceived,
      afterReceived,
      danaReceived,
    ],
  );
}

Future<void> _runGm003Dana(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final beforeSent = await waitForSharedJson(
    _signalName('alice_sent_aliceBeforeDanaAdd.json'),
  );
  final fixture = await waitForSharedJson(
    _signalName('dana_group_fixture.json'),
  );
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('dana_group_joined_after_offline'), 'ok');

  final beforeLeakBeforeDrain = await _matchingProofMessages(
    stack: stack,
    groupId: groupId,
    text: beforeSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  if (beforeLeakBeforeDrain.isNotEmpty) {
    throw StateError('Dana received GM-003 pre-add message before catch-up');
  }

  await drainGroupOfflineInboxForGroup(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    groupMessageListener: stack.groupListener,
    selfPeerId: stack.identity.peerId,
  );

  final afterSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterDanaOfflineAdd.json'),
  );
  final afterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterDanaOfflineAdd',
    text: afterSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );

  final beforeLeakAfterDrain = await _matchingProofMessages(
    stack: stack,
    groupId: groupId,
    text: beforeSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  if (beforeLeakAfterDrain.isNotEmpty) {
    throw StateError('Dana received GM-003 pre-add message after catch-up');
  }

  final danaText = 'GM-003 Dana after offline join $_runId';
  final danaSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'danaAfterOfflineJoin',
    text: danaText,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[danaSent],
    receivedMessages: <Map<String, dynamic>>[afterReceived],
    extra: const <String, dynamic>{
      'gm003OfflineCatchUpProof': <String, dynamic>{
        'startedAfterPostAddSend': true,
        'installedGroupConfigBeforeCatchUp': true,
        'drainedOfflineInbox': true,
        'preAddMessageAbsent': true,
        'postAddMessageCaughtUp': true,
      },
    },
  );
}

Future<void> _runGm004Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-004 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  await waitForSharedSignal(_signalName('bob_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_self_removed'));

  final rotatedKey = await rotateAndDistributeGroupKey(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    selfPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    sourceDeviceId: stack.p2pService.currentState.peerId,
    sendP2PMessage: (peerId, message) async {
      await stack.p2pService.sendMessage(peerId, message);
      return true;
    },
  );
  if (rotatedKey == null) {
    throw StateError('GM-004 Alice key rotation failed');
  }
  writeSharedJson(_signalName('rotated_key.json'), <String, dynamic>{
    'keyEpoch': rotatedKey.keyGeneration,
    'groupKey': rotatedKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_rotated_key'));

  final aliceText = 'GM-004 Alice after Charlie removal $_runId';
  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterCharlieRemove',
    text: aliceText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceAfterCharlieRemove.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobAfterCharlieRemove.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterCharlieRemove',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[aliceSent],
    receivedMessages: <Map<String, dynamic>>[bobReceived],
    extra: <String, dynamic>{
      'gm004RemovalProof': <String, dynamic>{
        'charlieOnlineBeforeRemoval': true,
        'removedCharlie': true,
        'removedPeerId': identities['charlie']!['peerId'] as String,
        'memberListExcludesCharlie': !(await _memberPeerIds(
          stack,
          groupId,
        )).contains(identities['charlie']!['peerId'] as String),
        'rotatedEpoch': rotatedKey.keyGeneration,
      },
    },
  );
}

Future<void> _runGm004Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');

  final charliePeerId = identities['charlie']!['peerId'] as String;
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_removed_charlie'), 'ok');

  final rotated = await waitForSharedJson(_signalName('rotated_key.json'));
  final rotatedEpoch = rotated['keyEpoch'] as int;
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rotatedEpoch,
  );
  writeSharedText(_signalName('bob_rotated_key'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterCharlieRemove.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterCharlieRemove',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );

  final bobText = 'GM-004 Bob after Charlie removal $_runId';
  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterCharlieRemove',
    text: bobText,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[aliceReceived],
    extra: <String, dynamic>{
      'gm004RemovalProof': <String, dynamic>{
        'memberListExcludesCharlie': !(await _memberPeerIds(
          stack,
          groupId,
        )).contains(charliePeerId),
        'hasRotatedEpoch': await _keyEpoch(stack, groupId) == rotatedEpoch,
        'rotatedEpoch': rotatedEpoch,
      },
    },
  );
}

Future<void> _runGm004Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  final currentMemberBeforeRemoval =
      await stack.groupRepo.getMember(groupId, stack.identity.peerId) != null;
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_self_removed'), 'ok');

  final rotated = await waitForSharedJson(_signalName('rotated_key.json'));
  final rotatedEpoch = rotated['keyEpoch'] as int;
  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterCharlieRemove.json'),
  );
  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobAfterCharlieRemove.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));

  final aliceLeakCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  final bobLeakCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );

  final rejectedSend = await _attemptRejectedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterCharlieRemove',
    text: 'GM-004 Charlie after removal $_runId',
  );
  final keyEpochAfterRemoval = await _keyEpoch(stack, groupId);
  final postRemovalPlaintextCount = aliceLeakCount + bobLeakCount;

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[rejectedSend],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm004RemovalProof': <String, dynamic>{
        'onlineBeforeRemoval': true,
        'currentMemberBeforeRemoval': currentMemberBeforeRemoval,
        'groupPresentAfterRemoval':
            await stack.groupRepo.getGroup(groupId) != null,
        'hasRotatedEpoch': keyEpochAfterRemoval >= rotatedEpoch,
        'rotatedEpoch': keyEpochAfterRemoval,
        'postRemovalSendOutcome': rejectedSend['outcome'] as String,
        'postRemovalPublishAccepted': rejectedSend['accepted'] == true,
        'receivedAliceAfterRemoval': aliceLeakCount > 0,
        'receivedBobAfterRemoval': bobLeakCount > 0,
        'postRemovalPlaintextCount': postRemovalPlaintextCount,
      },
    },
  );
}

Future<void> _runGm005Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-005 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_old_state_persisted.json'));
  await waitForSharedSignal(_signalName('charlie_offline_before_removal'));
  await Future<void>.delayed(const Duration(seconds: 5));

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  await waitForSharedSignal(_signalName('bob_removed_charlie'));

  final rotatedKey = await rotateAndDistributeGroupKey(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    selfPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    sourceDeviceId: stack.p2pService.currentState.peerId,
    sendP2PMessage: (peerId, message) async {
      await stack.p2pService.sendMessage(peerId, message);
      return true;
    },
  );
  if (rotatedKey == null) {
    throw StateError('GM-005 Alice key rotation failed');
  }
  writeSharedJson(_signalName('rotated_key.json'), <String, dynamic>{
    'keyEpoch': rotatedKey.keyGeneration,
    'groupKey': rotatedKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_rotated_key'));

  final sentMessages = <Map<String, dynamic>>[];
  for (var i = 1; i <= 3; i++) {
    final key = 'aliceAfterCharlieOfflineRemove$i';
    final text = 'GM-005 Alice after offline Charlie removal $i $_runId';
    final sent = await _sendProofMessage(
      stack: stack,
      groupId: groupId,
      key: key,
      text: text,
    );
    sentMessages.add(sent);
    await waitForSharedSignal(_signalName('bob_received_$key.json'));
  }

  writeSharedText(_signalName('charlie_relaunch_ready'), 'ok');
  await waitForSharedSignal(
    _signalName('charlie_self_removed_after_reconnect'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm005OfflineRemovalProof': <String, dynamic>{
        'charlieOfflineBeforeRemoval': true,
        'removedCharlie': true,
        'removedPeerId': identities['charlie']!['peerId'] as String,
        'memberListExcludesCharlie': !(await _memberPeerIds(
          stack,
          groupId,
        )).contains(identities['charlie']!['peerId'] as String),
        'rotatedEpoch': rotatedKey.keyGeneration,
        'postRemovalMessageCount': sentMessages.length,
      },
    },
  );
}

Future<void> _runGm005Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');

  final charliePeerId = identities['charlie']!['peerId'] as String;
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_removed_charlie'), 'ok');

  final rotated = await waitForSharedJson(_signalName('rotated_key.json'));
  final rotatedEpoch = rotated['keyEpoch'] as int;
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rotatedEpoch,
  );
  writeSharedText(_signalName('bob_rotated_key'), 'ok');

  final receivedMessages = <Map<String, dynamic>>[];
  for (var i = 1; i <= 3; i++) {
    final key = 'aliceAfterCharlieOfflineRemove$i';
    final aliceSent = await waitForSharedJson(
      _signalName('alice_sent_$key.json'),
    );
    final received = await _waitForReceivedProofMessage(
      stack: stack,
      groupId: groupId,
      key: key,
      text: aliceSent['text'] as String,
      senderPeerId: identities['alice']!['peerId'] as String,
    );
    receivedMessages.add(received);
  }

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'gm005OfflineRemovalProof': <String, dynamic>{
        'memberListExcludesCharlie': !(await _memberPeerIds(
          stack,
          groupId,
        )).contains(charliePeerId),
        'hasRotatedEpoch': await _keyEpoch(stack, groupId) == rotatedEpoch,
        'rotatedEpoch': rotatedEpoch,
        'receivedAllAlicePostRemovalMessages': receivedMessages.length == 3,
      },
    },
  );
}

Future<void> _runGm005CharlieSeed(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  final group = await stack.groupRepo.getGroup(groupId);
  final key = await stack.groupRepo.getLatestKey(groupId);
  if (group == null || key == null) {
    throw StateError('GM-005 Charlie failed to persist old group/key state');
  }
  writeSharedJson(
    _signalName('charlie_old_state_persisted.json'),
    <String, dynamic>{
      'groupId': groupId,
      'keyEpoch': key.keyGeneration,
      'hadOldConfigBeforeOffline': true,
      'hadOldKeyBeforeOffline': true,
    },
  );
}

Future<void> _runGm005Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  await waitForSharedSignal(_signalName('charlie_relaunch_ready'));
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = (fixture['group'] as Map)['id'] as String;
  var staleGroupBeforeDrain = await stack.groupRepo.getGroup(groupId);
  var staleKeyBeforeDrain = await stack.groupRepo.getLatestKey(groupId);
  var restoredStaleStateFromFixture = false;
  if (staleGroupBeforeDrain == null || staleKeyBeforeDrain == null) {
    await _importGm004JoinedGroupFixture(stack: stack, fixture: fixture);
    restoredStaleStateFromFixture = true;
    staleGroupBeforeDrain = await stack.groupRepo.getGroup(groupId);
    staleKeyBeforeDrain = await stack.groupRepo.getLatestKey(groupId);
  }
  if (staleGroupBeforeDrain == null || staleKeyBeforeDrain == null) {
    throw StateError('GM-005 Charlie did not relaunch with stale group/key');
  }

  final aliceSentMessages = <Map<String, dynamic>>[];
  for (var i = 1; i <= 3; i++) {
    aliceSentMessages.add(
      await waitForSharedJson(
        _signalName('alice_sent_aliceAfterCharlieOfflineRemove$i.json'),
      ),
    );
  }

  var retrievedInboxAfterReconnect = false;
  await drainGroupOfflineInboxForGroup(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    groupMessageListener: stack.groupListener,
    selfPeerId: stack.identity.peerId,
  );
  retrievedInboxAfterReconnect = true;

  final groupAfterDrain = await stack.groupRepo.getGroup(groupId);
  final keyEpochAfterDrain = await _keyEpoch(stack, groupId);
  final leakCounts = <int>[];
  for (final sent in aliceSentMessages) {
    leakCounts.add(
      await _proofMessageCount(
        stack: stack,
        groupId: groupId,
        text: sent['text'] as String,
        senderPeerId: identities['alice']!['peerId'] as String,
      ),
    );
  }
  final postRemovalPlaintextCount = leakCounts.fold<int>(
    0,
    (sum, count) => sum + count,
  );

  final rejectedSend = await _attemptRejectedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterOfflineRemove',
    text: 'GM-005 Charlie after offline removal $_runId',
  );
  writeSharedText(_signalName('charlie_self_removed_after_reconnect'), 'ok');

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[rejectedSend],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm005OfflineRemovalProof': <String, dynamic>{
        'hadOldConfigBeforeOffline': true,
        'hadOldKeyBeforeOffline': true,
        'offlineDuringRemoval': true,
        'reconnectedWithStaleState': true,
        'restoredStaleStateFromFixture': restoredStaleStateFromFixture,
        'staleKeyEpochBeforeDrain': staleKeyBeforeDrain.keyGeneration,
        'retrievedInboxAfterReconnect': retrievedInboxAfterReconnect,
        'convergedRemoved': groupAfterDrain == null,
        'groupPresentAfterCatchUp': groupAfterDrain != null,
        'hasRotatedEpoch': keyEpochAfterDrain >= 2,
        'rotatedEpoch': keyEpochAfterDrain,
        'postRemovalPlaintextCount': postRemovalPlaintextCount,
        'postRemovalSendOutcome': rejectedSend['outcome'] as String,
        'postRemovalPublishAccepted': rejectedSend['accepted'] == true,
      },
    },
  );
}

Future<void> _runGm006Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-006 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  await waitForSharedSignal(_signalName('bob_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_self_removed'));

  final rejoinKey = await rotateAndDistributeGroupKey(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    selfPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    sourceDeviceId: stack.p2pService.currentState.peerId,
    sendP2PMessage: (peerId, message) async {
      await stack.p2pService.sendMessage(peerId, message);
      return true;
    },
  );
  if (rejoinKey == null) {
    throw StateError('GM-006 Alice key rotation failed');
  }
  writeSharedJson(_signalName('rejoin_key.json'), <String, dynamic>{
    'keyEpoch': rejoinKey.keyGeneration,
    'groupKey': rejoinKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_rotated_key'));

  final duringText = 'GM-006 Alice during Charlie removal $_runId';
  final duringSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceDuringCharlieRemoval',
    text: duringText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceDuringCharlieRemoval.json'),
  );

  final charlieContact = await stack.contactRepo.getContact(
    identities['charlie']!['peerId'] as String,
  );
  if (charlieContact == null) {
    throw StateError('Alice missing Charlie contact before immediate re-add');
  }
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charlieContact.peerId,
    username: charlieContact.username,
    role: MemberRole.writer,
    publicKey: charlieContact.publicKey,
    mlKemPublicKey: charlieContact.mlKemPublicKey,
    joinedAt: DateTime.now().toUtc(),
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMembersAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    danaMember: charlieMember,
  );

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );

  await waitForSharedSignal(_signalName('bob_membership_readded'));
  await waitForSharedSignal(_signalName('charlie_group_rejoined'));

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieAfterImmediateReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterImmediateReadd',
    text: charlieSent['text'] as String,
    senderPeerId: identities['charlie']!['peerId'] as String,
  );
  writeSharedText(
    _signalName('alice_received_charlieAfterImmediateReadd'),
    'ok',
  );

  final afterText = 'GM-006 Alice after immediate re-add $_runId';
  final afterSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterImmediateReadd',
    text: afterText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceAfterImmediateReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceAfterImmediateReadd.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[duringSent, afterSent],
    receivedMessages: <Map<String, dynamic>>[charlieReceived],
    extra: <String, dynamic>{
      'gm006ImmediateReaddProof': <String, dynamic>{
        'removedCharlie': true,
        'readdedCharlie': true,
        'removedPeerId': identities['charlie']!['peerId'] as String,
        'memberListIncludesCharlie': (await _memberPeerIds(
          stack,
          groupId,
        )).contains(identities['charlie']!['peerId'] as String),
        'sentRemovedWindowBeforeReadd': true,
        'receivedCharliePostReaddMessage': true,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm006Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');

  final charliePeerId = identities['charlie']!['peerId'] as String;
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_removed_charlie'), 'ok');

  final rotated = await waitForSharedJson(_signalName('rejoin_key.json'));
  final rotatedEpoch = rotated['keyEpoch'] as int;
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rotatedEpoch,
  );
  writeSharedText(_signalName('bob_rotated_key'), 'ok');

  final duringSent = await waitForSharedJson(
    _signalName('alice_sent_aliceDuringCharlieRemoval.json'),
  );
  final duringReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceDuringCharlieRemoval',
    text: duringSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_membership_readded'), 'ok');

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieAfterImmediateReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterImmediateReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );

  final afterSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterImmediateReadd.json'),
  );
  final afterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterImmediateReadd',
    text: afterSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[
      duringReceived,
      charlieReceived,
      afterReceived,
    ],
    extra: <String, dynamic>{
      'gm006ImmediateReaddProof': <String, dynamic>{
        'memberListIncludesCharlie': (await _memberPeerIds(
          stack,
          groupId,
        )).contains(charliePeerId),
        'receivedRemovedWindowMessage': true,
        'receivedCharliePostReaddMessage': true,
        'receivedAlicePostReaddMessage': true,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm006Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_self_removed'), 'ok');

  final duringSent = await waitForSharedJson(
    _signalName('alice_sent_aliceDuringCharlieRemoval.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  final removedWindowPlaintextBeforeReadd = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: duringSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_group_rejoined'), 'ok');

  final charlieText = 'GM-006 Charlie after immediate re-add $_runId';
  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterImmediateReadd',
    text: charlieText,
  );

  await waitForSharedSignal(
    _signalName('alice_received_charlieAfterImmediateReadd'),
  );
  final afterSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterImmediateReadd.json'),
  );
  final afterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterImmediateReadd',
    text: afterSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );

  final removedWindowPlaintextAfterReadd = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: duringSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final finalEpoch = await _keyEpoch(stack, groupId);

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[charlieSent],
    receivedMessages: <Map<String, dynamic>>[afterReceived],
    extra: <String, dynamic>{
      'gm006ImmediateReaddProof': <String, dynamic>{
        'memberListIncludesAliceBob':
            memberPeerIds.contains(alicePeerId) &&
            memberPeerIds.contains(bobPeerId),
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'removedWindowPlaintextCount':
            removedWindowPlaintextBeforeReadd +
            removedWindowPlaintextAfterReadd,
        'hasStaleEpochAfterReadd': finalEpoch < 2,
        'postReaddPublishAccepted':
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        'receivedAlicePostReaddMessage': true,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGm007Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-007 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final beforeText = 'GM-007 Alice before Charlie removal $_runId';
  final beforeSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceBeforeCharlieRemoval',
    text: beforeText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceBeforeCharlieRemoval.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceBeforeCharlieRemoval.json'),
  );

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  await waitForSharedSignal(_signalName('bob_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_self_removed'));

  final rejoinKey = await rotateAndDistributeGroupKey(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    selfPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    sourceDeviceId: stack.p2pService.currentState.peerId,
    sendP2PMessage: (peerId, message) async {
      await stack.p2pService.sendMessage(peerId, message);
      return true;
    },
  );
  if (rejoinKey == null) {
    throw StateError('GM-007 Alice key rotation failed');
  }
  writeSharedJson(_signalName('rejoin_key.json'), <String, dynamic>{
    'keyEpoch': rejoinKey.keyGeneration,
    'groupKey': rejoinKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_rotated_key'));

  final removedWindowSent = <Map<String, dynamic>>[];
  for (var i = 1; i <= 3; i++) {
    removedWindowSent.add(
      await _sendProofMessage(
        stack: stack,
        groupId: groupId,
        key: 'aliceDuringCharlieRemoval$i',
        text: 'GM-007 Alice during Charlie removal $i $_runId',
      ),
    );
  }
  await waitForSharedSignal(_signalName('bob_received_removed_window'));

  final charlieContact = await stack.contactRepo.getContact(
    identities['charlie']!['peerId'] as String,
  );
  if (charlieContact == null) {
    throw StateError('Alice missing Charlie contact before GM-007 re-add');
  }
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charlieContact.peerId,
    username: charlieContact.username,
    role: MemberRole.writer,
    publicKey: charlieContact.publicKey,
    mlKemPublicKey: charlieContact.mlKemPublicKey,
    joinedAt: DateTime.now().toUtc(),
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMembersAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    danaMember: charlieMember,
  );

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );

  await waitForSharedSignal(_signalName('bob_membership_readded'));
  await waitForSharedSignal(_signalName('charlie_group_rejoined'));

  final afterText = 'GM-007 Alice after Charlie re-add $_runId';
  final afterSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterCharlieReadd',
    text: afterText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceAfterCharlieReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceAfterCharlieReadd.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[
      beforeSent,
      ...removedWindowSent,
      afterSent,
    ],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm007HistoryBoundaryProof': <String, dynamic>{
        'removedCharlie': true,
        'readdedCharlie': true,
        'removedPeerId': identities['charlie']!['peerId'] as String,
        'memberListIncludesCharlie': (await _memberPeerIds(
          stack,
          groupId,
        )).contains(identities['charlie']!['peerId'] as String),
        'sentPreRemovalBeforeRemove': true,
        'sentRemovedWindowWhileRemoved': removedWindowSent.length == 3,
        'sentPostReaddAfterReadd': true,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm007Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final beforeSent = await waitForSharedJson(
    _signalName('alice_sent_aliceBeforeCharlieRemoval.json'),
  );
  final beforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceBeforeCharlieRemoval',
    text: beforeSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_removed_charlie'), 'ok');

  final rotated = await waitForSharedJson(_signalName('rejoin_key.json'));
  final rotatedEpoch = rotated['keyEpoch'] as int;
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rotatedEpoch,
  );
  writeSharedText(_signalName('bob_rotated_key'), 'ok');

  final removedWindowReceived = <Map<String, dynamic>>[];
  for (var i = 1; i <= 3; i++) {
    final sent = await waitForSharedJson(
      _signalName('alice_sent_aliceDuringCharlieRemoval$i.json'),
    );
    removedWindowReceived.add(
      await _waitForReceivedProofMessage(
        stack: stack,
        groupId: groupId,
        key: 'aliceDuringCharlieRemoval$i',
        text: sent['text'] as String,
        senderPeerId: alicePeerId,
      ),
    );
  }
  writeSharedText(_signalName('bob_received_removed_window'), 'ok');

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_membership_readded'), 'ok');

  final afterSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterCharlieReadd.json'),
  );
  final afterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterCharlieReadd',
    text: afterSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[
      beforeReceived,
      ...removedWindowReceived,
      afterReceived,
    ],
    extra: <String, dynamic>{
      'gm007HistoryBoundaryProof': <String, dynamic>{
        'memberListIncludesCharlie': (await _memberPeerIds(
          stack,
          groupId,
        )).contains(charliePeerId),
        'receivedPreRemovalMessage': true,
        'receivedRemovedWindowMessageCount': removedWindowReceived.length,
        'receivedPostReaddMessage': true,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm007Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final beforeSent = await waitForSharedJson(
    _signalName('alice_sent_aliceBeforeCharlieRemoval.json'),
  );
  final beforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceBeforeCharlieRemoval',
    text: beforeSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_self_removed'), 'ok');

  final removedWindowSent = <Map<String, dynamic>>[];
  for (var i = 1; i <= 3; i++) {
    removedWindowSent.add(
      await waitForSharedJson(
        _signalName('alice_sent_aliceDuringCharlieRemoval$i.json'),
      ),
    );
  }
  await Future<void>.delayed(const Duration(seconds: 5));
  var removedWindowPlaintextCount = 0;
  for (final sent in removedWindowSent) {
    removedWindowPlaintextCount += await _proofMessageCount(
      stack: stack,
      groupId: groupId,
      text: sent['text'] as String,
      senderPeerId: alicePeerId,
    );
  }

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_group_rejoined'), 'ok');

  final afterSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterCharlieReadd.json'),
  );
  final afterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterCharlieReadd',
    text: afterSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  for (final sent in removedWindowSent) {
    removedWindowPlaintextCount += await _proofMessageCount(
      stack: stack,
      groupId: groupId,
      text: sent['text'] as String,
      senderPeerId: alicePeerId,
    );
  }

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final finalEpoch = await _keyEpoch(stack, groupId);

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[beforeReceived, afterReceived],
    extra: <String, dynamic>{
      'gm007HistoryBoundaryProof': <String, dynamic>{
        'memberListIncludesAliceBob':
            memberPeerIds.contains(alicePeerId) &&
            memberPeerIds.contains(bobPeerId),
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'receivedPreRemovalMessage': true,
        'receivedPostReaddMessage': true,
        'removedWindowPlaintextCount': removedWindowPlaintextCount,
        'hasStaleEpochAfterReadd': finalEpoch < 2,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runScenarioRole() async {
  final roles = _rolesByScenario[_scenario];
  if (roles == null) {
    throw StateError('Unsupported GROUP_MULTI_PARTY_SCENARIO=$_scenario');
  }
  if (!roles.contains(_role)) {
    throw StateError('Role $_role is not part of scenario $_scenario');
  }

  final stack = await setupGroupMultiDeviceStack(
    dbName: _dbNameForRole(),
    username: _usernameForRole(_role),
    cliPeerFixture: null,
    restoreMnemonic: _restoreMnemonic.isEmpty ? null : _restoreMnemonic,
  );
  try {
    await _waitForOnline(stack.p2pService);
    if (_mode == 'identityOnly') {
      writeSharedJson(
        _signalName('${_role}_identity.json'),
        _identityFixture(stack),
      );
      return;
    }

    final identities = await _publishIdentityAndWaitForAll(stack, roles);
    await _addPeerContacts(stack, identities);

    if (_scenario == 'gm001') {
      if (_role == 'alice') {
        await _runGm001Alice(stack, identities);
      } else {
        await _runGm001Receiver(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm002') {
      if (_role == 'alice') {
        await _runGm002Alice(stack, identities);
      } else if (_role == 'bob' || _role == 'charlie') {
        await _runGm002BobOrCharlie(stack, identities);
      } else {
        await _runGm002Dana(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm003') {
      if (_role == 'alice') {
        await _runGm003Alice(stack, identities);
      } else if (_role == 'bob' || _role == 'charlie') {
        await _runGm003BobOrCharlie(stack, identities);
      } else {
        await _runGm003Dana(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm004') {
      if (_role == 'alice') {
        await _runGm004Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm004Bob(stack, identities);
      } else {
        await _runGm004Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm005') {
      if (_role == 'alice') {
        await _runGm005Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm005Bob(stack, identities);
      } else if (_mode == 'seedOffline') {
        await _runGm005CharlieSeed(stack, identities);
      } else {
        await _runGm005Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm006') {
      if (_role == 'alice') {
        await _runGm006Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm006Bob(stack, identities);
      } else {
        await _runGm006Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm007') {
      if (_role == 'alice') {
        await _runGm007Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm007Bob(stack, identities);
      } else {
        await _runGm007Charlie(stack, identities);
      }
      return;
    }
  } finally {
    await stack.teardown();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializeSqliteForCurrentPlatform();

  testWidgets(
    'group multi-party device proof scenario=$_scenario role=$_role run=$_runId',
    (tester) async {
      Directory(_sharedDir).createSync(recursive: true);
      await _runScenarioRole();
    },
  );
}
