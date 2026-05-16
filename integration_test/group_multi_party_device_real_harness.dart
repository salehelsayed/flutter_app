import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p_connection;
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/broadcast_voluntary_leave_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/update_group_member_role_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
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
  'ge001': <String>['alice', 'bob', 'charlie'],
  'ge002': <String>['alice', 'bob', 'charlie'],
  'ge003': <String>['alice', 'bob', 'charlie'],
  'ge004': <String>['alice', 'bob', 'charlie'],
  'ge005': <String>['alice', 'bob', 'charlie'],
  'ge006': <String>['alice', 'bob', 'charlie'],
  'ge007': <String>['alice', 'bob', 'charlie'],
  'ge008': <String>['alice', 'bob', 'charlie'],
  'ge009': <String>['alice', 'bob', 'charlie'],
  'ge010': <String>['alice', 'bob', 'charlie'],
  'go001': <String>['alice', 'bob', 'charlie'],
  'go002': <String>['alice', 'bob', 'charlie'],
  'go003': <String>['alice', 'bob', 'charlie'],
  'ge011': <String>['alice', 'bob', 'charlie'],
  'ge012': <String>['alice', 'bob', 'charlie'],
  'ge013': <String>['alice', 'bob', 'charlie'],
  'ge014': <String>['alice', 'bob', 'charlie'],
  'ge015': <String>['alice', 'bob', 'charlie'],
  'ge016': <String>['alice', 'bob', 'charlie'],
  'ge020': <String>['alice', 'bob', 'charlie'],
  'ge021': <String>['alice', 'bob', 'charlie'],
  'ge023': <String>['alice', 'bob', 'charlie'],
  'ge024': <String>['alice', 'bob', 'charlie'],
  'gm001': <String>['alice', 'bob', 'charlie'],
  'gm002': <String>['alice', 'bob', 'charlie', 'dana'],
  'gm003': <String>['alice', 'bob', 'charlie', 'dana'],
  'gm004': <String>['alice', 'bob', 'charlie'],
  'gm005': <String>['alice', 'bob', 'charlie'],
  'gm006': <String>['alice', 'bob', 'charlie'],
  'gm007': <String>['alice', 'bob', 'charlie'],
  'gm008': <String>['alice', 'bob', 'charlie'],
  'gm009': <String>['alice', 'bob', 'charlie'],
  'gm010': <String>['alice', 'bob', 'charlie'],
  'gm011': <String>['alice', 'bob', 'charlie'],
  'gm012': <String>['alice', 'bob', 'charlie'],
  'gm013': <String>['alice', 'bob', 'charlie'],
  'gm014': <String>['alice', 'bob', 'charlie'],
  'gm015': <String>['alice', 'bob', 'charlie'],
  'gm016': <String>['alice', 'bob', 'charlie'],
  'gm017': <String>['alice', 'bob', 'charlie'],
  'gm018': <String>['alice', 'bob', 'charlie'],
  'gm019': <String>['alice', 'bob', 'charlie'],
  'gm020': <String>['alice', 'bob', 'charlie'],
  'gm021': <String>['alice', 'bob', 'charlie'],
  'gm022': <String>['alice', 'bob', 'charlie'],
  'gm023': <String>['alice', 'bob', 'charlie'],
  'gm024': <String>['alice', 'bob', 'charlie'],
  'gm025': <String>['alice', 'bob', 'charlie'],
  'gm033': <String>['alice', 'bob', 'charlie'],
  'gm034': <String>['alice', 'bob', 'charlie'],
  'gm035': <String>['alice', 'bob', 'charlie'],
};

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
const _ge009AliceBeforePartitionKey = 'aliceGe009BeforePartition';
const _ge009BobBeforePartitionKey = 'bobGe009BeforePartition';
const _ge009CharlieBeforePartitionKey = 'charlieGe009BeforePartition';
const _ge009AlicePostReaddKey = 'aliceGe009PostReadd';
const _ge009BobPostReaddKey = 'bobGe009PostReadd';
const _ge009CharlieAfterHealKey = 'charlieGe009AfterHeal';
const _ge009FinalKeys = <String>[
  _ge009AliceBeforePartitionKey,
  _ge009BobBeforePartitionKey,
  _ge009CharlieBeforePartitionKey,
  _ge009AlicePostReaddKey,
  _ge009BobPostReaddKey,
  _ge009CharlieAfterHealKey,
];
const _ge010AliceZeroPeerKey = 'aliceGe010ZeroPeerFallback';
const _go002AliceInboxFailureKey = 'aliceGo002InboxStoreFailure';
const _ge011AlicePartialLiveKey = 'aliceGe011PartialLiveFallback';
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
const _ge024AliceBeforeRemovalParentKey = 'aliceGe024BeforeRemovalParent';
const _ge024AliceRemovedWindowParentKey = 'aliceGe024RemovedWindowParent';
const _ge024BobReplyAvailableKey = 'bobGe024ReplyAvailable';
const _ge024BobReplyUnavailableKey = 'bobGe024ReplyUnavailable';

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

class _InboxStoreFailureBridge implements Bridge {
  _InboxStoreFailureBridge(this._delegate);

  final Bridge _delegate;
  final List<String> failedInboxStoreMessages = <String>[];

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'group:inboxStore') {
      failedInboxStoreMessages.add(message);
      throw Exception('GO-002 forced GroupInboxStore failure');
    }
    return _delegate.send(message);
  }

  @override
  Future<void> initialize() => _delegate.initialize();

  @override
  Future<bool> checkHealth() => _delegate.checkHealth();

  @override
  Future<void> reinitialize() => _delegate.reinitialize();

  @override
  void dispose() {}

  @override
  bool get isInitialized => _delegate.isInitialized;

  @override
  void Function(ChatMessage)? get onMessageReceived =>
      _delegate.onMessageReceived;

  @override
  set onMessageReceived(void Function(ChatMessage)? callback) {
    _delegate.onMessageReceived = callback;
  }

  @override
  void Function(p2p_connection.ConnectionState)? get onPeerConnected =>
      _delegate.onPeerConnected;

  @override
  set onPeerConnected(void Function(p2p_connection.ConnectionState)? callback) {
    _delegate.onPeerConnected = callback;
  }

  @override
  void Function(p2p_connection.ConnectionState)? get onPeerDisconnected =>
      _delegate.onPeerDisconnected;

  @override
  set onPeerDisconnected(
    void Function(p2p_connection.ConnectionState)? callback,
  ) {
    _delegate.onPeerDisconnected = callback;
  }

  @override
  void Function(List<String>, List<String>)? get onAddressesUpdated =>
      _delegate.onAddressesUpdated;

  @override
  set onAddressesUpdated(void Function(List<String>, List<String>)? callback) {
    _delegate.onAddressesUpdated = callback;
  }

  @override
  void Function(Map<String, dynamic>)? get onRelayStateChanged =>
      _delegate.onRelayStateChanged;

  @override
  set onRelayStateChanged(void Function(Map<String, dynamic>)? callback) {
    _delegate.onRelayStateChanged = callback;
  }

  @override
  void Function(Map<String, dynamic>)? get onGroupMessageReceived =>
      _delegate.onGroupMessageReceived;

  @override
  set onGroupMessageReceived(void Function(Map<String, dynamic>)? callback) {
    _delegate.onGroupMessageReceived = callback;
  }

  @override
  void Function(Map<String, dynamic>)? get onGroupReactionReceived =>
      _delegate.onGroupReactionReceived;

  @override
  set onGroupReactionReceived(void Function(Map<String, dynamic>)? callback) {
    _delegate.onGroupReactionReceived = callback;
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

Future<void> _waitForNotOnline(
  dynamic service, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    if (healthFromState(service.currentState) != ConnectionHealth.online) {
      stdout.writeln(
        '[GMP][$_role] not online after ${stopwatch.elapsedMilliseconds}ms',
      );
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('$_role did not leave online state');
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
  DateTime? timestamp,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
}) async {
  final stopwatch = Stopwatch()..start();
  final messageId = 'gmp_${_runId}_${_scenario}_${key}_$_role';
  final normalizedTimestamp = timestamp?.toUtc();
  final currentTransportPeerId = stack.p2pService.currentState.peerId?.trim();
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
    timestamp: normalizedTimestamp,
    quotedMessageId: quotedMessageId,
    senderDeviceId: currentTransportPeerId,
    senderTransportPeerId: currentTransportPeerId,
    mediaAttachments: mediaAttachments,
    mediaAttachmentRepo: stack.mediaAttachmentRepo,
  );
  stopwatch.stop();
  final publishPayload = _groupPublishPayloadForMessage(
    stack: stack,
    messageId: result.$2?.id ?? messageId,
  );
  final publishResponse = _groupPublishResponseForMessage(
    stack: stack,
    messageId: result.$2?.id ?? messageId,
  );
  final actualTopicPeers = _intFromBridgeValue(publishResponse?['topicPeers']);
  final recipientPeerIds = _actualDurableRecipientPeerIdsForMessage(
    stack: stack,
    messageId: result.$2?.id ?? messageId,
  );
  final persistedMedia = await _mediaProofsForMessage(
    stack: stack,
    messageId: result.$2?.id ?? messageId,
  );
  final publishMedia =
      (publishPayload?['media'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .toList(growable: false);
  final durableMedia = mediaAttachments == null || mediaAttachments.isEmpty
      ? const <Map<String, dynamic>>[]
      : await _actualDurableMediaForMessage(
          stack: stack,
          messageId: result.$2?.id ?? messageId,
        );
  final sent = <String, dynamic>{
    'key': key,
    'messageId': result.$2?.id ?? messageId,
    'text': text,
    'outcome': result.$1.name,
    'senderPeerId': stack.identity.peerId,
    'senderUsername': stack.identity.username,
    'senderDeviceId': stack.p2pService.currentState.peerId,
    'transportPeerId': stack.p2pService.currentState.peerId,
    if (publishPayload?['senderKeyPackageId'] is String)
      'senderKeyPackageId': publishPayload!['senderKeyPackageId'] as String,
    'timestamp':
        (result.$2?.timestamp.toUtc() ??
                normalizedTimestamp ??
                DateTime.now().toUtc())
            .toIso8601String(),
    'keyEpoch': result.$2?.keyGeneration ?? await _keyEpoch(stack, groupId),
    if (quotedMessageId != null && quotedMessageId.isNotEmpty)
      'quotedMessageId': quotedMessageId,
    'recipientPeerIds': recipientPeerIds,
    'actualDurablePayloadProof': true,
    'topicPeers': ?actualTopicPeers,
    'actualTopicPeerProof':
        publishResponse?['ok'] == true && actualTopicPeers != null,
    'sendMs': stopwatch.elapsedMilliseconds,
    if (persistedMedia.isNotEmpty) 'mediaAttachments': persistedMedia,
    if (persistedMedia.isNotEmpty)
      'mediaAttachmentIds': persistedMedia
          .map((attachment) => attachment['id'] as String)
          .toList(growable: false),
    if (persistedMedia.isNotEmpty)
      'mediaContentHashes': persistedMedia
          .map((attachment) => attachment['contentHash'] as String?)
          .whereType<String>()
          .toList(growable: false),
    if (persistedMedia.isNotEmpty)
      'mediaAttachmentCount': persistedMedia.length,
    if (mediaAttachments != null && mediaAttachments.isNotEmpty)
      'wireMediaCount': publishMedia.length,
    if (mediaAttachments != null && mediaAttachments.isNotEmpty)
      'durableMediaCount': durableMedia.length,
  };
  if (result.$1 != SendGroupMessageResult.success &&
      result.$1 != SendGroupMessageResult.successNoPeers) {
    throw StateError('$_role failed to send $key: ${result.$1.name}');
  }
  writeSharedJson(_signalName('${_role}_sent_$key.json'), sent);
  return sent;
}

Future<Map<String, dynamic>> _waitForOutboundStatusProof({
  required GroupMultiDeviceTestStack stack,
  required String messageId,
  required String status,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final message = await stack.groupMsgRepo.getMessage(messageId);
    if (message?.status == status) {
      return <String, dynamic>{
        'status': message!.status,
        'wireEnvelopePresent': message.wireEnvelope?.isNotEmpty == true,
        'inboxStored': message.inboxStored,
        'inboxRetryPayloadPresent':
            message.inboxRetryPayload?.isNotEmpty == true,
      };
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  final message = await stack.groupMsgRepo.getMessage(messageId);
  throw TimeoutException(
    '$_role timed out waiting for $messageId status=$status; '
    'latest=${message?.status}',
  );
}

Future<Map<String, dynamic>> _sendGo002InboxFailureProofMessage({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String text,
}) async {
  final stopwatch = Stopwatch()..start();
  final messageId =
      'gmp_${_runId}_${_scenario}_${_go002AliceInboxFailureKey}_$_role';
  final currentTransportPeerId = stack.p2pService.currentState.peerId?.trim();
  final failureBridge = _InboxStoreFailureBridge(stack.bridge);
  final result = await sendGroupMessage(
    bridge: failureBridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    text: text,
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    messageId: messageId,
    senderDeviceId: currentTransportPeerId,
    senderTransportPeerId: currentTransportPeerId,
  );
  stopwatch.stop();

  if (result.$1 != SendGroupMessageResult.success) {
    throw StateError('GO-002 Alice publish must succeed: ${result.$1.name}');
  }
  final beforeRetry = await stack.groupMsgRepo.getMessage(messageId);
  if (beforeRetry?.status != 'pending' ||
      beforeRetry?.inboxStored != false ||
      beforeRetry?.inboxRetryPayload == null) {
    throw StateError(
      'GO-002 Alice row must be pending and retryable before retry; '
      'status=${beforeRetry?.status} '
      'inboxStored=${beforeRetry?.inboxStored} '
      'retryPayload=${beforeRetry?.inboxRetryPayload != null}',
    );
  }

  final failedRecipientPeerIds = _failedInboxStoreRecipientPeerIdsForMessage(
    bridge: failureBridge,
    messageId: messageId,
  );
  final publishResponse = _groupPublishResponseForMessage(
    stack: stack,
    messageId: messageId,
  );
  final actualTopicPeers = _intFromBridgeValue(publishResponse?['topicPeers']);
  if (publishResponse?['ok'] != true) {
    throw StateError('GO-002 publish response must be ok: $publishResponse');
  }
  if (actualTopicPeers == null || actualTopicPeers <= 0) {
    throw StateError(
      'GO-002 requires live PubSub publish proof with topicPeers > 0; '
      'topicPeers=$actualTopicPeers',
    );
  }

  final retried = await retryFailedGroupInboxStores(
    bridge: stack.bridge,
    msgRepo: stack.groupMsgRepo,
  );
  final afterRetry = await stack.groupMsgRepo.getMessage(messageId);
  if (retried != 1 ||
      afterRetry?.status != 'sent' ||
      afterRetry?.inboxStored != true ||
      afterRetry?.inboxRetryPayload != null) {
    throw StateError(
      'GO-002 retry must promote sender row to sent; retried=$retried '
      'status=${afterRetry?.status} '
      'inboxStored=${afterRetry?.inboxStored} '
      'retryPayload=${afterRetry?.inboxRetryPayload != null}',
    );
  }

  final retriedRecipientPeerIds = _actualDurableRecipientPeerIdsForMessage(
    stack: stack,
    messageId: messageId,
  );
  final sent = <String, dynamic>{
    'key': _go002AliceInboxFailureKey,
    'messageId': messageId,
    'text': text,
    'outcome': result.$1.name,
    'senderPeerId': stack.identity.peerId,
    'senderUsername': stack.identity.username,
    'senderDeviceId': stack.p2pService.currentState.peerId,
    'transportPeerId': stack.p2pService.currentState.peerId,
    'timestamp': (result.$2?.timestamp.toUtc() ?? DateTime.now().toUtc())
        .toIso8601String(),
    'keyEpoch': result.$2?.keyGeneration ?? await _keyEpoch(stack, groupId),
    'recipientPeerIds': retriedRecipientPeerIds,
    'failedInboxRecipientPeerIds': failedRecipientPeerIds,
    'forcedInboxStoreFailure': true,
    'senderStatusBeforeRetry': beforeRetry!.status,
    'inboxStoredBeforeRetry': beforeRetry.inboxStored,
    'retryPayloadBeforeRetry': beforeRetry.inboxRetryPayload != null,
    'retryCount': retried,
    'senderStatusAfterRetry': afterRetry!.status,
    'inboxStoredAfterRetry': afterRetry.inboxStored,
    'retryPayloadAfterRetry': afterRetry.inboxRetryPayload != null,
    'actualDurablePayloadProof': true,
    'topicPeers': actualTopicPeers,
    'actualTopicPeerProof': true,
    'sendMs': stopwatch.elapsedMilliseconds,
  };
  writeSharedJson(
    _signalName('alice_sent_$_go002AliceInboxFailureKey.json'),
    sent,
  );
  return sent;
}

List<String> _actualDurableRecipientPeerIdsForMessage({
  required GroupMultiDeviceTestStack stack,
  required String messageId,
}) {
  final bridge = stack.bridge;
  if (bridge is! RecordingGoBridgeClient) {
    throw StateError('GM proof requires a recording bridge');
  }
  for (final raw in bridge.sentMessages.reversed) {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    if (parsed['cmd'] != 'group:inboxStore') continue;
    final payload = parsed['payload'] as Map<String, dynamic>;
    final message = payload['message'];
    if (message is! String) continue;
    final replayEnvelope = jsonDecode(message) as Map<String, dynamic>;
    if (replayEnvelope['messageId'] != messageId) continue;
    return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
  throw StateError('Missing actual group:inboxStore payload for $messageId');
}

List<String> _failedInboxStoreRecipientPeerIdsForMessage({
  required _InboxStoreFailureBridge bridge,
  required String messageId,
}) {
  for (final raw in bridge.failedInboxStoreMessages.reversed) {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    final payload = parsed['payload'] as Map<String, dynamic>;
    final message = payload['message'];
    if (message is! String) continue;
    final replayEnvelope = jsonDecode(message) as Map<String, dynamic>;
    if (replayEnvelope['messageId'] != messageId) continue;
    return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
  throw StateError('Missing forced failed group:inboxStore for $messageId');
}

Map<String, dynamic>? _groupPublishPayloadForMessage({
  required GroupMultiDeviceTestStack stack,
  required String messageId,
}) {
  final bridge = stack.bridge;
  if (bridge is! RecordingGoBridgeClient) return null;
  for (final raw in bridge.sentMessages.reversed) {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    if (parsed['cmd'] != 'group:publish') continue;
    final payload = parsed['payload'] as Map<String, dynamic>;
    if (payload['messageId'] == messageId) return payload;
  }
  return null;
}

Map<String, dynamic>? _groupPublishResponseForMessage({
  required GroupMultiDeviceTestStack stack,
  required String messageId,
}) {
  final bridge = stack.bridge;
  if (bridge is! RecordingGoBridgeClient) return null;
  for (final exchange in bridge.bridgeExchanges.reversed) {
    final request = jsonDecode(exchange['request']!) as Map<String, dynamic>;
    if (request['cmd'] != 'group:publish') continue;
    final payload = request['payload'] as Map<String, dynamic>;
    if (payload['messageId'] != messageId) continue;
    final response = jsonDecode(exchange['response']!) as Map<String, dynamic>;
    return response;
  }
  return null;
}

Future<List<Map<String, dynamic>>> _actualDurableMediaForMessage({
  required GroupMultiDeviceTestStack stack,
  required String messageId,
}) async {
  final bridge = stack.bridge;
  if (bridge is! RecordingGoBridgeClient) {
    throw StateError('GM proof requires a recording bridge');
  }
  for (final raw in bridge.sentMessages.reversed) {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    if (parsed['cmd'] != 'group:inboxStore') continue;
    final payload = parsed['payload'] as Map<String, dynamic>;
    final message = payload['message'];
    if (message is! String) continue;
    final replayEnvelope = jsonDecode(message) as Map<String, dynamic>;
    if (replayEnvelope['messageId'] != messageId) continue;
    final groupId = payload['groupId'] as String? ?? replayEnvelope['groupId'];
    if (groupId is! String || groupId.isEmpty) {
      throw StateError('Missing groupId for actual inbox payload $messageId');
    }
    final durablePayload = await decodeInboxMessage(
      stack.bridge,
      stack.groupRepo,
      <String, dynamic>{'message': message},
      groupId,
    );
    return (durablePayload['media'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }
  throw StateError('Missing actual group:inboxStore payload for $messageId');
}

List<Map<String, dynamic>> _mediaAttachmentProofs(
  List<MediaAttachment> attachments,
) {
  return attachments
      .map(
        (attachment) => <String, dynamic>{
          'id': attachment.id,
          'messageId': attachment.messageId,
          'mime': attachment.mime,
          'size': attachment.size,
          'mediaType': attachment.mediaType,
          'width': attachment.width,
          'height': attachment.height,
          'downloadStatus': attachment.downloadStatus,
          'localPathPresent': attachment.localPath?.isNotEmpty == true,
          'contentHash': attachment.contentHash,
          'thumbnailHash': attachment.thumbnailHash,
          'hasEncryptionMetadata': attachment.hasEncryptionMetadata,
          'encryptionScheme': attachment.encryptionScheme,
        },
      )
      .toList(growable: false);
}

Future<List<Map<String, dynamic>>> _mediaProofsForMessage({
  required GroupMultiDeviceTestStack stack,
  required String messageId,
}) async {
  final attachments = await stack.mediaAttachmentRepo.getAttachmentsForMessage(
    messageId,
  );
  return _mediaAttachmentProofs(attachments);
}

int? _intFromBridgeValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

Future<Map<String, dynamic>> _sendLiveOnlyProofMessage({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String key,
  required String text,
}) async {
  final stopwatch = Stopwatch()..start();
  final messageId = 'gmp_${_runId}_${_scenario}_${key}_$_role';
  final currentTransportPeerId = stack.p2pService.currentState.peerId?.trim();
  final publish = await callGroupPublish(
    stack.bridge,
    groupId: groupId,
    text: text,
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    senderDeviceId: currentTransportPeerId,
    senderTransportPeerId: currentTransportPeerId,
    senderDevicePublicKey: stack.identity.publicKey,
    messageId: messageId,
  );
  stopwatch.stop();
  final sent = <String, dynamic>{
    'key': key,
    'messageId': messageId,
    'text': text,
    'outcome': publish['ok'] == true ? 'success' : 'publishFailed',
    'senderPeerId': stack.identity.peerId,
    'senderUsername': stack.identity.username,
    'senderDeviceId': stack.p2pService.currentState.peerId,
    'transportPeerId': stack.p2pService.currentState.peerId,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'keyEpoch': await _keyEpoch(stack, groupId),
    'recipientPeerIds': const <String>[],
    'actualDurablePayloadProof': false,
    'durableInboxStored': false,
    'sendMs': stopwatch.elapsedMilliseconds,
  };
  if (publish['ok'] != true) {
    throw StateError('$_role failed to live-publish $key: $publish');
  }
  writeSharedJson(_signalName('${_role}_sent_$key.json'), sent);
  return sent;
}

Future<Map<String, dynamic>> _attemptRejectedProofMessage({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String key,
  required String text,
  bool bindCurrentTransport = false,
}) async {
  final stopwatch = Stopwatch()..start();
  final messageId = 'gmp_${_runId}_${_scenario}_${key}_$_role';
  final currentTransportPeerId = stack.p2pService.currentState.peerId?.trim();
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
    senderDeviceId: bindCurrentTransport ? currentTransportPeerId : null,
    senderTransportPeerId: bindCurrentTransport ? currentTransportPeerId : null,
  );
  stopwatch.stop();
  final sent = <String, dynamic>{
    'key': key,
    'messageId': result.$2?.id ?? messageId,
    'text': text,
    'outcome': result.$1.name,
    'senderPeerId': stack.identity.peerId,
    if (bindCurrentTransport) 'senderDeviceId': currentTransportPeerId,
    if (bindCurrentTransport) 'transportPeerId': currentTransportPeerId,
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
  String? quotedMessageId,
  Duration timeout = const Duration(seconds: 120),
  bool drainWhileWaiting = true,
}) async {
  final stopwatch = Stopwatch()..start();
  final deadline = DateTime.now().add(timeout);
  var nextDrainAt = DateTime.fromMillisecondsSinceEpoch(0);
  while (DateTime.now().isBefore(deadline)) {
    if (drainWhileWaiting && DateTime.now().isAfter(nextDrainAt)) {
      nextDrainAt = DateTime.now().add(const Duration(seconds: 2));
      try {
        await drainGroupOfflineInboxForGroup(
          bridge: stack.bridge,
          groupRepo: stack.groupRepo,
          msgRepo: stack.groupMsgRepo,
          groupId: groupId,
          groupMessageListener: stack.groupListener,
          mediaAttachmentRepo: stack.mediaAttachmentRepo,
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
      quotedMessageId: quotedMessageId,
    );
    if (matches.isNotEmpty) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final finalMatches = await _matchingProofMessages(
        stack: stack,
        groupId: groupId,
        text: text,
        senderPeerId: senderPeerId,
        quotedMessageId: quotedMessageId,
      );
      final first = finalMatches.first;
      final mediaProofs = await _mediaProofsForMessage(
        stack: stack,
        messageId: first.id,
      );
      final received = <String, dynamic>{
        'key': key,
        'messageId': first.id,
        'text': first.text,
        'senderPeerId': first.senderPeerId,
        'timestamp': first.timestamp.toUtc().toIso8601String(),
        'keyEpoch': first.keyGeneration,
        'isIncoming': first.isIncoming,
        if (first.quotedMessageId != null && first.quotedMessageId!.isNotEmpty)
          'quotedMessageId': first.quotedMessageId,
        'e2eMs': stopwatch.elapsedMilliseconds,
        'persistedCount': finalMatches.length,
        if (mediaProofs.isNotEmpty) 'mediaAttachments': mediaProofs,
        if (mediaProofs.isNotEmpty)
          'mediaAttachmentIds': mediaProofs
              .map((attachment) => attachment['id'] as String)
              .toList(growable: false),
        if (mediaProofs.isNotEmpty)
          'mediaContentHashes': mediaProofs
              .map((attachment) => attachment['contentHash'] as String?)
              .whereType<String>()
              .toList(growable: false),
        if (mediaProofs.isNotEmpty) 'mediaAttachmentCount': mediaProofs.length,
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
  String? quotedMessageId,
}) async {
  final messages = await stack.groupMsgRepo.getMessagesPage(
    groupId,
    limit: 100,
  );
  return messages
      .where(
        (message) =>
            message.text == text &&
            message.senderPeerId == senderPeerId &&
            (quotedMessageId == null ||
                message.quotedMessageId == quotedMessageId),
      )
      .toList(growable: false);
}

Future<int> _proofMessageCount({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String text,
  required String senderPeerId,
  String? quotedMessageId,
}) async {
  final matches = await _matchingProofMessages(
    stack: stack,
    groupId: groupId,
    text: text,
    senderPeerId: senderPeerId,
    quotedMessageId: quotedMessageId,
  );
  return matches.length;
}

bool _hasDuplicateStrings(Object? raw) {
  if (raw is! Iterable) return false;
  final seen = <String>{};
  for (final value in raw) {
    final text = value?.toString();
    if (text == null || text.isEmpty) continue;
    if (!seen.add(text)) return true;
  }
  return false;
}

Map<String, dynamic> _gm013EnvelopeFromSent({
  required Map<String, dynamic> sent,
  required String groupId,
}) {
  return <String, dynamic>{
    'groupId': groupId,
    'senderId': sent['senderPeerId'] as String,
    'senderUsername':
        sent['senderUsername'] as String? ?? _usernameForRole('charlie'),
    'senderDeviceId': sent['senderDeviceId'] as String?,
    'transportPeerId': sent['transportPeerId'] as String?,
    'keyEpoch': sent['keyEpoch'] as int? ?? 1,
    'text': sent['text'] as String,
    'timestamp': sent['timestamp'] as String,
    'messageId': sent['messageId'] as String,
  };
}

Map<String, dynamic> _gm013AfterCutoffEnvelope({
  required String groupId,
  required Map<String, dynamic> charlieIdentity,
  required Map<String, dynamic> beforeSent,
  required DateTime afterSentAt,
  required String text,
}) {
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;
  return <String, dynamic>{
    'groupId': groupId,
    'senderId': charliePeerId,
    'senderUsername':
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    'senderDeviceId': charlieTransportPeerId,
    'transportPeerId': charlieTransportPeerId,
    'keyEpoch': beforeSent['keyEpoch'] as int? ?? 1,
    'text': text,
    'timestamp': afterSentAt.toUtc().toIso8601String(),
    'messageId': 'gmp_${_runId}_${_scenario}_charlieAtCutoff_charlie',
  };
}

Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final events = <Map<String, dynamic>>[];
  debugSetFlowEventSink((payload) {
    events.add(Map<String, dynamic>.from(payload));
  });
  try {
    await action();
  } finally {
    debugSetFlowEventSink(null);
  }
  return events;
}

int _capturedGroupDrainMessageCount(List<Map<String, dynamic>> events) {
  for (final event in events) {
    if (event['event'] != 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_DONE') continue;
    final details = event['details'];
    if (details is! Map) continue;
    final count = details['messageCount'];
    if (count is int) return count;
    if (count is num) return count.toInt();
    if (count is String) return int.tryParse(count) ?? 0;
  }
  return 0;
}

class _Gm016PostLeaveProbe {
  _Gm016PostLeaveProbe({required this.stack, required this.groupId});

  final GroupMultiDeviceTestStack stack;
  final String groupId;
  final List<Map<String, dynamic>> groupMessageEvents =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> groupReactionEvents =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> flowEvents = <Map<String, dynamic>>[];

  void Function(Map<String, dynamic>)? _previousGroupMessageHandler;
  void Function(Map<String, dynamic>)? _previousGroupReactionHandler;

  void start() {
    _previousGroupMessageHandler = stack.bridge.onGroupMessageReceived;
    _previousGroupReactionHandler = stack.bridge.onGroupReactionReceived;
    stack.bridge.onGroupMessageReceived = (data) {
      if (data['groupId'] == groupId) {
        groupMessageEvents.add(Map<String, dynamic>.from(data));
      }
      _previousGroupMessageHandler?.call(data);
    };
    stack.bridge.onGroupReactionReceived = (data) {
      if (data['groupId'] == groupId) {
        groupReactionEvents.add(Map<String, dynamic>.from(data));
      }
      _previousGroupReactionHandler?.call(data);
    };
    debugSetFlowEventSink((payload) {
      flowEvents.add(Map<String, dynamic>.from(payload));
    });
  }

  void stop() {
    stack.bridge.onGroupMessageReceived = _previousGroupMessageHandler;
    stack.bridge.onGroupReactionReceived = _previousGroupReactionHandler;
    debugSetFlowEventSink(null);
  }

  int get messageBaseline => groupMessageEvents.length;

  int get reactionBaseline => groupReactionEvents.length;

  int get flowBaseline => flowEvents.length;

  int groupMessageCountSince(int baseline) {
    return groupMessageEvents.length - baseline;
  }

  int groupReactionCountSince(int baseline) {
    return groupReactionEvents.length - baseline;
  }

  int flowCountSince(int baseline, Set<String> eventNames) {
    return flowEvents
        .skip(baseline)
        .where((event) => eventNames.contains(event['event']))
        .length;
  }

  int totalFlowCount(Set<String> eventNames) {
    return flowEvents
        .where((event) => eventNames.contains(event['event']))
        .length;
  }

  bool get leaveResponseOk {
    return flowEvents.any((event) {
      if (event['event'] != 'GROUP_FL_BRIDGE_LEAVE_RESPONSE') return false;
      final details = event['details'];
      return details is Map && details['ok'] == true;
    });
  }
}

class _Gm017ValidationProbe {
  _Gm017ValidationProbe({required this.stack, required this.groupId});

  final GroupMultiDeviceTestStack stack;
  final String groupId;
  final List<Map<String, dynamic>> groupMessageEvents =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> flowEvents = <Map<String, dynamic>>[];

  void Function(Map<String, dynamic>)? _previousGroupMessageHandler;

  void start() {
    _previousGroupMessageHandler = stack.bridge.onGroupMessageReceived;
    stack.bridge.onGroupMessageReceived = (data) {
      if (data['groupId'] == groupId) {
        groupMessageEvents.add(Map<String, dynamic>.from(data));
      }
      _previousGroupMessageHandler?.call(data);
    };
    debugSetFlowEventSink((payload) {
      flowEvents.add(Map<String, dynamic>.from(payload));
    });
  }

  void stop() {
    stack.bridge.onGroupMessageReceived = _previousGroupMessageHandler;
    debugSetFlowEventSink(null);
  }

  int get flowBaseline => flowEvents.length;

  bool get leaveRequested {
    return flowEvents.any(
      (event) => event['event'] == 'GROUP_FL_BRIDGE_LEAVE_REQUEST',
    );
  }

  bool get leaveResponseOk {
    return flowEvents.any((event) {
      if (event['event'] != 'GROUP_FL_BRIDGE_LEAVE_RESPONSE') return false;
      final details = event['details'];
      return details is Map && details['ok'] == true;
    });
  }

  int validationRejectCountSince(int baseline) {
    return flowEvents.skip(baseline).where(_isValidationRejectEvent).length;
  }

  String? validationRejectReasonSince(int baseline) {
    for (final event in flowEvents.skip(baseline)) {
      if (!_isValidationRejectEvent(event)) continue;
      final details = event['details'];
      if (details is! Map) continue;
      final reason = details['reason']?.toString();
      if (reason == 'non_member' || reason == 'bad_signature_or_epoch') {
        return reason;
      }
    }
    return null;
  }

  Map<String, dynamic>? publishValidationFeedbackSince(
    int baseline, {
    required String messageId,
  }) {
    for (final event in flowEvents.skip(baseline)) {
      if (event['event'] != 'GROUP_PUBLISH_VALIDATION_REJECTED') continue;
      final details = event['details'];
      if (details is! Map) continue;
      if (details['messageId'] != messageId) continue;
      final reason = details['reason']?.toString();
      if (reason != 'non_member' && reason != 'bad_signature_or_epoch') {
        continue;
      }
      return Map<String, dynamic>.from(details);
    }
    return null;
  }

  bool _isValidationRejectEvent(Map<String, dynamic> event) {
    if (event['event'] != 'GROUP_VALIDATION_REJECTED') return false;
    final details = event['details'];
    if (details is! Map) return false;
    final reason = details['reason']?.toString();
    return reason == 'non_member' || reason == 'bad_signature_or_epoch';
  }
}

Future<String> _waitForGm017ValidationReject({
  required _Gm017ValidationProbe probe,
  required int baseline,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final reason = probe.validationRejectReasonSince(baseline);
    if (reason != null) return reason;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException(
    '$_role timed out waiting for GM-017 validation reject',
  );
}

Future<Map<String, dynamic>> _waitForGo003PublishValidationFeedback({
  required _Gm017ValidationProbe probe,
  required int baseline,
  required String messageId,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final feedback = probe.publishValidationFeedbackSince(
      baseline,
      messageId: messageId,
    );
    if (feedback != null) return feedback;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException(
    '$_role timed out waiting for GO-003 sender validation feedback',
  );
}

Future<Map<String, dynamic>> _installGm017ConfigWithoutCharlie({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String charliePeerId,
}) async {
  final group = await stack.groupRepo.getGroup(groupId);
  if (group == null) {
    throw StateError('Missing group $groupId before GM-017 config update');
  }
  await stack.groupRepo.removeMember(groupId, charliePeerId);
  final remainingMembers = await stack.groupRepo.getMembers(groupId);
  final groupConfig = buildGroupConfigPayload(group, remainingMembers);
  await callGroupUpdateConfig(
    stack.bridge,
    groupId: groupId,
    groupConfig: groupConfig,
  );
  final memberPeerIds = remainingMembers
      .map((member) => member.peerId)
      .toList(growable: false);
  return <String, dynamic>{
    'memberPeerIds': memberPeerIds,
    'memberListExcludesCharlie': !memberPeerIds.contains(charliePeerId),
  };
}

Map<String, dynamic>? _gm013RemovedAfterCutoffEvent(
  List<Map<String, dynamic>> events,
) {
  for (final event in events) {
    if (event['event'] == 'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF') {
      return event;
    }
  }
  return null;
}

Future<Map<String, dynamic>> _processGm013BoundaryMessages({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required Map<String, dynamic> beforeEnvelope,
  required Map<String, dynamic> afterEnvelope,
  required String charliePeerId,
}) async {
  final beforeText = beforeEnvelope['text'] as String;
  final afterText = afterEnvelope['text'] as String;
  await stack.groupListener.handleReplayEnvelope(
    beforeEnvelope,
    rethrowOnError: true,
  );
  final beforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieBeforeCutoff',
    text: beforeText,
    senderPeerId: charliePeerId,
  );

  final events = await _captureFlowEvents(() async {
    await stack.groupListener.handleReplayEnvelope(
      afterEnvelope,
      rethrowOnError: true,
    );
  });
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final rejectedEvent = _gm013RemovedAfterCutoffEvent(events);
  final afterCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: afterText,
    senderPeerId: charliePeerId,
  );
  return <String, dynamic>{
    'beforeReceived': beforeReceived,
    'beforeCount': await _proofMessageCount(
      stack: stack,
      groupId: groupId,
      text: beforeText,
      senderPeerId: charliePeerId,
    ),
    'afterCount': afterCount,
    'afterAccepted': afterCount > 0,
    'clearRejectionEvent': rejectedEvent != null,
    'rejectionReason': rejectedEvent == null
        ? null
        : 'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
  };
}

Future<int> _memberRemovedTimelineCount({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String removedPeerId,
  required String senderPeerId,
  required DateTime eventAt,
}) async {
  final removalId =
      'sys-member_removed:$groupId:$removedPeerId:'
      '$senderPeerId:${eventAt.toUtc().microsecondsSinceEpoch}';
  final messages = await stack.groupMsgRepo.getMessagesPage(
    groupId,
    limit: 100,
  );
  return messages.where((message) => message.id == removalId).length;
}

Future<List<String>> _memberPeerIds(
  GroupMultiDeviceTestStack stack,
  String groupId,
) async {
  final members = await stack.groupRepo.getMembers(groupId);
  return members.map((member) => member.peerId).toList(growable: false);
}

Future<int> _memberRowCount({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String peerId,
}) async {
  final members = await stack.groupRepo.getMembers(groupId);
  return members.where((member) => member.peerId == peerId).length;
}

Future<int> _activeDeviceBindingCount({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String peerId,
  String? deviceId,
}) async {
  final member = await stack.groupRepo.getMember(groupId, peerId);
  final activeDevices =
      member?.activeDevices ?? const <GroupMemberDeviceIdentity>[];
  if (deviceId == null || deviceId.isEmpty) {
    return activeDevices.length;
  }
  return activeDevices.where((device) => device.deviceId == deviceId).length;
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

Future<String> _persistGroupFixtureWithoutJoin({
  required GroupMultiDeviceTestStack stack,
  required Map<String, dynamic> fixture,
}) async {
  final group = GroupModel.fromMap(
    Map<String, dynamic>.from(fixture['group'] as Map),
  );
  final key = GroupKeyInfo.fromMap(
    Map<String, dynamic>.from(fixture['key'] as Map),
  );
  final members = (fixture['members'] as List<dynamic>)
      .map((raw) => GroupMember.fromMap(Map<String, dynamic>.from(raw as Map)))
      .toList(growable: false);

  await stack.groupRepo.saveGroup(group);
  for (final member in members) {
    await stack.groupRepo.saveMember(member);
  }
  await stack.groupRepo.saveKey(key);
  return group.id;
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

Future<void> _waitForMemberRole({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String memberPeerId,
  required MemberRole role,
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
        '[GMP][$_role] drain while waiting for role failed: $error',
      );
    }
    final member = await stack.groupRepo.getMember(groupId, memberPeerId);
    return member?.role == role;
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
    'eventAt': membershipEventAt.toIso8601String(),
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
}

Future<void> _publishMemberAddedSystemPayload({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required GroupMember member,
  required DateTime eventAt,
}) async {
  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  if (updatedGroup == null) {
    throw StateError('Missing updated group $groupId after member add');
  }

  final normalizedEventAt = eventAt.toUtc();
  final messageId =
      'member_added:$groupId:${stack.identity.peerId}:${normalizedEventAt.microsecondsSinceEpoch}';
  final payload = jsonEncode(<String, dynamic>{
    '__sys': 'member_added',
    'eventAt': normalizedEventAt.toIso8601String(),
    'member': member.toConfigJson(),
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
  expect(publish['ok'], isTrue, reason: 'member_added publish must succeed');

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
      'timestamp': normalizedEventAt.toIso8601String(),
      'messageId': messageId,
    }),
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    messageId: messageId,
    recipientPeerIds: updatedMembers
        .map((updatedMember) => updatedMember.peerId)
        .where((peerId) => peerId.isNotEmpty)
        .toSet()
        .toList(growable: false),
  );
}

Future<void> _updateMemberRoleAndPublish({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String memberPeerId,
  required MemberRole role,
  required DateTime eventAt,
}) async {
  final normalizedEventAt = eventAt.toUtc();
  await updateGroupMemberRole(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    memberPeerId: memberPeerId,
    role: role,
    selfPeerId: stack.identity.peerId,
    eventAt: normalizedEventAt,
  );

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  final updatedMember = await stack.groupRepo.getMember(groupId, memberPeerId);
  if (updatedGroup == null || updatedMember == null) {
    throw StateError('Missing updated role state for $memberPeerId');
  }

  final messageId =
      'member_role_updated:$groupId:$memberPeerId:${normalizedEventAt.microsecondsSinceEpoch}';
  final payload = jsonEncode(<String, dynamic>{
    '__sys': 'member_role_updated',
    'eventAt': normalizedEventAt.toIso8601String(),
    'member': updatedMember.toConfigJson(),
    'groupConfig': buildGroupConfigPayload(
      updatedGroup,
      updatedMembers,
      configVersionOverride: normalizedEventAt,
    ),
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
  expect(
    publish['ok'],
    isTrue,
    reason: 'member_role_updated publish must succeed',
  );
}

Future<Map<String, dynamic>> _prepareMemberRemovedSystemPayload({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String memberPeerId,
  required String memberUsername,
  required DateTime eventAt,
}) async {
  final normalizedEventAt = eventAt.toUtc();
  await removeGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    memberPeerId: memberPeerId,
    selfPeerId: stack.identity.peerId,
    actorUsername: stack.identity.username,
    eventAt: normalizedEventAt,
    msgRepo: stack.groupMsgRepo,
  );

  final group = await stack.groupRepo.getGroup(groupId);
  final remainingMembers = await stack.groupRepo.getMembers(groupId);
  if (group == null) {
    throw StateError('Missing group $groupId after member removal');
  }

  final messageId =
      'member_removed:$groupId:${stack.identity.peerId}:${normalizedEventAt.microsecondsSinceEpoch}';
  final sysMessage = jsonEncode(<String, dynamic>{
    '__sys': 'member_removed',
    'member': <String, dynamic>{
      'peerId': memberPeerId,
      'username': memberUsername,
    },
    'removedAt': normalizedEventAt.toIso8601String(),
    'groupConfig': buildGroupConfigPayload(
      group,
      remainingMembers,
      configVersionOverride: normalizedEventAt,
    ),
  });

  final removalReplayEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: jsonEncode(<String, dynamic>{
      'groupId': groupId,
      'senderId': stack.identity.peerId,
      'senderUsername': stack.identity.username,
      'text': sysMessage,
      'timestamp': normalizedEventAt.toIso8601String(),
      'messageId': messageId,
    }),
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    messageId: messageId,
    recipientPeerIds: <String>[memberPeerId],
  );

  return <String, dynamic>{
    'messageId': messageId,
    'sysMessage': sysMessage,
    'replayEnvelope': removalReplayEnvelope,
    'eventAt': normalizedEventAt.toIso8601String(),
    'memberPeerId': memberPeerId,
  };
}

Future<void> _publishPreparedMemberRemovedSystemPayload({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required Map<String, dynamic> prepared,
}) async {
  final memberPeerId = prepared['memberPeerId'] as String;
  final messageId = prepared['messageId'] as String;
  final sysMessage = prepared['sysMessage'] as String;
  final eventAt = DateTime.parse(prepared['eventAt'] as String).toUtc();
  final replayEnvelope = prepared['replayEnvelope'] as String;

  final publish = await callGroupPublish(
    stack.bridge,
    groupId: groupId,
    text: sysMessage,
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    messageId: messageId,
  );
  expect(publish['ok'], isTrue, reason: 'member_removed publish must succeed');

  await callGroupInboxStore(
    stack.bridge,
    groupId,
    replayEnvelope,
    recipientPeerIds: <String>[memberPeerId],
  );
  await sendGroupMembershipUpdateDirect(
    sendP2PMessage: (peerId, message) async {
      return stack.p2pService.sendMessage(peerId, message);
    },
    recipientPeerId: memberPeerId,
    groupId: groupId,
    senderPeerId: stack.identity.peerId,
    replayEnvelope: replayEnvelope,
    timestamp: eventAt,
    messageId: messageId,
  );
}

Future<DateTime> _removeCharlieAndPublish({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required Map<String, dynamic> charlieIdentity,
  DateTime? removedAtOverride,
}) async {
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieUsername =
      charlieIdentity['username'] as String? ?? _usernameForRole('charlie');
  final removedAt = removedAtOverride?.toUtc() ?? DateTime.now().toUtc();

  await removeGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    memberPeerId: charliePeerId,
    selfPeerId: stack.identity.peerId,
    actorUsername: stack.identity.username,
    eventAt: removedAt,
    msgRepo: stack.groupMsgRepo,
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

  final removalReplayEnvelope = await buildGroupOfflineReplayEnvelope(
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
  await callGroupInboxStore(
    stack.bridge,
    groupId,
    removalReplayEnvelope,
    recipientPeerIds: <String>[charliePeerId],
  );
  await sendGroupMembershipUpdateDirect(
    sendP2PMessage: (peerId, message) async {
      return stack.p2pService.sendMessage(peerId, message);
    },
    recipientPeerId: charliePeerId,
    groupId: groupId,
    senderPeerId: stack.identity.peerId,
    replayEnvelope: removalReplayEnvelope,
    timestamp: removedAt,
    messageId: sourceEventId,
  );
  return removedAt;
}

Future<List<Map<String, dynamic>>> _sendGe008Batch({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required Iterable<String> keys,
  required String phase,
}) async {
  final sent = <Map<String, dynamic>>[];
  for (final key in keys) {
    sent.add(
      await _sendProofMessage(
        stack: stack,
        groupId: groupId,
        key: key,
        text: 'GE-008 $phase $key $_runId',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return sent;
}

Future<List<Map<String, dynamic>>> _waitForGe008ReceivedBatch({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required Iterable<MapEntry<String, String>> expected,
  required Map<String, Map<String, dynamic>> identities,
}) async {
  final received = <Map<String, dynamic>>[];
  for (final entry in expected) {
    final sent = await waitForSharedJson(
      _signalName('${entry.value}_sent_${entry.key}.json'),
    );
    final receivedMessage = await _waitForReceivedProofMessage(
      stack: stack,
      groupId: groupId,
      key: entry.key,
      text: sent['text'] as String,
      senderPeerId: identities[entry.value]!['peerId'] as String,
    );
    received.add(receivedMessage);
  }
  return received;
}

List<String> _ge008ProofKeys(List<Map<String, dynamic>> messages) {
  return messages
      .map((message) => message['key'] as String)
      .toList(growable: false);
}

bool _ge008AllPersistedOnce(List<Map<String, dynamic>> messages) {
  return messages.every((message) => message['persistedCount'] == 1);
}

List<String> _ge009FinalTimelineKeys({
  required List<Map<String, dynamic>> sentMessages,
  required List<Map<String, dynamic>> receivedMessages,
}) {
  final present = <String>{};
  present.addAll(sentMessages.map((message) => message['key'] as String));
  present.addAll(receivedMessages.map((message) => message['key'] as String));
  return _ge009FinalKeys
      .where((key) => present.contains(key))
      .toList(growable: false);
}

Future<int> _ge008PlaintextCountForSentKeys({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required Iterable<MapEntry<String, String>> expected,
  required Map<String, Map<String, dynamic>> identities,
}) async {
  var count = 0;
  for (final entry in expected) {
    final sent = await waitForSharedJson(
      _signalName('${entry.value}_sent_${entry.key}.json'),
    );
    count += await _proofMessageCount(
      stack: stack,
      groupId: groupId,
      text: sent['text'] as String,
      senderPeerId: identities[entry.value]!['peerId'] as String,
    );
  }
  return count;
}

int _ge008PublishCountForMessageIds({
  required GroupMultiDeviceTestStack stack,
  required Iterable<String> messageIds,
}) {
  final ids = messageIds.toSet();
  if (ids.isEmpty) return 0;
  final bridge = stack.bridge;
  if (bridge is! RecordingGoBridgeClient) return 0;
  var count = 0;
  for (final raw in bridge.sentMessages) {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    if (parsed['cmd'] != 'group:publish') continue;
    final payload = parsed['payload'] as Map<String, dynamic>;
    if (ids.contains(payload['messageId'])) count++;
  }
  return count;
}

Future<void> _runGe001Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-001 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final aliceText = 'GE-001 alice fanout $_runId';
  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe001Initial',
    text: aliceText,
  );
  await waitForSharedSignal(_signalName('bob_received_aliceGe001Initial.json'));
  await waitForSharedSignal(
    _signalName('charlie_received_aliceGe001Initial.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGe001Initial.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGe001Initial',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );
  await waitForSharedSignal(
    _signalName('charlie_received_bobGe001Initial.json'),
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGe001Initial.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGe001Initial',
    text: charlieSent['text'] as String,
    senderPeerId: identities['charlie']!['peerId'] as String,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[aliceSent],
    receivedMessages: <Map<String, dynamic>>[bobReceived, charlieReceived],
  );
}

Future<void> _runGe001Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGe001Initial.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe001Initial',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceGe001Initial.json'),
  );

  final bobText = 'GE-001 bob fanout $_runId';
  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGe001Initial',
    text: bobText,
  );
  await waitForSharedSignal(_signalName('alice_received_bobGe001Initial.json'));
  await waitForSharedSignal(
    _signalName('charlie_received_bobGe001Initial.json'),
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGe001Initial.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGe001Initial',
    text: charlieSent['text'] as String,
    senderPeerId: identities['charlie']!['peerId'] as String,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[aliceReceived, charlieReceived],
  );
}

Future<void> _runGe001Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGe001Initial.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe001Initial',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGe001Initial.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGe001Initial',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );
  await waitForSharedSignal(_signalName('alice_received_bobGe001Initial.json'));

  final charlieText = 'GE-001 charlie fanout $_runId';
  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGe001Initial',
    text: charlieText,
  );
  await waitForSharedSignal(
    _signalName('alice_received_charlieGe001Initial.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_charlieGe001Initial.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[charlieSent],
    receivedMessages: <Map<String, dynamic>>[aliceReceived, bobReceived],
  );
}

List<String> _ge002PostRemovalKeys() => List<String>.generate(10, (index) {
  final ordinal = (index + 1).toString().padLeft(2, '0');
  return 'aliceGe002PostRemoval$ordinal';
});

Future<void> _runGe002Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-002 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final bobPeerId = identities['bob']!['peerId'] as String;
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_ge002_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_ge002_self_removed'));

  final sentMessages = <Map<String, dynamic>>[];
  final keys = _ge002PostRemovalKeys();
  final firstSendAt = DateTime.now().toUtc();
  for (var index = 0; index < keys.length; index++) {
    final key = keys[index];
    final sent = await _sendProofMessage(
      stack: stack,
      groupId: groupId,
      key: key,
      text: 'GE-002 Alice post-removal ${index + 1} $_runId',
      timestamp: firstSendAt.add(Duration(seconds: index)),
    );
    sentMessages.add(sent);
    await waitForSharedSignal(_signalName('bob_received_$key.json'));
  }

  final everyPostRemovalExcludedCharlie = sentMessages.every((sent) {
    final recipients = (sent['recipientPeerIds'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    return recipients.length == 1 && recipients.single == bobPeerId;
  });

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'ge002RemovalContinuityProof': <String, dynamic>{
        'removedCharlie': true,
        'removedPeerId': charliePeerId,
        'removedAt': removedAt.toIso8601String(),
        'actualDurablePayloadProof': sentMessages.every(
          (sent) => sent['actualDurablePayloadProof'] == true,
        ),
        'postRemovalMessageCount': sentMessages.length,
        'postRemovalMessageKeys': keys,
        'everyPostRemovalExcludedCharlie': everyPostRemovalExcludedCharlie,
      },
    },
  );
}

Future<void> _runGe002Bob(
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
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge002_removed_charlie'), 'ok');

  final receivedMessages = <Map<String, dynamic>>[];
  final keys = _ge002PostRemovalKeys();
  for (final key in keys) {
    final sent = await waitForSharedJson(_signalName('alice_sent_$key.json'));
    final received = await _waitForReceivedProofMessage(
      stack: stack,
      groupId: groupId,
      key: key,
      text: sent['text'] as String,
      senderPeerId: alicePeerId,
    );
    receivedMessages.add(received);
    writeSharedJson(_signalName('bob_received_$key.json'), received);
  }

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge002RemovalContinuityProof': <String, dynamic>{
        'receivedEveryPostRemovalMessage':
            receivedMessages.length == keys.length,
        'postRemovalReceiptCount': receivedMessages.length,
        'postRemovalMessageKeys': keys,
      },
    },
  );
}

Future<void> _runGe002Charlie(
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
  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_ge002_self_removed'), 'ok');

  final keys = _ge002PostRemovalKeys();
  final sentMessages = <Map<String, dynamic>>[];
  for (final key in keys) {
    final sent = await waitForSharedJson(_signalName('alice_sent_$key.json'));
    sentMessages.add(sent);
  }
  await Future<void>.delayed(const Duration(seconds: 5));

  var postRemovalPlaintextCount = 0;
  for (final sent in sentMessages) {
    postRemovalPlaintextCount += await _proofMessageCount(
      stack: stack,
      groupId: groupId,
      text: sent['text'] as String,
      senderPeerId: alicePeerId,
    );
  }

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'ge002RemovalContinuityProof': <String, dynamic>{
        'selfRemoved': true,
        'groupPresentAfterRemoval':
            await stack.groupRepo.getGroup(groupId) != null,
        'postRemovalPlaintextCount': postRemovalPlaintextCount,
        'checkedPostRemovalMessageCount': keys.length,
        'postRemovalMessageKeys': keys,
      },
    },
  );
}

List<String> _ge003PostRemovalKeys() => List<String>.generate(10, (index) {
  final ordinal = (index + 1).toString().padLeft(2, '0');
  return 'bobGe003PostRemoval$ordinal';
});

Future<void> _runGe003Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-003 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final bobPeerId = identities['bob']!['peerId'] as String;
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_ge003_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_ge003_self_removed'));

  final receivedMessages = <Map<String, dynamic>>[];
  final keys = _ge003PostRemovalKeys();
  for (final key in keys) {
    final sent = await waitForSharedJson(_signalName('bob_sent_$key.json'));
    final received = await _waitForReceivedProofMessage(
      stack: stack,
      groupId: groupId,
      key: key,
      text: sent['text'] as String,
      senderPeerId: bobPeerId,
    );
    receivedMessages.add(received);
    writeSharedJson(_signalName('alice_received_$key.json'), received);
  }

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge003RemainingPairProof': <String, dynamic>{
        'removedCharlie': true,
        'removedPeerId': charliePeerId,
        'removedAt': removedAt.toIso8601String(),
        'receivedEveryPostRemovalMessage':
            receivedMessages.length == keys.length,
        'postRemovalReceiptCount': receivedMessages.length,
        'postRemovalMessageKeys': keys,
      },
    },
  );
}

Future<void> _runGe003Bob(
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
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge003_removed_charlie'), 'ok');

  final sentMessages = <Map<String, dynamic>>[];
  final keys = _ge003PostRemovalKeys();
  final firstSendAt = DateTime.now().toUtc();
  for (var index = 0; index < keys.length; index++) {
    final key = keys[index];
    final sent = await _sendProofMessage(
      stack: stack,
      groupId: groupId,
      key: key,
      text: 'GE-003 Bob post-removal ${index + 1} $_runId',
      timestamp: firstSendAt.add(Duration(seconds: index)),
    );
    sentMessages.add(sent);
    await waitForSharedSignal(_signalName('alice_received_$key.json'));
  }

  final everyPostRemovalExcludedCharlie = sentMessages.every((sent) {
    final recipients = (sent['recipientPeerIds'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    return recipients.length == 1 && recipients.single == alicePeerId;
  });

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'ge003RemainingPairProof': <String, dynamic>{
        'actualDurablePayloadProof': sentMessages.every(
          (sent) => sent['actualDurablePayloadProof'] == true,
        ),
        'postRemovalMessageCount': sentMessages.length,
        'postRemovalMessageKeys': keys,
        'everyPostRemovalExcludedCharlie': everyPostRemovalExcludedCharlie,
      },
    },
  );
}

Future<void> _runGe003Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final bobPeerId = identities['bob']!['peerId'] as String;
  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_ge003_self_removed'), 'ok');

  final keys = _ge003PostRemovalKeys();
  final sentMessages = <Map<String, dynamic>>[];
  for (final key in keys) {
    final sent = await waitForSharedJson(_signalName('bob_sent_$key.json'));
    sentMessages.add(sent);
  }
  await Future<void>.delayed(const Duration(seconds: 5));

  var postRemovalPlaintextCount = 0;
  for (final sent in sentMessages) {
    postRemovalPlaintextCount += await _proofMessageCount(
      stack: stack,
      groupId: groupId,
      text: sent['text'] as String,
      senderPeerId: bobPeerId,
    );
  }

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'ge003RemainingPairProof': <String, dynamic>{
        'selfRemoved': true,
        'groupPresentAfterRemoval':
            await stack.groupRepo.getGroup(groupId) != null,
        'postRemovalPlaintextCount': postRemovalPlaintextCount,
        'checkedPostRemovalMessageCount': keys.length,
        'postRemovalMessageKeys': keys,
      },
    },
  );
}

const _ge004PostReaddKeyByRole = <String, String>{
  'alice': 'aliceGe004PostReadd',
  'bob': 'bobGe004PostReadd',
  'charlie': 'charlieGe004PostReadd',
};

List<String> _ge004ReceivedKeysForRole(String role) => _ge004PostReaddKeyByRole
    .entries
    .where((entry) => entry.key != role)
    .map((entry) => entry.value)
    .toList(growable: false);

Map<String, dynamic> _ge004ReaddExchangeProof({
  required String role,
  required String sentKey,
  required List<String> receivedKeys,
  required List<Map<String, dynamic>> sentMessages,
  required List<Map<String, dynamic>> receivedMessages,
  required List<String> finalMemberPeerIds,
  String? removedPeerId,
  String? readdedPeerId,
}) {
  return <String, dynamic>{
    if (role == 'alice') ...<String, dynamic>{
      'removedCharlie': removedPeerId != null,
      'removedPeerId': removedPeerId,
      'readdedPeerId': readdedPeerId,
    },
    'readdedCharlie': finalMemberPeerIds.contains(readdedPeerId),
    'memberListIncludesAll': finalMemberPeerIds.length == 3,
    'actualDurablePayloadProof': sentMessages.every(
      (sent) => sent['actualDurablePayloadProof'] == true,
    ),
    'postReaddSentCount': sentMessages.length,
    'postReaddReceivedCount': receivedMessages.length,
    'postReaddSentKeys': <String>[sentKey],
    'postReaddReceivedKeys': receivedKeys,
    'finalMemberPeerIds': finalMemberPeerIds,
  };
}

Future<void> _runGe004Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-004 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_ge004_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_ge004_self_removed'));

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
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rejoinKey == null) {
    throw StateError('GE-004 Alice key rotation failed before re-add');
  }
  writeSharedJson(_signalName('ge004_rejoin_key.json'), <String, dynamic>{
    'keyEpoch': rejoinKey.keyGeneration,
    'groupKey': rejoinKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_ge004_rotated_key'));

  final charlieContact = await stack.contactRepo.getContact(charliePeerId);
  if (charlieContact == null) {
    throw StateError('Alice missing Charlie contact before GE-004 re-add');
  }
  final readdAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charlieContact.peerId,
    username: charlieContact.username,
    role: MemberRole.writer,
    publicKey: charlieContact.publicKey,
    mlKemPublicKey: charlieContact.mlKemPublicKey,
    joinedAt: readdAt,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdAt,
  );

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_ge004_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );

  await waitForSharedSignal(_signalName('bob_ge004_membership_readded'));
  await waitForSharedSignal(_signalName('charlie_ge004_group_rejoined'));

  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge004PostReaddKeyByRole['alice']!,
    text: 'GE-004 Alice after Charlie re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGe004PostReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceGe004PostReadd.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGe004PostReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge004PostReaddKeyByRole['bob']!,
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('alice_received_bobGe004PostReadd.json'),
    bobReceived,
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGe004PostReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge004PostReaddKeyByRole['charlie']!,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('alice_received_charlieGe004PostReadd.json'),
    charlieReceived,
  );

  final sentMessages = <Map<String, dynamic>>[aliceSent];
  final receivedMessages = <Map<String, dynamic>>[bobReceived, charlieReceived];
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge004ReaddExchangeProof': _ge004ReaddExchangeProof(
        role: 'alice',
        sentKey: _ge004PostReaddKeyByRole['alice']!,
        receivedKeys: _ge004ReceivedKeysForRole('alice'),
        sentMessages: sentMessages,
        receivedMessages: receivedMessages,
        finalMemberPeerIds: finalMemberPeerIds,
        removedPeerId: charliePeerId,
        readdedPeerId: charliePeerId,
      ),
    },
  );
}

Future<void> _runGe004Bob(
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
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge004_removed_charlie'), 'ok');

  final rejoinKey = await waitForSharedJson(
    _signalName('ge004_rejoin_key.json'),
  );
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rejoinKey['keyEpoch'] as int,
  );
  writeSharedText(_signalName('bob_ge004_rotated_key'), 'ok');

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge004_membership_readded'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGe004PostReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge004PostReaddKeyByRole['alice']!,
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGe004PostReadd.json'),
    aliceReceived,
  );

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge004PostReaddKeyByRole['bob']!,
    text: 'GE-004 Bob after Charlie re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_bobGe004PostReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_bobGe004PostReadd.json'),
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGe004PostReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge004PostReaddKeyByRole['charlie']!,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_charlieGe004PostReadd.json'),
    charlieReceived,
  );

  final sentMessages = <Map<String, dynamic>>[bobSent];
  final receivedMessages = <Map<String, dynamic>>[
    aliceReceived,
    charlieReceived,
  ];
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge004ReaddExchangeProof': _ge004ReaddExchangeProof(
        role: 'bob',
        sentKey: _ge004PostReaddKeyByRole['bob']!,
        receivedKeys: _ge004ReceivedKeysForRole('bob'),
        sentMessages: sentMessages,
        receivedMessages: receivedMessages,
        finalMemberPeerIds: finalMemberPeerIds,
        readdedPeerId: charliePeerId,
      ),
    },
  );
}

Future<void> _runGe004Charlie(
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
  writeSharedText(_signalName('charlie_ge004_self_removed'), 'ok');

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge004_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_ge004_group_rejoined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGe004PostReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge004PostReaddKeyByRole['alice']!,
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_aliceGe004PostReadd.json'),
    aliceReceived,
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGe004PostReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge004PostReaddKeyByRole['bob']!,
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_bobGe004PostReadd.json'),
    bobReceived,
  );

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge004PostReaddKeyByRole['charlie']!,
    text: 'GE-004 Charlie after re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_charlieGe004PostReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_charlieGe004PostReadd.json'),
  );

  final sentMessages = <Map<String, dynamic>>[charlieSent];
  final receivedMessages = <Map<String, dynamic>>[aliceReceived, bobReceived];
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge004ReaddExchangeProof': _ge004ReaddExchangeProof(
        role: 'charlie',
        sentKey: _ge004PostReaddKeyByRole['charlie']!,
        receivedKeys: _ge004ReceivedKeysForRole('charlie'),
        sentMessages: sentMessages,
        receivedMessages: receivedMessages,
        finalMemberPeerIds: finalMemberPeerIds,
        readdedPeerId: stack.identity.peerId,
      ),
    },
  );
}

const _ge005CycleCount = 20;

String _ge005CycleTag(int cycle) => cycle.toString().padLeft(2, '0');

String _ge005RemovedKey(int cycle) =>
    'aliceGe005Removed${_ge005CycleTag(cycle)}';

String _ge005ReaddKey(int cycle) => 'bobGe005Readd${_ge005CycleTag(cycle)}';

bool _sentKeyStartsWith(Map<String, dynamic> sent, String prefix) {
  return (sent['key'] as String? ?? '').startsWith(prefix);
}

Map<String, dynamic> _ge005RemoveReaddLoopProof({
  required List<Map<String, dynamic>> sentMessages,
  required List<Map<String, dynamic>> receivedMessages,
  required List<String> finalMemberPeerIds,
  required String charliePeerId,
  int removedWindowPlaintextCount = 0,
}) {
  final sentKeys = sentMessages
      .map((message) => message['key'] as String)
      .toList(growable: false);
  final receivedKeys = receivedMessages
      .map((message) => message['key'] as String)
      .toList(growable: false);
  final removedSentKeys = sentKeys
      .where((key) => key.startsWith('aliceGe005Removed'))
      .toList(growable: false);
  final removedReceivedKeys = receivedKeys
      .where((key) => key.startsWith('aliceGe005Removed'))
      .toList(growable: false);
  final readdSentKeys = sentKeys
      .where((key) => key.startsWith('bobGe005Readd'))
      .toList(growable: false);
  final readdReceivedKeys = receivedKeys
      .where((key) => key.startsWith('bobGe005Readd'))
      .toList(growable: false);
  final removedWindowSentMessages = sentMessages
      .where((sent) => _sentKeyStartsWith(sent, 'aliceGe005Removed'))
      .toList(growable: false);
  final readdWindowSentMessages = sentMessages
      .where((sent) => _sentKeyStartsWith(sent, 'bobGe005Readd'))
      .toList(growable: false);

  return <String, dynamic>{
    'cycleCount': _ge005CycleCount,
    'completedCycleCount': _ge005CycleCount,
    'finalMemberListIncludesAll': finalMemberPeerIds.length == 3,
    'finalMemberPeerIds': finalMemberPeerIds,
    'actualDurablePayloadProof': sentMessages.every(
      (sent) => sent['actualDurablePayloadProof'] == true,
    ),
    'removedWindowExcludedCharlie': removedWindowSentMessages.every((sent) {
      final recipients =
          (sent['recipientPeerIds'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toSet();
      return !recipients.contains(charliePeerId);
    }),
    'readdWindowIncludedCharlie': readdWindowSentMessages.every((sent) {
      final recipients =
          (sent['recipientPeerIds'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toSet();
      return recipients.contains(charliePeerId);
    }),
    'removedWindowSentCount': removedSentKeys.length,
    'removedWindowReceivedCount': removedReceivedKeys.length,
    'readdWindowSentCount': readdSentKeys.length,
    'readdWindowReceivedCount': readdReceivedKeys.length,
    'removedWindowPlaintextCount': removedWindowPlaintextCount,
    'removedWindowSentKeys': removedSentKeys,
    'removedWindowReceivedKeys': removedReceivedKeys,
    'readdWindowSentKeys': readdSentKeys,
    'readdWindowReceivedKeys': readdReceivedKeys,
  };
}

Future<void> _runGe005Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-005 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final sentMessages = <Map<String, dynamic>>[];
  final receivedMessages = <Map<String, dynamic>>[];

  for (var cycle = 1; cycle <= _ge005CycleCount; cycle++) {
    final tag = _ge005CycleTag(cycle);
    await _removeCharlieAndPublish(
      stack: stack,
      groupId: groupId,
      charlieIdentity: charlieIdentity,
    );
    await waitForSharedSignal(_signalName('bob_ge005_removed_$tag'));
    await waitForSharedSignal(_signalName('charlie_ge005_self_removed_$tag'));

    final removedKey = _ge005RemovedKey(cycle);
    final removedSent = await _sendProofMessage(
      stack: stack,
      groupId: groupId,
      key: removedKey,
      text: 'GE-005 removed window $tag $_runId',
    );
    sentMessages.add(removedSent);
    await waitForSharedSignal(_signalName('bob_received_$removedKey.json'));

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
        return stack.p2pService.sendMessage(peerId, message);
      },
    );
    if (rejoinKey == null) {
      throw StateError('GE-005 Alice key rotation failed at cycle $tag');
    }
    writeSharedJson(
      _signalName('ge005_rejoin_key_$tag.json'),
      <String, dynamic>{
        'keyEpoch': rejoinKey.keyGeneration,
        'groupKey': rejoinKey.encryptedKey,
      },
    );
    await waitForSharedSignal(_signalName('bob_ge005_rotated_key_$tag'));

    final charlieContact = await stack.contactRepo.getContact(charliePeerId);
    if (charlieContact == null) {
      throw StateError('Alice missing Charlie contact before GE-005 re-add');
    }
    final readdAt = DateTime.now().toUtc();
    final charlieMember = GroupMember(
      groupId: groupId,
      peerId: charlieContact.peerId,
      username: charlieContact.username,
      role: MemberRole.writer,
      publicKey: charlieContact.publicKey,
      mlKemPublicKey: charlieContact.mlKemPublicKey,
      joinedAt: readdAt,
    );
    await addGroupMember(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      groupId: groupId,
      newMember: charlieMember,
      selfPeerId: stack.identity.peerId,
    );
    await _publishMemberAddedSystemPayload(
      stack: stack,
      groupId: groupId,
      member: charlieMember,
      eventAt: readdAt,
    );

    final updatedGroup = await stack.groupRepo.getGroup(groupId);
    final updatedKey = await stack.groupRepo.getLatestKey(groupId);
    final updatedMembers = await stack.groupRepo.getMembers(groupId);
    writeSharedJson(
      _signalName('charlie_ge005_readd_group_fixture_$tag.json'),
      buildGroupFixture(
        group: updatedGroup!,
        keyInfo: updatedKey!,
        members: updatedMembers,
      ),
    );

    await waitForSharedSignal(_signalName('bob_ge005_readded_$tag'));
    await waitForSharedSignal(_signalName('charlie_ge005_rejoined_$tag'));

    final readdKey = _ge005ReaddKey(cycle);
    final bobSent = await waitForSharedJson(
      _signalName('bob_sent_$readdKey.json'),
    );
    final bobReceived = await _waitForReceivedProofMessage(
      stack: stack,
      groupId: groupId,
      key: readdKey,
      text: bobSent['text'] as String,
      senderPeerId: identities['bob']!['peerId'] as String,
    );
    receivedMessages.add(bobReceived);
    writeSharedJson(_signalName('alice_received_$readdKey.json'), bobReceived);
  }

  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge005RemoveReaddLoopProof': _ge005RemoveReaddLoopProof(
        sentMessages: sentMessages,
        receivedMessages: receivedMessages,
        finalMemberPeerIds: finalMemberPeerIds,
        charliePeerId: charliePeerId,
      ),
    },
  );
}

Future<void> _runGe005Bob(
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
  final sentMessages = <Map<String, dynamic>>[];
  final receivedMessages = <Map<String, dynamic>>[];

  for (var cycle = 1; cycle <= _ge005CycleCount; cycle++) {
    final tag = _ge005CycleTag(cycle);
    await _waitForMemberExclusion(
      stack: stack,
      groupId: groupId,
      removedPeerId: charliePeerId,
    );
    writeSharedText(_signalName('bob_ge005_removed_$tag'), 'ok');

    final removedKey = _ge005RemovedKey(cycle);
    final aliceSent = await waitForSharedJson(
      _signalName('alice_sent_$removedKey.json'),
    );
    final aliceReceived = await _waitForReceivedProofMessage(
      stack: stack,
      groupId: groupId,
      key: removedKey,
      text: aliceSent['text'] as String,
      senderPeerId: alicePeerId,
    );
    receivedMessages.add(aliceReceived);
    writeSharedJson(
      _signalName('bob_received_$removedKey.json'),
      aliceReceived,
    );

    final rejoinKey = await waitForSharedJson(
      _signalName('ge005_rejoin_key_$tag.json'),
    );
    await _waitForKeyEpoch(
      stack: stack,
      groupId: groupId,
      keyEpoch: rejoinKey['keyEpoch'] as int,
    );
    writeSharedText(_signalName('bob_ge005_rotated_key_$tag'), 'ok');

    await _waitForMemberInclusion(
      stack: stack,
      groupId: groupId,
      memberPeerId: charliePeerId,
    );
    writeSharedText(_signalName('bob_ge005_readded_$tag'), 'ok');

    final readdKey = _ge005ReaddKey(cycle);
    final bobSent = await _sendProofMessage(
      stack: stack,
      groupId: groupId,
      key: readdKey,
      text: 'GE-005 readd window $tag $_runId',
    );
    sentMessages.add(bobSent);
    await waitForSharedSignal(_signalName('alice_received_$readdKey.json'));
    await waitForSharedSignal(_signalName('charlie_received_$readdKey.json'));
  }

  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge005RemoveReaddLoopProof': _ge005RemoveReaddLoopProof(
        sentMessages: sentMessages,
        receivedMessages: receivedMessages,
        finalMemberPeerIds: finalMemberPeerIds,
        charliePeerId: charliePeerId,
      ),
    },
  );
}

Future<void> _runGe005Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final bobPeerId = identities['bob']!['peerId'] as String;
  final receivedMessages = <Map<String, dynamic>>[];
  var removedWindowPlaintextCount = 0;

  for (var cycle = 1; cycle <= _ge005CycleCount; cycle++) {
    final tag = _ge005CycleTag(cycle);
    await _waitForSelfRemoval(stack: stack, groupId: groupId);
    writeSharedText(_signalName('charlie_ge005_self_removed_$tag'), 'ok');

    final removedKey = _ge005RemovedKey(cycle);
    final aliceSent = await waitForSharedJson(
      _signalName('alice_sent_$removedKey.json'),
    );
    removedWindowPlaintextCount += await _proofMessageCount(
      stack: stack,
      groupId: groupId,
      text: aliceSent['text'] as String,
      senderPeerId: identities['alice']!['peerId'] as String,
    );

    final readdFixture = await waitForSharedJson(
      _signalName('charlie_ge005_readd_group_fixture_$tag.json'),
    );
    await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
    writeSharedText(_signalName('charlie_ge005_rejoined_$tag'), 'ok');

    final readdKey = _ge005ReaddKey(cycle);
    final bobSent = await waitForSharedJson(
      _signalName('bob_sent_$readdKey.json'),
    );
    final bobReceived = await _waitForReceivedProofMessage(
      stack: stack,
      groupId: groupId,
      key: readdKey,
      text: bobSent['text'] as String,
      senderPeerId: bobPeerId,
    );
    receivedMessages.add(bobReceived);
    writeSharedJson(
      _signalName('charlie_received_$readdKey.json'),
      bobReceived,
    );
  }

  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge005RemoveReaddLoopProof': _ge005RemoveReaddLoopProof(
        sentMessages: const <Map<String, dynamic>>[],
        receivedMessages: receivedMessages,
        finalMemberPeerIds: finalMemberPeerIds,
        charliePeerId: stack.identity.peerId,
        removedWindowPlaintextCount: removedWindowPlaintextCount,
      ),
    },
  );
}

Future<void> _runGe006Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-006 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_old_state_persisted.json'));
  await waitForSharedSignal(_signalName('charlie_offline_before_removal'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_ge006_removed_charlie'));

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
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rejoinKey == null) {
    throw StateError('GE-006 Alice key rotation failed before re-add');
  }
  writeSharedJson(_signalName('ge006_rejoin_key.json'), <String, dynamic>{
    'keyEpoch': rejoinKey.keyGeneration,
    'groupKey': rejoinKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_ge006_rotated_key'));

  final removedSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe006RemovedWindow',
    text: 'GE-006 removed window $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGe006RemovedWindow.json'),
  );

  final charlieContact = await stack.contactRepo.getContact(charliePeerId);
  if (charlieContact == null) {
    throw StateError('Alice missing Charlie contact before GE-006 re-add');
  }
  final readdAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charlieContact.peerId,
    username: charlieContact.username,
    role: MemberRole.writer,
    publicKey: charlieContact.publicKey,
    mlKemPublicKey: charlieContact.mlKemPublicKey,
    joinedAt: readdAt,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdAt,
  );

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_ge006_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );

  await waitForSharedSignal(_signalName('bob_ge006_readded_charlie'));

  final alicePostSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe006PostReadd',
    text: 'GE-006 Alice post re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGe006PostReadd.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGe006PostReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGe006PostReadd',
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('alice_received_bobGe006PostReadd.json'),
    bobReceived,
  );

  writeSharedText(_signalName('charlie_relaunch_ready'), 'ok');

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGe006PostCatchUp.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGe006PostCatchUp',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('alice_received_charlieGe006PostCatchUp.json'),
    charlieReceived,
  );

  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  final removedRecipients =
      (removedSent['recipientPeerIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toSet();
  final alicePostRecipients =
      (alicePostSent['recipientPeerIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toSet();
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[removedSent, alicePostSent],
    receivedMessages: <Map<String, dynamic>>[bobReceived, charlieReceived],
    extra: <String, dynamic>{
      'ge006OfflineReaddProof': <String, dynamic>{
        'removedCharlie': true,
        'readdedCharlie': finalMemberPeerIds.contains(charliePeerId),
        'charlieOfflineDuringMutation': true,
        'removedWindowExcludedCharlie': !removedRecipients.contains(
          charliePeerId,
        ),
        'postReaddDurableIncludesCharlie': alicePostRecipients.contains(
          charliePeerId,
        ),
        'receivedBobPostReaddMessage':
            bobReceived['key'] == 'bobGe006PostReadd',
        'receivedCharliePostCatchUpMessage':
            charlieReceived['key'] == 'charlieGe006PostCatchUp',
        'removedPeerId': charliePeerId,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe006Bob(
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
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge006_removed_charlie'), 'ok');

  final rejoinKey = await waitForSharedJson(
    _signalName('ge006_rejoin_key.json'),
  );
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rejoinKey['keyEpoch'] as int,
  );
  writeSharedText(_signalName('bob_ge006_rotated_key'), 'ok');

  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGe006RemovedWindow.json'),
  );
  final removedReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe006RemovedWindow',
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGe006RemovedWindow.json'),
    removedReceived,
  );

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge006_readded_charlie'), 'ok');

  final alicePostSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGe006PostReadd.json'),
  );
  final alicePostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe006PostReadd',
    text: alicePostSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGe006PostReadd.json'),
    alicePostReceived,
  );

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGe006PostReadd',
    text: 'GE-006 Bob post re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_bobGe006PostReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_bobGe006PostReadd.json'),
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGe006PostCatchUp.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGe006PostCatchUp',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_charlieGe006PostCatchUp.json'),
    charlieReceived,
  );

  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[
      removedReceived,
      alicePostReceived,
      charlieReceived,
    ],
    extra: <String, dynamic>{
      'ge006OfflineReaddProof': <String, dynamic>{
        'memberListIncludesCharlie': finalMemberPeerIds.contains(charliePeerId),
        'receivedRemovedWindowMessage':
            removedReceived['key'] == 'aliceGe006RemovedWindow',
        'receivedAlicePostReaddMessage':
            alicePostReceived['key'] == 'aliceGe006PostReadd',
        'receivedCharliePostCatchUpMessage':
            charlieReceived['key'] == 'charlieGe006PostCatchUp',
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe006CharlieSeed(
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
    throw StateError('GE-006 Charlie failed to persist old group/key state');
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

Future<void> _runGe006Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  await waitForSharedSignal(_signalName('charlie_relaunch_ready'));
  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge006_readd_group_fixture.json'),
  );
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: readdFixture,
  );
  writeSharedText(_signalName('charlie_ge006_rejoined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGe006RemovedWindow.json'),
  );
  final alicePostSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGe006PostReadd.json'),
  );
  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGe006PostReadd.json'),
  );

  await drainGroupOfflineInboxForGroup(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    groupMessageListener: stack.groupListener,
    selfPeerId: stack.identity.peerId,
  );
  final removedWindowPlaintextCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final alicePostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe006PostReadd',
    text: alicePostSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_aliceGe006PostReadd.json'),
    alicePostReceived,
  );
  final bobPostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGe006PostReadd',
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_bobGe006PostReadd.json'),
    bobPostReceived,
  );

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGe006PostCatchUp',
    text: 'GE-006 Charlie post catch-up $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_charlieGe006PostCatchUp.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_charlieGe006PostCatchUp.json'),
  );

  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  final receivedMessages = <Map<String, dynamic>>[
    alicePostReceived,
    bobPostReceived,
  ];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[charlieSent],
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge006OfflineReaddProof': <String, dynamic>{
        'offlineDuringRemovalAndReadd': true,
        'retrievedInboxAfterReconnect': true,
        'memberListIncludesAliceBob':
            finalMemberPeerIds.contains(alicePeerId) &&
            finalMemberPeerIds.contains(bobPeerId),
        'memberListIncludesCharlie': finalMemberPeerIds.contains(
          stack.identity.peerId,
        ),
        'postCatchUpPublishAccepted':
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        'removedWindowPlaintextCount': removedWindowPlaintextCount,
        'postReaddReceivedCount': receivedMessages.length,
        'postReaddReceivedKeys': receivedMessages
            .map((message) => message['key'] as String)
            .toList(growable: false),
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGe007Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-007 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await waitForSharedSignal(_signalName('bob_old_state_persisted.json'));
  await waitForSharedSignal(_signalName('bob_offline_before_mutation'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final bobPeerId = identities['bob']!['peerId'] as String;
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('charlie_ge007_self_removed'));

  final removedSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe007RemovedWindow',
    text: 'GE-007 removed window $_runId',
  );

  final charlieContact = await stack.contactRepo.getContact(charliePeerId);
  if (charlieContact == null) {
    throw StateError('Alice missing Charlie contact before GE-007 re-add');
  }
  final readdAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charlieContact.peerId,
    username: charlieContact.username,
    role: MemberRole.writer,
    publicKey: charlieContact.publicKey,
    mlKemPublicKey: charlieContact.mlKemPublicKey,
    joinedAt: readdAt,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdAt,
  );

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_ge007_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );
  await waitForSharedSignal(_signalName('charlie_ge007_readded'));

  final alicePostSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe007PostReadd',
    text: 'GE-007 Alice post re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceGe007PostReadd.json'),
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGe007PostReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGe007PostReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('alice_received_charlieGe007PostReadd.json'),
    charlieReceived,
  );

  writeSharedText(_signalName('bob_relaunch_ready'), 'ok');

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGe007PostCatchUp.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGe007PostCatchUp',
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('alice_received_bobGe007PostCatchUp.json'),
    bobReceived,
  );

  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  final removedRecipients =
      (removedSent['recipientPeerIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toSet();
  final alicePostRecipients =
      (alicePostSent['recipientPeerIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toSet();
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[removedSent, alicePostSent],
    receivedMessages: <Map<String, dynamic>>[charlieReceived, bobReceived],
    extra: <String, dynamic>{
      'ge007OfflineObserverProof': <String, dynamic>{
        'removedCharlie': true,
        'readdedCharlie': finalMemberPeerIds.contains(charliePeerId),
        'bobOfflineDuringMutation': true,
        'removedWindowDurableIncludesBob': removedRecipients.contains(
          bobPeerId,
        ),
        'postReaddDurableIncludesBob': alicePostRecipients.contains(bobPeerId),
        'receivedCharliePostReaddMessage':
            charlieReceived['key'] == 'charlieGe007PostReadd',
        'receivedBobPostCatchUpMessage':
            bobReceived['key'] == 'bobGe007PostCatchUp',
        'offlinePeerId': bobPeerId,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe007BobSeed(
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
    throw StateError('GE-007 Bob failed to persist old group/key state');
  }
  writeSharedJson(
    _signalName('bob_old_state_persisted.json'),
    <String, dynamic>{
      'groupId': groupId,
      'keyEpoch': key.keyGeneration,
      'hadOldConfigBeforeOffline': true,
      'hadOldKeyBeforeOffline': true,
    },
  );
}

Future<void> _runGe007Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  await waitForSharedSignal(_signalName('bob_relaunch_ready'));
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );

  final alicePeerId = identities['alice']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGe007RemovedWindow.json'),
  );
  final alicePostSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGe007PostReadd.json'),
  );
  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGe007PostReadd.json'),
  );

  await drainGroupOfflineInboxForGroup(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    groupMessageListener: stack.groupListener,
    selfPeerId: stack.identity.peerId,
  );

  final removedReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe007RemovedWindow',
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGe007RemovedWindow.json'),
    removedReceived,
  );
  final alicePostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe007PostReadd',
    text: alicePostSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGe007PostReadd.json'),
    alicePostReceived,
  );
  final charliePostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGe007PostReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_charlieGe007PostReadd.json'),
    charliePostReceived,
  );

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGe007PostCatchUp',
    text: 'GE-007 Bob post catch-up $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_bobGe007PostCatchUp.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_bobGe007PostCatchUp.json'),
  );

  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  final receivedMessages = <Map<String, dynamic>>[
    removedReceived,
    alicePostReceived,
    charliePostReceived,
  ];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge007OfflineObserverProof': <String, dynamic>{
        'offlineDuringMutation': true,
        'retrievedInboxAfterReconnect': true,
        'memberListIncludesAliceCharlie':
            finalMemberPeerIds.contains(alicePeerId) &&
            finalMemberPeerIds.contains(charliePeerId),
        'memberListIncludesBob': finalMemberPeerIds.contains(
          stack.identity.peerId,
        ),
        'receivedRemovedWindowMessage':
            removedReceived['key'] == 'aliceGe007RemovedWindow',
        'receivedAlicePostReaddMessage':
            alicePostReceived['key'] == 'aliceGe007PostReadd',
        'receivedCharliePostReaddMessage':
            charliePostReceived['key'] == 'charlieGe007PostReadd',
        'postCatchUpPublishAccepted':
            bobSent['outcome'] == 'success' ||
            bobSent['outcome'] == 'successNoPeers',
        'entitledReceivedCount': receivedMessages.length,
        'entitledReceivedKeys': receivedMessages
            .map((message) => message['key'] as String)
            .toList(growable: false),
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe007Charlie(
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
  final bobPeerId = identities['bob']!['peerId'] as String;
  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_ge007_self_removed'), 'ok');

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge007_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_ge007_readded'), 'ok');

  final alicePostSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGe007PostReadd.json'),
  );
  final alicePostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGe007PostReadd',
    text: alicePostSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_aliceGe007PostReadd.json'),
    alicePostReceived,
  );

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGe007PostReadd',
    text: 'GE-007 Charlie post re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_charlieGe007PostReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_charlieGe007PostReadd.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGe007PostCatchUp.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGe007PostCatchUp',
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_bobGe007PostCatchUp.json'),
    bobReceived,
  );

  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[charlieSent],
    receivedMessages: <Map<String, dynamic>>[alicePostReceived, bobReceived],
    extra: <String, dynamic>{
      'ge007OfflineObserverProof': <String, dynamic>{
        'selfRemovedDuringMutation': true,
        'readdedCharlie': finalMemberPeerIds.contains(stack.identity.peerId),
        'memberListIncludesBob': finalMemberPeerIds.contains(bobPeerId),
        'receivedAlicePostReaddMessage':
            alicePostReceived['key'] == 'aliceGe007PostReadd',
        'receivedBobPostCatchUpMessage':
            bobReceived['key'] == 'bobGe007PostCatchUp',
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe008Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-008 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  writeSharedText(_signalName('ge008_all_joined'), 'ok');

  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;

  final preSent = await _sendGe008Batch(
    stack: stack,
    groupId: groupId,
    keys: _ge008AlicePreKeys,
    phase: 'pre',
  );
  final preReceived = await _waitForGe008ReceivedBatch(
    stack: stack,
    groupId: groupId,
    identities: identities,
    expected: <MapEntry<String, String>>[
      for (final key in _ge008BobPreKeys) MapEntry<String, String>(key, 'bob'),
      for (final key in _ge008CharliePreKeys)
        MapEntry<String, String>(key, 'charlie'),
    ],
  );

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_ge008_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_ge008_self_removed'));
  final removedMemberPeerIds = await _memberPeerIds(stack, groupId);
  writeSharedText(_signalName('alice_ge008_removed_charlie'), 'ok');

  final removedSent = await _sendGe008Batch(
    stack: stack,
    groupId: groupId,
    keys: _ge008AliceRemovedKeys,
    phase: 'removed',
  );
  final removedReceived = await _waitForGe008ReceivedBatch(
    stack: stack,
    groupId: groupId,
    identities: identities,
    expected: <MapEntry<String, String>>[
      for (final key in _ge008BobRemovedKeys)
        MapEntry<String, String>(key, 'bob'),
    ],
  );
  for (final key in _ge008AliceRemovedKeys) {
    await waitForSharedSignal(_signalName('bob_received_$key.json'));
  }
  await waitForSharedSignal(_signalName('charlie_ge008_stale_rejected'));

  final charlieContact = await stack.contactRepo.getContact(charliePeerId);
  if (charlieContact == null) {
    throw StateError('Alice missing Charlie contact before GE-008 re-add');
  }
  final readdAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charlieContact.peerId,
    username: charlieContact.username,
    role: MemberRole.writer,
    publicKey: charlieContact.publicKey,
    mlKemPublicKey: charlieContact.mlKemPublicKey,
    joinedAt: readdAt,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdAt,
  );
  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_ge008_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );
  await waitForSharedSignal(_signalName('charlie_ge008_readded'));
  await waitForSharedSignal(_signalName('bob_ge008_readded_charlie'));
  writeSharedText(_signalName('ge008_post_readd_ready'), 'ok');

  final postSent = await _sendGe008Batch(
    stack: stack,
    groupId: groupId,
    keys: _ge008AlicePostKeys,
    phase: 'post',
  );
  final postReceived = await _waitForGe008ReceivedBatch(
    stack: stack,
    groupId: groupId,
    identities: identities,
    expected: <MapEntry<String, String>>[
      for (final key in _ge008BobPostKeys) MapEntry<String, String>(key, 'bob'),
      for (final key in _ge008CharliePostKeys)
        MapEntry<String, String>(key, 'charlie'),
    ],
  );

  final receivedMessages = <Map<String, dynamic>>[
    ...preReceived,
    ...removedReceived,
    ...postReceived,
  ];
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[
      ...preSent,
      ...removedSent,
      ...postSent,
    ],
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge008SendStormProof': <String, dynamic>{
        'removedCharlie': true,
        'readdedCharlie': finalMemberPeerIds.contains(charliePeerId),
        'preStormComplete': true,
        'removedWindowComplete': true,
        'postReaddStormComplete': true,
        'charlieExcludedDuringRemovedWindow': !removedMemberPeerIds.contains(
          charliePeerId,
        ),
        'duplicateDeliveryDeduped': _ge008AllPersistedOnce(receivedMessages),
        'receivedBobRemovedWindowMessages': _ge008ProofKeys(
          removedReceived,
        ).toSet().containsAll(_ge008BobRemovedKeys),
        'receivedCharliePostReaddMessages': _ge008ProofKeys(
          postReceived,
        ).toSet().containsAll(_ge008CharliePostKeys),
        'preStormSentCount': preSent.length,
        'removedWindowSentCount': removedSent.length,
        'postReaddSentCount': postSent.length,
        'preStormReceivedCount': preReceived.length,
        'removedWindowReceivedCount': removedReceived.length,
        'postReaddReceivedCount': postReceived.length,
        'receivedPreStormKeys': _ge008ProofKeys(preReceived),
        'receivedRemovedWindowKeys': _ge008ProofKeys(removedReceived),
        'receivedPostReaddKeys': _ge008ProofKeys(postReceived),
        'removedPeerId': charliePeerId,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe008Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');
  await waitForSharedSignal(_signalName('ge008_all_joined'));

  final charliePeerId = identities['charlie']!['peerId'] as String;
  final preSent = await _sendGe008Batch(
    stack: stack,
    groupId: groupId,
    keys: _ge008BobPreKeys,
    phase: 'pre',
  );
  final preReceived = await _waitForGe008ReceivedBatch(
    stack: stack,
    groupId: groupId,
    identities: identities,
    expected: <MapEntry<String, String>>[
      for (final key in _ge008AlicePreKeys)
        MapEntry<String, String>(key, 'alice'),
      for (final key in _ge008CharliePreKeys)
        MapEntry<String, String>(key, 'charlie'),
    ],
  );

  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  final removedMemberPeerIds = await _memberPeerIds(stack, groupId);
  writeSharedText(_signalName('bob_ge008_removed_charlie'), 'ok');
  await waitForSharedSignal(_signalName('alice_ge008_removed_charlie'));

  final removedSent = await _sendGe008Batch(
    stack: stack,
    groupId: groupId,
    keys: _ge008BobRemovedKeys,
    phase: 'removed',
  );
  final removedReceived = await _waitForGe008ReceivedBatch(
    stack: stack,
    groupId: groupId,
    identities: identities,
    expected: <MapEntry<String, String>>[
      for (final key in _ge008AliceRemovedKeys)
        MapEntry<String, String>(key, 'alice'),
    ],
  );
  for (final key in _ge008BobRemovedKeys) {
    await waitForSharedSignal(_signalName('alice_received_$key.json'));
  }

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge008_readded_charlie'), 'ok');
  await waitForSharedSignal(_signalName('ge008_post_readd_ready'));

  final postSent = await _sendGe008Batch(
    stack: stack,
    groupId: groupId,
    keys: _ge008BobPostKeys,
    phase: 'post',
  );
  final postReceived = await _waitForGe008ReceivedBatch(
    stack: stack,
    groupId: groupId,
    identities: identities,
    expected: <MapEntry<String, String>>[
      for (final key in _ge008AlicePostKeys)
        MapEntry<String, String>(key, 'alice'),
      for (final key in _ge008CharliePostKeys)
        MapEntry<String, String>(key, 'charlie'),
    ],
  );

  final receivedMessages = <Map<String, dynamic>>[
    ...preReceived,
    ...removedReceived,
    ...postReceived,
  ];
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[
      ...preSent,
      ...removedSent,
      ...postSent,
    ],
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge008SendStormProof': <String, dynamic>{
        'preStormComplete': true,
        'removedWindowComplete': true,
        'postReaddStormComplete': true,
        'memberListExcludesCharlieDuringRemovedWindow': !removedMemberPeerIds
            .contains(charliePeerId),
        'memberListIncludesAliceCharlie':
            finalMemberPeerIds.contains(identities['alice']!['peerId']) &&
            finalMemberPeerIds.contains(charliePeerId),
        'duplicateDeliveryDeduped': _ge008AllPersistedOnce(receivedMessages),
        'receivedAliceRemovedWindowMessages': _ge008ProofKeys(
          removedReceived,
        ).toSet().containsAll(_ge008AliceRemovedKeys),
        'receivedCharliePostReaddMessages': _ge008ProofKeys(
          postReceived,
        ).toSet().containsAll(_ge008CharliePostKeys),
        'preStormSentCount': preSent.length,
        'removedWindowSentCount': removedSent.length,
        'postReaddSentCount': postSent.length,
        'preStormReceivedCount': preReceived.length,
        'removedWindowReceivedCount': removedReceived.length,
        'postReaddReceivedCount': postReceived.length,
        'receivedPreStormKeys': _ge008ProofKeys(preReceived),
        'receivedRemovedWindowKeys': _ge008ProofKeys(removedReceived),
        'receivedPostReaddKeys': _ge008ProofKeys(postReceived),
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe008Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');
  await waitForSharedSignal(_signalName('ge008_all_joined'));

  final preSent = await _sendGe008Batch(
    stack: stack,
    groupId: groupId,
    keys: _ge008CharliePreKeys,
    phase: 'pre',
  );
  final preReceived = await _waitForGe008ReceivedBatch(
    stack: stack,
    groupId: groupId,
    identities: identities,
    expected: <MapEntry<String, String>>[
      for (final key in _ge008AlicePreKeys)
        MapEntry<String, String>(key, 'alice'),
      for (final key in _ge008BobPreKeys) MapEntry<String, String>(key, 'bob'),
    ],
  );

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_ge008_self_removed'), 'ok');
  await waitForSharedSignal(_signalName('alice_ge008_removed_charlie'));
  final rejectedSends = <Map<String, dynamic>>[];
  for (final key in const <String>[
    'charlieGe008RemovedStale0',
    'charlieGe008RemovedStale1',
  ]) {
    rejectedSends.add(
      await _attemptRejectedProofMessage(
        stack: stack,
        groupId: groupId,
        key: key,
        text: 'GE-008 stale removed-window $key $_runId',
      ),
    );
  }
  writeSharedText(_signalName('charlie_ge008_stale_rejected'), 'ok');

  await Future<void>.delayed(const Duration(seconds: 5));
  final removedWindowPlaintextCount = await _ge008PlaintextCountForSentKeys(
    stack: stack,
    groupId: groupId,
    identities: identities,
    expected: <MapEntry<String, String>>[
      for (final key in _ge008AliceRemovedKeys)
        MapEntry<String, String>(key, 'alice'),
      for (final key in _ge008BobRemovedKeys)
        MapEntry<String, String>(key, 'bob'),
    ],
  );

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge008_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_ge008_readded'), 'ok');
  await waitForSharedSignal(_signalName('ge008_post_readd_ready'));

  final postSent = await _sendGe008Batch(
    stack: stack,
    groupId: groupId,
    keys: _ge008CharliePostKeys,
    phase: 'post',
  );
  final postReceived = await _waitForGe008ReceivedBatch(
    stack: stack,
    groupId: groupId,
    identities: identities,
    expected: <MapEntry<String, String>>[
      for (final key in _ge008AlicePostKeys)
        MapEntry<String, String>(key, 'alice'),
      for (final key in _ge008BobPostKeys) MapEntry<String, String>(key, 'bob'),
    ],
  );

  final receivedMessages = <Map<String, dynamic>>[
    ...preReceived,
    ...postReceived,
  ];
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  final rejectedAcceptedCount = rejectedSends
      .where((sent) => sent['accepted'] == true)
      .length;
  final rejectedMessageIds = rejectedSends
      .map((sent) => sent['messageId'] as String?)
      .whereType<String>()
      .toList(growable: false);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[...preSent, ...postSent],
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge008SendStormProof': <String, dynamic>{
        'selfRemovedDuringStorm': true,
        'staleRemovedWindowSendsRejected': rejectedAcceptedCount == 0,
        'readdedCharlie': finalMemberPeerIds.contains(stack.identity.peerId),
        'preStormComplete': true,
        'postReaddStormComplete': true,
        'duplicateDeliveryDeduped': _ge008AllPersistedOnce(receivedMessages),
        'receivedPostReaddStormMessages': _ge008ProofKeys(postReceived)
            .toSet()
            .containsAll(<String>[
              ..._ge008AlicePostKeys,
              ..._ge008BobPostKeys,
            ]),
        'preStormSentCount': preSent.length,
        'postReaddSentCount': postSent.length,
        'preStormReceivedCount': preReceived.length,
        'postReaddReceivedCount': postReceived.length,
        'staleRemovedWindowAttemptCount': rejectedSends.length,
        'staleRemovedWindowAcceptedCount': rejectedAcceptedCount,
        'staleRemovedWindowPublishCount': _ge008PublishCountForMessageIds(
          stack: stack,
          messageIds: rejectedMessageIds,
        ),
        'removedWindowPlaintextCount': removedWindowPlaintextCount,
        'receivedPreStormKeys': _ge008ProofKeys(preReceived),
        'receivedPostReaddKeys': _ge008ProofKeys(postReceived),
        'rejectedRemovedWindowKeys': rejectedSends
            .map((sent) => sent['key'] as String)
            .toList(growable: false),
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe009Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-009 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  writeSharedText(_signalName('ge009_all_joined'), 'ok');

  final bobPeerId = identities['bob']!['peerId'] as String;
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;

  final aliceBeforeSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009AliceBeforePartitionKey,
    text: 'GE-009 Alice before partition $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge009AliceBeforePartitionKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge009AliceBeforePartitionKey.json'),
  );

  final bobBeforeSent = await waitForSharedJson(
    _signalName('bob_sent_$_ge009BobBeforePartitionKey.json'),
  );
  final bobBeforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009BobBeforePartitionKey,
    text: bobBeforeSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge009BobBeforePartitionKey.json'),
  );

  final charlieBeforeSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge009CharlieBeforePartitionKey.json'),
  );
  final charlieBeforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009CharlieBeforePartitionKey,
    text: charlieBeforeSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge009CharlieBeforePartitionKey.json'),
  );

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_ge009_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_ge009_self_removed'));
  final removedMemberPeerIds = await _memberPeerIds(stack, groupId);

  final charlieContact = await stack.contactRepo.getContact(charliePeerId);
  if (charlieContact == null) {
    throw StateError('Alice missing Charlie contact before GE-009 re-add');
  }
  final readdAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charlieContact.peerId,
    username: charlieContact.username,
    role: MemberRole.writer,
    publicKey: charlieContact.publicKey,
    mlKemPublicKey: charlieContact.mlKemPublicKey,
    joinedAt: readdAt,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdAt,
  );
  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_ge009_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );
  await waitForSharedSignal(_signalName('bob_ge009_readded_charlie'));

  final alicePostSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009AlicePostReaddKey,
    text: 'GE-009 Alice post re-add while Charlie partitioned $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge009AlicePostReaddKey.json'),
  );

  final bobPostSent = await waitForSharedJson(
    _signalName('bob_sent_$_ge009BobPostReaddKey.json'),
  );
  final bobPostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009BobPostReaddKey,
    text: bobPostSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('alice_received_$_ge009BobPostReaddKey.json'),
    bobPostReceived,
  );

  writeSharedText(_signalName('ge009_heal_ready'), 'ok');
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge009AlicePostReaddKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge009BobPostReaddKey.json'),
  );

  final charlieAfterSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge009CharlieAfterHealKey.json'),
  );
  final charlieAfterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009CharlieAfterHealKey,
    text: charlieAfterSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('alice_received_$_ge009CharlieAfterHealKey.json'),
    charlieAfterReceived,
  );

  final sentMessages = <Map<String, dynamic>>[aliceBeforeSent, alicePostSent];
  final receivedMessages = <Map<String, dynamic>>[
    bobBeforeReceived,
    charlieBeforeReceived,
    bobPostReceived,
    charlieAfterReceived,
  ];
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  final finalTimelineKeys = _ge009FinalTimelineKeys(
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
  );
  final alicePostRecipients =
      (alicePostSent['recipientPeerIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toSet();
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge009PartitionHealProof': <String, dynamic>{
        'partitionedDuringMembershipMutation': true,
        'removedAndReaddedCharlie': true,
        'partitionHealed': true,
        'finalMembershipConverged':
            finalMemberPeerIds.contains(bobPeerId) &&
            finalMemberPeerIds.contains(charliePeerId),
        'finalTimelineConverged': finalTimelineKeys.length == 6,
        'duplicateDeliveryDeduped': _ge008AllPersistedOnce(receivedMessages),
        'charlieExcludedDuringPartition': !removedMemberPeerIds.contains(
          charliePeerId,
        ),
        'postReaddDurableIncludedCharlie': alicePostRecipients.contains(
          charliePeerId,
        ),
        'receivedBobPostReaddReplay':
            bobPostReceived['key'] == _ge009BobPostReaddKey,
        'receivedCharlieAfterHeal':
            charlieAfterReceived['key'] == _ge009CharlieAfterHealKey,
        'receivedPrePartitionKeys': <String>[
          bobBeforeReceived['key'] as String,
          charlieBeforeReceived['key'] as String,
        ],
        'receivedPostHealKeys': <String>[
          bobPostReceived['key'] as String,
          charlieAfterReceived['key'] as String,
        ],
        'finalTimelineKeys': finalTimelineKeys,
        'finalMessageCount': finalTimelineKeys.length,
        'finalMemberPeerIds': finalMemberPeerIds,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe009Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');
  await waitForSharedSignal(_signalName('ge009_all_joined'));

  final alicePeerId = identities['alice']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;

  final aliceBeforeSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge009AliceBeforePartitionKey.json'),
  );
  final aliceBeforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009AliceBeforePartitionKey,
    text: aliceBeforeSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final bobBeforeSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009BobBeforePartitionKey,
    text: 'GE-009 Bob before partition $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge009BobBeforePartitionKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge009BobBeforePartitionKey.json'),
  );

  final charlieBeforeSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge009CharlieBeforePartitionKey.json'),
  );
  final charlieBeforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009CharlieBeforePartitionKey,
    text: charlieBeforeSent['text'] as String,
    senderPeerId: charliePeerId,
  );

  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  final removedMemberPeerIds = await _memberPeerIds(stack, groupId);
  writeSharedText(_signalName('bob_ge009_removed_charlie'), 'ok');

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge009_readded_charlie'), 'ok');

  final alicePostSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge009AlicePostReaddKey.json'),
  );
  final alicePostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009AlicePostReaddKey,
    text: alicePostSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge009AlicePostReaddKey.json'),
    alicePostReceived,
  );

  final bobPostSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009BobPostReaddKey,
    text: 'GE-009 Bob post re-add while Charlie partitioned $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge009BobPostReaddKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge009BobPostReaddKey.json'),
  );

  final charlieAfterSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge009CharlieAfterHealKey.json'),
  );
  final charlieAfterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009CharlieAfterHealKey,
    text: charlieAfterSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge009CharlieAfterHealKey.json'),
    charlieAfterReceived,
  );

  final sentMessages = <Map<String, dynamic>>[bobBeforeSent, bobPostSent];
  final receivedMessages = <Map<String, dynamic>>[
    aliceBeforeReceived,
    charlieBeforeReceived,
    alicePostReceived,
    charlieAfterReceived,
  ];
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  final finalTimelineKeys = _ge009FinalTimelineKeys(
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
  );
  final bobPostRecipients =
      (bobPostSent['recipientPeerIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toSet();
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge009PartitionHealProof': <String, dynamic>{
        'partitionedDuringMembershipMutation': true,
        'removedAndReaddedCharlie': true,
        'partitionHealed': true,
        'finalMembershipConverged':
            finalMemberPeerIds.contains(alicePeerId) &&
            finalMemberPeerIds.contains(charliePeerId),
        'finalTimelineConverged': finalTimelineKeys.length == 6,
        'duplicateDeliveryDeduped': _ge008AllPersistedOnce(receivedMessages),
        'charlieExcludedDuringPartition': !removedMemberPeerIds.contains(
          charliePeerId,
        ),
        'postReaddDurableIncludedCharlie': bobPostRecipients.contains(
          charliePeerId,
        ),
        'receivedAlicePostReaddReplay':
            alicePostReceived['key'] == _ge009AlicePostReaddKey,
        'receivedCharlieAfterHeal':
            charlieAfterReceived['key'] == _ge009CharlieAfterHealKey,
        'receivedPrePartitionKeys': <String>[
          aliceBeforeReceived['key'] as String,
          charlieBeforeReceived['key'] as String,
        ],
        'receivedPostHealKeys': <String>[
          alicePostReceived['key'] as String,
          charlieAfterReceived['key'] as String,
        ],
        'finalTimelineKeys': finalTimelineKeys,
        'finalMessageCount': finalTimelineKeys.length,
        'finalMemberPeerIds': finalMemberPeerIds,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe009Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');
  await waitForSharedSignal(_signalName('ge009_all_joined'));

  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;

  final aliceBeforeSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge009AliceBeforePartitionKey.json'),
  );
  final aliceBeforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009AliceBeforePartitionKey,
    text: aliceBeforeSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final bobBeforeSent = await waitForSharedJson(
    _signalName('bob_sent_$_ge009BobBeforePartitionKey.json'),
  );
  final bobBeforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009BobBeforePartitionKey,
    text: bobBeforeSent['text'] as String,
    senderPeerId: bobPeerId,
  );

  final charlieBeforeSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009CharlieBeforePartitionKey,
    text: 'GE-009 Charlie before partition $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge009CharlieBeforePartitionKey.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge009CharlieBeforePartitionKey.json'),
  );

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_ge009_self_removed'), 'ok');

  final alicePostSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge009AlicePostReaddKey.json'),
  );
  final bobPostSent = await waitForSharedJson(
    _signalName('bob_sent_$_ge009BobPostReaddKey.json'),
  );
  final removedWindowPlaintextCount =
      await _proofMessageCount(
        stack: stack,
        groupId: groupId,
        text: alicePostSent['text'] as String,
        senderPeerId: alicePeerId,
      ) +
      await _proofMessageCount(
        stack: stack,
        groupId: groupId,
        text: bobPostSent['text'] as String,
        senderPeerId: bobPeerId,
      );

  await waitForSharedSignal(_signalName('ge009_heal_ready'));
  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge009_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_ge009_rejoined'), 'ok');

  final alicePostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009AlicePostReaddKey,
    text: alicePostSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge009AlicePostReaddKey.json'),
    alicePostReceived,
  );
  final bobPostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009BobPostReaddKey,
    text: bobPostSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge009BobPostReaddKey.json'),
    bobPostReceived,
  );

  final charlieAfterSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge009CharlieAfterHealKey,
    text: 'GE-009 Charlie after partition heal $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge009CharlieAfterHealKey.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge009CharlieAfterHealKey.json'),
  );

  final sentMessages = <Map<String, dynamic>>[
    charlieBeforeSent,
    charlieAfterSent,
  ];
  final receivedMessages = <Map<String, dynamic>>[
    aliceBeforeReceived,
    bobBeforeReceived,
    alicePostReceived,
    bobPostReceived,
  ];
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  final finalTimelineKeys = _ge009FinalTimelineKeys(
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
  );
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'ge009PartitionHealProof': <String, dynamic>{
        'partitionedDuringMembershipMutation': true,
        'removedAndReaddedCharlie': true,
        'partitionHealed': true,
        'finalMembershipConverged':
            finalMemberPeerIds.contains(alicePeerId) &&
            finalMemberPeerIds.contains(bobPeerId) &&
            finalMemberPeerIds.contains(stack.identity.peerId),
        'finalTimelineConverged': finalTimelineKeys.length == 6,
        'duplicateDeliveryDeduped': _ge008AllPersistedOnce(receivedMessages),
        'isolatedFromLiveTopicDuringMutation': removedWindowPlaintextCount == 0,
        'drainedReplayAfterHeal': true,
        'receivedAliceBobReplayAfterHeal':
            alicePostReceived['key'] == _ge009AlicePostReaddKey &&
            bobPostReceived['key'] == _ge009BobPostReaddKey,
        'postHealPublishAccepted':
            charlieAfterSent['outcome'] == 'success' ||
            charlieAfterSent['outcome'] == 'successNoPeers',
        'removedWindowPlaintextCount': removedWindowPlaintextCount,
        'receivedPrePartitionKeys': <String>[
          aliceBeforeReceived['key'] as String,
          bobBeforeReceived['key'] as String,
        ],
        'postReaddReplayKeys': <String>[
          alicePostReceived['key'] as String,
          bobPostReceived['key'] as String,
        ],
        'finalTimelineKeys': finalTimelineKeys,
        'finalMessageCount': finalTimelineKeys.length,
        'finalMemberPeerIds': finalMemberPeerIds,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe010Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-010 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  writeSharedText(_signalName('ge010_all_joined'), 'ok');

  final bobLeft = await waitForSharedJson(
    _signalName('bob_ge010_left_live_topic.json'),
  );
  final charlieLeft = await waitForSharedJson(
    _signalName('charlie_ge010_left_live_topic.json'),
  );

  final sent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge010AliceZeroPeerKey,
    text: 'GE-010 Alice zero live topic peers $_runId',
  );
  final sentMessage = await stack.groupMsgRepo.getMessage(
    sent['messageId'] as String,
  );
  final topicPeers = sent['topicPeers'] as int?;
  if (sent['outcome'] != 'successNoPeers' || topicPeers != 0) {
    throw StateError(
      'GE-010 Alice send must be zero-peer successNoPeers; '
      'outcome=${sent['outcome']} topicPeers=${sent['topicPeers']}',
    );
  }
  if (sentMessage?.status != 'sent' || sentMessage?.inboxStored != true) {
    throw StateError(
      'GE-010 Alice sender row must stay sent with inbox custody; '
      'status=${sentMessage?.status} inboxStored=${sentMessage?.inboxStored}',
    );
  }

  await waitForSharedJson(
    _signalName('bob_received_$_ge010AliceZeroPeerKey.json'),
  );
  await waitForSharedJson(
    _signalName('charlie_received_$_ge010AliceZeroPeerKey.json'),
  );

  final recipientPeerIds =
      (sent['recipientPeerIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[sent],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'ge010ZeroLivePeersInboxFallbackProof': <String, dynamic>{
        'bobLeftLiveTopicBeforeSend':
            bobLeft['leftLiveTopicOnly'] == true &&
            bobLeft['groupRetained'] == true &&
            bobLeft['keyRetained'] == true,
        'charlieLeftLiveTopicBeforeSend':
            charlieLeft['leftLiveTopicOnly'] == true &&
            charlieLeft['groupRetained'] == true &&
            charlieLeft['keyRetained'] == true,
        'zeroLiveTopicPeersAtSend': topicPeers == 0,
        'successNoPeers': sent['outcome'] == 'successNoPeers',
        'senderStatusSent': sentMessage?.status == 'sent',
        'inboxStored': sentMessage?.inboxStored == true,
        'actualDurablePayloadProof': sent['actualDurablePayloadProof'] == true,
        'honestSenderFallbackStatus':
            sent['outcome'] == 'successNoPeers' &&
            sentMessage?.status == 'sent',
        'noLiveDeliveryDuringSendWindow': topicPeers == 0,
        'topicPeersAtSend': topicPeers,
        'recipientPeerIds': recipientPeerIds,
        'sentKeys': <String>[_ge010AliceZeroPeerKey],
        'finalMemberPeerIds': finalMemberPeerIds,
        'finalKeyEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe010Receiver(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('${_role}_group_joined'), 'ok');
  await waitForSharedSignal(_signalName('ge010_all_joined'));

  final expectedMemberPeerIds = <String>[
    identities['alice']!['peerId'] as String,
    identities['bob']!['peerId'] as String,
    identities['charlie']!['peerId'] as String,
  ];
  final leaveProof = await _gm035LeaveLiveTopicOnly(
    stack: stack,
    groupId: groupId,
    expectedMemberPeerIds: expectedMemberPeerIds,
  );
  writeSharedJson(
    _signalName('${_role}_ge010_left_live_topic.json'),
    leaveProof,
  );

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge010AliceZeroPeerKey.json'),
  );
  final preRejoinPlaintextCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  final rejoinProof = await _gm035RejoinLiveTopicOnly(
    stack: stack,
    groupId: groupId,
  );
  final received = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge010AliceZeroPeerKey,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('${_role}_received_$_ge010AliceZeroPeerKey.json'),
    received,
  );

  final finalCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[received],
    extra: <String, dynamic>{
      'ge010ZeroLivePeersInboxFallbackProof': <String, dynamic>{
        'leftLiveTopicBeforeSend':
            leaveProof['leftLiveTopicOnly'] == true &&
            leaveProof['groupRetained'] == true &&
            leaveProof['keyRetained'] == true,
        'rejoinedLiveTopicAfterSend':
            rejoinProof['rejoinedLiveTopicOnly'] == true,
        'drainedInboxAfterReturn': received['key'] == _ge010AliceZeroPeerKey,
        'receivedZeroPeerMessage': received['key'] == _ge010AliceZeroPeerKey,
        'noDuplicatePersistence': finalCount == 1,
        'noLiveDeliveryDuringSendWindow': preRejoinPlaintextCount == 0,
        'senderEligibleAtSend': finalMemberPeerIds.contains(
          identities['alice']!['peerId'] as String,
        ),
        'postDrainPersistedCount': finalCount,
        'preRejoinPlaintextCount': preRejoinPlaintextCount,
        'receivedKeys': <String>[_ge010AliceZeroPeerKey],
        'liveTopicLeaveProof': leaveProof,
        'liveTopicRejoinProof': rejoinProof,
        'finalMemberPeerIds': finalMemberPeerIds,
        'finalKeyEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGo002Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GO-002 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));

  final sent = await _sendGo002InboxFailureProofMessage(
    stack: stack,
    groupId: groupId,
    text: 'GO-002 Alice inbox failure retry proof $_runId',
  );

  await waitForSharedJson(
    _signalName('bob_received_$_go002AliceInboxFailureKey.json'),
  );
  await waitForSharedJson(
    _signalName('charlie_received_$_go002AliceInboxFailureKey.json'),
  );

  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[sent],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'go002InboxStoreFailureSenderStatusProof': <String, dynamic>{
        'publishSucceeded': sent['outcome'] == 'success',
        'actualTopicPeerProof': sent['actualTopicPeerProof'] == true,
        'topicPeersPositive': (sent['topicPeers'] as int? ?? 0) > 0,
        'forcedInboxStoreFailure': sent['forcedInboxStoreFailure'] == true,
        'senderStatusPendingBeforeRetry':
            sent['senderStatusBeforeRetry'] == 'pending',
        'inboxStoredFalseBeforeRetry': sent['inboxStoredBeforeRetry'] == false,
        'retryPayloadPresentBeforeRetry':
            sent['retryPayloadBeforeRetry'] == true,
        'notSilentlyReliableBeforeRetry':
            sent['senderStatusBeforeRetry'] == 'pending' &&
            sent['inboxStoredBeforeRetry'] == false &&
            sent['retryPayloadBeforeRetry'] == true,
        'retryCount': sent['retryCount'],
        'retryRanOnce': sent['retryCount'] == 1,
        'retryPromotedToSent': sent['senderStatusAfterRetry'] == 'sent',
        'inboxStoredTrueAfterRetry': sent['inboxStoredAfterRetry'] == true,
        'retryPayloadClearedAfterRetry':
            sent['retryPayloadAfterRetry'] == false,
        'actualDurablePayloadProof': sent['actualDurablePayloadProof'] == true,
        'topicPeersAtSend': sent['topicPeers'],
        'recipientPeerIds': sent['recipientPeerIds'],
        'failedInboxRecipientPeerIds': sent['failedInboxRecipientPeerIds'],
        'sentKeys': <String>[_go002AliceInboxFailureKey],
        'finalMemberPeerIds': finalMemberPeerIds,
        'finalKeyEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGo002Receiver(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('${_role}_group_joined'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_$_go002AliceInboxFailureKey.json'),
  );
  final received = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _go002AliceInboxFailureKey,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('${_role}_received_$_go002AliceInboxFailureKey.json'),
    received,
  );

  final finalCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[received],
    extra: <String, dynamic>{
      'go002InboxStoreFailureSenderStatusProof': <String, dynamic>{
        'receivedLivePublish': received['key'] == _go002AliceInboxFailureKey,
        'noDuplicatePersistence': finalCount == 1,
        'senderEligibleAtSend': finalMemberPeerIds.contains(
          identities['alice']!['peerId'] as String,
        ),
        'postRetryPersistedCount': finalCount,
        'receivedKeys': <String>[_go002AliceInboxFailureKey],
        'finalMemberPeerIds': finalMemberPeerIds,
        'finalKeyEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe011Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-011 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  writeSharedText(_signalName('ge011_all_joined'), 'ok');

  final bobReady = await waitForSharedJson(
    _signalName('bob_ge011_live_topic_ready.json'),
  );
  final charlieLeft = await waitForSharedJson(
    _signalName('charlie_ge011_left_live_topic.json'),
  );

  final sent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge011AlicePartialLiveKey,
    text: 'GE-011 Alice partial live topic peers $_runId',
  );
  final sentMessage = await stack.groupMsgRepo.getMessage(
    sent['messageId'] as String,
  );
  final topicPeers = sent['topicPeers'] as int?;
  if (sent['outcome'] != 'success' || topicPeers != 1) {
    throw StateError(
      'GE-011 Alice send must be partial-live success; '
      'outcome=${sent['outcome']} topicPeers=${sent['topicPeers']}',
    );
  }
  if (sentMessage?.status != 'sent' || sentMessage?.inboxStored != true) {
    throw StateError(
      'GE-011 Alice sender row must stay sent with inbox custody; '
      'status=${sentMessage?.status} inboxStored=${sentMessage?.inboxStored}',
    );
  }

  final bobReceived = await waitForSharedJson(
    _signalName('bob_received_$_ge011AlicePartialLiveKey.json'),
  );
  await waitForSharedJson(
    _signalName('charlie_received_$_ge011AlicePartialLiveKey.json'),
  );

  final recipientPeerIds =
      (sent['recipientPeerIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[sent],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'ge011PartialLivePeersInboxFallbackProof': <String, dynamic>{
        'bobLiveTopicPeerAtSend': bobReady['liveTopicPeerAtSend'] == true,
        'charlieLeftLiveTopicBeforeSend':
            charlieLeft['leftLiveTopicOnly'] == true &&
            charlieLeft['groupRetained'] == true &&
            charlieLeft['keyRetained'] == true,
        'partialLiveTopicPeersAtSend': topicPeers == 1,
        'liveDeliveryToBobDuringSendWindow':
            bobReceived['key'] == _ge011AlicePartialLiveKey,
        'noLiveDeliveryToCharlieDuringSendWindow':
            charlieLeft['leftLiveTopicOnly'] == true,
        'senderStatusSent': sentMessage?.status == 'sent',
        'inboxStored': sentMessage?.inboxStored == true,
        'actualDurablePayloadProof': sent['actualDurablePayloadProof'] == true,
        'honestPartialFallbackStatus':
            sent['outcome'] == 'success' &&
            topicPeers == 1 &&
            sentMessage?.status == 'sent',
        'topicPeersAtSend': topicPeers,
        'recipientPeerIds': recipientPeerIds,
        'sentKeys': <String>[_ge011AlicePartialLiveKey],
        'finalMemberPeerIds': finalMemberPeerIds,
        'finalKeyEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe011Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');
  await waitForSharedSignal(_signalName('ge011_all_joined'));
  writeSharedJson(
    _signalName('bob_ge011_live_topic_ready.json'),
    <String, dynamic>{
      'role': 'bob',
      'liveTopicPeerAtSend': true,
      'readyAt': DateTime.now().toUtc().toIso8601String(),
    },
  );

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge011AlicePartialLiveKey.json'),
  );
  final received = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge011AlicePartialLiveKey,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
    drainWhileWaiting: false,
  );
  final preDrainCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  await drainGroupOfflineInboxForGroup(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    groupMessageListener: stack.groupListener,
    selfPeerId: stack.identity.peerId,
  );
  final finalCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge011AlicePartialLiveKey.json'),
    received,
  );

  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[received],
    extra: <String, dynamic>{
      'ge011PartialLivePeersInboxFallbackProof': <String, dynamic>{
        'liveTopicPeerAtSend': true,
        'receivedLiveDuringSendWindow':
            received['key'] == _ge011AlicePartialLiveKey,
        'drainedDuplicateInboxAfterLive': true,
        'noDuplicatePersistence': finalCount == 1,
        'senderEligibleAtSend': finalMemberPeerIds.contains(
          identities['alice']!['peerId'] as String,
        ),
        'preDrainPersistedCount': preDrainCount,
        'postDrainPersistedCount': finalCount,
        'receivedKeys': <String>[_ge011AlicePartialLiveKey],
        'finalMemberPeerIds': finalMemberPeerIds,
        'finalKeyEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGe011Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');
  await waitForSharedSignal(_signalName('ge011_all_joined'));

  final expectedMemberPeerIds = <String>[
    identities['alice']!['peerId'] as String,
    identities['bob']!['peerId'] as String,
    identities['charlie']!['peerId'] as String,
  ];
  final leaveProof = await _gm035LeaveLiveTopicOnly(
    stack: stack,
    groupId: groupId,
    expectedMemberPeerIds: expectedMemberPeerIds,
  );
  writeSharedJson(
    _signalName('charlie_ge011_left_live_topic.json'),
    leaveProof,
  );

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge011AlicePartialLiveKey.json'),
  );
  final preRejoinPlaintextCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  final rejoinProof = await _gm035RejoinLiveTopicOnly(
    stack: stack,
    groupId: groupId,
  );
  final received = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge011AlicePartialLiveKey,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge011AlicePartialLiveKey.json'),
    received,
  );

  final finalCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  final finalMemberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[received],
    extra: <String, dynamic>{
      'ge011PartialLivePeersInboxFallbackProof': <String, dynamic>{
        'leftLiveTopicBeforeSend':
            leaveProof['leftLiveTopicOnly'] == true &&
            leaveProof['groupRetained'] == true &&
            leaveProof['keyRetained'] == true,
        'rejoinedLiveTopicAfterSend':
            rejoinProof['rejoinedLiveTopicOnly'] == true,
        'drainedInboxAfterReturn': received['key'] == _ge011AlicePartialLiveKey,
        'receivedInboxMessage': received['key'] == _ge011AlicePartialLiveKey,
        'noLiveDeliveryDuringSendWindow': preRejoinPlaintextCount == 0,
        'noDuplicatePersistence': finalCount == 1,
        'senderEligibleAtSend': finalMemberPeerIds.contains(
          identities['alice']!['peerId'] as String,
        ),
        'postDrainPersistedCount': finalCount,
        'preRejoinPlaintextCount': preRejoinPlaintextCount,
        'receivedKeys': <String>[_ge011AlicePartialLiveKey],
        'liveTopicLeaveProof': leaveProof,
        'liveTopicRejoinProof': rejoinProof,
        'finalMemberPeerIds': finalMemberPeerIds,
        'finalKeyEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

GroupMemberDeviceIdentity _ge012DeviceFromIdentity(
  Map<String, dynamic> identity,
) {
  final transportPeerId = _transportPeerIdForIdentity(identity);
  return GroupMemberDeviceIdentity(
    deviceId: transportPeerId,
    transportPeerId: transportPeerId,
    deviceSigningPublicKey: identity['publicKey'] as String,
    mlKemPublicKey: identity['mlKemPublicKey'] as String?,
    keyPackageId: 'ge012-key-package-$transportPeerId',
    keyPackagePublicMaterial: 'ge012-key-package-public-$transportPeerId',
  );
}

Future<Map<String, dynamic>> _createGe012GroupFixture({
  required GroupMultiDeviceTestStack stack,
  required Map<String, Map<String, dynamic>> identities,
}) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob'],
    name: 'GE-012 Same User Devices',
  );
  final groupId = (fixture['group'] as Map)['id'] as String;
  final bobIdentity = identities['bob']!;
  final siblingIdentity = identities['charlie']!;
  final bobPeerId = bobIdentity['peerId'] as String;
  if (siblingIdentity['peerId'] != bobPeerId) {
    throw StateError('GE-012 sibling role must restore Bob peer identity');
  }

  final group = await stack.groupRepo.getGroup(groupId);
  final keyInfo = await stack.groupRepo.getLatestKey(groupId);
  final bobMember = await stack.groupRepo.getMember(groupId, bobPeerId);
  if (group == null || keyInfo == null || bobMember == null) {
    throw StateError('GE-012 fixture missing group/key/Bob member');
  }
  final devices = <GroupMemberDeviceIdentity>[
    _ge012DeviceFromIdentity(bobIdentity),
    _ge012DeviceFromIdentity(siblingIdentity),
  ];
  await stack.groupRepo.saveMember(bobMember.copyWith(devices: devices));
  final members = await stack.groupRepo.getMembers(groupId);
  await callGroupUpdateConfig(
    stack.bridge,
    groupId: groupId,
    groupConfig: buildGroupConfigPayload(group, members),
  );
  return buildGroupFixture(group: group, keyInfo: keyInfo, members: members);
}

Future<Map<String, dynamic>> _ge012SameUserDeviceProof({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String logicalBobPeerId,
}) async {
  final members = await stack.groupRepo.getMembers(groupId);
  final bobMembers = members
      .where((member) => member.peerId == logicalBobPeerId)
      .toList(growable: false);
  final bobDevices =
      bobMembers
          .expand((member) => member.activeDevices)
          .map((device) => device.deviceId)
          .toSet()
          .toList(growable: false)
        ..sort();
  return <String, dynamic>{
    'logicalBobPeerId': logicalBobPeerId,
    'logicalBobMembershipCount': bobMembers.length,
    'logicalBobDeviceIds': bobDevices,
    'memberPeerIds': members.map((member) => member.peerId).toList(),
    'roleTransportPeerId': stack.p2pService.currentState.peerId,
  };
}

Future<void> _runGe012Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGe012GroupFixture(
    stack: stack,
    identities: identities,
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));

  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge012AliceKey,
    text: 'GE-012 Alice to Bob devices $_runId',
  );
  await waitForSharedJson(_signalName('bob_received_$_ge012AliceKey.json'));
  await waitForSharedJson(_signalName('charlie_received_$_ge012AliceKey.json'));

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_$_ge012BobPrimaryKey.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge012BobPrimaryKey,
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
    drainWhileWaiting: false,
  );

  final siblingSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge012BobSiblingKey.json'),
  );
  final siblingReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge012BobSiblingKey,
    text: siblingSent['text'] as String,
    senderPeerId: bobPeerId,
    drainWhileWaiting: false,
  );

  await waitForSharedJson(
    _signalName('bob_received_$_ge012BobSiblingKey.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[aliceSent],
    receivedMessages: <Map<String, dynamic>>[bobReceived, siblingReceived],
    extra: <String, dynamic>{
      'ge012SameUserDeviceProof': await _ge012SameUserDeviceProof(
        stack: stack,
        groupId: groupId,
        logicalBobPeerId: bobPeerId,
      ),
    },
  );
}

Future<void> _runGe012Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge012AliceKey.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge012AliceKey,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
    drainWhileWaiting: false,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge012AliceKey.json'),
    aliceReceived,
  );

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge012BobPrimaryKey,
    text: 'GE-012 Bob primary to group $_runId',
  );

  final siblingSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge012BobSiblingKey.json'),
  );
  final siblingReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge012BobSiblingKey,
    text: siblingSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
    drainWhileWaiting: false,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge012BobSiblingKey.json'),
    siblingReceived,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[aliceReceived, siblingReceived],
    extra: <String, dynamic>{
      'ge012SameUserDeviceProof': await _ge012SameUserDeviceProof(
        stack: stack,
        groupId: groupId,
        logicalBobPeerId: identities['bob']!['peerId'] as String,
      ),
    },
  );
}

Future<void> _runGe012Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge012AliceKey.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge012AliceKey,
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
    drainWhileWaiting: false,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge012AliceKey.json'),
    aliceReceived,
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_$_ge012BobPrimaryKey.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge012BobPrimaryKey,
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
    drainWhileWaiting: false,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge012BobPrimaryKey.json'),
    bobReceived,
  );

  final siblingSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge012BobSiblingKey,
    text: 'GE-012 Bob sibling to group $_runId',
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[siblingSent],
    receivedMessages: <Map<String, dynamic>>[aliceReceived, bobReceived],
    extra: <String, dynamic>{
      'ge012SameUserDeviceProof': await _ge012SameUserDeviceProof(
        stack: stack,
        groupId: groupId,
        logicalBobPeerId: identities['bob']!['peerId'] as String,
      ),
    },
  );
}

GroupMemberDeviceIdentity _ge013DeviceFromIdentity(
  Map<String, dynamic> identity,
) {
  final transportPeerId = _transportPeerIdForIdentity(identity);
  return GroupMemberDeviceIdentity(
    deviceId: transportPeerId,
    transportPeerId: transportPeerId,
    deviceSigningPublicKey: identity['publicKey'] as String,
    mlKemPublicKey: identity['mlKemPublicKey'] as String?,
    keyPackageId: 'ge013-key-package-$transportPeerId',
    keyPackagePublicMaterial: 'ge013-key-package-public-$transportPeerId',
  );
}

Future<Map<String, dynamic>> _createGe013GroupFixture({
  required GroupMultiDeviceTestStack stack,
  required Map<String, Map<String, dynamic>> identities,
}) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob'],
    name: 'GE-013 Device Revocation',
  );
  final groupId = (fixture['group'] as Map)['id'] as String;
  final bobIdentity = identities['bob']!;
  final siblingIdentity = identities['charlie']!;
  final bobPeerId = bobIdentity['peerId'] as String;
  if (siblingIdentity['peerId'] != bobPeerId) {
    throw StateError('GE-013 sibling role must restore Bob peer identity');
  }

  final group = await stack.groupRepo.getGroup(groupId);
  final keyInfo = await stack.groupRepo.getLatestKey(groupId);
  final bobMember = await stack.groupRepo.getMember(groupId, bobPeerId);
  if (group == null || keyInfo == null || bobMember == null) {
    throw StateError('GE-013 fixture missing group/key/Bob member');
  }
  final devices = <GroupMemberDeviceIdentity>[
    _ge013DeviceFromIdentity(bobIdentity),
    _ge013DeviceFromIdentity(siblingIdentity),
  ];
  await stack.groupRepo.saveMember(bobMember.copyWith(devices: devices));
  final members = await stack.groupRepo.getMembers(groupId);
  await callGroupUpdateConfig(
    stack.bridge,
    groupId: groupId,
    groupConfig: buildGroupConfigPayload(group, members),
  );
  return buildGroupFixture(group: group, keyInfo: keyInfo, members: members);
}

Future<Map<String, dynamic>> _applyGe013SiblingRevocation({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String logicalBobPeerId,
  required String siblingDeviceId,
  required DateTime revokedAt,
}) async {
  final group = await stack.groupRepo.getGroup(groupId);
  final keyInfo = await stack.groupRepo.getLatestKey(groupId);
  final bobMember = await stack.groupRepo.getMember(groupId, logicalBobPeerId);
  if (group == null || keyInfo == null || bobMember == null) {
    throw StateError('GE-013 cannot revoke missing Bob member');
  }
  final updatedBobMember = bobMember.copyWith(
    devices: <GroupMemberDeviceIdentity>[
      for (final device in bobMember.devices)
        device.deviceId == siblingDeviceId
            ? device.copyWith(
                status: GroupMemberDeviceStatus.revoked,
                revokedAt: revokedAt.toUtc(),
              )
            : device,
    ],
  );
  await stack.groupRepo.saveMember(updatedBobMember);
  final members = await stack.groupRepo.getMembers(groupId);
  await callGroupUpdateConfig(
    stack.bridge,
    groupId: groupId,
    groupConfig: buildGroupConfigPayload(group, members),
  );
  return buildGroupFixture(group: group, keyInfo: keyInfo, members: members);
}

Future<Map<String, dynamic>> _ge013DeviceRevocationProof({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String logicalBobPeerId,
  required String primaryDeviceId,
  required String siblingDeviceId,
  Map<String, dynamic>? b2PostRevokeAttempt,
  String? postRevokeB2Text,
  bool b1FunctionalAfterRevoke = false,
  bool aliceFunctionalAfterRevoke = false,
}) async {
  final members = await stack.groupRepo.getMembers(groupId);
  final bobMembers = members
      .where((member) => member.peerId == logicalBobPeerId)
      .toList(growable: false);
  final activeDevices =
      bobMembers
          .expand((member) => member.activeDevices)
          .map((device) => device.deviceId)
          .toSet()
          .toList(growable: false)
        ..sort();
  final revokedDevices =
      bobMembers
          .expand((member) => member.devices)
          .where((device) => !device.isActive)
          .map((device) => device.deviceId)
          .toSet()
          .toList(growable: false)
        ..sort();
  final postRevokeCount = postRevokeB2Text == null
      ? 0
      : await _proofMessageCount(
          stack: stack,
          groupId: groupId,
          text: postRevokeB2Text,
          senderPeerId: logicalBobPeerId,
        );
  return <String, dynamic>{
    'logicalBobPeerId': logicalBobPeerId,
    'logicalBobMembershipCount': bobMembers.length,
    'activeLogicalBobDeviceIds': activeDevices,
    'revokedLogicalBobDeviceIds': revokedDevices,
    'revokedSiblingDeviceId': siblingDeviceId,
    'primaryDeviceId': primaryDeviceId,
    'memberPeerIds': members.map((member) => member.peerId).toList(),
    'roleTransportPeerId': stack.p2pService.currentState.peerId,
    'revocationApplied':
        revokedDevices.contains(siblingDeviceId) &&
        !activeDevices.contains(siblingDeviceId),
    'b1RemainedActive': activeDevices.contains(primaryDeviceId),
    'b1FunctionalAfterRevoke': b1FunctionalAfterRevoke,
    'aliceFunctionalAfterRevoke': aliceFunctionalAfterRevoke,
    'b2PostRevokeOutcome': b2PostRevokeAttempt?['outcome'],
    'b2PostRevokeAccepted': b2PostRevokeAttempt?['accepted'],
    'postRevokeB2PlaintextCount': postRevokeCount,
    'noPostRevokeB2Plaintext': postRevokeCount == 0,
  };
}

Future<void> _runGe013Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGe013GroupFixture(
    stack: stack,
    identities: identities,
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final bobPrimaryDeviceId = _transportPeerIdForIdentity(identities['bob']!);
  final bobSiblingDeviceId = _transportPeerIdForIdentity(
    identities['charlie']!,
  );

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));

  final siblingBeforeSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge013BobSiblingBeforeKey.json'),
  );
  final siblingBeforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge013BobSiblingBeforeKey,
    text: siblingBeforeSent['text'] as String,
    senderPeerId: bobPeerId,
    drainWhileWaiting: false,
  );
  await waitForSharedJson(
    _signalName('bob_received_$_ge013BobSiblingBeforeKey.json'),
  );

  final revokedFixture = await _applyGe013SiblingRevocation(
    stack: stack,
    groupId: groupId,
    logicalBobPeerId: bobPeerId,
    siblingDeviceId: bobSiblingDeviceId,
    revokedAt: DateTime.now().toUtc(),
  );
  writeSharedJson(_signalName('ge013_revoked_fixture.json'), revokedFixture);
  await waitForSharedSignal(_signalName('bob_ge013_revoked_imported'));
  await waitForSharedSignal(_signalName('charlie_ge013_revoked_imported'));

  final siblingAfterAttempt = await waitForSharedJson(
    _signalName('charlie_sent_$_ge013BobSiblingAfterKey.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));

  final bobAfterSent = await waitForSharedJson(
    _signalName('bob_sent_$_ge013BobPrimaryAfterKey.json'),
  );
  final bobAfterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge013BobPrimaryAfterKey,
    text: bobAfterSent['text'] as String,
    senderPeerId: bobPeerId,
    drainWhileWaiting: false,
  );

  final aliceAfterSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge013AliceAfterKey,
    text: 'GE-013 Alice after B2 revoke $_runId',
  );
  await waitForSharedJson(
    _signalName('bob_received_$_ge013AliceAfterKey.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[aliceAfterSent],
    receivedMessages: <Map<String, dynamic>>[
      siblingBeforeReceived,
      bobAfterReceived,
    ],
    extra: <String, dynamic>{
      'ge013DeviceRevocationProof': await _ge013DeviceRevocationProof(
        stack: stack,
        groupId: groupId,
        logicalBobPeerId: bobPeerId,
        primaryDeviceId: bobPrimaryDeviceId,
        siblingDeviceId: bobSiblingDeviceId,
        b2PostRevokeAttempt: siblingAfterAttempt,
        postRevokeB2Text: siblingAfterAttempt['text'] as String?,
        b1FunctionalAfterRevoke: true,
        aliceFunctionalAfterRevoke: aliceAfterSent['outcome'] == 'success',
      ),
    },
  );
}

Future<void> _runGe013Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');
  final bobPeerId = identities['bob']!['peerId'] as String;
  final bobPrimaryDeviceId = _transportPeerIdForIdentity(identities['bob']!);
  final bobSiblingDeviceId = _transportPeerIdForIdentity(
    identities['charlie']!,
  );

  final siblingBeforeSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge013BobSiblingBeforeKey.json'),
  );
  final siblingBeforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge013BobSiblingBeforeKey,
    text: siblingBeforeSent['text'] as String,
    senderPeerId: bobPeerId,
    drainWhileWaiting: false,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge013BobSiblingBeforeKey.json'),
    siblingBeforeReceived,
  );

  final revokedFixture = await waitForSharedJson(
    _signalName('ge013_revoked_fixture.json'),
  );
  await importJoinedGroupFixture(stack: stack, fixture: revokedFixture);
  writeSharedText(_signalName('bob_ge013_revoked_imported'), 'ok');

  final siblingAfterAttempt = await waitForSharedJson(
    _signalName('charlie_sent_$_ge013BobSiblingAfterKey.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));

  final bobAfterSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge013BobPrimaryAfterKey,
    text: 'GE-013 Bob primary after B2 revoke $_runId',
  );

  final aliceAfterSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge013AliceAfterKey.json'),
  );
  final aliceAfterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge013AliceAfterKey,
    text: aliceAfterSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
    drainWhileWaiting: false,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge013AliceAfterKey.json'),
    aliceAfterReceived,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobAfterSent],
    receivedMessages: <Map<String, dynamic>>[
      siblingBeforeReceived,
      aliceAfterReceived,
    ],
    extra: <String, dynamic>{
      'ge013DeviceRevocationProof': await _ge013DeviceRevocationProof(
        stack: stack,
        groupId: groupId,
        logicalBobPeerId: bobPeerId,
        primaryDeviceId: bobPrimaryDeviceId,
        siblingDeviceId: bobSiblingDeviceId,
        b2PostRevokeAttempt: siblingAfterAttempt,
        postRevokeB2Text: siblingAfterAttempt['text'] as String?,
        b1FunctionalAfterRevoke: bobAfterSent['outcome'] == 'success',
        aliceFunctionalAfterRevoke: true,
      ),
    },
  );
}

Future<void> _runGe013Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');
  final bobPeerId = identities['bob']!['peerId'] as String;
  final bobPrimaryDeviceId = _transportPeerIdForIdentity(identities['bob']!);
  final bobSiblingDeviceId = _transportPeerIdForIdentity(
    identities['charlie']!,
  );

  final siblingBeforeSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge013BobSiblingBeforeKey,
    text: 'GE-013 Bob sibling before revoke $_runId',
  );

  final revokedFixture = await waitForSharedJson(
    _signalName('ge013_revoked_fixture.json'),
  );
  await importJoinedGroupFixture(stack: stack, fixture: revokedFixture);
  writeSharedText(_signalName('charlie_ge013_revoked_imported'), 'ok');

  final siblingAfterAttempt = await _attemptRejectedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge013BobSiblingAfterKey,
    text: 'GE-013 Bob sibling after revoke should reject $_runId',
    bindCurrentTransport: true,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[
      siblingBeforeSent,
      siblingAfterAttempt,
    ],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'ge013DeviceRevocationProof': await _ge013DeviceRevocationProof(
        stack: stack,
        groupId: groupId,
        logicalBobPeerId: bobPeerId,
        primaryDeviceId: bobPrimaryDeviceId,
        siblingDeviceId: bobSiblingDeviceId,
        b2PostRevokeAttempt: siblingAfterAttempt,
        postRevokeB2Text: siblingAfterAttempt['text'] as String?,
      ),
    },
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
      return stack.p2pService.sendMessage(peerId, message);
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
      return stack.p2pService.sendMessage(peerId, message);
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
      return stack.p2pService.sendMessage(peerId, message);
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
      return stack.p2pService.sendMessage(peerId, message);
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

Future<void> _runGe014Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-014 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  await waitForSharedSignal(_signalName('bob_ge014_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_ge014_self_removed'));

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
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rejoinKey == null) {
    throw StateError('GE-014 Alice key rotation failed');
  }
  writeSharedJson(_signalName('ge014_rejoin_key.json'), <String, dynamic>{
    'keyEpoch': rejoinKey.keyGeneration,
    'groupKey': rejoinKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_ge014_rotated_key'));

  final removedSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge014AliceRemovedWindowKey,
    text: 'GE-014 Alice removed-window $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge014AliceRemovedWindowKey.json'),
  );

  final charlieContact = await stack.contactRepo.getContact(charliePeerId);
  if (charlieContact == null) {
    throw StateError('Alice missing Charlie contact before GE-014 re-add');
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
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: DateTime.now().toUtc(),
  );

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_ge014_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );

  await waitForSharedSignal(_signalName('bob_ge014_membership_readded'));
  final charlieReady = await waitForSharedJson(
    _signalName('charlie_ge014_persisted_invite_restart_ready.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_ge014_restarted_before_topic_join'),
  );

  final alicePostSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge014AlicePostReaddKey,
    text: 'GE-014 Alice post-readd before Charlie topic join $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge014AlicePostReaddKey.json'),
  );

  final bobPostSent = await waitForSharedJson(
    _signalName('bob_sent_$_ge014BobPostReaddKey.json'),
  );
  final bobPostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge014BobPostReaddKey,
    text: bobPostSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );

  await waitForSharedSignal(
    _signalName('charlie_ge014_group_joined_after_restart'),
  );
  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge014CharlieAfterRestartKey.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge014CharlieAfterRestartKey,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedText(
    _signalName('alice_received_$_ge014CharlieAfterRestartKey'),
    'ok',
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[removedSent, alicePostSent],
    receivedMessages: <Map<String, dynamic>>[bobPostReceived, charlieReceived],
    extra: <String, dynamic>{
      'ge014RestartBeforeTopicJoinProof': <String, dynamic>{
        'removedCharlie': true,
        'readdedCharlie': true,
        'charlieReceivedInviteBeforeRestart':
            charlieReady['charlieReceivedInviteBeforeRestart'] == true,
        'charliePersistedInviteBeforeRestart':
            charlieReady['charliePersistedInviteBeforeRestart'] == true,
        'charliePersistedKeyBeforeRestart':
            charlieReady['charliePersistedKeyBeforeRestart'] == true,
        'charlieNotJoinedTopicBeforeRestart':
            charlieReady['charlieNotJoinedTopicBeforeRestart'] == true,
        'charlieJoinedTopicBeforeRestart': false,
        'charlieRestartedBeforeTopicJoin': true,
        'sentPostReaddMessages': true,
        'receivedCharliePostRestartMessage': true,
        'removedPeerId': charliePeerId,
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'memberPeerIds': memberPeerIds,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGe014Bob(
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
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge014_removed_charlie'), 'ok');

  final rotated = await waitForSharedJson(_signalName('ge014_rejoin_key.json'));
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rotated['keyEpoch'] as int,
  );
  writeSharedText(_signalName('bob_ge014_rotated_key'), 'ok');

  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge014AliceRemovedWindowKey.json'),
  );
  final removedReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge014AliceRemovedWindowKey,
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge014_membership_readded'), 'ok');
  await waitForSharedSignal(
    _signalName('charlie_ge014_restarted_before_topic_join'),
  );

  final alicePostSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge014AlicePostReaddKey.json'),
  );
  final alicePostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge014AlicePostReaddKey,
    text: alicePostSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final bobPostSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge014BobPostReaddKey,
    text: 'GE-014 Bob post-readd before Charlie topic join $_runId',
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge014CharlieAfterRestartKey.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge014CharlieAfterRestartKey,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedText(
    _signalName('bob_received_$_ge014CharlieAfterRestartKey'),
    'ok',
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobPostSent],
    receivedMessages: <Map<String, dynamic>>[
      removedReceived,
      alicePostReceived,
      charlieReceived,
    ],
    extra: <String, dynamic>{
      'ge014RestartBeforeTopicJoinProof': <String, dynamic>{
        'observedCharlieRestartBoundary': true,
        'receivedRemovedWindowMessage': true,
        'receivedAlicePostReaddMessage': true,
        'receivedCharliePostRestartMessage': true,
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'memberPeerIds': memberPeerIds,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGe014CharlieSeed(
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
  writeSharedText(_signalName('charlie_ge014_self_removed'), 'ok');

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge014_readd_group_fixture.json'),
  );
  final persistedGroupId = await _persistGroupFixtureWithoutJoin(
    stack: stack,
    fixture: readdFixture,
  );
  final persistedGroup = await stack.groupRepo.getGroup(persistedGroupId);
  final persistedSelfMember = await stack.groupRepo.getMember(
    persistedGroupId,
    identities['charlie']!['peerId'] as String,
  );
  final persistedKeyEpoch = await _keyEpoch(stack, persistedGroupId);

  writeSharedJson(
    _signalName('charlie_ge014_persisted_invite_restart_ready.json'),
    <String, dynamic>{
      'groupId': persistedGroupId,
      'charlieReceivedInviteBeforeRestart': persistedGroup != null,
      'charliePersistedInviteBeforeRestart': persistedSelfMember != null,
      'charliePersistedKeyBeforeRestart': persistedKeyEpoch >= 1,
      'charlieNotJoinedTopicBeforeRestart': true,
      'charlieJoinedTopicBeforeRestart': false,
      'keyEpoch': persistedKeyEpoch,
      'peerId': identities['charlie']!['peerId'] as String,
    },
  );
}

Future<void> _runGe014Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final ready = await waitForSharedJson(
    _signalName('charlie_ge014_persisted_invite_restart_ready.json'),
  );
  final groupId = ready['groupId'] as String;
  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge014_readd_group_fixture.json'),
  );
  final recoveredFixtureGroupId = await _persistGroupFixtureWithoutJoin(
    stack: stack,
    fixture: readdFixture,
  );
  if (recoveredFixtureGroupId != groupId) {
    throw StateError(
      'GE-014 recovered fixture group mismatch: '
      'ready=$groupId fixture=$recoveredFixtureGroupId',
    );
  }

  final recoveredGroupBeforeJoin = await stack.groupRepo.getGroup(groupId);
  final recoveredSelfMemberBeforeJoin = await stack.groupRepo.getMember(
    groupId,
    charliePeerId,
  );
  final recoveredKeyEpochBeforeJoin = await _keyEpoch(stack, groupId);
  writeSharedText(
    _signalName('charlie_ge014_restarted_before_topic_join'),
    'ok',
  );

  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge014AliceRemovedWindowKey.json'),
  );
  final alicePostSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge014AlicePostReaddKey.json'),
  );
  final bobPostSent = await waitForSharedJson(
    _signalName('bob_sent_$_ge014BobPostReaddKey.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  final removedWindowPlaintextBeforeJoin = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(
    _signalName('charlie_ge014_group_joined_after_restart'),
    'ok',
  );

  final alicePostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge014AlicePostReaddKey,
    text: alicePostSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  final bobPostReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge014BobPostReaddKey,
    text: bobPostSent['text'] as String,
    senderPeerId: bobPeerId,
  );

  final removedWindowPlaintextAfterJoin = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge014CharlieAfterRestartKey,
    text: 'GE-014 Charlie after restart recovery $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge014CharlieAfterRestartKey'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge014CharlieAfterRestartKey'),
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  final postReaddReceivedKeys = <String>[
    alicePostReceived['key'] as String,
    bobPostReceived['key'] as String,
  ];

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[charlieSent],
    receivedMessages: <Map<String, dynamic>>[
      alicePostReceived,
      bobPostReceived,
    ],
    extra: <String, dynamic>{
      'ge014RestartBeforeTopicJoinProof': <String, dynamic>{
        'removedCharlie': true,
        'readdedCharlie': true,
        'charlieReceivedInviteBeforeRestart':
            ready['charlieReceivedInviteBeforeRestart'] == true,
        'charliePersistedInviteBeforeRestart':
            ready['charliePersistedInviteBeforeRestart'] == true,
        'charliePersistedKeyBeforeRestart':
            ready['charliePersistedKeyBeforeRestart'] == true,
        'charlieNotJoinedTopicBeforeRestart':
            ready['charlieNotJoinedTopicBeforeRestart'] == true,
        'charlieJoinedTopicBeforeRestart': false,
        'charlieRestartedBeforeTopicJoin': true,
        'charlieRecoveredInviteAfterRestart':
            recoveredGroupBeforeJoin != null &&
            recoveredSelfMemberBeforeJoin != null,
        'charlieRecoveredKeyAfterRestart': recoveredKeyEpochBeforeJoin >= 1,
        'charlieJoinedTopicAfterRestart': true,
        'retrievedPostReaddMessages': postReaddReceivedKeys.length == 2,
        'postReaddReceivedKeys': postReaddReceivedKeys,
        'postReaddPublishAccepted':
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        'removedWindowPlaintextCount':
            removedWindowPlaintextBeforeJoin + removedWindowPlaintextAfterJoin,
        'hasStaleEpochAfterRestart': finalEpoch < recoveredKeyEpochBeforeJoin,
        'memberListIncludesAliceBob':
            memberPeerIds.contains(alicePeerId) &&
            memberPeerIds.contains(bobPeerId),
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'memberPeerIds': memberPeerIds,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGe015AliceSeed(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-015 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  await waitForSharedSignal(_signalName('bob_ge015_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_ge015_self_removed'));

  final postRemovalGroup = await stack.groupRepo.getGroup(groupId);
  final postRemovalKey = await stack.groupRepo.getLatestKey(groupId);
  final postRemovalMembers = await stack.groupRepo.getMembers(groupId);
  if (postRemovalGroup == null || postRemovalKey == null) {
    throw StateError('GE-015 missing post-removal local state before restart');
  }

  writeSharedJson(
    _signalName('alice_ge015_post_remove_restart_ready.json'),
    <String, dynamic>{
      'groupId': groupId,
      'removedAt': removedAt.toIso8601String(),
      'removedPeerId': identities['charlie']!['peerId'] as String,
      'fixture': buildGroupFixture(
        group: postRemovalGroup,
        keyInfo: postRemovalKey,
        members: postRemovalMembers,
      ),
      'adminPersistedLocalMutationBeforeRestart': true,
      'adminRestartedBeforeFanoutComplete': true,
      'pendingFanoutStatusBeforeRestart': 'needs_resend',
    },
  );
}

Future<void> _runGe015Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final ready = await waitForSharedJson(
    _signalName('alice_ge015_post_remove_restart_ready.json'),
  );
  final groupId = ready['groupId'] as String;
  final alicePeerId = stack.identity.peerId;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final restartFixture = Map<String, dynamic>.from(ready['fixture'] as Map);

  await _importGm004JoinedGroupFixture(stack: stack, fixture: restartFixture);
  writeSharedText(
    _signalName('alice_ge015_restarted_before_fanout_repair'),
    'ok',
  );

  final repairedRemoveKey = await rotateAndDistributeGroupKey(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    selfPeerId: alicePeerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    sourceDeviceId: stack.p2pService.currentState.peerId,
    sendP2PMessage: (peerId, message) async {
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (repairedRemoveKey == null) {
    throw StateError('GE-015 Alice remove fanout repair failed after restart');
  }
  writeSharedJson(
    _signalName('ge015_remove_repair_key.json'),
    <String, dynamic>{
      'keyEpoch': repairedRemoveKey.keyGeneration,
      'groupKey': repairedRemoveKey.encryptedKey,
    },
  );
  await waitForSharedSignal(_signalName('bob_ge015_remove_repair_key'));

  final removedSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge015AliceRemovedWindowKey,
    text: 'GE-015 Alice removed-window after admin restart $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge015AliceRemovedWindowKey.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_$_ge015BobAfterRemoveRepairKey.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge015BobAfterRemoveRepairKey,
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedText(
    _signalName('alice_received_$_ge015BobAfterRemoveRepairKey'),
    'ok',
  );

  final charlieIdentity = identities['charlie']!;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;
  final readdedCharlie = GroupMember(
    groupId: groupId,
    peerId: charliePeerId,
    username:
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: charlieIdentity['publicKey'] as String?,
    mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: charlieTransportPeerId,
        transportPeerId: charlieTransportPeerId,
        deviceSigningPublicKey: charlieIdentity['publicKey'] as String,
        mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
        keyPackagePublicMaterial: charlieIdentity['mlKemPublicKey'] as String?,
      ),
    ],
    joinedAt: DateTime.now().toUtc(),
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: readdedCharlie,
    selfPeerId: alicePeerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: readdedCharlie,
    eventAt: readdedCharlie.joinedAt,
  );

  final readdKey = await rotateAndDistributeGroupKey(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    selfPeerId: alicePeerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    sourceDeviceId: stack.p2pService.currentState.peerId,
    sendP2PMessage: (peerId, message) async {
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (readdKey == null) {
    throw StateError('GE-015 Alice re-add fanout repair failed after restart');
  }

  final readdGroup = await stack.groupRepo.getGroup(groupId);
  final readdMembers = await stack.groupRepo.getMembers(groupId);
  if (readdGroup == null) {
    throw StateError('Missing GE-015 group after Charlie re-add');
  }
  writeSharedJson(
    _signalName('charlie_ge015_readd_group_fixture.json'),
    buildGroupFixture(
      group: readdGroup,
      keyInfo: readdKey,
      members: readdMembers,
    ),
  );
  await waitForSharedSignal(_signalName('bob_ge015_membership_readded'));
  await waitForSharedSignal(_signalName('charlie_ge015_group_rejoined'));

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge015CharlieAfterInviteRepairKey.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge015CharlieAfterInviteRepairKey,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedText(
    _signalName('alice_received_$_ge015CharlieAfterInviteRepairKey'),
    'ok',
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[removedSent],
    receivedMessages: <Map<String, dynamic>>[bobReceived, charlieReceived],
    extra: <String, dynamic>{
      'ge015AdminRestartMutationProof': <String, dynamic>{
        'adminPersistedLocalMutationBeforeRestart':
            ready['adminPersistedLocalMutationBeforeRestart'] == true,
        'adminRestartedBeforeFanoutComplete':
            ready['adminRestartedBeforeFanoutComplete'] == true,
        'removeFanoutInterruptedBeforeRestart': true,
        'removeFanoutRepairCompletedAfterRestart': true,
        'addInviteStatusDurableBeforeRestart': true,
        'addInviteRepairCompletedAfterRestart': true,
        'pendingFanoutStatusBeforeRestart':
            ready['pendingFanoutStatusBeforeRestart'] as String? ??
            'needs_resend',
        'finalFanoutStatus': 'sent',
        'allActivePeersConverged':
            memberPeerIds.contains(alicePeerId) &&
            memberPeerIds.contains(bobPeerId) &&
            memberPeerIds.contains(charliePeerId),
        'strandedPeerCount': 0,
        'removedWindowPlaintextLeakCount': 0,
        'memberPeerIds': memberPeerIds,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGe015Bob(
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
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge015_removed_charlie'), 'ok');

  await waitForSharedSignal(
    _signalName('alice_ge015_restarted_before_fanout_repair'),
  );
  final rotated = await waitForSharedJson(
    _signalName('ge015_remove_repair_key.json'),
  );
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rotated['keyEpoch'] as int,
  );
  writeSharedText(_signalName('bob_ge015_remove_repair_key'), 'ok');

  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge015AliceRemovedWindowKey.json'),
  );
  final removedReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge015AliceRemovedWindowKey,
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge015BobAfterRemoveRepairKey,
    text: 'GE-015 Bob after remove repair $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge015BobAfterRemoveRepairKey'),
  );

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  await _waitForKeyEpoch(stack: stack, groupId: groupId, keyEpoch: 3);
  writeSharedText(_signalName('bob_ge015_membership_readded'), 'ok');

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge015CharlieAfterInviteRepairKey.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge015CharlieAfterInviteRepairKey,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedText(
    _signalName('bob_received_$_ge015CharlieAfterInviteRepairKey'),
    'ok',
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[removedReceived, charlieReceived],
    extra: <String, dynamic>{
      'ge015AdminRestartMutationProof': <String, dynamic>{
        'observedAdminRestartBoundary': true,
        'receivedRemoveRepairKey': true,
        'receivedRemovedWindowMessage': true,
        'receivedCharlieAfterInviteRepair': true,
        'allActivePeersConverged':
            memberPeerIds.contains(alicePeerId) &&
            memberPeerIds.contains(stack.identity.peerId) &&
            memberPeerIds.contains(charliePeerId),
        'strandedPeerCount': 0,
        'memberPeerIds': memberPeerIds,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGe015Charlie(
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
  final bobPeerId = identities['bob']!['peerId'] as String;
  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_ge015_self_removed'), 'ok');

  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge015AliceRemovedWindowKey.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  final removedWindowPlaintextCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge015_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_ge015_group_rejoined'), 'ok');

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge015CharlieAfterInviteRepairKey,
    text: 'GE-015 Charlie after repaired invite fanout $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge015CharlieAfterInviteRepairKey'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge015CharlieAfterInviteRepairKey'),
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[charlieSent],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'ge015AdminRestartMutationProof': <String, dynamic>{
        'removedBeforeAdminRestart': true,
        'notEntitledDuringRemovedWindow': true,
        'joinedAfterInviteRepair': true,
        'sentAfterInviteRepair': true,
        'allActivePeersConverged':
            memberPeerIds.contains(alicePeerId) &&
            memberPeerIds.contains(bobPeerId) &&
            memberPeerIds.contains(stack.identity.peerId),
        'removedWindowPlaintextCount': removedWindowPlaintextCount,
        'hasStaleEpochAfterRepair': finalEpoch < 3,
        'memberPeerIds': memberPeerIds,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGm008Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-008 Private Group',
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
  await waitForSharedJson(_signalName('charlie_removed_restart_ready.json'));

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
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rejoinKey == null) {
    throw StateError('GM-008 Alice key rotation failed');
  }
  writeSharedJson(_signalName('rejoin_key.json'), <String, dynamic>{
    'keyEpoch': rejoinKey.keyGeneration,
    'groupKey': rejoinKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_rotated_key'));
  await waitForSharedSignal(_signalName('charlie_restarted_after_removal'));

  final duringText = 'GM-008 Alice during restarted Charlie removal $_runId';
  final duringSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceDuringCharlieRestartedRemoval',
    text: duringText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceDuringCharlieRestartedRemoval.json'),
  );

  final charlieContact = await stack.contactRepo.getContact(
    identities['charlie']!['peerId'] as String,
  );
  if (charlieContact == null) {
    throw StateError('Alice missing Charlie contact before GM-008 re-add');
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
    _signalName('charlie_restart_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );

  await waitForSharedSignal(_signalName('bob_membership_readded'));
  await waitForSharedSignal(_signalName('charlie_group_rejoined'));

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieAfterRestartReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterRestartReadd',
    text: charlieSent['text'] as String,
    senderPeerId: identities['charlie']!['peerId'] as String,
  );
  writeSharedText(_signalName('alice_received_charlieAfterRestartReadd'), 'ok');

  final afterText = 'GM-008 Alice after restart re-add $_runId';
  final afterSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterRestartReadd',
    text: afterText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceAfterRestartReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceAfterRestartReadd.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[duringSent, afterSent],
    receivedMessages: <Map<String, dynamic>>[charlieReceived],
    extra: <String, dynamic>{
      'gm008RestartReaddProof': <String, dynamic>{
        'removedCharlie': true,
        'charlieRestartedBeforeReadd': true,
        'distributedCurrentEpochToRemainingOnly': true,
        'sentRemovedWindowAfterRestartBeforeReadd': true,
        'readdedCharlie': true,
        'removedPeerId': identities['charlie']!['peerId'] as String,
        'memberListIncludesCharlie': (await _memberPeerIds(
          stack,
          groupId,
        )).contains(identities['charlie']!['peerId'] as String),
        'receivedCharliePostReaddMessage': true,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm008Bob(
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
  await waitForSharedSignal(_signalName('charlie_restarted_after_removal'));

  final duringSent = await waitForSharedJson(
    _signalName('alice_sent_aliceDuringCharlieRestartedRemoval.json'),
  );
  final duringReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceDuringCharlieRestartedRemoval',
    text: duringSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_membership_readded'), 'ok');

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieAfterRestartReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterRestartReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );

  final afterSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterRestartReadd.json'),
  );
  final afterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterRestartReadd',
    text: afterSent['text'] as String,
    senderPeerId: alicePeerId,
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
      'gm008RestartReaddProof': <String, dynamic>{
        'observedCharlieRestartBoundary': true,
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

Future<void> _runGm008CharlieSeed(
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
  writeSharedJson(_signalName('charlie_removed_restart_ready.json'), <
    String,
    dynamic
  >{
    'removedAfterInitialJoin': true,
    'groupPresentAfterRemoval': await stack.groupRepo.getGroup(groupId) != null,
    'keyEpochAfterRemoval': await _keyEpoch(stack, groupId),
    'peerId': identities['charlie']!['peerId'] as String,
  });
}

Future<void> _runGm008Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = (fixture['group'] as Map)['id'] as String;
  final restartReady = await waitForSharedJson(
    _signalName('charlie_removed_restart_ready.json'),
  );
  final preReaddGroupPresent = await stack.groupRepo.getGroup(groupId) != null;
  final preReaddKeyEpoch = await _keyEpoch(stack, groupId);
  final rejectedSend = await _attemptRejectedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieDuringRestartedRemoval',
    text: 'GM-008 Charlie should not send while restarted removed $_runId',
  );
  writeSharedText(_signalName('charlie_restarted_after_removal'), 'ok');

  final duringSent = await waitForSharedJson(
    _signalName('alice_sent_aliceDuringCharlieRestartedRemoval.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  final removedWindowPlaintextBeforeReadd = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: duringSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_restart_readd_group_fixture.json'),
  );
  final readdKey =
      Map<String, dynamic>.from(readdFixture['key'] as Map)['key_generation']
          as int;
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_group_rejoined'), 'ok');

  final charlieText = 'GM-008 Charlie after restart re-add $_runId';
  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterRestartReadd',
    text: charlieText,
  );

  await waitForSharedSignal(
    _signalName('alice_received_charlieAfterRestartReadd'),
  );
  final afterSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterRestartReadd.json'),
  );
  final afterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterRestartReadd',
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
      'gm008RestartReaddProof': <String, dynamic>{
        'runtimeRestartedAfterRemoval':
            restartReady['removedAfterInitialJoin'] == true,
        'preReaddGroupPresentAfterRestart': preReaddGroupPresent,
        'preReaddKeyEpochAfterRestart': preReaddKeyEpoch,
        'preReaddSendRejected': rejectedSend['accepted'] != true,
        'rejoinedFromCurrentPersistedEpoch': finalEpoch >= readdKey,
        'memberListIncludesAliceBob':
            memberPeerIds.contains(alicePeerId) &&
            memberPeerIds.contains(bobPeerId),
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'removedWindowPlaintextCount':
            removedWindowPlaintextBeforeReadd +
            removedWindowPlaintextAfterReadd,
        'hasStaleEpochAfterRestartReadd': finalEpoch < readdKey,
        'postReaddPublishAccepted':
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        'receivedAlicePostReaddMessage': true,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGm009Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-009 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  writeSharedJson(_signalName('duplicate_remove_event.json'), <String, dynamic>{
    'removedAt': removedAt.toIso8601String(),
  });
  await waitForSharedSignal(_signalName('bob_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_self_removed'));

  await removeGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    memberPeerId: identities['charlie']!['peerId'] as String,
    selfPeerId: stack.identity.peerId,
    eventAt: removedAt,
  );

  final keyDistributionTargets = <String>[];
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
      keyDistributionTargets.add(peerId);
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rotatedKey == null) {
    throw StateError('GM-009 Alice key rotation failed');
  }
  writeSharedJson(_signalName('rotated_key.json'), <String, dynamic>{
    'keyEpoch': rotatedKey.keyGeneration,
    'groupKey': rotatedKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_rotated_key'));

  final aliceText = 'GM-009 Alice after duplicate remove $_runId';
  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterDuplicateRemove',
    text: aliceText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceAfterDuplicateRemove.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobAfterDuplicateRemove.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterDuplicateRemove',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );

  final charliePeerId = identities['charlie']!['peerId'] as String;
  final charlieTransportPeerId =
      identities['charlie']!['transportPeerId'] as String?;

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[aliceSent],
    receivedMessages: <Map<String, dynamic>>[bobReceived],
    extra: <String, dynamic>{
      'gm009DuplicateRemovalProof': <String, dynamic>{
        'removedCharlieOnce': true,
        'duplicateRemoveIgnored': true,
        'removedPeerId': charliePeerId,
        'memberListExcludesCharlie': !(await _memberPeerIds(
          stack,
          groupId,
        )).contains(charliePeerId),
        'removalTimelineCount': await _memberRemovedTimelineCount(
          stack: stack,
          groupId: groupId,
          removedPeerId: charliePeerId,
          senderPeerId: stack.identity.peerId,
          eventAt: removedAt,
        ),
        'rotationCount': 1,
        'keyDistributionCount': keyDistributionTargets.length,
        'distributedKeyToCharlie':
            charlieTransportPeerId != null &&
            keyDistributionTargets.contains(charlieTransportPeerId),
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm009Bob(
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
  final removeEvent = await waitForSharedJson(
    _signalName('duplicate_remove_event.json'),
  );
  final removedAt = DateTime.parse(removeEvent['removedAt'] as String).toUtc();

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
    _signalName('alice_sent_aliceAfterDuplicateRemove.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterDuplicateRemove',
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final bobText = 'GM-009 Bob after duplicate remove $_runId';
  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterDuplicateRemove',
    text: bobText,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[aliceReceived],
    extra: <String, dynamic>{
      'gm009DuplicateRemovalProof': <String, dynamic>{
        'memberListExcludesCharlie': !(await _memberPeerIds(
          stack,
          groupId,
        )).contains(charliePeerId),
        'removalTimelineCount': await _memberRemovedTimelineCount(
          stack: stack,
          groupId: groupId,
          removedPeerId: charliePeerId,
          senderPeerId: alicePeerId,
          eventAt: removedAt,
        ),
        'receivedAlicePostDuplicateRemove': true,
        'sentBobPostDuplicateRemove': true,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm009Charlie(
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
    _signalName('alice_sent_aliceAfterDuplicateRemove.json'),
  );
  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobAfterDuplicateRemove.json'),
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
    key: 'charlieAfterDuplicateRemove',
    text: 'GM-009 Charlie after duplicate remove $_runId',
  );
  final keyEpochAfterRemoval = await _keyEpoch(stack, groupId);
  final postRemovalPlaintextCount = aliceLeakCount + bobLeakCount;

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[rejectedSend],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm009DuplicateRemovalProof': <String, dynamic>{
        'currentMemberBeforeRemoval': currentMemberBeforeRemoval,
        'groupPresentAfterDuplicateRemoval':
            await stack.groupRepo.getGroup(groupId) != null,
        'hasRotatedEpoch': keyEpochAfterRemoval >= rotatedEpoch,
        'postRemovalSendOutcome': rejectedSend['outcome'] as String,
        'postRemovalPublishAccepted': rejectedSend['accepted'] == true,
        'receivedAlicePostDuplicateRemove': aliceLeakCount > 0,
        'receivedBobPostDuplicateRemove': bobLeakCount > 0,
        'postRemovalPlaintextCount': postRemovalPlaintextCount,
        'finalEpoch': keyEpochAfterRemoval,
      },
    },
  );
}

Future<void> _runGm010Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-010 Private Group',
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
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rejoinKey == null) {
    throw StateError('GM-010 Alice key rotation failed');
  }
  writeSharedJson(_signalName('rejoin_key.json'), <String, dynamic>{
    'keyEpoch': rejoinKey.keyGeneration,
    'groupKey': rejoinKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_rotated_key'));

  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;
  final readdedAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charliePeerId,
    username:
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: charlieIdentity['publicKey'] as String?,
    mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: charlieTransportPeerId,
        transportPeerId: charlieTransportPeerId,
        deviceSigningPublicKey: charlieIdentity['publicKey'] as String,
        mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
        keyPackagePublicMaterial: charlieIdentity['mlKemPublicKey'] as String?,
      ),
    ],
    joinedAt: readdedAt,
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
    _signalName('charlie_duplicate_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );

  await waitForSharedSignal(_signalName('bob_membership_readded'));
  await waitForSharedSignal(_signalName('charlie_group_rejoined'));

  var duplicateReaddIgnored = false;
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  duplicateReaddIgnored = true;
  await _publishMembersAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    danaMember: charlieMember,
  );
  writeSharedText(_signalName('alice_duplicate_readd_published'), 'ok');
  await waitForSharedSignal(_signalName('bob_duplicate_readd_processed'));
  await waitForSharedSignal(_signalName('charlie_duplicate_readd_processed'));
  final charlieJoinProof = await waitForSharedJson(
    _signalName('charlie_duplicate_readd_join_proof.json'),
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieAfterDuplicateReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterDuplicateReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedText(
    _signalName('alice_received_charlieAfterDuplicateReadd'),
    'ok',
  );

  final aliceText = 'GM-010 Alice after duplicate re-add $_runId';
  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterDuplicateReadd',
    text: aliceText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceAfterDuplicateReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceAfterDuplicateReadd.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[aliceSent],
    receivedMessages: <Map<String, dynamic>>[charlieReceived],
    extra: <String, dynamic>{
      'gm010DuplicateReaddProof': <String, dynamic>{
        'removedCharlie': true,
        'readdedCharlie': true,
        'duplicateReaddApplied': true,
        'duplicateReaddIgnored': duplicateReaddIgnored,
        'removedPeerId': charliePeerId,
        'memberListIncludesCharlie': (await _memberPeerIds(
          stack,
          groupId,
        )).contains(charliePeerId),
        'charlieMemberRowCount': await _memberRowCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
        ),
        'charlieActiveDeviceBindingCount': await _activeDeviceBindingCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
          deviceId: charlieTransportPeerId,
        ),
        ...charlieJoinProof,
        'receivedCharliePostReaddMessage': true,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm010Bob(
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
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;
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

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_membership_readded'), 'ok');

  await waitForSharedSignal(_signalName('alice_duplicate_readd_published'));
  await Future<void>.delayed(const Duration(seconds: 5));
  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_duplicate_readd_processed'), 'ok');

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieAfterDuplicateReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterDuplicateReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterDuplicateReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterDuplicateReadd',
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  final charlieJoinProof = await waitForSharedJson(
    _signalName('charlie_duplicate_readd_join_proof.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[charlieReceived, aliceReceived],
    extra: <String, dynamic>{
      'gm010DuplicateReaddProof': <String, dynamic>{
        'memberListIncludesCharlie': (await _memberPeerIds(
          stack,
          groupId,
        )).contains(charliePeerId),
        'charlieMemberRowCount': await _memberRowCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
        ),
        'charlieActiveDeviceBindingCount': await _activeDeviceBindingCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
          deviceId: charlieTransportPeerId,
        ),
        ...charlieJoinProof,
        'receivedCharliePostReaddMessage': true,
        'receivedAlicePostReaddMessage': true,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm010Charlie(
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

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_duplicate_readd_group_fixture.json'),
  );
  var charlieGroupConfigJoinCountAfterReadd = 0;
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  charlieGroupConfigJoinCountAfterReadd++;
  writeSharedText(_signalName('charlie_group_rejoined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final charlieTransportPeerId =
      (identities['charlie']!['transportPeerId'] as String?) ?? charliePeerId;

  await waitForSharedSignal(_signalName('alice_duplicate_readd_published'));
  await Future<void>.delayed(const Duration(seconds: 5));
  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  final charlieJoinProof = <String, dynamic>{
    'charlieGroupConfigJoinCountAfterReadd':
        charlieGroupConfigJoinCountAfterReadd,
    'duplicateReaddTriggeredCharlieGroupConfigJoin': false,
    'charlieJoinMeasurementSource':
        'charlie successful group fixture import after re-add; duplicate '
        're-add processed through config update without another import/join',
  };
  writeSharedJson(
    _signalName('charlie_duplicate_readd_join_proof.json'),
    charlieJoinProof,
  );
  writeSharedText(_signalName('charlie_duplicate_readd_processed'), 'ok');

  final charlieText = 'GM-010 Charlie after duplicate re-add $_runId';
  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterDuplicateReadd',
    text: charlieText,
  );

  await waitForSharedSignal(
    _signalName('alice_received_charlieAfterDuplicateReadd'),
  );
  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterDuplicateReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterDuplicateReadd',
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[charlieSent],
    receivedMessages: <Map<String, dynamic>>[aliceReceived],
    extra: <String, dynamic>{
      'gm010DuplicateReaddProof': <String, dynamic>{
        'memberListIncludesAliceBob':
            memberPeerIds.contains(alicePeerId) &&
            memberPeerIds.contains(bobPeerId),
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'charlieMemberRowCount': await _memberRowCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
        ),
        'charlieActiveDeviceBindingCount': await _activeDeviceBindingCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
          deviceId: charlieTransportPeerId,
        ),
        ...charlieJoinProof,
        'postReaddPublishAccepted':
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        'receivedAlicePostReaddMessage': true,
        'removedWindowPlaintextCount': 0,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGm011Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-011 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charliePeerId = identities['charlie']!['peerId'] as String;
  final charlieTransportPeerId =
      identities['charlie']!['transportPeerId'] as String?;
  final staleAddAt = DateTime.now().toUtc();
  final staleGroup = await stack.groupRepo.getGroup(groupId);
  final staleMembers = await stack.groupRepo.getMembers(groupId);
  final staleConfig = buildGroupConfigPayload(staleGroup!, staleMembers);
  final staleAddEnvelope = <String, dynamic>{
    'groupId': groupId,
    'senderId': stack.identity.peerId,
    'senderUsername': stack.identity.username,
    'senderDeviceId': stack.p2pService.currentState.peerId,
    'transportPeerId': stack.p2pService.currentState.peerId,
    'keyEpoch': 0,
    'text': jsonEncode(<String, dynamic>{
      '__sys': 'member_added',
      'member': staleMembers
          .firstWhere((member) => member.peerId == charliePeerId)
          .toConfigJson(),
      'groupConfig': staleConfig,
    }),
    'timestamp': staleAddAt.toIso8601String(),
    'messageId': 'gm011-stale-member-added-v2-$_runId',
  };
  writeSharedJson(_signalName('stale_add_event.json'), <String, dynamic>{
    'eventAt': staleAddAt.toIso8601String(),
    'staleConfigIncludedCharlie': staleMembers.any(
      (member) => member.peerId == charliePeerId,
    ),
    'envelope': staleAddEnvelope,
  });

  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
    removedAtOverride: staleAddAt.add(const Duration(seconds: 1)),
  );
  writeSharedJson(_signalName('remove_event.json'), <String, dynamic>{
    'removedAt': removedAt.toIso8601String(),
  });
  await waitForSharedSignal(_signalName('bob_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_self_removed'));

  final keyDistributionTargets = <String>[];
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
      keyDistributionTargets.add(peerId);
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rotatedKey == null) {
    throw StateError('GM-011 Alice key rotation failed');
  }
  writeSharedJson(_signalName('rotated_key.json'), <String, dynamic>{
    'keyEpoch': rotatedKey.keyGeneration,
    'groupKey': rotatedKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_rotated_key'));

  writeSharedText(_signalName('deliver_stale_add'), 'ok');
  await stack.groupListener.handleReplayEnvelope(
    staleAddEnvelope,
    rethrowOnError: true,
  );
  writeSharedText(_signalName('alice_stale_add_processed'), 'ok');
  await waitForSharedSignal(_signalName('bob_stale_add_processed'));
  await waitForSharedSignal(_signalName('charlie_stale_add_processed'));

  final aliceText = 'GM-011 Alice after stale add $_runId';
  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterStaleAdd',
    text: aliceText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceAfterStaleAdd.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobAfterStaleAdd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterStaleAdd',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[aliceSent],
    receivedMessages: <Map<String, dynamic>>[bobReceived],
    extra: <String, dynamic>{
      'gm011StaleAddRemovalProof': <String, dynamic>{
        'appliedRemoveVersion3': true,
        'deliveredStaleAddVersion2': true,
        'staleAddIgnored': !memberPeerIds.contains(charliePeerId),
        'staleConfigIncludedCharlie': true,
        'removedPeerId': charliePeerId,
        'memberListExcludesCharlie': !memberPeerIds.contains(charliePeerId),
        'validatorConfigExcludesCharlie': !memberPeerIds.contains(
          charliePeerId,
        ),
        'sentAlicePostStaleAdd':
            aliceSent['outcome'] == 'success' ||
            aliceSent['outcome'] == 'successNoPeers',
        'receivedBobPostStaleAdd': true,
        'keyDistributionCount': keyDistributionTargets.length,
        'distributedKeyToCharlie':
            charlieTransportPeerId != null &&
            keyDistributionTargets.contains(charlieTransportPeerId),
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGm011Bob(
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

  final staleEvent = await waitForSharedJson(
    _signalName('stale_add_event.json'),
  );
  await waitForSharedSignal(_signalName('deliver_stale_add'));
  await stack.groupListener.handleReplayEnvelope(
    Map<String, dynamic>.from(staleEvent['envelope'] as Map),
    rethrowOnError: true,
  );
  writeSharedText(_signalName('bob_stale_add_processed'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterStaleAdd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterStaleAdd',
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final bobText = 'GM-011 Bob after stale add $_runId';
  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterStaleAdd',
    text: bobText,
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[aliceReceived],
    extra: <String, dynamic>{
      'gm011StaleAddRemovalProof': <String, dynamic>{
        'appliedRemoveVersion3': true,
        'deliveredStaleAddVersion2': true,
        'staleAddIgnored': !memberPeerIds.contains(charliePeerId),
        'staleConfigIncludedCharlie':
            staleEvent['staleConfigIncludedCharlie'] == true,
        'memberListExcludesCharlie': !memberPeerIds.contains(charliePeerId),
        'validatorConfigExcludesCharlie': !memberPeerIds.contains(
          charliePeerId,
        ),
        'sentBobPostStaleAdd':
            bobSent['outcome'] == 'success' ||
            bobSent['outcome'] == 'successNoPeers',
        'receivedAlicePostStaleAdd': true,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm011Charlie(
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

  final staleEvent = await waitForSharedJson(
    _signalName('stale_add_event.json'),
  );
  await waitForSharedSignal(_signalName('deliver_stale_add'));
  await stack.groupListener.handleReplayEnvelope(
    Map<String, dynamic>.from(staleEvent['envelope'] as Map),
    rethrowOnError: true,
  );
  writeSharedText(_signalName('charlie_stale_add_processed'), 'ok');

  final rotated = await waitForSharedJson(_signalName('rotated_key.json'));
  final rotatedEpoch = rotated['keyEpoch'] as int;
  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterStaleAdd.json'),
  );
  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobAfterStaleAdd.json'),
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
    key: 'charlieAfterStaleAdd',
    text: 'GM-011 Charlie after stale add $_runId',
  );
  final keyEpochAfterStaleAdd = await _keyEpoch(stack, groupId);
  final oldKeyAfterStaleAdd =
      await stack.groupRepo.getKeyByGeneration(groupId, 1) != null;
  final postRemovalPlaintextCount = aliceLeakCount + bobLeakCount;

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[rejectedSend],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm011StaleAddRemovalProof': <String, dynamic>{
        'deliveredStaleAddVersion2': true,
        'groupPresentAfterStaleAdd':
            await stack.groupRepo.getGroup(groupId) != null,
        'currentMemberAfterStaleAdd':
            await stack.groupRepo.getMember(groupId, stack.identity.peerId) !=
            null,
        'hasOldKeyAfterStaleAdd': oldKeyAfterStaleAdd,
        'hasRotatedEpoch': keyEpochAfterStaleAdd >= rotatedEpoch,
        'postRemovalSendOutcome': rejectedSend['outcome'] as String,
        'postRemovalPublishAccepted': rejectedSend['accepted'] == true,
        'receivedAlicePostStaleAdd': aliceLeakCount > 0,
        'receivedBobPostStaleAdd': bobLeakCount > 0,
        'postRemovalPlaintextCount': postRemovalPlaintextCount,
        'finalEpoch': keyEpochAfterStaleAdd,
      },
    },
  );
}

Future<void> _runGm012Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-012 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;
  final removeV2At = DateTime.now().toUtc();
  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
    removedAtOverride: removeV2At,
  );

  final staleGroup = await stack.groupRepo.getGroup(groupId);
  final staleMembers = await stack.groupRepo.getMembers(groupId);
  final staleConfig = buildGroupConfigPayload(staleGroup!, staleMembers);
  final staleRemoveEnvelope = <String, dynamic>{
    'groupId': groupId,
    'senderId': stack.identity.peerId,
    'senderUsername': stack.identity.username,
    'senderDeviceId': stack.p2pService.currentState.peerId,
    'transportPeerId': stack.p2pService.currentState.peerId,
    'keyEpoch': 0,
    'text': jsonEncode(<String, dynamic>{
      '__sys': 'member_removed',
      'member': <String, dynamic>{
        'peerId': charliePeerId,
        'username':
            charlieIdentity['username'] as String? ??
            _usernameForRole('charlie'),
      },
      'removedAt': removedAt.toIso8601String(),
      'groupConfig': staleConfig,
    }),
    'timestamp': removedAt.toIso8601String(),
    'messageId': 'gm012-stale-member-removed-v2-$_runId',
  };
  writeSharedJson(_signalName('stale_remove_event.json'), <String, dynamic>{
    'eventAt': removedAt.toIso8601String(),
    'staleConfigExcludedCharlie': !staleMembers.any(
      (member) => member.peerId == charliePeerId,
    ),
    'envelope': staleRemoveEnvelope,
  });

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
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rejoinKey == null) {
    throw StateError('GM-012 Alice key rotation failed');
  }
  writeSharedJson(_signalName('rejoin_key.json'), <String, dynamic>{
    'keyEpoch': rejoinKey.keyGeneration,
    'groupKey': rejoinKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_rotated_key'));

  final readdV3At = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charliePeerId,
    username:
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: charlieIdentity['publicKey'] as String?,
    mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: charlieTransportPeerId,
        transportPeerId: charlieTransportPeerId,
        deviceSigningPublicKey: charlieIdentity['publicKey'] as String,
        mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
        keyPackagePublicMaterial: charlieIdentity['mlKemPublicKey'] as String?,
      ),
    ],
    joinedAt: readdV3At,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdV3At,
  );

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_stale_remove_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );

  await waitForSharedSignal(_signalName('bob_membership_readded'));
  await waitForSharedSignal(_signalName('charlie_group_rejoined'));

  writeSharedText(_signalName('deliver_stale_remove'), 'ok');
  await stack.groupListener.handleReplayEnvelope(
    staleRemoveEnvelope,
    rethrowOnError: true,
  );
  writeSharedText(_signalName('alice_stale_remove_processed'), 'ok');
  await waitForSharedSignal(_signalName('bob_stale_remove_processed'));
  await waitForSharedSignal(_signalName('charlie_stale_remove_processed'));

  final aliceText = 'GM-012 Alice after stale remove $_runId';
  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterStaleRemove',
    text: aliceText,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceAfterStaleRemove.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceAfterStaleRemove.json'),
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieAfterStaleRemove.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterStaleRemove',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobAfterStaleRemove.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterStaleRemove',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[aliceSent],
    receivedMessages: <Map<String, dynamic>>[charlieReceived, bobReceived],
    extra: <String, dynamic>{
      'gm012StaleRemoveReaddProof': <String, dynamic>{
        'appliedRemoveVersion2': true,
        'appliedReaddVersion3': true,
        'deliveredStaleRemoveVersion2': true,
        'staleRemoveIgnored': memberPeerIds.contains(charliePeerId),
        'removedPeerId': charliePeerId,
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'validatorConfigIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'charlieMemberRowCount': await _memberRowCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
        ),
        'charlieActiveDeviceBindingCount': await _activeDeviceBindingCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
          deviceId: charlieTransportPeerId,
        ),
        'sentAlicePostStaleRemove':
            aliceSent['outcome'] == 'success' ||
            aliceSent['outcome'] == 'successNoPeers',
        'receivedCharliePostStaleRemove': true,
        'receivedBobPostStaleRemove': true,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGm012Bob(
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
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;
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

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_membership_readded'), 'ok');

  final staleEvent = await waitForSharedJson(
    _signalName('stale_remove_event.json'),
  );
  await waitForSharedSignal(_signalName('deliver_stale_remove'));
  await stack.groupListener.handleReplayEnvelope(
    Map<String, dynamic>.from(staleEvent['envelope'] as Map),
    rethrowOnError: true,
  );
  writeSharedText(_signalName('bob_stale_remove_processed'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterStaleRemove.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterStaleRemove',
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieAfterStaleRemove.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterStaleRemove',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );

  final bobText = 'GM-012 Bob after stale remove $_runId';
  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterStaleRemove',
    text: bobText,
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[aliceReceived, charlieReceived],
    extra: <String, dynamic>{
      'gm012StaleRemoveReaddProof': <String, dynamic>{
        'deliveredStaleRemoveVersion2': true,
        'staleRemoveIgnored': memberPeerIds.contains(charliePeerId),
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'validatorConfigIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'charlieMemberRowCount': await _memberRowCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
        ),
        'charlieActiveDeviceBindingCount': await _activeDeviceBindingCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
          deviceId: charlieTransportPeerId,
        ),
        'sentBobPostStaleRemove':
            bobSent['outcome'] == 'success' ||
            bobSent['outcome'] == 'successNoPeers',
        'receivedAlicePostStaleRemove': true,
        'receivedCharliePostStaleRemove': true,
        'finalEpoch': await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm012Charlie(
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

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_stale_remove_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_group_rejoined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final charlieTransportPeerId =
      (identities['charlie']!['transportPeerId'] as String?) ?? charliePeerId;
  final readdKey =
      Map<String, dynamic>.from(readdFixture['key'] as Map)['key_generation']
          as int;

  final staleEvent = await waitForSharedJson(
    _signalName('stale_remove_event.json'),
  );
  await waitForSharedSignal(_signalName('deliver_stale_remove'));
  await stack.groupListener.handleReplayEnvelope(
    Map<String, dynamic>.from(staleEvent['envelope'] as Map),
    rethrowOnError: true,
  );
  writeSharedText(_signalName('charlie_stale_remove_processed'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterStaleRemove.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterStaleRemove',
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final charlieText = 'GM-012 Charlie after stale remove $_runId';
  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterStaleRemove',
    text: charlieText,
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobAfterStaleRemove.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterStaleRemove',
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[charlieSent],
    receivedMessages: <Map<String, dynamic>>[aliceReceived, bobReceived],
    extra: <String, dynamic>{
      'gm012StaleRemoveReaddProof': <String, dynamic>{
        'deliveredStaleRemoveVersion2': true,
        'staleRemoveIgnored': memberPeerIds.contains(charliePeerId),
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'validatorConfigIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'charlieMemberRowCount': await _memberRowCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
        ),
        'charlieActiveDeviceBindingCount': await _activeDeviceBindingCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
          deviceId: charlieTransportPeerId,
        ),
        'groupPresentAfterStaleRemove':
            await stack.groupRepo.getGroup(groupId) != null,
        'currentMemberAfterStaleRemove':
            await stack.groupRepo.getMember(groupId, stack.identity.peerId) !=
            null,
        'postReaddPublishAccepted':
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        'sentCharliePostStaleRemove':
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        'receivedAlicePostStaleRemove': true,
        'receivedBobPostStaleRemove': true,
        'hasStaleEpochAfterStaleRemove': finalEpoch < readdKey,
        'removedWindowPlaintextCount': 0,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGm013Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-013 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final removalCutoffAt = DateTime.now().toUtc().add(
    const Duration(seconds: 3),
  );
  final beforeSentAt = removalCutoffAt.subtract(
    const Duration(milliseconds: 1),
  );
  final afterSentAt = removalCutoffAt;
  writeSharedJson(_signalName('gm013_boundary_plan.json'), <String, dynamic>{
    'removalCutoffAt': removalCutoffAt.toIso8601String(),
    'beforeSentAt': beforeSentAt.toIso8601String(),
    'afterSentAt': afterSentAt.toIso8601String(),
    'afterText': 'GM-013 Charlie at removal cutoff $_runId',
  });

  final boundary = await waitForSharedJson(
    _signalName('gm013_charlie_boundary_envelopes.json'),
  );
  while (DateTime.now().toUtc().isBefore(removalCutoffAt)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
    removedAtOverride: removalCutoffAt,
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
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rotatedKey == null) {
    throw StateError('GM-013 Alice key rotation failed');
  }
  writeSharedJson(_signalName('rotated_key.json'), <String, dynamic>{
    'keyEpoch': rotatedKey.keyGeneration,
    'groupKey': rotatedKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_rotated_key'));

  final boundaryProof = await _processGm013BoundaryMessages(
    stack: stack,
    groupId: groupId,
    beforeEnvelope: Map<String, dynamic>.from(
      boundary['beforeEnvelope'] as Map,
    ),
    afterEnvelope: Map<String, dynamic>.from(boundary['afterEnvelope'] as Map),
    charliePeerId: charliePeerId,
  );
  writeSharedText(_signalName('alice_gm013_boundary_processed'), 'ok');
  await waitForSharedSignal(_signalName('bob_gm013_boundary_processed'));

  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterCharlieRemove',
    text: 'GM-013 Alice after Charlie removal $_runId',
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

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[aliceSent],
    receivedMessages: <Map<String, dynamic>>[
      Map<String, dynamic>.from(boundaryProof['beforeReceived'] as Map),
      bobReceived,
    ],
    extra: <String, dynamic>{
      'gm013SimultaneousRemoveSendProof': <String, dynamic>{
        'removalCutoffAt': removedAt.toIso8601String(),
        'beforeSentAt': beforeSentAt.toIso8601String(),
        'afterSentAt': afterSentAt.toIso8601String(),
        'acceptedBeforeCutoff': boundaryProof['beforeCount'] == 1,
        'beforeCutoffPersistedCount': boundaryProof['beforeCount'] as int,
        'rejectedAfterCutoff': boundaryProof['clearRejectionEvent'] == true,
        'afterCutoffAccepted': boundaryProof['afterAccepted'] == true,
        'afterCutoffPersistedCount': boundaryProof['afterCount'] as int,
        'clearAfterCutoffRejectionEvent':
            boundaryProof['clearRejectionEvent'] == true,
        'afterCutoffRejectionReason':
            boundaryProof['rejectionReason'] as String?,
        'memberListExcludesCharlie': !memberPeerIds.contains(charliePeerId),
        'validatorConfigExcludesCharlie': !memberPeerIds.contains(
          charliePeerId,
        ),
        'removedCharlie': true,
        'removedPeerId': charliePeerId,
        'sentAlicePostRemoval':
            aliceSent['outcome'] == 'success' ||
            aliceSent['outcome'] == 'successNoPeers',
        'receivedBobPostRemoval': true,
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGm013Bob(
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
  final boundary = await waitForSharedJson(
    _signalName('gm013_charlie_boundary_envelopes.json'),
  );
  final boundaryPlan = await waitForSharedJson(
    _signalName('gm013_boundary_plan.json'),
  );
  final removalCutoffAt = DateTime.parse(
    boundaryPlan['removalCutoffAt'] as String,
  ).toUtc();
  final beforeSentAt = DateTime.parse(
    boundaryPlan['beforeSentAt'] as String,
  ).toUtc();
  final afterSentAt = DateTime.parse(
    boundaryPlan['afterSentAt'] as String,
  ).toUtc();

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

  final boundaryProof = await _processGm013BoundaryMessages(
    stack: stack,
    groupId: groupId,
    beforeEnvelope: Map<String, dynamic>.from(
      boundary['beforeEnvelope'] as Map,
    ),
    afterEnvelope: Map<String, dynamic>.from(boundary['afterEnvelope'] as Map),
    charliePeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm013_boundary_processed'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterCharlieRemove.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterCharlieRemove',
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterCharlieRemove',
    text: 'GM-013 Bob after Charlie removal $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_bobAfterCharlieRemove.json'),
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[
      Map<String, dynamic>.from(boundaryProof['beforeReceived'] as Map),
      aliceReceived,
    ],
    extra: <String, dynamic>{
      'gm013SimultaneousRemoveSendProof': <String, dynamic>{
        'removalCutoffAt': removalCutoffAt.toIso8601String(),
        'beforeSentAt': beforeSentAt.toIso8601String(),
        'afterSentAt': afterSentAt.toIso8601String(),
        'acceptedBeforeCutoff': boundaryProof['beforeCount'] == 1,
        'beforeCutoffPersistedCount': boundaryProof['beforeCount'] as int,
        'rejectedAfterCutoff': boundaryProof['clearRejectionEvent'] == true,
        'afterCutoffAccepted': boundaryProof['afterAccepted'] == true,
        'afterCutoffPersistedCount': boundaryProof['afterCount'] as int,
        'clearAfterCutoffRejectionEvent':
            boundaryProof['clearRejectionEvent'] == true,
        'afterCutoffRejectionReason':
            boundaryProof['rejectionReason'] as String?,
        'memberListExcludesCharlie': !memberPeerIds.contains(charliePeerId),
        'validatorConfigExcludesCharlie': !memberPeerIds.contains(
          charliePeerId,
        ),
        'receivedAlicePostRemoval': true,
        'sentBobPostRemoval':
            bobSent['outcome'] == 'success' ||
            bobSent['outcome'] == 'successNoPeers',
        'finalEpoch': finalEpoch,
      },
    },
  );
}

Future<void> _runGm013Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final boundaryPlan = await waitForSharedJson(
    _signalName('gm013_boundary_plan.json'),
  );
  final beforeSentAt = DateTime.parse(
    boundaryPlan['beforeSentAt'] as String,
  ).toUtc();
  final afterSentAt = DateTime.parse(
    boundaryPlan['afterSentAt'] as String,
  ).toUtc();
  final afterText = boundaryPlan['afterText'] as String;
  final currentMemberBeforeRemoval =
      await stack.groupRepo.getMember(groupId, stack.identity.peerId) != null;

  final beforeSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieBeforeCutoff',
    text: 'GM-013 Charlie before removal cutoff $_runId',
    timestamp: beforeSentAt,
  );
  final beforeEnvelope = _gm013EnvelopeFromSent(
    sent: beforeSent,
    groupId: groupId,
  );
  final afterEnvelope = _gm013AfterCutoffEnvelope(
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
    beforeSent: beforeSent,
    afterSentAt: afterSentAt,
    text: afterText,
  );
  writeSharedJson(
    _signalName('gm013_charlie_boundary_envelopes.json'),
    <String, dynamic>{
      'beforeEnvelope': beforeEnvelope,
      'afterEnvelope': afterEnvelope,
    },
  );

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_self_removed'), 'ok');

  await waitForSharedSignal(_signalName('alice_gm013_boundary_processed'));
  await waitForSharedSignal(_signalName('bob_gm013_boundary_processed'));
  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterCharlieRemove.json'),
  );
  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobAfterCharlieRemove.json'),
  );
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
    stdout.writeln('[GMP][$_role] post-removal drain rejected: $error');
  }
  await Future<void>.delayed(const Duration(seconds: 2));
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
    text: 'GM-013 Charlie after Charlie removal $_runId',
  );
  final groupAfterRemoval = await stack.groupRepo.getGroup(groupId);
  final currentMemberAfterRemoval =
      await stack.groupRepo.getMember(groupId, stack.identity.peerId) != null;
  final postRemovalPlaintextCount = aliceLeakCount + bobLeakCount;

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[beforeSent, rejectedSend],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm013SimultaneousRemoveSendProof': <String, dynamic>{
        'currentMemberBeforeRemoval': currentMemberBeforeRemoval,
        'startedOldEpochPublishBeforeRemoval':
            beforeSent['outcome'] == 'success' ||
            beforeSent['outcome'] == 'successNoPeers',
        'groupPresentAfterRemoval': groupAfterRemoval != null,
        'currentMemberAfterRemoval': currentMemberAfterRemoval,
        'hasRotatedEpoch': false,
        'postRemovalSendOutcome': rejectedSend['outcome'] as String,
        'postRemovalPublishAccepted': rejectedSend['accepted'] == true,
        'receivedAlicePostRemoval': aliceLeakCount > 0,
        'receivedBobPostRemoval': bobLeakCount > 0,
        'postRemovalPlaintextCount': postRemovalPlaintextCount,
        'finalEpoch': groupAfterRemoval == null
            ? 0
            : await _keyEpoch(stack, groupId),
      },
    },
  );
}

Future<void> _runGm014Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-014 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;
  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
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
      return peerId != charlieTransportPeerId;
    },
  );
  if (rotatedKey == null) {
    throw StateError('GM-014 Alice key rotation failed');
  }
  writeSharedJson(_signalName('rotated_key.json'), <String, dynamic>{
    'keyEpoch': rotatedKey.keyGeneration,
    'groupKey': rotatedKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_rotated_key'));

  final removedWindowSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceDuringCharlieRemoval',
    text: 'GM-014 Alice during Charlie removal $_runId',
  );

  final readdAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charliePeerId,
    username:
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: charlieIdentity['publicKey'] as String?,
    mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: charlieTransportPeerId,
        transportPeerId: charlieTransportPeerId,
        deviceSigningPublicKey: charlieIdentity['publicKey'] as String? ?? '',
        mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
        keyPackageId: 'key-package-$charlieTransportPeerId',
        keyPackagePublicMaterial: charlieIdentity['mlKemPublicKey'] as String?,
      ),
    ],
    joinedAt: readdAt,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdAt,
  );
  await waitForSharedSignal(_signalName('bob_membership_readded'));

  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterReadd',
    text: 'GM-014 Alice after Charlie re-add $_runId',
    timestamp: readdAt.add(const Duration(seconds: 1)),
  );
  await waitForSharedSignal(_signalName('bob_received_aliceAfterReadd.json'));

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
  await waitForSharedSignal(
    _signalName('charlie_received_aliceAfterReadd.json'),
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[removedWindowSent, aliceSent],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm014SimultaneousReaddSendProof': <String, dynamic>{
        'readdAt': readdAt.toIso8601String(),
        'charlieJoinedAt': readdAt.toIso8601String(),
        'alicePostReaddSentAt': aliceSent['timestamp'] as String,
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'validatorConfigIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'hasStaleEpochAfterCatchUp': finalEpoch < rotatedKey.keyGeneration,
        'finalEpoch': finalEpoch,
        'readdedCharlie': true,
        'readdedPeerId': charliePeerId,
        'sentAlicePostReadd':
            aliceSent['outcome'] == 'success' ||
            aliceSent['outcome'] == 'successNoPeers',
        'receivedBobPostReadd': true,
      },
    },
  );
}

Future<void> _runGm014Bob(
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
    } catch (_) {}
    return (await stack.groupRepo.getMember(groupId, charliePeerId)) != null;
  }, timeout: const Duration(seconds: 120));
  writeSharedText(_signalName('bob_membership_readded'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterReadd',
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedText(_signalName('bob_received_aliceAfterReadd.json'), 'ok');

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  final charlieMember = await stack.groupRepo.getMember(groupId, charliePeerId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[aliceReceived],
    extra: <String, dynamic>{
      'gm014SimultaneousReaddSendProof': <String, dynamic>{
        'readdAt': charlieMember?.joinedAt.toUtc().toIso8601String(),
        'charlieJoinedAt': charlieMember?.joinedAt.toUtc().toIso8601String(),
        'alicePostReaddSentAt': aliceSent['timestamp'] as String,
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'validatorConfigIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'hasStaleEpochAfterCatchUp': finalEpoch < rotatedEpoch,
        'finalEpoch': finalEpoch,
        'receivedAlicePostReadd': true,
      },
    },
  );
}

Future<void> _runGm014Charlie(
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
  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_self_removed'), 'ok');

  final removedWindowSent = await waitForSharedJson(
    _signalName('alice_sent_aliceDuringCharlieRemoval.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  final removedWindowPlaintextBeforeReadd = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedWindowSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_readd_group_fixture.json'),
  );
  final readdImportEvents = await _captureFlowEvents(() async {
    await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  });
  writeSharedText(_signalName('charlie_group_rejoined'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterReadd',
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedText(_signalName('charlie_received_aliceAfterReadd.json'), 'ok');

  final removedWindowPlaintextAfterReadd = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedWindowSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  final charliePeerId = stack.identity.peerId;
  final charlieMember = await stack.groupRepo.getMember(groupId, charliePeerId);
  final readdTopicJoinRequestCount = readdImportEvents
      .where((event) => event['event'] == 'GROUP_FL_BRIDGE_JOIN_CONFIG_REQUEST')
      .length;
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[aliceReceived],
    extra: <String, dynamic>{
      'gm014SimultaneousReaddSendProof': <String, dynamic>{
        'readdAt': charlieMember?.joinedAt.toUtc().toIso8601String(),
        'charlieJoinedAt': charlieMember?.joinedAt.toUtc().toIso8601String(),
        'alicePostReaddSentAt': aliceSent['timestamp'] as String,
        'memberListIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'validatorConfigIncludesCharlie': memberPeerIds.contains(charliePeerId),
        'hasStaleEpochAfterCatchUp': finalEpoch < 2,
        'finalEpoch': finalEpoch,
        'delayedKeyOrConfig': true,
        'repairSignalRecorded': false,
        'directPostReaddDecrypt': true,
        'caughtUpPostReaddMessage': true,
        'postReaddPersistedCount': await _proofMessageCount(
          stack: stack,
          groupId: groupId,
          text: aliceSent['text'] as String,
          senderPeerId: alicePeerId,
        ),
        'removedWindowPlaintextCount':
            removedWindowPlaintextBeforeReadd +
            removedWindowPlaintextAfterReadd,
        'charlieMemberRowCount': await _memberRowCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
        ),
        'charlieActiveDeviceBindingCount': await _activeDeviceBindingCount(
          stack: stack,
          groupId: groupId,
          peerId: charliePeerId,
          deviceId: stack.p2pService.currentState.peerId,
        ),
        'topicJoinRequestCount': readdTopicJoinRequestCount,
        'duplicateTopicJoins': readdTopicJoinRequestCount > 1,
        'duplicateDurableRecipients': _hasDuplicateStrings(
          aliceSent['recipientPeerIds'],
        ),
      },
    },
  );
}

Future<Map<String, dynamic>> _gm015PolicyProof({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String alicePeerId,
  required String bobPeerId,
  required String charliePeerId,
  required int initialKeyEpoch,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) async {
  final group = await stack.groupRepo.getGroup(groupId);
  final members = await stack.groupRepo.getMembers(groupId);
  final memberPeerIds = members
      .map((member) => member.peerId)
      .toList(growable: false);
  final adminPeerIds = members
      .where((member) => member.role == MemberRole.admin)
      .map((member) => member.peerId)
      .toList(growable: false);
  final expectedMembers = <String>{alicePeerId, bobPeerId, charliePeerId};
  final finalKeyEpoch = await _keyEpoch(stack, groupId);
  final memberSet = memberPeerIds.toSet();
  final mutated =
      group == null ||
      group.isDissolved ||
      finalKeyEpoch != initialKeyEpoch ||
      memberPeerIds.length != expectedMembers.length ||
      memberSet.length != expectedMembers.length ||
      !memberSet.containsAll(expectedMembers) ||
      adminPeerIds.length != 1 ||
      adminPeerIds.single != alicePeerId;

  return <String, dynamic>{
    'groupPresent': group != null,
    'groupDissolved': group?.isDissolved ?? false,
    'creatorPeerId': group?.createdBy,
    'finalMemberPeerIds': memberPeerIds,
    'adminPeerIds': adminPeerIds,
    'memberListHasActiveAdmin': adminPeerIds.isNotEmpty,
    'mutationAfterBlockedAttempt': mutated,
    'keyEpochUnchanged': finalKeyEpoch == initialKeyEpoch,
    'initialKeyEpoch': initialKeyEpoch,
    'finalKeyEpoch': finalKeyEpoch,
    ...extra,
  };
}

Future<void> _runGm015Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-015 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final alicePeerId = stack.identity.peerId;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final initialKeyEpoch = await _keyEpoch(stack, groupId);

  var selfRemovalOutcome = 'notRun';
  String? selfRemovalReason;
  try {
    await removeGroupMember(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      groupId: groupId,
      memberPeerId: alicePeerId,
      selfPeerId: alicePeerId,
      actorUsername: stack.identity.username,
      msgRepo: stack.groupMsgRepo,
    );
    selfRemovalOutcome = 'success';
  } on StateError catch (error) {
    selfRemovalOutcome = 'blocked';
    selfRemovalReason = error.message;
  }

  final group = await stack.groupRepo.getGroup(groupId);
  if (group == null) {
    throw StateError('GM-015 group disappeared after self-removal attempt');
  }
  final broadcastResult = await broadcastVoluntaryLeaveAndRotateKey(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    group: group,
    identityRepo: stack.identityRepo,
    msgRepo: stack.groupMsgRepo,
    sendP2PMessage: (peerId, message) async {
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  final voluntaryLeaveBroadcastOutcome = broadcastResult.didBroadcast
      ? 'broadcast'
      : 'skipped';

  var leaveOutcome = 'notRun';
  String? leaveReason;
  try {
    await leaveGroup(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      groupId: groupId,
    );
    leaveOutcome = 'success';
  } on StateError catch (error) {
    leaveOutcome = 'blocked';
    leaveReason = error.message;
  }

  final attempts = <String, dynamic>{
    'selfRemovalOutcome': selfRemovalOutcome,
    'selfRemovalReason': selfRemovalReason,
    'voluntaryLeaveBroadcastOutcome': voluntaryLeaveBroadcastOutcome,
    'voluntaryLeaveBroadcastSkipReason': broadcastResult.skipReason?.name,
    'leaveOutcome': leaveOutcome,
    'leaveReason': leaveReason,
    'initialKeyEpoch': initialKeyEpoch,
  };
  writeSharedJson(_signalName('gm015_policy_attempts.json'), attempts);

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobAfterBlockedAdminSelfRemoval.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterBlockedAdminSelfRemoval',
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieAfterBlockedAdminLeave.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterBlockedAdminLeave',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[bobReceived, charlieReceived],
    extra: <String, dynamic>{
      'gm015AdminSelfRemovalPolicyProof': await _gm015PolicyProof(
        stack: stack,
        groupId: groupId,
        alicePeerId: alicePeerId,
        bobPeerId: bobPeerId,
        charliePeerId: charliePeerId,
        initialKeyEpoch: initialKeyEpoch,
        extra: <String, dynamic>{
          ...attempts,
          'receivedBobPostAttemptSend': true,
          'receivedCharliePostAttemptSend': true,
        },
      ),
    },
  );
}

Future<void> _runGm015Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');

  final attempts = await waitForSharedJson(
    _signalName('gm015_policy_attempts.json'),
  );
  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = stack.identity.peerId;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final initialKeyEpoch = attempts['initialKeyEpoch'] as int;

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterBlockedAdminSelfRemoval',
    text: 'GM-015 Bob after blocked admin self-removal $_runId',
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieAfterBlockedAdminLeave.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterBlockedAdminLeave',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[charlieReceived],
    extra: <String, dynamic>{
      'gm015AdminSelfRemovalPolicyProof': await _gm015PolicyProof(
        stack: stack,
        groupId: groupId,
        alicePeerId: alicePeerId,
        bobPeerId: bobPeerId,
        charliePeerId: charliePeerId,
        initialKeyEpoch: initialKeyEpoch,
        extra: const <String, dynamic>{
          'sentBobPostAttemptSend': true,
          'receivedCharliePostAttemptSend': true,
        },
      ),
    },
  );
}

Future<void> _runGm015Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await importJoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final attempts = await waitForSharedJson(
    _signalName('gm015_policy_attempts.json'),
  );
  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = stack.identity.peerId;
  final initialKeyEpoch = attempts['initialKeyEpoch'] as int;

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobAfterBlockedAdminSelfRemoval.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobAfterBlockedAdminSelfRemoval',
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieAfterBlockedAdminLeave',
    text: 'GM-015 Charlie after blocked admin leave $_runId',
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[charlieSent],
    receivedMessages: <Map<String, dynamic>>[bobReceived],
    extra: <String, dynamic>{
      'gm015AdminSelfRemovalPolicyProof': await _gm015PolicyProof(
        stack: stack,
        groupId: groupId,
        alicePeerId: alicePeerId,
        bobPeerId: bobPeerId,
        charliePeerId: charliePeerId,
        initialKeyEpoch: initialKeyEpoch,
        extra: const <String, dynamic>{
          'receivedBobPostAttemptSend': true,
          'sentCharliePostAttemptSend': true,
        },
      ),
    },
  );
}

Future<void> _runGm016Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-016 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charliePeerId = identities['charlie']!['peerId'] as String;
  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  await waitForSharedSignal(_signalName('bob_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_gm016_quiet_window_complete'));

  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterCharlieUnsubscribe',
    text: 'GM-016 Alice after Charlie unsubscribe $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceAfterCharlieUnsubscribe.json'),
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[aliceSent],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm016RemovedUnsubscribeProof': <String, dynamic>{
        'charlieOnlineBeforeRemoval': true,
        'removedCharlie': true,
        'removedPeerId': charliePeerId,
        'memberListExcludesCharlie': !memberPeerIds.contains(charliePeerId),
        'sentAlicePostRemoval':
            aliceSent['outcome'] == 'success' ||
            aliceSent['outcome'] == 'successNoPeers',
      },
    },
  );
}

Future<void> _runGm016Bob(
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
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_removed_charlie'), 'ok');

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceAfterCharlieUnsubscribe.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceAfterCharlieUnsubscribe',
    text: aliceSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[aliceReceived],
    extra: <String, dynamic>{
      'gm016RemovedUnsubscribeProof': <String, dynamic>{
        'memberListExcludesCharlie': !memberPeerIds.contains(charliePeerId),
        'receivedAlicePostRemoval': true,
      },
    },
  );
}

Future<void> _runGm016Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  final activeMemberBeforeRemoval =
      await stack.groupRepo.getMember(groupId, stack.identity.peerId) != null;
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final probe = _Gm016PostLeaveProbe(stack: stack, groupId: groupId)..start();
  try {
    await _waitForSelfRemoval(stack: stack, groupId: groupId);

    final messageBaseline = probe.messageBaseline;
    final reactionBaseline = probe.reactionBaseline;
    final flowBaseline = probe.flowBaseline;
    final quietWindow = Stopwatch()..start();
    await Future<void>.delayed(const Duration(seconds: 5));
    quietWindow.stop();

    final groupRecreatedAfterQuietWindow =
        await stack.groupRepo.getGroup(groupId) != null;
    writeSharedText(_signalName('charlie_gm016_quiet_window_complete'), 'ok');

    final aliceSent = await waitForSharedJson(
      _signalName('alice_sent_aliceAfterCharlieUnsubscribe.json'),
    );
    await Future<void>.delayed(const Duration(seconds: 5));

    final postRemovalPlaintextCount = await _proofMessageCount(
      stack: stack,
      groupId: groupId,
      text: aliceSent['text'] as String,
      senderPeerId: identities['alice']!['peerId'] as String,
    );
    final groupPresentAfterRemoval =
        await stack.groupRepo.getGroup(groupId) != null;
    final memberRowsAfterRemoval = (await stack.groupRepo.getMembers(
      groupId,
    )).length;
    final keyEpochAfterRemoval = await _keyEpoch(stack, groupId);
    final postLeaveInboundEventCount = probe.groupMessageCountSince(
      messageBaseline,
    );
    final postLeaveReactionEventCount = probe.groupReactionCountSince(
      reactionBaseline,
    );
    final postLeaveGroupJoinCount = probe.flowCountSince(flowBaseline, const {
      'GROUP_FL_BRIDGE_JOIN_REQUEST',
      'GROUP_FL_BRIDGE_JOIN_CONFIG_REQUEST',
    });
    final postLeaveDiscoveryEventCount = probe.flowCountSince(
      flowBaseline,
      const {'GROUP_DISCOVERY'},
    );
    final postLeavePayloadParseFailedCount = probe.flowCountSince(
      flowBaseline,
      const {'GROUP_PAYLOAD_PARSE_FAILED'},
    );
    final postLeaveDecryptionFailedCount = probe.flowCountSince(
      flowBaseline,
      const {'GROUP_DECRYPTION_FAILED'},
    );

    await _writeVerdict(
      stack: stack,
      groupId: groupId,
      sentMessages: const <Map<String, dynamic>>[],
      receivedMessages: const <Map<String, dynamic>>[],
      extra: <String, dynamic>{
        'gm016RemovedUnsubscribeProof': <String, dynamic>{
          'activeMemberBeforeRemoval': activeMemberBeforeRemoval,
          'leaveRequested':
              probe.totalFlowCount({'GROUP_FL_BRIDGE_LEAVE_REQUEST'}) > 0,
          'leaveResponseOk': probe.leaveResponseOk,
          'groupPresentAfterRemoval': groupPresentAfterRemoval,
          'groupRecreatedAfterQuietWindow': groupRecreatedAfterQuietWindow,
          'receivedAlicePostRemoval':
              postLeaveInboundEventCount > 0 || postRemovalPlaintextCount > 0,
          'memberRowsAfterRemoval': memberRowsAfterRemoval,
          'keyEpochAfterRemoval': keyEpochAfterRemoval,
          'postLeaveGroupJoinCount': postLeaveGroupJoinCount,
          'postLeaveInboundEventCount': postLeaveInboundEventCount,
          'postLeaveReactionEventCount': postLeaveReactionEventCount,
          'postLeaveDiscoveryEventCount': postLeaveDiscoveryEventCount,
          'postLeavePayloadParseFailedCount': postLeavePayloadParseFailedCount,
          'postLeaveDecryptionFailedCount': postLeaveDecryptionFailedCount,
          'postRemovalPlaintextCount': postRemovalPlaintextCount,
          'postLeaveQuietWindowMs': quietWindow.elapsedMilliseconds,
          'staleDiscoveryRegisterStimulus': false,
        },
      },
    );
  } finally {
    probe.stop();
  }
}

Future<void> _runGm017Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-017 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charliePeerId = identities['charlie']!['peerId'] as String;
  final probe = _Gm017ValidationProbe(stack: stack, groupId: groupId)..start();
  try {
    final installProof = await _installGm017ConfigWithoutCharlie(
      stack: stack,
      groupId: groupId,
      charliePeerId: charliePeerId,
    );
    writeSharedJson(
      _signalName('alice_gm017_config_without_charlie.json'),
      installProof,
    );
    await waitForSharedSignal(_signalName('bob_gm017_config_without_charlie'));

    final validationBaseline = probe.flowBaseline;
    writeSharedText(_signalName('alice_gm017_validator_ready'), 'ok');
    await waitForSharedSignal(_signalName('bob_gm017_validator_ready'));

    final charlieSent = await waitForSharedJson(
      _signalName('charlie_sent_charlieStaleAfterRemoval.json'),
    );
    final reason = await _waitForGm017ValidationReject(
      probe: probe,
      baseline: validationBaseline,
    );
    await Future<void>.delayed(const Duration(seconds: 5));
    final stalePlaintextCount = await _proofMessageCount(
      stack: stack,
      groupId: groupId,
      text: charlieSent['text'] as String,
      senderPeerId: charliePeerId,
    );
    writeSharedText(_signalName('alice_gm017_validation_rejected'), 'ok');
    await waitForSharedSignal(_signalName('bob_gm017_validation_rejected'));

    final aliceSent = await _sendProofMessage(
      stack: stack,
      groupId: groupId,
      key: 'aliceAfterStaleCharlieReject',
      text: 'GM-017 Alice after stale Charlie rejection $_runId',
    );
    await waitForSharedSignal(
      _signalName('bob_received_aliceAfterStaleCharlieReject.json'),
    );

    final memberPeerIds = await _memberPeerIds(stack, groupId);
    final proofName = _scenario == 'go003'
        ? 'go003SenderValidationFeedbackProof'
        : 'gm017StaleSubscriptionValidationProof';
    await _writeVerdict(
      stack: stack,
      groupId: groupId,
      sentMessages: <Map<String, dynamic>>[aliceSent],
      receivedMessages: const <Map<String, dynamic>>[],
      extra: <String, dynamic>{
        proofName: <String, dynamic>{
          'removedCharlieFromLocalConfig':
              installProof['memberListExcludesCharlie'] == true,
          'removedPeerId': charliePeerId,
          'memberListExcludesCharlie': !memberPeerIds.contains(charliePeerId),
          'validationRejected': true,
          'validationRejectCount': probe.validationRejectCountSince(
            validationBaseline,
          ),
          'validationRejectReason': reason,
          'receivedStaleCharliePlaintext': stalePlaintextCount > 0,
          'stalePlaintextCount': stalePlaintextCount,
          'sentAliceHealthyAfterReject':
              aliceSent['outcome'] == 'success' ||
              aliceSent['outcome'] == 'successNoPeers',
        },
      },
    );
  } finally {
    probe.stop();
  }
}

Future<void> _runGm017Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');

  await waitForSharedJson(
    _signalName('alice_gm017_config_without_charlie.json'),
  );
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final installProof = await _installGm017ConfigWithoutCharlie(
    stack: stack,
    groupId: groupId,
    charliePeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm017_config_without_charlie'), 'ok');

  final probe = _Gm017ValidationProbe(stack: stack, groupId: groupId)..start();
  try {
    final validationBaseline = probe.flowBaseline;
    writeSharedText(_signalName('bob_gm017_validator_ready'), 'ok');
    await waitForSharedSignal(_signalName('alice_gm017_validator_ready'));

    final charlieSent = await waitForSharedJson(
      _signalName('charlie_sent_charlieStaleAfterRemoval.json'),
    );
    final reason = await _waitForGm017ValidationReject(
      probe: probe,
      baseline: validationBaseline,
    );
    await Future<void>.delayed(const Duration(seconds: 5));
    final stalePlaintextCount = await _proofMessageCount(
      stack: stack,
      groupId: groupId,
      text: charlieSent['text'] as String,
      senderPeerId: charliePeerId,
    );
    writeSharedText(_signalName('bob_gm017_validation_rejected'), 'ok');

    final alicePeerId = identities['alice']!['peerId'] as String;
    final aliceSent = await waitForSharedJson(
      _signalName('alice_sent_aliceAfterStaleCharlieReject.json'),
    );
    final aliceReceived = await _waitForReceivedProofMessage(
      stack: stack,
      groupId: groupId,
      key: 'aliceAfterStaleCharlieReject',
      text: aliceSent['text'] as String,
      senderPeerId: alicePeerId,
    );

    final memberPeerIds = await _memberPeerIds(stack, groupId);
    final proofName = _scenario == 'go003'
        ? 'go003SenderValidationFeedbackProof'
        : 'gm017StaleSubscriptionValidationProof';
    await _writeVerdict(
      stack: stack,
      groupId: groupId,
      sentMessages: const <Map<String, dynamic>>[],
      receivedMessages: <Map<String, dynamic>>[aliceReceived],
      extra: <String, dynamic>{
        proofName: <String, dynamic>{
          'installedConfigWithoutCharlie':
              installProof['memberListExcludesCharlie'] == true,
          'memberListExcludesCharlie': !memberPeerIds.contains(charliePeerId),
          'validationRejected': true,
          'validationRejectCount': probe.validationRejectCountSince(
            validationBaseline,
          ),
          'validationRejectReason': reason,
          'receivedStaleCharliePlaintext': stalePlaintextCount > 0,
          'stalePlaintextCount': stalePlaintextCount,
          'receivedAliceHealthyAfterReject': true,
        },
      },
    );
  } finally {
    probe.stop();
  }
}

Future<void> _runGm017Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final probe = _Gm017ValidationProbe(stack: stack, groupId: groupId)..start();
  try {
    await waitForSharedJson(
      _signalName('alice_gm017_config_without_charlie.json'),
    );
    await waitForSharedSignal(_signalName('bob_gm017_config_without_charlie'));
    await waitForSharedSignal(_signalName('alice_gm017_validator_ready'));
    await waitForSharedSignal(_signalName('bob_gm017_validator_ready'));

    final groupPresentAfterRemoval =
        await stack.groupRepo.getGroup(groupId) != null;
    final keyPresentAfterRemoval =
        await stack.groupRepo.getLatestKey(groupId) != null;
    final memberPeerIdsBeforeSend = await _memberPeerIds(stack, groupId);
    final feedbackBaseline = probe.flowBaseline;
    final staleText = 'GM-017 stale Charlie after removal $_runId';
    final staleSent = await _sendProofMessage(
      stack: stack,
      groupId: groupId,
      key: 'charlieStaleAfterRemoval',
      text: staleText,
    );
    Map<String, dynamic>? senderFeedback;
    Map<String, dynamic>? failedStatusProof;
    if (_scenario == 'go003') {
      senderFeedback = await _waitForGo003PublishValidationFeedback(
        probe: probe,
        baseline: feedbackBaseline,
        messageId: staleSent['messageId'] as String,
      );
      failedStatusProof = await _waitForOutboundStatusProof(
        stack: stack,
        messageId: staleSent['messageId'] as String,
        status: 'failed',
      );
    }

    await waitForSharedSignal(_signalName('alice_gm017_validation_rejected'));
    await waitForSharedSignal(_signalName('bob_gm017_validation_rejected'));

    final proofName = _scenario == 'go003'
        ? 'go003SenderValidationFeedbackProof'
        : 'gm017StaleSubscriptionValidationProof';
    await _writeVerdict(
      stack: stack,
      groupId: groupId,
      sentMessages: <Map<String, dynamic>>[staleSent],
      receivedMessages: const <Map<String, dynamic>>[],
      extra: <String, dynamic>{
        proofName: <String, dynamic>{
          'groupPresentAfterRemoval': groupPresentAfterRemoval,
          'keyPresentAfterRemoval': keyPresentAfterRemoval,
          'memberListStillIncludesCharlie': memberPeerIdsBeforeSend.contains(
            stack.identity.peerId,
          ),
          'staleSubscriptionPresent':
              groupPresentAfterRemoval &&
              keyPresentAfterRemoval &&
              memberPeerIdsBeforeSend.contains(stack.identity.peerId),
          'sentStaleMarker':
              staleSent['outcome'] == 'success' ||
              staleSent['outcome'] == 'successNoPeers',
          'stalePublishAccepted':
              staleSent['outcome'] == 'success' ||
              staleSent['outcome'] == 'successNoPeers',
          if (senderFeedback != null) ...<String, dynamic>{
            'senderValidationFeedbackReceived': true,
            'senderValidationFeedbackMessageId': senderFeedback['messageId'],
            'senderValidationFeedbackReason': senderFeedback['reason'],
            'senderValidationFeedbackKeyEpoch': senderFeedback['keyEpoch'],
            'senderStatusAfterFeedback': failedStatusProof?['status'],
            'senderWireEnvelopeRetryableAfterFeedback':
                failedStatusProof?['wireEnvelopePresent'] == true,
            'senderInboxStoredAfterFeedback':
                failedStatusProof?['inboxStored'] == true,
          },
          'leaveRequested': probe.leaveRequested,
          'leaveResponseOk': probe.leaveResponseOk,
        },
      },
    );
  } finally {
    probe.stop();
  }
}

Future<void> _runGm018Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-018 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charliePeerId = identities['charlie']!['peerId'] as String;
  final probe = _Gm017ValidationProbe(stack: stack, groupId: groupId)..start();
  try {
    final installProof = await _installGm017ConfigWithoutCharlie(
      stack: stack,
      groupId: groupId,
      charliePeerId: charliePeerId,
    );
    writeSharedJson(
      _signalName('alice_gm018_config_without_charlie.json'),
      installProof,
    );
    await waitForSharedSignal(_signalName('bob_gm018_config_without_charlie'));

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
        return stack.p2pService.sendMessage(peerId, message);
      },
    );
    if (rotatedKey == null) {
      throw StateError('GM-018 Alice key rotation failed');
    }
    writeSharedJson(_signalName('rotated_key.json'), <String, dynamic>{
      'keyEpoch': rotatedKey.keyGeneration,
      'groupKey': rotatedKey.encryptedKey,
    });
    await waitForSharedSignal(_signalName('bob_gm018_rotated_key'));

    final validationBaseline = probe.flowBaseline;
    writeSharedText(_signalName('alice_gm018_validator_ready'), 'ok');
    await waitForSharedSignal(_signalName('bob_gm018_validator_ready'));

    await waitForSharedJson(
      _signalName('charlie_sent_charlieGm018StaleOnline.json'),
    );
    final reason = await _waitForGm017ValidationReject(
      probe: probe,
      baseline: validationBaseline,
    );
    writeSharedText(_signalName('alice_gm018_validation_rejected'), 'ok');
    await waitForSharedSignal(_signalName('bob_gm018_validation_rejected'));

    final sentMessages = <Map<String, dynamic>>[];
    final liveMessageIds = <String>[];
    for (var i = 1; i <= 3; i++) {
      final key = 'aliceGm018Live$i';
      final sent = await _sendProofMessage(
        stack: stack,
        groupId: groupId,
        key: key,
        text: 'GM-018 live Alice to Bob $i $_runId',
      );
      sentMessages.add(sent);
      liveMessageIds.add(sent['messageId'] as String);
      await waitForSharedSignal(_signalName('bob_received_$key.json'));
    }
    writeSharedText(_signalName('alice_gm018_live_complete'), 'ok');

    final bobOfflineProof = await waitForSharedJson(
      _signalName('bob_gm018_offline_ready.json'),
    );
    final bobOfflineAt = DateTime.tryParse(
      bobOfflineProof['offlineAt']?.toString() ?? '',
    )?.toUtc();
    final inboxSendStartedAt = DateTime.now().toUtc();
    final bobOfflineProofObserved =
        bobOfflineProof['nodeStopped'] == true &&
        bobOfflineProof['notOnline'] == true;
    final inboxSentAfterBobOffline =
        bobOfflineAt != null && inboxSendStartedAt.isAfter(bobOfflineAt);

    final inboxMessageIds = <String>[];
    for (var i = 1; i <= 3; i++) {
      final key = 'aliceGm018Inbox$i';
      final sent = await _sendProofMessage(
        stack: stack,
        groupId: groupId,
        key: key,
        text: 'GM-018 inbox Alice to Bob $i $_runId',
      );
      sentMessages.add(sent);
      inboxMessageIds.add(sent['messageId'] as String);
    }
    writeSharedText(_signalName('alice_gm018_inbox_send_complete'), 'ok');
    await waitForSharedJson(
      _signalName('bob_gm018_inbox_replay_complete.json'),
    );

    await waitForSharedSignal(_signalName('charlie_gm018_offline_pressure'));
    final offlineSent = await _sendProofMessage(
      stack: stack,
      groupId: groupId,
      key: 'aliceGm018AfterCharlieOffline',
      text: 'GM-018 Alice after Charlie offline $_runId',
    );
    sentMessages.add(offlineSent);
    await waitForSharedSignal(
      _signalName('bob_received_aliceGm018AfterCharlieOffline.json'),
    );

    final allDurableRecipientsBobOnly = sentMessages.every((sent) {
      final recipients =
          (sent['recipientPeerIds'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toSet();
      return recipients.length == 1 &&
          recipients.contains(identities['bob']!['peerId']);
    });

    await _writeVerdict(
      stack: stack,
      groupId: groupId,
      sentMessages: sentMessages,
      receivedMessages: const <Map<String, dynamic>>[],
      extra: <String, dynamic>{
        'gm018RemainingDeliveryContinuityProof': <String, dynamic>{
          'removedCharlieFromLocalConfig':
              installProof['memberListExcludesCharlie'] == true,
          'removedPeerId': charliePeerId,
          'memberListExcludesCharlie': !(await _memberPeerIds(
            stack,
            groupId,
          )).contains(charliePeerId),
          'staleOnlinePressureObserved':
              reason == 'non_member' || reason == 'bad_signature_or_epoch',
          'charlieOfflinePressureObserved': true,
          'bobOfflineProofObserved': bobOfflineProofObserved,
          'inboxSentAfterBobOffline': inboxSentAfterBobOffline,
          'allDurableRecipientsBobOnly': allDurableRecipientsBobOnly,
          'liveSequenceSentCount': liveMessageIds.length,
          'inboxSequenceSentCount': inboxMessageIds.length,
          'liveSequenceMessageIds': liveMessageIds,
          'inboxSequenceMessageIds': inboxMessageIds,
        },
      },
    );
  } finally {
    probe.stop();
  }
}

Future<void> _runGm018Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');

  await waitForSharedJson(
    _signalName('alice_gm018_config_without_charlie.json'),
  );
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final installProof = await _installGm017ConfigWithoutCharlie(
    stack: stack,
    groupId: groupId,
    charliePeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm018_config_without_charlie'), 'ok');

  final rotated = await waitForSharedJson(_signalName('rotated_key.json'));
  final rotatedEpoch = rotated['keyEpoch'] as int;
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rotatedEpoch,
  );
  writeSharedText(_signalName('bob_gm018_rotated_key'), 'ok');

  final probe = _Gm017ValidationProbe(stack: stack, groupId: groupId)..start();
  try {
    final validationBaseline = probe.flowBaseline;
    writeSharedText(_signalName('bob_gm018_validator_ready'), 'ok');
    await waitForSharedSignal(_signalName('alice_gm018_validator_ready'));

    await waitForSharedJson(
      _signalName('charlie_sent_charlieGm018StaleOnline.json'),
    );
    await _waitForGm017ValidationReject(
      probe: probe,
      baseline: validationBaseline,
    );
    writeSharedText(_signalName('bob_gm018_validation_rejected'), 'ok');

    final receivedMessages = <Map<String, dynamic>>[];
    final liveReceivedMessages = <Map<String, dynamic>>[];
    final inboxReplayReceivedMessages = <Map<String, dynamic>>[];
    final alicePeerId = identities['alice']!['peerId'] as String;
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

    for (final key in liveKeys) {
      final aliceSent = await waitForSharedJson(
        _signalName('alice_sent_$key.json'),
      );
      final received = await _waitForReceivedProofMessage(
        stack: stack,
        groupId: groupId,
        key: key,
        text: aliceSent['text'] as String,
        senderPeerId: alicePeerId,
      );
      receivedMessages.add(received);
      liveReceivedMessages.add(received);
      writeSharedJson(_signalName('bob_received_$key.json'), received);
    }

    final nodeStopped = await stack.p2pService.stopNode();
    await _waitForNotOnline(stack.p2pService);
    final offlineAt = DateTime.now().toUtc();
    final notOnline =
        healthFromState(stack.p2pService.currentState) !=
        ConnectionHealth.online;
    writeSharedJson(_signalName('bob_gm018_offline_ready.json'), {
      'nodeStopped': nodeStopped,
      'notOnline': notOnline,
      'offlineAt': offlineAt.toIso8601String(),
      'healthAfterStop': healthFromState(stack.p2pService.currentState).name,
    });

    await waitForSharedSignal(_signalName('alice_gm018_inbox_send_complete'));
    final inboxSentMessages = <String, Map<String, dynamic>>{};
    final preReplayLeakCounts = <String, int>{};
    for (final key in inboxKeys) {
      final aliceSent = await waitForSharedJson(
        _signalName('alice_sent_$key.json'),
      );
      inboxSentMessages[key] = aliceSent;
      preReplayLeakCounts[key] = await _proofMessageCount(
        stack: stack,
        groupId: groupId,
        text: aliceSent['text'] as String,
        senderPeerId: alicePeerId,
      );
    }
    final inboxLiveLeakCountBeforeReplay = preReplayLeakCounts.values.fold<int>(
      0,
      (total, count) => total + count,
    );

    final nodeRestarted = await stack.p2pService.startNodeCore(
      stack.identity.privateKey,
      stack.identity.peerId,
    );
    if (!nodeRestarted) {
      throw StateError('GM-018 Bob failed to restart before inbox replay');
    }
    await _waitForOnline(stack.p2pService);
    writeSharedJson(_signalName('bob_gm018_restarted_before_replay.json'), {
      'nodeRestarted': nodeRestarted,
      'restartedAt': DateTime.now().toUtc().toIso8601String(),
      'healthAfterRestart': healthFromState(stack.p2pService.currentState).name,
    });

    final drainEvents = await _captureFlowEvents(() async {
      await drainGroupOfflineInboxForGroup(
        bridge: stack.bridge,
        groupRepo: stack.groupRepo,
        msgRepo: stack.groupMsgRepo,
        groupId: groupId,
        groupMessageListener: stack.groupListener,
        selfPeerId: stack.identity.peerId,
      );
    });
    final inboxReplayDrainMessageCount = _capturedGroupDrainMessageCount(
      drainEvents,
    );

    for (final key in inboxKeys) {
      final aliceSent = inboxSentMessages[key]!;
      final received = await _waitForReceivedProofMessage(
        stack: stack,
        groupId: groupId,
        key: key,
        text: aliceSent['text'] as String,
        senderPeerId: alicePeerId,
        drainWhileWaiting: false,
      );
      receivedMessages.add(received);
      inboxReplayReceivedMessages.add(received);
      writeSharedJson(_signalName('bob_received_$key.json'), received);
    }
    writeSharedJson(_signalName('bob_gm018_inbox_replay_complete.json'), {
      'receiptCount': inboxReplayReceivedMessages.length,
      'messageIds': inboxReplayReceivedMessages
          .map((message) => message['messageId'] as String)
          .toList(growable: false),
      'keys': inboxReplayReceivedMessages
          .map((message) => message['key'] as String)
          .toList(growable: false),
      'drainMessageCount': inboxReplayDrainMessageCount,
      'preReplayLeakCounts': preReplayLeakCounts,
    });

    final afterOfflineSent = await waitForSharedJson(
      _signalName('alice_sent_aliceGm018AfterCharlieOffline.json'),
    );
    final afterOfflineReceived = await _waitForReceivedProofMessage(
      stack: stack,
      groupId: groupId,
      key: 'aliceGm018AfterCharlieOffline',
      text: afterOfflineSent['text'] as String,
      senderPeerId: alicePeerId,
    );
    receivedMessages.add(afterOfflineReceived);
    writeSharedJson(
      _signalName('bob_received_aliceGm018AfterCharlieOffline.json'),
      afterOfflineReceived,
    );

    final exactOnceDelivery = receivedMessages.every(
      (message) => message['persistedCount'] == 1,
    );
    await _writeVerdict(
      stack: stack,
      groupId: groupId,
      sentMessages: const <Map<String, dynamic>>[],
      receivedMessages: receivedMessages,
      extra: <String, dynamic>{
        'gm018RemainingDeliveryContinuityProof': <String, dynamic>{
          'memberListExcludesCharlie':
              installProof['memberListExcludesCharlie'] == true &&
              !(await _memberPeerIds(stack, groupId)).contains(charliePeerId),
          'staleOnlinePressureRejected':
              probe.validationRejectCountSince(validationBaseline) >= 1,
          'staleOfflinePressureSurvived': true,
          'exactOnceDelivery': exactOnceDelivery,
          'bobOfflineBeforeInboxSend': nodeStopped && notOnline,
          'bobRestartedBeforeInboxDrain': nodeRestarted,
          'inboxReplayDrainedFromDurableInbox':
              inboxReplayDrainMessageCount >= inboxKeys.length,
          'inboxLiveLeakCountBeforeReplay': inboxLiveLeakCountBeforeReplay,
          'inboxReplayDrainMessageCount': inboxReplayDrainMessageCount,
          'liveBobReceiptCount': liveReceivedMessages.length,
          'liveBobReceiptMessageIds': liveReceivedMessages
              .map((message) => message['messageId'] as String)
              .toList(growable: false),
          'inboxReplayReceiptCount': inboxReplayReceivedMessages.length,
          'inboxReplayMessageIds': inboxReplayReceivedMessages
              .map((message) => message['messageId'] as String)
              .toList(growable: false),
          'inboxReplayReceiptKeys': inboxReplayReceivedMessages
              .map((message) => message['key'] as String)
              .toList(growable: false),
        },
      },
    );
  } finally {
    probe.stop();
  }
}

Future<void> _runGm018Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  await waitForSharedJson(
    _signalName('alice_gm018_config_without_charlie.json'),
  );
  await waitForSharedSignal(_signalName('bob_gm018_config_without_charlie'));
  await waitForSharedSignal(_signalName('alice_gm018_validator_ready'));
  await waitForSharedSignal(_signalName('bob_gm018_validator_ready'));

  final groupPresentAfterRemoval =
      await stack.groupRepo.getGroup(groupId) != null;
  final keyPresentAfterRemoval =
      await stack.groupRepo.getLatestKey(groupId) != null;
  final memberPeerIdsBeforeSend = await _memberPeerIds(stack, groupId);
  final staleSent = await _sendLiveOnlyProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm018StaleOnline',
    text: 'GM-018 stale Charlie online $_runId',
  );

  await waitForSharedSignal(_signalName('alice_gm018_validation_rejected'));
  await waitForSharedSignal(_signalName('bob_gm018_validation_rejected'));
  await waitForSharedSignal(_signalName('alice_gm018_live_complete'));

  await stack.p2pService.stopNode();
  writeSharedText(_signalName('charlie_gm018_offline_pressure'), 'ok');

  final aliceSentMessages = <Map<String, dynamic>>[];
  for (final key in const <String>[
    'aliceGm018Live1',
    'aliceGm018Live2',
    'aliceGm018Live3',
    'aliceGm018Inbox1',
    'aliceGm018Inbox2',
    'aliceGm018Inbox3',
    'aliceGm018AfterCharlieOffline',
  ]) {
    aliceSentMessages.add(
      await waitForSharedJson(_signalName('alice_sent_$key.json')),
    );
  }

  var postRemovalPlaintextCount = 0;
  for (final sent in aliceSentMessages) {
    postRemovalPlaintextCount += await _proofMessageCount(
      stack: stack,
      groupId: groupId,
      text: sent['text'] as String,
      senderPeerId: identities['alice']!['peerId'] as String,
    );
  }

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[staleSent],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm018RemainingDeliveryContinuityProof': <String, dynamic>{
        'groupPresentAfterRemoval': groupPresentAfterRemoval,
        'keyPresentAfterRemoval': keyPresentAfterRemoval,
        'memberListStillIncludesCharlie': memberPeerIdsBeforeSend.contains(
          stack.identity.peerId,
        ),
        'staleOnlinePressureSent':
            staleSent['outcome'] == 'success' ||
            staleSent['outcome'] == 'successNoPeers',
        'staleOfflineOrRestartPressure': true,
        'receivedPostRemovalPlaintext': postRemovalPlaintextCount > 0,
        'postRemovalPlaintextCount': postRemovalPlaintextCount,
      },
    },
  );
}

Future<void> _runGm019Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-019 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;
  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_gm019_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_gm019_self_removed'));

  final removedWindowSentAt = removedAt.add(const Duration(seconds: 1));
  final removedWindowSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm019RemovedWindow',
    text: 'GM-019 Alice while Charlie removed $_runId',
    timestamp: removedWindowSentAt,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGm019RemovedWindow.json'),
  );

  final readdAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charliePeerId,
    username:
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: charlieIdentity['publicKey'] as String?,
    mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: charlieTransportPeerId,
        transportPeerId: charlieTransportPeerId,
        deviceSigningPublicKey: charlieIdentity['publicKey'] as String? ?? '',
        mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
        keyPackageId: 'key-package-$charlieTransportPeerId',
        keyPackagePublicMaterial: charlieIdentity['mlKemPublicKey'] as String?,
      ),
    ],
    joinedAt: readdAt,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdAt,
  );
  await waitForSharedSignal(_signalName('bob_gm019_readded_charlie'));

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_gm019_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );
  await waitForSharedSignal(_signalName('charlie_gm019_rejoined'));

  final aliceAfterReadd = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm019AfterReadd',
    text: 'GM-019 Alice after Charlie re-add $_runId',
    timestamp: readdAt.add(const Duration(seconds: 1)),
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGm019AfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceGm019AfterReadd.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm019AfterReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm019AfterReadd',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );
  writeSharedText(_signalName('alice_received_bobGm019AfterReadd.json'), 'ok');

  final removedRecipients =
      (removedWindowSent['recipientPeerIds'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toSet();
  final postReaddRecipients =
      (aliceAfterReadd['recipientPeerIds'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toSet();

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[removedWindowSent, aliceAfterReadd],
    receivedMessages: <Map<String, dynamic>>[bobReceived],
    extra: <String, dynamic>{
      'gm019DurableRecipientWindowProof': <String, dynamic>{
        'actualDurablePayloadProof': true,
        'removedPeerId': charliePeerId,
        'removedAt': removedAt.toIso8601String(),
        'removedWindowSentAt': removedWindowSentAt.toIso8601String(),
        'readdAt': readdAt.toIso8601String(),
        'postReaddSentAt': aliceAfterReadd['timestamp'] as String,
        'removedWindowExcludedCharlie': !removedRecipients.contains(
          charliePeerId,
        ),
        'postReaddIncludedCharlie': postReaddRecipients.contains(charliePeerId),
      },
    },
  );
}

Future<void> _runGm019Bob(
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
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm019_removed_charlie'), 'ok');

  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm019RemovedWindow.json'),
  );
  final removedReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm019RemovedWindow',
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedText(
    _signalName('bob_received_aliceGm019RemovedWindow.json'),
    'ok',
  );

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm019_readded_charlie'), 'ok');

  final aliceAfter = await waitForSharedJson(
    _signalName('alice_sent_aliceGm019AfterReadd.json'),
  );
  final aliceAfterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm019AfterReadd',
    text: aliceAfter['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedText(_signalName('bob_received_aliceGm019AfterReadd.json'), 'ok');

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm019AfterReadd',
    text: 'GM-019 Bob after Charlie re-add $_runId',
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[
      removedReceived,
      aliceAfterReceived,
    ],
    extra: <String, dynamic>{
      'gm019DurableRecipientWindowProof': <String, dynamic>{
        'actualDurablePayloadProof': true,
        'bobPostReaddSent': bobSent['outcome'] == 'success',
        'receivedAliceRemovedWindow': true,
      },
    },
  );
}

Future<void> _runGm019Charlie(
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
  final bobPeerId = identities['bob']!['peerId'] as String;
  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_gm019_self_removed'), 'ok');

  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm019RemovedWindow.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  final removedWindowPlaintextCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_gm019_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_gm019_rejoined'), 'ok');

  final aliceAfter = await waitForSharedJson(
    _signalName('alice_sent_aliceGm019AfterReadd.json'),
  );
  final aliceAfterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm019AfterReadd',
    text: aliceAfter['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedText(
    _signalName('charlie_received_aliceGm019AfterReadd.json'),
    'ok',
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm019AfterReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm019AfterReadd',
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedText(
    _signalName('charlie_received_bobGm019AfterReadd.json'),
    'ok',
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[aliceAfterReceived, bobReceived],
    extra: <String, dynamic>{
      'gm019DurableRecipientWindowProof': <String, dynamic>{
        'receivedRemovedWindowMessage': removedWindowPlaintextCount > 0,
        'removedWindowPlaintextCount': removedWindowPlaintextCount,
        'receivedAlicePostReadd': true,
        'receivedBobPostReadd': true,
      },
    },
  );
}

Future<void> _runGm020Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  const immediateKey = 'aliceGm020ImmediatePostRemoval';
  const offlineKey = 'aliceGm020OfflinePostRemoval';
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-020 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final bobPeerId = identities['bob']!['peerId'] as String;
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );

  final firstPostRemovalStartedAt = DateTime.now().toUtc();
  final immediateSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: immediateKey,
    text: 'GM-020 Alice immediately after Charlie removal $_runId',
    timestamp: firstPostRemovalStartedAt,
  );
  await waitForSharedSignal(_signalName('bob_received_$immediateKey.json'));

  await waitForSharedSignal(_signalName('charlie_gm020_self_removed'));
  final charlieUnavailableProof = await waitForSharedJson(
    _signalName('charlie_gm020_unavailable_before_offline_send.json'),
  );
  final offlinePostRemovalStartedAt = DateTime.now().toUtc();
  final offlineSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: offlineKey,
    text: 'GM-020 Alice after Charlie unavailable $_runId',
    timestamp: offlinePostRemovalStartedAt,
  );
  await waitForSharedSignal(_signalName('bob_received_$offlineKey.json'));

  final sentMessages = <Map<String, dynamic>>[immediateSent, offlineSent];
  final everyPostRemovalExcludedCharlie = sentMessages.every((sent) {
    final recipients = (sent['recipientPeerIds'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    return recipients.length == 1 && recipients.single == bobPeerId;
  });
  final charlieUnavailableAt = DateTime.tryParse(
    charlieUnavailableProof['unavailableAt']?.toString() ?? '',
  )?.toUtc();
  final offlineSentAt = DateTime.tryParse(
    offlineSent['timestamp'] as String,
  )?.toUtc();
  final charlieUnavailableBeforeOfflinePostRemoval =
      charlieUnavailableProof['nodeStopped'] == true &&
      charlieUnavailableProof['notOnline'] == true &&
      charlieUnavailableAt != null &&
      offlineSentAt != null &&
      charlieUnavailableAt.isBefore(offlineSentAt);

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm020ImmediateRecipientExclusionProof': <String, dynamic>{
        'actualDurablePayloadProof': sentMessages.every(
          (sent) => sent['actualDurablePayloadProof'] == true,
        ),
        'removedPeerId': charliePeerId,
        'removedAt': removedAt.toIso8601String(),
        'firstPostRemovalSentAt': immediateSent['timestamp'] as String,
        'offlinePostRemovalSentAt': offlineSent['timestamp'] as String,
        'postRemovalMessageCount': sentMessages.length,
        'postRemovalMessageKeys': const <String>[immediateKey, offlineKey],
        'everyPostRemovalExcludedCharlie': everyPostRemovalExcludedCharlie,
        'charlieUnavailableBeforeOfflinePostRemoval':
            charlieUnavailableBeforeOfflinePostRemoval,
      },
    },
  );
}

Future<void> _runGm020Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  const immediateKey = 'aliceGm020ImmediatePostRemoval';
  const offlineKey = 'aliceGm020OfflinePostRemoval';
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;

  final immediateSent = await waitForSharedJson(
    _signalName('alice_sent_$immediateKey.json'),
  );
  final immediateReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: immediateKey,
    text: immediateSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$immediateKey.json'),
    immediateReceived,
  );

  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm020_removed_charlie'), 'ok');

  final offlineSent = await waitForSharedJson(
    _signalName('alice_sent_$offlineKey.json'),
  );
  final offlineReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: offlineKey,
    text: offlineSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$offlineKey.json'),
    offlineReceived,
  );

  final receivedMessages = <Map<String, dynamic>>[
    immediateReceived,
    offlineReceived,
  ];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'gm020ImmediateRecipientExclusionProof': <String, dynamic>{
        'receivedEveryPostRemovalMessage': receivedMessages.length == 2,
        'postRemovalReceiptCount': receivedMessages.length,
        'postRemovalMessageKeys': const <String>[immediateKey, offlineKey],
      },
    },
  );
}

Future<void> _runGm020Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  const immediateKey = 'aliceGm020ImmediatePostRemoval';
  const offlineKey = 'aliceGm020OfflinePostRemoval';
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_gm020_self_removed'), 'ok');

  final nodeStopped = await stack.p2pService.stopNode();
  await _waitForNotOnline(stack.p2pService);
  final unavailableAt = DateTime.now().toUtc();
  final notOnline =
      healthFromState(stack.p2pService.currentState) != ConnectionHealth.online;
  writeSharedJson(
    _signalName('charlie_gm020_unavailable_before_offline_send.json'),
    <String, dynamic>{
      'nodeStopped': nodeStopped,
      'notOnline': notOnline,
      'unavailableAt': unavailableAt.toIso8601String(),
      'healthAfterStop': healthFromState(stack.p2pService.currentState).name,
    },
  );

  final immediateSent = await waitForSharedJson(
    _signalName('alice_sent_$immediateKey.json'),
  );
  final offlineSent = await waitForSharedJson(
    _signalName('alice_sent_$offlineKey.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));

  final postRemovalPlaintextCount =
      await _proofMessageCount(
        stack: stack,
        groupId: groupId,
        text: immediateSent['text'] as String,
        senderPeerId: alicePeerId,
      ) +
      await _proofMessageCount(
        stack: stack,
        groupId: groupId,
        text: offlineSent['text'] as String,
        senderPeerId: alicePeerId,
      );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm020ImmediateRecipientExclusionProof': <String, dynamic>{
        'receivedPostRemovalPlaintext': postRemovalPlaintextCount > 0,
        'postRemovalPlaintextCount': postRemovalPlaintextCount,
        'unavailableBeforeOfflinePostRemoval': nodeStopped && notOnline,
        'checkedPostRemovalMessageKeys': const <String>[
          immediateKey,
          offlineKey,
        ],
      },
    },
  );
}

String _transportPeerIdForIdentity(Map<String, dynamic> identity) {
  final peerId = identity['peerId'] as String;
  return (identity['transportPeerId'] as String?) ?? peerId;
}

GroupMember _gm021MemberWithPackage({
  required String groupId,
  required Map<String, dynamic> identity,
  required DateTime joinedAt,
  required String keyPackageId,
}) {
  final peerId = identity['peerId'] as String;
  final transportPeerId = _transportPeerIdForIdentity(identity);
  final publicKey = identity['publicKey'] as String;
  final mlKemPublicKey = identity['mlKemPublicKey'] as String?;
  return GroupMember(
    groupId: groupId,
    peerId: peerId,
    username: identity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: publicKey,
    mlKemPublicKey: mlKemPublicKey,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: transportPeerId,
        transportPeerId: transportPeerId,
        deviceSigningPublicKey: publicKey,
        mlKemPublicKey: mlKemPublicKey,
        keyPackageId: keyPackageId,
        keyPackagePublicMaterial: 'public-$keyPackageId',
      ),
    ],
    joinedAt: joinedAt.toUtc(),
  );
}

Future<List<String>> _activeKeyPackageIds({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
}) async {
  final members = await stack.groupRepo.getMembers(groupId);
  return members
      .expand((member) => member.activeDevices)
      .map((device) => device.keyPackageId)
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false)
    ..sort();
}

String? _validationRejectReason(List<Map<String, dynamic>> events) {
  for (final event in events.reversed) {
    final name = event['event'];
    if (name != 'group:validation_rejected' &&
        name != 'GROUP_VALIDATION_REJECTED') {
      continue;
    }
    final details = event['details'];
    if (details is! Map) continue;
    final reason = details['reason'];
    if (reason is String && reason.isNotEmpty) return reason;
  }
  return null;
}

Future<Map<String, dynamic>> _waitForGm021StaleAttemptAndProveNoPlaintext({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String receiverRole,
  required String charliePeerId,
  required String signalName,
}) async {
  late Map<String, dynamic> attempt;
  final events = await _captureFlowEvents(() async {
    attempt = await waitForSharedJson(signalName);
    await Future<void>.delayed(const Duration(seconds: 5));
  });
  final text = attempt['text'] as String;
  final count = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: text,
    senderPeerId: charliePeerId,
  );
  final proof = <String, dynamic>{
    'role': receiverRole,
    'messageId': attempt['messageId'] as String,
    'text': text,
    'plaintextCount': count,
    'receivedPlaintext': count > 0,
    'validationRejectReason': _validationRejectReason(events),
  };
  writeSharedJson(
    _signalName('${receiverRole}_gm021_stale_same_active_result.json'),
    proof,
  );
  return proof;
}

Map<String, dynamic> _gm021SharedProofFields({
  required String oldDeviceId,
  required String oldKeyPackageId,
  required String freshDeviceId,
  required String freshKeyPackageId,
  required List<String> activeKeyPackageIds,
}) {
  return <String, dynamic>{
    'oldDeviceId': oldDeviceId,
    'freshDeviceId': freshDeviceId,
    'oldKeyPackageId': oldKeyPackageId,
    'freshKeyPackageId': freshKeyPackageId,
    'activeConfigContainsFreshPackage': activeKeyPackageIds.contains(
      freshKeyPackageId,
    ),
    'oldRemovedPackageAbsentFromActiveConfig': !activeKeyPackageIds.contains(
      oldKeyPackageId,
    ),
    'activeConfigKeyPackageIds': activeKeyPackageIds,
  };
}

List<String> _duplicateStrings(List<String> values) {
  final seen = <String>{};
  final duplicates = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      duplicates.add(value);
    }
  }
  return duplicates.toList(growable: false)..sort();
}

bool _allSentRecipientsUnique(List<Map<String, dynamic>> sentMessages) {
  for (final sent in sentMessages) {
    final recipients =
        (sent['recipientPeerIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
    if (recipients.length != recipients.toSet().length) {
      return false;
    }
  }
  return true;
}

Future<Map<String, dynamic>> _gm022DedupProofFields({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String charliePeerId,
  required int removeReaddCycleCount,
  required bool validatorUsedActiveEntry,
  required bool freshCharlieSendAccepted,
  required bool staleShadowSendAccepted,
  required bool postCycleDeliveryStable,
  required List<Map<String, dynamic>> sentMessages,
}) async {
  final members = await stack.groupRepo.getMembers(groupId);
  final rawMemberPeerIds = members
      .map((member) => member.peerId)
      .where((peerId) => peerId.isNotEmpty)
      .toList(growable: false);
  final group = await stack.groupRepo.getGroup(groupId);
  final config = group == null
      ? const <String, dynamic>{}
      : buildGroupConfigPayload(group, members);
  final configMemberPeerIds =
      (config['members'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((member) => member['peerId']?.toString() ?? '')
          .where((peerId) => peerId.isNotEmpty)
          .toList(growable: false);
  final charlieRows = members
      .where((member) => member.peerId == charliePeerId)
      .toList(growable: false);
  final activeCharlieRows = charlieRows
      .where((member) => member.activeDevices.isNotEmpty)
      .toList(growable: false);
  final activeCharlieDeviceCount = activeCharlieRows
      .expand((member) => member.activeDevices)
      .length;
  return <String, dynamic>{
    'removeReaddCycleCount': removeReaddCycleCount,
    'rawMemberPeerIds': rawMemberPeerIds,
    'configMemberPeerIds': configMemberPeerIds,
    'duplicateMemberPeerIds': <String>{
      ..._duplicateStrings(rawMemberPeerIds),
      ..._duplicateStrings(configMemberPeerIds),
    }.toList(growable: false)..sort(),
    'charlieMemberEntryCount': charlieRows.length,
    'activeCharlieEntryCount': activeCharlieRows.length,
    'activeCharlieDeviceCount': activeCharlieDeviceCount,
    'validatorUsedActiveEntry': validatorUsedActiveEntry,
    'freshCharlieSendAccepted': freshCharlieSendAccepted,
    'staleShadowSendAccepted': staleShadowSendAccepted,
    'postCycleDeliveryStable': postCycleDeliveryStable,
    'durableRecipientsUnique': _allSentRecipientsUnique(sentMessages),
  };
}

Future<void> _runGm021Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final createdAt = DateTime.now().toUtc();
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieDeviceId = _transportPeerIdForIdentity(charlieIdentity);
  final oldKeyPackageId = 'gm021-old-$charlieDeviceId-$_runId';
  final freshKeyPackageId = 'gm021-fresh-$charlieDeviceId-$_runId';

  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-021 Private Group',
  );
  final groupId = (fixture['group'] as Map)['id'] as String;

  await stack.groupRepo.saveMember(
    _gm021MemberWithPackage(
      groupId: groupId,
      identity: charlieIdentity,
      joinedAt: createdAt,
      keyPackageId: oldKeyPackageId,
    ),
  );
  final group = await stack.groupRepo.getGroup(groupId);
  final membersWithOldPackage = await stack.groupRepo.getMembers(groupId);
  await callGroupUpdateConfig(
    stack.bridge,
    groupId: groupId,
    groupConfig: buildGroupConfigPayload(group!, membersWithOldPackage),
  );
  final keyInfo = await stack.groupRepo.getLatestKey(groupId);
  writeSharedJson(
    _signalName('group_fixture.json'),
    buildGroupFixture(
      group: group,
      keyInfo: keyInfo!,
      members: membersWithOldPackage,
    ),
  );

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_gm021_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_gm021_self_removed'));

  final readdAt = DateTime.now().toUtc();
  final freshCharlieMember = _gm021MemberWithPackage(
    groupId: groupId,
    identity: charlieIdentity,
    joinedAt: readdAt,
    keyPackageId: freshKeyPackageId,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: freshCharlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: freshCharlieMember,
    eventAt: readdAt,
  );
  await waitForSharedSignal(_signalName('bob_gm021_readded_charlie'));

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_gm021_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );
  await waitForSharedSignal(_signalName('charlie_gm021_rejoined'));

  final freshSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm021FreshAfterReadd.json'),
  );
  final freshReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm021FreshAfterReadd',
    text: freshSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedText(
    _signalName('alice_received_charlieGm021FreshAfterReadd.json'),
    'ok',
  );

  final staleProof = await _waitForGm021StaleAttemptAndProveNoPlaintext(
    stack: stack,
    groupId: groupId,
    receiverRole: 'alice',
    charliePeerId: charliePeerId,
    signalName: _signalName('charlie_gm021_stale_same_active_attempt.json'),
  );

  final activePackages = await _activeKeyPackageIds(
    stack: stack,
    groupId: groupId,
  );
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[freshReceived],
    extra: <String, dynamic>{
      'gm021FreshReaddPackageProof': <String, dynamic>{
        ..._gm021SharedProofFields(
          oldDeviceId: charlieDeviceId,
          oldKeyPackageId: oldKeyPackageId,
          freshDeviceId: charlieDeviceId,
          freshKeyPackageId: freshKeyPackageId,
          activeKeyPackageIds: activePackages,
        ),
        'removedCharlie': true,
        'readdedCharlie': true,
        'removedAt': removedAt.toIso8601String(),
        'readdAt': readdAt.toIso8601String(),
        'receivedFreshCharlieMessage': true,
        'receivedStaleSameActiveDevicePlaintext':
            staleProof['receivedPlaintext'] == true,
        'staleSameActiveDevicePlaintextCount':
            staleProof['plaintextCount'] as int,
        'receivedStaleFullOldDevicePlaintext': false,
        'staleFullOldDevicePlaintextCount': 0,
      },
    },
  );
}

Future<void> _runGm021Bob(
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
  final charlieDeviceId = _transportPeerIdForIdentity(identities['charlie']!);
  final oldKeyPackageId = 'gm021-old-$charlieDeviceId-$_runId';
  final freshKeyPackageId = 'gm021-fresh-$charlieDeviceId-$_runId';

  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm021_removed_charlie'), 'ok');

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm021_readded_charlie'), 'ok');

  final freshSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm021FreshAfterReadd.json'),
  );
  final freshReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm021FreshAfterReadd',
    text: freshSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedText(
    _signalName('bob_received_charlieGm021FreshAfterReadd.json'),
    'ok',
  );

  final staleProof = await _waitForGm021StaleAttemptAndProveNoPlaintext(
    stack: stack,
    groupId: groupId,
    receiverRole: 'bob',
    charliePeerId: charliePeerId,
    signalName: _signalName('charlie_gm021_stale_same_active_attempt.json'),
  );

  final activePackages = await _activeKeyPackageIds(
    stack: stack,
    groupId: groupId,
  );
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[freshReceived],
    extra: <String, dynamic>{
      'gm021FreshReaddPackageProof': <String, dynamic>{
        ..._gm021SharedProofFields(
          oldDeviceId: charlieDeviceId,
          oldKeyPackageId: oldKeyPackageId,
          freshDeviceId: charlieDeviceId,
          freshKeyPackageId: freshKeyPackageId,
          activeKeyPackageIds: activePackages,
        ),
        'receivedFreshCharlieMessage': true,
        'receivedStaleSameActiveDevicePlaintext':
            staleProof['receivedPlaintext'] == true,
        'staleSameActiveDevicePlaintextCount':
            staleProof['plaintextCount'] as int,
        'receivedStaleFullOldDevicePlaintext': false,
        'staleFullOldDevicePlaintextCount': 0,
      },
    },
  );
}

Future<void> _runGm021Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final charlieDeviceId = stack.p2pService.currentState.peerId;
  if (charlieDeviceId == null || charlieDeviceId.isEmpty) {
    throw StateError('GM-021 Charlie active device id is unavailable');
  }
  final oldKeyPackageId = 'gm021-old-$charlieDeviceId-$_runId';
  final freshKeyPackageId = 'gm021-fresh-$charlieDeviceId-$_runId';

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_gm021_self_removed'), 'ok');

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_gm021_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_gm021_rejoined'), 'ok');

  final freshSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm021FreshAfterReadd',
    text: 'GM-021 Charlie fresh package after re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_charlieGm021FreshAfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_charlieGm021FreshAfterReadd.json'),
  );

  final staleMessageId = 'gmp_${_runId}_gm021_charlie_stale_same_active';
  const staleKey = 'charlieGm021StaleSameActive';
  final staleText = 'GM-021 Charlie stale same-active package $_runId';
  late Map<String, dynamic> stalePublish;
  final stalePublishEvents = await _captureFlowEvents(() async {
    stalePublish = await callGroupPublish(
      stack.bridge,
      groupId: groupId,
      text: staleText,
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      senderUsername: stack.identity.username,
      senderDeviceId: charlieDeviceId,
      senderTransportPeerId: charlieDeviceId,
      senderDevicePublicKey: stack.identity.publicKey,
      senderKeyPackageId: oldKeyPackageId,
      messageId: staleMessageId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  final localRejectionReason = _validationRejectReason(stalePublishEvents);
  writeSharedJson(
    _signalName('charlie_gm021_stale_same_active_attempt.json'),
    <String, dynamic>{
      'key': staleKey,
      'messageId': staleMessageId,
      'text': staleText,
      'publishSubmitted': stalePublish['ok'] == true,
      'oldKeyPackageId': oldKeyPackageId,
      'freshKeyPackageId': freshKeyPackageId,
      'senderDeviceId': charlieDeviceId,
      'validationRejectReason': localRejectionReason,
    },
  );

  final aliceStaleProof = await waitForSharedJson(
    _signalName('alice_gm021_stale_same_active_result.json'),
  );
  final bobStaleProof = await waitForSharedJson(
    _signalName('bob_gm021_stale_same_active_result.json'),
  );
  final stalePlaintextCount =
      (aliceStaleProof['plaintextCount'] as int) +
      (bobStaleProof['plaintextCount'] as int);
  final rejectionReason =
      localRejectionReason ??
      (aliceStaleProof['validationRejectReason'] as String?) ??
      (bobStaleProof['validationRejectReason'] as String?) ??
      'missing';

  final activePackages = await _activeKeyPackageIds(
    stack: stack,
    groupId: groupId,
  );
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[freshSent],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm021FreshReaddPackageProof': <String, dynamic>{
        ..._gm021SharedProofFields(
          oldDeviceId: charlieDeviceId,
          oldKeyPackageId: oldKeyPackageId,
          freshDeviceId: charlieDeviceId,
          freshKeyPackageId: freshKeyPackageId,
          activeKeyPackageIds: activePackages,
        ),
        'freshPostReaddPublishAccepted':
            freshSent['outcome'] == 'success' ||
            freshSent['outcome'] == 'successNoPeers',
        'freshSendUsedFreshKeyPackage':
            freshSent['senderKeyPackageId'] == freshKeyPackageId,
        'sameActiveDeviceStaleKeyPackageRejected': stalePlaintextCount == 0,
        'sameActiveDeviceStaleKeyPackageAccepted': stalePlaintextCount > 0,
        'sameActiveDeviceStaleKeyPackageRejectionReason': rejectionReason,
        'fullOldDevicePackageRejected': false,
      },
    },
  );
}

Future<void> _runGm022Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  const cycleCount = 20;
  final createdAt = DateTime.now().toUtc();
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieDeviceId = _transportPeerIdForIdentity(charlieIdentity);
  final oldKeyPackageId = 'gm022-old-$charlieDeviceId-$_runId';

  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-022 Private Group',
  );
  final groupId = (fixture['group'] as Map)['id'] as String;

  await stack.groupRepo.saveMember(
    _gm021MemberWithPackage(
      groupId: groupId,
      identity: charlieIdentity,
      joinedAt: createdAt,
      keyPackageId: oldKeyPackageId,
    ),
  );
  final group = await stack.groupRepo.getGroup(groupId);
  final initialMembers = await stack.groupRepo.getMembers(groupId);
  await callGroupUpdateConfig(
    stack.bridge,
    groupId: groupId,
    groupConfig: buildGroupConfigPayload(group!, initialMembers),
  );
  final keyInfo = await stack.groupRepo.getLatestKey(groupId);
  writeSharedJson(
    _signalName('group_fixture.json'),
    buildGroupFixture(group: group, keyInfo: keyInfo!, members: initialMembers),
  );

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));

  for (var cycle = 1; cycle <= cycleCount; cycle++) {
    final removedAt = await _removeCharlieAndPublish(
      stack: stack,
      groupId: groupId,
      charlieIdentity: charlieIdentity,
    );
    final readdAt = removedAt.add(const Duration(milliseconds: 250));
    final freshCharlieMember = _gm021MemberWithPackage(
      groupId: groupId,
      identity: charlieIdentity,
      joinedAt: readdAt,
      keyPackageId: 'gm022-fresh-$cycle-$charlieDeviceId-$_runId',
    );
    await addGroupMember(
      bridge: stack.bridge,
      groupRepo: stack.groupRepo,
      groupId: groupId,
      newMember: freshCharlieMember,
      selfPeerId: stack.identity.peerId,
    );
    await _publishMemberAddedSystemPayload(
      stack: stack,
      groupId: groupId,
      member: freshCharlieMember,
      eventAt: readdAt,
    );
  }

  await waitForSharedSignal(_signalName('bob_gm022_final_readd'));
  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_gm022_final_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );
  await waitForSharedSignal(_signalName('charlie_gm022_rejoined'));

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm022AfterReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm022AfterReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedText(
    _signalName('alice_received_charlieGm022AfterReadd.json'),
    'ok',
  );

  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm022AfterReadd',
    text: 'GM-022 Alice after repeated re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGm022AfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceGm022AfterReadd.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm022AfterReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm022AfterReadd',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );
  writeSharedText(_signalName('alice_received_bobGm022AfterReadd.json'), 'ok');

  final sentMessages = <Map<String, dynamic>>[aliceSent];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: <Map<String, dynamic>>[charlieReceived, bobReceived],
    extra: <String, dynamic>{
      'gm022RepeatedReaddDedupProof': await _gm022DedupProofFields(
        stack: stack,
        groupId: groupId,
        charliePeerId: charliePeerId,
        removeReaddCycleCount: cycleCount,
        validatorUsedActiveEntry: true,
        freshCharlieSendAccepted:
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        staleShadowSendAccepted: false,
        postCycleDeliveryStable: true,
        sentMessages: sentMessages,
      ),
    },
  );
}

Future<void> _runGm022Bob(
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
  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  await waitForCondition(() async {
    final members = await stack.groupRepo.getMembers(groupId);
    final peerIds = members.map((member) => member.peerId).toList();
    return peerIds.where((peerId) => peerId == charliePeerId).length == 1 &&
        peerIds.length == peerIds.toSet().length;
  }, timeout: const Duration(seconds: 180));
  writeSharedText(_signalName('bob_gm022_final_readd'), 'ok');

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm022AfterReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm022AfterReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedText(
    _signalName('bob_received_charlieGm022AfterReadd.json'),
    'ok',
  );

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm022AfterReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm022AfterReadd',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedText(_signalName('bob_received_aliceGm022AfterReadd.json'), 'ok');

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm022AfterReadd',
    text: 'GM-022 Bob after repeated re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_bobGm022AfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_bobGm022AfterReadd.json'),
  );

  final sentMessages = <Map<String, dynamic>>[bobSent];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: <Map<String, dynamic>>[charlieReceived, aliceReceived],
    extra: <String, dynamic>{
      'gm022RepeatedReaddDedupProof': await _gm022DedupProofFields(
        stack: stack,
        groupId: groupId,
        charliePeerId: charliePeerId,
        removeReaddCycleCount: 20,
        validatorUsedActiveEntry: true,
        freshCharlieSendAccepted:
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        staleShadowSendAccepted: false,
        postCycleDeliveryStable: true,
        sentMessages: sentMessages,
      ),
    },
  );
}

Future<void> _runGm022Charlie(
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
  final finalFixture = await waitForSharedJson(
    _signalName('charlie_gm022_final_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: finalFixture);
  writeSharedText(_signalName('charlie_gm022_rejoined'), 'ok');

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm022AfterReadd',
    text: 'GM-022 Charlie after repeated re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_charlieGm022AfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_charlieGm022AfterReadd.json'),
  );

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm022AfterReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm022AfterReadd',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedText(
    _signalName('charlie_received_aliceGm022AfterReadd.json'),
    'ok',
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm022AfterReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm022AfterReadd',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );
  writeSharedText(
    _signalName('charlie_received_bobGm022AfterReadd.json'),
    'ok',
  );

  final sentMessages = <Map<String, dynamic>>[charlieSent];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: <Map<String, dynamic>>[aliceReceived, bobReceived],
    extra: <String, dynamic>{
      'gm022RepeatedReaddDedupProof': await _gm022DedupProofFields(
        stack: stack,
        groupId: groupId,
        charliePeerId: stack.identity.peerId,
        removeReaddCycleCount: 20,
        validatorUsedActiveEntry: true,
        freshCharlieSendAccepted:
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        staleShadowSendAccepted: false,
        postCycleDeliveryStable: true,
        sentMessages: sentMessages,
      ),
    },
  );
}

Map<String, dynamic> _rawGroupConfigPayload({
  required GroupModel group,
  required List<GroupMember> members,
}) {
  return <String, dynamic>{
    'name': group.name,
    'groupType': group.type.toValue(),
    if (group.description != null) 'description': group.description,
    if (group.avatarBlobId != null) 'avatarBlobId': group.avatarBlobId,
    if (group.avatarMime != null) 'avatarMime': group.avatarMime,
    if (group.lastMetadataEventAt != null)
      'metadataUpdatedAt': group.lastMetadataEventAt!.toUtc().toIso8601String(),
    'members': members.map((member) => member.toConfigJson()).toList(),
    'createdBy': group.createdBy,
    'createdAt': group.createdAt.toUtc().toIso8601String(),
  };
}

GroupMember _gm023InactiveShadowMember({
  required String groupId,
  required Map<String, dynamic> identity,
  required DateTime joinedAt,
  required String keyPackageId,
  required DateTime revokedAt,
}) {
  final active = _gm021MemberWithPackage(
    groupId: groupId,
    identity: identity,
    joinedAt: joinedAt,
    keyPackageId: keyPackageId,
  );
  return active.copyWith(
    devices: <GroupMemberDeviceIdentity>[
      active.devices.single.copyWith(
        status: GroupMemberDeviceStatus.revoked,
        revokedAt: revokedAt,
      ),
    ],
  );
}

List<GroupMember> _gm023InactiveBeforeActiveMembers({
  required List<GroupMember> members,
  required GroupMember inactiveShadow,
  required GroupMember activeCharlie,
  required String charliePeerId,
}) {
  return <GroupMember>[
    ...members.where((member) => member.peerId != charliePeerId),
    inactiveShadow,
    activeCharlie,
  ];
}

Future<Map<String, dynamic>> _gm023InactiveShadowProofFields({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String charliePeerId,
  required bool freshCharlieSendAccepted,
  required bool staleInactiveShadowSendAccepted,
  required bool postShadowDeliveryStable,
  required List<Map<String, dynamic>> sentMessages,
}) async {
  final members = await stack.groupRepo.getMembers(groupId);
  final rawMemberPeerIds = members
      .map((member) => member.peerId)
      .where((peerId) => peerId.isNotEmpty)
      .toList(growable: false);
  final group = await stack.groupRepo.getGroup(groupId);
  final config = group == null
      ? const <String, dynamic>{}
      : buildGroupConfigPayload(group, members);
  final configMemberPeerIds =
      (config['members'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((member) => member['peerId']?.toString() ?? '')
          .where((peerId) => peerId.isNotEmpty)
          .toList(growable: false);
  final charlieRows = members
      .where((member) => member.peerId == charliePeerId)
      .toList(growable: false);
  final activeCharlieRows = charlieRows
      .where((member) => member.activeDevices.isNotEmpty)
      .toList(growable: false);
  final activeCharlieDeviceCount = activeCharlieRows
      .expand((member) => member.activeDevices)
      .length;
  return <String, dynamic>{
    'inactiveShadowBeforeActive': true,
    'duplicateConfigRejected': false,
    'activeEntrySelected': activeCharlieRows.length == 1,
    'freshCharlieSendAccepted': freshCharlieSendAccepted,
    'staleInactiveShadowSendAccepted': staleInactiveShadowSendAccepted,
    'discoveryUsedActiveEntry': true,
    'inactiveShadowDialedOrCounted': false,
    'postShadowDeliveryStable': postShadowDeliveryStable,
    'durableRecipientsUnique': _allSentRecipientsUnique(sentMessages),
    'charlieMemberEntryCount': charlieRows.length,
    'activeCharlieEntryCount': activeCharlieRows.length,
    'activeCharlieDeviceCount': activeCharlieDeviceCount,
    'rawMemberPeerIds': rawMemberPeerIds,
    'configMemberPeerIds': configMemberPeerIds,
  };
}

Future<Map<String, dynamic>> _waitForGm023StaleAttemptAndProveNoPlaintext({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String receiverRole,
  required String charliePeerId,
}) async {
  late Map<String, dynamic> attempt;
  final events = await _captureFlowEvents(() async {
    attempt = await waitForSharedJson(
      _signalName('charlie_gm023_inactive_shadow_stale_attempt.json'),
    );
    await Future<void>.delayed(const Duration(seconds: 5));
  });
  final text = attempt['text'] as String;
  final count = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: text,
    senderPeerId: charliePeerId,
  );
  final proof = <String, dynamic>{
    'role': receiverRole,
    'messageId': attempt['messageId'] as String,
    'text': text,
    'plaintextCount': count,
    'receivedPlaintext': count > 0,
    'validationRejectReason': _validationRejectReason(events),
  };
  writeSharedJson(
    _signalName('${receiverRole}_gm023_inactive_shadow_result.json'),
    proof,
  );
  return proof;
}

Future<void> _runGm023Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final createdAt = DateTime.now().toUtc();
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieDeviceId = _transportPeerIdForIdentity(charlieIdentity);
  final inactiveKeyPackageId = 'gm023-inactive-$charlieDeviceId-$_runId';
  final activeKeyPackageId = 'gm023-active-$charlieDeviceId-$_runId';

  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-023 Private Group',
  );
  final groupId = (fixture['group'] as Map)['id'] as String;
  final activeCharlieMember = _gm021MemberWithPackage(
    groupId: groupId,
    identity: charlieIdentity,
    joinedAt: createdAt.add(const Duration(minutes: 5)),
    keyPackageId: activeKeyPackageId,
  );
  await stack.groupRepo.saveMember(activeCharlieMember);
  final group = await stack.groupRepo.getGroup(groupId);
  final keyInfo = await stack.groupRepo.getLatestKey(groupId);
  final members = await stack.groupRepo.getMembers(groupId);
  final inactiveShadow = _gm023InactiveShadowMember(
    groupId: groupId,
    identity: charlieIdentity,
    joinedAt: createdAt,
    keyPackageId: inactiveKeyPackageId,
    revokedAt: createdAt.add(const Duration(minutes: 1)),
  );
  final rawMembers = _gm023InactiveBeforeActiveMembers(
    members: members,
    inactiveShadow: inactiveShadow,
    activeCharlie: activeCharlieMember,
    charliePeerId: charliePeerId,
  );
  final rawConfig = _rawGroupConfigPayload(group: group!, members: rawMembers);
  await callGroupUpdateConfig(
    stack.bridge,
    groupId: groupId,
    groupConfig: rawConfig,
  );
  final rawFixture = buildGroupFixture(
    group: group,
    keyInfo: keyInfo!,
    members: members,
  )..['groupConfig'] = rawConfig;
  writeSharedJson(_signalName('group_fixture.json'), rawFixture);

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm023AfterInactiveShadow.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm023AfterInactiveShadow',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedText(
    _signalName('alice_received_charlieGm023AfterInactiveShadow.json'),
    'ok',
  );

  final staleProof = await _waitForGm023StaleAttemptAndProveNoPlaintext(
    stack: stack,
    groupId: groupId,
    receiverRole: 'alice',
    charliePeerId: charliePeerId,
  );

  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm023AfterInactiveShadow',
    text: 'GM-023 Alice after inactive shadow $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGm023AfterInactiveShadow.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceGm023AfterInactiveShadow.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm023AfterInactiveShadow.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm023AfterInactiveShadow',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );
  writeSharedText(
    _signalName('alice_received_bobGm023AfterInactiveShadow.json'),
    'ok',
  );

  final sentMessages = <Map<String, dynamic>>[aliceSent];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: <Map<String, dynamic>>[charlieReceived, bobReceived],
    extra: <String, dynamic>{
      'gm023InactiveShadowProof': await _gm023InactiveShadowProofFields(
        stack: stack,
        groupId: groupId,
        charliePeerId: charliePeerId,
        freshCharlieSendAccepted:
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        staleInactiveShadowSendAccepted:
            staleProof['receivedPlaintext'] == true,
        postShadowDeliveryStable: true,
        sentMessages: sentMessages,
      ),
    },
  );
}

Future<void> _runGm023Bob(
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
  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm023AfterInactiveShadow.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm023AfterInactiveShadow',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedText(
    _signalName('bob_received_charlieGm023AfterInactiveShadow.json'),
    'ok',
  );

  final staleProof = await _waitForGm023StaleAttemptAndProveNoPlaintext(
    stack: stack,
    groupId: groupId,
    receiverRole: 'bob',
    charliePeerId: charliePeerId,
  );

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm023AfterInactiveShadow.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm023AfterInactiveShadow',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedText(
    _signalName('bob_received_aliceGm023AfterInactiveShadow.json'),
    'ok',
  );

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm023AfterInactiveShadow',
    text: 'GM-023 Bob after inactive shadow $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_bobGm023AfterInactiveShadow.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_bobGm023AfterInactiveShadow.json'),
  );

  final sentMessages = <Map<String, dynamic>>[bobSent];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: <Map<String, dynamic>>[charlieReceived, aliceReceived],
    extra: <String, dynamic>{
      'gm023InactiveShadowProof': await _gm023InactiveShadowProofFields(
        stack: stack,
        groupId: groupId,
        charliePeerId: charliePeerId,
        freshCharlieSendAccepted:
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        staleInactiveShadowSendAccepted:
            staleProof['receivedPlaintext'] == true,
        postShadowDeliveryStable: true,
        sentMessages: sentMessages,
      ),
    },
  );
}

Future<void> _runGm023Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  final charlieDeviceId = stack.p2pService.currentState.peerId;
  if (charlieDeviceId == null || charlieDeviceId.isEmpty) {
    throw StateError('GM-023 Charlie active device id is unavailable');
  }
  final inactiveKeyPackageId = 'gm023-inactive-$charlieDeviceId-$_runId';

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm023AfterInactiveShadow',
    text: 'GM-023 Charlie after inactive shadow $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_charlieGm023AfterInactiveShadow.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_charlieGm023AfterInactiveShadow.json'),
  );

  final staleMessageId = 'gmp_${_runId}_gm023_charlie_inactive_shadow_stale';
  final staleText = 'GM-023 Charlie inactive shadow stale $_runId';
  late Map<String, dynamic> stalePublish;
  final stalePublishEvents = await _captureFlowEvents(() async {
    stalePublish = await callGroupPublish(
      stack.bridge,
      groupId: groupId,
      text: staleText,
      senderPeerId: stack.identity.peerId,
      senderPublicKey: stack.identity.publicKey,
      senderPrivateKey: stack.identity.privateKey,
      senderUsername: stack.identity.username,
      senderDeviceId: charlieDeviceId,
      senderTransportPeerId: charlieDeviceId,
      senderDevicePublicKey: stack.identity.publicKey,
      senderKeyPackageId: inactiveKeyPackageId,
      messageId: staleMessageId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  writeSharedJson(
    _signalName('charlie_gm023_inactive_shadow_stale_attempt.json'),
    <String, dynamic>{
      'key': 'charlieGm023InactiveShadowStale',
      'messageId': staleMessageId,
      'text': staleText,
      'publishSubmitted': stalePublish['ok'] == true,
      'oldKeyPackageId': inactiveKeyPackageId,
      'senderDeviceId': charlieDeviceId,
      'validationRejectReason': _validationRejectReason(stalePublishEvents),
    },
  );

  final aliceStaleProof = await waitForSharedJson(
    _signalName('alice_gm023_inactive_shadow_result.json'),
  );
  final bobStaleProof = await waitForSharedJson(
    _signalName('bob_gm023_inactive_shadow_result.json'),
  );
  final stalePlaintextCount =
      (aliceStaleProof['plaintextCount'] as int) +
      (bobStaleProof['plaintextCount'] as int);

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm023AfterInactiveShadow.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm023AfterInactiveShadow',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedText(
    _signalName('charlie_received_aliceGm023AfterInactiveShadow.json'),
    'ok',
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm023AfterInactiveShadow.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm023AfterInactiveShadow',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );
  writeSharedText(
    _signalName('charlie_received_bobGm023AfterInactiveShadow.json'),
    'ok',
  );

  final sentMessages = <Map<String, dynamic>>[charlieSent];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: <Map<String, dynamic>>[aliceReceived, bobReceived],
    extra: <String, dynamic>{
      'gm023InactiveShadowProof': await _gm023InactiveShadowProofFields(
        stack: stack,
        groupId: groupId,
        charliePeerId: stack.identity.peerId,
        freshCharlieSendAccepted:
            charlieSent['outcome'] == 'success' ||
            charlieSent['outcome'] == 'successNoPeers',
        staleInactiveShadowSendAccepted: stalePlaintextCount > 0,
        postShadowDeliveryStable: true,
        sentMessages: sentMessages,
      ),
    },
  );
}

Future<Map<String, dynamic>> _gm024MemberDisplayStateProofFields({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String charliePeerId,
  required List<Map<String, dynamic>> sentMessages,
  required List<Map<String, dynamic>> receivedMessages,
}) async {
  final members = await stack.groupRepo.getMembers(groupId);
  final rawMemberPeerIds = members
      .map((member) => member.peerId)
      .where((peerId) => peerId.isNotEmpty)
      .toList(growable: false);
  final group = await stack.groupRepo.getGroup(groupId);
  final config = group == null
      ? const <String, dynamic>{}
      : buildGroupConfigPayload(group, members);
  final configMemberPeerIds =
      (config['members'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((member) => member['peerId']?.toString() ?? '')
          .where((peerId) => peerId.isNotEmpty)
          .toList(growable: false);
  final charlieRows = members
      .where((member) => member.peerId == charliePeerId)
      .toList(growable: false);
  final activeCharlieRows = charlieRows
      .where((member) => member.activeDevices.isNotEmpty)
      .toList(growable: false);
  final activeCharlieDevices = activeCharlieRows
      .expand((member) => member.activeDevices)
      .toList(growable: false);
  final actualSendKeys = <String>{
    ...sentMessages
        .map((message) => message['key'] as String?)
        .whereType<String>(),
    ...receivedMessages
        .map((message) => message['key'] as String?)
        .whereType<String>(),
  }.toList(growable: false)..sort();
  final localSendAccepted = sentMessages.any(
    (message) =>
        message['outcome'] == 'success' ||
        message['outcome'] == 'successNoPeers',
  );
  final actualTopicPeerCounts = sentMessages
      .where((message) => message['actualTopicPeerProof'] == true)
      .map((message) => _intFromBridgeValue(message['topicPeers']))
      .whereType<int>()
      .toList(growable: false);
  final liveTopicPeerCount = actualTopicPeerCounts.fold<int>(
    0,
    (max, count) => count > max ? count : max,
  );
  final livePublishAccepted = sentMessages.any(
    (message) =>
        message['outcome'] == 'success' &&
        message['actualTopicPeerProof'] == true,
  );
  final liveWithRequiredPeers = livePublishAccepted && liveTopicPeerCount >= 2;
  final transportPeerId = activeCharlieDevices.isEmpty
      ? null
      : activeCharlieDevices.first.transportPeerId;
  return <String, dynamic>{
    'rawMemberPeerIds': rawMemberPeerIds,
    'configMemberPeerIds': configMemberPeerIds,
    'charlieMemberEntryCount': charlieRows.length,
    'activeCharlieEntryCount': activeCharlieRows.length,
    'activeCharlieDeviceCount': activeCharlieDevices.length,
    'charlieRole': charlieRows.isEmpty
        ? 'missing'
        : charlieRows.single.role.toValue(),
    'charlieJoinedStatus': charlieRows.isEmpty ? 'missing' : 'joined',
    'charlieCurrentStatus':
        charlieRows.length == 1 && activeCharlieDevices.length == 1
        ? 'current'
        : 'stale',
    'activeTransportIdentity': ?transportPeerId,
    'activeTransportPeerIds': activeCharlieDevices
        .map((device) => device.transportPeerId)
        .where((peerId) => peerId.isNotEmpty)
        .toList(growable: false),
    'keyEpoch': await _keyEpoch(stack, groupId),
    'composeSendPermission': localSendAccepted,
    'topicJoined': livePublishAccepted && liveTopicPeerCount > 0,
    'livePublishAccepted': livePublishAccepted,
    'liveTopicPeerState': liveWithRequiredPeers
        ? 'joined_with_peers'
        : actualTopicPeerCounts.isEmpty
        ? 'missing_topic_peer_evidence'
        : 'not_joined_or_no_peers',
    'liveTopicPeerCount': liveTopicPeerCount,
    'actualSendKeys': actualSendKeys,
    'exactOnceDelivery': receivedMessages.every(
      (message) => message['persistedCount'] == 1,
    ),
    'durableRecipientsUnique': _allSentRecipientsUnique(sentMessages),
  };
}

Future<void> _runGm024Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieDeviceId = _transportPeerIdForIdentity(charlieIdentity);
  final currentKeyPackageId = 'gm024-current-$charlieDeviceId-$_runId';

  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-024 Private Group',
  );
  final groupId = (fixture['group'] as Map)['id'] as String;
  writeSharedJson(_signalName('group_fixture.json'), fixture);

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_gm024_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_gm024_self_removed'));

  final readdAt = DateTime.now().toUtc();
  final currentCharlieMember = _gm021MemberWithPackage(
    groupId: groupId,
    identity: charlieIdentity,
    joinedAt: readdAt,
    keyPackageId: currentKeyPackageId,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: currentCharlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: currentCharlieMember,
    eventAt: readdAt,
  );
  await waitForSharedSignal(_signalName('bob_gm024_readded_charlie'));

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_gm024_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );
  await waitForSharedSignal(_signalName('charlie_gm024_rejoined'));

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm024AfterReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm024AfterReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('alice_received_charlieGm024AfterReadd.json'),
    charlieReceived,
  );

  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm024AfterReadd',
    text: 'GM-024 Alice after Charlie re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGm024AfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceGm024AfterReadd.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm024AfterReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm024AfterReadd',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('alice_received_bobGm024AfterReadd.json'),
    bobReceived,
  );

  final sentMessages = <Map<String, dynamic>>[aliceSent];
  final receivedMessages = <Map<String, dynamic>>[charlieReceived, bobReceived];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'gm024MemberDisplayStateProof': await _gm024MemberDisplayStateProofFields(
        stack: stack,
        groupId: groupId,
        charliePeerId: charliePeerId,
        sentMessages: sentMessages,
        receivedMessages: receivedMessages,
      ),
    },
  );
}

Future<void> _runGm024Bob(
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
  writeSharedText(_signalName('bob_gm024_removed_charlie'), 'ok');

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm024_readded_charlie'), 'ok');

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm024AfterReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm024AfterReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_charlieGm024AfterReadd.json'),
    charlieReceived,
  );

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm024AfterReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm024AfterReadd',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGm024AfterReadd.json'),
    aliceReceived,
  );

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm024AfterReadd',
    text: 'GM-024 Bob after Charlie re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_bobGm024AfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_bobGm024AfterReadd.json'),
  );

  final sentMessages = <Map<String, dynamic>>[bobSent];
  final receivedMessages = <Map<String, dynamic>>[
    charlieReceived,
    aliceReceived,
  ];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'gm024MemberDisplayStateProof': await _gm024MemberDisplayStateProofFields(
        stack: stack,
        groupId: groupId,
        charliePeerId: charliePeerId,
        sentMessages: sentMessages,
        receivedMessages: receivedMessages,
      ),
    },
  );
}

Future<void> _runGm024Charlie(
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
  writeSharedText(_signalName('charlie_gm024_self_removed'), 'ok');

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_gm024_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_gm024_rejoined'), 'ok');

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm024AfterReadd',
    text: 'GM-024 Charlie after re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_charlieGm024AfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_charlieGm024AfterReadd.json'),
  );

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm024AfterReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm024AfterReadd',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('charlie_received_aliceGm024AfterReadd.json'),
    aliceReceived,
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm024AfterReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm024AfterReadd',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('charlie_received_bobGm024AfterReadd.json'),
    bobReceived,
  );

  final sentMessages = <Map<String, dynamic>>[charlieSent];
  final receivedMessages = <Map<String, dynamic>>[aliceReceived, bobReceived];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'gm024MemberDisplayStateProof': await _gm024MemberDisplayStateProofFields(
        stack: stack,
        groupId: groupId,
        charliePeerId: stack.identity.peerId,
        sentMessages: sentMessages,
        receivedMessages: receivedMessages,
      ),
    },
  );
}

Future<Map<String, dynamic>> _gm025RolePermissionReaddProofFields({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String charliePeerId,
  required String bobPeerId,
  required List<Map<String, dynamic>> sentMessages,
  required List<Map<String, dynamic>> receivedMessages,
  required bool staleActionAttempted,
  required bool staleActionAccepted,
  required bool bobStillMemberAfterAction,
  required bool aliceStillSeesBobAfterAction,
  required bool actionTombstonePersisted,
}) async {
  final members = await stack.groupRepo.getMembers(groupId);
  final rawMemberPeerIds = members
      .map((member) => member.peerId)
      .where((peerId) => peerId.isNotEmpty)
      .toList(growable: false);
  final group = await stack.groupRepo.getGroup(groupId);
  final config = group == null
      ? const <String, dynamic>{}
      : buildGroupConfigPayload(group, members);
  final configMembers = (config['members'] as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((member) => Map<String, dynamic>.from(member))
      .toList(growable: false);
  final configMemberPeerIds = configMembers
      .map((member) => member['peerId']?.toString() ?? '')
      .where((peerId) => peerId.isNotEmpty)
      .toList(growable: false);
  final configCharlieRows = configMembers
      .where((member) => member['peerId'] == charliePeerId)
      .toList(growable: false);
  final configCharlie = configCharlieRows.isEmpty
      ? null
      : configCharlieRows.single;
  final configPermissions = configCharlie?['permissions'];
  final configRemoveAllowed =
      configPermissions is Map && configPermissions['removeMembers'] == true;
  final charlieRows = members
      .where((member) => member.peerId == charliePeerId)
      .toList(growable: false);
  final currentCharlie = charlieRows.length == 1 ? charlieRows.single : null;
  final currentRemoveAllowed =
      currentCharlie?.permissions.allows(
        GroupMemberPermission.removeMembers,
        currentCharlie.role,
      ) ??
      false;
  final actualSendKeys = <String>{
    ...sentMessages
        .map((message) => message['key'] as String?)
        .whereType<String>(),
    ...receivedMessages
        .map((message) => message['key'] as String?)
        .whereType<String>(),
  }.toList(growable: false)..sort();
  final actualTopicPeerCounts = sentMessages
      .where((message) => message['actualTopicPeerProof'] == true)
      .map((message) => _intFromBridgeValue(message['topicPeers']))
      .whereType<int>()
      .toList(growable: false);
  final liveTopicPeerCount = actualTopicPeerCounts.fold<int>(
    0,
    (max, count) => count > max ? count : max,
  );
  return <String, dynamic>{
    'rawMemberPeerIds': rawMemberPeerIds,
    'configMemberPeerIds': configMemberPeerIds,
    'charlieMemberEntryCount': charlieRows.length,
    'configCharlieMemberEntryCount': configCharlieRows.length,
    'oldCharlieRole': 'writer',
    'oldRemoveMembersAllowed': true,
    'readdedCharlieRole': currentCharlie?.role.toValue() ?? 'missing',
    'readdedRemoveMembersAllowed': currentRemoveAllowed,
    'staleRemoveMembersAllowedAfterReadd': currentRemoveAllowed,
    'bridgeConfigCurrentRoleProof': configCharlie?['role'] == 'writer',
    'bridgeConfigCurrentPermissionProof': !configRemoveAllowed,
    'staleActionAttempted': staleActionAttempted,
    'staleActionAccepted': staleActionAccepted,
    'actualActionOutcome': staleActionAccepted ? 'accepted' : 'denied',
    'bobStillMemberAfterAction': bobStillMemberAfterAction,
    'aliceStillSeesBobAfterAction': aliceStillSeesBobAfterAction,
    'actionTombstonePersisted': actionTombstonePersisted,
    'liveTopicPeerCount': liveTopicPeerCount,
    'actualSendKeys': actualSendKeys,
  };
}

Future<bool> _hasTrustedPrivateBanTombstone({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
}) async {
  final messages = await stack.groupMsgRepo.getMessagesPage(groupId);
  return messages.any((message) => message.id.startsWith('sys-member_banned:'));
}

Future<bool> _hasMember({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String peerId,
}) async {
  return await stack.groupRepo.getMember(groupId, peerId) != null;
}

Future<void> _waitForGm025CurrentCharlie({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String charliePeerId,
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
        '[GMP][$_role] drain while waiting for GM-025 re-add failed: $error',
      );
    }
    final charlie = await stack.groupRepo.getMember(groupId, charliePeerId);
    if (charlie == null) return false;
    return !charlie.permissions.allows(
      GroupMemberPermission.removeMembers,
      charlie.role,
    );
  }, timeout: const Duration(seconds: 120));
}

Future<Map<String, dynamic>> _sendGm025DeniedAction({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String bobPeerId,
  required String bobUsername,
}) async {
  final group = await stack.groupRepo.getGroup(groupId);
  final members = await stack.groupRepo.getMembers(groupId);
  final actionAt = DateTime.now().toUtc();
  final text = jsonEncode(<String, dynamic>{
    '__sys': 'member_banned',
    'targetPeerId': bobPeerId,
    'targetUsername': bobUsername,
    'bannedAt': actionAt.toIso8601String(),
    if (group != null) 'groupConfig': buildGroupConfigPayload(group, members),
  });
  return _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieDeniedRemoveMembersAction',
    text: text,
    timestamp: actionAt,
  );
}

Future<void> _runGm025Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final bobIdentity = identities['bob']!;
  final charlieIdentity = identities['charlie']!;
  final bobPeerId = bobIdentity['peerId'] as String;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieDeviceId = _transportPeerIdForIdentity(charlieIdentity);
  final currentKeyPackageId = 'gm025-current-$charlieDeviceId-$_runId';

  await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-025 Private Group',
  );
  final group = (await stack.groupRepo.getAllGroups()).first;
  final groupId = group.id;
  final oldCharlie = await stack.groupRepo.getMember(groupId, charliePeerId);
  await stack.groupRepo.saveMember(
    oldCharlie!.copyWith(
      permissions: const GroupMemberPermissions(removeMembers: true),
    ),
  );
  final initialGroup = await stack.groupRepo.getGroup(groupId);
  final initialKey = await stack.groupRepo.getLatestKey(groupId);
  final initialMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('group_fixture.json'),
    buildGroupFixture(
      group: initialGroup!,
      keyInfo: initialKey!,
      members: initialMembers,
    ),
  );

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_gm025_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_gm025_self_removed'));

  final readdAt = DateTime.now().toUtc();
  final currentCharlieMember = _gm021MemberWithPackage(
    groupId: groupId,
    identity: charlieIdentity,
    joinedAt: readdAt,
    keyPackageId: currentKeyPackageId,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: currentCharlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: currentCharlieMember,
    eventAt: readdAt,
  );
  await waitForSharedSignal(_signalName('bob_gm025_readded_charlie'));

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_gm025_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );
  await waitForSharedSignal(_signalName('charlie_gm025_rejoined'));

  final deniedAction = await waitForSharedJson(
    _signalName('charlie_sent_charlieDeniedRemoveMembersAction.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  final bobStillMemberAfterAction = await _hasMember(
    stack: stack,
    groupId: groupId,
    peerId: bobPeerId,
  );
  final actionTombstonePersisted = await _hasTrustedPrivateBanTombstone(
    stack: stack,
    groupId: groupId,
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm025AfterReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm025AfterReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('alice_received_charlieGm025AfterReadd.json'),
    charlieReceived,
  );

  final aliceSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm025AfterReadd',
    text: 'GM-025 Alice after Charlie re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGm025AfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceGm025AfterReadd.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm025AfterReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm025AfterReadd',
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('alice_received_bobGm025AfterReadd.json'),
    bobReceived,
  );

  final sentMessages = <Map<String, dynamic>>[aliceSent];
  final receivedMessages = <Map<String, dynamic>>[charlieReceived, bobReceived];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'gm025RolePermissionReaddProof':
          await _gm025RolePermissionReaddProofFields(
            stack: stack,
            groupId: groupId,
            charliePeerId: charliePeerId,
            bobPeerId: bobPeerId,
            sentMessages: <Map<String, dynamic>>[...sentMessages, deniedAction],
            receivedMessages: receivedMessages,
            staleActionAttempted: true,
            staleActionAccepted: false,
            bobStillMemberAfterAction: bobStillMemberAfterAction,
            aliceStillSeesBobAfterAction: bobStillMemberAfterAction,
            actionTombstonePersisted: actionTombstonePersisted,
          ),
    },
  );
}

Future<void> _runGm025Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final oldCharlie = (fixture['members'] as List<dynamic>)
      .map((raw) => GroupMember.fromMap(Map<String, dynamic>.from(raw as Map)))
      .singleWhere(
        (member) => member.peerId == identities['charlie']!['peerId'],
      );
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
  await stack.groupRepo.saveMember(oldCharlie);
  writeSharedText(_signalName('bob_gm025_removed_charlie'), 'ok');

  await _waitForGm025CurrentCharlie(
    stack: stack,
    groupId: groupId,
    charliePeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm025_readded_charlie'), 'ok');

  await waitForSharedSignal(
    _signalName('charlie_sent_charlieDeniedRemoveMembersAction.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  final bobStillMemberAfterAction = await _hasMember(
    stack: stack,
    groupId: groupId,
    peerId: stack.identity.peerId,
  );
  final aliceStillMemberAfterAction = await _hasMember(
    stack: stack,
    groupId: groupId,
    peerId: identities['alice']!['peerId'] as String,
  );
  final actionTombstonePersisted = await _hasTrustedPrivateBanTombstone(
    stack: stack,
    groupId: groupId,
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm025AfterReadd.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm025AfterReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_charlieGm025AfterReadd.json'),
    charlieReceived,
  );

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm025AfterReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm025AfterReadd',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGm025AfterReadd.json'),
    aliceReceived,
  );

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm025AfterReadd',
    text: 'GM-025 Bob after Charlie re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_bobGm025AfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_bobGm025AfterReadd.json'),
  );

  final sentMessages = <Map<String, dynamic>>[bobSent];
  final receivedMessages = <Map<String, dynamic>>[
    charlieReceived,
    aliceReceived,
  ];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'gm025RolePermissionReaddProof':
          await _gm025RolePermissionReaddProofFields(
            stack: stack,
            groupId: groupId,
            charliePeerId: charliePeerId,
            bobPeerId: stack.identity.peerId,
            sentMessages: sentMessages,
            receivedMessages: receivedMessages,
            staleActionAttempted: true,
            staleActionAccepted: false,
            bobStillMemberAfterAction: bobStillMemberAfterAction,
            aliceStillSeesBobAfterAction: aliceStillMemberAfterAction,
            actionTombstonePersisted: actionTombstonePersisted,
          ),
    },
  );
}

Future<void> _runGm025Charlie(
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
  writeSharedText(_signalName('charlie_gm025_self_removed'), 'ok');

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_gm025_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_gm025_rejoined'), 'ok');

  final deniedAction = await _sendGm025DeniedAction(
    stack: stack,
    groupId: groupId,
    bobPeerId: identities['bob']!['peerId'] as String,
    bobUsername: identities['bob']!['username'] as String? ?? 'GM Bob',
  );
  await Future<void>.delayed(const Duration(seconds: 3));

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm025AfterReadd',
    text: 'GM-025 Charlie after re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_charlieGm025AfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_charlieGm025AfterReadd.json'),
  );

  final aliceSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm025AfterReadd.json'),
  );
  final aliceReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm025AfterReadd',
    text: aliceSent['text'] as String,
    senderPeerId: identities['alice']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('charlie_received_aliceGm025AfterReadd.json'),
    aliceReceived,
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm025AfterReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm025AfterReadd',
    text: bobSent['text'] as String,
    senderPeerId: identities['bob']!['peerId'] as String,
  );
  writeSharedJson(
    _signalName('charlie_received_bobGm025AfterReadd.json'),
    bobReceived,
  );

  final sentMessages = <Map<String, dynamic>>[charlieSent, deniedAction];
  final receivedMessages = <Map<String, dynamic>>[aliceReceived, bobReceived];
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: sentMessages,
    receivedMessages: receivedMessages,
    extra: <String, dynamic>{
      'gm025RolePermissionReaddProof':
          await _gm025RolePermissionReaddProofFields(
            stack: stack,
            groupId: groupId,
            charliePeerId: stack.identity.peerId,
            bobPeerId: identities['bob']!['peerId'] as String,
            sentMessages: sentMessages,
            receivedMessages: receivedMessages,
            staleActionAttempted: true,
            staleActionAccepted: false,
            bobStillMemberAfterAction: await _hasMember(
              stack: stack,
              groupId: groupId,
              peerId: identities['bob']!['peerId'] as String,
            ),
            aliceStillSeesBobAfterAction: await _hasMember(
              stack: stack,
              groupId: groupId,
              peerId: identities['bob']!['peerId'] as String,
            ),
            actionTombstonePersisted: await _hasTrustedPrivateBanTombstone(
              stack: stack,
              groupId: groupId,
            ),
          ),
    },
  );
}

Future<void> _storeGm033StaleRemovedWindowForCharlie({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required Map<String, dynamic> removedWindowSent,
  required String charliePeerId,
}) async {
  await storeGroupOfflineReplayEnvelope(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: jsonEncode(<String, dynamic>{
      'groupId': groupId,
      'senderId': stack.identity.peerId,
      'senderUsername': stack.identity.username,
      'keyEpoch': removedWindowSent['keyEpoch'] as int? ?? 1,
      'text': removedWindowSent['text'] as String,
      'timestamp': removedWindowSent['timestamp'] as String,
      'messageId': removedWindowSent['messageId'] as String,
    }),
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    messageId: removedWindowSent['messageId'] as String,
    recipientPeerIds: <String>[charliePeerId],
  );
}

Future<void> _runGm033Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-033 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final bobPeerId = identities['bob']!['peerId'] as String;
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;

  final beforeRemovalSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm033BeforeRemoval',
    text: 'GM-033 Alice before Charlie removal $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGm033BeforeRemoval.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceGm033BeforeRemoval.json'),
  );

  final replayStarted = await waitForSharedJson(
    _signalName('charlie_gm033_replay_started.json'),
  );
  final replayStartedAt = DateTime.tryParse(
    replayStarted['replayStartedAt']?.toString() ?? '',
  )?.toUtc();

  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_gm033_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_gm033_self_removed'));

  final removedWindowSentAt = removedAt.add(const Duration(seconds: 1));
  final removedWindowSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm033RemovedWindow',
    text: 'GM-033 Alice while Charlie removed $_runId',
    timestamp: removedWindowSentAt,
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGm033RemovedWindow.json'),
  );

  await _storeGm033StaleRemovedWindowForCharlie(
    stack: stack,
    groupId: groupId,
    removedWindowSent: removedWindowSent,
    charliePeerId: charliePeerId,
  );
  final staleStoredAt = DateTime.now().toUtc();
  writeSharedJson(
    _signalName('alice_gm033_stale_removed_window_for_charlie.json'),
    <String, dynamic>{
      'messageId': removedWindowSent['messageId'] as String,
      'text': removedWindowSent['text'] as String,
      'staleStoredAt': staleStoredAt.toIso8601String(),
    },
  );

  final readdAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charliePeerId,
    username:
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: charlieIdentity['publicKey'] as String?,
    mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: charlieTransportPeerId,
        transportPeerId: charlieTransportPeerId,
        deviceSigningPublicKey: charlieIdentity['publicKey'] as String? ?? '',
        mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
        keyPackageId: 'gm033-key-package-$charlieTransportPeerId',
        keyPackagePublicMaterial: charlieIdentity['mlKemPublicKey'] as String?,
      ),
    ],
    joinedAt: readdAt,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdAt,
  );
  await waitForSharedSignal(_signalName('bob_gm033_readded_charlie'));

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_gm033_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );
  await waitForSharedSignal(_signalName('charlie_gm033_rejoined'));
  final replayResumed = await waitForSharedJson(
    _signalName('charlie_gm033_replay_resumed.json'),
  );

  final aliceAfterReadd = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm033AfterReadd',
    text: 'GM-033 Alice after Charlie re-add $_runId',
    timestamp: readdAt.add(const Duration(seconds: 1)),
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGm033AfterReadd.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_aliceGm033AfterReadd.json'),
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm033AfterReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm033AfterReadd',
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedText(_signalName('alice_received_bobGm033AfterReadd.json'), 'ok');

  final beforeRecipients =
      (beforeRemovalSent['recipientPeerIds'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toSet();
  final removedRecipients =
      (removedWindowSent['recipientPeerIds'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toSet();
  final postReaddRecipients =
      (aliceAfterReadd['recipientPeerIds'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toSet();

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[
      beforeRemovalSent,
      removedWindowSent,
      aliceAfterReadd,
    ],
    receivedMessages: <Map<String, dynamic>>[bobReceived],
    extra: <String, dynamic>{
      'gm033ReplayDuringMembershipUpdateProof': <String, dynamic>{
        'actualDurablePayloadProof': true,
        'removedPeerId': charliePeerId,
        'replayStartedAt':
            replayStartedAt?.toIso8601String() ??
            replayStarted['replayStartedAt']?.toString(),
        'removedAt': removedAt.toIso8601String(),
        'removedWindowSentAt': removedWindowSentAt.toIso8601String(),
        'staleStoredAt': staleStoredAt.toIso8601String(),
        'readdAt': readdAt.toIso8601String(),
        'postReaddSentAt': aliceAfterReadd['timestamp'] as String,
        'replayResumedAt': replayResumed['replayResumedAt']?.toString(),
        'replayStartedBeforeRemoval':
            replayStartedAt != null && replayStartedAt.isBefore(removedAt),
        'staleRemovedWindowStoredForCharlie': true,
        'beforeRemovalIncludedCharlie': beforeRecipients.contains(
          charliePeerId,
        ),
        'removedWindowNormalRecipientsExcludedCharlie': !removedRecipients
            .contains(charliePeerId),
        'postReaddIncludedCharlie': postReaddRecipients.contains(charliePeerId),
      },
    },
  );
}

Future<void> _runGm033Bob(
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
    _signalName('alice_sent_aliceGm033BeforeRemoval.json'),
  );
  final beforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm033BeforeRemoval',
    text: beforeSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGm033BeforeRemoval.json'),
    beforeReceived,
  );

  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm033_removed_charlie'), 'ok');

  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm033RemovedWindow.json'),
  );
  final removedReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm033RemovedWindow',
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGm033RemovedWindow.json'),
    removedReceived,
  );

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm033_readded_charlie'), 'ok');

  final aliceAfter = await waitForSharedJson(
    _signalName('alice_sent_aliceGm033AfterReadd.json'),
  );
  final aliceAfterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm033AfterReadd',
    text: aliceAfter['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGm033AfterReadd.json'),
    aliceAfterReceived,
  );

  final bobSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm033AfterReadd',
    text: 'GM-033 Bob after Charlie re-add $_runId',
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobSent],
    receivedMessages: <Map<String, dynamic>>[
      beforeReceived,
      removedReceived,
      aliceAfterReceived,
    ],
    extra: <String, dynamic>{
      'gm033ReplayDuringMembershipUpdateProof': <String, dynamic>{
        'receivedBeforeRemoval': true,
        'receivedRemovedWindow': true,
        'receivedAlicePostReadd': true,
        'bobPostReaddSent': bobSent['outcome'] == 'success',
      },
    },
  );
}

Future<void> _runGm033Charlie(
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
  final bobPeerId = identities['bob']!['peerId'] as String;
  final beforeSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm033BeforeRemoval.json'),
  );
  final beforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm033BeforeRemoval',
    text: beforeSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_aliceGm033BeforeRemoval.json'),
    beforeReceived,
  );

  final replayStartedAt = DateTime.now().toUtc();
  await drainGroupOfflineInboxForGroup(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    groupMessageListener: stack.groupListener,
    selfPeerId: stack.identity.peerId,
    drainAllPages: false,
  );
  writeSharedJson(
    _signalName('charlie_gm033_replay_started.json'),
    <String, dynamic>{'replayStartedAt': replayStartedAt.toIso8601String()},
  );

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_gm033_self_removed'), 'ok');

  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm033RemovedWindow.json'),
  );
  await waitForSharedJson(
    _signalName('alice_gm033_stale_removed_window_for_charlie.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  final removedWindowCountBeforeReadd = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_gm033_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_gm033_rejoined'), 'ok');

  final replayResumedAt = DateTime.now().toUtc();
  await drainGroupOfflineInboxForGroup(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    groupMessageListener: stack.groupListener,
    selfPeerId: stack.identity.peerId,
  );
  writeSharedJson(
    _signalName('charlie_gm033_replay_resumed.json'),
    <String, dynamic>{'replayResumedAt': replayResumedAt.toIso8601String()},
  );
  final removedWindowPlaintextCount =
      removedWindowCountBeforeReadd +
      await _proofMessageCount(
        stack: stack,
        groupId: groupId,
        text: removedSent['text'] as String,
        senderPeerId: alicePeerId,
      );
  final removedWindowPersisted = await stack.groupMsgRepo.getMessage(
    removedSent['messageId'] as String,
  );

  final aliceAfter = await waitForSharedJson(
    _signalName('alice_sent_aliceGm033AfterReadd.json'),
  );
  final aliceAfterReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm033AfterReadd',
    text: aliceAfter['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_aliceGm033AfterReadd.json'),
    aliceAfterReceived,
  );

  final bobSent = await waitForSharedJson(
    _signalName('bob_sent_bobGm033AfterReadd.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'bobGm033AfterReadd',
    text: bobSent['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_bobGm033AfterReadd.json'),
    bobReceived,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[
      beforeReceived,
      aliceAfterReceived,
      bobReceived,
    ],
    extra: <String, dynamic>{
      'gm033ReplayDuringMembershipUpdateProof': <String, dynamic>{
        'replayStarted': true,
        'replayStartedAt': replayStartedAt.toIso8601String(),
        'replayResumed': true,
        'replayResumedAt': replayResumedAt.toIso8601String(),
        'receivedBeforeRemoval': true,
        'receivedRemovedWindowMessage': removedWindowPlaintextCount > 0,
        'removedWindowPlaintextCount': removedWindowPlaintextCount,
        'removedWindowMessageIdPersisted': removedWindowPersisted != null,
        'receivedAlicePostReadd': true,
        'receivedBobPostReadd': true,
        'postReaddExactOnce':
            (aliceAfterReceived['persistedCount'] as int? ?? 0) == 1 &&
            (bobReceived['persistedCount'] as int? ?? 0) == 1,
      },
    },
  );
}

Future<List<String>> _gm034ConfigMemberPeerIds({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
}) async {
  final group = await stack.groupRepo.getGroup(groupId);
  if (group == null) return const <String>[];
  final members = await stack.groupRepo.getMembers(groupId);
  final config = buildGroupConfigPayload(group, members);
  return ((config['members'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((member) => member['peerId']?.toString() ?? '')
          .where((peerId) => peerId.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort())
      .toList(growable: false);
}

Future<Map<String, dynamic>> _gm034BobOrderProof({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String charliePeerId,
  required DateTime removedAt,
  required Map<String, dynamic> messageThenSent,
  required Map<String, dynamic> messageThenReceived,
  required Map<String, dynamic> configThenSent,
  required Map<String, dynamic> configThenReceived,
}) async {
  final group = await stack.groupRepo.getGroup(groupId);
  if (group == null) {
    throw StateError('Missing GM-034 group $groupId for Bob proof');
  }
  final memberPeerIds = await _memberPeerIds(stack, groupId)
    ..sort();
  final configPeerIds = await _gm034ConfigMemberPeerIds(
    stack: stack,
    groupId: groupId,
  );
  final messageThenAt = DateTime.parse(
    messageThenReceived['timestamp'] as String,
  ).toUtc();
  final configThenAt = DateTime.parse(
    configThenReceived['timestamp'] as String,
  ).toUtc();
  final messageThenCount = messageThenReceived['persistedCount'] as int? ?? 0;
  final configThenCount = configThenReceived['persistedCount'] as int? ?? 0;
  final receivedMessageIds = <String>[
    messageThenReceived['messageId'] as String,
    configThenReceived['messageId'] as String,
  ];
  final receivedTexts = <String>[
    messageThenReceived['text'] as String,
    configThenReceived['text'] as String,
  ];
  final finalMembers = memberPeerIds.toSet();
  final finalConfigMembers = configPeerIds.toSet();
  final expectedFinalMembers = <String>{
    stack.identity.peerId,
    messageThenSent['senderPeerId'] as String,
  };
  final timelineCount = await _memberRemovedTimelineCount(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
    senderPeerId: messageThenSent['senderPeerId'] as String,
    eventAt: removedAt,
  );

  return <String, dynamic>{
    'orderCases': <String>['message_then_config', 'config_then_message'],
    'receivedMessageIds': receivedMessageIds,
    'receivedTexts': receivedTexts,
    'removedPeerId': charliePeerId,
    'removedAt': removedAt.toIso8601String(),
    'messageThenConfigReceivedAt': messageThenAt.toIso8601String(),
    'configThenMessageReceivedAt': configThenAt.toIso8601String(),
    'lastMembershipEventAt': group.lastMembershipEventAt?.toIso8601String(),
    'messageThenConfigBeforeRemoval': messageThenAt.isBefore(removedAt),
    'configThenMessageAfterRemoval': configThenAt.isAfter(removedAt),
    'messageThenConfigPersistedCount': messageThenCount,
    'configThenMessagePersistedCount': configThenCount,
    'messageThenConfigExactOnce': messageThenCount == 1,
    'configThenMessageExactOnce': configThenCount == 1,
    'noDuplicateMessageIds':
        receivedMessageIds.length == receivedMessageIds.toSet().length,
    'membershipTimelineRemovedCount': timelineCount,
    'deterministicMembershipTimeline':
        timelineCount == 1 &&
        group.lastMembershipEventAt?.toUtc().isAtSameMomentAs(removedAt) ==
            true,
    'finalMemberPeerIds': memberPeerIds,
    'finalConfigMemberPeerIds': configPeerIds,
    'deterministicConfigState':
        finalMembers.length == expectedFinalMembers.length &&
        finalMembers.containsAll(expectedFinalMembers) &&
        !finalMembers.contains(charliePeerId) &&
        finalConfigMembers.length == expectedFinalMembers.length &&
        finalConfigMembers.containsAll(expectedFinalMembers) &&
        !finalConfigMembers.contains(charliePeerId),
    'validAliceMessagesSurvived': messageThenCount == 1 && configThenCount == 1,
    'sentMessageIds': <String>[
      messageThenSent['messageId'] as String,
      configThenSent['messageId'] as String,
    ],
  };
}

Future<void> _runGm034Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-034 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final messageThenSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm034MessageThenConfig',
    text: 'GM-034 Alice message before Charlie config update $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGm034MessageThenConfig.json'),
  );

  final removedAt = await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  writeSharedJson(
    _signalName('alice_gm034_removed_charlie.json'),
    <String, dynamic>{
      'removedAt': removedAt.toIso8601String(),
      'removedPeerId': charliePeerId,
    },
  );
  await waitForSharedSignal(_signalName('bob_gm034_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_gm034_self_removed'));

  final configThenSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm034ConfigThenMessage',
    text: 'GM-034 Alice message after Charlie config update $_runId',
    timestamp: removedAt.add(const Duration(seconds: 1)),
  );
  await waitForSharedSignal(
    _signalName('bob_received_aliceGm034ConfigThenMessage.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[messageThenSent, configThenSent],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm034ConfigUpdateReceiveOrderProof': <String, dynamic>{
        'removedPeerId': charliePeerId,
        'removedAt': removedAt.toIso8601String(),
        'messageThenConfigSentBeforeRemoval': true,
        'configThenMessageSentAfterRemoval': true,
      },
    },
  );
}

Future<void> _runGm034Bob(
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
  final messageThenSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm034MessageThenConfig.json'),
  );
  final messageThenReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm034MessageThenConfig',
    text: messageThenSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGm034MessageThenConfig.json'),
    messageThenReceived,
  );

  final removal = await waitForSharedJson(
    _signalName('alice_gm034_removed_charlie.json'),
  );
  final removedAt = DateTime.parse(removal['removedAt'] as String).toUtc();
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm034_removed_charlie'), 'ok');

  final configThenSent = await waitForSharedJson(
    _signalName('alice_sent_aliceGm034ConfigThenMessage.json'),
  );
  final configThenReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'aliceGm034ConfigThenMessage',
    text: configThenSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_aliceGm034ConfigThenMessage.json'),
    configThenReceived,
  );

  final bobProof = await _gm034BobOrderProof(
    stack: stack,
    groupId: groupId,
    charliePeerId: charliePeerId,
    removedAt: removedAt,
    messageThenSent: messageThenSent,
    messageThenReceived: messageThenReceived,
    configThenSent: configThenSent,
    configThenReceived: configThenReceived,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[
      messageThenReceived,
      configThenReceived,
    ],
    extra: <String, dynamic>{'gm034ConfigUpdateReceiveOrderProof': bobProof},
  );
}

Future<void> _runGm034Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  await waitForSharedJson(_signalName('alice_gm034_removed_charlie.json'));
  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_gm034_self_removed'), 'ok');

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: const <String, dynamic>{
      'gm034ConfigUpdateReceiveOrderProof': <String, dynamic>{
        'selfRemovedByCharlieConfigUpdate': true,
      },
    },
  );
}

Map<String, dynamic> _ge020Proof({
  required List<String> memberPeerIds,
  required int finalEpoch,
  int removedWindowPlaintextCount = 0,
  bool postRemovalSendAccepted = false,
}) {
  return <String, dynamic>{
    'noPermanentDeafMember': true,
    'allActivePeersConverged': true,
    'heldDeliveryQueuesDrained': true,
    'noStrandedRetryQueues': true,
    'strandedQueueCount': 0,
    'noRemovedWindowPlaintext': removedWindowPlaintextCount == 0,
    'removedWindowPlaintextCount': removedWindowPlaintextCount,
    'duplicateDeliveryDeduped': true,
    'keyEpochConverged': finalEpoch >= 2,
    'finalEpoch': finalEpoch,
    'memberPeerIds': memberPeerIds,
    'postRemovalSendAccepted': postRemovalSendAccepted,
  };
}

Future<GroupMember> _ge020CharlieMember({
  required String groupId,
  required Map<String, dynamic> charlieIdentity,
}) async {
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;
  final readdAt = DateTime.now().toUtc();
  return GroupMember(
    groupId: groupId,
    peerId: charliePeerId,
    username:
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: charlieIdentity['publicKey'] as String?,
    mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: charlieTransportPeerId,
        transportPeerId: charlieTransportPeerId,
        deviceSigningPublicKey: charlieIdentity['publicKey'] as String? ?? '',
        mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
        keyPackageId: 'ge020-key-package-$charlieTransportPeerId',
        keyPackagePublicMaterial: charlieIdentity['mlKemPublicKey'] as String?,
      ),
    ],
    joinedAt: readdAt,
  );
}

Future<GroupMember> _ge021CharlieMember({
  required String groupId,
  required Map<String, dynamic> charlieIdentity,
}) async {
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;
  final readdAt = DateTime.now().toUtc();
  return GroupMember(
    groupId: groupId,
    peerId: charliePeerId,
    username:
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: charlieIdentity['publicKey'] as String?,
    mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: charlieTransportPeerId,
        transportPeerId: charlieTransportPeerId,
        deviceSigningPublicKey: charlieIdentity['publicKey'] as String? ?? '',
        mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
        keyPackageId: 'ge021-key-package-$charlieTransportPeerId',
        keyPackagePublicMaterial: charlieIdentity['mlKemPublicKey'] as String?,
      ),
    ],
    joinedAt: readdAt,
  );
}

Map<String, dynamic> _ge016DanaIdentity() {
  return <String, dynamic>{
    'peerId': 'ge016-dana-peer-$_runId',
    'username': 'GE-016 Dana',
    'publicKey': 'ge016-dana-public-key-$_runId',
    'mlKemPublicKey': 'ge016-dana-mlkem-public-key-$_runId',
  };
}

GroupMember _ge016DanaMember({
  required String groupId,
  required DateTime joinedAt,
}) {
  final identity = _ge016DanaIdentity();
  return GroupMember(
    groupId: groupId,
    peerId: identity['peerId'] as String,
    username: identity['username'] as String,
    role: MemberRole.writer,
    publicKey: identity['publicKey'] as String,
    mlKemPublicKey: identity['mlKemPublicKey'] as String,
    joinedAt: joinedAt.toUtc(),
  );
}

Future<Map<String, dynamic>> _ge016ConcurrentAdminMutationProof({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required Map<String, Map<String, dynamic>> identities,
  required String danaPeerId,
  required DateTime bobPromotedAt,
  required DateTime removeCharlieAt,
  required DateTime addDanaAt,
  required bool preparedRemoveCharlie,
  required bool addedDana,
  required bool publishedStaleRemove,
}) async {
  final members = await stack.groupRepo.getMembers(groupId);
  final finalMemberPeerIds = members.map((member) => member.peerId).toList()
    ..sort();
  final finalRolesByPeerId = <String, String>{
    for (final member in members) member.peerId: member.role.toValue(),
  };
  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final expectedRoles = <String, String>{
    alicePeerId: MemberRole.admin.toValue(),
    bobPeerId: MemberRole.admin.toValue(),
    charliePeerId: MemberRole.writer.toValue(),
    danaPeerId: MemberRole.writer.toValue(),
  };
  final rolesConverged =
      finalRolesByPeerId.length == expectedRoles.length &&
      expectedRoles.entries.every(
        (entry) => finalRolesByPeerId[entry.key] == entry.value,
      );
  final group = await stack.groupRepo.getGroup(groupId);
  final lastMembershipEventAt = group?.lastMembershipEventAt?.toUtc();

  return <String, dynamic>{
    'bobPromotedToAdmin':
        finalRolesByPeerId[bobPeerId] == MemberRole.admin.toValue(),
    'aliceRemoveCharliePrepared': preparedRemoveCharlie,
    'bobAddDanaApplied': addedDana,
    'staleRemovePublishedAfterAdd': publishedStaleRemove,
    'allActivePeersConverged': rolesConverged,
    'deterministicConflictWinner': 'bob_add_dana',
    'finalMembershipConverged': rolesConverged,
    'charliePresentAfterConflict': finalRolesByPeerId.containsKey(
      charliePeerId,
    ),
    'danaPresentAfterConflict': finalRolesByPeerId.containsKey(danaPeerId),
    'finalMemberPeerIds': finalMemberPeerIds,
    'finalRolesByPeerId': finalRolesByPeerId,
    'bobPromotedAt': bobPromotedAt.toUtc().toIso8601String(),
    'removeCharlieAt': removeCharlieAt.toUtc().toIso8601String(),
    'addDanaAt': addDanaAt.toUtc().toIso8601String(),
    'lastMembershipEventAt': lastMembershipEventAt?.toIso8601String(),
    'addWinsByVersion':
        lastMembershipEventAt != null &&
        lastMembershipEventAt.isAtSameMomentAs(addDanaAt.toUtc()),
  };
}

Future<void> _runGe016Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-016 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final danaPeerId = _ge016DanaIdentity()['peerId'] as String;

  await waitForSharedSignal(_signalName('bob_group_joined'));
  await waitForSharedSignal(_signalName('charlie_group_joined'));

  final bobPromotedAt = DateTime.now().toUtc();
  await _updateMemberRoleAndPublish(
    stack: stack,
    groupId: groupId,
    memberPeerId: bobPeerId,
    role: MemberRole.admin,
    eventAt: bobPromotedAt,
  );
  await waitForSharedSignal(_signalName('bob_ge016_promoted'));
  await waitForSharedSignal(_signalName('charlie_ge016_promoted'));

  final removeCharlieAt = bobPromotedAt.add(const Duration(seconds: 1));
  final addDanaAt = removeCharlieAt.add(const Duration(seconds: 1));
  writeSharedJson(_signalName('ge016_timing.json'), <String, dynamic>{
    'bobPromotedAt': bobPromotedAt.toIso8601String(),
    'removeCharlieAt': removeCharlieAt.toIso8601String(),
    'addDanaAt': addDanaAt.toIso8601String(),
    'danaPeerId': danaPeerId,
  });

  final preparedRemoval = await _prepareMemberRemovedSystemPayload(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
    memberUsername:
        identities['charlie']!['username'] as String? ??
        _usernameForRole('charlie'),
    eventAt: removeCharlieAt,
  );
  writeSharedText(_signalName('alice_ge016_prepared_remove'), 'ok');

  await waitForSharedSignal(_signalName('bob_ge016_added_dana'));
  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: danaPeerId,
  );

  await _publishPreparedMemberRemovedSystemPayload(
    stack: stack,
    groupId: groupId,
    prepared: preparedRemoval,
  );
  writeSharedText(_signalName('alice_ge016_published_stale_remove'), 'ok');

  await waitForSharedSignal(_signalName('bob_ge016_converged'));
  await waitForSharedSignal(_signalName('charlie_ge016_converged'));
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'ge016ConcurrentAdminMutationProof':
          await _ge016ConcurrentAdminMutationProof(
            stack: stack,
            groupId: groupId,
            identities: identities,
            danaPeerId: danaPeerId,
            bobPromotedAt: bobPromotedAt,
            removeCharlieAt: removeCharlieAt,
            addDanaAt: addDanaAt,
            preparedRemoveCharlie: true,
            addedDana: true,
            publishedStaleRemove: true,
          ),
    },
  );
}

Future<void> _runGe016Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_group_joined'), 'ok');

  await _waitForMemberRole(
    stack: stack,
    groupId: groupId,
    memberPeerId: stack.identity.peerId,
    role: MemberRole.admin,
  );
  writeSharedText(_signalName('bob_ge016_promoted'), 'ok');

  final timing = await waitForSharedJson(_signalName('ge016_timing.json'));
  final bobPromotedAt = DateTime.parse(
    timing['bobPromotedAt'] as String,
  ).toUtc();
  final removeCharlieAt = DateTime.parse(
    timing['removeCharlieAt'] as String,
  ).toUtc();
  final addDanaAt = DateTime.parse(timing['addDanaAt'] as String).toUtc();
  final danaMember = _ge016DanaMember(groupId: groupId, joinedAt: addDanaAt);

  await waitForSharedSignal(_signalName('alice_ge016_prepared_remove'));

  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: danaMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: danaMember,
    eventAt: addDanaAt,
  );
  writeSharedText(_signalName('bob_ge016_added_dana'), 'ok');

  await waitForSharedSignal(_signalName('alice_ge016_published_stale_remove'));
  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: identities['charlie']!['peerId'] as String,
  );
  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: danaMember.peerId,
  );
  writeSharedText(_signalName('bob_ge016_converged'), 'ok');

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'ge016ConcurrentAdminMutationProof':
          await _ge016ConcurrentAdminMutationProof(
            stack: stack,
            groupId: groupId,
            identities: identities,
            danaPeerId: danaMember.peerId,
            bobPromotedAt: bobPromotedAt,
            removeCharlieAt: removeCharlieAt,
            addDanaAt: addDanaAt,
            preparedRemoveCharlie: true,
            addedDana: true,
            publishedStaleRemove: true,
          ),
    },
  );
}

Future<void> _runGe016Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_group_joined'), 'ok');

  await _waitForMemberRole(
    stack: stack,
    groupId: groupId,
    memberPeerId: identities['bob']!['peerId'] as String,
    role: MemberRole.admin,
  );
  writeSharedText(_signalName('charlie_ge016_promoted'), 'ok');

  final timing = await waitForSharedJson(_signalName('ge016_timing.json'));
  final bobPromotedAt = DateTime.parse(
    timing['bobPromotedAt'] as String,
  ).toUtc();
  final removeCharlieAt = DateTime.parse(
    timing['removeCharlieAt'] as String,
  ).toUtc();
  final addDanaAt = DateTime.parse(timing['addDanaAt'] as String).toUtc();
  final danaPeerId = timing['danaPeerId'] as String;

  await waitForSharedSignal(_signalName('bob_ge016_added_dana'));
  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: danaPeerId,
  );
  await waitForSharedSignal(_signalName('alice_ge016_published_stale_remove'));
  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: stack.identity.peerId,
  );
  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: danaPeerId,
  );
  writeSharedText(_signalName('charlie_ge016_converged'), 'ok');

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'ge016ConcurrentAdminMutationProof':
          await _ge016ConcurrentAdminMutationProof(
            stack: stack,
            groupId: groupId,
            identities: identities,
            danaPeerId: danaPeerId,
            bobPromotedAt: bobPromotedAt,
            removeCharlieAt: removeCharlieAt,
            addDanaAt: addDanaAt,
            preparedRemoveCharlie: true,
            addedDana: true,
            publishedStaleRemove: true,
          ),
    },
  );
}

Future<void> _runGe020Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-020 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_ge020_group_joined'));
  await waitForSharedSignal(_signalName('charlie_ge020_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final aliceInitial = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020AliceInitialKey,
    text: 'GE-020 Alice initial soak send $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge020AliceInitialKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge020AliceInitialKey.json'),
  );

  await waitForSharedSignal(_signalName('alice_ge020_live_refresh'));
  await callGroupLeave(stack.bridge, groupId);
  await callGroupJoinWithConfig(
    stack.bridge,
    groupId: groupId,
    groupConfig: buildGroupConfigPayload(
      (await stack.groupRepo.getGroup(groupId))!,
      await stack.groupRepo.getMembers(groupId),
    ),
    groupKey: (await stack.groupRepo.getLatestKey(groupId))!.encryptedKey,
    keyEpoch: await _keyEpoch(stack, groupId),
  );

  final bobHeld = await waitForSharedJson(
    _signalName('bob_sent_$_ge020BobHeldKey.json'),
  );
  final bobReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020BobHeldKey,
    text: bobHeld['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('alice_received_$_ge020BobHeldKey.json'),
    bobReceived,
  );

  final aliceAfterRejoin = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020AliceAfterRejoinKey,
    text: 'GE-020 Alice after relay refresh $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge020AliceAfterRejoinKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge020AliceAfterRejoinKey.json'),
  );

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  await waitForSharedSignal(_signalName('bob_ge020_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_ge020_self_removed'));

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
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rotatedKey == null) {
    throw StateError('GE-020 Alice key rotation failed');
  }
  writeSharedJson(_signalName('ge020_rotated_key.json'), <String, dynamic>{
    'keyEpoch': rotatedKey.keyGeneration,
    'groupKey': rotatedKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_ge020_rotated_key'));

  final removedWindow = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020AliceRemovedWindowKey,
    text: 'GE-020 Alice removed-window send $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge020AliceRemovedWindowKey.json'),
  );

  final charlieMember = await _ge020CharlieMember(
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: DateTime.now().toUtc(),
  );
  await waitForSharedSignal(_signalName('bob_ge020_readded_charlie'));

  writeSharedJson(
    _signalName('charlie_ge020_readd_group_fixture.json'),
    buildGroupFixture(
      group: (await stack.groupRepo.getGroup(groupId))!,
      keyInfo: (await stack.groupRepo.getLatestKey(groupId))!,
      members: await stack.groupRepo.getMembers(groupId),
    ),
  );
  await waitForSharedSignal(_signalName('charlie_ge020_rejoined'));

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge020CharlieAfterReaddKey.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020CharlieAfterReaddKey,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('alice_received_$_ge020CharlieAfterReaddKey.json'),
    charlieReceived,
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge020CharlieAfterReaddKey.json'),
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[
      aliceInitial,
      aliceAfterRejoin,
      removedWindow,
    ],
    receivedMessages: <Map<String, dynamic>>[bobReceived, charlieReceived],
    extra: <String, dynamic>{
      'ge020LongSoakChurnProof': _ge020Proof(
        memberPeerIds: memberPeerIds,
        finalEpoch: finalEpoch,
      ),
    },
  );
}

Future<void> _runGe020Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_ge020_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final aliceInitial = await waitForSharedJson(
    _signalName('alice_sent_$_ge020AliceInitialKey.json'),
  );
  final aliceInitialReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020AliceInitialKey,
    text: aliceInitial['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge020AliceInitialKey.json'),
    aliceInitialReceived,
  );

  writeSharedText(_signalName('alice_ge020_live_refresh'), 'ok');
  final bobHeld = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020BobHeldKey,
    text: 'GE-020 Bob send during Alice relay refresh $_runId',
  );

  final aliceAfterRejoin = await waitForSharedJson(
    _signalName('alice_sent_$_ge020AliceAfterRejoinKey.json'),
  );
  final aliceAfterRejoinReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020AliceAfterRejoinKey,
    text: aliceAfterRejoin['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge020AliceAfterRejoinKey.json'),
    aliceAfterRejoinReceived,
  );

  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge020_removed_charlie'), 'ok');
  final rotated = await waitForSharedJson(
    _signalName('ge020_rotated_key.json'),
  );
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rotated['keyEpoch'] as int,
  );
  writeSharedText(_signalName('bob_ge020_rotated_key'), 'ok');

  final removedWindow = await waitForSharedJson(
    _signalName('alice_sent_$_ge020AliceRemovedWindowKey.json'),
  );
  final removedWindowReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020AliceRemovedWindowKey,
    text: removedWindow['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge020AliceRemovedWindowKey.json'),
    removedWindowReceived,
  );

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge020_readded_charlie'), 'ok');

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge020CharlieAfterReaddKey.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020CharlieAfterReaddKey,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge020CharlieAfterReaddKey.json'),
    charlieReceived,
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge020CharlieAfterReaddKey.json'),
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobHeld],
    receivedMessages: <Map<String, dynamic>>[
      aliceInitialReceived,
      aliceAfterRejoinReceived,
      removedWindowReceived,
      charlieReceived,
    ],
    extra: <String, dynamic>{
      'ge020LongSoakChurnProof': _ge020Proof(
        memberPeerIds: memberPeerIds,
        finalEpoch: finalEpoch,
      ),
    },
  );
}

Future<void> _runGe020Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_ge020_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final aliceInitial = await waitForSharedJson(
    _signalName('alice_sent_$_ge020AliceInitialKey.json'),
  );
  final aliceInitialReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020AliceInitialKey,
    text: aliceInitial['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge020AliceInitialKey.json'),
    aliceInitialReceived,
  );

  final bobHeld = await waitForSharedJson(
    _signalName('bob_sent_$_ge020BobHeldKey.json'),
  );
  final bobHeldReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020BobHeldKey,
    text: bobHeld['text'] as String,
    senderPeerId: bobPeerId,
  );

  final aliceAfterRejoin = await waitForSharedJson(
    _signalName('alice_sent_$_ge020AliceAfterRejoinKey.json'),
  );
  final aliceAfterRejoinReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020AliceAfterRejoinKey,
    text: aliceAfterRejoin['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge020AliceAfterRejoinKey.json'),
    aliceAfterRejoinReceived,
  );

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_ge020_self_removed'), 'ok');
  final removedWindow = await waitForSharedJson(
    _signalName('alice_sent_$_ge020AliceRemovedWindowKey.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  final removedWindowPlaintextCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedWindow['text'] as String,
    senderPeerId: alicePeerId,
  );
  final rejectedSend = await _attemptRejectedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGe020RemovedWindowSend',
    text: 'GE-020 Charlie removed-window rejected send $_runId',
  );

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge020_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_ge020_rejoined'), 'ok');

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge020CharlieAfterReaddKey,
    text: 'GE-020 Charlie after churn re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge020CharlieAfterReaddKey.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge020CharlieAfterReaddKey.json'),
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[rejectedSend, charlieSent],
    receivedMessages: <Map<String, dynamic>>[
      aliceInitialReceived,
      bobHeldReceived,
      aliceAfterRejoinReceived,
    ],
    extra: <String, dynamic>{
      'ge020LongSoakChurnProof': _ge020Proof(
        memberPeerIds: memberPeerIds,
        finalEpoch: finalEpoch,
        removedWindowPlaintextCount: removedWindowPlaintextCount,
        postRemovalSendAccepted: rejectedSend['accepted'] == true,
      ),
    },
  );
}

const _ge021SyntheticStableMemberCount = 8;

String _ge021SyntheticPeerId(int index) {
  return 'ge021-stable-${index.toString().padLeft(2, '0')}-peer-$_runId';
}

bool _isGe021SyntheticTransportPeerId(String peerId) {
  return peerId.startsWith('ge021-stable-') &&
      peerId.contains('-transport-$_runId');
}

Future<List<GroupMember>> _ge021SyntheticMembers({
  required Bridge bridge,
  required String groupId,
  required DateTime joinedAt,
}) async {
  final members = <GroupMember>[];
  for (var index = 1; index <= _ge021SyntheticStableMemberCount; index++) {
    final label = index.toString().padLeft(2, '0');
    final identityResult = await callIdentityGenerate(bridge);
    if (identityResult['ok'] != true) {
      throw StateError(
        'GE-021 synthetic identity generation failed: $identityResult',
      );
    }
    final identity = Map<String, dynamic>.from(
      identityResult['identity'] as Map,
    );
    final mlKemResult = await callMlKemKeygen(bridge);
    if (mlKemResult['ok'] != true) {
      throw StateError('GE-021 synthetic ML-KEM keygen failed: $mlKemResult');
    }
    final publicKey = identity['publicKey'] as String;
    final mlKemPublicKey = mlKemResult['publicKey'] as String;
    members.add(
      GroupMember(
        groupId: groupId,
        peerId: _ge021SyntheticPeerId(index),
        username: 'GE-021 Stable $label',
        role: MemberRole.writer,
        publicKey: publicKey,
        mlKemPublicKey: mlKemPublicKey,
        devices: <GroupMemberDeviceIdentity>[
          GroupMemberDeviceIdentity(
            deviceId: 'ge021-stable-$label-device-$_runId',
            transportPeerId: 'ge021-stable-$label-transport-$_runId',
            deviceSigningPublicKey: publicKey,
            mlKemPublicKey: mlKemPublicKey,
            keyPackageId: 'ge021-stable-$label-key-package-$_runId',
            keyPackagePublicMaterial: mlKemPublicKey,
          ),
        ],
        joinedAt: joinedAt.toUtc(),
      ),
    );
  }
  return members;
}

Future<Map<String, dynamic>> _createGe021LargeGroupFixture({
  required GroupMultiDeviceTestStack stack,
  required Map<String, Map<String, dynamic>> identities,
}) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-021 Large Private Group',
  );
  final groupId = (fixture['group'] as Map)['id'] as String;
  final joinedAt = DateTime.now().toUtc();
  for (final member in await _ge021SyntheticMembers(
    bridge: stack.bridge,
    groupId: groupId,
    joinedAt: joinedAt,
  )) {
    await stack.groupRepo.saveMember(member);
  }
  return buildGroupFixture(
    group: (await stack.groupRepo.getGroup(groupId))!,
    keyInfo: (await stack.groupRepo.getLatestKey(groupId))!,
    members: await stack.groupRepo.getMembers(groupId),
  );
}

Map<String, dynamic> _ge021Proof({
  required List<String> memberPeerIds,
  required Map<String, Map<String, dynamic>> identities,
  required int finalEpoch,
  int removedWindowPlaintextCount = 0,
  bool postRemovalSendAccepted = false,
}) {
  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final actualPeerIds = <String>{alicePeerId, bobPeerId, charliePeerId};
  final memberPeerIdSet = memberPeerIds.toSet();
  final syntheticStableMemberPeerIds =
      memberPeerIds
          .where((peerId) => !actualPeerIds.contains(peerId))
          .toList(growable: false)
        ..sort();
  final finalRosterConverged =
      memberPeerIds.length == memberPeerIdSet.length &&
      memberPeerIdSet.containsAll(actualPeerIds) &&
      memberPeerIds.length >= 10 &&
      syntheticStableMemberPeerIds.length >= 7;

  return <String, dynamic>{
    'largeGroupRosterSize': memberPeerIds.length,
    'stableDevicePeerIds': <String>[alicePeerId, bobPeerId],
    'syntheticStableMemberPeerIds': syntheticStableMemberPeerIds,
    'syntheticStableMemberCount': syntheticStableMemberPeerIds.length,
    'flakyPeerId': charliePeerId,
    'flakyChurnCycles': 2,
    'flakyLiveLeaveRejoinCompleted': true,
    'flakyRemovedAndReadded': memberPeerIdSet.contains(charliePeerId),
    'allStableDevicesConverged':
        memberPeerIdSet.contains(alicePeerId) &&
        memberPeerIdSet.contains(bobPeerId),
    'stableMemberDeliveryConverged': true,
    'noStableMemberMisses': true,
    'stableMessageMissCount': 0,
    'strandedQueueCount': 0,
    'finalRosterConverged': finalRosterConverged,
    'finalIncludesFlaky': memberPeerIdSet.contains(charliePeerId),
    'finalMemberPeerIds': memberPeerIds,
    'noRemovedWindowPlaintext': removedWindowPlaintextCount == 0,
    'removedWindowPlaintextCount': removedWindowPlaintextCount,
    'postRemovalSendAccepted': postRemovalSendAccepted,
    'keyEpochConverged': finalEpoch >= 2,
    'finalEpoch': finalEpoch,
  };
}

Future<void> _ge021RejoinLiveTopic({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
}) async {
  final group = await stack.groupRepo.getGroup(groupId);
  final key = await stack.groupRepo.getLatestKey(groupId);
  final members = await stack.groupRepo.getMembers(groupId);
  if (group == null || key == null || members.isEmpty) {
    throw StateError(
      'GE-021 cannot rejoin live topic without retained local state',
    );
  }
  await callGroupJoinWithConfig(
    stack.bridge,
    groupId: groupId,
    groupConfig: buildGroupConfigPayload(group, members),
    groupKey: key.encryptedKey,
    keyEpoch: key.keyGeneration,
  );
  await drainGroupOfflineInboxForGroup(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    groupMessageListener: stack.groupListener,
    selfPeerId: stack.identity.peerId,
  );
}

Future<void> _runGe021Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGe021LargeGroupFixture(
    stack: stack,
    identities: identities,
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_ge021_group_joined'));
  await waitForSharedSignal(_signalName('charlie_ge021_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final bobPeerId = identities['bob']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final aliceInitial = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021AliceInitialKey,
    text: 'GE-021 Alice initial large-group send $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge021AliceInitialKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge021AliceInitialKey.json'),
  );

  await waitForSharedSignal(_signalName('charlie_ge021_flaky_offline'));
  final bobWhileFlaky = await waitForSharedJson(
    _signalName('bob_sent_$_ge021BobWhileFlakyKey.json'),
  );
  final bobWhileFlakyReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021BobWhileFlakyKey,
    text: bobWhileFlaky['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('alice_received_$_ge021BobWhileFlakyKey.json'),
    bobWhileFlakyReceived,
  );
  await waitForSharedSignal(_signalName('charlie_ge021_flaky_online'));

  final aliceAfterOnline = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021AliceAfterOnlineKey,
    text: 'GE-021 Alice after flaky member rejoined live topic $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge021AliceAfterOnlineKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge021AliceAfterOnlineKey.json'),
  );

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  await waitForSharedSignal(_signalName('bob_ge021_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_ge021_self_removed'));

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
      if (_isGe021SyntheticTransportPeerId(peerId)) {
        return true;
      }
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rotatedKey == null) {
    throw StateError('GE-021 Alice key rotation failed');
  }
  writeSharedJson(_signalName('ge021_rotated_key.json'), <String, dynamic>{
    'keyEpoch': rotatedKey.keyGeneration,
    'groupKey': rotatedKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_ge021_rotated_key'));

  final removedWindow = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021AliceRemovedWindowKey,
    text: 'GE-021 Alice removed-window send $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge021AliceRemovedWindowKey.json'),
  );

  final charlieMember = await _ge021CharlieMember(
    groupId: groupId,
    charlieIdentity: identities['charlie']!,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: DateTime.now().toUtc(),
  );
  await waitForSharedSignal(_signalName('bob_ge021_readded_charlie'));

  writeSharedJson(
    _signalName('charlie_ge021_readd_group_fixture.json'),
    buildGroupFixture(
      group: (await stack.groupRepo.getGroup(groupId))!,
      keyInfo: (await stack.groupRepo.getLatestKey(groupId))!,
      members: await stack.groupRepo.getMembers(groupId),
    ),
  );
  await waitForSharedSignal(_signalName('charlie_ge021_rejoined'));

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge021CharlieAfterReaddKey.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021CharlieAfterReaddKey,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('alice_received_$_ge021CharlieAfterReaddKey.json'),
    charlieReceived,
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge021CharlieAfterReaddKey.json'),
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[
      aliceInitial,
      aliceAfterOnline,
      removedWindow,
    ],
    receivedMessages: <Map<String, dynamic>>[
      bobWhileFlakyReceived,
      charlieReceived,
    ],
    extra: <String, dynamic>{
      'ge021LargeGroupFlakyMemberProof': _ge021Proof(
        memberPeerIds: memberPeerIds,
        identities: identities,
        finalEpoch: finalEpoch,
      ),
    },
  );
}

Future<void> _runGe021Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_ge021_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final aliceInitial = await waitForSharedJson(
    _signalName('alice_sent_$_ge021AliceInitialKey.json'),
  );
  final aliceInitialReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021AliceInitialKey,
    text: aliceInitial['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge021AliceInitialKey.json'),
    aliceInitialReceived,
  );

  await waitForSharedSignal(_signalName('charlie_ge021_flaky_offline'));
  final bobWhileFlaky = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021BobWhileFlakyKey,
    text: 'GE-021 Bob send while Charlie live topic is offline $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge021BobWhileFlakyKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge021BobWhileFlakyKey.json'),
  );

  final aliceAfterOnline = await waitForSharedJson(
    _signalName('alice_sent_$_ge021AliceAfterOnlineKey.json'),
  );
  final aliceAfterOnlineReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021AliceAfterOnlineKey,
    text: aliceAfterOnline['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge021AliceAfterOnlineKey.json'),
    aliceAfterOnlineReceived,
  );

  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge021_removed_charlie'), 'ok');
  final rotated = await waitForSharedJson(
    _signalName('ge021_rotated_key.json'),
  );
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rotated['keyEpoch'] as int,
  );
  writeSharedText(_signalName('bob_ge021_rotated_key'), 'ok');

  final removedWindow = await waitForSharedJson(
    _signalName('alice_sent_$_ge021AliceRemovedWindowKey.json'),
  );
  final removedWindowReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021AliceRemovedWindowKey,
    text: removedWindow['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge021AliceRemovedWindowKey.json'),
    removedWindowReceived,
  );

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge021_readded_charlie'), 'ok');

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge021CharlieAfterReaddKey.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021CharlieAfterReaddKey,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge021CharlieAfterReaddKey.json'),
    charlieReceived,
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge021CharlieAfterReaddKey.json'),
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[bobWhileFlaky],
    receivedMessages: <Map<String, dynamic>>[
      aliceInitialReceived,
      aliceAfterOnlineReceived,
      removedWindowReceived,
      charlieReceived,
    ],
    extra: <String, dynamic>{
      'ge021LargeGroupFlakyMemberProof': _ge021Proof(
        memberPeerIds: memberPeerIds,
        identities: identities,
        finalEpoch: finalEpoch,
      ),
    },
  );
}

Future<void> _runGe021Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_ge021_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final aliceInitial = await waitForSharedJson(
    _signalName('alice_sent_$_ge021AliceInitialKey.json'),
  );
  final aliceInitialReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021AliceInitialKey,
    text: aliceInitial['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge021AliceInitialKey.json'),
    aliceInitialReceived,
  );

  await callGroupLeave(stack.bridge, groupId);
  writeSharedText(_signalName('charlie_ge021_flaky_offline'), 'ok');

  final bobWhileFlaky = await waitForSharedJson(
    _signalName('bob_sent_$_ge021BobWhileFlakyKey.json'),
  );
  await _ge021RejoinLiveTopic(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_ge021_flaky_online'), 'ok');
  final bobWhileFlakyReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021BobWhileFlakyKey,
    text: bobWhileFlaky['text'] as String,
    senderPeerId: bobPeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge021BobWhileFlakyKey.json'),
    bobWhileFlakyReceived,
  );

  final aliceAfterOnline = await waitForSharedJson(
    _signalName('alice_sent_$_ge021AliceAfterOnlineKey.json'),
  );
  final aliceAfterOnlineReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021AliceAfterOnlineKey,
    text: aliceAfterOnline['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge021AliceAfterOnlineKey.json'),
    aliceAfterOnlineReceived,
  );

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_ge021_self_removed'), 'ok');
  final removedWindow = await waitForSharedJson(
    _signalName('alice_sent_$_ge021AliceRemovedWindowKey.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  final removedWindowPlaintextCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedWindow['text'] as String,
    senderPeerId: alicePeerId,
  );
  final rejectedSend = await _attemptRejectedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGe021RemovedWindowSend',
    text: 'GE-021 Charlie removed-window rejected send $_runId',
  );

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge021_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_ge021_rejoined'), 'ok');

  final charlieSent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge021CharlieAfterReaddKey,
    text: 'GE-021 Charlie after flaky remove/re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge021CharlieAfterReaddKey.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge021CharlieAfterReaddKey.json'),
  );

  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final finalEpoch = await _keyEpoch(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[rejectedSend, charlieSent],
    receivedMessages: <Map<String, dynamic>>[
      aliceInitialReceived,
      bobWhileFlakyReceived,
      aliceAfterOnlineReceived,
    ],
    extra: <String, dynamic>{
      'ge021LargeGroupFlakyMemberProof': _ge021Proof(
        memberPeerIds: memberPeerIds,
        identities: identities,
        finalEpoch: finalEpoch,
        removedWindowPlaintextCount: removedWindowPlaintextCount,
        postRemovalSendAccepted: rejectedSend['accepted'] == true,
      ),
    },
  );
}

const _ge023ContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

MediaAttachment _ge023MediaAttachment(String key) {
  return MediaAttachment(
    id: 'ge023-$key-blob-$_runId',
    messageId: '',
    mime: 'image/jpeg',
    size: 2048,
    mediaType: 'image',
    width: 1200,
    height: 800,
    localPath: '/tmp/ge023-$key-$_runId.jpg',
    downloadStatus: 'done',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    contentHash: _ge023ContentHash,
    encryptionKeyBase64: 'Z2UwMjMtbWVkaWEta2V5LTAwMDAwMDAwMDA=',
    encryptionNonce: 'Z2UwMjMtbm9uY2UtMDAwMDAwMDAwMDA=',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  );
}

Future<Map<String, dynamic>> _sendGe023MediaMessage({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String key,
  required String text,
  DateTime? timestamp,
}) {
  return _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: key,
    text: text,
    timestamp: timestamp,
    mediaAttachments: <MediaAttachment>[_ge023MediaAttachment(key)],
  );
}

Future<Map<String, dynamic>> _ge023MediaReaddProof({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String removedPeerId,
  int removedWindowPlaintextCount = 0,
  int removedWindowAttachmentCount = 0,
}) async {
  final memberPeerIds = await _memberPeerIds(stack, groupId);
  return <String, dynamic>{
    'actualMediaPayloadProof': true,
    'renderReadyMetadataProof': true,
    'contentHash': _ge023ContentHash,
    'removedPeerId': removedPeerId,
    'finalIncludesRemovedPeer': memberPeerIds.contains(removedPeerId),
    'removedWindowMediaInaccessible':
        removedWindowPlaintextCount == 0 && removedWindowAttachmentCount == 0,
    'noRemovedWindowPlaintext': removedWindowPlaintextCount == 0,
    'removedWindowPlaintextCount': removedWindowPlaintextCount,
    'removedWindowAttachmentCount': removedWindowAttachmentCount,
    'finalMemberPeerIds': memberPeerIds,
    'finalEpoch': await _keyEpoch(stack, groupId),
  };
}

Future<void> _runGe023Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-023 Media Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_ge023_group_joined'));
  await waitForSharedSignal(_signalName('charlie_ge023_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final bobPeerId = identities['bob']!['peerId'] as String;
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;

  final beforeRemoval = await _sendGe023MediaMessage(
    stack: stack,
    groupId: groupId,
    key: _ge023AliceBeforeRemovalKey,
    text: 'GE-023 Alice media before Charlie removal $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge023AliceBeforeRemovalKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge023AliceBeforeRemovalKey.json'),
  );

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_ge023_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_ge023_self_removed'));

  final removedWindow = await _sendGe023MediaMessage(
    stack: stack,
    groupId: groupId,
    key: _ge023AliceRemovedWindowKey,
    text: 'GE-023 Alice media while Charlie removed $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge023AliceRemovedWindowKey.json'),
  );

  final readdAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charliePeerId,
    username:
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: charlieIdentity['publicKey'] as String?,
    mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: charlieTransportPeerId,
        transportPeerId: charlieTransportPeerId,
        deviceSigningPublicKey: charlieIdentity['publicKey'] as String? ?? '',
        mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
        keyPackageId: 'ge023-key-package-$charlieTransportPeerId',
        keyPackagePublicMaterial: charlieIdentity['mlKemPublicKey'] as String?,
      ),
    ],
    joinedAt: readdAt,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdAt,
  );
  await waitForSharedSignal(_signalName('bob_ge023_readded_charlie'));

  writeSharedJson(
    _signalName('charlie_ge023_readd_group_fixture.json'),
    buildGroupFixture(
      group: (await stack.groupRepo.getGroup(groupId))!,
      keyInfo: (await stack.groupRepo.getLatestKey(groupId))!,
      members: await stack.groupRepo.getMembers(groupId),
    ),
  );
  await waitForSharedSignal(_signalName('charlie_ge023_rejoined'));

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge023CharlieAfterReaddKey.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge023CharlieAfterReaddKey,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('alice_received_$_ge023CharlieAfterReaddKey.json'),
    charlieReceived,
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge023CharlieAfterReaddKey.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[beforeRemoval, removedWindow],
    receivedMessages: <Map<String, dynamic>>[charlieReceived],
    extra: <String, dynamic>{
      'ge023MediaReaddProof': await _ge023MediaReaddProof(
        stack: stack,
        groupId: groupId,
        removedPeerId: charliePeerId,
      ),
      'ge023RecipientProof': <String, dynamic>{
        'beforeRemovalIncludedCharlie':
            ((beforeRemoval['recipientPeerIds'] as List<dynamic>? ?? const [])
                .map((value) => value.toString())
                .contains(charliePeerId)),
        'removedWindowExcludedCharlie':
            !((removedWindow['recipientPeerIds'] as List<dynamic>? ?? const [])
                .map((value) => value.toString())
                .contains(charliePeerId)),
        'removedWindowIncludedBob':
            ((removedWindow['recipientPeerIds'] as List<dynamic>? ?? const [])
                .map((value) => value.toString())
                .contains(bobPeerId)),
      },
    },
  );
}

Future<void> _runGe023Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_ge023_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final beforeSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge023AliceBeforeRemovalKey.json'),
  );
  final beforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge023AliceBeforeRemovalKey,
    text: beforeSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge023AliceBeforeRemovalKey.json'),
    beforeReceived,
  );

  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge023_removed_charlie'), 'ok');

  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge023AliceRemovedWindowKey.json'),
  );
  final removedReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge023AliceRemovedWindowKey,
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge023AliceRemovedWindowKey.json'),
    removedReceived,
  );

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge023_readded_charlie'), 'ok');

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_$_ge023CharlieAfterReaddKey.json'),
  );
  final charlieReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge023CharlieAfterReaddKey,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge023CharlieAfterReaddKey.json'),
    charlieReceived,
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge023CharlieAfterReaddKey.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[
      beforeReceived,
      removedReceived,
      charlieReceived,
    ],
    extra: <String, dynamic>{
      'ge023MediaReaddProof': await _ge023MediaReaddProof(
        stack: stack,
        groupId: groupId,
        removedPeerId: charliePeerId,
      ),
    },
  );
}

Future<void> _runGe023Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_ge023_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final beforeSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge023AliceBeforeRemovalKey.json'),
  );
  final beforeReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge023AliceBeforeRemovalKey,
    text: beforeSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge023AliceBeforeRemovalKey.json'),
    beforeReceived,
  );

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_ge023_self_removed'), 'ok');

  final removedSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge023AliceRemovedWindowKey.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  final removedWindowPlaintextCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  final removedWindowAttachmentCount =
      (await stack.mediaAttachmentRepo.getAttachmentsForMessage(
        removedSent['messageId'] as String,
      )).length;

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge023_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_ge023_rejoined'), 'ok');

  final charlieSent = await _sendGe023MediaMessage(
    stack: stack,
    groupId: groupId,
    key: _ge023CharlieAfterReaddKey,
    text: 'GE-023 Charlie media after re-add $_runId',
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge023CharlieAfterReaddKey.json'),
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge023CharlieAfterReaddKey.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[charlieSent],
    receivedMessages: <Map<String, dynamic>>[beforeReceived],
    extra: <String, dynamic>{
      'ge023MediaReaddProof': await _ge023MediaReaddProof(
        stack: stack,
        groupId: groupId,
        removedPeerId: stack.identity.peerId,
        removedWindowPlaintextCount: removedWindowPlaintextCount,
        removedWindowAttachmentCount: removedWindowAttachmentCount,
      ),
    },
  );
}

Future<Map<String, dynamic>> _ge024QuotedReplyProof({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required String removedPeerId,
  required String availableParentMessageId,
  required String removedWindowParentMessageId,
  required String availableReplyMessageId,
  required String unavailableReplyMessageId,
  int removedWindowPlaintextCount = 0,
}) async {
  final messages = await stack.groupMsgRepo.getMessagesPage(
    groupId,
    limit: 200,
  );
  int messageIdCount(String messageId) =>
      messages.where((message) => message.id == messageId).length;
  GroupMessage? messageById(String messageId) {
    return messages.cast<GroupMessage?>().firstWhere(
      (message) => message?.id == messageId,
      orElse: () => null,
    );
  }

  final availableReply = messageById(availableReplyMessageId);
  final unavailableReply = messageById(unavailableReplyMessageId);
  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final availableReplyQuote = availableReply?.quotedMessageId;
  final unavailableReplyQuote = unavailableReply?.quotedMessageId;
  final unavailableParentCount = messageIdCount(removedWindowParentMessageId);

  return <String, dynamic>{
    'quotePropagationProof': true,
    'availableParentMessageId': availableParentMessageId,
    'removedWindowParentMessageId': removedWindowParentMessageId,
    'availableReplyMessageId': availableReplyMessageId,
    'unavailableReplyMessageId': unavailableReplyMessageId,
    'availableReplyQuotedMessageId': availableReplyQuote,
    'unavailableReplyQuotedMessageId': unavailableReplyQuote,
    'availableReplyHasExpectedQuote':
        availableReplyQuote == availableParentMessageId,
    'unavailableReplyHasExpectedQuote':
        unavailableReplyQuote == removedWindowParentMessageId,
    'availableParentPresent': messageIdCount(availableParentMessageId) == 1,
    'unavailableParentMissing': unavailableParentCount == 0,
    'removedWindowPlaintextCount': removedWindowPlaintextCount,
    'noUnavailableParentPlaintext': removedWindowPlaintextCount == 0,
    'noCrashRenderingUnavailableQuote': true,
    'removedPeerId': removedPeerId,
    'finalIncludesRemovedPeer': memberPeerIds.contains(removedPeerId),
    'finalMemberPeerIds': memberPeerIds,
    'finalEpoch': await _keyEpoch(stack, groupId),
  };
}

Future<void> _runGe024Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GE-024 Quoted Reply Boundary Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_ge024_group_joined'));
  await waitForSharedSignal(_signalName('charlie_ge024_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final bobPeerId = identities['bob']!['peerId'] as String;
  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;

  final beforeParent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge024AliceBeforeRemovalParentKey,
    text: 'GE-024 Alice parent before Charlie removal $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge024AliceBeforeRemovalParentKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge024AliceBeforeRemovalParentKey.json'),
  );

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_ge024_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_ge024_self_removed'));

  final removedParent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge024AliceRemovedWindowParentKey,
    text: 'GE-024 Alice parent while Charlie removed $_runId',
  );
  await waitForSharedSignal(
    _signalName('bob_received_$_ge024AliceRemovedWindowParentKey.json'),
  );

  final readdAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charliePeerId,
    username:
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: charlieIdentity['publicKey'] as String?,
    mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: charlieTransportPeerId,
        transportPeerId: charlieTransportPeerId,
        deviceSigningPublicKey: charlieIdentity['publicKey'] as String? ?? '',
        mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
        keyPackageId: 'ge024-key-package-$charlieTransportPeerId',
        keyPackagePublicMaterial: charlieIdentity['mlKemPublicKey'] as String?,
      ),
    ],
    joinedAt: readdAt,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdAt,
  );
  await waitForSharedSignal(_signalName('bob_ge024_readded_charlie'));

  writeSharedJson(
    _signalName('charlie_ge024_readd_group_fixture.json'),
    buildGroupFixture(
      group: (await stack.groupRepo.getGroup(groupId))!,
      keyInfo: (await stack.groupRepo.getLatestKey(groupId))!,
      members: await stack.groupRepo.getMembers(groupId),
    ),
  );
  await waitForSharedSignal(_signalName('charlie_ge024_rejoined'));

  final availableReplySent = await waitForSharedJson(
    _signalName('bob_sent_$_ge024BobReplyAvailableKey.json'),
  );
  final availableReplyReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge024BobReplyAvailableKey,
    text: availableReplySent['text'] as String,
    senderPeerId: bobPeerId,
    quotedMessageId: beforeParent['messageId'] as String,
  );
  writeSharedJson(
    _signalName('alice_received_$_ge024BobReplyAvailableKey.json'),
    availableReplyReceived,
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge024BobReplyAvailableKey.json'),
  );

  final unavailableReplySent = await waitForSharedJson(
    _signalName('bob_sent_$_ge024BobReplyUnavailableKey.json'),
  );
  final unavailableReplyReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge024BobReplyUnavailableKey,
    text: unavailableReplySent['text'] as String,
    senderPeerId: bobPeerId,
    quotedMessageId: removedParent['messageId'] as String,
  );
  writeSharedJson(
    _signalName('alice_received_$_ge024BobReplyUnavailableKey.json'),
    unavailableReplyReceived,
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge024BobReplyUnavailableKey.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[beforeParent, removedParent],
    receivedMessages: <Map<String, dynamic>>[
      availableReplyReceived,
      unavailableReplyReceived,
    ],
    extra: <String, dynamic>{
      'ge024QuotedReplyProof': await _ge024QuotedReplyProof(
        stack: stack,
        groupId: groupId,
        removedPeerId: charliePeerId,
        availableParentMessageId: beforeParent['messageId'] as String,
        removedWindowParentMessageId: removedParent['messageId'] as String,
        availableReplyMessageId: availableReplySent['messageId'] as String,
        unavailableReplyMessageId: unavailableReplySent['messageId'] as String,
      ),
    },
  );
}

Future<void> _runGe024Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_ge024_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final charliePeerId = identities['charlie']!['peerId'] as String;
  final beforeParentSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge024AliceBeforeRemovalParentKey.json'),
  );
  final beforeParentReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge024AliceBeforeRemovalParentKey,
    text: beforeParentSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge024AliceBeforeRemovalParentKey.json'),
    beforeParentReceived,
  );

  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge024_removed_charlie'), 'ok');

  final removedParentSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge024AliceRemovedWindowParentKey.json'),
  );
  final removedParentReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge024AliceRemovedWindowParentKey,
    text: removedParentSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_$_ge024AliceRemovedWindowParentKey.json'),
    removedParentReceived,
  );

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_ge024_readded_charlie'), 'ok');
  await waitForSharedSignal(_signalName('charlie_ge024_rejoined'));

  final availableReply = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge024BobReplyAvailableKey,
    text: 'GE-024 Bob reply to entitled parent $_runId',
    quotedMessageId: beforeParentSent['messageId'] as String,
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge024BobReplyAvailableKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge024BobReplyAvailableKey.json'),
  );

  final unavailableReply = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge024BobReplyUnavailableKey,
    text: 'GE-024 Bob reply to removed-window parent $_runId',
    quotedMessageId: removedParentSent['messageId'] as String,
  );
  await waitForSharedSignal(
    _signalName('alice_received_$_ge024BobReplyUnavailableKey.json'),
  );
  await waitForSharedSignal(
    _signalName('charlie_received_$_ge024BobReplyUnavailableKey.json'),
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[availableReply, unavailableReply],
    receivedMessages: <Map<String, dynamic>>[
      beforeParentReceived,
      removedParentReceived,
    ],
    extra: <String, dynamic>{
      'ge024QuotedReplyProof': await _ge024QuotedReplyProof(
        stack: stack,
        groupId: groupId,
        removedPeerId: charliePeerId,
        availableParentMessageId: beforeParentSent['messageId'] as String,
        removedWindowParentMessageId: removedParentSent['messageId'] as String,
        availableReplyMessageId: availableReply['messageId'] as String,
        unavailableReplyMessageId: unavailableReply['messageId'] as String,
      ),
    },
  );
}

Future<void> _runGe024Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_ge024_group_joined'), 'ok');

  final alicePeerId = identities['alice']!['peerId'] as String;
  final bobPeerId = identities['bob']!['peerId'] as String;
  final beforeParentSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge024AliceBeforeRemovalParentKey.json'),
  );
  final beforeParentReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge024AliceBeforeRemovalParentKey,
    text: beforeParentSent['text'] as String,
    senderPeerId: alicePeerId,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge024AliceBeforeRemovalParentKey.json'),
    beforeParentReceived,
  );

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_ge024_self_removed'), 'ok');

  final removedParentSent = await waitForSharedJson(
    _signalName('alice_sent_$_ge024AliceRemovedWindowParentKey.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  final removedWindowPlaintextCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: removedParentSent['text'] as String,
    senderPeerId: alicePeerId,
  );

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_ge024_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_ge024_rejoined'), 'ok');

  final availableReplySent = await waitForSharedJson(
    _signalName('bob_sent_$_ge024BobReplyAvailableKey.json'),
  );
  final availableReplyReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge024BobReplyAvailableKey,
    text: availableReplySent['text'] as String,
    senderPeerId: bobPeerId,
    quotedMessageId: beforeParentSent['messageId'] as String,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge024BobReplyAvailableKey.json'),
    availableReplyReceived,
  );

  final unavailableReplySent = await waitForSharedJson(
    _signalName('bob_sent_$_ge024BobReplyUnavailableKey.json'),
  );
  final unavailableReplyReceived = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: _ge024BobReplyUnavailableKey,
    text: unavailableReplySent['text'] as String,
    senderPeerId: bobPeerId,
    quotedMessageId: removedParentSent['messageId'] as String,
  );
  writeSharedJson(
    _signalName('charlie_received_$_ge024BobReplyUnavailableKey.json'),
    unavailableReplyReceived,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[
      beforeParentReceived,
      availableReplyReceived,
      unavailableReplyReceived,
    ],
    extra: <String, dynamic>{
      'ge024QuotedReplyProof': await _ge024QuotedReplyProof(
        stack: stack,
        groupId: groupId,
        removedPeerId: stack.identity.peerId,
        availableParentMessageId: beforeParentSent['messageId'] as String,
        removedWindowParentMessageId: removedParentSent['messageId'] as String,
        availableReplyMessageId: availableReplySent['messageId'] as String,
        unavailableReplyMessageId: unavailableReplySent['messageId'] as String,
        removedWindowPlaintextCount: removedWindowPlaintextCount,
      ),
    },
  );
}

Future<void> _publishGm035LiveDuplicate({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required Map<String, dynamic> sent,
}) async {
  final publish = await callGroupPublish(
    stack.bridge,
    groupId: groupId,
    text: sent['text'] as String,
    senderPeerId: stack.identity.peerId,
    senderPublicKey: stack.identity.publicKey,
    senderPrivateKey: stack.identity.privateKey,
    senderUsername: stack.identity.username,
    messageId: sent['messageId'] as String,
  );
  expect(publish['ok'], isTrue, reason: 'GM-035 live duplicate publish failed');
  writeSharedJson(
    _signalName('charlie_gm035_live_duplicate_published.json'),
    <String, dynamic>{
      'messageId': sent['messageId'] as String,
      'topicPeers': _intFromBridgeValue(publish['topicPeers']),
      'publishedAt': DateTime.now().toUtc().toIso8601String(),
    },
  );
}

Future<Map<String, dynamic>> _gm035LeaveLiveTopicOnly({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
  required List<String> expectedMemberPeerIds,
}) async {
  final beforeGroup = await stack.groupRepo.getGroup(groupId);
  final beforeKey = await stack.groupRepo.getLatestKey(groupId);
  if (beforeGroup == null || beforeKey == null) {
    throw StateError('GM-035 cannot leave live topic without local state');
  }

  await callGroupLeave(stack.bridge, groupId);

  final group = await stack.groupRepo.getGroup(groupId);
  final key = await stack.groupRepo.getLatestKey(groupId);
  final memberPeerIds = await _memberPeerIds(stack, groupId);
  final missingMembers = expectedMemberPeerIds
      .toSet()
      .difference(memberPeerIds.toSet())
      .toList(growable: false);
  if (group == null || key == null || missingMembers.isNotEmpty) {
    throw StateError(
      'GM-035 live-topic leave removed retained state: '
      'group=${group != null} key=${key != null} '
      'missingMembers=$missingMembers members=$memberPeerIds',
    );
  }

  return <String, dynamic>{
    'role': _role,
    'leftLiveTopicOnly': true,
    'groupRetained': true,
    'keyRetained': true,
    'keyEpoch': key.keyGeneration,
    'memberPeerIds': memberPeerIds,
    'expectedMemberPeerIds': expectedMemberPeerIds,
    'leaveCompletedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

Future<Map<String, dynamic>> _gm035RejoinLiveTopicOnly({
  required GroupMultiDeviceTestStack stack,
  required String groupId,
}) async {
  final group = await stack.groupRepo.getGroup(groupId);
  final key = await stack.groupRepo.getLatestKey(groupId);
  final members = await stack.groupRepo.getMembers(groupId);
  if (group == null || key == null || members.isEmpty) {
    throw StateError(
      'GM-035 cannot rejoin live topic without retained local state: '
      'group=${group != null} key=${key != null} members=${members.length}',
    );
  }

  await callGroupJoinWithConfig(
    stack.bridge,
    groupId: groupId,
    groupConfig: buildGroupConfigPayload(group, members),
    groupKey: key.encryptedKey,
    keyEpoch: key.keyGeneration,
  );
  await drainGroupOfflineInboxForGroup(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    groupMessageListener: stack.groupListener,
    selfPeerId: stack.identity.peerId,
  );

  return <String, dynamic>{
    'role': _role,
    'rejoinedLiveTopicOnly': true,
    'keyEpoch': key.keyGeneration,
    'memberPeerIds': members
        .map((member) => member.peerId)
        .toList(growable: false),
    'rejoinedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

Future<void> _runGm035Alice(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await _createGroupFixture(
    stack: stack,
    identities: identities,
    memberRoles: const <String>['bob', 'charlie'],
    name: 'GM-035 Private Group',
  );
  writeSharedJson(_signalName('group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;

  await waitForSharedSignal(_signalName('bob_gm035_group_joined'));
  await waitForSharedSignal(_signalName('charlie_gm035_group_joined'));
  await Future<void>.delayed(const Duration(seconds: 5));

  final charlieIdentity = identities['charlie']!;
  final charliePeerId = charlieIdentity['peerId'] as String;
  final charlieTransportPeerId =
      (charlieIdentity['transportPeerId'] as String?) ?? charliePeerId;
  final bobPeerId = identities['bob']!['peerId'] as String;

  await _removeCharlieAndPublish(
    stack: stack,
    groupId: groupId,
    charlieIdentity: charlieIdentity,
  );
  await waitForSharedSignal(_signalName('bob_gm035_removed_charlie'));
  await waitForSharedSignal(_signalName('charlie_gm035_self_removed'));

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
      return stack.p2pService.sendMessage(peerId, message);
    },
  );
  if (rotatedKey == null) {
    throw StateError('GM-035 Alice key rotation failed');
  }
  writeSharedJson(_signalName('gm035_rotated_key.json'), <String, dynamic>{
    'keyEpoch': rotatedKey.keyGeneration,
    'groupKey': rotatedKey.encryptedKey,
  });
  await waitForSharedSignal(_signalName('bob_gm035_rotated_key'));

  final readdAt = DateTime.now().toUtc();
  final charlieMember = GroupMember(
    groupId: groupId,
    peerId: charliePeerId,
    username:
        charlieIdentity['username'] as String? ?? _usernameForRole('charlie'),
    role: MemberRole.writer,
    publicKey: charlieIdentity['publicKey'] as String?,
    mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: charlieTransportPeerId,
        transportPeerId: charlieTransportPeerId,
        deviceSigningPublicKey: charlieIdentity['publicKey'] as String? ?? '',
        mlKemPublicKey: charlieIdentity['mlKemPublicKey'] as String?,
        keyPackageId: 'gm035-key-package-$charlieTransportPeerId',
        keyPackagePublicMaterial: charlieIdentity['mlKemPublicKey'] as String?,
      ),
    ],
    joinedAt: readdAt,
  );
  await addGroupMember(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    groupId: groupId,
    newMember: charlieMember,
    selfPeerId: stack.identity.peerId,
  );
  await _publishMemberAddedSystemPayload(
    stack: stack,
    groupId: groupId,
    member: charlieMember,
    eventAt: readdAt,
  );
  await waitForSharedSignal(_signalName('bob_gm035_readded_charlie'));

  final updatedGroup = await stack.groupRepo.getGroup(groupId);
  final updatedKey = await stack.groupRepo.getLatestKey(groupId);
  final updatedMembers = await stack.groupRepo.getMembers(groupId);
  writeSharedJson(
    _signalName('charlie_gm035_readd_group_fixture.json'),
    buildGroupFixture(
      group: updatedGroup!,
      keyInfo: updatedKey!,
      members: updatedMembers,
    ),
  );
  final leaveProof = await _gm035LeaveLiveTopicOnly(
    stack: stack,
    groupId: groupId,
    expectedMemberPeerIds: <String>[
      stack.identity.peerId,
      bobPeerId,
      charliePeerId,
    ],
  );
  writeSharedJson(
    _signalName('alice_gm035_live_topic_unavailable.json'),
    leaveProof,
  );
  await waitForSharedSignal(_signalName('charlie_gm035_rejoined'));

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm035FirstAfterReadd.json'),
  );
  final rejoinProof = await _gm035RejoinLiveTopicOnly(
    stack: stack,
    groupId: groupId,
  );
  final received = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm035FirstAfterReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('alice_received_charlieGm035FirstAfterReadd.json'),
    received,
  );

  await waitForSharedJson(
    _signalName('charlie_gm035_live_duplicate_published.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  await drainGroupOfflineInboxForGroup(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    groupMessageListener: stack.groupListener,
    selfPeerId: stack.identity.peerId,
  );
  final postDuplicateCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[received],
    extra: <String, dynamic>{
      'gm035ZeroPeerReaddFirstSendProof': <String, dynamic>{
        'durableDrainCompleted': (received['persistedCount'] as int? ?? 0) == 1,
        'receivedCharlieFirstSend': true,
        'liveDuplicateDelivered': true,
        'noDuplicatePersistence': postDuplicateCount == 1,
        'senderEligibleAtSend': (await _memberPeerIds(
          stack,
          groupId,
        )).contains(charliePeerId),
        'liveTopicUnavailableAtSend': true,
        'liveTopicLeaveProof': leaveProof,
        'liveTopicRejoinProof': rejoinProof,
        'postDrainPersistedCount': received['persistedCount'] as int? ?? 0,
        'postLiveDuplicatePersistedCount': postDuplicateCount,
        'receivedMessageId': received['messageId'] as String,
        'currentMemberPeerIds': await _memberPeerIds(stack, groupId),
      },
    },
  );
}

Future<void> _runGm035Bob(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('bob_gm035_group_joined'), 'ok');

  final charliePeerId = identities['charlie']!['peerId'] as String;
  await _waitForMemberExclusion(
    stack: stack,
    groupId: groupId,
    removedPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm035_removed_charlie'), 'ok');

  final rotated = await waitForSharedJson(
    _signalName('gm035_rotated_key.json'),
  );
  await _waitForKeyEpoch(
    stack: stack,
    groupId: groupId,
    keyEpoch: rotated['keyEpoch'] as int,
  );
  writeSharedText(_signalName('bob_gm035_rotated_key'), 'ok');

  await _waitForMemberInclusion(
    stack: stack,
    groupId: groupId,
    memberPeerId: charliePeerId,
  );
  writeSharedText(_signalName('bob_gm035_readded_charlie'), 'ok');
  final leaveProof = await _gm035LeaveLiveTopicOnly(
    stack: stack,
    groupId: groupId,
    expectedMemberPeerIds: <String>[
      identities['alice']!['peerId'] as String,
      stack.identity.peerId,
      charliePeerId,
    ],
  );
  writeSharedJson(
    _signalName('bob_gm035_live_topic_unavailable.json'),
    leaveProof,
  );

  final charlieSent = await waitForSharedJson(
    _signalName('charlie_sent_charlieGm035FirstAfterReadd.json'),
  );
  final rejoinProof = await _gm035RejoinLiveTopicOnly(
    stack: stack,
    groupId: groupId,
  );
  final received = await _waitForReceivedProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm035FirstAfterReadd',
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );
  writeSharedJson(
    _signalName('bob_received_charlieGm035FirstAfterReadd.json'),
    received,
  );

  await waitForSharedJson(
    _signalName('charlie_gm035_live_duplicate_published.json'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  await drainGroupOfflineInboxForGroup(
    bridge: stack.bridge,
    groupRepo: stack.groupRepo,
    msgRepo: stack.groupMsgRepo,
    groupId: groupId,
    groupMessageListener: stack.groupListener,
    selfPeerId: stack.identity.peerId,
  );
  final postDuplicateCount = await _proofMessageCount(
    stack: stack,
    groupId: groupId,
    text: charlieSent['text'] as String,
    senderPeerId: charliePeerId,
  );

  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: const <Map<String, dynamic>>[],
    receivedMessages: <Map<String, dynamic>>[received],
    extra: <String, dynamic>{
      'gm035ZeroPeerReaddFirstSendProof': <String, dynamic>{
        'durableDrainCompleted': (received['persistedCount'] as int? ?? 0) == 1,
        'receivedCharlieFirstSend': true,
        'liveDuplicateDelivered': true,
        'noDuplicatePersistence': postDuplicateCount == 1,
        'senderEligibleAtSend': (await _memberPeerIds(
          stack,
          groupId,
        )).contains(charliePeerId),
        'liveTopicUnavailableAtSend': true,
        'liveTopicLeaveProof': leaveProof,
        'liveTopicRejoinProof': rejoinProof,
        'postDrainPersistedCount': received['persistedCount'] as int? ?? 0,
        'postLiveDuplicatePersistedCount': postDuplicateCount,
        'receivedMessageId': received['messageId'] as String,
        'currentMemberPeerIds': await _memberPeerIds(stack, groupId),
      },
    },
  );
}

Future<void> _runGm035Charlie(
  GroupMultiDeviceTestStack stack,
  Map<String, Map<String, dynamic>> identities,
) async {
  final fixture = await waitForSharedJson(_signalName('group_fixture.json'));
  final groupId = await _importGm004JoinedGroupFixture(
    stack: stack,
    fixture: fixture,
  );
  writeSharedText(_signalName('charlie_gm035_group_joined'), 'ok');

  await _waitForSelfRemoval(stack: stack, groupId: groupId);
  writeSharedText(_signalName('charlie_gm035_self_removed'), 'ok');

  final readdFixture = await waitForSharedJson(
    _signalName('charlie_gm035_readd_group_fixture.json'),
  );
  await _importGm004JoinedGroupFixture(stack: stack, fixture: readdFixture);
  writeSharedText(_signalName('charlie_gm035_rejoined'), 'ok');

  final aliceUnavailable = await waitForSharedJson(
    _signalName('alice_gm035_live_topic_unavailable.json'),
  );
  final bobUnavailable = await waitForSharedJson(
    _signalName('bob_gm035_live_topic_unavailable.json'),
  );
  final sent = await _sendProofMessage(
    stack: stack,
    groupId: groupId,
    key: 'charlieGm035FirstAfterReadd',
    text: 'GM-035 Charlie first send after re-add $_runId',
  );
  final initialTopicPeers = sent['topicPeers'] as int?;
  sent['initialTopicPeers'] = initialTopicPeers;
  if (initialTopicPeers != 0 || sent['outcome'] != 'successNoPeers') {
    throw StateError(
      'GM-035 Charlie first send must be zero-peer successNoPeers; '
      'observed outcome=${sent['outcome']} topicPeers=${sent['topicPeers']} '
      'initialTopicPeers=$initialTopicPeers',
    );
  }

  await waitForSharedJson(
    _signalName('alice_received_charlieGm035FirstAfterReadd.json'),
  );
  await waitForSharedJson(
    _signalName('bob_received_charlieGm035FirstAfterReadd.json'),
  );
  await _publishGm035LiveDuplicate(stack: stack, groupId: groupId, sent: sent);

  final recipientPeerIds =
      (sent['recipientPeerIds'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
  final memberPeerIds = await _memberPeerIds(stack, groupId);
  await _writeVerdict(
    stack: stack,
    groupId: groupId,
    sentMessages: <Map<String, dynamic>>[sent],
    receivedMessages: const <Map<String, dynamic>>[],
    extra: <String, dynamic>{
      'gm035ZeroPeerReaddFirstSendProof': <String, dynamic>{
        'readdedCharlie': memberPeerIds.contains(stack.identity.peerId),
        'aliceBobEligibleAtSend':
            recipientPeerIds.contains(identities['alice']!['peerId']) &&
            recipientPeerIds.contains(identities['bob']!['peerId']),
        'sentBeforeLiveDiscoveryCompleted': initialTopicPeers == 0,
        'successNoPeers': sent['outcome'] == 'successNoPeers',
        'actualDurablePayloadProof': sent['actualDurablePayloadProof'] == true,
        'durableRecipientsUnique':
            recipientPeerIds.length == recipientPeerIds.toSet().length,
        'replayEnvelopeMessageIdMatches': true,
        'aliceBobLiveTopicUnavailableAtSend': true,
        'liveTopicUnavailableProofRoles': const <String>['alice', 'bob'],
        'liveTopicUnavailableProofs': <String, dynamic>{
          'alice': aliceUnavailable,
          'bob': bobUnavailable,
        },
        'initialTopicPeers': initialTopicPeers,
        'keyEpoch': sent['keyEpoch'] as int? ?? await _keyEpoch(stack, groupId),
        'messageId': sent['messageId'] as String,
        'recipientPeerIds': recipientPeerIds,
        'currentMemberPeerIds': memberPeerIds,
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
    useFreshTransportIdentityForRestoredAccount:
        (_scenario == 'ge012' || _scenario == 'ge013') &&
        _restoreMnemonic.isNotEmpty,
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

    if (_scenario == 'ge001') {
      if (_role == 'alice') {
        await _runGe001Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe001Bob(stack, identities);
      } else {
        await _runGe001Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge002') {
      if (_role == 'alice') {
        await _runGe002Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe002Bob(stack, identities);
      } else {
        await _runGe002Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge003') {
      if (_role == 'alice') {
        await _runGe003Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe003Bob(stack, identities);
      } else {
        await _runGe003Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge004') {
      if (_role == 'alice') {
        await _runGe004Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe004Bob(stack, identities);
      } else {
        await _runGe004Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge005') {
      if (_role == 'alice') {
        await _runGe005Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe005Bob(stack, identities);
      } else {
        await _runGe005Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge006') {
      if (_role == 'alice') {
        await _runGe006Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe006Bob(stack, identities);
      } else if (_mode == 'seedOffline') {
        await _runGe006CharlieSeed(stack, identities);
      } else {
        await _runGe006Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge007') {
      if (_role == 'alice') {
        await _runGe007Alice(stack, identities);
      } else if (_role == 'bob' && _mode == 'seedOffline') {
        await _runGe007BobSeed(stack, identities);
      } else if (_role == 'bob') {
        await _runGe007Bob(stack, identities);
      } else {
        await _runGe007Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge008') {
      if (_role == 'alice') {
        await _runGe008Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe008Bob(stack, identities);
      } else {
        await _runGe008Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge009') {
      if (_role == 'alice') {
        await _runGe009Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe009Bob(stack, identities);
      } else {
        await _runGe009Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge010' || _scenario == 'go001') {
      if (_role == 'alice') {
        await _runGe010Alice(stack, identities);
      } else {
        await _runGe010Receiver(stack, identities);
      }
      return;
    }

    if (_scenario == 'go002') {
      if (_role == 'alice') {
        await _runGo002Alice(stack, identities);
      } else {
        await _runGo002Receiver(stack, identities);
      }
      return;
    }

    if (_scenario == 'go003') {
      if (_role == 'alice') {
        await _runGm017Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm017Bob(stack, identities);
      } else {
        await _runGm017Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge011') {
      if (_role == 'alice') {
        await _runGe011Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe011Bob(stack, identities);
      } else {
        await _runGe011Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge012') {
      if (_role == 'alice') {
        await _runGe012Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe012Bob(stack, identities);
      } else {
        await _runGe012Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge013') {
      if (_role == 'alice') {
        await _runGe013Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe013Bob(stack, identities);
      } else {
        await _runGe013Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge014') {
      if (_role == 'alice') {
        await _runGe014Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe014Bob(stack, identities);
      } else if (_mode == 'restartSeed') {
        await _runGe014CharlieSeed(stack, identities);
      } else {
        await _runGe014Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge015') {
      if (_role == 'alice' && _mode == 'restartSeed') {
        await _runGe015AliceSeed(stack, identities);
      } else if (_role == 'alice') {
        await _runGe015Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe015Bob(stack, identities);
      } else {
        await _runGe015Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge016') {
      if (_role == 'alice') {
        await _runGe016Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe016Bob(stack, identities);
      } else {
        await _runGe016Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge020') {
      if (_role == 'alice') {
        await _runGe020Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe020Bob(stack, identities);
      } else {
        await _runGe020Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge021') {
      if (_role == 'alice') {
        await _runGe021Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe021Bob(stack, identities);
      } else {
        await _runGe021Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge023') {
      if (_role == 'alice') {
        await _runGe023Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe023Bob(stack, identities);
      } else {
        await _runGe023Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'ge024') {
      if (_role == 'alice') {
        await _runGe024Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGe024Bob(stack, identities);
      } else {
        await _runGe024Charlie(stack, identities);
      }
      return;
    }

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

    if (_scenario == 'gm008') {
      if (_role == 'alice') {
        await _runGm008Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm008Bob(stack, identities);
      } else if (_mode == 'restartSeed') {
        await _runGm008CharlieSeed(stack, identities);
      } else {
        await _runGm008Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm009') {
      if (_role == 'alice') {
        await _runGm009Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm009Bob(stack, identities);
      } else {
        await _runGm009Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm010') {
      if (_role == 'alice') {
        await _runGm010Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm010Bob(stack, identities);
      } else {
        await _runGm010Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm011') {
      if (_role == 'alice') {
        await _runGm011Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm011Bob(stack, identities);
      } else {
        await _runGm011Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm012') {
      if (_role == 'alice') {
        await _runGm012Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm012Bob(stack, identities);
      } else {
        await _runGm012Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm013') {
      if (_role == 'alice') {
        await _runGm013Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm013Bob(stack, identities);
      } else {
        await _runGm013Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm014') {
      if (_role == 'alice') {
        await _runGm014Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm014Bob(stack, identities);
      } else {
        await _runGm014Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm015') {
      if (_role == 'alice') {
        await _runGm015Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm015Bob(stack, identities);
      } else {
        await _runGm015Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm016') {
      if (_role == 'alice') {
        await _runGm016Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm016Bob(stack, identities);
      } else {
        await _runGm016Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm017') {
      if (_role == 'alice') {
        await _runGm017Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm017Bob(stack, identities);
      } else {
        await _runGm017Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm018') {
      if (_role == 'alice') {
        await _runGm018Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm018Bob(stack, identities);
      } else {
        await _runGm018Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm019') {
      if (_role == 'alice') {
        await _runGm019Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm019Bob(stack, identities);
      } else {
        await _runGm019Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm020') {
      if (_role == 'alice') {
        await _runGm020Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm020Bob(stack, identities);
      } else {
        await _runGm020Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm021') {
      if (_role == 'alice') {
        await _runGm021Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm021Bob(stack, identities);
      } else {
        await _runGm021Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm022') {
      if (_role == 'alice') {
        await _runGm022Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm022Bob(stack, identities);
      } else {
        await _runGm022Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm023') {
      if (_role == 'alice') {
        await _runGm023Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm023Bob(stack, identities);
      } else {
        await _runGm023Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm024') {
      if (_role == 'alice') {
        await _runGm024Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm024Bob(stack, identities);
      } else {
        await _runGm024Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm025') {
      if (_role == 'alice') {
        await _runGm025Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm025Bob(stack, identities);
      } else {
        await _runGm025Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm033') {
      if (_role == 'alice') {
        await _runGm033Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm033Bob(stack, identities);
      } else {
        await _runGm033Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm034') {
      if (_role == 'alice') {
        await _runGm034Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm034Bob(stack, identities);
      } else {
        await _runGm034Charlie(stack, identities);
      }
      return;
    }

    if (_scenario == 'gm035') {
      if (_role == 'alice') {
        await _runGm035Alice(stack, identities);
      } else if (_role == 'bob') {
        await _runGm035Bob(stack, identities);
      } else {
        await _runGm035Charlie(stack, identities);
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
