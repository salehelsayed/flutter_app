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
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
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
    'payload': {
      'groupId': groupId,
      'topicName': topicName,
    },
  };

  try {
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
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
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
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
    'payload': {
      'groupId': groupId,
    },
  };

  try {
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
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

  final request = {
    'cmd': 'group:publish',
    'payload': {
      'groupId': groupId,
      'text': text,
      'senderPeerId': senderPeerId,
      'senderPublicKey': senderPublicKey,
      'senderPrivateKey': senderPrivateKey,
      'senderUsername': senderUsername,
    },
  };

  try {
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
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
    'payload': {
      'groupId': groupId,
      'groupConfig': groupConfig,
    },
  };

  try {
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
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
    'payload': {
      'groupId': groupId,
    },
  };

  try {
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
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
    'payload': {
      'groupId': groupId,
      'groupKey': groupKey,
      'keyEpoch': keyEpoch,
    },
  };

  try {
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
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
    },
  };

  try {
    await bridge.send(jsonEncode(request)).timeout(timeout);

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
    'payload': {
      'groupId': groupId,
      'sinceTimestamp': sinceTimestamp,
    },
  };

  try {
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    final messages = (response['messages'] as List<dynamic>?)
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
    return [];
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

  final request = {
    'cmd': 'group.keygen',
    'payload': <String, dynamic>{},
  };

  try {
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
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
    'payload': {
      'key': groupKey,
      'plaintext': plaintext,
    },
  };

  try {
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
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
    'payload': {
      'key': groupKey,
      'ciphertext': ciphertext,
      'nonce': nonce,
    },
  };

  try {
    final responseJson =
        await bridge.send(jsonEncode(request)).timeout(timeout);
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
