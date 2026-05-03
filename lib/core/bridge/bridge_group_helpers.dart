import 'dart:async';
import 'dart:convert';

import '../utils/flow_event_emitter.dart';
import 'bridge.dart';

/// Thrown when a Go bridge command returns `{ "ok": false }`.
class BridgeCommandException implements Exception {
  final String command;
  final String errorCode;
  final String? errorMessage;
  BridgeCommandException(this.command, this.errorCode, [this.errorMessage]);
  @override
  String toString() =>
      'BridgeCommandException($command: $errorCode${errorMessage != null ? ' — $errorMessage' : ''})';
}

/// Calls the bridge to create a new group on the P2P network.
///
/// Returns a map with:
/// - On success: `{ "ok": true, "groupId": "...", "topicName": "..." }`
/// - On error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callGroupCreate(
  Bridge bridge, {
  required String name,
  required String type,
  required String creatorPeerId,
  required String creatorPublicKey,
  String? creatorMlKemPublicKey,
  String? description,
  Duration timeout = const Duration(seconds: 30),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_CREATE_REQUEST',
    details: {'name': name, 'type': type},
  );

  final request = {
    'cmd': 'group:create',
    'payload': {
      'name': name,
      'groupType': type,
      'creatorPeerId': creatorPeerId,
      'creatorPublicKey': creatorPublicKey,
      if (creatorMlKemPublicKey != null)
        'creatorMlKemPublicKey': creatorMlKemPublicKey,
      if (description != null) 'description': description,
    },
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_CREATE_RESPONSE',
      details: {'ok': response['ok']},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_CREATE_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to join an existing group.
Future<void> callGroupJoin(
  Bridge bridge, {
  required String groupId,
  required String topicName,
  Duration timeout = const Duration(seconds: 30),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_JOIN_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final request = {
    'cmd': 'group:join',
    'payload': {'groupId': groupId, 'topicName': topicName},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw BridgeCommandException(
        'group:join',
        response['errorCode']?.toString() ?? 'UNKNOWN',
        response['errorMessage']?.toString(),
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_JOIN_RESPONSE',
      details: {'ok': true},
    );
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_JOIN_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}

/// Calls the bridge to join an existing group with full config.
///
/// Sends the groupId, groupConfig, groupKey, and keyEpoch to the Go bridge's
/// `GroupJoinTopic` function. This is the correct payload format expected by Go.
Future<void> callGroupJoinWithConfig(
  Bridge bridge, {
  required String groupId,
  required Map<String, dynamic> groupConfig,
  required String groupKey,
  required int keyEpoch,
  Duration timeout = const Duration(seconds: 30),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_JOIN_CONFIG_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'keyEpoch': keyEpoch,
    },
  );

  final request = {
    'cmd': 'group:join',
    'payload': {
      'groupId': groupId,
      'groupConfig': groupConfig,
      'groupKey': groupKey,
      'keyEpoch': keyEpoch,
    },
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw BridgeCommandException(
        'group:join',
        response['errorCode']?.toString() ?? 'UNKNOWN',
        response['errorMessage']?.toString(),
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_JOIN_CONFIG_RESPONSE',
      details: {'ok': true},
    );
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_JOIN_CONFIG_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}

/// Calls the bridge to acknowledge that Flutter has finished any required
/// group topic rejoin after recovery.
Future<void> callGroupAcknowledgeRecovery(
  Bridge bridge, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_ACK_RECOVERY_REQUEST',
    details: {},
  );

  final request = {
    'cmd': 'group:acknowledgeRecovery',
    'payload': <String, dynamic>{},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw BridgeCommandException(
        'group:acknowledgeRecovery',
        response['errorCode']?.toString() ?? 'UNKNOWN',
        response['errorMessage']?.toString(),
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_ACK_RECOVERY_RESPONSE',
      details: {'ok': true},
    );
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_ACK_RECOVERY_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}

/// Calls the bridge to leave a group.
Future<void> callGroupLeave(
  Bridge bridge,
  String groupId, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_LEAVE_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final request = {
    'cmd': 'group:leave',
    'payload': {'groupId': groupId},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw BridgeCommandException(
        'group:leave',
        response['errorCode']?.toString() ?? 'UNKNOWN',
        response['errorMessage']?.toString(),
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_LEAVE_RESPONSE',
      details: {'ok': true},
    );
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_LEAVE_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}

/// Calls the bridge to publish a message to the group topic.
///
/// Go's GroupPublish handles encryption and signing internally.
/// It needs the sender's keys to sign the message.
///
/// Returns a map with:
/// - On success: `{ "ok": true, "messageId": "..." }`
/// - On error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callGroupPublish(
  Bridge bridge, {
  required String groupId,
  required String text,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  String senderUsername = '',
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderDevicePublicKey,
  String? senderKeyPackageId,
  String? messageId,
  String? quotedMessageId,
  List<Map<String, dynamic>>? media,
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_PUBLISH_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'textLength': text.length,
    },
  );

  final payload = <String, dynamic>{
    'groupId': groupId,
    'text': text,
    'senderPeerId': senderPeerId,
    'senderPublicKey': senderPublicKey,
    'senderPrivateKey': senderPrivateKey,
    'senderUsername': senderUsername,
  };
  if (senderDeviceId != null && senderDeviceId.isNotEmpty) {
    payload['senderDeviceId'] = senderDeviceId;
  }
  if (senderTransportPeerId != null && senderTransportPeerId.isNotEmpty) {
    payload['senderTransportPeerId'] = senderTransportPeerId;
  }
  if (senderDevicePublicKey != null && senderDevicePublicKey.isNotEmpty) {
    payload['senderDevicePublicKey'] = senderDevicePublicKey;
  }
  if (senderKeyPackageId != null && senderKeyPackageId.isNotEmpty) {
    payload['senderKeyPackageId'] = senderKeyPackageId;
  }
  if (messageId != null && messageId.isNotEmpty) {
    payload['messageId'] = messageId;
  }
  if (quotedMessageId != null && quotedMessageId.isNotEmpty) {
    payload['quotedMessageId'] = quotedMessageId;
  }
  if (media != null && media.isNotEmpty) {
    payload['media'] = media;
  }

  final request = {'cmd': 'group:publish', 'payload': payload};

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_PUBLISH_RESPONSE',
      details: {'ok': response['ok']},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_PUBLISH_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to publish a reaction to a group topic.
///
/// The reaction payload is encrypted and signed inside a v3 group_reaction
/// envelope by Go. All group members can react, including non-admins in
/// announcement groups.
Future<Map<String, dynamic>> callGroupPublishReaction(
  Bridge bridge, {
  required String groupId,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String reactionPayload,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderDevicePublicKey,
  String? senderKeyPackageId,
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_PUBLISH_REACTION_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final request = {
    'cmd': 'group:publishReaction',
    'payload': {
      'groupId': groupId,
      'senderPeerId': senderPeerId,
      'senderPublicKey': senderPublicKey,
      'senderPrivateKey': senderPrivateKey,
      'reactionPayload': reactionPayload,
      if (senderDeviceId != null && senderDeviceId.isNotEmpty)
        'senderDeviceId': senderDeviceId,
      if (senderTransportPeerId != null && senderTransportPeerId.isNotEmpty)
        'senderTransportPeerId': senderTransportPeerId,
      if (senderDevicePublicKey != null && senderDevicePublicKey.isNotEmpty)
        'senderDevicePublicKey': senderDevicePublicKey,
      if (senderKeyPackageId != null && senderKeyPackageId.isNotEmpty)
        'senderKeyPackageId': senderKeyPackageId,
    },
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_PUBLISH_REACTION_RESPONSE',
      details: {'ok': response['ok']},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_PUBLISH_REACTION_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to update group configuration.
///
/// The Go side expects `{ "groupId": "...", "groupConfig": { ... } }` where
/// groupConfig is the full [GroupConfig] struct (name, groupType, members, etc.).
Future<void> callGroupUpdateConfig(
  Bridge bridge, {
  required String groupId,
  required Map<String, dynamic> groupConfig,
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_UPDATE_CONFIG_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'memberCount': (groupConfig['members'] as List?)?.length ?? 0,
    },
  );

  final request = {
    'cmd': 'group:updateConfig',
    'payload': {'groupId': groupId, 'groupConfig': groupConfig},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw BridgeCommandException(
        'group:updateConfig',
        response['errorCode']?.toString() ?? 'UNKNOWN',
        response['errorMessage']?.toString(),
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_UPDATE_CONFIG_RESPONSE',
      details: {'ok': true},
    );
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_UPDATE_CONFIG_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}

/// Calls the bridge to rotate the group encryption key.
///
/// Returns a map with:
/// - On success: `{ "ok": true, "groupKey": "base64...", "keyEpoch": N }`
/// - On error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callGroupGenerateNextKey(
  Bridge bridge,
  String groupId, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_GENERATE_NEXT_KEY_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final request = {
    'cmd': 'group:generateNextKey',
    'payload': {'groupId': groupId},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_GENERATE_NEXT_KEY_RESPONSE',
      details: {'ok': response['ok']},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_GENERATE_NEXT_KEY_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to rotate the group encryption key.
///
/// Legacy helper retained for older flows. New Section 7 callers should use
/// [callGroupGenerateNextKey] followed by [callGroupUpdateKey].
///
/// Returns a map with:
/// - On success: `{ "ok": true, "groupKey": "base64...", "keyEpoch": N }`
/// - On error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callGroupRotateKey(
  Bridge bridge,
  String groupId, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_ROTATE_KEY_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final request = {
    'cmd': 'group:rotateKey',
    'payload': {'groupId': groupId},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_ROTATE_KEY_RESPONSE',
      details: {'ok': response['ok']},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_ROTATE_KEY_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to update the stored group key without generating a new one.
///
/// Used by non-admin members when receiving a key update via P2P.
/// This updates Go's `n.groupKeys[groupId]` so the topic validator accepts
/// messages signed with the new epoch.
Future<void> callGroupUpdateKey(
  Bridge bridge, {
  required String groupId,
  required String groupKey,
  required int keyEpoch,
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_UPDATE_KEY_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'keyEpoch': keyEpoch,
    },
  );

  final request = {
    'cmd': 'group:updateKey',
    'payload': {'groupId': groupId, 'groupKey': groupKey, 'keyEpoch': keyEpoch},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw BridgeCommandException(
        'group:updateKey',
        response['errorCode']?.toString() ?? 'UNKNOWN',
        response['errorMessage']?.toString(),
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_UPDATE_KEY_RESPONSE',
      details: {'ok': true},
    );
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_UPDATE_KEY_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}

/// Calls the bridge to store a message in the group inbox on the relay.
Future<void> callGroupInboxStore(
  Bridge bridge,
  String groupId,
  String message, {
  List<String>? recipientPeerIds,
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_INBOX_STORE_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final request = {
    'cmd': 'group:inboxStore',
    'payload': {
      'groupId': groupId,
      'message': message,
      if (recipientPeerIds != null && recipientPeerIds.isNotEmpty)
        'recipientPeerIds': recipientPeerIds,
    },
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_FL_BRIDGE_INBOX_STORE_RESPONSE',
        details: {
          'ok': false,
          'errorCode': response['errorCode'],
          'errorMessage': response['errorMessage'],
        },
      );
      throw BridgeCommandException(
        'group:inboxStore',
        response['errorCode']?.toString() ?? 'UNKNOWN',
        response['errorMessage']?.toString(),
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_INBOX_STORE_RESPONSE',
      details: {'ok': true},
    );
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_INBOX_STORE_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}

/// Calls the bridge to retrieve messages from the group inbox.
///
/// Returns a list of message maps from the relay inbox.
Future<List<Map<String, dynamic>>> callGroupInboxRetrieve(
  Bridge bridge,
  String groupId,
  int sinceTimestamp, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_INBOX_RETRIEVE_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'sinceTimestamp': sinceTimestamp,
    },
  );

  final request = {
    'cmd': 'group:inboxRetrieve',
    'payload': {'groupId': groupId, 'sinceTimestamp': sinceTimestamp},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_FL_BRIDGE_INBOX_RETRIEVE_RESPONSE',
        details: {
          'ok': false,
          'errorCode': response['errorCode'],
          'errorMessage': response['errorMessage'],
        },
      );
      throw BridgeCommandException(
        'group:inboxRetrieve',
        response['errorCode']?.toString() ?? 'UNKNOWN',
        response['errorMessage']?.toString(),
      );
    }

    final messages =
        (response['messages'] as List<dynamic>?)
            ?.map((m) => Map<String, dynamic>.from(m as Map))
            .toList() ??
        [];

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_INBOX_RETRIEVE_RESPONSE',
      details: {'ok': response['ok'], 'count': messages.length},
    );

    return messages;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_INBOX_RETRIEVE_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}

/// Result of a cursor-based group inbox retrieval.
class GroupInboxPage {
  final List<Map<String, dynamic>> messages;
  final String cursor;
  final List<GroupInboxHistoryGap> historyGaps;

  const GroupInboxPage({
    required this.messages,
    required this.cursor,
    this.historyGaps = const <GroupInboxHistoryGap>[],
  });
}

class GroupInboxHistoryGap {
  final String groupId;
  final String gapId;
  final String missingAfterMessageId;
  final String missingBeforeMessageId;
  final String expectedRangeHash;
  final String expectedHeadMessageId;
  final List<String> candidateSourcePeerIds;

  const GroupInboxHistoryGap({
    required this.groupId,
    required this.gapId,
    required this.missingAfterMessageId,
    required this.missingBeforeMessageId,
    required this.expectedRangeHash,
    required this.expectedHeadMessageId,
    required this.candidateSourcePeerIds,
  });

  factory GroupInboxHistoryGap.fromMap(Map<String, dynamic> map) {
    return GroupInboxHistoryGap(
      groupId: (map['groupId'] as String?)?.trim() ?? '',
      gapId: (map['gapId'] as String?)?.trim() ?? '',
      missingAfterMessageId:
          (map['missingAfterMessageId'] as String?)?.trim() ?? '',
      missingBeforeMessageId:
          (map['missingBeforeMessageId'] as String?)?.trim() ?? '',
      expectedRangeHash: (map['expectedRangeHash'] as String?)?.trim() ?? '',
      expectedHeadMessageId:
          (map['expectedHeadMessageId'] as String?)?.trim() ?? '',
      candidateSourcePeerIds:
          (map['candidateSourcePeerIds'] as List<dynamic>?)
              ?.whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
    );
  }

  Map<String, dynamic> toBridgePayload() {
    return {
      'groupId': groupId,
      'gapId': gapId,
      'missingAfterMessageId': missingAfterMessageId,
      'missingBeforeMessageId': missingBeforeMessageId,
      'expectedRangeHash': expectedRangeHash,
      'expectedHeadMessageId': expectedHeadMessageId,
      'candidateSourcePeerIds': candidateSourcePeerIds,
    };
  }
}

class GroupHistoryRepairRangeResult {
  final String groupId;
  final String gapId;
  final String sourcePeerId;
  final String rangeHash;
  final String headMessageId;
  final List<Map<String, dynamic>> messages;

  const GroupHistoryRepairRangeResult({
    required this.groupId,
    required this.gapId,
    required this.sourcePeerId,
    required this.rangeHash,
    required this.headMessageId,
    required this.messages,
  });
}

/// Calls the bridge to retrieve messages from the group inbox using
/// cursor-based pagination for exactly-once delivery.
///
/// Returns a [GroupInboxPage] with the messages and an opaque cursor
/// for fetching the next page. An empty cursor means no more pages.
Future<GroupInboxPage> callGroupInboxRetrieveWithCursor(
  Bridge bridge,
  String groupId,
  String cursor,
  int limit, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_INBOX_RETRIEVE_CURSOR_REQUEST',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'hasCursor': cursor.isNotEmpty,
      'limit': limit,
    },
  );

  final request = {
    'cmd': 'group:inboxRetrieveCursor',
    'payload': {'groupId': groupId, 'cursor': cursor, 'limit': limit},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_FL_BRIDGE_INBOX_RETRIEVE_CURSOR_RESPONSE',
        details: {
          'ok': false,
          'errorCode': response['errorCode'],
          'errorMessage': response['errorMessage'],
        },
      );
      throw BridgeCommandException(
        'group:inboxRetrieveCursor',
        response['errorCode']?.toString() ?? 'UNKNOWN',
        response['errorMessage']?.toString(),
      );
    }

    final messages =
        (response['messages'] as List<dynamic>?)
            ?.map((m) => Map<String, dynamic>.from(m as Map))
            .toList() ??
        [];
    final nextCursor = response['cursor'] as String? ?? '';
    final historyGaps = _parseGroupInboxHistoryGaps(response);

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_INBOX_RETRIEVE_CURSOR_RESPONSE',
      details: {
        'ok': response['ok'],
        'count': messages.length,
        'hasMore': nextCursor.isNotEmpty,
        'historyGapCount': historyGaps.length,
      },
    );

    return GroupInboxPage(
      messages: messages,
      cursor: nextCursor,
      historyGaps: historyGaps,
    );
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_INBOX_RETRIEVE_CURSOR_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}

List<GroupInboxHistoryGap> _parseGroupInboxHistoryGaps(
  Map<String, dynamic> response,
) {
  final rawList = response['historyGaps'];
  if (rawList is List) {
    return rawList
        .whereType<Map>()
        .map(
          (raw) => GroupInboxHistoryGap.fromMap(Map<String, dynamic>.from(raw)),
        )
        .where(_isValidHistoryGap)
        .toList(growable: false);
  }

  final rawSingle = response['historyGap'];
  if (rawSingle is Map) {
    final gap = GroupInboxHistoryGap.fromMap(
      Map<String, dynamic>.from(rawSingle),
    );
    return _isValidHistoryGap(gap)
        ? <GroupInboxHistoryGap>[gap]
        : const <GroupInboxHistoryGap>[];
  }

  return const <GroupInboxHistoryGap>[];
}

bool _isValidHistoryGap(GroupInboxHistoryGap gap) {
  return gap.groupId.isNotEmpty &&
      gap.gapId.isNotEmpty &&
      gap.missingAfterMessageId.isNotEmpty &&
      gap.missingBeforeMessageId.isNotEmpty &&
      gap.expectedRangeHash.isNotEmpty &&
      gap.expectedHeadMessageId.isNotEmpty &&
      gap.candidateSourcePeerIds.isNotEmpty;
}

Future<GroupHistoryRepairRangeResult> callGroupHistoryRepairRange(
  Bridge bridge, {
  required GroupInboxHistoryGap gap,
  required String sourcePeerId,
  int limit = 50,
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_HISTORY_REPAIR_RANGE_REQUEST',
    details: {
      'groupId': gap.groupId.length > 8
          ? gap.groupId.substring(0, 8)
          : gap.groupId,
      'gapId': gap.gapId.length > 8 ? gap.gapId.substring(0, 8) : gap.gapId,
      'sourcePeerId': sourcePeerId.length > 8
          ? sourcePeerId.substring(0, 8)
          : sourcePeerId,
      'limit': limit,
    },
  );

  final request = {
    'cmd': 'group:historyRepairRange',
    'payload': {
      ...gap.toBridgePayload(),
      'sourcePeerId': sourcePeerId,
      'limit': limit,
    },
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_FL_BRIDGE_HISTORY_REPAIR_RANGE_RESPONSE',
        details: {
          'ok': false,
          'errorCode': response['errorCode'],
          'errorMessage': response['errorMessage'],
        },
      );
      throw BridgeCommandException(
        'group:historyRepairRange',
        response['errorCode']?.toString() ?? 'UNKNOWN',
        response['errorMessage']?.toString(),
      );
    }

    final messages =
        (response['messages'] as List<dynamic>?)
            ?.map((m) => Map<String, dynamic>.from(m as Map))
            .toList() ??
        const <Map<String, dynamic>>[];
    final result = GroupHistoryRepairRangeResult(
      groupId: response['groupId'] as String? ?? gap.groupId,
      gapId: response['gapId'] as String? ?? gap.gapId,
      sourcePeerId: response['sourcePeerId'] as String? ?? sourcePeerId,
      rangeHash: response['rangeHash'] as String? ?? '',
      headMessageId: response['headMessageId'] as String? ?? '',
      messages: messages,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_HISTORY_REPAIR_RANGE_RESPONSE',
      details: {
        'ok': true,
        'count': result.messages.length,
        'hasRangeHash': result.rangeHash.isNotEmpty,
      },
    );

    return result;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_HISTORY_REPAIR_RANGE_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}

/// Calls the bridge to generate a symmetric group key.
///
/// Returns the base64-encoded key string on success.
Future<String> callGroupKeygen(
  Bridge bridge, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_KEYGEN_REQUEST',
    details: {},
  );

  final request = {'cmd': 'group.keygen', 'payload': <String, dynamic>{}};

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_KEYGEN_RESPONSE',
      details: {'ok': response['ok']},
    );

    return response['groupKey'] as String;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_KEYGEN_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}

/// Calls the bridge to encrypt plaintext with a symmetric group key.
///
/// Returns a map with:
/// - On success: `{ "ok": true, "ciphertext": "base64...", "nonce": "base64..." }`
/// - On error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callGroupEncrypt(
  Bridge bridge,
  String groupKey,
  String plaintext, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_ENCRYPT_REQUEST',
    details: {'plaintextLength': plaintext.length},
  );

  final request = {
    'cmd': 'group.encrypt',
    'payload': {'groupKey': groupKey, 'plaintext': plaintext},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_ENCRYPT_RESPONSE',
      details: {'ok': response['ok']},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_ENCRYPT_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to decrypt ciphertext with a symmetric group key.
///
/// Returns the decrypted plaintext string on success.
Future<String> callGroupDecrypt(
  Bridge bridge,
  String groupKey,
  String ciphertext,
  String nonce, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_FL_BRIDGE_DECRYPT_REQUEST',
    details: {},
  );

  final request = {
    'cmd': 'group.decrypt',
    'payload': {'groupKey': groupKey, 'ciphertext': ciphertext, 'nonce': nonce},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_DECRYPT_RESPONSE',
      details: {'ok': response['ok']},
    );

    return response['plaintext'] as String;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_FL_BRIDGE_DECRYPT_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    rethrow;
  }
}
